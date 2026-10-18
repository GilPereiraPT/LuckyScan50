# API pública v1

A implementação de produção é Python nativo WSGI em `api-python/`. Distribui resultados administrativos e resultados oficiais validados pelos coletores RSS/cartaz; não valida comprovativos ou credenciais de jogadores. Não existe escrita HTTP.

Todos os endpoints devolvem JSON UTF-8, `X-Content-Type-Options: nosniff` e cache de 120 segundos para 200; RSS e estatísticas usam `no-cache` para revalidação; erros usam `no-store`. Métodos diferentes de GET devolvem 405 e `Allow: GET`. Falhas de dados devolvem 503 `results_unavailable`, sem detalhes internos.

| Endpoint GET | Resposta 200 |
| --- | --- |
| `/health` | `{ "ok": true, "service": "luckyscan50-results", "version": "0.2.0", "runtime": "native_wsgi" }` |
| `/v1/draws/latest?game=euromilhoes` | Objeto do último concurso armazenado desse jogo |
| `/v1/draws?game=euromilhoes&limit=30&offset=0` | `{ "data": [], "pagination": { "limit":30,"offset":0,"total":0,"hasMore":false } }` |
| `/v1/draws/euromilhoes/083/2026` | Objeto do concurso pedido |
| `/v1/draws/milhao/009/2026` | Objeto M1lhão |
| `/v1/milhao/latest` | Alias de latest com game=milhao |
| `/v1/milhao/009/2026` | Alias do detalhe M1lhão |
| `/v1/statistics/numbers` | 50 entradas com `value,count,eligibleDraws,lastDate,drawsSinceLast` |
| `/v1/statistics/stars` | 12 entradas, com elegibilidade histórica de 9/11/12 estrelas |
| `/v1/statistics/summary` | Contagens, datas extremas, meses, pares/ímpares, dezenas e combinações repetidas |
| `/v1/rss/overview` | Observações RSS validadas, previsões e indicadores Portal separados; ver [integração RSS](rss-integration.md) |
| `/v1/sync?after=0&limit=30` | Revisões ordenadas por sequência global, cursor e `hasMore` |

Filtros `from` e `to` são datas ISO inclusivas. `limit`: 1–100; `offset` e `after`: inteiros não negativos. A paginação da lista é por ordem decrescente de data; `total` respeita filtros. As estatísticas usam chaves `complete` e `numbers_confirmed` armazenadas, identificam `scope=stored_confirmed_keys`, não afirmam cobrir todo o histórico e não fazem previsões. As dezenas são 1–10, 11–20, 21–30, 31–40 e 41–50.

Erros 400 incluem `invalid_game`, `invalid_pagination`, `invalid_date`, `invalid_date_range`, `duplicate_parameter`. Resultados inexistentes: 404 `no_validated_results` ou `draw_not_found`; rotas inexistentes: `not_found`. Uma base vazia é uma situação válida, não é preenchida com fixtures.

## Resultado

Mantém os campos existentes: `game`, `drawId` no formato `NNN/AAAA`, `date`, `sourceUrl` HTTPS, `retrievedAt` ISO com fuso e `status` (`numbers_confirmed` ou `complete`). Euromilhões inclui `numbers` (5), `stars` (2), `tiers` (13). Cada escalão tem `tier,main,stars,amountCents,winnersPortugal,winnersTotal`. Valores monetários são cêntimos inteiros. `null` é desconhecido/não atribuído, nunca converter em zero. Os dados parciais são explicitamente identificados pelo estado; consumidores não devem tratá-los como definitivos.

M1lhão inclui `winningCode` completo e `amountCents` quando conhecido. Compatibilidade permite registos legados sem prémio, sem assumir um milhão ou qualquer outro valor.

## Sincronização

SQLite devolve `{ "mode":"revisions", "data":[{"sequence":1,"revision":1,"game":"euromilhoes","drawId":"001/2026","updatedAt":"…","result":{…}}], "nextCursor":1,"hasMore":false }`. Aplicar páginas por ordem, guardar o cursor **apenas depois de persistir os resultados**, substituir o concurso pela revisão mais recente e rever prémios afetados. O cursor é global e não suporta filtros por jogo/data. Não existem eliminações nesta versão. Restaurar a base a uma cópia mais antiga pode exigir reinicialização do cursor dos clientes.

Em modo JSON não há histórico: `/v1/sync` devolve `mode=snapshot`, todos os resultados, `nextCursor=null`. Substituir a cache de resultados, sem eliminar os bilhetes pessoais.

## Fontes

Em 17/10/2026 foi possível consultar por GET as páginas públicas de referência e confirmar `/health` e o concurso 083/2026 da API existente. Isso não comprova autorização para recolha nem verificação independente do concurso. Não foi encontrado contrato documentado/autorizado de integração nesta auditoria. A versão inicial usa importação administrativa; não ativa scraping, endpoints internos, login ou Cron remoto. Fixtures sintéticas de testes usam `example.org` e nunca são importadas em produção.

A integração posterior dos três RSS oficiais está documentada em [rss-integration.md](rss-integration.md), com XML reais e verificação HTTPS. As observações RSS não fornecem valores oficiais por categoria. A importação automática não foi ativada em produção.

## Cobertura histórica

Estatísticas de números, estrelas e resumo acrescentam `coverage`, com
`historyStart=2004-02-13`, `storedFrom`, `storedTo`, `storedDrawCount`,
`isCompleteHistory=false`, `verification=not_audited` e aviso de amostra.
Os campos anteriores mantêm a forma. Um único concurso não é apresentado como
histórico integral; não há carga histórica nesta entrega.

A preparação de Cron e os limites de promoção RSS estão em
[rss-cron-cpanel.md](rss-cron-cpanel.md).

A confirmação automática dos 13 escalões e a promoção com revisão estão documentadas em [official-results-cpanel.md](official-results-cpanel.md). Os endpoints e as formas de resposta mantêm-se.
