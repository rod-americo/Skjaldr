#!/bin/zsh
set -euo pipefail

RAIZ_PROJETO="${0:A:h:h}"
ORIGEM_APP="${RAIZ_PROJETO}/dist/Skjaldr.app"
DESTINO_APP="/Applications/Skjaldr.app"

if [[ ! -d "${ORIGEM_APP}" ]]; then
    echo "Aplicação compilada não encontrada em ${ORIGEM_APP}." >&2
    echo "Execute ./Scripts/compilar-app.sh primeiro." >&2
    exit 1
fi

if pgrep -f "${DESTINO_APP}/Contents/MacOS/Skjaldr" >/dev/null; then
    echo "Encerre o Skjaldr antes de instalar uma nova versão." >&2
    exit 1
fi

if [[ -e "${DESTINO_APP}" ]]; then
    rm -rf "${DESTINO_APP}"
fi

ditto "${ORIGEM_APP}" "${DESTINO_APP}"
codesign --verify --deep --strict "${DESTINO_APP}"

echo "Aplicação instalada em: ${DESTINO_APP}"
echo "Abra esta cópia para manter estáveis as permissões do macOS."
