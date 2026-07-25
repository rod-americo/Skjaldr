# Pasteboard e compatibilidade

## Representações publicadas

Ao copiar, o Skjaldr cria um único `NSPasteboardItem` com:

| Tipo | Constante | Finalidade |
|---|---|---|
| PNG | `NSPasteboard.PasteboardType.png` / `public.png` | editores web, navegadores e destinos modernos |
| TIFF | `NSPasteboard.PasteboardType.tiff` / `public.tiff` | representação nativa tradicional de `NSImage` no macOS e editores RTF |

O arquivo temporário criado durante o arraste contém exatamente o PNG renderizado e não contém nome nem caminho de nenhuma fonte. O comando de copiar não cria arquivo novo.

`NSImage(pasteboard:)` consegue reconstruir a imagem a partir das representações publicadas; isso é verificado automaticamente em pasteboard isolado.

## Decisão sobre URL de arquivo

O protótipo inicial publicou `public.file-url` junto com PNG e TIFF no clipboard, como previsto na análise de risco. No ensaio com `contenteditable` do Safari, o WebKit consumiu a colagem mas não inseriu a imagem. A URL foi removida da operação de copiar, preservando PNG/TIFF como representações inequívocas.

O arraste segue a estratégia oposta: cria um PNG temporário e publica somente `public.file-url`/`public.url` por `NSURL`, sem uma representação `public.png` concorrente. Assim, o destino recebe o gesto como arquivo vindo do Finder e percorre o mesmo caminho de upload que já funciona em editores HTML embarcados.

Arquivos de arraste com mais de 24 horas são eliminados quando um novo arraste é iniciado.

## Por que não publicar HTML ou RTF?

Publicar um fragmento HTML/RTF faria o Skjaldr escolher marcação específica para o destino e poderia introduzir caminhos, wrappers ou comportamento inconsistente. Publicar a imagem em tipos nativos deixa o editor receptor produzir seu próprio `<img>`, attachment RTF ou objeto de mídia.

## Matriz de validação

Os testes automatizados validam os tipos e a reconstrução por AppKit. Os aplicativos abaixo precisam de ensaio manual porque o resultado depende da versão e das políticas do editor instalado:

| Destino | Estado | Resultado a registrar |
|---|---|---|
| `contenteditable` em Safari | aprovado no Safari 26.5 | uma imagem inline, não link |
| `contenteditable` em Chrome | pendente de ensaio manual | imagem inline, não link |
| TextEdit em modo RTF | aprovado no macOS 26.5 | um attachment de imagem por colagem |
| Microsoft Word | pendente de ensaio manual | imagem incorporada |
| Pages | pendente de ensaio manual | imagem incorporada |
| PowerPoint | pendente de ensaio manual | objeto de imagem |
| Keynote | pendente de ensaio manual | objeto de imagem |
| Outlook | pendente de ensaio manual | imagem inline no corpo |
| sistema real de laudo | pendente de ambiente clínico | imagem inline e persistente após salvar |

Não é correto marcar esses destinos como validados sem executar o teste na versão realmente usada.

## Roteiro manual

1. Monte uma composição com três imagens visualmente distintas.
2. Pressione `⌘C` no Skjaldr.
3. Cole no destino.
4. Confirme que há uma única imagem.
5. Salve, feche e reabra o documento.
6. Confirme que a imagem continua incorporada e não depende do arquivo temporário.
7. Compare dimensões, cores, orientação e nitidez.
8. Registre aplicativo, versão, sistema, resultado e observações em `Docs/RESULTADOS-CLIPBOARD.md`.

## Diagnóstico

Para listar os tipos depois de copiar:

```bash
osascript -e 'the clipboard info'
```

Esse comando inspeciona somente a declaração de tipos. Não deve ser usado para imprimir o conteúdo visual ou textual de material clínico.
