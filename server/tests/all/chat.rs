//! Tournament chats (`classichs_server::chat`): real WebSocket clients subscribe to the
//! tournaments list's chat and to tournaments' own chats, write, see the marks and a moderator's
//! deletes; a tournament's chat closes 10 minutes after its end; the cleanup by the keeping time.

use super::tournament::{create, server, C};
use classichs_server::entity::{chat_message as cm, message, tournament as tour};
use classichs_server::events::now_ms;
use classichs_server::{chat, db, ranked, settings, AppRef};
use sea_orm::sea_query::Expr;
use sea_orm::{ColumnTrait, EntityTrait, PaginatorTrait, QueryFilter, Set};
use serde_json::{json, Value};

const MIN: i64 = 60_000;

async fn make_admin(app: &AppRef, name: &str) {
    let id = classichs_server::db::id_by_name(&app.db, name).await.unwrap().unwrap();
    classichs_server::perm::give_builtin(&app.db, id, 0, "Admin").await.unwrap(); // (the roles: main's Admin)
}

async fn sub(c: &mut C, channel: &str) -> Value {
    c.send(json!({"t": "chat_sub", "channel": channel})).await;
    let h = c.want("chat_history").await;
    assert_eq!(h["channel"], channel);
    h
}

async fn say(c: &mut C, channel: &str, text: &str) {
    c.send(json!({"t": "chat_send", "channel": channel, "text": text})).await;
}

/// The next chat push (a message, a delete or a closing).
async fn chat_push(c: &mut C) -> Value {
    loop {
        let v = c.next().await;
        match v["t"].as_str().unwrap() {
            "chat_msg" | "chat_deleted" | "chat_closed" => return v,
            "error" => panic!("{}: {v}", c.name),
            _ => {}
        }
    }
}

async fn set_ended(app: &AppRef, id: i64, ended: i64) {
    tour::Entity::update_many()
        .col_expr(tour::Column::Ended, Expr::value(ended))
        .col_expr(tour::Column::Status, Expr::value("finished"))
        .filter(tour::Column::Id.eq(id))
        .exec(&app.db)
        .await
        .unwrap();
}

#[tokio::test]
async fn channels_live_marks_and_deletes() {
    let (addr, app) = server().await;
    let mut a = C::register(addr, "chat_a").await;
    let mut b = C::register(addr, "chat_b").await;
    let mut m = C::register(addr, "chat_mod").await;
    make_admin(&app, "chat_mod").await;
    let t1 = create(&mut a, json!({"name": "A cup"})).await["id"].as_i64().unwrap();
    let t2 = create(&mut b, json!({"name": "B cup"})).await["id"].as_i64().unwrap();
    let (c1, c2) = (format!("t:{t1}"), format!("t:{t2}"));

    let h = sub(&mut a, &c1).await;
    assert_eq!((h["list"].clone(), h["open"].clone(), h["closes"].clone(), h["moderator"].clone()), (json!([]), json!(true), json!(0), json!(false)));
    sub(&mut b, &c2).await;
    assert_eq!(sub(&mut m, &c1).await["moderator"], true);
    sub(&mut m, "tournaments").await;

    // live, to that channel's subscribers only; the creator's and the admin's marks
    say(&mut a, &c1, "hello").await;
    for c in [&mut a, &mut m] {
        let v = chat_push(c).await;
        assert_eq!((v["t"].as_str(), v["channel"].as_str(), v["msg"]["from"].as_str(), v["msg"]["text"].as_str(), v["msg"]["mark"].as_str()),
                   (Some("chat_msg"), Some(c1.as_str()), Some("chat_a"), Some("hello"), Some("creator")));
    }
    let hello = a_id(&app, &c1, "hello").await;
    say(&mut m, &c1, "rules").await;
    assert_eq!(chat_push(&mut a).await["msg"]["mark"], "admin");
    chat_push(&mut m).await;
    say(&mut b, &c2, "mine").await;
    let v = chat_push(&mut b).await; // not a message of the other tournament
    assert_eq!((v["channel"].as_str(), v["msg"]["text"].as_str(), v["msg"]["mark"].as_str()), (Some(c2.as_str()), Some("mine"), Some("creator")));

    // the list's chat: only admins are marked (a creator is not)
    say(&mut a, "tournaments", "hi all").await;
    let v = chat_push(&mut m).await;
    assert_eq!((v["channel"].as_str(), v["msg"]["mark"].as_str()), (Some("tournaments"), Some("")));
    say(&mut m, "tournaments", "welcome").await;
    assert_eq!(chat_push(&mut m).await["msg"]["mark"], "admin");

    // only a moderator deletes; everyone sees who did, the text is gone for later readers too
    let e = a.refused(json!({"t": "chat_delete", "id": hello})).await;
    assert!(e.contains("moderators"), "{e}");
    m.send(json!({"t": "chat_delete", "id": hello})).await;
    for c in [&mut a, &mut m] {
        let v = chat_push(c).await;
        assert_eq!((v["t"].as_str(), v["channel"].as_str(), v["id"].as_i64(), v["by"].as_str()), (Some("chat_deleted"), Some(c1.as_str()), Some(hello), Some("chat_mod")));
    }
    let h = sub(&mut b, &c1).await;
    let first = &h["list"][0];
    assert_eq!((first["text"].as_str(), first["deleted_by"].as_str(), h["list"][1]["text"].as_str()), (Some(""), Some("chat_mod"), Some("rules")));
    assert_eq!(cm::Entity::find().count(&app.db).await.unwrap(), 5, "a deleted message keeps its row");

    // unsubscribed: no more messages of that channel
    a.send(json!({"t": "chat_unsub", "channel": c1})).await;
    sub(&mut a, "tournaments").await;
    say(&mut m, &c1, "after").await;
    say(&mut m, "tournaments", "list again").await;
    assert_eq!(chat_push(&mut a).await["msg"]["text"], "list again");

    // checks: the text, the channel, the rate limit
    assert!(a.refused(json!({"t": "chat_send", "channel": "tournaments", "text": " "})).await.contains("1 to 500"));
    assert!(a.refused(json!({"t": "chat_send", "channel": "tournaments", "text": "x".repeat(501)})).await.contains("1 to 500"));
    assert!(a.refused(json!({"t": "chat_sub", "channel": "lobby"})).await.contains("channel"));
    assert!(a.refused(json!({"t": "chat_sub", "channel": "t:999999"})).await.contains("No such tournament"));
    let mut limited = false;
    for i in 0..12 {
        a.send(json!({"t": "chat_send", "channel": "tournaments", "text": format!("spam {i}")})).await;
    }
    for _ in 0..12 {
        let v = a.next().await;
        if v["t"] == "error" {
            assert_eq!(v["code"], "rate_limited");
            limited = true;
            break;
        }
    }
    assert!(limited, "sending is rate-limited");
}

async fn a_id(app: &AppRef, channel: &str, text: &str) -> i64 {
    cm::Entity::find().filter(cm::Column::Channel.eq(channel)).filter(cm::Column::Text.eq(text)).one(&app.db).await.unwrap().unwrap().id
}

#[tokio::test]
async fn a_tournament_chat_closes_ten_minutes_after_its_end() {
    let (addr, app) = server().await;
    let mut a = C::register(addr, "close_a").await;
    let t = create(&mut a, json!({})).await["id"].as_i64().unwrap();
    let ch = format!("t:{t}");

    let ended = now_ms() - 9 * MIN;
    set_ended(&app, t, ended).await;
    let h = sub(&mut a, &ch).await;
    assert_eq!((h["open"].as_bool(), h["closes"].as_i64()), (Some(true), Some((ended + 10 * MIN + 999) / 1000)));
    say(&mut a, &ch, "gg").await;
    assert_eq!(chat_push(&mut a).await["msg"]["text"], "gg");

    // the subscribers learn when it closes
    chat::announce_closed(&app, ended + 10 * MIN - 1000, ended + 10 * MIN).await;
    assert_eq!(chat_push(&mut a).await, json!({"t": "chat_closed", "channel": ch}));

    set_ended(&app, t, now_ms() - 11 * MIN).await;
    let e = a.refused(json!({"t": "chat_send", "channel": ch, "text": "late"})).await;
    assert!(e.contains("closed"), "{e}");
    let h = sub(&mut a, &ch).await;
    assert_eq!((h["open"].as_bool(), h["list"][0]["text"].as_str()), (Some(false), Some("gg")), "read-only, still readable");
    // the list's chat never closes
    assert_eq!(sub(&mut a, "tournaments").await["open"], true);
}

#[tokio::test]
async fn the_cleanup_removes_what_is_past_the_keeping_time() {
    let (_addr, app) = server().await;
    // the server's own cleanup at its start first (its first tick)
    tokio::time::sleep(std::time::Duration::from_millis(500)).await;
    let now = ranked::now();
    let day = 86_400;
    let u1 = db::create_account(&app.db, "keep_1", "x", "player").await.unwrap().unwrap();
    let u2 = db::create_account(&app.db, "keep_2", "x", "player").await.unwrap().unwrap();
    for (i, age) in [1, 13, 15, 400].into_iter().enumerate() {
        let at = now - age * day;
        cm::Entity::insert(cm::ActiveModel { subserver: Set(0), channel: Set(if i % 2 == 0 { "tournaments".into() } else { "t:1".into() }),
            account: Set(u1), text: Set(format!("{age} days")), at: Set(at), ..Default::default() })
            .exec(&app.db)
            .await
            .unwrap();
        message::Entity::insert(message::ActiveModel { lo: Set(u1), hi: Set(u2), src: Set(u1), text: Set(format!("{age} days")), at: Set(at), seen: Set(true), ..Default::default() })
            .exec(&app.db)
            .await
            .unwrap();
    }
    let left = |app: AppRef| async move { (cm::Entity::find().count(&app.db).await.unwrap(), message::Entity::find().count(&app.db).await.unwrap()) };

    assert_eq!(settings::chat_keep_days(&app).await.unwrap(), 14, "two weeks by default");
    assert_eq!(chat::cleanup(&app, now).await.unwrap(), (2, 2));
    assert_eq!(left(app.clone()).await, (2, 2));

    settings::set(&app, 0, settings::CHAT_KEEP_DAYS, "0").await.unwrap();
    assert_eq!(chat::cleanup(&app, now + 1000 * day).await.unwrap(), (0, 0), "0 = unlimited");
    assert_eq!(left(app.clone()).await, (2, 2));

    settings::set(&app, 0, settings::CHAT_KEEP_DAYS, "3").await.unwrap();
    assert_eq!(chat::cleanup(&app, now).await.unwrap(), (1, 1));
    let kept: Vec<String> = cm::Entity::find().all(&app.db).await.unwrap().into_iter().map(|m| m.text).collect();
    assert_eq!(kept, ["1 days"]);
}
