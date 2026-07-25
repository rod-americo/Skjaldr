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

## Grupos de linha

Uma linha agrupada possui identidade própria e não depende do número visual da linha. O usuário seleciona de duas a quatro imagens; seus identificadores são armazenados em `CompositionRowGroup`.

Ao calcular o layout:

1. itens não agrupados continuam usando o algoritmo do modo selecionado;
2. ao encontrar o primeiro item de um grupo, o motor encerra o segmento anterior;
3. todas as imagens do grupo são justificadas em uma única linha;
4. legendas individuais ocupam uma faixa sob suas respectivas imagens;
5. a legenda comum ocupa outra faixa, centralizada sob toda a largura da linha;
6. o processamento continua com os itens seguintes.

Reordenar um integrante move o bloco inteiro. Remover imagens dissolve automaticamente grupos que ficariam com menos de dois itens.

Esse vínculo por identificadores evita que uma legenda comum migre de conteúdo quando a largura ou o modo de layout muda.

## Legendas

As legendas não cobrem pixels médicos. Cada faixa admite até três linhas, possui fundo neutro, borda discreta e alinhamento central. Faixas vazias não são criadas.

Em uma linha com legendas individuais, a base é compartilhada para manter os textos alinhados. A faixa comum do grupo vem depois das legendas individuais:

```text
┌────────────┐  ┌────────────┐
│  imagem A  │  │  imagem B  │
└────────────┘  └────────────┘
   Anterior          Atual

        Comparação evolutiva
```

## Grade

O número de colunas é `ceil(sqrt(n))`, limitado a três no MVP. A proporção mediana define a altura das células, reduzindo a influência de uma imagem extremamente horizontal ou vertical. Cada imagem é ajustada dentro da célula sem corte.

## Comparação

Cada linha contém até duas células de mesma largura. A altura da linha acomoda a imagem mais alta do par. Os conteúdos são centralizados, o que favorece anterior/atual e direita/esquerda.

## Limite de altura

Se a composição exceder a altura máxima do perfil, o renderizador reduz proporcionalmente a largura e recalcula o layout. O comportamento padrão continua produzindo uma única imagem.

## Coordenadas e fidelidade

O motor usa coordenadas de topo esquerdo, naturais para galerias. O renderizador converte essas coordenadas para o sistema do AppKit. Retângulos são integralizados para evitar bordas em meio pixel.
