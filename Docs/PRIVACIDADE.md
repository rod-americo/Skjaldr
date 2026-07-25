# Privacidade

## Princípios

- processamento integralmente local;
- nenhuma chamada de rede;
- nenhuma telemetria;
- nenhuma conta;
- nenhuma sincronização;
- nenhum OCR externo;
- nenhuma gravação de pixels em logs.

## Dados persistidos

O Skjaldr mantém somente:

- cópias locais das imagens da sessão;
- estado JSON com dimensões, ordem, recorte, legenda e configurações;
- PNGs temporários usados no pasteboard e no arraste.

O estado atual fica em `~/Library/Application Support/Skjaldr`. A versão MVP preserva a sessão até o usuário iniciar outra composição ou remover manualmente os dados da aplicação. Política de expiração configurável está no roadmap.

## Metadados

A saída é criada em um novo bitmap. A codificação não copia propriedades da fonte. Assim, EXIF, GPS, comentários, caminhos, nomes e miniaturas embutidas não são transferidos. Propriedades técnicas criadas pelo codificador, como largura, altura, profundidade de bits e modelo de cor, são necessárias para representar a imagem.

## Temporários

O comando de copiar publica os dados diretamente, sem criar arquivo novo. O arraste usa um arquivo com identificador aleatório, eliminado pela limpeza de temporários após 24 horas. Nenhum temporário incorpora o nome da captura de origem.

## Logs

O código do aplicativo não usa `print`, `NSLog` ou logger próprio. Mensagens ao usuário são genéricas e não incluem caminho nem nome da fonte.

## Limites

O pasteboard do macOS é compartilhado entre aplicativos. Depois de copiar, outros processos com acesso ao pasteboard podem ler a composição. Essa é uma característica necessária do fluxo solicitado; políticas institucionais do equipamento continuam aplicáveis.

A versão local ad hoc não está em sandbox. Isso permite monitorar a pasta escolhida sem persistir bookmark de segurança. Uma distribuição pela Mac App Store exigirá sandbox, seletor de pasta e bookmark com escopo de segurança.
