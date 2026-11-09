//! Replays: every finished game kept (table `replays`, M9) as the JSON the rules engine plays
//! again — the setup (players with their decks, seed, first, pack), every applied action in
//! order, the result and the final state hash — deflate-compressed. server/README.md, "Replays".

use crate::db::DbResult;
use crate::entity::replay;
use crate::AppRef;
use flate2::read::DeflateDecoder;
use flate2::write::DeflateEncoder;
use flate2::Compression;
use sea_orm::{ColumnTrait, Condition, ConnectionTrait, EntityTrait, QueryFilter, QueryOrder, QuerySelect, Set};
use serde_json::{json, Value};
use std::io::{Read, Write};

/// The replays a player gets in `replays {}`.
pub const LIST: u64 = 50;

pub fn compress(v: &Value) -> Vec<u8> {
    let mut e = DeflateEncoder::new(vec![], Compression::best());
    e.write_all(v.to_string().as_bytes()).expect("writing to a Vec");
    e.finish().expect("writing to a Vec")
}

pub fn decompress(b: &[u8]) -> Option<Value> {
    let mut s = String::new();
    DeflateDecoder::new(b).read_to_string(&mut s).ok()?;
    serde_json::from_str(&s).ok()
}

/// Keeps a finished game's replay (`data`: the replay JSON).
pub async fn save(c: &impl ConnectionTrait, game: &str, pack: &str, ids: [i64; 2], ended: i64, data: &Value) -> DbResult<()> {
    let row = replay::ActiveModel {
        game: Set(game.into()),
        pack: Set(pack.into()),
        p0: Set(Some(ids[0])),
        p1: Set(Some(ids[1])),
        ended: Set(ended),
        data: Set(compress(data)),
    };
    replay::Entity::insert(row).exec_without_returning(c).await?;
    Ok(())
}

/// A game's replay JSON (None: no such replay).
pub async fn data(c: &impl ConnectionTrait, game: &str) -> DbResult<Option<Value>> {
    Ok(replay::Entity::find_by_id(game).one(c).await?.and_then(|r| decompress(&r.data)))
}

/// Whether an account may watch a game's replay: its players. (Tournament games: part D adds
/// who else may.)
pub async fn can_view(app: &AppRef, account: i64, game: &str) -> bool {
    match replay::Entity::find_by_id(game).select_only().columns([replay::Column::P0, replay::Column::P1]).into_tuple::<(Option<i64>, Option<i64>)>().one(&app.db).await {
        Ok(Some((p0, p1))) => p0 == Some(account) || p1 == Some(account),
        _ => false,
    }
}

/// The `replays` answer: a player's last games, newest first.
pub async fn list(c: &impl ConnectionTrait, me: i64) -> DbResult<Value> {
    let rows = replay::Entity::find()
        .filter(Condition::any().add(replay::Column::P0.eq(me)).add(replay::Column::P1.eq(me)))
        .order_by_desc(replay::Column::Ended)
        .limit(LIST)
        .all(c)
        .await?;
    let list: Vec<Value> = rows
        .iter()
        .filter_map(|r| {
            let d = decompress(&r.data)?;
            let seat = if r.p0 == Some(me) { 0 } else { 1 };
            Some(json!({"game": r.game, "mode": d["mode"], "pack": r.pack, "pack_name": d["pack_name"],
                        "opponent": d["players"][1 - seat]["name"], "won": d["result"]["winner"] == json!(seat),
                        "started": d["started"], "ended": r.ended, "turns": d["result"]["turns"],
                        "you": seat, "winner": d["result"]["winner"], "heroes": [d["players"][0]["hero"], d["players"][1]["hero"]], "players": [d["players"][0]["name"], d["players"][1]["name"]]}))
        })
        .collect();
    Ok(json!({"t": "replays", "list": list}))
}
