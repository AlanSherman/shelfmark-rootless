#!/bin/bash
# Simplified entrypoint for the custom shelfmark image.
#
# Removed from the upstream entrypoint:
#   - Tor launch logic (USING_TOR / tor.sh)
#   - Runtime UID/GID switching (gosu, PUID/PGID) — handled by Docker's
#     `user:` field in docker-compose.yml instead.
#   - Permission repair (chown, chmod tree walks)
#   - DEBUG Chromium/Xvfb introspection
#
# TZ: Docker passes TZ as an environment variable, which Python and glibc both
#     honour natively. Writing to /etc/localtime requires root and is skipped.
set -e

is_truthy() {
    case "${1,,}" in
        true|yes|1|y) return 0 ;;
        *) return 1 ;;
    esac
}

# ─── Optional: tee startup messages to a log file ────────────────────────────
# Gunicorn itself logs to stdout/stderr (captured by Docker's logging driver).
# This only covers the startup messages printed before exec.
# Log directory defaults to /config/shelfmark/ — set LOG_ROOT to override.
ENABLE_LOGGING_VALUE="${ENABLE_LOGGING:-true}"
TEE_PID=""
LOG_PIPE_DIR=""
LOG_PIPE=""

if is_truthy "$ENABLE_LOGGING_VALUE"; then
    LOG_DIR="${LOG_ROOT:-/var/log/}shelfmark"
    mkdir -p "$LOG_DIR"
    LOG_FILE="${LOG_DIR}/shelfmark_entrypoint.log"
    [ -f "${LOG_FILE}.prev" ] && rm -f "${LOG_FILE}.prev"
    [ -f "$LOG_FILE" ]       && mv "$LOG_FILE" "${LOG_FILE}.prev"

    LOG_PIPE_DIR="$(mktemp -d)"
    LOG_PIPE="${LOG_PIPE_DIR}/shelfmark-log.pipe"
    mkfifo "$LOG_PIPE"
    tee -a "$LOG_FILE" < "$LOG_PIPE" &
    TEE_PID=$!
    exec 3>&1 4>&2
    exec > "$LOG_PIPE" 2>&1
fi

echo "Starting shelfmark"
echo "Upstream version : ${UPSTREAM_TAG:-unknown}"
echo "Build version    : ${BUILD_VERSION:-unknown}"
echo "Running as       : $(id)"

# ─── /tmp sanity check ───────────────────────────────────────────────────────
echo "Verifying /tmp is writable"
if ! dd if=/dev/zero of=/tmp/test.shelfmark bs=1M count=1 2>/dev/null || \
   [ "$(wc -c < /tmp/test.shelfmark)" -ne 1048576 ]; then
    echo "Error: /tmp is not writable or has insufficient space"
    exit 1
fi
rm -f /tmp/test.shelfmark
echo "OK"

# ─── umask ───────────────────────────────────────────────────────────────────
UMASK_VALUE="${UMASK:-0022}"
umask "$UMASK_VALUE"
echo "umask: $UMASK_VALUE"

# ─── Build gunicorn command ──────────────────────────────────────────────────
gunicorn_loglevel="$([ "$DEBUG" = "true" ] && echo debug || echo "${LOG_LEVEL:-info}" | tr '[:upper:]' '[:lower:]')"

command="gunicorn \
  --log-level ${gunicorn_loglevel} \
  --access-logfile - \
  --error-logfile - \
  --worker-class geventwebsocket.gunicorn.workers.GeventWebSocketWorker \
  --workers 1 \
  -t 300 \
  -b ${FLASK_HOST:-0.0.0.0}:${FLASK_PORT:-8084} \
  shelfmark.main:app"

echo "Running: $command"

# ─── Stop log tee before exec ────────────────────────────────────────────────
# Gunicorn output goes to Docker's logging driver (stdout/stderr) directly.
if [ -n "$TEE_PID" ]; then
    exec 1>&3 2>&4
    exec 3>&- 4>&-
    rm -f "$LOG_PIPE"
    rmdir "$LOG_PIPE_DIR" 2>/dev/null || true
    wait "$TEE_PID" 2>/dev/null || true
fi

# HOME=/tmp is always writable regardless of which uid:gid the container runs
# as, so Python and any libraries that try to write user-cache files won't
# error. /app is root-owned and not writable by arbitrary uids.
exec env HOME=/tmp $command
