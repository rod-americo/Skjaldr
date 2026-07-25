#!/bin/zsh
set -euo pipefail

RAIZ_PROJETO="${0:A:h:h}"
XCODE_PADRAO="/Applications/Xcode.app/Contents/Developer"
DESTINO_APP="${RAIZ_PROJETO}/dist/Skjaldr.app"
CATALOGO_RECURSOS="${RAIZ_PROJETO}/Resources/Assets.xcassets"
PLIST_PARCIAL="$(mktemp -t skjaldr-assetcatalog)"
IDENTIDADE_PADRAO="Developer ID Application: Rodrigo Americo Cunha de Souza (LCQ4JFLH3Z)"
IDENTIDADE_ASSINATURA="${SKJALDR_CODESIGN_IDENTITY:-${IDENTIDADE_PADRAO}}"
trap 'rm -f "${PLIST_PARCIAL}"' EXIT

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

xcrun actool "${CATALOGO_RECURSOS}" \
    --compile "${DESTINO_APP}/Contents/Resources" \
    --platform macosx \
    --minimum-deployment-target 26.0 \
    --app-icon AppIcon \
    --output-partial-info-plist "${PLIST_PARCIAL}"

if ! security find-identity -v -p codesigning |
    grep -Fq "\"${IDENTIDADE_ASSINATURA}\""; then
    echo "Identidade de assinatura não encontrada: ${IDENTIDADE_ASSINATURA}" >&2
    echo "Defina SKJALDR_CODESIGN_IDENTITY com uma identidade válida." >&2
    exit 1
fi

codesign \
    --force \
    --deep \
    --options runtime \
    --timestamp \
    --sign "${IDENTIDADE_ASSINATURA}" \
    "${DESTINO_APP}"
codesign --verify --deep --strict "${DESTINO_APP}"

echo "Aplicação criada em: ${DESTINO_APP}"
echo "Assinatura: ${IDENTIDADE_ASSINATURA}"

"${RAIZ_PROJETO}/Scripts/instalar-app.sh"
