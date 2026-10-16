use classichs_server::storage::{Storage, S3};
use classichs_server::{auth, db, packs, App};
use std::net::SocketAddr;
use std::path::PathBuf;

const USAGE: &str = "usage:
  classichs-server [--listen 127.0.0.1:7377] [--db classichs.db] [--trust-proxy]
                   [--packs-dir <dir>] [--default-pack neon] [--store-dir store]
                   [--s3-bucket <name> --s3-endpoint <url> --s3-region <r>
                    --s3-access-key <key> --s3-secret-key <secret>]
  classichs-server admin <name> [--db classichs.db]

Every game runs in the server with the built-in rules engine (classichs-engine);
nothing else is needed.

Game packs are stored in S3 when a bucket is given (flags, or the environment:
S3_BUCKET, S3_ENDPOINT, S3_REGION, S3_ACCESS_KEY, S3_SECRET_KEY), else in --store-dir.
Bundled packs (*.cardpack in --packs-dir; default: the first of packs/ next to the binary,\n./packs, ../packs or a packs/ folder above the binary that has a .cardpack) are
installed as server packs at start, each once. Games without a pack are played in the
default pack (the admin panel sets it); until one is set, the newest enabled server
pack with the manifest id --default-pack becomes it, else the built-in Classic rules.";

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
    let mut default_pack = "neon".to_string();
    let mut it = args.into_iter();
    while let Some(a) = it.next() {
        let mut val = |name: &str| it.next().unwrap_or_else(|| die(&format!("{name} needs a value")));
        match a.as_str() {
            "--listen" => listen = val("--listen"),
            "--db" => db_path = val("--db"),
            "--trust-proxy" => trust_proxy = true,
            "--store-dir" => store_dir = val("--store-dir"),
            "--packs-dir" => packs_dir = Some(val("--packs-dir").into()),
            "--default-pack" => default_pack = val("--default-pack"),
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
        let exe = std::env::current_exe().ok();
        let cwd = std::env::current_dir().unwrap_or_else(|_| ".".into());
        find_packs_dir(exe.as_deref(), &cwd).unwrap_or_else(|| {
            tracing::warn!(
                "no game packs found (no *.cardpack in packs/ next to the binary, in ./packs, ../packs or a packs/ \
                 folder above the binary): run tools/build_packs.sh in the project, or pass --packs-dir"
            );
            exe.as_deref().and_then(|p| Some(p.parent()?.join("packs"))).unwrap_or_else(|| "packs".into())
        })
    });
    rt.block_on(async move {
        tracing::info!("rules engine {} (cards {})", classichs_engine::api::VERSION, classichs_engine::card_db::data_hash());
        tracing::info!("pack storage: {}; bundled packs: {}", store.what, packs_dir.display());
        let app = App::new(db, trust_proxy, None, store);
        let n = packs::migrate_hashes(&app).await;
        if n > 0 {
            tracing::info!("{n} pack(s) moved to the hashes of docs/packs/format.md");
        }
        let n = packs::import_bundled(&app, &packs_dir).await;
        if n > 0 {
            tracing::info!("{n} bundled pack(s) installed");
        }
        match packs::set_default(&app, None, &default_pack).await {
            Ok(Some(p)) => tracing::info!("default game: {}", packs::label(&p)),
            Ok(None) => {}
            Err(e) => tracing::error!("default game: {e}"),
        }
        let d = packs::playable(&app, None, None).await.map(|r| packs::short_name(&r.0)).unwrap_or_else(|e| e.1);
        tracing::info!("games without a pack: {d}");
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


/// The bundled packs folder when --packs-dir is not given: the first of packs/ next to the
/// binary, ./packs, ../packs, or a packs/ folder in a directory above the binary (e.g. the
/// project's packs/ for server/target/release/classichs-server) that holds a *.cardpack.
fn find_packs_dir(exe: Option<&std::path::Path>, cwd: &std::path::Path) -> Option<PathBuf> {
    let has_pack = |d: &std::path::Path| {
        std::fs::read_dir(d).is_ok_and(|r| r.flatten().any(|e| e.path().extension().is_some_and(|x| x == "cardpack")))
    };
    let mut tries: Vec<PathBuf> = Vec::new();
    if let Some(bin) = exe.and_then(|p| p.parent()) {
        tries.push(bin.join("packs"));
    }
    tries.push(cwd.join("packs"));
    tries.push(cwd.join("..").join("packs"));
    if let Some(bin) = exe.and_then(|p| p.parent()) {
        tries.extend(bin.ancestors().skip(1).take(6).map(|a| a.join("packs")));
    }
    tries.into_iter().find(|d| has_pack(d))
}

#[cfg(test)]
mod tests {
    use super::find_packs_dir;

    #[test]
    fn packs_dir_found_above_the_binary_and_next_to_the_working_dir() {
        let t = std::env::temp_dir().join(format!("chs_packs_{}", std::process::id()));
        let bin = t.join("server/target/release");
        std::fs::create_dir_all(&bin).unwrap();
        std::fs::create_dir_all(t.join("packs")).unwrap();
        let exe = bin.join("classichs-server");
        assert_eq!(find_packs_dir(Some(&exe), &t.join("server")), None, "no pack yet");
        std::fs::write(t.join("packs/neon.cardpack"), b"x").unwrap();
        assert_eq!(find_packs_dir(Some(&exe), &t.join("server")), Some(t.join("server").join("..").join("packs")));
        assert_eq!(find_packs_dir(Some(&exe), &bin), Some(t.join("packs")), "found above the binary");
        std::fs::create_dir_all(bin.join("packs")).unwrap();
        std::fs::write(bin.join("packs/x.cardpack"), b"x").unwrap();
        assert_eq!(find_packs_dir(Some(&exe), &t), Some(bin.join("packs")), "next to the binary wins");
        std::fs::remove_dir_all(&t).unwrap();
    }
}
