# Arquitetura

## Visão geral

O Skjaldr usa SwiftUI para estrutura e estado de interface, AppKit para integração de pasteboard, painéis e compartilhamento, e ImageIO/Core Graphics por meio das representações nativas de imagem. Não existem dependências de terceiros.

```text
Interface SwiftUI
      │
      ▼
ProjectStore ───── ScreenshotMonitor
      │
      ├── ImageImporter ── cópia local da fonte
      ├── LayoutEngine ─── retângulos de destino
      ├── CompositionRenderer ─ imagem raster final
      ├── ClipboardManager ─── PNG/TIFF/arquivo
      └── SessionPersistence ─ JSON + fontes locais
```

## Componentes

### Modelo do projeto

`CompositionState` é um valor `Codable` que contém itens, layout e perfil de saída. `CompositionItem` registra apenas a URL da cópia local, dimensões, recorte normalizado, legenda, ordem e destaque. A imagem original não é serializada dentro do JSON.

### Importação

`ImageImporter` valida o tipo por `UTType`, abre a imagem com AppKit/ImageIO, obtém dimensões e cria uma cópia privada em `Application Support`. A cópia estabiliza a recuperação da sessão mesmo que a captura original seja removida.

### Estado e histórico

`ProjectStore` é isolado ao ator principal. Toda mutação cria um instantâneo anterior, com limite de cem estados. Desfazer e refazer restauram valores; as fontes permanecem locais até a limpeza da sessão, evitando perda após desfazer remoções.

### Layout

`LayoutEngine` é puro e determinístico. Recebe somente identificadores, proporções e marcação de imagem principal. O retorno contém tamanho final e retângulos em coordenadas de topo esquerdo. Não abre arquivos nem renderiza pixels.

### Renderização

`CompositionRenderer`:

1. recalcula o layout na largura de saída;
2. cria bitmap RGBA de 8 bits;
3. preenche o fundo branco;
4. abre cada fonte original;
5. aplica o recorte normalizado sem alterar a fonte;
6. reduz com interpolação de alta qualidade;
7. desenha legenda opcional;
8. recodifica PNG/TIFF ou JPEG.

A pré-visualização utiliza largura reduzida. Cópia e salvamento invocam uma nova renderização na resolução configurada.

### Pasteboard e temporários

`ClipboardManager` publica PNG e TIFF no mesmo `NSPasteboardItem`. Um ensaio com URL de arquivo no mesmo item mostrou que o Safari consumia o evento de colagem sem inserir a imagem; por isso, a URL foi removida do clipboard. O arraste publica PNG e uma representação de arquivo temporário, atendendo destinos que exigem arquivo sem prejudicar editores HTML. Temporários com mais de 24 horas são eliminados quando uma nova cópia é criada.

### Monitor de capturas

`ScreenshotMonitor` verifica a pasta a cada 750 ms. Arquivos já existentes são ignorados. Um novo arquivo só é emitido após apresentar o mesmo tamanho em duas leituras consecutivas, reduzindo o risco de importar uma gravação incompleta.

### Persistência

O estado é salvo atomicamente em JSON sob `~/Library/Application Support/Skjaldr`. O diretório recebe permissões `0700` quando criado. Não existe banco de dados nem processo servidor.

## Concorrência

A coordenação de interface e sessão ocorre no ator principal. A renderização de pré-visualização é adiada por uma tarefa cancelável para coalescer alterações rápidas. O desenho usa contextos bitmap independentes e não reutiliza a imagem reduzida para exportação.

## Falhas e recuperação

- arquivos de entrada inválidos são ignorados e comunicados sem registrar caminhos;
- sessão corrompida inicia um projeto vazio;
- fontes ausentes são removidas da sessão durante a abertura;
- salvamento e cópia apresentam erro ao usuário sem diálogo em caso de sucesso;
- a escrita de sessão e de exportação é atômica.
