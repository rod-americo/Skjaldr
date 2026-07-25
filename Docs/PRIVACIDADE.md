# Privacidade

## Princípios

- processamento integralmente local;
- nenhuma chamada de rede;
- nenhuma telemetria;
- nenhuma conta;
- nenhuma sincronização;
- nenhum OCR externo;
- nenhuma gravação de pixels em logs.
- vídeo e áudio capturados somente após ação explícita do usuário.

## Dados persistidos

O Skjaldr mantém somente:

- cópias locais das imagens da sessão;
- estado JSON com dimensões, ordem, recorte, legendas, grupos e configurações;
- PNGs temporários usados no pasteboard e no arraste.
- preferências de vídeo: orientação, fonte de áudio, identificador do
  microfone, pasta de saída e região normalizada;
- MP4s gravados na pasta escolhida pelo usuário.

O estado atual fica em `~/Library/Application Support/Skjaldr`. A versão MVP preserva a sessão até o usuário iniciar outra composição ou remover manualmente os dados da aplicação. Política de expiração configurável está no roadmap.

## Metadados

A saída é criada em um novo bitmap. A codificação não copia propriedades da fonte. Assim, EXIF, GPS, comentários, caminhos, nomes e miniaturas embutidas não são transferidos. Propriedades técnicas criadas pelo codificador, como largura, altura, profundidade de bits e modelo de cor, são necessárias para representar a imagem.

## Temporários

O comando de copiar publica os dados diretamente, sem criar arquivo novo. O arraste usa um arquivo com identificador aleatório, eliminado pela limpeza de temporários após 24 horas. Nenhum temporário incorpora o nome da captura de origem.

Uma gravação de vídeo usa um arquivo oculto com identificador aleatório na
própria pasta de saída. Depois que ScreenCaptureKit finaliza o contêiner, o
arquivo é movido para o nome definitivo. Cancelamento ou falha removem somente
o temporário daquela gravação.

## Permissões de captura

A permissão de gravação de tela é solicitada ao iniciar a primeira captura. A
permissão de microfone só é solicitada nos modos `Microfone` e `Sistema +
microfone`. O Skjaldr não mantém essas permissões; elas são administradas pelo
macOS em Privacidade e Segurança. Erros de tela e microfone são diferenciados,
e cada um abre diretamente o painel correspondente dos Ajustes do Sistema.

O áudio do próprio Skjaldr é excluído da captura do sistema. Nenhuma imagem ou
amostra de áudio é enviada a outro processo pelo aplicativo.

O bundle assinado declara somente o entitlement público de entrada de áudio,
necessário para o microfone sob Hardened Runtime. Não usa entitlement privado
para contornar o TCC nem para capturar a tela sem consentimento.

## Logs

O aplicativo registra apenas eventos técnicos da inicialização da captura e
mensagens genéricas de erro pelo logger unificado do macOS. Não registra
pixels, áudio, caminho de saída nem nome de arquivos ou fontes.

## Limites

O pasteboard do macOS é compartilhado entre aplicativos. Depois de copiar, outros processos com acesso ao pasteboard podem ler a composição. Essa é uma característica necessária do fluxo solicitado; políticas institucionais do equipamento continuam aplicáveis.

A versão local assinada com Developer ID não está em sandbox. Isso permite
monitorar a pasta escolhida sem persistir bookmark de segurança. A exigência
designada da assinatura permanece estável entre compilações para que o macOS
associe as permissões sempre ao mesmo aplicativo. Uma distribuição pela Mac App
Store exigirá sandbox, seletor de pasta e bookmark com escopo de segurança.
