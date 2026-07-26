#!/bin/zsh
set -euo pipefail

ROOT="${0:A:h:h}"
WORKER="${ROOT}/Cloudflare/worker"
PROVISION_ENV="${SKJALDR_CLOUDFLARE_ENV:-${HOME}/.local/share/skjaldr-cloudflare.env}"
R2_ENV="${CLOUDFLARE_R2_ENV:-${HOME}/.local/share/cloudflare-r2.env}"
SIGNATURE_ENV="${SKJALDR_SIGNATURE_ENV:-${HOME}/.local/share/skjaldr-signature.env}"
APP_CONFIG="${HOME}/Library/Application Support/Skjaldr/cloud-upload.json"
API="https://api.cloudflare.com/client/v4"

for command_name in curl jq node npm openssl; do
    command -v "${command_name}" >/dev/null || {
        echo "Dependência ausente: ${command_name}" >&2
        exit 1
    }
done

"${ROOT}/Scripts/bootstrap-cloudflare.sh"
set -a
source "${R2_ENV}"
source "${PROVISION_ENV}"
source "${SIGNATURE_ENV}"
set +a
: "${PROFESSIONAL_SIGNATURE:?Defina PROFESSIONAL_SIGNATURE em ${SIGNATURE_ENV}}"
AUTH="Authorization: Bearer ${CLOUDFLARE_API_TOKEN}"

curl -fsS -H "${AUTH}" \
    "${API}/accounts/${CLOUDFLARE_ACCOUNT_ID}/tokens/verify" |
    jq -e '.success and .result.status == "active"' >/dev/null

ROOT_DNS="$(
    curl -fsS -H "${AUTH}" \
        "${API}/zones/${CLOUDFLARE_ZONE_ID}/dns_records?name=odin.med.br&per_page=100"
)"
if jq -e '.result[] | select(.type == "A" or .type == "CNAME")' \
    <<<"${ROOT_DNS}" >/dev/null; then
    echo "A raiz possui origem A/CNAME incompatível; nada foi alterado." >&2
    exit 1
fi

DOMAINS="$(
    curl -fsS -H "${AUTH}" \
        "${API}/accounts/${CLOUDFLARE_ACCOUNT_ID}/workers/domains?hostname=odin.med.br"
)"
if jq -e '.result[] | select(.service != "skjaldr-video")' \
    <<<"${DOMAINS}" >/dev/null; then
    echo "odin.med.br está associado a outro Worker; nada foi alterado." >&2
    exit 1
fi

MANAGED="$(
    curl -fsS -H "${AUTH}" \
        "${API}/accounts/${CLOUDFLARE_ACCOUNT_ID}/r2/buckets/skjaldr/domains/managed"
)"
CUSTOM="$(
    curl -fsS -H "${AUTH}" \
        "${API}/accounts/${CLOUDFLARE_ACCOUNT_ID}/r2/buckets/skjaldr/domains/custom"
)"
[[ "$(jq -r '.result.enabled' <<<"${MANAGED}")" == "false" ]] || {
    echo "O bucket skjaldr possui r2.dev público; desative-o antes do deploy." >&2
    exit 1
}
[[ "$(jq '[.result.domains[]?] | length' <<<"${CUSTOM}")" == "0" ]] || {
    echo "O bucket skjaldr possui domínio público; nada foi alterado." >&2
    exit 1
}

BUCKETS="$(
    curl -fsS -H "${AUTH}" \
        "${API}/accounts/${CLOUDFLARE_ACCOUNT_ID}/r2/buckets"
)"
if ! jq -e '.result.buckets[] | select(.name == "skjaldr")' \
    <<<"${BUCKETS}" >/dev/null; then
    curl -fsS -X POST -H "${AUTH}" -H "Content-Type: application/json" \
        --data '{"name":"skjaldr"}' \
        "${API}/accounts/${CLOUDFLARE_ACCOUNT_ID}/r2/buckets" >/dev/null
fi

DATABASES="$(
    curl -fsS -H "${AUTH}" \
        "${API}/accounts/${CLOUDFLARE_ACCOUNT_ID}/d1/database"
)"
D1_ID="$(
    jq -r '.result[] | select(.name == "skjaldr-videos") | .uuid' \
        <<<"${DATABASES}" | head -1
)"
if [[ -z "${D1_ID}" ]]; then
    D1_ID="$(
        curl -fsS -X POST -H "${AUTH}" -H "Content-Type: application/json" \
            --data '{"name":"skjaldr-videos"}' \
            "${API}/accounts/${CLOUDFLARE_ACCOUNT_ID}/d1/database" |
            jq -r '.result.uuid'
    )"
fi

cd "${WORKER}"
npm ci
sed \
    -e "s/__D1_DATABASE_ID__/${D1_ID}/g" \
    -e "s/__ACCOUNT_ID__/${CLOUDFLARE_ACCOUNT_ID}/g" \
    -e "s/__R2_BUCKET__/skjaldr/g" \
    -e "s|__PUBLIC_BASE_URL__|https://odin.med.br|g" \
    wrangler.template.jsonc >wrangler.generated.jsonc

APP_TOKEN=""
if [[ -f "${APP_CONFIG}" ]]; then
    APP_TOKEN="$(jq -r '.apiToken // empty' "${APP_CONFIG}")"
fi
if [[ -z "${APP_TOKEN}" ]]; then
    APP_TOKEN="$(openssl rand -hex 32)"
fi

mkdir -p "${APP_CONFIG:h}"
chmod 700 "${APP_CONFIG:h}"
umask 077
APP_TEMP="$(mktemp)"
SECRETS_TEMP="$(mktemp)"
trap 'rm -f "${APP_TEMP}" "${SECRETS_TEMP}"' EXIT
jq -n \
    --arg baseURL "https://odin.med.br" \
    --arg token "${APP_TOKEN}" \
    '{baseURL: $baseURL, apiToken: $token, uploadEnabled: true}' \
    >"${APP_TEMP}"
mv "${APP_TEMP}" "${APP_CONFIG}"
chmod 600 "${APP_CONFIG}"

jq -n \
    --arg app "${APP_TOKEN}" \
    --arg access "${AWS_ACCESS_KEY_ID}" \
    --arg secret "${AWS_SECRET_ACCESS_KEY}" \
    --arg signature "${PROFESSIONAL_SIGNATURE}" \
    '{APP_API_TOKEN:$app,R2_ACCESS_KEY_ID:$access,R2_SECRET_ACCESS_KEY:$secret,
      PROFESSIONAL_SIGNATURE:$signature}' \
    >"${SECRETS_TEMP}"

export CLOUDFLARE_API_TOKEN CLOUDFLARE_ACCOUNT_ID
npx wrangler d1 migrations apply skjaldr-videos --remote \
    --config wrangler.generated.jsonc
npx wrangler deploy --config wrangler.generated.jsonc \
    --secrets-file "${SECRETS_TEMP}"

echo "Cloudflare configurada:"
echo "  Worker: skjaldr-video"
echo "  Domínio: https://odin.med.br"
echo "  Bucket privado: skjaldr"
echo "  D1: skjaldr-videos"
echo "  App: ${APP_CONFIG}"
