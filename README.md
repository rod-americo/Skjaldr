# Skjaldr

Ferramenta nativa para composição local de imagens, gravação de tela e
publicação opcional de vídeos por link curto.

O Skjaldr transforma várias capturas em uma única imagem rasterizada, pronta para copiar e colar em editores de laudo HTML ou RTF. O fluxo principal é deliberadamente curto:

```text
captura → captura → captura → ⌘C → cola no laudo
```

Imagens continuam integralmente locais. Vídeos são sempre preservados
localmente e, quando a integração está configurada, enviados ao bucket R2
privado após a finalização.

O módulo de vídeo grava uma região com proporção de telefone, pronta para
demonstrações e compartilhamento:

```text
⌘F14 → seleciona a região → Enter → grava → ⌘F14 → MP4 pronto
```

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
- múltiplas composições em abas independentes;
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
- testes automatizados de layout, renderização, pasteboard e persistência;
- captura de vídeo em `Phone Portrait` (6:13) e `Phone Landscape` (13:6);
- controle permanente pela barra de menus, sem trazer o compositor à frente;
- seleção multitelas com proporção fixa e restauração da última região;
- moldura persistente em quatro bordas leves, passiva e excluída do vídeo;
- áudio do sistema, microfone, ambos ou nenhum;
- exportação 720 × 1560 (ou 1560 × 720) em H.264/AAC a 30 fps;
- salvamento automático na pasta configurada;
- início e parada pelo atalho global `⌘F14`;
- cancelamento sem salvar nem enviar pelo atalho global `⌃⌥F14`;
- nova composição em aba pelo atalho global `⌘F13`;
- suspensão do monitor de imagens e da fila de upload durante a captura;
- recuperação de MP4 temporário e timeout de finalização;
- validação da duração da trilha de vídeo antes de salvar ou enviar;
- finalização segura ao encerrar o aplicativo durante uma gravação.
- upload assíncrono para Cloudflare R2 depois do salvamento local;
- MP4 móvel H.264 a 3 Mb/s e `faststart`, com bruto recuperável até o upload;
- URL curta `https://odin.med.br/123-456`, copiada automaticamente;
- retry persistente e progresso sem bloquear novas capturas;
- conclusão remota persistida antes de substituir o MP4 local;
- Worker, D1, R2 privado, Range HTTP, revogação e retenção configurável.
- notificação nativa de conclusão, com banner local se o macOS a bloquear.

## Requisitos

- macOS 26;
- Xcode 26 ou Command Line Tools compatíveis;
- nenhum pacote externo.

## Compilar e testar

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test
./Scripts/compilar-app.sh
```

O script gera o build assinado em `dist/Skjaldr.app` e o instala
automaticamente em:

```text
/Applications/Skjaldr.app
```

Para reinstalar o último build sem recompilar:

```bash
./Scripts/instalar-app.sh
```

Para abrir:

```bash
open /Applications/Skjaldr.app
```

Na primeira gravação, o macOS solicitará as permissões correspondentes de tela
e microfone. O microfone só é solicitado quando fizer parte do modo de áudio.
Depois de autorizar a gravação de tela pela primeira vez, encerre e reabra o
Skjaldr antes de iniciar a captura. Se uma autorização for negada, o alerta
abre diretamente o painel correto para gravação de tela ou microfone.

O pacote é assinado com um certificado Developer ID fixado pelo fingerprint
SHA-1 e instalado em `/Applications`. O instalador compara a exigência
designada da versão nova com a já instalada e recusa a atualização se as
identidades forem diferentes. Assim o macOS reconhece recompilações como
versões do mesmo aplicativo e preserva a permissão de gravação.

O Hardened Runtime é mantido ativo. O único entitlement de captura incorporado
é o de entrada de áudio exigido pelo macOS para solicitar acesso ao microfone;
a gravação de tela continua protegida exclusivamente pelo consentimento em
Privacidade e Segurança.

Para trocar deliberadamente o certificado:

```bash
SKJALDR_CODESIGN_CERTIFICATE="FINGERPRINT_SHA1" \
  ./Scripts/compilar-app.sh
```

Trocar o certificado também troca a identidade do aplicativo perante o macOS e
exige uma nova autorização. Notarização só é necessária para distribuir o
aplicativo a outras pessoas.

## Uso rápido

1. Abra o Skjaldr; cada execução começa com uma composição vazia. Use `⌘T`
   ou `⌘N` para outra composição em aba.
2. Pressione `⌘V`, arraste imagens para a janela ou use **Adicionar**.
3. Escolha Automático, Grade ou Comparação.
4. Reordene pelas miniaturas, se necessário.
5. Para forçar uma quebra, selecione a imagem que deverá iniciar a próxima linha e ative **Iniciar nova linha**.
6. Para uma legenda individual, selecione a imagem e preencha **Legenda da imagem**.
7. Para uma legenda comum, use `⌘`-clique em duas a quatro miniaturas e escolha **Agrupar como linha**.
8. Pressione `⌘C` ou arraste a pré-visualização como PNG.
9. Cole ou solte no editor do laudo.

Para gravar vídeo:

1. Clique em **Gravar tela** ou abra **Captura > Configurar gravação**.
2. Escolha `Phone Portrait` ou `Phone Landscape`.
3. Escolha a fonte de áudio e a pasta de saída.
4. Clique em **Selecionar região** e desenhe a moldura em qualquer monitor.
5. Arraste dentro da região para reposicioná-la, se necessário, e pressione
   `Enter`.
6. Pressione `⌘F14` ou use **Parar** para finalizar.
7. O MP4 será salvo automaticamente como
   `yyyyMMdd_HHmm_video-laudo.mp4`, sem diálogo ou preview.
8. Com a nuvem configurada, o Skjaldr envia o arquivo, confirma sua integridade
   e copia o link curto. Falhas de rede nunca removem o arquivo local.

## Cloudflare e links de vídeo

Pré-requisitos:

- Node.js e npm;
- `jq`, `curl`, `openssl`, `ffmpeg` e `dig`;
- credencial bootstrap em `~/.local/share/cloudflare-r2.env`;
- zona `odin.med.br` na mesma conta do bucket privado `skjaldr`.

Provisionamento idempotente:

```bash
./Scripts/bootstrap-cloudflare.sh
./Scripts/setup-cloudflare.sh
./Scripts/test-cloudflare-e2e.sh
```

Deploys posteriores:

```bash
./Scripts/deploy-cloudflare.sh
```

O bootstrap cria um Account API Token dedicado com acesso somente à conta
necessária e à zona `odin.med.br`. O segredo operacional do app fica em
`~/Library/Application Support/Skjaldr/cloud-upload.json`, com modo `0600`.
Nenhum segredo é versionado.

O bucket não usa `r2.dev`, domínio público ou CORS. O app envia por PUT
pré-assinado; a leitura pública passa exclusivamente pelo Worker, que resolve o
código no D1 e transmite o objeto privado com suporte a Range.

Retenção é indefinida por padrão (`VIDEO_RETENTION_DAYS=0`). Consulte
[Operação Cloudflare](Docs/CLOUD_UPLOAD.md) para variáveis, permissões, rotação,
revogação, exclusão, backup, recuperação e troubleshooting.

Atalhos principais:

| Atalho | Ação |
|---|---|
| `⌘N` | nova composição em aba |
| `⌘T` | nova aba de composição na janela única |
| `⌘F13` | mostrar o Skjaldr e abrir uma composição em aba |
| `⌘W` | fechar a aba atual; na última, ocultar o Skjaldr |
| `⌘V` | adicionar imagem do clipboard; em uma legenda, colar texto |
| `⌘C` | copiar a composição final; em uma legenda, copiar texto |
| `⌘X` / `⌘A` | recortar / selecionar tudo em uma legenda |
| `⌘E` | salvar a composição |
| `⌘O` | importar arquivos |
| `⌘Z` / `⌘⇧Z` | desfazer / refazer |
| `Delete` | remover a imagem selecionada |
| `⌘D` | duplicar a imagem selecionada |
| `⌘G` | agrupar a seleção como uma linha |
| `⌘⇧G` | desagrupar a linha selecionada |
| `⌘1` / `⌘2` / `⌘3` | automático / comparação / grade |
| `⌘F14` | iniciar seleção / cancelar seleção / parar gravação |
| `⌃⌥F14` | cancelar gravação sem salvar nem enviar |

O botão de fechar de uma aba sempre fecha aquela composição. Se for a última,
o Skjaldr cria imediatamente uma nova aba vazia e mantém a janela visível. Para
ocultar o aplicativo com apenas uma aba aberta, use `⌘W` ou `⌘H`.

## Privacidade

O processamento de imagens ocorre localmente e não há analytics. As fontes copiadas para a sessão
ficam em:

```text
~/Library/Application Support/Skjaldr/
```

Ao encerrar e abrir novamente o Skjaldr, as composições anteriores e suas
fontes locais são removidas. Preferências visuais, como largura, margens e
espaçamento, são preservadas.

A saída é recodificada e não herda EXIF, GPS, nomes, caminhos, comentários ou miniaturas das fontes. Logs da aplicação não registram nomes de arquivos nem conteúdo visual.

Vídeos e áudio são capturados somente durante uma gravação iniciada pelo
usuário. O MP4 é finalizado localmente antes do upload opcional. A tabela
remota não recebe nomes de paciente, exame, hospital ou caminho local. O código
de seis dígitos é um identificador por obscuridade, não autenticação.

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
├── VideoModels.swift
├── VideoRegionSelection.swift
├── ScreenCaptureRecorder.swift
├── VideoRecorderStore.swift
├── VideoCaptureView.swift
├── GlobalHotKeyController.swift
└── SkjaldrApp.swift
```

## Decisões de escopo

O MVP produz uma única imagem, não PDF nem documento paginado. OCR, PACS, nuvem, contas, banco de dados complexo e anotações clínicas avançadas foram excluídos intencionalmente. A medição visual também não faz parte deste MVP e nunca deve ser interpretada como medição clínica.
