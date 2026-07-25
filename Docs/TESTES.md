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
- legenda individual posicionada abaixo da própria imagem;
- grupo mantido em uma linha e legenda comum na largura combinada;
- renderização conjunta de legendas individuais e de linha;
- criação, edição e persistência de grupos pelo `ProjectStore`;
- migração de sessões anteriores sem grupos;
- recálculo de cem imagens abaixo de 150 ms;
- renderização de vinte imagens sintéticas abaixo de um segundo;
- renderização de uma única imagem PNG;
- ausência de GPS e dicionário TIFF herdado;
- publicação de PNG e TIFF, sem URL no mesmo item;
- arraste publicado como URL de arquivo, sem `public.png` concorrente;
- reconstrução do pasteboard como `NSImage`;
- recuperação da sessão JSON;
- proporções exatas e dimensões pares dos presets de vídeo;
- seleção 6:13 e 13:6 nos quatro sentidos do arraste;
- contenção e movimentação da região dentro da tela;
- persistência normalizada da última região;
- mapeamento dos quatro modos de áudio.

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

Também não substitui a validação manual de ScreenCaptureKit. Para vídeo:

Instale e abra sempre a cópia assinada em `/Applications/Skjaldr.app`. A
permissão de gravação de tela é vinculada à identidade de assinatura; não use
uma cópia ad hoc nem execute o binário diretamente de `.build`.

1. abrir e cancelar a seleção cinco vezes;
2. gravar Portrait e Landscape por pelo menos dez segundos;
3. repetir com os quatro modos de áudio;
4. confirmar proporção, orientação e faixas no QuickTime;
5. gravar por dez minutos com sistema + microfone e verificar sincronização;
6. interromper uma gravação encerrando o aplicativo;
7. negar tela e microfone e confirmar que nenhum temporário permanece;
8. confirmar que cada negação abre seu painel específico em Privacidade e
   Segurança;
9. recompilar, reinstalar e repetir uma gravação com microfone sem alterar as
   permissões.

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
