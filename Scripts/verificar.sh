#!/bin/zsh
set -euo pipefail

RAIZ_PROJETO="${0:A:h:h}"
XCODE_PADRAO="/Applications/Xcode.app/Contents/Developer"

if [[ -d "${XCODE_PADRAO}" ]]; then
    export DEVELOPER_DIR="${DEVELOPER_DIR:-${XCODE_PADRAO}}"
fi

cd "${RAIZ_PROJETO}"
swift test
"${RAIZ_PROJETO}/Scripts/compilar-app.sh"

echo "Verificação concluída."
