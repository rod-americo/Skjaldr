#!/bin/zsh
set -euo pipefail

BOOTSTRAP_ENV="${CLOUDFLARE_BOOTSTRAP_ENV:-${HOME}/.local/share/cloudflare-r2.env}"
OUTPUT_ENV="${SKJALDR_CLOUDFLARE_ENV:-${HOME}/.local/share/skjaldr-cloudflare.env}"
API="https://api.cloudflare.com/client/v4"

if [[ -f "${OUTPUT_ENV}" ]]; then
    set -a
    source "${OUTPUT_ENV}"
    set +a
    curl -fsS \
        -H "Authorization: Bearer ${CLOUDFLARE_API_TOKEN}" \
        "${API}/accounts/${CLOUDFLARE_ACCOUNT_ID}/tokens/verify" |
        jq -e '.success and .result.status == "active"' >/dev/null
    echo "Token skjaldr-production já está ativo em ${OUTPUT_ENV}."
    exit 0
fi

[[ -f "${BOOTSTRAP_ENV}" ]] || {
    echo "Credenciais bootstrap ausentes: ${BOOTSTRAP_ENV}" >&2
    exit 1
}

set -a
source "${BOOTSTRAP_ENV}"
set +a
AUTH="Authorization: Bearer ${CLOUDFLARE_API_TOKEN}"

ZONE_ID="$(
    curl -fsS -G -H "${AUTH}" --data-urlencode "name=odin.med.br" \
        "${API}/zones" | jq -r '.result[0].id // empty'
)"
[[ -n "${ZONE_ID}" ]] || {
    echo "A zona odin.med.br não foi encontrada." >&2
    exit 1
}

if curl -fsS -H "${AUTH}" \
    "${API}/accounts/${CLOUDFLARE_ACCOUNT_ID}/tokens?per_page=50" |
    jq -e '.result[] | select(.name == "skjaldr-production")' >/dev/null; then
    echo "O token existe, mas seu segredo não está disponível localmente." >&2
    echo "Rotacione-o no painel ou remova-o antes de repetir o bootstrap." >&2
    exit 1
fi

GROUPS="$(
    curl -fsS -H "${AUTH}" \
        "${API}/accounts/${CLOUDFLARE_ACCOUNT_ID}/tokens/permission_groups"
)"
group_id() {
    jq -r --arg name "$1" \
        '.result[] | select(.name == $name) | .id' <<<"${GROUPS}" | head -1
}

PAYLOAD="$(
    jq -n \
        --arg account "${CLOUDFLARE_ACCOUNT_ID}" \
        --arg zone "${ZONE_ID}" \
        --arg a1 "$(group_id 'Account Settings Read')" \
        --arg a2 "$(group_id 'Workers Scripts Write')" \
        --arg a3 "$(group_id 'D1 Write')" \
        --arg a4 "$(group_id 'Workers R2 Storage Write')" \
        --arg z1 "$(group_id 'Zone Read')" \
        --arg z2 "$(group_id 'DNS Read')" \
        --arg z3 "$(group_id 'DNS Write')" \
        --arg z4 "$(group_id 'Workers Routes Read')" \
        --arg z5 "$(group_id 'Workers Routes Write')" \
        '{
          name: "skjaldr-production",
          policies: [
            {
              effect: "allow",
              resources: {("com.cloudflare.api.account." + $account): "*"},
              permission_groups: [
                {id: $a1}, {id: $a2}, {id: $a3}, {id: $a4}
              ]
            },
            {
              effect: "allow",
              resources: {("com.cloudflare.api.account.zone." + $zone): "*"},
              permission_groups: [
                {id: $z1}, {id: $z2}, {id: $z3}, {id: $z4}, {id: $z5}
              ]
            }
          ]
        }'
)"
RESPONSE="$(
    curl -fsS -X POST -H "${AUTH}" -H "Content-Type: application/json" \
        --data "${PAYLOAD}" \
        "${API}/accounts/${CLOUDFLARE_ACCOUNT_ID}/tokens"
)"
TOKEN="$(jq -r '.result.value // empty' <<<"${RESPONSE}")"
[[ -n "${TOKEN}" ]] || {
    echo "A Cloudflare não retornou o segredo do novo token." >&2
    exit 1
}

mkdir -p "${OUTPUT_ENV:h}"
umask 077
printf \
    'CLOUDFLARE_ACCOUNT_ID=%q\nCLOUDFLARE_ZONE_ID=%q\nCLOUDFLARE_API_TOKEN=%q\nCLOUDFLARE_R2_BUCKET=%q\nPUBLIC_BASE_URL=%q\n' \
    "${CLOUDFLARE_ACCOUNT_ID}" "${ZONE_ID}" "${TOKEN}" \
    "skjaldr" "https://odin.med.br" >"${OUTPUT_ENV}"
chmod 600 "${OUTPUT_ENV}"
echo "Token dedicado criado e salvo em ${OUTPUT_ENV}."
