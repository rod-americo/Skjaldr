#!/bin/zsh
set -euo pipefail

ROOT="${0:A:h:h}"
WORKER="${ROOT}/Cloudflare/worker"
ENV_FILE="${SKJALDR_CLOUDFLARE_ENV:-${HOME}/.local/share/skjaldr-cloudflare.env}"
[[ -f "${ENV_FILE}" ]] || {
    echo "Execute ./Scripts/setup-cloudflare.sh primeiro." >&2
    exit 1
}
set -a
source "${ENV_FILE}"
set +a
cd "${WORKER}"
npm ci
npm run check
npm test
npx wrangler d1 migrations apply skjaldr-videos --remote \
    --config wrangler.generated.jsonc
npx wrangler deploy --config wrangler.generated.jsonc
