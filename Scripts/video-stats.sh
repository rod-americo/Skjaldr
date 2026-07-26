#!/bin/zsh
set -euo pipefail

[[ "$#" -ge 1 && "$#" -le 2 ]] || {
    echo "Uso: ./Scripts/video-stats.sh 123-456" >&2
    echo "     ./Scripts/video-stats.sh --recent [quantidade]" >&2
    exit 2
}

if [[ "$1" == "--recent" ]]; then
    LIMIT="${2:-20}"
    [[ "${LIMIT}" == <-> && "${LIMIT}" -ge 1 && "${LIMIT}" -le 100 ]] || {
        echo "Quantidade inválida: use um valor entre 1 e 100." >&2
        exit 2
    }
else
    [[ "$#" -eq 1 ]] || {
        echo "Um código deve ser informado sem argumentos adicionais." >&2
        exit 2
    }
    RAW_CODE="${1##*/}"
    CODE="${RAW_CODE//-/}"
    [[ "${CODE}" == <-> && "${#CODE}" -eq 6 && "${CODE[1]}" != "0" ]] || {
        echo "Código inválido: ${RAW_CODE}" >&2
        exit 2
    }
fi

APP_CONFIG="${HOME}/Library/Application Support/Skjaldr/cloud-upload.json"
[[ -f "${APP_CONFIG}" ]] || {
    echo "Configuração do Skjaldr ausente: ${APP_CONFIG}" >&2
    exit 1
}

BASE_URL="$(jq -r '.baseURL' "${APP_CONFIG}")"
API_TOKEN="$(jq -r '.apiToken' "${APP_CONFIG}")"
HOSTNAME="${${BASE_URL#*://}%%/*}"
CURL=(curl)
PUBLIC_IP="$(dig @1.1.1.1 +short "${HOSTNAME}" A | head -1)"
[[ -n "${PUBLIC_IP}" ]] && CURL+=(--resolve "${HOSTNAME}:443:${PUBLIC_IP}")

if [[ "$1" == "--recent" ]]; then
    "${CURL[@]}" -fsS -G \
        -H "Authorization: Bearer ${API_TOKEN}" \
        --data-urlencode "limit=${LIMIT}" \
        "${BASE_URL}/api/stats/recent" |
        jq -r '
          ["CÓDIGO", "STATUS", "CRIADO EM", "VISUALIZAÇÕES", "INICIADAS", "CONCLUÍDAS"],
          (.videos[] | [
            .short_code,
            .status,
            .created_at,
            (.page_views | tostring),
            (.play_starts | tostring),
            (.play_completions | tostring)
          ]) | @tsv
        ' | column -t -s $'\t'
    exit 0
fi

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
