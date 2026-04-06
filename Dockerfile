# ─────────────────────────────────────────────────────────────────────────────
# Custom shelfmark image — lean, non-root, Prowlarr-only variant.
#
# Removes: Tor, Supervisor, iptables, Chromium/Xvfb/SeleniumBase, gosu,
#          debug tools (zip, iputils-ping), SOCKS proxy support.
# Adds:    Fixed non-root user (uid/gid 1000 by default); override at runtime
#          via the `user:` field in docker-compose.yml.
#
# Build:
#   make build
#   make build UPSTREAM_TAG=v0.9.0
# ─────────────────────────────────────────────────────────────────────────────

ARG UPSTREAM_TAG=main
ARG BUILDPLATFORM
ARG TARGETPLATFORM

# ── Stage 1: Fetch upstream source ───────────────────────────────────────────
FROM alpine/git AS source

ARG UPSTREAM_TAG
RUN git clone --depth 1 --branch "${UPSTREAM_TAG}" \
        https://github.com/calibrain/shelfmark.git /src

# ── Stage 2: Build the React/Vite frontend ───────────────────────────────────
# Runs on the build host's native platform (faster for cross-compilation).
FROM --platform=$BUILDPLATFORM node:20-alpine AS frontend-builder

WORKDIR /frontend

COPY --from=source /src/src/frontend/package*.json ./

RUN --mount=type=cache,target=/root/.npm \
    npm ci

COPY --from=source /src/src/frontend/ ./

RUN npm run build

# ── Stage 3: Runtime image ───────────────────────────────────────────────────
FROM python:3.14-slim

ARG UPSTREAM_TAG
ARG BUILD_VERSION

# Expose both as env vars so the entrypoint can log them.
ENV UPSTREAM_TAG=${UPSTREAM_TAG} \
    BUILD_VERSION=${BUILD_VERSION}

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

ENV DEBIAN_FRONTEND=noninteractive \
    DOCKERMODE=true \
    PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1 \
    PYTHONIOENCODING=UTF-8 \
    PIP_NO_CACHE_DIR=1 \
    PIP_DISABLE_PIP_VERSION_CHECK=1 \
    PIP_DEFAULT_TIMEOUT=100 \
    PYTHONPATH=/app \
    LANG=en_US.UTF-8 \
    LANGUAGE=en_US:en \
    LC_ALL=en_US.UTF-8 \
    FLASK_PORT=8084 \
    # Disable the internal Chromium/SeleniumBase bypasser entirely.
    USING_EXTERNAL_BYPASSER=true \
    # Write logs inside the /config bind-mount so they survive restarts and
    # are accessible on the host without exec-ing into the container.
    # Override with LOG_ROOT=/var/log/ to keep the upstream default.
    LOG_ROOT=/config/

RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        locales \
        tzdata \
        curl \
        dumb-init && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/* && \
    # Locale
    sed -i '/en_US.UTF-8/s/^# //g' /etc/locale.gen && \
    locale-gen en_US.UTF-8 && \
    echo "LC_ALL=en_US.UTF-8" >> /etc/environment && \
    echo "LANG=en_US.UTF-8" > /etc/locale.conf && \
    # Default timezone (TZ env var overrides at runtime without root)
    ln -snf /usr/share/zoneinfo/UTC /etc/localtime && echo UTC > /etc/timezone

WORKDIR /app

# Install Python dependencies before copying source (better layer caching).
COPY requirements.txt ./
RUN --mount=type=cache,target=/root/.cache/pip \
    pip install -r requirements.txt

# Copy only what the app needs at runtime.
COPY --from=source /src/shelfmark ./shelfmark
COPY --from=source /src/data      ./data

# Copy built frontend assets.
COPY --from=frontend-builder /frontend/dist ./frontend-dist

# Copy our custom entrypoint.
COPY entrypoint.sh ./entrypoint.sh
RUN chmod +x /app/entrypoint.sh

# No named user is created. The process uid:gid is set entirely by the
# `user:` field in docker-compose.yml (or --user at runtime).
#
# /app contents: root-owned, world-readable (755/644 from COPY defaults).
# /config /books: will be bind-mounted; created world-writable here so the
#   image is functional for smoke tests without mounts.
# /tmp: always world-writable; used as HOME so any uid can write cache files.
RUN mkdir -p /config /books && chmod 1777 /config /books

EXPOSE ${FLASK_PORT}

HEALTHCHECK --interval=60s --timeout=60s --start-period=60s --retries=3 \
    CMD curl -sf "http://localhost:${FLASK_PORT}/api/health" > /dev/null || exit 1

# Run as an unprivileged user by default. Override at runtime with
# `user: "UID:GID"` in docker-compose.yml or `--user uid:gid` on the CLI.
# The image does not depend on this specific uid existing in /etc/passwd.
USER 1000:1000

ENTRYPOINT ["/usr/bin/dumb-init", "--"]
CMD ["/app/entrypoint.sh"]
