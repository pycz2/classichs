//! Where pack files live: an S3-compatible bucket or a local directory (the default), both
//! through `object_store`. Keys are content hashes, so a file never changes once written.

use futures_util::stream::BoxStream;
use object_store::aws::AmazonS3Builder;
use object_store::buffered::BufWriter;
use object_store::local::LocalFileSystem;
use object_store::path::Path as Key;
use object_store::{ObjectStore, ObjectStoreExt};
use std::sync::Arc;
use tokio::io::AsyncWriteExt;

pub use object_store::Error;

/// S3 settings (path-style URLs, so any S3-compatible store works).
#[derive(Clone, Debug, Default)]
pub struct S3 {
    /// e.g. http://seaweedfs:8333; empty = AWS itself.
    pub endpoint: String,
    pub region: String,
    pub bucket: String,
    pub access_key: String,
    pub secret_key: String,
}

#[derive(Clone)]
pub struct Storage {
    store: Arc<dyn ObjectStore>,
    /// For logs and the admin panel: "s3 http://…/bucket" or "dir /path".
    pub what: String,
}

/// The object's key: `<content_hash>.cardpack`.
pub fn key(content_hash: &str) -> Key {
    Key::from(format!("{content_hash}.cardpack"))
}

impl Storage {
    /// A local directory (created if missing).
    pub fn dir(path: &std::path::Path) -> Result<Storage, String> {
        std::fs::create_dir_all(path).map_err(|e| format!("{}: {e}", path.display()))?;
        let abs = path.canonicalize().map_err(|e| format!("{}: {e}", path.display()))?;
        let fs = LocalFileSystem::new_with_prefix(&abs).map_err(|e| e.to_string())?;
        Ok(Storage { store: Arc::new(fs), what: format!("dir {}", abs.display()) })
    }

    pub fn s3(c: &S3) -> Result<Storage, String> {
        let mut b = AmazonS3Builder::new()
            .with_bucket_name(&c.bucket)
            .with_region(if c.region.is_empty() { "us-east-1" } else { &c.region })
            .with_access_key_id(&c.access_key)
            .with_secret_access_key(&c.secret_key)
            .with_virtual_hosted_style_request(false);
        if !c.endpoint.is_empty() {
            b = b.with_endpoint(&c.endpoint).with_allow_http(c.endpoint.starts_with("http://"));
        }
        let s3 = b.build().map_err(|e| e.to_string())?;
        let at = if c.endpoint.is_empty() { "aws".into() } else { c.endpoint.trim_end_matches('/').to_string() };
        Ok(Storage { store: Arc::new(s3), what: format!("s3 {at}/{}", c.bucket) })
    }

    /// Copies a local file in (multipart when large).
    pub async fn put_file(&self, content_hash: &str, file: &std::path::Path) -> Result<(), Error> {
        let mut src = tokio::fs::File::open(file).await.map_err(|e| Error::Generic { store: "file", source: Box::new(e) })?;
        let mut w = BufWriter::new(self.store.clone(), key(content_hash));
        let r = async {
            tokio::io::copy(&mut src, &mut w).await?;
            w.shutdown().await
        }
        .await;
        if let Err(e) = r {
            let _ = w.abort().await;
            return Err(Error::Generic { store: "upload", source: Box::new(e) });
        }
        Ok(())
    }

    pub async fn exists(&self, content_hash: &str) -> Result<bool, Error> {
        match self.store.head(&key(content_hash)).await {
            Ok(_) => Ok(true),
            Err(Error::NotFound { .. }) => Ok(false),
            Err(e) => Err(e),
        }
    }

    /// The file as a stream of chunks, with its size.
    pub async fn get(&self, content_hash: &str) -> Result<(u64, BoxStream<'static, Result<axum::body::Bytes, Error>>), Error> {
        let r = self.store.get(&key(content_hash)).await?;
        Ok((r.meta.size, r.into_stream()))
    }

    /// Gone already is fine.
    pub async fn delete(&self, content_hash: &str) -> Result<(), Error> {
        match self.store.delete(&key(content_hash)).await {
            Err(Error::NotFound { .. }) => Ok(()),
            r => r,
        }
    }
}
