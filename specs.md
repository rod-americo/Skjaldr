# Skjaldr — Captura de vídeo

## Status

Especificação implementada do MVP de gravação de tela do Skjaldr.

Este documento define o produto e os critérios de aceite. Detalhes de
implementação podem mudar, desde que o comportamento descrito aqui seja
preservado.

## Contexto

O Skjaldr já transforma capturas estáticas em artefatos prontos para
documentação. A gravação de tela estende o mesmo fluxo para demonstrações
curtas de sistemas, aplicações e processos.

O objetivo não é competir com gravadores generalistas ou editores de vídeo.
O objetivo é produzir rapidamente um MP4 com enquadramento adequado para
visualização em um telefone, sem edição ou conversão posterior.

## Princípios

- poucas decisões durante a captura;
- operação rápida e previsível;
- nenhuma etapa obrigatória de edição, pré-visualização ou confirmação;
- configurações anteriores reutilizadas sempre que possível;
- processamento e armazenamento exclusivamente locais;
- módulo de vídeo independente do compositor de imagens;
- comportamento e aparência coerentes com um recurso nativo do macOS.

Quando houver conflito entre acrescentar flexibilidade e manter o fluxo curto,
o MVP deve favorecer o fluxo curto.

## Escopo do MVP

O MVP deve:

- gravar uma região da tela;
- oferecer somente os presets `Phone Portrait` e `Phone Landscape`;
- manter a proporção do preset durante toda a seleção;
- permitir escolher a fonte de áudio;
- iniciar e encerrar a gravação por interface e por atalho;
- codificar o resultado como MP4 com vídeo H.264 e, quando houver áudio, AAC;
- salvar automaticamente na pasta de saída configurada;
- lembrar as últimas escolhas e a última região válida;
- indicar claramente quando uma gravação estiver em andamento.

## Fora do escopo

Não implementar no MVP:

- editor ou timeline;
- tela de pré-visualização após a captura;
- confirmação antes de salvar;
- upload ou compartilhamento automático;
- histórico ou biblioteca de gravações;
- GIF;
- câmera ou webcam;
- zoom e seguimento automático do cursor;
- efeitos, anotações ou animações;
- múltiplos presets personalizados;
- gravação simultânea de várias regiões;
- integração do vídeo com o compositor de imagens;
- HEVC ou outros formatos de exportação.

## Presets de enquadramento

Os presets representam proporções, não modelos específicos de aparelho.

| Preset | Proporção da região | Resolução de saída inicial |
|---|---:|---:|
| `Phone Portrait` | 9:19,5 (6:13) | 1080 × 2340 |
| `Phone Landscape` | 19,5:9 (13:6) | 2340 × 1080 |

A resolução da região selecionada pode ser diferente da resolução de saída. O
pipeline deve redimensionar a captura para a resolução do preset sem distorcer,
recortar ou criar barras. A proporção exata da região é, portanto, um requisito
invariante.

As dimensões de saída devem continuar compatíveis com a codificação H.264. Uma
alteração futura de resolução não pode alterar a proporção dos presets.

## Seleção da região

### Comportamento

- A seleção nasce e permanece na proporção do preset ativo.
- O usuário pode criar, mover e redimensionar a região.
- As alças de redimensionamento nunca liberam a proporção.
- A seleção deve permanecer dentro dos limites da tela escolhida.
- Pressionar `Escape` antes do início cancela a operação sem criar arquivo.
- Pressionar `Enter` com uma região válida inicia a gravação.
- Ao reabrir o recurso, a última região válida deve reaparecer se a tela e seus
  limites ainda forem compatíveis.
- Se a configuração de telas mudou, a região deve ser ajustada para uma área
  visível ou descartada de forma segura.

### Aparência

A moldura deve ser legível sobre fundos claros e escuros, sem aparecer no
vídeo final. A interface pode escurecer levemente a área externa, desde que não
altere o conteúdo capturado.

Não simular moldura física de iPhone, Dynamic Island ou áreas seguras no MVP.

## Áudio

Oferecer estes modos:

- `Sem áudio`;
- `Microfone`;
- `Áudio do sistema`;
- `Sistema + microfone`.

Quando houver mais de um dispositivo de entrada, o usuário deve poder escolher
o microfone. Dispositivos virtuais disponibilizados ao macOS, como BlackHole e
Loopback, devem aparecer como entradas normais quando forem enumerados pelo
sistema; não precisam de integração específica.

O último modo e o último dispositivo selecionado devem ser persistidos. Se um
dispositivo deixar de existir, o aplicativo deve escolher um fallback seguro e
informar a mudança antes de gravar.

No modo `Sistema + microfone`, as duas fontes devem ser mixadas em uma única
faixa AAC. O áudio deve permanecer sincronizado com o vídeo durante toda a
gravação.

## Fluxo principal

```text
Abrir Captura de vídeo
        ↓
Escolher Portrait ou Landscape
        ↓
Posicionar a região com proporção travada
        ↓
Confirmar a fonte de áudio
        ↓
Iniciar
        ↓
Gravar a demonstração
        ↓
Parar por botão ou atalho
        ↓
MP4 salvo automaticamente
```

Não deve haver diálogo de salvamento, confirmação ou pré-visualização após uma
gravação concluída com sucesso.

## Interface

O controle de gravação deve ser compacto e conter somente:

- orientação: `Phone Portrait` ou `Phone Landscape`;
- modo de áudio;
- dispositivo de entrada, quando aplicável;
- pasta de saída;
- ação `Iniciar gravação`.

Durante a gravação:

- a moldura e o painel de configuração não podem aparecer no resultado;
- deve existir um indicador discreto e inequívoco de gravação;
- deve existir uma ação visível para parar;
- o mesmo atalho usado para iniciar pode parar a gravação;
- a duração pode ser exibida, mas não é requisito do primeiro incremento.

O atalho definitivo deve ser escolhido durante a implementação após verificar
conflitos com atalhos existentes do Skjaldr e do macOS. O usuário deve poder
iniciar e parar pela interface mesmo se o atalho global não estiver disponível.

## Exportação

### Formato

- contêiner: MP4;
- vídeo: H.264;
- formato de pixels: 4:2:0 compatível com players comuns;
- áudio: AAC quando uma fonte de áudio estiver ativa;
- taxa de quadros alvo: 30 fps;
- extensão: `.mp4`.

O perfil de codificação deve privilegiar legibilidade de texto e interfaces,
com tamanho adequado para compartilhamento. Não é necessário expor bitrate,
qualidade, perfil H.264 ou taxa de quadros na interface do MVP.

### Arquivo

A gravação deve ser escrita primeiro como arquivo temporário e movida para o
destino somente após a finalização correta do contêiner. Uma gravação não pode
sobrescrever arquivo existente.

Formato inicial do nome:

```text
yyyyMMdd_HHmm_video-laudo.mp4
```

Exemplo: `20260725_1124_video-laudo.mp4`.

Se já existir um arquivo com o mesmo nome, acrescentar um sufixo incremental
antes da extensão.

Ao concluir:

- salvar diretamente na pasta configurada;
- apresentar uma notificação discreta com o nome do arquivo;
- oferecer acesso ao arquivo ou à pasta pela notificação, se isso não exigir
  uma etapa adicional no fluxo;
- não abrir automaticamente um player.

## Interrupções e falhas

- Cancelar antes do início não cria arquivo.
- Parar depois do início finaliza e salva uma gravação válida, ainda que curta.
- Erros de permissão, espaço em disco, codificação ou dispositivo de áudio
  devem ser apresentados sem expor conteúdo capturado ou caminhos sensíveis em
  logs.
- Se a captura for interrompida pelo sistema, o aplicativo deve tentar
  finalizar o arquivo; se isso não for possível, deve remover apenas o
  temporário daquela gravação e informar a falha.
- Suspensão, bloqueio de sessão, remoção de tela e mudança de configuração de
  monitores precisam encerrar a captura de maneira controlada.
- Encerrar o Skjaldr durante uma gravação deve primeiro solicitar a finalização
  da captura.

## Permissões e privacidade

O recurso requer permissão de gravação de tela do macOS e, para os modos
correspondentes, permissão de microfone.

- Solicitar cada permissão somente quando necessária.
- Explicar como habilitá-la caso tenha sido negada.
- Não iniciar uma gravação parcial quando uma fonte solicitada não estiver
  autorizada.
- Não realizar upload, telemetria ou processamento remoto.
- Não registrar imagens, amostras de áudio, nomes de janelas, nomes de
  aplicativos ou nomes completos de arquivos.
- Manter a política de privacidade local já adotada pelo Skjaldr.

## Assinatura e instalação local

Para que o TCC preserve as autorizações entre compilações:

- assinar todos os builds com o mesmo certificado Developer ID;
- fixar o certificado pelo fingerprint, sem seleção implícita por nome;
- manter `io.skjaldr.app`, o Team ID e a exigência designada estáveis;
- instalar e executar somente `/Applications/Skjaldr.app`;
- recusar a instalação se a exigência designada do bundle novo diferir da
  versão instalada;
- manter Hardened Runtime e incorporar o entitlement público
  `com.apple.security.device.audio-input`;
- não usar entitlement privado para gravação de tela ou para contornar o TCC;
- verificar assinatura, identidade, entitlement e cópia final em cada build.

## Arquitetura

Usar preferencialmente:

- SwiftUI e AppKit para interface e integração com o macOS;
- ScreenCaptureKit para captura de tela, áudio do sistema, microfone e escrita
  do MP4 por `SCRecordingOutput`;
- AVFoundation somente para descoberta e autorização dos dispositivos de
  entrada e para os tipos de mídia usados pela configuração.

O aplicativo é de uso pessoal e tem como alvo a versão atual da máquina:
macOS 26. Não é necessário manter compatibilidade com versões anteriores.

Usar diretamente as APIs atuais do ScreenCaptureKit, incluindo captura de
microfone e `SCRecordingOutput`, evitando camadas de compatibilidade,
implementações duplicadas ou fallbacks para APIs antigas.

Separação lógica desejada:

```text
Skjaldr
├── Image Composer
├── Video Capture
│   ├── Region Selection
│   ├── Capture Session
│   ├── Audio Sources
│   └── Recording State
├── Video Export
├── Preferences
└── App Commands
```

O compositor de imagens não deve conhecer detalhes de ScreenCaptureKit,
AVFoundation ou do ciclo de uma gravação. Preferências compartilhadas, comandos
do aplicativo e seleção da pasta de saída podem permanecer em infraestrutura
comum.

## Estado da gravação

O módulo deve possuir estados explícitos para evitar ações ambíguas:

```text
idle
  → selecting
  → preparing
  → recording
  → finishing
  → idle
```

Falha ou cancelamento devem retornar a `idle` depois da limpeza dos recursos da
sessão. Somente `recording` aceita a ação de parar. Durante `preparing` e
`finishing`, novos inícios devem ser ignorados ou desabilitados.

## Persistência

Persistir localmente:

- último preset;
- última região válida por preset e por tela, quando identificável;
- último modo de áudio;
- último dispositivo de entrada;
- pasta de saída.

Não incluir uma gravação em andamento na persistência normal da sessão do
compositor. Arquivos temporários do gravador devem ter ciclo de vida próprio e
limpeza conservadora.

## Critérios de aceite

O MVP estará pronto quando:

1. for possível selecionar uma região `Phone Portrait` e redimensioná-la sem
   desviar de 6:13;
2. for possível fazer o mesmo em `Phone Landscape`, mantendo 13:6;
3. uma gravação de cada preset gerar MP4 reproduzível em QuickTime e manter a
   proporção e a orientação esperadas;
4. texto e movimentos de interface permanecerem visualmente legíveis na saída
   de 30 fps;
5. os quatro modos de áudio produzirem o resultado correspondente, sem perda
   perceptível de sincronização em uma gravação de pelo menos dez minutos;
6. iniciar e parar funcionarem pela interface e pelo atalho escolhido;
7. cancelar uma gravação em curso por `⌥⌘⇧9` apagar o arquivo temporário,
   sem salvar o vídeo nem iniciar o upload;
8. o arquivo aparecer automaticamente na pasta configurada, sem diálogo e sem
   sobrescrever outro arquivo;
9. cancelar a seleção não deixar MP4 nem temporário órfão;
10. negar permissões produzir uma orientação compreensível e não iniciar captura
   incompleta;
11. moldura, painel e indicador próprios do Skjaldr não aparecerem no vídeo;
12. as últimas escolhas e regiões válidas serem restauradas após reiniciar o
    aplicativo;
13. o compositor de imagens e seus testes continuarem funcionando sem mudança
    de comportamento;
14. recompilar e reinstalar o app não exigir nova autorização de tela ou
    microfone.
15. iniciar uma gravação global não ativar nem trazer o compositor de imagens
    à frente;
16. a barra de menus permanecer disponível para iniciar, parar, cancelar e
    acompanhar gravações e uploads;
17. monitoramento de pasta, renderização de preview e upload ficarem suspensos
    durante toda a operação de captura;
18. a finalização nunca aguardar indefinidamente e preservar para recuperação
    qualquer MP4 temporário válido.

## Estratégia de implementação

Ordem recomendada:

1. modelar presets, preferências e máquina de estados;
2. implementar e testar a seleção de região com proporção fixa;
3. capturar a região sem áudio e gerar MP4 H.264;
4. adicionar parada, finalização atômica e tratamento de interrupções;
5. adicionar os modos de áudio e testes de sincronização;
6. integrar comandos, atalho, indicador e persistência;
7. validar permissões, múltiplas telas e recuperação de falhas;
8. executar os critérios de aceite e atualizar a documentação do projeto.

## Evoluções futuras

Somente depois do MVP:

- atalho global configurável;
- início imediato com a última configuração;
- contagem regressiva opcional;
- presets adicionais;
- resoluções ou qualidade configuráveis;
- HEVC;
- gravação de uma janela;
- extração de quadros;
- GIF;
- integração com o compositor de imagens;
- abertura ou compartilhamento rápido do último arquivo.
