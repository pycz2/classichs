use classichs_server::storage::{Storage, S3};
use classichs_server::{auth, db, packs, App, Timers};
use std::net::SocketAddr;
use std::path::PathBuf;

const USAGE: &str = "usage:
  classichs-server [--listen 127.0.0.1:7377] [--db classichs.db] [--trust-proxy]
                   [--packs-dir <dir>] [--store-dir store]
                   [--s3-bucket <name> --s3-endpoint <url> --s3-region <r>
                    --s3-access-key <key> --s3-secret-key <secret>]
  classichs-server admin <name> [--db classichs.db]

Every game runs in the server with the built-in rules engine (classichs-engine);
nothing else is needed.

Game packs are stored in S3 when a bucket is given (flags, or the environment:
S3_BUCKET, S3_ENDPOINT, S3_REGION, S3_ACCESS_KEY, S3_SECRET_KEY), else in --store-dir.
Bundled packs (*.cardpack in --packs-dir, default: packs/ next to the binary) are
installed as server packs at start, each once.";

fn main() {
    tracing_subscriber::fmt()
        .with_env_filter(tracing_subscriber::EnvFilter::try_from_default_env().unwrap_or_else(|_| "info".into()))
        .init();
    let args: Vec<String> = std::env::args().skip(1).collect();
    let mut listen = "127.0.0.1:7377".to_string();
    let mut db_path = "classichs.db".to_string();
    let mut trust_proxy = false;
    let mut admin: Option<String> = None;
    let env = |k: &str| std::env::var(k).unwrap_or_default();
    let mut s3 = S3 {
        endpoint: env("S3_ENDPOINT"),
        region: env("S3_REGION"),
        bucket: env("S3_BUCKET"),
        access_key: env("S3_ACCESS_KEY"),
        secret_key: env("S3_SECRET_KEY"),
    };
    let mut store_dir = "store".to_string();
    let mut packs_dir: Option<PathBuf> = None;
    let mut it = args.into_iter();
    while let Some(a) = it.next() {
        let mut val = |name: &str| it.next().unwrap_or_else(|| die(&format!("{name} needs a value")));
        match a.as_str() {
            "--listen" => listen = val("--listen"),
            "--db" => db_path = val("--db"),
            "--trust-proxy" => trust_proxy = true,
            "--store-dir" => store_dir = val("--store-dir"),
            "--packs-dir" => packs_dir = Some(val("--packs-dir").into()),
            "--s3-bucket" => s3.bucket = val("--s3-bucket"),
            "--s3-endpoint" => s3.endpoint = val("--s3-endpoint"),
            "--s3-region" => s3.region = val("--s3-region"),
            "--s3-access-key" => s3.access_key = val("--s3-access-key"),
            "--s3-secret-key" => s3.secret_key = val("--s3-secret-key"),
            "admin" if admin.is_none() => admin = Some(val("admin")),
            "-h" | "--help" => {
                println!("{USAGE}");
                return;
            }
            other => die(&format!("unknown argument {other}")),
        }
    }
    let rt = tokio::runtime::Runtime::new().expect("tokio runtime");
    let db = rt.block_on(db::open(&db_path)).unwrap_or_else(|e| die(&format!("cannot open the database {db_path}: {e}")));
    if let Some(name) = admin {
        return rt.block_on(make_admin(db, name));
    }
    let addr: SocketAddr = listen.parse().unwrap_or_else(|_| die(&format!("bad --listen address {listen}")));
    let store = if s3.bucket.is_empty() { Storage::dir(store_dir.as_ref()) } else { Storage::s3(&s3) };
    let store = store.unwrap_or_else(|e| die(&format!("cannot open the pack storage: {e}")));
    let packs_dir = packs_dir.unwrap_or_else(|| {
        std::env::current_exe().ok().and_then(|p| Some(p.parent()?.join("packs"))).unwrap_or_else(|| "packs".into())
    });
    rt.block_on(async move {
        tracing::info!("rules engine {} (cards {})", classichs_engine::api::VERSION, classichs_engine::card_db::data_hash());
        tracing::info!("pack storage: {}; bundled packs: {}", store.what, packs_dir.display());
        let app = App::new(db, trust_proxy, Timers::default(), store);
        let n = packs::import_bundled(&app, &packs_dir).await;
        if n > 0 {
            tracing::info!("{n} bundled pack(s) installed");
        }
        classichs_server::spawn_background(app.clone());
        let listener = tokio::net::TcpListener::bind(addr).await.unwrap_or_else(|e| die(&format!("cannot listen on {addr}: {e}")));
        println!("classichs-server listening on ws://{addr} (admin panel: http://{addr}/admin, database: {db_path})");
        axum::serve(listener, classichs_server::router(app).into_make_service_with_connect_info::<SocketAddr>())
            .await
            .unwrap_or_else(|e| die(&format!("server error: {e}")));
    });
}

async fn make_admin(db: db::Db, name: String) {
    if !auth::valid_user(&name) {
        die("a name is 3 to 20 letters, digits or _");
    }
    let pw = rpassword::prompt_password(format!("Password for {name}: ")).unwrap_or_else(|e| die(&e.to_string()));
    if !auth::valid_password(&pw) {
        die("a password is 8 to 128 characters");
    }
    let again = rpassword::prompt_password("Again: ").unwrap_or_else(|e| die(&e.to_string()));
    if pw != again {
        die("the passwords differ");
    }
    let hash = auth::hash_password(&pw);
    match db::make_superuser(&db, &name, &hash).await {
        Ok(true) => println!("Superuser {name} created."),
        Ok(false) => println!("{name} is the superuser now; the password was reset."),
        Err(e) => die(&format!("database error: {e}")),
    }
}

fn die(msg: &str) -> ! {
    eprintln!("classichs-server: {msg}\n\n{USAGE}");
    std::process::exit(2);
}
