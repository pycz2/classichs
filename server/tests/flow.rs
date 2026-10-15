//! End-to-end: real WebSocket clients against the server with the fake referee.

use classichs_server::referee::{FakeReferee, ProcessReferee, Referee};
use classichs_server::entity::account;
use classichs_server::{db, router, spawn_background, App, AppRef};
use sea_orm::{EntityTrait, QueryOrder};
use futures_util::{SinkExt, StreamExt};
use serde_json::{json, Value};
use std::net::SocketAddr;
use std::sync::Arc;
use std::time::Duration;
use tokio_tungstenite::tungstenite::Message;

type Ws = tokio_tungstenite::WebSocketStream<tokio_tungstenite::MaybeTlsStream<tokio::net::TcpStream>>;

async fn server(grace: Duration) -> (SocketAddr, AppRef) {
    server_with(Arc::new(FakeReferee::default()), grace).await
}

async fn server_with(referee: Arc<dyn Referee>, grace: Duration) -> (SocketAddr, AppRef) {
    let app = App::new(db::open(":memory:").await.unwrap(), referee, false, grace);
    spawn_background(app.clone());
    let listener = tokio::net::TcpListener::bind("127.0.0.1:0").await.unwrap();
    let addr = listener.local_addr().unwrap();
    let svc = router(app.clone()).into_make_service_with_connect_info::<SocketAddr>();
    tokio::spawn(async move { axum::serve(listener, svc).await.unwrap() });
    (addr, app)
}

struct C {
    ws: Ws,
}

impl C {
    async fn connect(addr: SocketAddr) -> C {
        let (ws, _) = tokio_tungstenite::connect_async(format!("ws://{addr}/")).await.unwrap();
        C { ws }
    }

    async fn send(&mut self, v: Value) {
        self.ws.send(Message::text(v.to_string())).await.unwrap();
    }

    /// The next message of type `t` (others, like queue_status, are skipped).
    async fn want(&mut self, t: &str) -> Value {
        let deadline = tokio::time::Instant::now() + Duration::from_secs(10);
        loop {
            let m = tokio::time::timeout_at(deadline, self.ws.next())
                .await
                .unwrap_or_else(|_| panic!("timed out waiting for {t}"))
                .unwrap_or_else(|| panic!("closed while waiting for {t}"))
                .unwrap();
            if let Message::Text(s) = m {
                let v: Value = serde_json::from_str(s.as_str()).unwrap();
                if v["t"] == t {
                    return v;
                }
                assert!(v["t"] != "error" || t == "error", "unexpected error while waiting for {t}: {v}");
            }
        }
    }

    async fn register(addr: SocketAddr, name: &str) -> C {
        let mut c = C::connect(addr).await;
        c.send(json!({"t": "register", "user": name, "password": "password123"})).await;
        let a = c.want("auth").await;
        assert_eq!(a["me"]["user"], name);
        assert_eq!(a["me"]["rank"]["rank"], 25);
        c
    }

    async fn game(&mut self, m: Value) {
        self.send(json!({"t": "game", "m": m})).await;
    }
}

fn deck(hero: &str) -> Value {
    json!({"name": "Test", "hero": hero, "cards": vec!["CARD_A"; 30]})
}

/// Two players queue in `mode` (the first with HERO_08); returns (host, guest, host's match message).
async fn matched(addr: SocketAddr, a: &str, b: &str, mode: &str) -> (C, C, Value) {
    let mut ca = C::register(addr, a).await;
    let mut cb = C::register(addr, b).await;
    ca.send(json!({"t": "queue", "mode": mode, "deck": deck("HERO_08")})).await;
    ca.want("queued").await;
    cb.send(json!({"t": "queue", "mode": mode, "deck": deck("HERO_01")})).await;
    cb.want("queued").await;
    let ma = ca.want("match").await;
    let mb = cb.want("match").await;
    assert_eq!(ma["game"], mb["game"]);
    assert_eq!(ma["seed"], mb["seed"]);
    assert_ne!(ma["host"], mb["host"]);
    assert_eq!(ma["mode"], mode);
    if ma["host"] == true {
        (ca, cb, ma)
    } else {
        (cb, ca, mb)
    }
}

/// hello both ways and the host's start.
async fn begin(host: &mut C, guest: &mut C, m: &Value) {
    let (hd, gd) = (m["_host_hero"].clone(), m["_guest_hero"].clone());
    host.game(json!({"t": "hello", "protocol": 1, "hero": hd, "cards": vec!["CARD_A"; 30]})).await;
    guest.game(json!({"t": "hello", "protocol": 1, "hero": gd, "cards": vec!["CARD_A"; 30]})).await;
    assert_eq!(guest.want("game").await["m"]["t"], "hello");
    assert_eq!(host.want("game").await["m"]["t"], "hello");
    host.game(json!({"t": "start", "seed": m["seed"], "decks": [[hd, vec!["CARD_A"; 30]], [gd, vec!["CARD_A"; 30]]]})).await;
    assert_eq!(guest.want("game").await["m"]["t"], "start");
}

/// Fills in which hero each side queued with (alice/carol queue first with HERO_08).
fn heroes(m: &mut Value, host_first: bool) {
    let (h, g) = if host_first { ("HERO_08", "HERO_01") } else { ("HERO_01", "HERO_08") };
    m["_host_hero"] = json!(h);
    m["_guest_hero"] = json!(g);
}

async fn setup(addr: SocketAddr, a: &str, b: &str, mode: &str) -> (C, C, Value) {
    let (mut host, mut guest, mut m) = matched(addr, a, b, mode).await;
    let host_first = m["opponent"]["user"] == b;
    heroes(&mut m, host_first);
    begin(&mut host, &mut guest, &m).await;
    (host, guest, m)
}

#[tokio::test]
async fn register_queue_match_relay_game_over() {
    let (addr, app) = server(Duration::from_secs(30)).await;
    let (mut host, mut guest, _) = setup(addr, "alice", "bob", "casual").await;
    host.game(json!({"t": "action", "n": 0, "action": {"type": "mulligan", "player": 0, "replace": []}, "hash": ""})).await;
    assert_eq!(guest.want("game").await["m"]["action"]["type"], "mulligan");
    guest.game(json!({"t": "action", "n": 0, "action": {"type": "mulligan", "player": 1, "replace": []}, "hash": ""})).await;
    host.want("game").await;
    host.game(json!({"t": "action", "n": 1, "action": {"type": "end_turn", "player": 0}, "hash": "h3"})).await;
    assert_eq!(guest.want("game").await["m"]["hash"], "h3");
    guest.game(json!({"t": "emote", "id": "greetings"})).await;
    assert_eq!(host.want("game").await["m"]["id"], "greetings");
    guest.game(json!({"t": "action", "n": 1, "action": {"type": "concede", "player": 1}, "hash": ""})).await;
    let h = host.want("game_over").await;
    let g = guest.want("game_over").await;
    assert_eq!((h["result"].as_str(), g["result"].as_str()), (Some("win"), Some("loss")));
    assert_eq!(h["reason"], "over");
    let mmrs: Vec<f64> =
        account::Entity::find().order_by_asc(account::Column::CasualMmr).all(&app.db).await.unwrap().iter().map(|a| a.casual_mmr).collect();
    assert_eq!(mmrs, vec![1484.0, 1516.0]);
    assert!(app.hub().games.is_empty());
    // Free to queue again.
    host.send(json!({"t": "queue", "mode": "casual", "deck": deck("HERO_08")})).await;
    host.want("queued").await;
}

#[tokio::test]
async fn wrong_hash_or_seed_loses() {
    let (addr, _app) = server(Duration::from_secs(30)).await;
    let (mut host, mut guest, _) = setup(addr, "carol", "dave", "ranked").await;
    host.game(json!({"t": "action", "n": 0, "action": {"type": "end_turn", "player": 0}, "hash": "nope"})).await;
    let h = host.want("game_over").await;
    assert_eq!((h["result"].as_str(), h["reason"].as_str()), (Some("loss"), Some("desync")));
    let g = guest.want("game_over").await;
    assert_eq!(g["result"], "win");
    assert_eq!(g["rank"]["stars"], 1);
    assert_eq!(h["rank"]["rank"], 25);

    let (mut host, mut guest, _) = matched(addr, "erin", "frank", "casual").await;
    host.game(json!({"t": "hello", "hero": "HERO_99", "cards": vec!["CARD_A"; 30]})).await;
    assert_eq!(host.want("game_over").await["reason"], "cheat");
    guest.want("game_over").await;
}

#[tokio::test]
async fn bad_start_and_actions_for_the_other_player() {
    let (addr, _app) = server(Duration::from_secs(30)).await;
    let (mut host, mut guest, mut m) = matched(addr, "gina", "hank", "casual").await;
    let host_first = m["opponent"]["user"] == "hank";
    heroes(&mut m, host_first);
    let (hd, gd) = (m["_host_hero"].clone(), m["_guest_hero"].clone());
    host.game(json!({"t": "hello", "hero": hd, "cards": vec!["CARD_A"; 30]})).await;
    guest.game(json!({"t": "hello", "hero": gd, "cards": vec!["CARD_A"; 30]})).await;
    host.want("game").await;
    host.game(json!({"t": "start", "seed": 1, "decks": [[hd, vec!["CARD_A"; 30]], [gd, vec!["CARD_A"; 30]]]})).await;
    assert_eq!(host.want("game_over").await["reason"], "cheat");
    guest.want("game_over").await;

    let (mut host, mut guest, _) = setup(addr, "ivan", "judy", "casual").await;
    guest.game(json!({"t": "action", "n": 0, "action": {"type": "concede", "player": 0}, "hash": ""})).await;
    let g = guest.want("game_over").await;
    assert_eq!((g["result"].as_str(), g["reason"].as_str()), (Some("loss"), Some("cheat")));
    host.want("game_over").await;
}

#[tokio::test]
async fn disconnect_loses_after_grace() {
    let (addr, _app) = server(Duration::from_millis(500)).await;
    let (host, mut guest, _) = setup(addr, "kate", "liam", "casual").await;
    drop(host);
    let g = guest.want("game_over").await;
    assert_eq!((g["result"].as_str(), g["reason"].as_str()), (Some("win"), Some("disconnect")));
}

#[tokio::test]
async fn social_and_friendly_invite() {
    let (addr, _app) = server(Duration::from_secs(30)).await;
    let mut a = C::register(addr, "mona").await;
    let mut b = C::register(addr, "ned").await;
    a.send(json!({"t": "set_tag", "tag": "Mona"})).await;
    assert_eq!(a.want("me").await["me"]["tag"], "Mona");
    b.send(json!({"t": "set_tag", "tag": "mONA"})).await;
    assert_eq!(b.want("error").await["code"], "tag_taken");
    b.send(json!({"t": "set_tag", "tag": "Ned"})).await;
    b.want("me").await;
    a.send(json!({"t": "friend_add", "tag": "ned"})).await;
    assert_eq!(a.want("friends").await["requests_out"][0]["user"], "ned");
    assert_eq!(b.want("friends").await["requests_in"][0]["user"], "mona");
    b.send(json!({"t": "friend_accept", "user": "mona"})).await;
    let f = b.want("friends").await;
    assert_eq!(f["list"][0]["user"], "mona");
    assert_eq!(f["list"][0]["online"], true);
    a.want("friends").await;
    a.send(json!({"t": "msg", "to": "ned", "text": "hi"})).await;
    a.want("msg_sent").await;
    let m = b.want("msg").await;
    assert_eq!((m["from"].as_str(), m["text"].as_str()), (Some("mona"), Some("hi")));
    b.send(json!({"t": "history", "with": "mona"})).await;
    assert_eq!(b.want("history").await["list"][0]["text"], "hi");
    a.send(json!({"t": "msg", "to": "ned", "text": ""})).await;
    assert_eq!(a.want("error").await["code"], "bad_text");

    // Friendly game by invite.
    a.send(json!({"t": "invite", "to": "ned", "deck": deck("HERO_08")})).await;
    a.want("invited").await;
    assert_eq!(b.want("invite").await["from"], "mona");
    b.send(json!({"t": "invite_accept", "from": "mona", "deck": deck("HERO_01")})).await;
    assert_eq!(a.want("match").await["mode"], "friendly");
    assert_eq!(b.want("match").await["mode"], "friendly");
    a.game(json!({"t": "bye", "code": "left"})).await;
    assert_eq!(a.want("game_over").await["reason"], "left");
    b.want("game_over").await;

    // A block ends the friendship and stops messages and invites.
    b.send(json!({"t": "block", "user": "mona"})).await;
    assert_eq!(b.want("friends").await["blocked"][0]["user"], "mona");
    a.send(json!({"t": "msg", "to": "ned", "text": "hello?"})).await;
    assert_eq!(a.want("error").await["code"], "not_friends");
    a.send(json!({"t": "friend_add", "tag": "Ned"})).await;
    assert_eq!(a.want("error").await["code"], "not_found");
    a.send(json!({"t": "invite", "to": "ned", "deck": deck("HERO_08")})).await;
    assert_eq!(a.want("error").await["code"], "not_friends");
}

#[tokio::test]
async fn arena_run() {
    let (addr, _app) = server(Duration::from_secs(30)).await;
    let mut cs = vec![];
    for name in ["olga", "pete"] {
        let mut c = C::register(addr, name).await;
        c.send(json!({"t": "arena_start"})).await;
        let s = c.want("arena").await;
        assert_eq!(s["state"]["heroes"].as_array().unwrap().len(), 3);
        c.send(json!({"t": "arena_queue"})).await;
        assert_eq!(c.want("error").await["code"], "not_ready");
        c.send(json!({"t": "arena_hero", "i": 1})).await;
        assert_eq!(c.want("arena").await["state"]["hero"], "HERO_02");
        for k in 0..30 {
            c.send(json!({"t": "arena_pick", "i": k % 3})).await;
            c.want("arena").await;
        }
        c.send(json!({"t": "arena_pick", "i": 0})).await;
        assert_eq!(c.want("error").await["code"], "bad_request");
        c.send(json!({"t": "arena_queue"})).await;
        assert_eq!(c.want("queued").await["mode"], "arena");
        cs.push(c);
    }
    let m0 = cs[0].want("match").await;
    cs[1].want("match").await;
    assert_eq!(m0["mode"], "arena");
    let (host, guest) = if m0["host"] == true { (0, 1) } else { (1, 0) };
    let hello = json!({"t": "hello", "hero": "HERO_02", "cards": (0..30).map(|k| format!("CARD_{}", k % 3)).collect::<Vec<_>>()});
    cs[host].game(hello.clone()).await;
    cs[guest].game(hello).await;
    cs[host].want("game").await;
    cs[host].game(json!({"t": "action", "n": 0, "action": {"type": "concede", "player": 1}, "hash": ""})).await;
    // Only the started game accepts actions: the host's action before start is a protocol loss.
    let h = cs[host].want("game_over").await;
    assert_eq!(h["arena"]["losses"], 1);
    assert_eq!(h["arena"]["over"], false);
    assert_eq!(cs[guest].want("game_over").await["arena"]["wins"], 1);
    cs[host].send(json!({"t": "arena_retire"})).await;
    assert_eq!(cs[host].want("arena").await["state"], Value::Null);
}

#[tokio::test]
async fn auth_rules_and_abuse() {
    let (addr, _app) = server(Duration::from_secs(30)).await;
    let mut c = C::connect(addr).await;
    c.send(json!({"t": "friends"})).await;
    assert_eq!(c.want("error").await["code"], "auth_required");
    c.send(json!({"t": "register", "user": "x", "password": "password123"})).await;
    assert_eq!(c.want("error").await["code"], "bad_user");
    c.send(json!({"t": "register", "user": "quinn", "password": "short"})).await;
    assert_eq!(c.want("error").await["code"], "bad_password");
    c.send(json!({"t": "register", "user": "quinn", "password": "password123", "extra": 1})).await;
    assert_eq!(c.want("error").await["code"], "bad_request");
    c.send(json!({"t": "register", "user": "quinn", "password": "password123"})).await;
    let token = c.want("auth").await["token"].as_str().unwrap().to_string();

    // Wrong password, then resume with the token on a new connection.
    let mut d = C::connect(addr).await;
    d.send(json!({"t": "login", "user": "quinn", "password": "wrongpassword"})).await;
    assert_eq!(d.want("error").await["code"], "bad_login");
    d.send(json!({"t": "resume", "token": token})).await;
    assert_eq!(d.want("auth").await["me"]["user"], "quinn");
    assert_eq!(c.want("error").await["code"], "replaced");
    d.send(json!({"t": "logout"})).await;
    d.want("logged_out").await;
    d.send(json!({"t": "resume", "token": token})).await;
    assert_eq!(d.want("error").await["code"], "bad_token");

    // Garbage again and again: the server hangs up.
    let mut e = C::connect(addr).await;
    for _ in 0..25 {
        if e.ws.send(Message::text("{not json")).await.is_err() {
            break;
        }
    }
    let mut closed = false;
    for _ in 0..40 {
        match tokio::time::timeout(Duration::from_secs(5), e.ws.next()).await {
            Ok(Some(Ok(Message::Close(_)))) | Ok(None) | Ok(Some(Err(_))) => {
                closed = true;
                break;
            }
            _ => {}
        }
    }
    assert!(closed);
}

/// With the real referee (the game without a window): set CLASSICHS_GODOT=godot and
/// CLASSICHS_PROJECT=/path/to/like_classic_hs, else this test does nothing.
#[tokio::test]
async fn real_referee() {
    let (Ok(godot), Ok(project)) = (std::env::var("CLASSICHS_GODOT"), std::env::var("CLASSICHS_PROJECT")) else {
        eprintln!("real_referee skipped: set CLASSICHS_GODOT and CLASSICHS_PROJECT");
        return;
    };
    let r = Arc::new(ProcessReferee::new(&format!("{godot} --headless --path {project} -- --referee")));
    assert_eq!(r.call(json!({"op": "ping"})).await.unwrap()["ok"], true);
    let mut cards: Vec<&str> = vec![];
    for id in ["VAN_CS2_022", "VAN_CS2_023", "VAN_CS2_024", "VAN_CS2_025", "VAN_CS2_026", "VAN_CS2_027", "VAN_CS2_029",
               "VAN_CS2_032", "VAN_CS2_033", "VAN_EX1_277", "VAN_EX1_066", "VAN_CS2_172", "VAN_EX1_019", "VAN_CS2_182", "VAN_CS2_147"] {
        cards.extend([id, id]);
    }
    let mage = json!({"hero": "HERO_08", "cards": cards});
    let v = r.call(json!({"op": "validate", "deck": mage})).await.unwrap();
    assert_eq!(v["ok"], true, "{v}");
    let v = r.call(json!({"op": "validate", "deck": {"hero": "HERO_08", "cards": &cards[..29]}})).await.unwrap();
    assert_eq!(v["ok"], false);
    let d = r.call(json!({"op": "draft", "seed": 5, "hero": 0, "picks": [0, 1]})).await.unwrap();
    assert_eq!(d["heroes"].as_array().unwrap().len(), 3);
    assert_eq!(d["cards"].as_array().unwrap().len(), 2);
    assert_eq!(d["offer"].as_array().unwrap().len(), 3);

    // A whole game through the server: hello, start, mulligans, a concede.
    let (addr, _app) = server_with(r, Duration::from_secs(30)).await;
    let mut a = C::register(addr, "rhea").await;
    let mut b = C::register(addr, "saul").await;
    for c in [&mut a, &mut b] {
        c.send(json!({"t": "queue", "mode": "ranked", "deck": mage})).await;
        c.want("queued").await;
    }
    let m = a.want("match").await;
    b.want("match").await;
    let (mut host, mut guest) = if m["host"] == true { (a, b) } else { (b, a) };
    let hello = json!({"t": "hello", "hero": "HERO_08", "cards": cards});
    host.game(hello.clone()).await;
    guest.game(hello).await;
    host.want("game").await;
    host.game(json!({"t": "start", "seed": m["seed"], "decks": [["HERO_08", cards], ["HERO_08", cards]]})).await;
    guest.want("game").await;
    host.game(json!({"t": "action", "n": 0, "action": {"type": "mulligan", "player": 0, "replace": []}, "hash": ""})).await;
    guest.want("game").await;
    guest.game(json!({"t": "action", "n": 0, "action": {"type": "concede", "player": 1}, "hash": ""})).await;
    let h = host.want("game_over").await;
    assert_eq!((h["result"].as_str(), h["reason"].as_str()), (Some("win"), Some("over")));
    assert_eq!(guest.want("game_over").await["result"], "loss");
}

#[tokio::test]
async fn presence_chats_and_read() {
    let (addr, app) = server(Duration::from_secs(30)).await;
    let mut a = C::connect(addr).await;
    a.send(json!({"t": "register", "user": "uma", "password": "password123"})).await;
    let token = a.want("auth").await["token"].as_str().unwrap().to_string();
    let mut b = C::register(addr, "vic").await;
    b.send(json!({"t": "set_tag", "tag": "Vic"})).await;
    b.want("me").await;
    a.send(json!({"t": "friend_add", "tag": "vic"})).await;
    b.want("friends").await;
    b.send(json!({"t": "friend_accept", "user": "uma"})).await;
    let p = a.want("presence").await;
    assert_eq!((p["user"].as_str(), p["online"].as_bool(), p["status"].as_str()), (Some("vic"), Some(true), Some("online")));
    assert_eq!(b.want("presence").await["user"], "uma");

    // No messages yet; then two, unread until read.
    b.send(json!({"t": "chats"})).await;
    let c = b.want("chats").await;
    assert_eq!(c["list"][0]["with"], "uma");
    assert_eq!(c["list"][0]["status"], "online");
    assert_eq!((c["list"][0]["last"].clone(), c["list"][0]["unread"].as_i64()), (Value::Null, Some(0)));
    for text in ["hello", "again"] {
        a.send(json!({"t": "msg", "to": "vic", "text": text})).await;
        a.want("msg_sent").await;
        assert_eq!(b.want("msg").await["text"], text);
    }
    b.send(json!({"t": "msg", "to": "uma", "text": "hi"})).await;
    b.want("msg_sent").await;
    b.send(json!({"t": "chats"})).await;
    let c = b.want("chats").await;
    assert_eq!(c["list"][0]["unread"], 2);
    assert_eq!((c["list"][0]["last"]["from"].as_str(), c["list"][0]["last"]["text"].as_str()), (Some("vic"), Some("hi")));
    a.send(json!({"t": "chats"})).await;
    assert_eq!(a.want("chats").await["list"][0]["unread"], 1);
    b.send(json!({"t": "read", "with": "uma"})).await;
    assert_eq!(b.want("read_ok").await["with"], "uma");
    b.send(json!({"t": "chats"})).await;
    assert_eq!(b.want("chats").await["list"][0]["unread"], 0);
    b.send(json!({"t": "read", "with": "nobody_here"})).await;
    assert_eq!(b.want("error").await["code"], "not_found");

    // Searching, back online, offline, back by token.
    a.send(json!({"t": "queue", "mode": "casual", "deck": deck("HERO_08")})).await;
    assert_eq!(b.want("presence").await["status"], "searching");
    a.send(json!({"t": "unqueue"})).await;
    assert_eq!(b.want("presence").await["status"], "online");
    drop(a);
    let p = b.want("presence").await;
    assert_eq!((p["user"].as_str(), p["online"].as_bool(), p["status"].as_str()), (Some("uma"), Some(false), Some("offline")));

    // The token is renewed on use: 30 days from now again.
    use classichs_server::entity::session;
    use sea_orm::{ColumnTrait, QueryFilter};
    let soon = classichs_server::ranked::now() + 60;
    session::Entity::update_many().col_expr(session::Column::Expires, soon.into()).exec(&app.db).await.unwrap();
    let mut a = C::connect(addr).await;
    a.send(json!({"t": "resume", "token": token})).await;
    assert_eq!(a.want("auth").await["me"]["user"], "uma");
    assert_eq!(b.want("presence").await["status"], "online");
    let s = session::Entity::find().filter(session::Column::Account.eq(1)).one(&app.db).await.unwrap().unwrap();
    assert!(s.expires > soon + 29 * 86400, "renewed: {}", s.expires);
}

#[tokio::test]
async fn games_are_in_the_event_log() {
    use classichs_server::entity::event;
    use sea_orm::{ColumnTrait, QueryFilter};
    let (addr, app) = server(Duration::from_secs(30)).await;
    let (mut host, mut guest, m) = setup(addr, "walt", "xena", "casual").await;
    host.game(json!({"t": "action", "n": 0, "action": {"type": "end_turn", "player": 0}, "hash": "h1"})).await;
    guest.want("game").await;
    guest.game(json!({"t": "action", "n": 0, "action": {"type": "illegal", "player": 1}, "hash": ""})).await;
    assert_eq!(guest.want("game_over").await["reason"], "illegal");
    host.want("game_over").await;
    let game = m["game"].as_str().unwrap().to_string();
    let mut kinds = vec![];
    for _ in 0..50 {
        let evs = event::Entity::find().filter(event::Column::Game.eq(&game)).order_by_asc(event::Column::Id).all(&app.db).await.unwrap();
        kinds = evs.iter().map(|e| e.kind.clone()).collect::<Vec<_>>();
        if kinds.last().map(String::as_str) == Some("game_end") {
            let end = evs.last().unwrap();
            let data: Value = serde_json::from_str(end.data.as_deref().unwrap()).unwrap();
            assert_eq!(data["reason"], "illegal");
            assert_eq!(data["message"]["action"]["type"], "illegal");
            assert!(end.text.contains("beat"), "{}", end.text);
            let act = evs.iter().find(|e| e.kind == "game_action").unwrap();
            assert_eq!(act.text, format!("{}: end_turn", act.user.as_deref().unwrap()));
            break;
        }
        tokio::time::sleep(Duration::from_millis(50)).await;
    }
    assert_eq!(kinds, ["match", "game_start", "game_action", "game_end"]);
    let all: Vec<String> = event::Entity::find().all(&app.db).await.unwrap().into_iter().map(|e| e.kind).collect();
    for k in ["register", "queue", "match", "game_end"] {
        assert!(all.iter().any(|x| x == k), "{k} missing from {all:?}");
    }
}

#[tokio::test]
async fn presence_follows_a_game() {
    let (addr, _app) = server(Duration::from_secs(30)).await;
    let mut f = C::register(addr, "yuri").await;
    let (mut host, mut guest, m) = setup(addr, "zack", "abby", "casual").await;
    f.send(json!({"t": "set_tag", "tag": "Yuri"})).await;
    f.want("me").await;
    let host_name = if m["opponent"]["user"] == "abby" { "zack" } else { "abby" };
    host.send(json!({"t": "friend_add", "tag": "yuri"})).await;
    f.want("friends").await;
    f.send(json!({"t": "friend_accept", "user": host_name})).await;
    let p = f.want("presence").await;
    assert_eq!((p["user"].as_str(), p["status"].as_str()), (Some(host_name), Some("in_game")));
    host.game(json!({"t": "action", "n": 0, "action": {"type": "concede", "player": 0}, "hash": ""})).await;
    host.want("game_over").await;
    guest.want("game_over").await;
    let p = f.want("presence").await;
    assert_eq!((p["user"].as_str(), p["online"].as_bool(), p["status"].as_str()), (Some(host_name), Some(true), Some("online")));
}
