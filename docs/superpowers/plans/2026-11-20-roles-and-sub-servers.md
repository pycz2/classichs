# 0.74.0: roles and permissions, and sub-servers — the owner's request (2026-11-20)

(After 0.73.0, the megapack. Not started: the owner says when.)

## 1. Everything behind permissions

Every admin action and every admin view checks a permission — never "is admin". A role is a named set of
permissions; a user gets one or more roles; what he may do is the union. Roles are edited in the admin panel (by
whoever has the permission to manage roles), with ready-made roles to start from.

Permissions (a first, detailed list; each one guards both the API endpoint and the panel's view/button):

| Area | Permissions |
|---|---|
| Panel | `panel.open` (enter the admin panel at all), `dashboard.view` |
| Players | `players.view`, `players.edit` (name, tag, rating, rank), `players.ban`, `players.delete`, `players.decks.view`, `players.decks.edit` (add/copy decks, deck codes), `players.sessions.kick` |
| Invites | `invites.view`, `invites.create`, `invites.revoke` |
| Roles | `roles.view`, `roles.edit` (create/change roles and their permissions), `roles.assign` (give/take roles — only roles whose permissions the assigner has himself) |
| Games/packs | `packs.view`, `packs.upload`, `packs.enable`, `packs.delete`, `packs.default` (the default game) |
| Settings | `settings.view`, `settings.edit` (server name, registration mode, autobots, timers …) |
| Bots | `bots.view`, `bots.edit` (autobot levels, waits, tournament bots) |
| Tournaments | `tournaments.view`, `tournaments.create`, `tournaments.manage` (any tournament: pause, cancel, change), `tournaments.delete` |
| Chats | `chats.view` (tournament chats in the panel), `chats.write_as_admin`, `chats.moderate` (delete messages, mute) |
| Replays | `replays.view`, `replays.delete` |
| Stats | `stats.view` |
| Server info | `server.view` (version, storage sizes, logs) |
| Sub-servers (super level) | `subservers.view`, `subservers.create`, `subservers.suspend` (suspend / resume, available / unavailable), `subservers.delete`, `subservers.enter` (open any sub-server's panel with its settings), `admin_invites.create` (invites that make a sub-server admin), `superadmins.manage` |

Ready-made roles: **Super admin** (everything, all sub-servers), **Admin** (everything inside his own sub-server,
nothing at the super level), **Moderator** (players.view/ban, chats.*, tournaments.manage, replays.view), **Viewer**
(the `*.view` ones). A **player** has no role and no panel access; he plays.

Rules: the last super admin can't lose the role; a user can't give permissions he lacks; every change of roles,
permissions, bans and settings goes to an audit log (who, what, when, before → after), viewable with a permission.

## 2. Sub-servers

The server becomes a host of many game servers ("sub-servers"), all running at the same time:

- Today's admins become **super admins**; more super admins can be added.
- A super admin creates **admin invites**. Registering with such an invite makes the user the **admin of a new
  sub-server**: it gets its own address (a path or a sub-domain, e.g. `https://hs.borovilov.xyz/s/<name>` and the
  game's `wss://…/s/<name>`), its own players, games (packs), ladders and casual queues, tournaments, chats, replays,
  statistics, bots, invites and settings, and its own admin panel limited to it — everything today's server has.
- The admin manages only his sub-server (inside it his role is Admin; he can make his own moderators etc. with the
  roles of his sub-server).
- The super admin sees the list of sub-servers (state, admin, players online, storage), can **suspend/resume** a
  sub-server or an admin (a suspended sub-server refuses logins and games with a clear message), make it
  available/unavailable, enter any sub-server's panel and see all its settings.
- Players: an account belongs to one sub-server (the same name may exist on two sub-servers). The game client
  connects to a sub-server by its address (the "game servers" list takes the full address).
- Isolation: no data crosses sub-servers (separate DB per sub-server or a sub-server key on every table and every
  query — decide in the design; resource limits per sub-server: storage, packs, players, bots).
- The existing server's data becomes the first sub-server (or the "main" one) on upgrade, nothing lost.

## Decisions (the owner, 2026-11-20)

1. **One account for everything.** A person registers once and logs into any sub-server with that account (an
   account is global; what he has on each sub-server — rating, decks, stats, roles there — is per sub-server). The
   game's server list keeps the sub-server addresses; one login works for all of them.
2. **Addresses by path**: `https://hs.borovilov.xyz/s/<name>` (and the game's `wss://hs.borovilov.xyz/s/<name>`).
   No sub-domains, no wildcard certificate.
3. **Packs**: a common library the super admin offers to all sub-servers, plus each sub-server's own uploads.
4. **Limits are needed.** The super admin sets them: defaults for every sub-server and overrides per sub-server
   (storage, packs, players, bots, tournaments …). A sub-server's admin can configure his sub-server only within the
   limits the super admin gave him (he may set lower values, never higher).
5. **How many sub-servers a user may own**: a quota per user set by the super admin (an admin invite grants the first
   one; the user can create more sub-servers himself up to his quota). The super admin can change any user's quota at
   any time and suspend any of the sub-servers.

The account-level permissions this adds (super level): `quotas.edit` (sub-server quota per user), `limits.edit`
(defaults and per-sub-server limits); an admin gets `subservers.create_own` (within his quota) and `limits.view` of
his own sub-servers.

## 3. Problem reports from the game (the owner, 2026-11-20)

The owner's request: a player can send a message about a bug or a problem from the game client to the server; a
screenshot and a voice message can go with it; the server keeps the reports, and admins and super admins see them in
the admin panel.

- In the client: "Report a problem" in the main menu and in the match menu. A text field; a screenshot of the screen as
  it was before the window opened (attached by default, the player can remove it); a voice message recorded in the
  window (play back, record again, remove; the web asks for the microphone). Sent to the server the player is logged
  into.
- My proposals (the owner to confirm): the report carries the game's version, platform, screen size, language, the
  active pack and its version, and in a match the game's id (so the admin can open its replay); limits per report
  (text length, picture and voice size and length) and per player (a few reports per hour); a report made offline waits
  and is sent at the next login.
- On the server: a table of reports (player, time, text, attachments in the store, the context above, a state: new,
  seen, done, and an admin's note). Attachments are removed with the report; reports are kept as the chats are (the
  keeping time setting of the tournament chats plan, the super admin's).
- In the admin panel: a "Reports" page — a list with filters (state, player, version), a count of new ones on the
  dashboard, a report's page with the text, the picture, a player for the voice, the context and a link to the replay;
  change the state, write a note. Maybe later: an answer to the player as a private message.
- Also in a report (the owner, 2026-11-20): who wrote it (the account: name, tag, id), when it was written (the time on
  the player's device as he wrote it, and the time the server got it), and the player's last games: links to their
  replays in the admin panel (the last 5 finished games on that server, and the current one if sent from a match).
- Export (the owner, 2026-11-20): the "Reports" page downloads the reports (all, or those the filters show, or the
  ticked ones) as one zip: `reports.json` (every report with its fields, the context, the account, the times, the
  state and notes, the paths of its files inside the zip) and a folder per report with its screenshot (`.png`), its
  voice message (`.ogg`, Opus in Ogg: plays in browsers and common players) and the replays of its games (`.chsreplay`,
  the replay files the game opens). A plain JSON export (no files) too.
- Permissions: `reports.view`, `reports.manage` (state, note, delete), `reports.export`. With sub-servers: a report belongs to the
  sub-server it was sent to; that sub-server's admins see its reports, the super admin sees the reports of all
  sub-servers (with a sub-server filter).
