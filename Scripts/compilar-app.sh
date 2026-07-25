#!/bin/zsh
set -euo pipefail

RAIZ_PROJETO="${0:A:h:h}"
XCODE_PADRAO="/Applications/Xcode.app/Contents/Developer"
DESTINO_APP="${RAIZ_PROJETO}/dist/Skjaldr.app"
CATALOGO_RECURSOS="${RAIZ_PROJETO}/Resources/Assets.xcassets"
ENTITLEMENTS="${RAIZ_PROJETO}/Resources/Skjaldr.entitlements"
PLIST_PARCIAL="$(mktemp -t skjaldr-assetcatalog)"
CERTIFICADO_PADRAO="12BC7AE2E054A0921E900B23423EF7585A39D11F"
CERTIFICADO_ASSINATURA="${SKJALDR_CODESIGN_CERTIFICATE:-${CERTIFICADO_PADRAO}}"
BUNDLE_ID_ESPERADO="io.skjaldr.app"
TEAM_ID_ESPERADO="LCQ4JFLH3Z"
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
    grep -Fq "${CERTIFICADO_ASSINATURA}"; then
    echo "Certificado de assinatura não encontrado: ${CERTIFICADO_ASSINATURA}" >&2
    echo "Defina SKJALDR_CODESIGN_CERTIFICATE com o SHA-1 correto." >&2
    exit 1
fi

codesign \
    --force \
    --deep \
    --options runtime \
    --timestamp \
    --entitlements "${ENTITLEMENTS}" \
    --sign "${CERTIFICADO_ASSINATURA}" \
    "${DESTINO_APP}"
codesign --verify --deep --strict "${DESTINO_APP}"

IDENTIFICADOR_ASSINADO="$(
    codesign -dv --verbose=4 "${DESTINO_APP}" 2>&1 |
        sed -n 's/^Identifier=//p'
)"
TEAM_ASSINADO="$(
    codesign -dv --verbose=4 "${DESTINO_APP}" 2>&1 |
        sed -n 's/^TeamIdentifier=//p'
)"
REQUISITO_ASSINADO="$(
    codesign -dr - "${DESTINO_APP}" 2>&1 |
        sed -n 's/^designated => //p'
)"

if [[ "${IDENTIFICADOR_ASSINADO}" != "${BUNDLE_ID_ESPERADO}" ]]; then
    echo "Bundle ID assinado inesperado: ${IDENTIFICADOR_ASSINADO}" >&2
    exit 1
fi

if [[ "${TEAM_ASSINADO}" != "${TEAM_ID_ESPERADO}" ]]; then
    echo "Team ID assinado inesperado: ${TEAM_ASSINADO}" >&2
    exit 1
fi

if [[ -z "${REQUISITO_ASSINADO}" ]]; then
    echo "Não foi possível determinar a exigência designada do aplicativo." >&2
    exit 1
fi

ENTITLEMENTS_XML="$(
    codesign --display --entitlements - --xml "${DESTINO_APP}" 2>/dev/null
)"
if ! print -r -- "${ENTITLEMENTS_XML}" |
    grep -Fq '<key>com.apple.security.device.audio-input</key><true/>'; then
    echo "O entitlement de entrada de áudio não foi incorporado." >&2
    exit 1
fi

echo "Aplicação criada em: ${DESTINO_APP}"
echo "Certificado: ${CERTIFICADO_ASSINATURA}"
echo "Identidade: ${IDENTIFICADOR_ASSINADO} (${TEAM_ASSINADO})"
echo "Exigência designada: ${REQUISITO_ASSINADO}"
echo "Entrada de áudio autorizada pelo Hardened Runtime."

"${RAIZ_PROJETO}/Scripts/instalar-app.sh"
