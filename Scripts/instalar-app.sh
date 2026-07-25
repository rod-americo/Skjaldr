#!/bin/zsh
set -euo pipefail

RAIZ_PROJETO="${0:A:h:h}"
ORIGEM_APP="${RAIZ_PROJETO}/dist/Skjaldr.app"
DESTINO_APP="/Applications/Skjaldr.app"
TEMPORARIO_INSTALACAO=""
APP_TEMPORARIO=""
APP_ANTERIOR=""
BUNDLE_ID_ESPERADO="io.skjaldr.app"
TEAM_ID_ESPERADO="LCQ4JFLH3Z"

requisito_designado() {
    codesign -dr - "$1" 2>&1 | sed -n 's/^designated => //p'
}

limpar_temporario() {
    if [[ -n "${TEMPORARIO_INSTALACAO}" &&
          -d "${TEMPORARIO_INSTALACAO}" ]]; then
        rm -rf "${TEMPORARIO_INSTALACAO}"
    fi
}

identificador_assinado() {
    codesign -dv --verbose=4 "$1" 2>&1 | sed -n 's/^Identifier=//p'
}

team_assinado() {
    codesign -dv --verbose=4 "$1" 2>&1 | sed -n 's/^TeamIdentifier=//p'
}

restaurar_anterior() {
    if [[ -n "${APP_ANTERIOR}" && -e "${APP_ANTERIOR}" ]]; then
        if [[ -e "${DESTINO_APP}" ]]; then
            rm -rf "${DESTINO_APP}"
        fi
        mv "${APP_ANTERIOR}" "${DESTINO_APP}"
    fi
}

trap limpar_temporario EXIT

if [[ ! -d "${ORIGEM_APP}" ]]; then
    echo "Aplicação compilada não encontrada em ${ORIGEM_APP}." >&2
    echo "Execute ./Scripts/compilar-app.sh primeiro." >&2
    exit 1
fi

if pgrep -f "${DESTINO_APP}/Contents/MacOS/Skjaldr" >/dev/null; then
    echo "Encerre o Skjaldr antes de instalar uma nova versão." >&2
    exit 1
fi

codesign --verify --deep --strict "${ORIGEM_APP}"
if [[ "$(identificador_assinado "${ORIGEM_APP}")" != "${BUNDLE_ID_ESPERADO}" ||
      "$(team_assinado "${ORIGEM_APP}")" != "${TEAM_ID_ESPERADO}" ]]; then
    echo "A origem não possui o Bundle ID e o Team ID esperados." >&2
    exit 1
fi

REQUISITO_ORIGEM="$(requisito_designado "${ORIGEM_APP}")"
if [[ -z "${REQUISITO_ORIGEM}" ]]; then
    echo "A origem não possui uma exigência designada válida." >&2
    exit 1
fi

if [[ -e "${DESTINO_APP}" ]]; then
    codesign --verify --deep --strict "${DESTINO_APP}"
    REQUISITO_INSTALADO="$(requisito_designado "${DESTINO_APP}")"
    if [[ "${REQUISITO_INSTALADO}" != "${REQUISITO_ORIGEM}" ]]; then
        echo "Instalação recusada: a identidade do novo app é diferente." >&2
        echo "Instalado: ${REQUISITO_INSTALADO}" >&2
        echo "Novo:      ${REQUISITO_ORIGEM}" >&2
        echo "Isso invalidaria as permissões de gravação do macOS." >&2
        exit 1
    fi
fi

TEMPORARIO_INSTALACAO="$(mktemp -d /Applications/.skjaldr-install.XXXXXX)"
APP_TEMPORARIO="${TEMPORARIO_INSTALACAO}/Skjaldr.app"
APP_ANTERIOR="${TEMPORARIO_INSTALACAO}/Skjaldr-anterior.app"

ditto "${ORIGEM_APP}" "${APP_TEMPORARIO}"
codesign --verify --deep --strict "${APP_TEMPORARIO}"

if [[ "$(requisito_designado "${APP_TEMPORARIO}")" != "${REQUISITO_ORIGEM}" ]]; then
    echo "A cópia temporária não preservou a identidade assinada." >&2
    exit 1
fi

if [[ -e "${DESTINO_APP}" ]]; then
    mv "${DESTINO_APP}" "${APP_ANTERIOR}"
fi

if ! mv "${APP_TEMPORARIO}" "${DESTINO_APP}"; then
    restaurar_anterior
    echo "Falha ao instalar; a versão anterior foi restaurada." >&2
    exit 1
fi

if ! codesign --verify --deep --strict "${DESTINO_APP}"; then
    restaurar_anterior
    echo "A assinatura final falhou; a versão anterior foi restaurada." >&2
    exit 1
fi

if [[ "$(requisito_designado "${DESTINO_APP}")" != "${REQUISITO_ORIGEM}" ]]; then
    restaurar_anterior
    echo "A identidade final mudou; a versão anterior foi restaurada." >&2
    exit 1
fi

echo "Aplicação instalada em: ${DESTINO_APP}"
echo "Identidade preservada: ${REQUISITO_ORIGEM}"
