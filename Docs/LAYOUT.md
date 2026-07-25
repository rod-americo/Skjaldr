# Algoritmo de layout

## Objetivo

O motor procura maximizar a área legível, preservar proporções e evitar linhas desequilibradas. Ele trabalha com geometria; nenhum pixel médico é analisado.

## Automático sem imagem principal

O modo automático usa linhas justificadas com programação dinâmica.

Para cada intervalo candidato de uma a quatro imagens:

1. soma as proporções `largura / altura`;
2. desconta os espaçamentos da largura útil;
3. calcula a altura que faria a linha ocupar a largura;
4. mede a distância quadrática dessa altura em relação à altura-alvo;
5. adiciona penalidades para linha solitária e altura excessiva;
6. escolhe, por programação dinâmica, a sequência de quebras de menor custo.

Em forma resumida:

```text
alturaLinha = (larguraÚtil - espaçamentos) / somaDasProporções

custo = ((alturaLinha - alturaAlvo) / alturaAlvo)²
      + penalidadeDeLinhaSolitária
      + penalidadeDeAlturaExcessiva
```

A última linha curta é centralizada e limitada à altura-alvo, evitando ampliar uma ou duas imagens de forma desproporcional.

Complexidade: `O(n × k)`, com `k = 4` imagens candidatas por linha. Para cem imagens, o custo geométrico permanece pequeno.

## Imagem principal

Com ao menos três itens e um item principal:

- a imagem principal recebe aproximadamente 66% da largura útil;
- as secundárias ocupam uma coluna lateral;
- cada secundária usa `aspect fit`, sem deformação;
- a altura final considera o maior dos dois blocos.

## Grade

O número de colunas é `ceil(sqrt(n))`, limitado a três no MVP. A proporção mediana define a altura das células, reduzindo a influência de uma imagem extremamente horizontal ou vertical. Cada imagem é ajustada dentro da célula sem corte.

## Comparação

Cada linha contém até duas células de mesma largura. A altura da linha acomoda a imagem mais alta do par. Os conteúdos são centralizados, o que favorece anterior/atual e direita/esquerda.

## Limite de altura

Se a composição exceder a altura máxima do perfil, o renderizador reduz proporcionalmente a largura e recalcula o layout. O comportamento padrão continua produzindo uma única imagem.

## Coordenadas e fidelidade

O motor usa coordenadas de topo esquerdo, naturais para galerias. O renderizador converte essas coordenadas para o sistema do AppKit. Retângulos são integralizados para evitar bordas em meio pixel.
