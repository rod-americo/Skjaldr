# Testes

## Suíte automatizada

Execute:

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test
```

Ou execute compilação, testes e empacotamento:

```bash
./Scripts/verificar.sh
```

Cobertura atual:

- vinte imagens no layout automático;
- mistura de proporções horizontais e verticais;
- grade;
- comparação em pares;
- área reservada à imagem principal;
- ausência de sobreposição geométrica;
- recálculo de cem imagens abaixo de 150 ms;
- renderização de vinte imagens sintéticas abaixo de um segundo;
- renderização de uma única imagem PNG;
- ausência de GPS e dicionário TIFF herdado;
- publicação de PNG e TIFF, sem URL no mesmo item;
- reconstrução do pasteboard como `NSImage`;
- recuperação da sessão JSON.

## Plano de imagens

Antes de uma versão de produção, executar com material sintético ou totalmente anonimizado:

- 1, 2, 3, 4, 5, 10 e 20 imagens;
- horizontais, verticais e mistura;
- PNG transparente, JPEG, TIFF, HEIC e WebP;
- imagens pequenas e muito grandes;
- bordas pretas, brancas e cinza uniforme;
- barras de ferramentas com conteúdo não uniforme;
- recortes manuais nos quatro lados;
- legenda e imagem principal;
- cem imagens para teste de limite.

## Metas de desempenho

Medir em uma compilação Release no hardware de uso:

| Operação | Meta |
|---|---:|
| adicionar imagem | < 100 ms |
| recalcular layout | < 150 ms |
| copiar composição | < 500 ms |
| gerar PNG | < 1 s |

As metas são para composições usuais de até vinte imagens. O teste deve informar modelo do Mac, dimensões das fontes e dimensões da saída.

## Compatibilidade manual

O teste automatizado não substitui colagem em editores reais. Siga o roteiro de [PASTEBOARD.md](PASTEBOARD.md) e preencha [RESULTADOS-CLIPBOARD.md](RESULTADOS-CLIPBOARD.md).

Uma página local sem scripts nem rede está disponível em:

```text
Tests/Manual/clipboard-contenteditable.html
```

## Privacidade

Verificações estáticas recomendadas:

```bash
rg 'URLSession|NWConnection|Analytics|Telemetry|http://' Sources
rg 'print\\(|debugPrint\\(|NSLog\\(' Sources
```

O resultado esperado é vazio. Faça o ensaio de rede também com uma ferramenta local de observação durante importação, cópia e salvamento.
