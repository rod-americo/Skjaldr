# Limitações e roadmap

## Limitações conhecidas do MVP

- o recorte manual usa controles percentuais; ainda não há alça visual sobre a imagem;
- o recorte automático remove apenas bordas externas quase uniformes;
- não há perfil específico por viewer;
- a grade escolhe até três colunas automaticamente, sem seletor explícito `2 × 3`;
- o modo imagem principal usa uma composição principal + coluna lateral fixa;
- legendas usam faixas de altura limitada a três linhas, sem formatação rica;
- não há setas, círculos, medições ou outras anotações;
- rotação está prevista no modelo, mas ainda não possui comando de interface;
- PDFs não são importados;
- limpeza configurável de sessões de 1 hora, 24 horas ou 7 dias ainda não foi implementada;
- o histórico é limitado à sessão aberta e aos cem últimos estados;
- não há indicador específico de ampliação de uma fonte pequena;
- JPEG é disponível no salvamento pelo perfil compacto, mas a ação principal de clipboard publica PNG/TIFF;
- compatibilidade com aplicativos de terceiros exige a matriz manual;
- assinatura Developer ID e notarização não fazem parte do artefato local;
- o vídeo oferece apenas as proporções 6:13 e 13:6;
- resolução, codec e 30 fps são fixos;
- não há preview, edição, webcam, GIF, zoom ou anotação de vídeo;
- o atalho global de vídeo é fixo em `⌘⇧9`;
- não há gravação isolada de uma janela.

## Próxima etapa: robustez clínica

1. executar a matriz real de pasteboard;
2. registrar versões e particularidades dos sistemas de laudo;
3. adicionar fallback específico somente quando um destino exigir;
4. medir desempenho Release com até vinte imagens;
5. auditar temporários e tráfego de rede;
6. executar teste prolongado do monitor de pasta.

## Pós-MVP

### Interação

- editor visual de recorte;
- seleção múltipla;
- grade configurável;
- modos série horizontal, vertical e pares;
- simulação de largura no editor;
- aviso de ampliação;
- limpeza rápida após copiar com desfazer.

### Composição

- perfis personalizados persistentes;
- fundo preto, cinza, transparente e personalizado;
- bordas discretas;
- numeração automática;
- rotação;
- estilos tipográficos e formatação avançada de legendas;
- anotação não destrutiva.

### Entrada

- extensão de compartilhamento do macOS;
- rasterização opcional de páginas PDF;
- bookmarks de segurança para distribuição sandboxed;
- regras conservadoras por aplicativo para recorte.

### Distribuição

- ícone final e identidade visual;
- projeto de assinatura;
- Hardened Runtime;
- Developer ID;
- notarização;
- atualizações assinadas, sem telemetria.

### Vídeo

- atalho configurável;
- contagem regressiva opcional;
- gravação de janela;
- presets e resoluções adicionais;
- HEVC;
- extração de quadros e GIF;
- integração com o compositor de imagens.

OCR, integração PACS, reconhecimento de modalidade, nuvem e contas permanecem fora do escopo até haver necessidade clínica, análise de risco e autorização explícita.
