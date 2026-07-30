# The export stack — OpenObserve on your machine, dashboards on your phone

The opt-in third plane of `docs/observability-architecture.md`: a single
lightweight store + dashboards, fed by `scripts/observe_push.sh`, reached
from anywhere through your tailnet. Everything below runs on the machine
that already runs the loop; nothing leaves it.

Platform choice, resource budget, and the losers table are in the
architecture doc §6–7. Short version: OpenObserve is one ~100–300 MB
process with embedded dashboards and a JSON-array ingest endpoint the
event log maps onto almost verbatim.

## 1. Run OpenObserve

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

Bind to `127.0.0.1` deliberately — the tailnet, not the LAN, is the way in.

To survive reboots on macOS, wrap the native binary in a LaunchAgent
(`~/Library/LaunchAgents/io.openobserve.plist`, `RunAtLoad` + `KeepAlive`)
or keep the Docker `--restart unless-stopped`.

## 2. Reach it from your phone

```bash
tailscale serve --bg 5080
```

The dashboard is now `https://<machine-name>.<tailnet>.ts.net` on every
device in your tailnet (Tailscale's personal plan covers this; the cert is
handled for you). No port forwarding, nothing exposed to the internet.

## 3. Feed it

```bash
# in the project's ./.env (gitignored — never commit credentials):
O2_URL=http://127.0.0.1:5080
O2_AUTH=you@example.com:choose-a-real-password
# optional: O2_ORG=default  O2_STREAM=agentic

/agentic-loop:config observability stack on
set -a; source ./.env; set +a
./scripts/observe_push.sh          # cursor-based; re-run any time
```

Schedule it however you like — a cron line, a LaunchAgent, or just run it
at the start of evening review. Push before `observe_prune.sh`: the push
reads live `.jsonl` files only.

## 4. Dashboards

Build the three boards from the queries in `dashboards.md` (one panel per
query, ~10 minutes total). The local `./scripts/observe_metrics.sh` stays
the source of truth for exact numbers — the boards are the glanceable view.
