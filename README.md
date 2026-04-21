# Watchtower

Local, self-hosted 24/7 home surveillance for the homelab. Replaces the
Tapo cloud app with a fully on-prem stack: RTSP ingest, event-driven
clipping, GPU-accelerated object detection, web UI, Telegram alerts,
and a markdown feed into the QMD memory layer.

**Status:** scaffold. Binaries compile and exit cleanly. No real
functionality yet — see the implementation roadmap below.

## Architecture

```
                          ┌────────────────┐
                          │   NATS bus     │  nats://127.0.0.1:4222
                          └──┬──┬──┬──┬────┘
       motion.*, detect.*,   │  │  │  │   clip.finalized, health.*
       camera.status.*       │  │  │  │
                             ▼  ▼  ▼  ▼
  ┌──────────┐   HLS    ┌────────┐
  │ Cameras  │─RTSP────▶│ relay  │────────▶  browser (HLS / WebRTC)
  │ (Tapo …) │          └────┬───┘
  └──────────┘               │  decoded frames (shm/socket)
                             ▼
                         ┌────────┐             ┌───────────┐
                         │detector│──detect.*──▶│ recorder  │─▶ /var/lib/watchtower/clips
                         └────────┘             └─────┬─────┘
                                                      │ clip.finalized
                                                      ▼
                                                 ┌────────┐
                                                 │  api   │─▶ REST / WS / Web UI (:7800)
                                                 └────┬───┘
                                                      │ per-session markdown
                                                      ▼
                                          ~/qmd-memory/watchtower/<date>/
                                          (QMD indexes this path)
```

Four independent binaries communicate over NATS pub/sub. Each has its
own systemd unit — if one crashes the others keep running.

### Architecture decisions

**NATS over Redis pub/sub.** Lighter footprint, native Go client,
better dead-subscriber handling, no persistence tax we don't need.
Runs as its own systemd unit (`nats-server.service`) — install from
[the official release](https://github.com/nats-io/nats-server/releases).

**go2rtc as a managed subprocess, not embedded.** Cleaner upgrade
path, well-packaged upstream binary, keeps its (chunky) dependency
tree out of our `go.mod`. Relay spawns and supervises it.

**Python sidecar for Tapo extras.** The `pytapo` library covers
siren/LED/PTZ/privacy calls that no mature Go equivalent handles.
Sidecar runs over a tiny localhost HTTP surface; documented in
`docs/tapo-quirks.md` once implemented.

## Layout

```
watchtower/
├── cmd/
│   ├── relay/       RTSP ingest + HLS/WebRTC fanout (wraps go2rtc)
│   ├── recorder/    Event-driven MP4 clipping (ffmpeg)
│   ├── detector/    YOLO via ONNX Runtime + CUDA
│   └── api/         REST + WebSocket + embedded web UI (:7800)
├── internal/
│   ├── bus/         NATS pub/sub abstraction
│   ├── config/      YAML config loader
│   └── version/     Build-time version stamp
├── deploy/systemd/  Unit files for all four binaries
├── docs/            Config example, quirks notes
├── web/             Embedded UI assets (empty for now)
└── Makefile
```

## Ports

| Port | Purpose                       |
|------|-------------------------------|
| 7800 | API + Web UI                  |
| 7801 | Reserved (WebRTC signalling)  |
| 4222 | NATS (loopback only)          |

## Development

```sh
go build ./...
make run      # runs all four in foreground, Ctrl-C stops all
```

Config lives at `~/.watchtower/config.yaml` — copy `docs/config.example.yaml`
and edit. Secrets go in `.env` (see `.env.example`), never in config.yaml.

## Production install (Debian Trixie)

```sh
# 1. NATS
# Download nats-server from GitHub releases, drop into /usr/local/bin,
# ship a systemd unit, enable it. Docs: https://docs.nats.io

# 2. Build + install watchtower
make build
sudo make install

# 3. Edit the systemd units to set User= / Group=
sudo systemctl edit --full watchtower-relay   # repeat for recorder/detector/api

# 4. Create the config
mkdir -p ~/.watchtower
cp docs/config.example.yaml ~/.watchtower/config.yaml
$EDITOR ~/.watchtower/config.yaml

# 5. Secrets
sudo install -m 0600 .env /etc/watchtower.env

# 6. Enable + start
sudo systemctl enable --now watchtower-{relay,recorder,detector,api}
```

System deps to install separately (`apt install`): `ffmpeg`, CUDA + cuDNN
for the RTX 4060 Ti, `nats-server` (from GitHub releases).
**Ask Michael before running any install.**

## Auth

- Tailscale (`100.64.0.0/10`) and LAN (`192.168.1.0/24`) are trusted by default.
- Everything else needs a bearer token. Token generated on first run of
  `watchtower-api` and stored in `config.yaml`.
- Siren / two-way audio / privacy toggles always require the token,
  regardless of network.

## QMD integration

Watchtower writes one markdown file per *session* (motion start → N
seconds of quiet → session end), not per detection. Files land at
`~/qmd-memory/watchtower/<YYYY-MM-DD>/<HH-MM-SS>-<camera>.md` and are
written atomically (`.tmp` → rename) so QMD never indexes a
half-written file.

Watchtower does **not** touch `~/.cache/qmd/` or try to write to
QMD's SQLite index. It only emits markdown; QMD picks it up on its
next index pass.

## Implementation roadmap

Per the project brief, implementation proceeds in this order, with a
checkpoint commit after each:

1. **relay** — go2rtc supervision, HLS endpoint, ONVIF motion subscribe
2. **recorder** — ring buffer + ffmpeg segment mux + clip finalize
3. **detector** — ONNX + CUDA YOLO, zone filter, detect events
4. **api** — REST + WebSocket + bearer auth
5. **UI** — live HLS player + clip browser + camera controls
6. **Tapo extras** — siren / LED / PTZ / privacy (pytapo sidecar)
7. **Alerts** — Telegram snapshot + preview, rate limiting, quiet hours
8. **QMD writer** — session grouping + markdown emitter
9. **Privacy schedule** — cron rules per camera

## Troubleshooting

Empty until we hit real issues worth writing down. Tapo-specific
oddities will land in `docs/tapo-quirks.md`.

## License

Private. Not for redistribution.
