# The export stack — OpenObserve on your always-on machine, dashboards on your phone

The opt-in third plane of `docs/observability-architecture.md`: a single
lightweight store + dashboards, fed by `scripts/observe_push.sh` from
every machine that runs a loop, reached from anywhere through your
tailnet — nothing ever exposed to the public internet.

The topology is producer/store split, and offline-first:

- **Producers** — the dev machine(s) running the factory. Capture always
  writes local JSONL, connected or not; `observe_push.sh` flushes to the
  store when it can reach it. Offline (or store down) = the cursor holds
  and the whole backlog flushes on the next successful run; nothing is
  lost, and `observe_prune.sh` refuses to rotate lines the store has not
  acknowledged.
- **Store** — the always-on box (a Mac Mini "own cloud" is exactly right).
  Runs OpenObserve, nothing else required.
- **Viewers** — any device in your tailnet, from ANY network: Tailscale
  connects across LANs and cellular, so the phone sees the dashboards away
  from home exactly as it does on the couch.

Platform choice, resource budget, and the losers table are in the
architecture doc §6–7. Short version: OpenObserve is one ~100–300 MB
process with embedded dashboards and a JSON-array ingest endpoint the
event log maps onto almost verbatim.

## 1. Run OpenObserve (on the always-on machine)

Native binary (preferred on a Mac Mini — no Docker daemon tax):

```bash
# download the darwin binary from https://github.com/openobserve/openobserve/releases
mkdir -p ~/openobserve/data
ZO_ROOT_USER_EMAIL="you@example.com" \
ZO_ROOT_USER_PASSWORD="choose-a-real-password" \
ZO_DATA_DIR="$HOME/openobserve/data" \
./openobserve
```

Or Docker, if the daemon is already running for something else:

```bash
docker run -d --name openobserve --restart unless-stopped \
  -p 127.0.0.1:5080:5080 \
  -e ZO_ROOT_USER_EMAIL="you@example.com" \
  -e ZO_ROOT_USER_PASSWORD="choose-a-real-password" \
  -v "$HOME/openobserve/data:/data" \
  public.ecr.aws/zinclabs/openobserve:latest
```

Bind to `127.0.0.1` deliberately — the tailnet, not the LAN, is the way in
(for both the phone AND the producers; see step 3).

To survive reboots on macOS, wrap the native binary in a LaunchAgent
(`~/Library/LaunchAgents/io.openobserve.plist`, `RunAtLoad` + `KeepAlive`)
or keep the Docker `--restart unless-stopped`.

## 2. Reach it from your phone

```bash
tailscale serve --bg 5080
```

The dashboard is now `https://<machine-name>.<tailnet>.ts.net` on every
device in your tailnet — **from any network**, not just your home LAN:
Tailscale tunnels over whatever internet the device has (the personal plan
covers this; the cert is handled for you). No port forwarding, nothing
exposed to the internet.

## 3. Feed it (from each machine that runs a loop)

```bash
# in the project's ./.env (gitignored — never commit credentials).
# O2_URL points at the STORE over the tailnet — the serve URL, or the
# machine's tailnet name with the raw port if you skip serve:
O2_URL=https://<machine-name>.<tailnet>.ts.net
O2_AUTH=you@example.com:choose-a-real-password
# optional: O2_ORG=default  O2_STREAM=agentic

/agentic-loop:config observability stack on
set -a; source ./.env; set +a
./scripts/observe_push.sh          # cursor-based; re-run any time
```

Schedule it however you like — a cron line, a LaunchAgent, or just run it
at the start of evening review. Connectivity is never a precondition:
capture is local-always, an unreachable store just holds the cursor
(`exit 1`, retry-not-loss), and the next successful push flushes the whole
backlog. Push before `observe_prune.sh` — and if you forget, prune holds
any file with unacknowledged lines rather than rotating it out from under
the push.

## 4. Dashboards

Build the three boards from the queries in `dashboards.md` (one panel per
query, ~10 minutes total). The local `./scripts/observe_metrics.sh` stays
the source of truth for exact numbers — the boards are the glanceable view.
