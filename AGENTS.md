# Agents guide — Watchtower

This file is for Claude / clawd sessions working on this repo. Read it
before making changes.

## What this is

Local home surveillance stack running on Michael's Debian Trixie
homelab. Four Go binaries (`relay`, `recorder`, `detector`, `api`)
coordinating over a NATS bus. Replaces the Tapo cloud app end-to-end.
See `README.md` for architecture and ports.

## Status

Scaffold. All four `cmd/*` binaries compile, parse `--config` and
`--version`, and exit cleanly on SIGINT/SIGTERM. Nothing else works
yet. Implementation order is fixed:

```
relay → recorder → detector → api → UI → Tapo extras → alerts → QMD writer → privacy schedule
```

Do not jump ahead. Each stage ends with a checkpoint commit.

## Ground rules (hard)

- **Ask before installing system-level deps** — ffmpeg, CUDA, cuDNN,
  nats-server, pytapo, ONNX Runtime native libs. Never `apt install`
  without Michael's explicit go-ahead in the current session.
- **Ask before creating anything under `/var`, `/etc`, or `/usr`.**
- **Never touch network config** — no iptables, no routes, no DNS, no
  VPN changes. Ever.
- **Never restart existing systemd units** outside this project. The
  `make install` target reloads only the watchtower units.
- **Never touch `~/.cache/qmd/`** — that's QMD's index. Watchtower is
  a producer of markdown files only; QMD owns indexing.
- **Credentials and camera IPs** — stop and ask. Do not invent
  placeholders and keep going.

## Ground rules (soft)

- **Commit after each working milestone** with a clear message. Prefer
  many small commits over one giant one.
- **Tapo API rabbit holes** — document the weirdness in
  `docs/tapo-quirks.md` and move on. Don't let an undocumented oddity
  stall a milestone.
- Keep the four binaries genuinely independent. If one crashes, the
  others must keep running.
- The message bus is the ONLY coordination mechanism between binaries.
  No shared SQLite, no shared files (except clips + markdown outputs
  which are one-writer).

## QMD integration — critical details

The surveillance → memory path works ONLY via markdown files:

- One file per **session**, not per detection. A session starts when
  motion begins and ends after N seconds of quiet (default 10s).
- Path: `~/qmd-memory/watchtower/<YYYY-MM-DD>/<HH-MM-SS>-<camera>.md`.
  Output root is configurable; `~/qmd-memory/watchtower` is the default.
- Write `.tmp` first, then `rename(2)` into place. Never leave a
  half-written file in the indexed directory.
- Every file must contain the literal line `**Source:** watchtower`
  so QMD queries can filter by source.
- File structure (exact) is pinned in the project brief — see the
  `## Narrative` + `## Detections` + `## Tags` layout. Deviating
  breaks both BM25 and semantic recall.
- Narrative is templated prose generated from detection data. No LLM
  call in v1.
- **Do not try to write to QMD's SQLite index.** QMD has no write API;
  stop anyone who suggests adding one.

## Directory ownership

| Path                             | Who writes            | Agents reading |
|----------------------------------|-----------------------|----------------|
| `~/projects/watchtower/`         | Michael + this agent  | anyone         |
| `~/.watchtower/config.yaml`      | `watchtower-api` + Michael | read-only |
| `/var/lib/watchtower/clips/`     | `watchtower-recorder` | read-only      |
| `~/qmd-memory/watchtower/`       | `watchtower-api` (or dedicated session writer) | read via QMD only |
| `~/.cache/qmd/`                  | QMD only              | do not touch   |

## Ports in play on this host

Claimed elsewhere: 2020 (Tapo C230), 7654, 7777, 7780, 8001, 8200.
Watchtower owns: **7800** (API + UI), **7801** (reserved for WebRTC
signalling). NATS stays on loopback `127.0.0.1:4222`.

## Useful commands (once built on the homelab)

```sh
# Build + install
make build
sudo make install

# Tail a specific binary
journalctl -u watchtower-relay -f

# Reload config on all four
sudo systemctl reload watchtower-{relay,recorder,detector,api}
```

## If Watchtower looks broken

Units failed, cameras offline >2 min, disk near full, QMD not seeing
new session files: log a P2 observation and tell Michael.
**Do not attempt repair without asking.**
