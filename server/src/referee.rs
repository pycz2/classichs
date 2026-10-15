//! The referee: the game itself without a window checks every game with the real
//! rules engine (net/referee.gd). JSON lines over a localhost TCP socket: the
//! server listens on 127.0.0.1:0 and starts `<command> <port>`; the referee connects.

use serde_json::{json, Value};
use std::collections::HashMap;
use std::future::Future;
use std::pin::Pin;
use std::process::Stdio;
use std::sync::Mutex;
use std::time::Duration;
use tokio::io::{AsyncBufReadExt, AsyncWriteExt, BufReader};
use tokio::net::tcp::{OwnedReadHalf, OwnedWriteHalf};
use tokio::net::TcpListener;
use tokio::process::{Child, Command};

pub type RefFuture<'a> = Pin<Box<dyn Future<Output = Result<Value, String>> + Send + 'a>>;

/// One request → one reply. Err = the referee itself failed (not the move).
pub trait Referee: Send + Sync {
    fn call(&self, req: Value) -> RefFuture<'_>;
}

const CONNECT_TIMEOUT: Duration = Duration::from_secs(20);
const REPLY_TIMEOUT: Duration = Duration::from_secs(10);

// ponytail: one request at a time over one referee (~3 ms an action, so a few hundred
// actions a second); a pool of referees keyed by game id if that is ever too few.
pub struct ProcessReferee {
    cmd: Vec<String>,
    conn: tokio::sync::Mutex<Option<Conn>>,
    /// Game id → the referee process (epoch) that knows it.
    games: Mutex<HashMap<String, u64>>,
    epoch: Mutex<u64>,
}

struct Conn {
    _child: Child,
    reader: BufReader<OwnedReadHalf>,
    writer: OwnedWriteHalf,
    epoch: u64,
}

impl ProcessReferee {
    pub fn new(cmd: &str) -> Self {
        ProcessReferee {
            cmd: split_command(cmd),
            conn: tokio::sync::Mutex::new(None),
            games: Mutex::new(HashMap::new()),
            epoch: Mutex::new(0),
        }
    }

    async fn spawn(&self) -> Result<Conn, String> {
        let (prog, args) = self.cmd.split_first().ok_or("empty referee command")?;
        let listener = TcpListener::bind("127.0.0.1:0").await.map_err(|e| e.to_string())?;
        let port = listener.local_addr().map_err(|e| e.to_string())?.port();
        let mut child = Command::new(prog)
            .args(args)
            .arg(port.to_string())
            .stdin(Stdio::null())
            .stdout(Stdio::null())
            .kill_on_drop(true)
            .spawn()
            .map_err(|e| format!("cannot start the referee `{}`: {e}", self.cmd.join(" ")))?;
        let accepted = tokio::select! {
            r = tokio::time::timeout(CONNECT_TIMEOUT, listener.accept()) => r,
            _ = child.wait() => return Err(format!("the referee `{}` exited before connecting", self.cmd.join(" "))),
        };
        let (sock, _) = accepted
            .map_err(|_| format!("the referee `{}` did not connect within 20 s", self.cmd.join(" ")))?
            .map_err(|e| e.to_string())?;
        let (r, w) = sock.into_split();
        let mut epoch = self.epoch.lock().unwrap();
        *epoch += 1;
        tracing::info!("referee started (port {port})");
        Ok(Conn { _child: child, reader: BufReader::new(r), writer: w, epoch: *epoch })
    }

    async fn request(&self, req: Value) -> Result<Value, String> {
        let mut guard = self.conn.lock().await;
        if guard.is_none() {
            *guard = Some(self.spawn().await?);
        }
        let conn = guard.as_mut().unwrap();
        let op = req["op"].as_str().unwrap_or("");
        let game = req["game"].as_str().unwrap_or("").to_string();
        if matches!(op, "act" | "drop") && self.games.lock().unwrap().get(&game) != Some(&conn.epoch) {
            // The referee that knew this game is gone: the game cannot be checked any more.
            return if op == "drop" { Ok(json!({"ok": true})) } else { Err("the referee restarted".into()) };
        }
        let io = async {
            let mut line = serde_json::to_string(&req).map_err(|e| e.to_string())?;
            line.push('\n');
            conn.writer.write_all(line.as_bytes()).await.map_err(|e| e.to_string())?;
            let mut reply = String::new();
            if conn.reader.read_line(&mut reply).await.map_err(|e| e.to_string())? == 0 {
                return Err("the referee closed the connection".to_string());
            }
            serde_json::from_str::<Value>(&reply).map_err(|e| format!("bad referee reply: {e}"))
        };
        match tokio::time::timeout(REPLY_TIMEOUT, io).await {
            Ok(Ok(v)) if v.is_object() => {
                let mut games = self.games.lock().unwrap();
                match op {
                    "new" if v["ok"] == true => {
                        games.insert(game, conn.epoch);
                    }
                    "drop" => {
                        games.remove(&game);
                    }
                    _ => {}
                }
                Ok(v)
            }
            other => {
                *guard = None; // kills the process; the next request starts a new one
                let why = match other {
                    Ok(Err(e)) => e,
                    Err(_) => "the referee did not answer within 10 s".into(),
                    Ok(Ok(_)) => "the referee's reply is not an object".into(),
                };
                tracing::error!("referee: {why}");
                Err(why)
            }
        }
    }
}

impl Referee for ProcessReferee {
    fn call(&self, req: Value) -> RefFuture<'_> {
        Box::pin(self.request(req))
    }
}

/// A stand-in for tests: any action with a "type" is legal except type "illegal";
/// the hash after n actions is "h<n>"; a concede ends the game.
#[derive(Default)]
pub struct FakeReferee {
    games: Mutex<HashMap<String, u64>>,
}

impl FakeReferee {
    pub fn answer(&self, req: &Value) -> Value {
        let game = req["game"].as_str().unwrap_or("").to_string();
        let mut games = self.games.lock().unwrap();
        match req["op"].as_str().unwrap_or("") {
            "ping" => json!({"ok": true, "version": "fake"}),
            "new" => {
                games.insert(game.clone(), 0);
                json!({"ok": true, "game": game, "hash": "h0", "over": false, "winner": -1, "turn": 0, "current": 0})
            }
            "act" => {
                let Some(n) = games.get_mut(&game) else { return json!({"ok": false, "error": "no such game"}) };
                let a = &req["action"];
                if a["type"] == "illegal" || !a["type"].is_string() {
                    return json!({"ok": false, "game": game, "error": "illegal"});
                }
                *n += 1;
                let over = a["type"] == "concede";
                let winner = if over { 1 - a["player"].as_i64().unwrap_or(0) } else { -1 };
                json!({"ok": true, "game": game, "hash": format!("h{n}"), "over": over, "winner": winner,
                       "turn": *n, "current": *n % 2})
            }
            "drop" => {
                games.remove(&game);
                json!({"ok": true})
            }
            "validate" => {
                let d = &req["deck"];
                let ok = d["hero"].is_string() && d["cards"].as_array().is_some_and(|c| c.len() == 30);
                if ok { json!({"ok": true}) } else { json!({"ok": false, "error": "A deck needs exactly 30 cards"}) }
            }
            "draft" => {
                let heroes = ["HERO_01", "HERO_02", "HERO_03"];
                let hero = req["hero"].as_i64().filter(|h| (0..3).contains(h));
                let picks: Vec<i64> = req["picks"].as_array().map(|p| p.iter().filter_map(Value::as_i64).collect()).unwrap_or_default();
                let cards: Vec<String> = picks.iter().map(|i| format!("CARD_{i}")).collect();
                let done = cards.len() >= 30;
                let offer: Vec<&str> = if hero.is_some() && !done { vec!["CARD_0", "CARD_1", "CARD_2"] } else { vec![] };
                json!({"ok": true, "heroes": heroes, "hero": hero.map(|h| heroes[h as usize]).unwrap_or(""),
                       "cards": cards, "offer": offer, "done": done})
            }
            _ => json!({"ok": false, "error": "unknown op"}),
        }
    }
}

impl Referee for FakeReferee {
    fn call(&self, req: Value) -> RefFuture<'_> {
        let v = self.answer(&req);
        Box::pin(async move { Ok(v) })
    }
}

/// Splits a command line on spaces; "double" or 'single' quotes keep spaces in one word
/// (e.g. "/Applications/Classic HS.app/Contents/MacOS/Classic HS" --headless -- --referee).
pub fn split_command(cmd: &str) -> Vec<String> {
    let (mut out, mut word, mut quote, mut any) = (Vec::new(), String::new(), None, false);
    for c in cmd.chars() {
        match (quote, c) {
            (Some(q), c) if c == q => quote = None,
            (Some(_), c) => word.push(c),
            (None, '"' | '\'') => {
                quote = Some(c);
                any = true;
            }
            (None, c) if c.is_whitespace() => {
                if any || !word.is_empty() {
                    out.push(std::mem::take(&mut word));
                }
                any = false;
            }
            (None, c) => word.push(c),
        }
    }
    if any || !word.is_empty() {
        out.push(word);
    }
    out
}

#[cfg(test)]
mod tests {
    use super::split_command;

    #[test]
    fn split_command_quotes() {
        assert_eq!(split_command("godot --headless  --path . -- --referee"), ["godot", "--headless", "--path", ".", "--", "--referee"]);
        assert_eq!(
            split_command("\"/Apps/Classic HS.app/Contents/MacOS/Classic HS\" --headless -- --referee"),
            ["/Apps/Classic HS.app/Contents/MacOS/Classic HS", "--headless", "--", "--referee"]
        );
        assert_eq!(split_command("run 'a b' \"\""), ["run", "a b", ""]);
    }
}
