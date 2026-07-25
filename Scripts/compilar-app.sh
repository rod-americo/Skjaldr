#!/bin/zsh
set -euo pipefail

RAIZ_PROJETO="${0:A:h:h}"
XCODE_PADRAO="/Applications/Xcode.app/Contents/Developer"
DESTINO_APP="${RAIZ_PROJETO}/dist/Skjaldr.app"

if [[ -d "${XCODE_PADRAO}" ]]; then
    export DEVELOPER_DIR="${DEVELOPER_DIR:-${XCODE_PADRAO}}"
fi

cd "${RAIZ_PROJETO}"
swift build -c release --product Skjaldr

BINARIO="$(swift build -c release --show-bin-path)/Skjaldr"

rm -rf "${DESTINO_APP}"
mkdir -p "${DESTINO_APP}/Contents/MacOS" "${DESTINO_APP}/Contents/Resources"
cp "${BINARIO}" "${DESTINO_APP}/Contents/MacOS/Skjaldr"
cp "${RAIZ_PROJETO}/Resources/Info.plist" "${DESTINO_APP}/Contents/Info.plist"

codesign --force --deep --sign - "${DESTINO_APP}"
codesign --verify --deep --strict "${DESTINO_APP}"

echo "Aplicação criada em: ${DESTINO_APP}"
