//! The admin panel's changes to a player (beside admin.rs, behind its guard and its `may_manage`):
//! per game the ranked standing, the decks (with their codes, deck_code.rs) and the settings; the
//! Arena run and the tag. Each change is checked, logged as an `admin` event and pushed to the player
//! when online (`me`, `arena`, `decks`, `game_settings`: messages the client already reads).
//! server/README.md, "The admin API".

use crate::admin::{db_err, err, may_manage, Admin};
use crate::bots::cards::Library;
use crate::db::{self, Account};
use crate::deck_code;
use crate::entity::{account, arena, deck, game_setting, pack, standing};
use crate::packs::{self, GameRules};
use crate::ranked::{self, Mode, Rank};
use crate::ws::{arena_json, deck_json, game_settings_msg, me_json, merge_game_settings, MAX_DECKS};
use crate::{auth, AppRef};
use axum::extract::{Path, State};
use axum::http::StatusCode;
use axum::response::{IntoResponse, Response};
use axum::routing::post;
use axum::{Extension, Json, Router};
use classichs_engine::deck::Deck;
use classichs_engine::ruleset::Ruleset;
use sea_orm::{ActiveModelTrait, ColumnTrait, EntityTrait, PaginatorTrait, QueryFilter, QueryOrder, Set, Unchanged};
use serde::Deserialize;
use serde_json::{json, Map, Value};
use std::collections::{BTreeMap, HashMap};
use std::sync::{Arc, Mutex, OnceLock};

pub fn routes() -> Router<AppRef> {
    Router::new()
        .route("/admin/api/accounts/{id}/standing", post(standing_edit))
        .route("/admin/api/accounts/{id}/arena", post(arena_edit))
        .route("/admin/api/accounts/{id}/game_settings", post(settings_edit))
        .route("/admin/api/accounts/{id}/tag", post(tag_edit))
        .route("/admin/api/accounts/{id}/decks", post(deck_add))
        .route("/admin/api/accounts/{id}/decks/{deck}/{action}", post(deck_action))
}

type Res<T> = Result<T, Response>;

fn bad(text: impl AsRef<str>) -> Response {
    err(StatusCode::BAD_REQUEST, text.as_ref())
}

// --- games and names ----------------------------------------------------------------------------

/// The games an account may have data in: every server pack's manifest id (its newest version,
/// an enabled one first), and the built-in Classic rules when no server pack has their id. By name.
pub async fn games(app: &AppRef) -> Result<Vec<Arc<GameRules>>, sea_orm::DbErr> {
    let rows = pack::Entity::find().filter(pack::Column::Owner.is_null()).order_by_asc(pack::Column::Id).all(&app.db).await?;
    let mut newest: BTreeMap<String, &pack::Model> = BTreeMap::new();
    for p in &rows {
        if p.enabled || newest.get(&p.pack_id).is_none_or(|o| !o.enabled) {
            newest.insert(p.pack_id.clone(), p);
        }
    }
    let mut out = vec![];
    for p in newest.values() {
        match packs::rules_for(app, &p.rules_hash).await {
            Ok(r) => out.push(r),
            Err(e) => tracing::warn!("admin: the rules of {}: {e}", p.pack_id),
        }
    }
    let classic = GameRules::classic();
    if !out.iter().any(|r| r.id == classic.id) {
        out.push(classic);
    }
    out.sort_by_key(|r| packs::short_name(r));
    Ok(out)
}

/// The game of a manifest id, or a 400.
async fn game(app: &AppRef, id: &str) -> Res<Arc<GameRules>> {
    let all = games(app).await.map_err(db_err)?;
    all.into_iter().find(|r| r.id == id).ok_or_else(|| bad("This server has no such game"))
}

/// English names of a game's cards (by id) and classes ("class:<ID>"): the pack's locales/en.json,
/// else the built-in card names; read once per rules hash.
pub async fn names(app: &AppRef, rules: &GameRules) -> Arc<HashMap<String, String>> {
    static CACHE: OnceLock<Mutex<HashMap<String, Arc<HashMap<String, String>>>>> = OnceLock::new();
    let cache = CACHE.get_or_init(Default::default);
    if let Some(n) = cache.lock().unwrap_or_else(|e| e.into_inner()).get(&rules.rules_hash) {
        return n.clone();
    }
    let en = if rules.rs.builtin { Value::Null } else { crate::stats::locale(app, &rules.rules_hash).await.unwrap_or(Value::Null) };
    let lib = Library::get();
    let title = |s: &str| s.split('_').map(|w| w[..1.min(w.len())].to_uppercase() + &w[1.min(w.len())..].to_lowercase()).collect::<Vec<_>>().join(" ");
    let mut m: HashMap<String, String> =
        rules.rs.cards.keys().map(|id| (id.clone(), en["cards"][id]["name"].as_str().map_or_else(|| lib.name(id), String::from))).collect();
    for c in &rules.rs.classes {
        m.insert(format!("class:{}", c.id), en["classes"][&c.id].as_str().map_or_else(|| title(&c.id), String::from));
    }
    let m = Arc::new(m);
    cache.lock().unwrap_or_else(|e| e.into_inner()).insert(rules.rules_hash.clone(), m.clone());
    m
}

/// What the panel shows of any deck: `{code, class, class_name, count, valid, cards: [{id, name, cost, n}]}`
/// (by cost, then name). `code` is null when a card is not in these rules.
pub fn deck_info(rs: &Ruleset, names: &HashMap<String, String>, hero: &str, cards: &[String]) -> Value {
    let mut counted: BTreeMap<&str, i64> = BTreeMap::new();
    for c in cards {
        *counted.entry(c).or_default() += 1;
    }
    let mut list: Vec<Value> = counted
        .into_iter()
        .map(|(c, n)| json!({"id": c, "name": names.get(c).cloned().unwrap_or_else(|| c.to_string()), "n": n, "cost": rs.cards.get(c).map(|x| x.cost)}))
        .collect();
    list.sort_by_key(|c| (c["cost"].as_i64().unwrap_or(99), c["name"].as_str().unwrap_or_default().to_string()));
    let class = rs.class_of_champion(hero).unwrap_or_default();
    let valid = Deck { hero: hero.into(), cards: cards.to_vec(), arena: false }.validate_in(rs);
    json!({"code": deck_code::encode(rs, hero, cards), "class": class, "class_name": names.get(&format!("class:{class}")),
           "count": cards.len(), "valid": valid.is_empty(), "problem": valid, "cards": list})
}

/// `deck_info` added to each `{hero, cards}` deck of a list (a replay's players, a tournament's decks).
pub async fn add_codes(app: &AppRef, rules_hash: &str, decks: &mut [Value]) {
    let Ok(rules) = packs::rules_for(app, rules_hash).await else { return };
    let names = names(app, &rules).await;
    for d in decks {
        let cards: Vec<String> = serde_json::from_value(d["cards"].clone()).unwrap_or_default();
        let info = deck_info(rules.rs, &names, d["hero"].as_str().unwrap_or_default(), &cards);
        if let (Some(o), Value::Object(i)) = (d.as_object_mut(), info) {
            o.extend(i); // (`cards` becomes the listed cards; the code is of the ids)
        }
    }
}

fn cards_of(d: &deck::Model) -> Vec<String> {
    serde_json::from_str(&d.cards).unwrap_or_default()
}

/// The account page's `games`: per game its ladder, the standing this season, the settings and the decks.
pub async fn games_json(app: &AppRef, id: i64) -> Result<Vec<Value>, sea_orm::DbErr> {
    let db = &app.db;
    let decks = deck::Entity::find().filter(deck::Column::Account.eq(id)).order_by_asc(deck::Column::Id).all(db).await?;
    let mut out = vec![];
    for g in games(app).await? {
        let l = &g.ladder;
        let (s, kept) = db::standing_now(db, id, &g.id, l).await?;
        let settings = game_setting::Entity::find_by_id((id, g.id.clone())).one(db).await?;
        let names = names(app, &g).await;
        let decks: Vec<Value> = decks
            .iter()
            .filter(|d| d.pack == g.id)
            .map(|d| {
                let mut v = deck_info(g.rs, &names, &d.hero, &cards_of(d));
                v["id"] = json!(d.id);
                v["name"] = json!(d.name);
                v["hero"] = json!(d.hero);
                v["updated"] = json!(d.updated);
                v
            })
            .collect();
        out.push(json!({
            "pack": g.id, "rules_hash": g.rules_hash, "name": packs::short_name(&g), "ranked": g.ranked,
            "ladder": {"ranks": l.ranks.iter().map(|r| json!({"rank": r.rank, "stars": r.stars})).collect::<Vec<_>>(), "legend": l.legend,
                       "start": {"rank": l.start.rank, "stars": l.start.stars}},
            "arena": {"wins": g.arena_wins, "losses": g.arena_losses},
            "standing": {"season": ranked::season_name(s.season), "kept": kept, "rank": s.rank, "stars": s.stars, "streak": s.streak,
                         "legend": db::legend_number(db, &s).await?, "ranked_mmr": s.ranked_mmr.round(), "casual_mmr": s.casual_mmr.round()},
            "settings": settings.and_then(|s| serde_json::from_str::<Value>(&s.value).ok()).unwrap_or_else(|| json!({})),
            "decks": decks,
        }));
    }
    Ok(out)
}

// --- shared steps -------------------------------------------------------------------------------

/// The account, if this admin may change it.
async fn target(app: &AppRef, a: &Admin, id: i64) -> Res<Account> {
    match db::account_by_id(&app.db, id).await {
        Ok(Some(t)) if may_manage(a, &t) => Ok(t),
        Ok(Some(_)) => Err(err(StatusCode::FORBIDDEN, "You may not change this account")),
        Ok(None) => Err(err(StatusCode::NOT_FOUND, "No such account")),
        Err(e) => Err(db_err(e)),
    }
}

/// Logs the change (kind `admin`, `data.action`, `data.target`) and answers `{ok, text}`.
fn done(app: &AppRef, a: &Admin, t: &Account, action: &str, text: String, mut data: Value) -> Response {
    tracing::info!("admin: {text}");
    data["action"] = json!(action);
    data["target"] = json!(t.id);
    app.event(a.ev(text.clone()).other(&t.name).data(data));
    Json(json!({"ok": true, "text": text})).into_response()
}

/// `me` to the player, if online, in the game of their last `me` (the rank they look at).
async fn push_me(app: &AppRef, id: i64) {
    let Some(pack) = app.hub().conns.get(&id).map(|c| c.me_pack.clone()) else { return };
    let Ok((rules, _)) = packs::playable(app, pack.as_deref(), None).await else { return };
    if let Ok(me) = me_json(&app.db, id, &rules).await {
        app.hub().send(id, &json!({"t": "me", "me": me}));
    }
}

/// All the player's decks (`decks {list}`, as asked without a pack), if online.
async fn push_decks(app: &AppRef, id: i64) {
    if !app.hub().conns.contains_key(&id) {
        return;
    }
    if let Ok(rows) = deck::Entity::find().filter(deck::Column::Account.eq(id)).order_by_asc(deck::Column::Id).all(&app.db).await {
        app.hub().send(id, &json!({"t": "decks", "list": rows.iter().map(deck_json).collect::<Vec<_>>()}));
    }
}

fn rank_text(r: Rank) -> String {
    if r.legend() { "Legend".into() } else { format!("Rank {} ({} stars)", r.rank, r.stars) }
}

// --- the standing -------------------------------------------------------------------------------

#[derive(Deserialize)]
struct StandingIn {
    pack: String,
    #[serde(default)]
    reset: bool,
    rank: Option<i64>,
    stars: Option<i64>,
    legend: Option<bool>,
    streak: Option<i64>,
    ranked_mmr: Option<f64>,
    casual_mmr: Option<f64>,
}

/// The new standing (the fields given over the old one), or why not.
fn edited(g: &GameRules, old: &db::Standing, f: &StandingIn) -> Result<db::Standing, String> {
    let l = &g.ladder;
    let mut s = old.clone();
    if !g.ranked && (f.rank.is_some() || f.stars.is_some() || f.legend.is_some() || f.streak.is_some()) {
        return Err("This game has no ranked ladder: only the MMRs can change".into());
    }
    if let Some(r) = f.rank {
        s.rank = r;
    }
    match f.legend {
        Some(true) => s.rank = ranked::LEGEND,
        Some(false) if s.rank == ranked::LEGEND => return Err("Give a rank to leave Legend".into()),
        _ => {}
    }
    if s.rank == ranked::LEGEND {
        if !l.legend {
            return Err("This ladder has no Legend".into());
        }
        s.stars = 0;
    } else {
        if !l.ranks.iter().any(|x| x.rank == s.rank) {
            let (lo, hi) = (l.ranks[0].rank, l.ranks[l.ranks.len() - 1].rank);
            return Err(format!("A rank is {hi}–{lo}{}", if l.legend { " (or Legend)" } else { "" }));
        }
        if let Some(n) = f.stars {
            s.stars = n;
        }
        let max = l.max_stars(s.rank);
        if !(0..=max).contains(&s.stars) {
            return Err(format!("Rank {} holds 0–{max} stars", s.rank));
        }
    }
    if let Some(n) = f.streak {
        if !(0..=1000).contains(&n) {
            return Err("A win streak is 0–1000".into());
        }
        s.streak = n;
    }
    for (v, to) in [(f.ranked_mmr, &mut s.ranked_mmr), (f.casual_mmr, &mut s.casual_mmr)] {
        if let Some(v) = v {
            if !(0.0..=10000.0).contains(&v) {
                return Err("An MMR is 0–10000".into());
            }
            *to = v;
        }
    }
    Ok(s)
}

async fn standing_edit(State(app): State<AppRef>, Extension(a): Extension<Admin>, Path(id): Path<i64>, Json(f): Json<StandingIn>) -> Response {
    let t = match target(&app, &a, id).await {
        Ok(t) => t,
        Err(r) => return r,
    };
    let g = match game(&app, &f.pack).await {
        Ok(g) => g,
        Err(r) => return r,
    };
    let db = &app.db;
    let r = async {
        let (old, _) = db::standing_now(db, id, &g.id, &g.ladder).await?;
        let new = if f.reset {
            standing::Entity::delete_by_id((id, g.id.clone(), old.season)).exec(db).await?;
            db::standing_now(db, id, &g.id, &g.ladder).await?.0
        } else {
            let new = match edited(&g, &old, &f) {
                Ok(s) => s,
                Err(why) => return Ok(Err(why)),
            };
            db::standing(db, id, &g.id, &g.ladder).await?; // the row, if it was not kept yet
            db::save_standing(db, &new).await?;
            new
        };
        Ok::<_, sea_orm::DbErr>(Ok((old, new)))
    };
    let (old, new) = match r.await {
        Ok(Ok(x)) => x,
        Ok(Err(why)) => return bad(why),
        Err(e) => return db_err(e),
    };
    push_me(&app, id).await;
    let show = |s: &db::Standing| json!({"rank": s.rank, "stars": s.stars, "streak": s.streak, "ranked_mmr": s.ranked_mmr, "casual_mmr": s.casual_mmr});
    let what = if f.reset { "reset to the season's start" } else { "set" };
    let text = format!(
        "{} {what} the standing of {} in {}: {} → {}, MMR {:.0}/{:.0}",
        a.me.name, t.name, g.id, rank_text(old.rank()), rank_text(new.rank()), new.ranked_mmr, new.casual_mmr
    );
    done(&app, &a, &t, "standing", text, json!({"pack": g.id, "season": ranked::season_name(new.season), "before": show(&old), "after": show(&new)}))
}

// --- the Arena run ------------------------------------------------------------------------------

#[derive(Deserialize)]
struct ArenaIn {
    /// "set" {wins, losses} | "end"
    action: String,
    #[serde(default)]
    wins: i64,
    #[serde(default)]
    losses: i64,
}

async fn arena_edit(State(app): State<AppRef>, Extension(a): Extension<Admin>, Path(id): Path<i64>, Json(f): Json<ArenaIn>) -> Response {
    let t = match target(&app, &a, id).await {
        Ok(t) => t,
        Err(r) => return r,
    };
    let db = &app.db;
    let run = match arena::Entity::find_by_id(id).one(db).await {
        Ok(Some(r)) => r,
        Ok(None) => return err(StatusCode::NOT_FOUND, "No Arena run"),
        Err(e) => return db_err(e),
    };
    let busy = {
        let hub = app.hub();
        hub.queue.get(&id).is_some_and(|s| s.mode == Mode::Arena)
            || hub.in_game.get(&id).and_then(|(g, _)| hub.games.get(g)).is_some_and(|g| g.mode == Mode::Arena)
    };
    if busy {
        return err(StatusCode::CONFLICT, "The player is in an Arena game or its queue: wait until it ends");
    }
    let before = json!({"wins": run.wins, "losses": run.losses});
    let (text, r) = match f.action.as_str() {
        "end" => (format!("{} ended the Arena run of {} ({}–{})", a.me.name, t.name, run.wins, run.losses), arena::Entity::delete_by_id(id).exec(db).await.map(|_| ())),
        "set" => {
            let g = match packs::rules_for(&app, &run.pack).await {
                Ok(g) => g,
                Err(e) => return bad(format!("The run's game is not on the server: {e}")),
            };
            if !(0..g.arena_wins).contains(&f.wins) || !(0..g.arena_losses).contains(&f.losses) {
                return bad(format!("A run goes on with 0–{} wins and 0–{} losses (End it instead)", g.arena_wins - 1, g.arena_losses - 1));
            }
            let r = arena::ActiveModel { account: Unchanged(id), wins: Set(f.wins), losses: Set(f.losses), ..Default::default() }.update(db).await;
            (format!("{} set the Arena run of {} to {}–{} (was {}–{})", a.me.name, t.name, f.wins, f.losses, run.wins, run.losses), r.map(|_| ()))
        }
        _ => return err(StatusCode::NOT_FOUND, "No such action"),
    };
    if let Err(e) = r {
        return db_err(e);
    }
    if let Ok(state) = arena_json(db, id).await {
        app.hub().send(id, &json!({"t": "arena", "state": state}));
    }
    push_me(&app, id).await;
    done(&app, &a, &t, "arena", text, json!({"arena": f.action, "before": before, "after": {"wins": f.wins, "losses": f.losses}}))
}

// --- settings and the tag -----------------------------------------------------------------------

#[derive(Deserialize)]
struct SettingsIn {
    pack: String,
    /// {key: text | null (removes it)}, as `game_settings_set`
    settings: Map<String, Value>,
}

async fn settings_edit(State(app): State<AppRef>, Extension(a): Extension<Admin>, Path(id): Path<i64>, Json(f): Json<SettingsIn>) -> Response {
    let t = match target(&app, &a, id).await {
        Ok(t) => t,
        Err(r) => return r,
    };
    let g = match game(&app, &f.pack).await {
        Ok(g) => g,
        Err(r) => return r,
    };
    let db = &app.db;
    let old = match game_setting::Entity::find_by_id((id, g.id.clone())).one(db).await {
        Ok(o) => o,
        Err(e) => return db_err(e),
    };
    let changes = Value::Object(f.settings.clone());
    let value = match merge_game_settings(old.as_ref().map_or("{}", |o| o.value.as_str()), f.settings) {
        Ok(v) => v,
        Err(e) => return bad(e.1),
    };
    let row = game_setting::ActiveModel { account: Set(id), pack: Set(g.id.clone()), value: Set(value.clone()), updated: Set(ranked::now()) };
    if let Err(e) = if old.is_some() { row.update(db).await.map(|_| ()) } else { row.insert(db).await.map(|_| ()) } {
        return db_err(e);
    }
    if let Ok(v) = game_settings_msg(db, id).await {
        app.hub().send(id, &v);
    }
    let text = format!("{} changed the settings of {} in {}: {changes}", a.me.name, t.name, g.id);
    done(&app, &a, &t, "game_settings", text, json!({"pack": g.id, "changes": changes, "value": serde_json::from_str::<Value>(&value).ok()}))
}

#[derive(Deserialize)]
struct TagIn {
    /// "" removes it
    tag: String,
}

async fn tag_edit(State(app): State<AppRef>, Extension(a): Extension<Admin>, Path(id): Path<i64>, Json(f): Json<TagIn>) -> Response {
    let t = match target(&app, &a, id).await {
        Ok(t) => t,
        Err(r) => return r,
    };
    let tag = f.tag.trim().to_string();
    if !tag.is_empty() && !auth::valid_tag(&tag) {
        return bad("A tag is 3 to 16 letters or digits");
    }
    let db = &app.db;
    let key = (!tag.is_empty()).then(|| tag.to_lowercase());
    if let Some(k) = &key {
        match account::Entity::find().filter(account::Column::TagKey.eq(k)).filter(account::Column::Id.ne(id)).one(db).await {
            Ok(Some(_)) => return err(StatusCode::CONFLICT, "This tag is taken"),
            Ok(None) => {}
            Err(e) => return db_err(e),
        }
    }
    let new = (!tag.is_empty()).then(|| tag.clone());
    // (a race with another taker: the unique index refuses the second)
    if let Err(e) = (account::ActiveModel { id: Unchanged(id), tag: Set(new), tag_key: Set(key), ..Default::default() }).update(db).await {
        return if e.to_string().contains("UNIQUE") { err(StatusCode::CONFLICT, "This tag is taken") } else { db_err(e) };
    }
    push_me(&app, id).await;
    let text = if tag.is_empty() { format!("{} removed the tag of {}", a.me.name, t.name) } else { format!("{} gave {} the tag {tag}", a.me.name, t.name) };
    done(&app, &a, &t, "tag", text, json!({"before": t.tag, "after": tag}))
}

// --- decks --------------------------------------------------------------------------------------

/// A deck name as kept (trimmed; 60 characters at most).
fn deck_name(n: &str) -> Res<String> {
    let n = n.trim();
    if n.chars().count() > 60 {
        return Err(bad("A deck name is at most 60 characters"));
    }
    Ok(n.to_string())
}

async fn room_for_one(app: &AppRef, who: &Account) -> Res<()> {
    match deck::Entity::find().filter(deck::Column::Account.eq(who.id)).count(&app.db).await {
        Ok(n) if n >= MAX_DECKS => Err(err(StatusCode::CONFLICT, &format!("{} has {MAX_DECKS} decks on this server: delete one first", who.name))),
        Ok(_) => Ok(()),
        Err(e) => Err(db_err(e)),
    }
}

async fn insert_deck(app: &AppRef, account: i64, pack: &str, name: &str, hero: &str, cards: &[String]) -> Result<deck::Model, sea_orm::DbErr> {
    let now = ranked::now();
    deck::ActiveModel {
        account: Set(account),
        pack: Set(pack.into()),
        name: Set(name.into()),
        hero: Set(hero.into()),
        cards: Set(json!(cards).to_string()),
        created: Set(now),
        updated: Set(now),
        ..Default::default()
    }
    .insert(&app.db)
    .await
}

#[derive(Deserialize)]
struct DeckAddIn {
    pack: String,
    code: String,
    #[serde(default)]
    name: String,
}

/// A new deck from a code (or Hearthstone's copied text), checked with the game's rules.
async fn deck_add(State(app): State<AppRef>, Extension(a): Extension<Admin>, Path(id): Path<i64>, Json(f): Json<DeckAddIn>) -> Response {
    let r = async {
        let t = target(&app, &a, id).await?;
        let g = game(&app, &f.pack).await?;
        if f.code.len() > 10_000 {
            return Err(bad("This is not a deck code"));
        }
        let d = deck_code::decode(g.rs, &f.code).map_err(bad)?;
        let name = deck_name(&f.name)?;
        let name = if name.is_empty() { d.name.clone().unwrap_or_else(|| "Imported deck".into()) } else { name };
        room_for_one(&app, &t).await?;
        let row = insert_deck(&app, id, &g.id, &name, &d.hero, &d.cards).await.map_err(db_err)?;
        push_decks(&app, id).await;
        let text = format!("{} added the deck \"{name}\" to {} in {}", a.me.name, t.name, g.id);
        Ok(done(&app, &a, &t, "deck_add", text, json!({"pack": g.id, "deck": row.id, "code": f.code.trim()})))
    };
    r.await.unwrap_or_else(|e| e)
}

#[derive(Deserialize, Default)]
#[serde(default)]
struct DeckActionIn {
    name: String,
    /// copy: the account name to copy to
    to: String,
}

/// rename {name} | delete | copy {to}: a deck of this account.
async fn deck_action(
    State(app): State<AppRef>,
    Extension(a): Extension<Admin>,
    Path((id, deck_id, action)): Path<(i64, i64, String)>,
    Json(f): Json<DeckActionIn>,
) -> Response {
    let r = async {
        let t = target(&app, &a, id).await?;
        let db = &app.db;
        let d = deck::Entity::find_by_id(deck_id).one(db).await.map_err(db_err)?.filter(|d| d.account == id);
        let d = d.ok_or_else(|| err(StatusCode::NOT_FOUND, "No such deck of this account"))?;
        let data = json!({"pack": d.pack, "deck": d.id, "name": d.name});
        let text = match action.as_str() {
            "rename" => {
                let name = deck_name(&f.name)?;
                deck::ActiveModel { id: Unchanged(d.id), name: Set(name.clone()), updated: Set(ranked::now()), ..Default::default() }
                    .update(db)
                    .await
                    .map_err(db_err)?;
                push_decks(&app, id).await;
                format!("{} renamed the deck \"{}\" of {} to \"{name}\"", a.me.name, d.name, t.name)
            }
            "delete" => {
                deck::Entity::delete_by_id(d.id).exec(db).await.map_err(db_err)?;
                push_decks(&app, id).await;
                format!("{} deleted the deck \"{}\" of {}", a.me.name, d.name, t.name)
            }
            "copy" => {
                let to = db::account_by_name(db, f.to.trim()).await.map_err(db_err)?.ok_or_else(|| err(StatusCode::NOT_FOUND, "No such account"))?;
                if !may_manage(&a, &to) {
                    return Err(err(StatusCode::FORBIDDEN, "You may not change that account"));
                }
                room_for_one(&app, &to).await?;
                let row = insert_deck(&app, to.id, &d.pack, &d.name, &d.hero, &cards_of(&d)).await.map_err(db_err)?;
                push_decks(&app, to.id).await;
                let text = format!("{} copied the deck \"{}\" of {} to {}", a.me.name, d.name, t.name, to.name);
                return Ok(done(&app, &a, &t, "deck_copy", text, json!({"pack": d.pack, "deck": d.id, "to": to.name, "to_id": to.id, "copy": row.id})));
            }
            _ => return Err(err(StatusCode::NOT_FOUND, "No such action")),
        };
        Ok(done(&app, &a, &t, &format!("deck_{action}"), text, data))
    };
    r.await.unwrap_or_else(|e| e)
}
