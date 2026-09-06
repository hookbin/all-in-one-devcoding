#!/usr/bin/env bash
set -Eeuo pipefail

IMAGE="${IMAGE:-all-in-one-devcoding:test}"
CONTAINER="${CONTAINER:-all-in-one-devcoding-smoke}"
PORT="${PORT:-18000}"

cleanup() {
  docker logs "$CONTAINER" 2>&1 || true
  docker rm -f "$CONTAINER" >/dev/null 2>&1 || true
}
trap cleanup EXIT

docker rm -f "$CONTAINER" >/dev/null 2>&1 || true
docker run -d \
  --name "$CONTAINER" \
  -p "${PORT}:8000" \
  "$IMAGE" >/dev/null

wait_for_http_200() {
  local url="$1"
  local status

  for _ in $(seq 1 30); do
    status="$(
      curl \
        --silent \
        --show-error \
        --connect-timeout 3 \
        --max-time 3 \
        --output /dev/null \
        --write-out "%{http_code}" \
        "$url" || true
    )"
    if [ "$status" = "200" ]; then
      return 0
    fi
    sleep 2
  done

  echo "Expected HTTP 200 from $url, got $status" >&2
  docker ps -a >&2 || true
  docker logs "$CONTAINER" >&2 || true
  return 1
}

for path in / /health /app/ /vscode/; do
  wait_for_http_200 "http://127.0.0.1:${PORT}${path}"
done

echo "Container HTTP 200 tests passed."
