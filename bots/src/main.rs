//! classichs-bots: bots that play Classic on a Classic HS game server, with a local admin page.
//!
//!   classichs-bots [--server wss://hs.borovilov.xyz] [--ladder 6] [--arena 3] [--admin 127.0.0.1:8098]
//!                  [--prefix Bot] [--state-dir bots/state] [--root .] [--think-ms 1200] [--pause 5-15]
//!
//! Ladder bots play ranked and casual games in turn with a random deck of bots/decks; Arena bots draft
//! and play Arena runs one after another. Accounts are registered on the first run and kept (with their
//! tokens) in <state-dir>/accounts.json.

use classichs_bots::cards::Library;
use classichs_bots::runtime::{self, Config, Kind};
use classichs_bots::status::{self, BotStatus, Shared};
use classichs_bots::admin;
use std::path::PathBuf;
use std::sync::{Arc, Mutex};
use std::time::Duration;

fn die(msg: &str) -> ! {
    eprintln!("classichs-bots: {msg}");
    std::process::exit(2)
}

#[tokio::main]
async fn main() {
    tracing_subscriber::fmt().with_env_filter(tracing_subscriber::EnvFilter::try_from_default_env().unwrap_or_else(|_| "info".into())).init();
    let mut server = "wss://hs.borovilov.xyz".to_string();
    let (mut ladder, mut arena) = (6usize, 3usize);
    let mut admin_addr = "127.0.0.1:8098".to_string();
    let mut prefix = "Bot".to_string();
    let mut root: Option<PathBuf> = None;
    let mut state_dir: Option<PathBuf> = None;
    let mut think = 1200u64;
    let mut pause = (5u64, 15u64);
    let mut args = std::env::args().skip(1);
    while let Some(a) = args.next() {
        let mut val = || args.next().unwrap_or_else(|| die(&format!("{a} needs a value")));
        match a.as_str() {
            "--server" => server = val(),
            "--ladder" => ladder = val().parse().unwrap_or_else(|_| die("--ladder: a number")),
            "--arena" => arena = val().parse().unwrap_or_else(|_| die("--arena: a number")),
            "--admin" => admin_addr = val(),
            "--prefix" => prefix = val(),
            "--root" => root = Some(PathBuf::from(val())),
            "--state-dir" => state_dir = Some(PathBuf::from(val())),
            "--think-ms" => think = val().parse().unwrap_or_else(|_| die("--think-ms: a number")),
            "--pause" => {
                let v = val();
                let (a, b) = v.split_once('-').unwrap_or_else(|| die("--pause: from-to seconds, e.g. 5-15"));
                pause = (a.parse().unwrap_or_else(|_| die("--pause")), b.parse().unwrap_or_else(|_| die("--pause")));
            }
            "-h" | "--help" => {
                println!("{}", include_str!("main.rs").lines().take_while(|l| l.starts_with("//!")).map(|l| l.trim_start_matches("//!")).collect::<Vec<_>>().join("\n"));
                return;
            }
            _ => die(&format!("unknown argument {a} (see --help)")),
        }
    }
    if !admin_addr.starts_with("127.0.0.1:") && !admin_addr.starts_with("localhost:") && !admin_addr.starts_with("[::1]:") {
        die("--admin must be a local address (127.0.0.1:PORT): the page has no login");
    }
    // the repository: given, or the current directory or its parent (run from bots/)
    let root = root.unwrap_or_else(|| {
        let cwd = std::env::current_dir().unwrap_or_default();
        [cwd.clone(), cwd.join("..")].into_iter().find(|p| p.join("data/cards.json").is_file()).unwrap_or(cwd)
    });
    let lib = Arc::new(Library::load(&root).unwrap_or_else(|e| die(&e)));
    let state_dir = state_dir.unwrap_or_else(|| root.join("bots/state"));
    let cfg = Config { server: server.clone(), state_dir, think: Duration::from_millis(think), pause, pack_id: "classic-2014".into() };
    let mut list = vec![];
    for n in 1..=ladder {
        list.push((format!("{prefix}_Ladder_{n}"), Kind::Ladder));
    }
    for n in 1..=arena {
        list.push((format!("{prefix}_Arena_{n}"), Kind::Arena));
    }
    let sh = Shared {
        bots: Arc::new(Mutex::new(
            list.iter()
                .map(|(name, kind)| BotStatus {
                    name: name.clone(),
                    kind: if *kind == Kind::Arena { "arena" } else { "ladder" }.into(),
                    state: "старт".into(),
                    since: status::now(),
                    ..Default::default()
                })
                .collect(),
        )),
        started: status::now(),
        server: server.clone(),
    };
    println!("classichs-bots: {} bots on {server}, {} decks; admin page http://{admin_addr}/", list.len(), lib.decks.len());
    for (i, (name, kind)) in list.into_iter().enumerate() {
        let (cfg, lib, sh) = (cfg.clone(), lib.clone(), sh.clone());
        tokio::spawn(async move {
            // (logins spread out: the server allows 10 a minute per address)
            tokio::time::sleep(Duration::from_millis(1500 * i as u64)).await;
            runtime::run(cfg, lib, sh, i, name, kind).await
        });
    }
    if let Err(e) = admin::serve(&admin_addr, sh).await {
        die(&e);
    }
}
