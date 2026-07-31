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

A native binary avoids the Docker daemon tax on a Mac Mini — GitHub no
longer ships raw binary releases, so grab one from
[openobserve.ai/downloads](https://openobserve.ai/downloads) and run it with
the same env vars as the Docker recipe below. Docker works identically if
the daemon is already running for something else — this exact recipe was
verified against a real OpenObserve 0.91.5 instance while building the
dashboards in step 4:

```bash
mkdir -p ~/openobserve/data
docker run -d --name openobserve --restart unless-stopped \
  -p 127.0.0.1:5080:5080 \
  -e ZO_ROOT_USER_EMAIL="you@example.com" \
  -e ZO_ROOT_USER_PASSWORD="ChooseAReal1!" \
  -e ZO_INGEST_ALLOWED_UPTO=8760 \
  -v "$HOME/openobserve/data:/data" \
  public.ecr.aws/zinclabs/openobserve:latest
```

Two hard requirements the server enforces at boot (it panics and exits
otherwise, not a friendly error): the email must look like a real address
— `user@example.com`, not `user@local` — and the password needs 8-128
chars with at least one uppercase, one lowercase, one digit, and one
special character.

**`ZO_INGEST_ALLOWED_UPTO` is not optional if you ever backfill.** Events
are indexed at the time the work actually happened (`observe_push.sh`
stamps `_timestamp` from each event's `ts`), and OpenObserve **discards**
anything older than this many hours — default 5. A producer that was
offline for a day, or a first push over existing history, is entirely
"too old" and lands nothing. The rejection arrives as HTTP 200 with
`failed` in the body, so it looks like success unless something reads the
body (`observe_push.sh` does, and holds its cursor). Set it generously:

```bash
-e ZO_INGEST_ALLOWED_UPTO=8760      # one year; pick whatever covers your history
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
O2_AUTH=you@example.com:ChooseAReal1!
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

## 4. Dashboards — one command, not fifteen panels by hand

```bash
O2_URL=https://<machine-name>.<tailnet>.ts.net O2_AUTH=you@example.com:ChooseAReal1! \
  ./scripts/observe_dashboards_import.sh
```

Imports all three prebuilt boards — **Tonight** (evening review), **The
Factory** (weekly trends), **Spec Economics** (the estimation board), 14
panels total — pre-wired to the right SQL, axes, and breakdowns. Run this
once per OpenObserve instance, from wherever the plugin lives (it reads
`templates/observability/dashboards/*.json` next to this file, not from a
project — dashboard setup is a store-level action, done once, not per
project). `--dry-run` lists what it would create without touching anything.

These files aren't hand-authored: `scripts/observe_dashboards_gen.py`
derives them from the SQL in `dashboards.md`, so the doc and the importable
JSON can't silently drift apart. Every panel was verified end-to-end against
a live instance — real events pushed via `observe_push.sh`, all 14 queries
confirmed error-free and returning real rows (see
`docs/observability-architecture.md`).

**One real gotcha, worth knowing before your first import looks broken:**
OpenObserve only creates a schema field once it has seen that key with a
*non-null* value at least once. A brand-new instance fed only a few events
will show "Search field not found" on panels for event types you haven't
hit yet — Gate postpones, PRs opened, LLM-layer errors. This is not a bug
in the dashboards; it self-resolves the first time each event type actually
fires (a real gate postpone, a real PR-open transition, a real API error).
Widen the time range (top right, default is 15 minutes) if a panel looks
empty on data you know exists — that's the far more common cause.

Want to customize a panel? Edit `dashboards.md`, then regenerate:
```bash
python3 scripts/observe_dashboards_gen.py \
  templates/observability/dashboards.md templates/observability/dashboards
```
(Python is a maintainer-only, build-time convenience here — nothing in the
loop itself ever depends on it.) The local `./scripts/observe_metrics.sh`
stays the source of truth for exact numbers regardless; the boards are the
glanceable view.
