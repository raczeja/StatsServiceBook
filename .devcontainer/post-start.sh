#!/usr/bin/env bash
set -euo pipefail

WORKSPACE_DIR="/workspaces/StatsServiceBook"
TEST_SCRIPT="$WORKSPACE_DIR/test/run-tests.sh"

echo "[devcontainer] post-start: ensuring test runner executable"
if [ -f "$TEST_SCRIPT" ]; then
  chmod +x "$TEST_SCRIPT" || true
else
  echo "[devcontainer] test runner not found at $TEST_SCRIPT"
  exit 0
fi

if [ "${RUN_TESTS:-"false"}" = "true" ] || [ "${RUN_TESTS:-"false"}" = "1" ]; then
  echo "[devcontainer] RUN_TESTS is set — starting test runner (logs follow)"
  pushd "$WORKSPACE_DIR" >/dev/null
  # Run in background so postStartCommand can finish; exit code isn't propagated
  bash "$TEST_SCRIPT" || echo "[devcontainer] test runner finished with non-zero exit code"
  popd >/dev/null
else
  echo "[devcontainer] RUN_TESTS not set — skipping automatic test run. To run tests manually:" \
       "chmod +x test/run-tests.sh && ./test/run-tests.sh"
fi
