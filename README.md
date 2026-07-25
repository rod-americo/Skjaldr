# Skjaldr

Compositor nativo e local de capturas médicas para macOS.

O Skjaldr transforma várias capturas em uma única imagem rasterizada, pronta para copiar e colar em editores de laudo HTML ou RTF. O fluxo principal é deliberadamente curto:

```text
captura → captura → captura → ⌘C → cola no laudo
```

Não há nuvem, conta, telemetria, OCR remoto nem etapa obrigatória de salvamento.

## Por que “Skjaldr”?

O nome é uma grafia estilizada inspirada em **skjǫldr** (também grafado **skjöldr**), “escudo” em nórdico antigo, e no radical **skjald-**. O escudo representa duas ideias do projeto:

- proteção: imagens médicas e sessões permanecem no Mac;
- composição: vários elementos se encaixam como uma parede de escudos, formando uma peça única.

“Skjaldr” não pretende ser uma transliteração acadêmica exata; é o nome próprio do aplicativo, preservando a sonoridade e a referência cultural.

## Estado do MVP

Implementado:

- aplicativo nativo em SwiftUI e AppKit;
- colar, selecionar e arrastar imagens;
- PNG, JPEG, TIFF, HEIC, WebP, BMP e demais tipos reconhecidos pelo ImageIO;
- miniaturas, seleção, remoção, duplicação e reordenação por arraste;
- layouts automático justificado, grade e comparação;
- quebra manual para forçar uma imagem a iniciar outra linha;
- imagem principal com área destacada;
- recorte manual não destrutivo;
- remoção conservadora de bordas uniformes na importação;
- fundo branco, margem, espaçamento e largura configuráveis;
- perfis Laudo padrão (750 px, margem e espaçamento de 12 px), Alta resolução e Imagem compacta;
- renderização integral a partir dos arquivos originais;
- legendas individuais centralizadas abaixo de cada imagem;
- agrupamento estável de duas a quatro imagens em uma linha;
- legenda comum centralizada sob toda a linha agrupada;
- cópia da composição com PNG e TIFF;
- salvamento como PNG ou JPEG;
- arraste da composição como PNG;
- menu nativo de compartilhamento;
- monitoramento de pasta com verificação de estabilidade do arquivo;
- desfazer e refazer;
- recuperação local da sessão;
- remoção de metadados identificáveis na nova codificação;
- arraste da pré-visualização como arquivo PNG temporário, equivalente ao Finder;
- testes automatizados de layout, renderização, pasteboard e persistência.

## Requisitos

- macOS 14 ou posterior;
- Xcode 26 ou Command Line Tools compatíveis;
- nenhum pacote externo.

## Compilar e testar

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test
./Scripts/compilar-app.sh
```

A aplicação será criada em:

```text
dist/Skjaldr.app
```

Para abrir:

```bash
open dist/Skjaldr.app
```

O pacote recebe uma assinatura ad hoc local. Distribuição para outras máquinas exige certificado Developer ID e notarização da Apple.

## Uso rápido

1. Abra o Skjaldr.
2. Pressione `⌘V`, arraste imagens para a janela ou use **Adicionar**.
3. Escolha Automático, Grade ou Comparação.
4. Reordene pelas miniaturas, se necessário.
5. Para forçar uma quebra, selecione a imagem que deverá iniciar a próxima linha e ative **Iniciar nova linha**.
6. Para uma legenda individual, selecione a imagem e preencha **Legenda da imagem**.
7. Para uma legenda comum, use `⌘`-clique em duas a quatro miniaturas e escolha **Agrupar como linha**.
8. Pressione `⌘C` ou arraste a pré-visualização como PNG.
9. Cole ou solte no editor do laudo.

Atalhos principais:

| Atalho | Ação |
|---|---|
| `⌘N` | nova composição |
| `⌘V` | adicionar imagem do clipboard |
| `⌘C` | copiar sempre a composição final |
| `⌘E` | salvar a composição |
| `⌘O` | importar arquivos |
| `⌘Z` / `⌘⇧Z` | desfazer / refazer |
| `Delete` | remover a imagem selecionada |
| `⌘D` | duplicar a imagem selecionada |
| `⌘G` | agrupar a seleção como uma linha |
| `⌘⇧G` | desagrupar a linha selecionada |
| `⌘1` / `⌘2` / `⌘3` | automático / comparação / grade |

## Privacidade

Todo o processamento ocorre localmente. O código não contém cliente HTTP, analytics ou integração com serviços externos. As fontes copiadas para a sessão ficam em:

```text
~/Library/Application Support/Skjaldr/
```

A saída é recodificada e não herda EXIF, GPS, nomes, caminhos, comentários ou miniaturas das fontes. Logs da aplicação não registram nomes de arquivos nem conteúdo visual.

Consulte [PRIVACIDADE.md](Docs/PRIVACIDADE.md) para o modelo de ameaça e a lista de verificações.

## Documentação

- [Arquitetura](Docs/ARQUITETURA.md)
- [Pasteboard e compatibilidade](Docs/PASTEBOARD.md)
- [Algoritmo de layout](Docs/LAYOUT.md)
- [Testes](Docs/TESTES.md)
- [Limitações e roadmap](Docs/ROADMAP.md)

## Organização do código

```text
Sources/SkjaldrApp/
├── Models.swift
├── ImageImporter.swift
├── ScreenshotMonitor.swift
├── LayoutEngine.swift
├── CompositionRenderer.swift
├── ClipboardManager.swift
├── SessionPersistence.swift
├── ProjectStore.swift
├── ContentView.swift
└── SkjaldrApp.swift
```

## Decisões de escopo

O MVP produz uma única imagem, não PDF nem documento paginado. OCR, PACS, nuvem, contas, banco de dados complexo e anotações clínicas avançadas foram excluídos intencionalmente. A medição visual também não faz parte deste MVP e nunca deve ser interpretada como medição clínica.
