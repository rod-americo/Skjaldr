#!/bin/zsh
set -euo pipefail

[[ "$#" -eq 1 ]] || {
    echo "Uso: ./Scripts/video-stats.sh 123-456" >&2
    exit 2
}

APP_CONFIG="${HOME}/Library/Application Support/Skjaldr/cloud-upload.json"
[[ -f "${APP_CONFIG}" ]] || {
    echo "Configuração do Skjaldr ausente: ${APP_CONFIG}" >&2
    exit 1
}

RAW_CODE="${1##*/}"
CODE="${RAW_CODE//-/}"
[[ "${CODE}" == <-> && "${#CODE}" -eq 6 && "${CODE[1]}" != "0" ]] || {
    echo "Código inválido: ${RAW_CODE}" >&2
    exit 2
}

BASE_URL="$(jq -r '.baseURL' "${APP_CONFIG}")"
API_TOKEN="$(jq -r '.apiToken' "${APP_CONFIG}")"
HOSTNAME="${${BASE_URL#*://}%%/*}"
CURL=(curl)
PUBLIC_IP="$(dig @1.1.1.1 +short "${HOSTNAME}" A | head -1)"
[[ -n "${PUBLIC_IP}" ]] && CURL+=(--resolve "${HOSTNAME}:443:${PUBLIC_IP}")

"${CURL[@]}" -fsS -G \
    -H "Authorization: Bearer ${API_TOKEN}" \
    --data-urlencode "code=${CODE}" \
    "${BASE_URL}/api/stats" |
    jq '{
      codigo: .short_code,
      totais: {
        visualizacoes: .totals.page_views,
        reproducoes_iniciadas: .totals.play_starts,
        reproducoes_concluidas: .totals.play_completions
      },
      distribuicao_diaria: .daily
    }'
