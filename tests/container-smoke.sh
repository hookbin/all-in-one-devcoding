#!/usr/bin/env bash
set -Eeuo pipefail

IMAGE="${IMAGE:-all-in-one-devcoding:test}"
CONTAINER="${CONTAINER:-all-in-one-devcoding-smoke}"
PORT="${PORT:-18000}"
TOTP_SECRET="${TOTP_SECRET:-JBSWY3DPEHPK3PXPJBSWY3DPEHPK3PXP}"
COOKIE_JAR="$(mktemp)"

cleanup() {
  docker logs "$CONTAINER" 2>&1 || true
  docker rm -f "$CONTAINER" >/dev/null 2>&1 || true
  rm -f "$COOKIE_JAR"
}
trap cleanup EXIT

docker rm -f "$CONTAINER" >/dev/null 2>&1 || true
docker run -d \
  --name "$CONTAINER" \
  -e "NGINX_TOTP_SECRET=${TOTP_SECRET}" \
  -p "${PORT}:8000" \
  "$IMAGE" >/dev/null

wait_for_http_200() {
  local url="$1"
  local status
  shift

  for _ in $(seq 1 30); do
    status="$(
      curl \
        --silent \
        --show-error \
        --connect-timeout 3 \
        --max-time 3 \
        --output /dev/null \
        --write-out "%{http_code}" \
        "$@" \
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

for path in / /health /app/; do
  wait_for_http_200 "http://127.0.0.1:${PORT}${path}"
done

for protected_path in /vscode /vscode/ /app/auth /app/auth/status; do
  unauthenticated_status="$(
    curl --silent --output /dev/null --write-out "%{http_code}" \
      "http://127.0.0.1:${PORT}${protected_path}"
  )"
  if [ "$unauthenticated_status" != "401" ]; then
    echo "Expected unauthenticated ${protected_path} request to return 401, got $unauthenticated_status" >&2
    exit 1
  fi
done

totp_code="$(
  docker exec "$CONTAINER" node -e \
    "console.log(require('/config/app/totp').generateTotp(process.env.NGINX_TOTP_SECRET))"
)"
authentication_status="$(
  curl \
    --silent \
    --show-error \
    --output /dev/null \
    --write-out "%{http_code}" \
    --cookie-jar "$COOKIE_JAR" \
    --request POST \
    --header "X-Nginx-TOTP: ${totp_code}" \
    "http://127.0.0.1:${PORT}/app/api/nginx/auth"
)"
if [ "$authentication_status" != "200" ]; then
  echo "Expected TOTP authentication to return 200, got $authentication_status" >&2
  exit 1
fi

wait_for_http_200 "http://127.0.0.1:${PORT}/vscode/" --cookie "$COOKIE_JAR"
wait_for_http_200 "http://127.0.0.1:${PORT}/app/auth/status" --cookie "$COOKIE_JAR"

for _ in $(seq 1 30); do
  health_status="$(docker inspect --format '{{.State.Health.Status}}' "$CONTAINER" 2>/dev/null || true)"
  if [ "$health_status" = "healthy" ]; then
    echo "Container health check passed."
    exit 0
  fi
  sleep 2
done

echo "Container health check did not become healthy; status: ${health_status:-unknown}" >&2
docker inspect "$CONTAINER" >&2 || true
exit 1
