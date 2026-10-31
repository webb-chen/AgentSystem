#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RUNNER_IMAGE="${RUNNER_IMAGE:-postgres:16-alpine}"
GOARCH_VALUE="${GOARCH_VALUE:-$(go env GOARCH)}"
TEST_BINARY="${TEST_BINARY:-/tmp/mingyingkeji-runner-linux-integration.test}"

cd "$ROOT_DIR"

CGO_ENABLED=0 GOOS=linux GOARCH="$GOARCH_VALUE" go test -tags=integration -c ./internal/runner -o "$TEST_BINARY"

docker run --rm \
  --privileged \
  -v "$TEST_BINARY:/runner.test" \
  "$RUNNER_IMAGE" \
  sh -lc 'apk add --no-cache bubblewrap python3 >/dev/null && MINGYINGKEJI_SANDBOX_TEST_SECURE_ROOTFS=/ MINGYINGKEJI_SANDBOX_TEST_BWRAP_BINARY=bwrap MINGYINGKEJI_SANDBOX_SECURE_RUNTIME_CPU_SECONDS=0 MINGYINGKEJI_SANDBOX_SECURE_RUNTIME_MEMORY_BYTES=0 MINGYINGKEJI_SANDBOX_SECURE_RUNTIME_PROCESS_LIMIT=0 MINGYINGKEJI_SANDBOX_SECURE_RUNTIME_OPEN_FILE_LIMIT=0 /runner.test -test.v -test.run "^TestLinuxSecureBackend"'
