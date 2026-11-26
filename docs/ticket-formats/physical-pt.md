# Talão físico Euromilhões + M1lhão (PT)

Observações de uma fotografia real (362×598 px), descritas no patch original. Não publicar fotografia nem códigos. Hipóteses a confirmar com mais talões.

- Cabeçalho AP SIMPLES AUT SORT NNN; linhas k.N com cinco pares e E com dois pares.
- E fica abaixo das duas primeiras colunas N; estas usam tipo maior e mais carregado.
- Espaçamento vertical próximo da altura do glifo (16 px para 15 px).
- Rodapé com total, data/hora, código, VIRN e PDF417.

O patch relata que RapidOCR reconheceu as três colunas direitas, Tesseract perdeu quase todas as estrelas e a segmentação por componentes ligados recuperou a estrutura de cinco apostas (70 glifos). Isto não comprova a classificação correta dos 70 algarismos.

O PDF417 foi descodificado com zxing-cpp, mas não foram identificadas apostas em claro. Não usar como confirmação de valores sem validar o formato.

Próximo passo experimental: segmentar e reconhecer glifos individualmente, sem inventar valores, mantendo validação e confirmação de divergências.
