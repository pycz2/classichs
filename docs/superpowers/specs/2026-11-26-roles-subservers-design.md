# 0.74.0: roles, sub-servers, problem reports, tournament chats — design

Plan (the owner's requests and decisions): docs/superpowers/plans/2026-11-20-roles-and-sub-servers.md (§1 roles and
permissions, §2 sub-servers + "Decisions", §3 problem reports, §4 tournament chats). This file fixes the names and the
data model so the parts can be built in parallel. Every agent reads it first.

## 1. Sub-server scope everywhere (built first, used by all)

- Table `subserver`: id (i64), name (the path part, `[a-z0-9-]{3,32}`, unique), title, owner (account id), state
  (`active` | `suspended` | `unavailable`), limits (JSON), created. **Row id 0 = "main"**: today's server; the migration
  creates it, and every existing row belongs to it.
- Every table that holds a sub-server's data gets `subserver: i64` (default 0): games, standings, decks, replays,
  tournaments, packs (own uploads; the common library = packs with `subserver = -1`), invites/signup keys, settings,
  events, bots, messages, and the new tables below. Every query filters by it (a helper `Scope { subserver: i64 }`
  carried in the request/connection; never a global query in sub-server code paths).
- Accounts are **global** (one login for every sub-server); what a player has on a sub-server (rating, rank, stars,
  standings, decks, stats, roles) is per sub-server.
- Addresses: `https://<host>/s/<name>/…` (admin panel `/s/<name>/admin`, websocket `wss://<host>/s/<name>/ws`); the
  bare `/` paths stay the main sub-server (old clients keep working). The client's server list stores the full URL.

## 2. Permissions (§1 of the plan)

- Table `role`: id, subserver (NULL = global, i.e. super level), name, perms (JSON list of permission names, `*` = all),
  builtin (bool). Built-in roles created by the migration: **Super admin** (global, `*`), and per sub-server **Admin**
  (every permission except the super level ones), **Moderator** (`players.view`, `players.ban`, `chats.*`,
  `tournaments.manage`, `replays.view`, `reports.view`, `reports.manage`), **Viewer** (every `*.view`).
- Table `account_role`: account, role, subserver (the scope the role is given in; NULL for global roles).
- Migration: accounts with `role = "admin"` today get Super admin; `account.role` stays for old code paths but is no
  longer read for permission checks.
- One check everywhere: `perm::has(app, account_id, "players.ban", subserver) -> bool` (global roles apply to every
  sub-server); `perm::all(..) -> BTreeSet<String>` for the panel. Every admin API endpoint declares its permission;
  the admin panel hides what the user lacks. A user can give only roles whose permissions he has; the last super admin
  can't lose the role.
- The permission names are the plan's table plus: `quotas.edit`, `limits.edit`, `limits.view`,
  `subservers.create_own`, `settings.retention`, `reports.view`, `reports.manage`, `reports.export`, `audit.view`.
- Table `audit`: id, at, account, subserver, action, target, before (JSON), after (JSON). Every change of roles,
  permissions, bans, settings, limits, quotas, sub-server states writes a row; `audit.view` shows it in the panel.

## 3. Problem reports (§3 of the plan, all proposals confirmed)

- Table `report`: id, subserver, account, written_at (client time), received_at, text, context (JSON: version,
  platform, screen size, language, pack id/version/rules_hash, game id when sent from a match), games (JSON: the last 5
  finished game ids on that sub-server + the current one), state (`new` | `seen` | `done`), note, answer_message (id of
  a private message sent back, if any). Files in the store: `reports/<id>/screen.png`, `reports/<id>/voice.ogg` (Opus in
  Ogg). Limits: text ≤ 4000 chars, picture ≤ 4 MB, voice ≤ 60 s / 1 MB, 5 reports per player per hour.
- Client: "Report a problem" in the main menu and the match menu; the screenshot taken before the window opens
  (attached, removable), voice recorded in the window (play, record again, remove; the web asks for the microphone); an
  offline report waits in user:// and is sent at the next login.
- Admin panel: a "Reports" page (filters: state, player, version; the count of new ones on the dashboard), a report's
  page (text, picture, voice player, context, links to the replays, state, note, "answer as a private message"),
  export: zip (`reports.json` + per report `screen.png`, `voice.ogg`, `<game>.chsreplay`) or plain JSON, of all / the
  filtered / the ticked ones.

## 4. Tournament chats (§4 of the plan)

- Table `chat_message`: id, subserver, channel (`tournaments` = the common chat of the tournaments list,
  `t:<tournament id>` = a tournament's own), account, text, at, deleted_by, deleted_at. A deleted message keeps its row;
  everyone sees "deleted by <moderator>" instead of the text.
- Live over the websocket (subscribe when the list / a tournament page is open); marks: inside a tournament "admin"
  (has `chats.moderate` there) and "creator"; in the list chat only "admin". A tournament's chat opens at creation and
  closes 10 minutes after its end (read-only then).
- Keeping: chats and private messages older than the keeping time are removed by a daily cleanup; the keeping time is
  a setting (`chat_keep_days`: 14 by default, any number of days, 0 = unlimited), editable only with
  `settings.retention` (super level).
- Admin panel: the chats (the list's and each tournament's), write as the admin (`chats.write_as_admin`), delete
  (`chats.moderate`).

## 5. Order and parallel work

1. Foundation (one agent): the `subserver` table + `subserver` columns + `Scope`, roles/permissions/audit, the path
   routing `/s/<name>/`, the admin panel's permission gating. Main stays the sub-server 0, so everything else keeps
   working.
2. In parallel, on top of the foundation's names (they may start before it lands, adding `subserver` to their own new
   tables and using `perm::has` as above): problem reports; tournament chats; then sub-server management (creating
   through admin invites, the quota per user, limits by the super admin with admins only lowering them, suspend /
   available, the super admin's list and "enter" any sub-server's panel, the common pack library + own packs).
