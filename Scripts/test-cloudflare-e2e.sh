#!/bin/zsh
set -euo pipefail
trap 'echo "E2E falhou na linha ${LINENO}." >&2' ZERR

APP_CONFIG="${HOME}/Library/Application Support/Skjaldr/cloud-upload.json"
for command_name in curl jq ffmpeg shasum dig; do
    command -v "${command_name}" >/dev/null || {
        echo "Dependência ausente: ${command_name}" >&2
        exit 1
    }
done
[[ -f "${APP_CONFIG}" ]] || {
    echo "Execute ./Scripts/setup-cloudflare.sh primeiro." >&2
    exit 1
}

BASE_URL="$(jq -r '.baseURL' "${APP_CONFIG}")"
API_TOKEN="$(jq -r '.apiToken' "${APP_CONFIG}")"
HOSTNAME="${${BASE_URL#*://}%%/*}"
CURL=(curl)
PUBLIC_IP="$(dig @1.1.1.1 +short "${HOSTNAME}" A | head -1)"
[[ -n "${PUBLIC_IP}" ]] || {
    echo "O domínio ainda não está disponível em DNS público." >&2
    exit 1
}
CURL+=(--resolve "${HOSTNAME}:443:${PUBLIC_IP}")
TEMP_DIR="$(mktemp -d)"
VIDEO="${TEMP_DIR}/synthetic.mp4"
trap 'rm -rf "${TEMP_DIR}"' EXIT

ffmpeg -y -v error -f lavfi -i "color=c=navy:s=320x180:d=1:r=24" \
    -f lavfi -i "sine=frequency=440:duration=1" \
    -c:v libx264 -pix_fmt yuv420p -c:a aac -movflags +faststart \
    -shortest "${VIDEO}"
SIZE="$(stat -f '%z' "${VIDEO}")"
SHA="$(shasum -a 256 "${VIDEO}" | awk '{print $1}')"
IDEMPOTENCY="$(uuidgen | tr '[:upper:]' '[:lower:]')"
AUTH="Authorization: Bearer ${API_TOKEN}"

CREATE="$(
    jq -n --arg key "${IDEMPOTENCY}" --arg sha "${SHA}" \
        --argjson size "${SIZE}" \
        '{idempotency_key:$key,content_type:"video/mp4",
          size_bytes:$size,duration_seconds:1,sha256:$sha}' |
        "${CURL[@]}" -fsS -X POST -H "${AUTH}" -H "Content-Type: application/json" \
            --data @- "${BASE_URL}/api/videos"
)"
ID="$(jq -r '.id' <<<"${CREATE}")"
PUBLIC_URL="$(jq -r '.public_url' <<<"${CREATE}")"
UPLOAD_URL="$(jq -r '.upload_url' <<<"${CREATE}")"
CONTENT_TYPE="$(jq -r '.upload_headers["Content-Type"]' <<<"${CREATE}")"
CHECKSUM="$(jq -r '.upload_headers["x-amz-checksum-sha256"]' <<<"${CREATE}")"

"${CURL[@]}" -fsS -X PUT -H "Content-Type: ${CONTENT_TYPE}" \
    -H "x-amz-checksum-sha256: ${CHECKSUM}" --data-binary "@${VIDEO}" \
    "${UPLOAD_URL}" >/dev/null
"${CURL[@]}" -fsS -X POST -H "${AUTH}" "${BASE_URL}/api/videos/${ID}/complete" |
    jq -e '.status == "available"' >/dev/null
"${CURL[@]}" -fsS "${PUBLIC_URL}" | grep -q "material complementar"
SHORT_CODE="$(jq -r '.short_code' <<<"${CREATE}")"
"${CURL[@]}" -fsS -X POST -H "Origin: ${BASE_URL}" \
    -H "User-Agent: Skjaldr-E2E-Mobile" \
    "${BASE_URL}/analytics/${SHORT_CODE}/play" >/dev/null
"${CURL[@]}" -fsS -X POST -H "Origin: ${BASE_URL}" \
    -H "User-Agent: Skjaldr-E2E-Mobile" \
    "${BASE_URL}/analytics/${SHORT_CODE}/complete" >/dev/null
for attempt in 1 2 3 4 5; do
    STATS="$("${CURL[@]}" -fsS -H "${AUTH}" \
        "${BASE_URL}/api/stats?code=${SHORT_CODE}")"
    if jq -e \
        '.totals.page_views >= 1 and .totals.play_starts == 1
         and .totals.play_completions == 1' <<<"${STATS}" >/dev/null; then
        break
    fi
    [[ "${attempt}" -lt 5 ]] || {
        echo "Estatísticas agregadas não foram persistidas." >&2
        exit 1
    }
    sleep 1
done
if grep -Eqi 'ip|user.?agent|city|latitude|longitude' <<<"${STATS}"; then
    echo "A API de estatísticas expôs um campo intrusivo." >&2
    exit 1
fi
RANGE_HEADERS="${TEMP_DIR}/range.headers"
"${CURL[@]}" -fsS -D "${RANGE_HEADERS}" -H "Range: bytes=0-255" \
    "${BASE_URL}/media/${SHORT_CODE}" >/dev/null
grep -q " 206 " "${RANGE_HEADERS}"
grep -qi '^content-range: bytes 0-255/' "${RANGE_HEADERS}"
"${CURL[@]}" -fsS -X POST -H "${AUTH}" \
    "${BASE_URL}/api/videos/${ID}/revoke" |
    jq -e '.status == "revoked"' >/dev/null
[[ "$("${CURL[@]}" -sS -o /dev/null -w '%{http_code}' "${PUBLIC_URL}")" == "410" ]]
"${CURL[@]}" -fsS -X DELETE -H "${AUTH}" "${BASE_URL}/api/videos/${ID}" |
    jq -e '.status == "deleted"' >/dev/null
echo "E2E aprovado: upload, analytics agregados, página, Range, revogação e limpeza."
