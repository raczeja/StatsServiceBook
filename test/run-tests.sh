#!/usr/bin/env bash
set -euo pipefail

# run-tests.sh — build the test container, run it, execute functional tests,
# stop the container. Exits 0 on all pass, 1 on any failure.
#
# Usage (from repo root):
#   ./test/run-tests.sh
#
# Requires: Podman, Node.js >= 18, npm


TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT_DIR="$(dirname "$TEST_DIR")"
CONTAINER='stravame-tests'
IMAGE='stravame-test'
EXIT_CODE=0
HOST_PORT=""
CONTAINER_PORT=8080

# Detect runtime: prefer podman, fallback to docker
if command -v podman >/dev/null 2>&1; then
  CRUNNER='podman'
elif command -v docker >/dev/null 2>&1; then
  CRUNNER='docker'
else
  echo "Neither podman nor docker found. Install one to run tests." >&2
  exit 1
fi

echo "Using container runtime: $CRUNNER"

# Choose host port mapping. If STRAVA_TEST_PORT is set, use it; otherwise
# allocate a free ephemeral port on the host and bind it to container port.
if [ -n "${STRAVA_TEST_PORT:-}" ]; then
  HOST_PORT="$STRAVA_TEST_PORT"
else
  # Reserve a free TCP port on localhost
  if command -v python3 >/dev/null 2>&1; then
    HOST_PORT=$(python3 -c 'import socket,sys; s=socket.socket(); s.bind(("127.0.0.1",0)); print(s.getsockname()[1]); s.close()')
  else
    # Fallback: try to use /dev/tcp trick (may not work everywhere)
    HOST_PORT=$(( (RANDOM%16384) + 49152 ))
  fi
fi

PORT_MAPPING="-p ${HOST_PORT}:${CONTAINER_PORT}"

echo "==> Building production image 'stravame-prod' (context: $SCRIPT_DIR) ..."
$CRUNNER build -t stravame-prod "$SCRIPT_DIR"

echo "==> Building test image '$IMAGE' on top of 'stravame-prod' ..."
$CRUNNER build -f "$TEST_DIR/Containerfile" --build-arg BASE=stravame-prod -t "$IMAGE" "$SCRIPT_DIR"

echo "==> Starting container '$CONTAINER' on :$HOST_PORT ..."
$CRUNNER rm -f "$CONTAINER" >/dev/null 2>&1 || true
$CRUNNER run -d --name "$CONTAINER" $PORT_MAPPING "$IMAGE"

echo "==> Container listening on host port: $HOST_PORT"

echo "==> Waiting for httpd to become ready ..."
ready=false
for i in $(seq 1 20); do
  if curl -sSf --max-time 2 "http://localhost:${HOST_PORT}/strava/me/index.html" >/dev/null 2>&1; then
    ready=true
    break
  fi
  echo "  [$i] not yet ready ..."
  sleep 1
done

if [ "$ready" != true ]; then
  echo "==> Container logs:"
  $CRUNNER logs "$CONTAINER" || true
  echo "httpd did not become ready in 20 s" >&2
  $CRUNNER stop "$CONTAINER" >/dev/null 2>&1 || true
  $CRUNNER rm   "$CONTAINER" >/dev/null 2>&1 || true
  exit 1
fi
echo "   httpd is ready."

cleanup() {
  echo "==> Cleaning up..."
  $CRUNNER stop "$CONTAINER" >/dev/null 2>&1 || true
  $CRUNNER rm   "$CONTAINER" >/dev/null 2>&1 || true
}
trap cleanup EXIT

# Use local node_modules if present, otherwise install puppeteer into a temp dir
if [ -d "$TEST_DIR/node_modules/puppeteer" ]; then
  echo "==> Using local puppeteer from test/node_modules ..."
  export TEST_PORT="$HOST_PORT"
  node "$TEST_DIR/functional-tests.mjs" || EXIT_CODE=$?
else
  TMPDIR_NPM="$(mktemp -d)"
  trap 'cleanup; rm -rf "$TMPDIR_NPM"' EXIT
  echo "==> Installing puppeteer into $TMPDIR_NPM ..."
  pushd "$TMPDIR_NPM" >/dev/null
  npm init -y >/dev/null 2>&1
  npm install --no-audit --no-fund --silent puppeteer
  cp "$TEST_DIR/functional-tests.mjs" "$TMPDIR_NPM/functional-tests.mjs"
  export TEST_PORT="$HOST_PORT"
  node functional-tests.mjs || EXIT_CODE=$?
  popd >/dev/null
fi

# ---- Run shell unit tests inside the container ----------------------------
echo "==> Running shell unit tests ..."
$CRUNNER exec "$CONTAINER" sh /opt/shell-tests.sh || EXIT_CODE=$?

if [ "$EXIT_CODE" -ne 0 ]; then
  echo "";
  echo "==> Container logs (on test failure):"
  $CRUNNER logs "$CONTAINER" || true
fi

if [ "$EXIT_CODE" -eq 0 ]; then
  echo "All functional tests passed."
else
  echo "Functional tests FAILED (exit code $EXIT_CODE)."
fi

exit "$EXIT_CODE"
