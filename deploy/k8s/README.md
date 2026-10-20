# Classic HS server on Kubernetes

Plain manifests (no Helm, no kustomize): the game server with its SQLite database on a
volume, a Service, an example Ingress, and an optional in-cluster S3 store (SeaweedFS).
The numbers behind the resources: `docs/server-profiling.md`.

| File | What |
|---|---|
| `deployment.yaml` | the server: 1 replica, `Recreate`, probes, resources, the volume at `/data` |
| `pvc.yaml` | `classichs-data`: the SQLite database (and the packs when there is no S3) |
| `service.yaml` | `classichs-server:7377` (WebSocket, `/packs`, `/admin`) |
| `secret.example.yaml` | `classichs-s3`: the S3 settings as environment variables (optional) |
| `ingress.example.yaml` | ingress-nginx with TLS and the WebSocket timeouts |
| `seaweedfs.yaml` | optional: SeaweedFS `weed mini` as the S3 store, with its own volume |

## Run

```sh
# the image: build it from the repository root and push it where the cluster can pull it
tools/build_packs.sh
docker build -f server/Dockerfile -t <registry>/classichs-server:0.28.1 . && docker push <registry>/classichs-server:0.28.1
# (then set that name in deployment.yaml)

kubectl create namespace classichs
cp deploy/k8s/secret.example.yaml secret.yaml   # edit; skip both lines to keep the packs on the volume
kubectl -n classichs apply -f secret.yaml
kubectl -n classichs apply -f deploy/k8s/seaweedfs.yaml      # only for the in-cluster S3
kubectl -n classichs apply -f deploy/k8s/pvc.yaml -f deploy/k8s/deployment.yaml -f deploy/k8s/service.yaml
kubectl -n classichs apply -f deploy/k8s/ingress.example.yaml  # after setting the host and TLS secret

# the superuser for the admin panel (asks for the password; the image has no shell, so this
# runs the server binary itself in the pod)
kubectl -n classichs exec -it deploy/classichs-server -- classichs-server admin root --db /data/classichs.db
```

The game connects to `wss://<host>`; the admin panel is `https://<host>/admin`.

## Why one replica, and `Recreate`

- Every live game is a task inside the process, holding the rules engine's state; the
  matchmaking queues, who is online and the friends' presence are in memory too. Two pods
  would be two separate worlds: players on one could not meet or see friends on the other.
- SQLite allows one writer, and the file must not be opened by two pods at once
  (`ReadWriteOnce` + `Recreate` makes sure the old pod is gone before the new one starts).
- So a rollout or a node drain ends the games being played. Players come back with their
  token (`resume`) as soon as the new pod is ready (about 0.3–0.5 s after start, a few
  seconds on the first start); their unfinished games are lost. Do upgrades when few play.
- One pod handles the load measured in `docs/server-profiling.md` (1 000 players in 500
  games at a fast test pace: ~0.8 of a core, 440 MiB); scale up the pod, not out.

## Resources

From the measurements (Linux container, `docker stats`):

| Players online (live games at a fast test pace) | requests | limits | measured |
|---|---|---|---|
| ≤ 100 (≤ 50) | `cpu: 250m`, `memory: 256Mi` | `memory: 512Mi` | 0.12 core, 53 MiB |
| ≤ 1 000 (≤ 500) — `deployment.yaml` | `cpu: "1"`, `memory: 512Mi` | `memory: 1536Mi` | 0.8 core, 440 MiB; p99 36 ms with 2 cores, 150–725 ms capped at 1 |
| ≤ 5 000 (≤ 1 000–2 000) | `cpu: "2"`, `memory: 1536Mi` | `memory: 3Gi` | 726 MiB with 5 000 idle; ~1.1 GiB with 1 000 games |

No CPU limit: the server is latency-sensitive (CFS throttling adds the rest of the 100 ms
period to a turn) and uses spare CPU only in bursts (logins, pack uploads, the hourly
event-log cleanup). The memory limit is mostly headroom for **password logins and
registrations**: each one is an argon2 hash that takes 19 MiB for ~20 ms, and nothing
caps how many run at once, so a burst of 50 simultaneous logins adds ~1 GB. Players
normally come back with `resume` (no hash), so bursts follow a server restart only when
many tokens expired; see the profiling doc before lowering the limit.

## Probes

`GET /admin` (the admin panel's page, served from the binary): the server answers it only
after the database is open, the bundled packs are installed and the default game is
loaded (0.3–0.7 s; ~1.4 s on the first start, which checks each bundled pack with a
trial game). `startupProbe` allows 2 minutes, for a slow S3 or a big uploaded pack set.

## Storage

- `classichs-data` (`/data`): `classichs.db` (+ `-wal`, `-shm`). Use block storage
  (`ReadWriteOnce`), not NFS/SMB: SQLite's WAL needs real file locks and shared memory.
  Growth: about 45 KB per finished game (the event log keeps every action 90 days, then
  the hourly prune frees the space for reuse), so the file settles at **≈ 4 MB × games
  per day**: 10 Gi is enough for ~2 500 games a day; 10 000 games a day need ~40 Gi.
  Back it up with `sqlite3 classichs.db ".backup x.db"` or a volume snapshot.
- Packs: in S3 when the secret sets `S3_BUCKET`, else in `/data/store` (Classic 43 MB +
  Neonfall 16 MB bundled, plus what players and admins upload: 100 MB per player pack, 10
  per player).

## S3

Any S3-compatible store works (requests are path-style; `http://` endpoints are allowed):
AWS S3 (leave `S3_ENDPOINT` empty), Cloudflare R2, Backblaze B2, an existing MinIO, or the
in-cluster SeaweedFS of `seaweedfs.yaml` (the same `weed mini` as `server/docker-compose.yml`:
one process, creates the bucket, ~210 MiB of memory idle). The bucket must exist. The server
reads a pack from S3 once per process (the default game at start, others when first played),
so S3 latency matters only then.

## Ingress

One replica, so no sticky sessions. Set the read/send timeouts high (the example: 1 hour):
the server and the game do not ping idle connections, and ingress-nginx closes a proxied
connection after 60 s without data by default, which would disconnect every player in the
menu. Pack uploads need `proxy-body-size: 128m`. The server runs with `--trust-proxy`: it
takes the client address (for the login rate limits and the event log) from the last
`X-Forwarded-For` entry, which ingress-nginx sets to the address it saw; behind a cloud L4
load balancer use `externalTrafficPolicy: Local` (or the PROXY protocol) on the ingress
controller, or every player shares the balancer's address and its 10 logins a minute.
The admin cookie gets `Secure` from `X-Forwarded-Proto: https`, which ingress-nginx sends.

The manifests pass `kubeconform -strict` (Kubernetes schemas).
