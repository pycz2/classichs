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
