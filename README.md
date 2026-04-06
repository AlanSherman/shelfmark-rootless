# shelfmark-rootless

A lean, rootless Docker image for [calibrain/shelfmark](https://github.com/calibrain/shelfmark), stripped down to a Prowlarr-only variant.

## What's changed from upstream

**Removed:**
- Tor / SOCKS proxy support
- Chromium, Xvfb, SeleniumBase (internal bypasser stack)
- Supervisor
- iptables
- `gosu` / runtime UID–GID switching
- Debug tools (`zip`, `iputils-ping`)

**Added / changed:**
- Fixed non-root user (uid/gid 1000) — override at runtime via the `user:` field in `docker-compose.yml`
- `USING_EXTERNAL_BYPASSER=true` — disables the internal bypass stack
- Logs written to `/config/shelfmark/` by default (survives restarts, accessible on the host)

## Image

Published to the GitHub Container Registry on every upstream release:

```
ghcr.io/AlanSherman/shelfmark-rootless:1.2.3
```

## Usage

```yaml
services:
  shelfmark:
    image: ghcr.io/OWNER/shelfmark-custom:latest
    user: "1000:1000"
    ports:
      - "8084:8084"
    volumes:
      - ./config:/config
    environment:
      - TZ=Europe/London
```

## Environment variables

| Variable | Default | Description |
|---|---|---|
| `FLASK_PORT` | `8084` | Port the web UI listens on |
| `FLASK_HOST` | `0.0.0.0` | Bind address |
| `LOG_ROOT` | `/config/` | Root directory for log files |
| `LOG_LEVEL` | `info` | Gunicorn log level |
| `UMASK` | `0022` | File creation mask |
| `ENABLE_LOGGING` | `true` | Tee startup messages to a log file |
| `DEBUG` | `false` | Enable debug logging |
| `TZ` | — | Timezone (e.g. `Europe/London`) |

## Building locally

```sh
# Build against upstream main
make build

# Build against a specific upstream tag
make build UPSTREAM_TAG=v0.9.0
```

## CI

- **`check-release.yml`** — runs daily; dispatches a build when a new upstream release is detected
- **`build.yml`** — builds and pushes multi-arch (`amd64`/`arm64`) images to `ghcr.io` on tag pushes and `workflow_dispatch`
