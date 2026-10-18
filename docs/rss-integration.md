# RSS oficiais e origem dos prémios — 17/10/2026

Implementação local de validação, sem instalação no cPanel, Cron remoto, migração
ou alteração de dados de produção. Nenhuma alteração Android ou dependência nova.

Atualização 18/10/2026: [leitura automática do cartaz e revisões](official-results-cpanel.md); os detalhes abaixo conservam a auditoria inicial.

## Auditoria dos prémios efetivos

A API instalada respondeu a GET `/health` com versão `0.1.1` e a
`/v1/draws/euromilhoes/083/2026` com estado `complete`, data `2026-10-16`,
13 categorias, acertos, montantes unitários em cêntimos e vencedores em Portugal
e no total. A aplicação lê `tiers[].amountCents` e só calcula prémios para
concursos `complete` (`app/lib/domain/wallet.dart`). Não existem endpoints
separados de categorias: os dados estão no objeto do concurso.

A origem declarada é a [página oficial do concurso](https://www.jogossantacasa.pt/web/SCCartazResult/euroMilhoes).
Uma consulta HTTPS de leitura confirmou a chave, a data e a igualdade das **13
categorias**, incluindo montantes e vencedores, com a API instalada. A evidência,
os hashes das respostas e a tabela comparada estão em
[validation/rss-source-audit-20261017.json](validation/rss-source-audit-20261017.json).
A coincidência não prova a cadeia de importação administrativa original: o código
atual recebe JSON revisto (`import_result.py` ou inbox `collect_results.py`), sem
coletor automático de categorias. O scaffold TypeScript também importa JSON.

Exemplo decisivo: a categoria 5 (4 números + 1 estrela) tem **101,06 €**, com
61 vencedores em Portugal e 831 no total. O maior prémio **224,64 €** do RSS
Portal é outro indicador e nunca substitui esse montante unitário.
Os três RSS não fornecem a tabela oficial de categorias. A atualização desses
valores continua administrativa, com validação das 13 categorias; um futuro
adaptador da tabela oficial deve verificar concurso/data e conservar proveniência
e revisão. Não foi adicionado scraping periódico de HTML.

## Fontes verificadas

GET HTTPS direto, status 200, sem redirecionamentos, em 17/10/2026:

| Feed | URL | Publicação dos itens relevantes UTC |
| --- | --- | --- |
| Resultados | `https://www.jogossantacasa.pt/web/SCRss/rssFeedCartRes` | 16/10/2026 19:51:19 |
| Jackpots | `https://www.jogossantacasa.pt/web/SCRss/rssFeedJackpots` | 16/10/2026 20:01:29 |
| Portal | `https://www.jogossantacasa.pt/web/SCRss/rssFeedPremiosPortal` | 17/10/2026 03:00:19 |

Os XML originais ISO-8859-1 estão em `api-python/fixtures/rss/`, sem reserialização.
`manifest.json` regista tamanho e SHA-256; os testes verificam esses hashes.
Os links HTTP internos são metadados ignorados pelo transporte. A primeira tentativa
em `/web/SCCartazResult/rssFeedCartRes` respondeu 500; o caminho correto é `/web/SCRss/`.

## Dados separados

| Jogo | Resultado anterior | Próximo concurso | Montante anunciado |
| --- | --- | --- | --- |
| Euromilhões | 083/2026: 7,15,16,22,35 + 4,6 | 084/2026, 2026-10-20 | 5 900 000 000 cêntimos, previsão |
| M1lhão | 009/2026: PTM 09893 | 010/2026, 2026-10-30 | 100 000 000 cêntimos, anunciado |

Os montantes anunciados não são prémios de apostas anteriores. O código M1lhão
conserva o zero inicial. Os identificadores são sempre `(game, drawId)`.

O Portal tem utilidade concreta de auditoria: permite consultar indicadores e a
sua origem sem os confundir com categorias oficiais. Fica em observações separadas,
com `scope=portal_only`, nunca em `prize_tiers` ou `milhao_results`.

| Indicador Portal | Euromilhões 083/2026 | M1lhão 009/2026 |
| --- | --- | --- |
| Total último sorteio | 101 555,09 € | 0,00 € |
| Maior último sorteio | 224,64 €, categoria 5 | 0,00 €, SEM DADOS |
| Total histórico | 332 324 620,01 € | 43 000 000,00 € |
| Maior histórico | 7 331 827,00 €, categoria 1 | 1 000 000,00 €, categoria 1 |

`SEM DADOS` mantém o texto e categoria `null`: não declara ausência de vencedor.

## Importação e proteção

`api-python/rss_import.py` usa apenas a biblioteca padrão. Seleciona títulos exatos
`Euromilhões` e `M1lhão`, independentemente da ordem; ignora outros jogos e rejeita
itens duplicados do mesmo jogo. Respeita a codificação XML (testes ISO-8859-1,
UTF-8, UTF-16, UTF-16BE, UTF-32 e Windows-1252), descodifica HTML/entidades e valida
estritamente as descrições reais. Mudanças de formato falham de forma explícita;
não há extração aproximada de números. DTD/entidades declaradas são proibidas,
com limite de 1 MiB e timeout de rede de 20 segundos. Não segue redirects, mesmo
para outro HTTPS; nunca consulta links do XML. TLS usa a validação padrão.

As tabelas adicionais `rss_imports` e `rss_observations` são criadas apenas ao
executar uma importação administrativa numa base explicitamente escolhida.
Registam fonte, hash, publicação UTC, primeira importação UTC, estado de validação,
conteúdo e conflito/erro. Os concursos mantêm as revisões existentes. Repetir os
mesmos bytes não duplica observações ou concursos. As escritas de observação e
concurso usam a mesma transação `BEGIN IMMEDIATE`; erros revertem todo o lote.

Cada chave é comparada com o concurso guardado e com observações anteriores dos
dois feeds. Divergências ficam em quarentena, incluindo as observações anteriores,
e são omitidas da resposta pública; nenhum concurso existente é alterado pelo RSS,
mesmo que esteja parcial. A correção de um conflito exige revisão administrativa:
não há resolução automática nem escolha de um feed como vencedor. Uma correção
administrativa posterior também impede a exposição de uma observação incompatível.
Falhas de um feed não impedem os restantes e não apagam snapshots anteriores.
`run_remote` regista falhas por fonte; a CLI também regista falhas quando a base
está acessível. Não há Cron ativado.

**Os XML não incluem a data do sorteio anterior.** Sem uma data confirmada
separadamente, a observação fica disponível mas o histórico permanece intacto.
É possível repetir o mesmo XML com `--draw-date` após confirmação. Não se usa a
data de publicação como data do sorteio. Novos concursos são `numbers_confirmed`,
com prémios/vencedores desconhecidos (`null`); não ficam `complete` sem categorias.

Exemplo exclusivamente numa base local de validação, a partir da raiz:

```sh
python3 api-python/rss_import.py --database /tmp/luckyscan50-rss-validation.sqlite3 \
  --feed results --file api-python/fixtures/rss/rssFeedCartRes.xml \
  --draw-date euromilhoes:083/2026=2026-10-16
python3 api-python/rss_import.py --database /tmp/luckyscan50-rss-validation.sqlite3 \
  --feed jackpots --file api-python/fixtures/rss/rssFeedJackpots.xml
python3 api-python/rss_import.py --database /tmp/luckyscan50-rss-validation.sqlite3 \
  --feed portal --file api-python/fixtures/rss/rssFeedPremiosPortal.xml
```

A data Euromilhões acima foi confirmada pela página oficial. O exemplo deixa
M1lhão pendente de confirmação independente da data. Omitir `--file` obtém o feed
HTTPS direto. Não executar estes exemplos com o caminho da base de produção.

## Contrato JSON e estatísticas

Novo GET **`/v1/rss/overview`**: `{data: [...], conflicts: N}`. Por jogo/feed devolve
a observação mais recente por publicação, com `sourceUrl`, `publishedAt`,
`importedAt`, `validation`, `historyStatus` e resultado; jackpots acrescenta
`upcoming`, Portal acrescenta `lastDraw` e `allTime`. `historyStatus` distingue
`stored`, `pending_draw_date` e `not_applicable`. `conflicts` conta os grupos
mais recentes em conflito, não todas as revisões. Os detalhes ficam na base
administrativa. Não há escrita HTTP. Sem SQLite configurado ou antes de qualquer
importação RSS, a resposta é vazia. Erros de armazenamento devolvem 503.

Os endpoints de resultados conservam a forma e a cache HTTP de 120 segundos.
RSS e estatísticas usam `Cache-Control: no-cache`: revalidar a cada utilização.
Não existe cache interna de estatísticas para invalidar: cada pedido usa **todo o
histórico da base**, nunca apenas um RSS. As estatísticas passam a incluir chaves
`numbers_confirmed` e `complete`, pois uma chave validada não depende da publicação
dos montantes. O campo `scope` muda de `stored_complete_draws` para
`stored_confirmed_keys`; os restantes campos mantêm a forma. A carteira Android
continua a exigir `complete` para calcular prémios, sem alterações nesta tarefa.

## Validação e limites

38 testes Python passam: regressões existentes, XML reais, codificações, HTML,
valores de referência, campos incompletos, intervalos, datas, duplicados, conflitos,
Portal separado, replay, concorrência, rollback, indisponibilidade parcial,
correções administrativas e histórico completo nas estatísticas.
Comando: `cd api-python && PYTHONDONTWRITEBYTECODE=1 python3 -m unittest discover -v`.
O workflow Python existente descobre também estes testes.

Validado localmente e por leituras HTTPS públicas; não houve implantação, Cron,
migração remota, publicação de versão ou alteração Android. Não foi necessário
compilar APK ou repetir testes Flutter para uma mudança exclusivamente backend.
Uma ativação futura deve primeiro rever a base local, as datas confirmadas e o
contrato de `scope`; os prémios efetivos continuam a depender da fonte por categoria.
