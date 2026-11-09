//! Registration by invite key over real WebSockets: signup_info, invite_required / invite_invalid,
//! a key's uses taken without races, a failed insert gives its use back.

use classichs_server::auth::RateLimit;
use classichs_server::entity::{account, signup_key};
use classichs_server::storage::Storage;
use classichs_server::{db, router, settings, App, AppRef, Timers};
use futures_util::{SinkExt, StreamExt};
use sea_orm::{ActiveModelTrait, ColumnTrait, EntityTrait, PaginatorTrait, QueryFilter, Set};
use serde_json::{json, Value};
use std::net::SocketAddr;
use std::time::Duration;
use tokio_tungstenite::tungstenite::Message;

async fn server() -> (SocketAddr, AppRef) {
    let store = Storage::dir(&std::env::temp_dir().join(format!("chs-test-{}", rand::random::<u64>()))).unwrap();
    let app = App::new(db::open(":memory:").await.unwrap(), false, Some(Timers::default()), store);
    // the tests register many accounts from one address
    *app.logins.lock().unwrap() = RateLimit::new(1000, Duration::from_secs(60));
    let listener = tokio::net::TcpListener::bind("127.0.0.1:0").await.unwrap();
    let addr = listener.local_addr().unwrap();
    let svc = router(app.clone()).into_make_service_with_connect_info::<SocketAddr>();
    tokio::spawn(async move { axum::serve(listener, svc).await.unwrap() });
    (addr, app)
}

/// One message to a new connection: the first answer of type auth, error or signup_info.
async fn ask(addr: SocketAddr, msg: Value) -> Value {
    let (mut ws, _) = tokio_tungstenite::connect_async(format!("ws://{addr}/")).await.unwrap();
    ws.send(Message::text(msg.to_string())).await.unwrap();
    loop {
        let m = tokio::time::timeout(Duration::from_secs(20), ws.next()).await.expect("an answer").unwrap().unwrap();
        if let Message::Text(s) = m {
            let v: Value = serde_json::from_str(s.as_str()).unwrap();
            if ["auth", "error", "signup_info"].contains(&v["t"].as_str().unwrap_or("")) {
                return v;
            }
        }
    }
}

fn reg(user: &str, key: Option<&str>) -> Value {
    let mut m = json!({"t": "register", "user": user, "password": "password123"});
    if let Some(k) = key {
        m["key"] = json!(k);
    }
    m
}

async fn make_key(app: &AppRef, key: &str, uses: i64) -> i64 {
    let row = signup_key::ActiveModel {
        key: Set(key.into()),
        uses_total: Set(uses),
        uses_left: Set(uses),
        created: Set(0),
        created_by_name: Set("root".into()),
        revoked: Set(false),
        ..Default::default()
    };
    row.insert(&app.db).await.unwrap().id
}

async fn uses_left(app: &AppRef, id: i64) -> i64 {
    signup_key::Entity::find_by_id(id).one(&app.db).await.unwrap().unwrap().uses_left
}

#[tokio::test]
async fn invite_only_registration() {
    let (addr, app) = server().await;
    assert_eq!(ask(addr, json!({"t": "signup_info"})).await, json!({"t": "signup_info", "invite_only": false}));

    // Open registration: no key needed; a valid key given anyway is recorded and spent.
    assert_eq!(ask(addr, reg("open_one", None)).await["t"], "auth");
    let k = make_key(&app, "11111111-1111-4111-8111-111111111111", 2).await;
    assert_eq!(ask(addr, reg("open_two", Some("11111111-1111-4111-8111-111111111111"))).await["t"], "auth");
    assert_eq!(uses_left(&app, k).await, 1);
    let a = db::account_by_name(&app.db, "open_two").await.unwrap().unwrap();
    assert_eq!(a.signup_key, Some(k));
    assert_eq!(db::account_by_name(&app.db, "open_one").await.unwrap().unwrap().signup_key, None);

    settings::set(&app, settings::INVITE_ONLY, "1").await.unwrap();
    assert_eq!(ask(addr, json!({"t": "signup_info"})).await["invite_only"], true);
    assert_eq!(ask(addr, reg("nokey", None)).await["code"], "invite_required");
    assert_eq!(ask(addr, reg("nokey", Some("  "))).await["code"], "invite_required", "a blank key is none");
    assert_eq!(ask(addr, reg("badkey", Some("not-a-key"))).await["code"], "invite_invalid");

    // A failed insert (the name taken) does not spend a use.
    let r = ask(addr, reg("open_one", Some("11111111-1111-4111-8111-111111111111"))).await;
    assert_eq!(r["code"], "taken", "{r}");
    assert_eq!(uses_left(&app, k).await, 1, "the use is given back");
    // Keys are not case-sensitive (pasted from anywhere); the last use goes, then the key is used up.
    assert_eq!(ask(addr, reg("closed_one", Some(" 11111111-1111-4111-8111-111111111111 "))).await["t"], "auth");
    assert_eq!(uses_left(&app, k).await, 0);
    assert_eq!(ask(addr, reg("closed_two", Some("11111111-1111-4111-8111-111111111111"))).await["code"], "invite_invalid");

    // A revoked key registers nobody.
    let r = make_key(&app, "22222222-2222-4222-8222-222222222222", 5).await;
    signup_key::ActiveModel { id: sea_orm::Unchanged(r), revoked: Set(true), ..Default::default() }.update(&app.db).await.unwrap();
    assert_eq!(ask(addr, reg("revoked", Some("22222222-2222-4222-8222-222222222222"))).await["code"], "invite_invalid");
    assert_eq!(uses_left(&app, r).await, 5);

    // Logging in needs no key.
    assert_eq!(ask(addr, json!({"t": "login", "user": "open_one", "password": "password123"})).await["t"], "auth");
}

#[tokio::test]
async fn a_key_is_never_overspent() {
    let (addr, app) = server().await;
    settings::set(&app, settings::INVITE_ONLY, "1").await.unwrap();
    let key = "33333333-3333-4333-8333-333333333333";
    let k = make_key(&app, key, 3).await;
    let tries: Vec<_> = (0..16).map(|i| tokio::spawn(ask(addr, reg(&format!("racer_{i}"), Some(key))))).collect();
    let mut ok = 0;
    for t in tries {
        let r = t.await.unwrap();
        match r["t"].as_str() {
            Some("auth") => ok += 1,
            _ => assert_eq!(r["code"], "invite_invalid", "{r}"),
        }
    }
    assert_eq!(ok, 3, "exactly the key's uses");
    assert_eq!(uses_left(&app, k).await, 0);
    assert_eq!(account::Entity::find().filter(account::Column::SignupKey.eq(k)).count(&app.db).await.unwrap(), 3);
}
