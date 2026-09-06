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

wait_for_http() {
  local url="$1"
  for _ in $(seq 1 30); do
    if curl -fsS -o /dev/null "$url"; then
      return 0
    fi
    sleep 2
  done
  echo "Timed out waiting for $url" >&2
  return 1
}

for path in / /health /app/ /vscode/; do
  wait_for_http "http://127.0.0.1:${PORT}${path}"
done

for port in 3000 8000 8443 27017; do
  docker exec "$CONTAINER" sh -c "nc -z 127.0.0.1 ${port}"
done

echo "Container page and port tests passed."
