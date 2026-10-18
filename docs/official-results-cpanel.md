# Atualização automática: cartaz oficial e revisões — 18/10/2026

A atualização acrescenta ao coletor existente a leitura do cartaz oficial do
Euromilhões. Não instala em produção, não modifica a SQLite de produção, não muda
o Cron e não altera Android ou dependências.

## Ficheiros a atualizar no cPanel

| Ficheiro na raiz `api-luckyscan50` | Alteração |
| --- | --- |
| **`official_cartaz.py`** | Novo: transporte HTTPS, análise do HTML oficial, 13 escalões e reconciliação transacional. |
| **`collect_results.py`** | Alterado: consulta o cartaz dentro do bloqueio existente, antes da promoção RSS; falhas independentes. |
| **`rss_import.py`** | Alterado: mantém em quarentena divergências entre cartaz e RSS também nas repetições de importação. |

`store.py`, `domain.py`, `app.py`, `passenger_wsgi.py` e os restantes módulos
mantêm-se inalterados no repositório. O pacote completo inclui-os para manter
correspondência entre versões; `Store.import_rows()` deve suportar a conexão
transacional `_connection`, como na entrega anterior. Não copiar bases de dados,
JSON de resultados, `.env` ou configurações Passenger.

Os novos testes são `test_official_cartaz.py` e o fixture HTML real em
`fixtures/official/`. No pacote, ficam em `validacao/`, separados da aplicação.
`rss-collector.example.json` acrescenta `cartaz: true` mas continua com
`enabled: false`. Não substituir `rss-collector.json` privado pelo exemplo.

## Instalação sem alterar o Cron

1. Guardar cópia dos três módulos antigos e um backup consistente da SQLite com
   `backup_results.py`. Não copiar uma base ativa apenas com `cp`. Preservar o
   ficheiro privado de configuração, o JSON legado e a variável de dados Passenger.
2. Validar primeiro numa cópia da aplicação/base. Atualizar os três ficheiros
   acima, com o módulo novo na mesma pasta de `collect_results.py`. É possível
   extrair o pacote completo numa pasta de staging; não inclui dados de produção.
3. Executar os testes offline do pacote, a partir dessa pasta:

```sh
"$HOME/virtualenv/api-luckyscan50/3.12/bin/python" -m unittest discover -s validacao/api-python -v
```

4. Testar o coletor com uma configuração que aponte **apenas para a cópia da base**,
   mantendo `enabled: false`:

```sh
"$HOME/virtualenv/api-luckyscan50/3.12/bin/python" collect_results.py \
  --rss --config /caminho/privado/staging-rss.json \
  --fixtures "$PWD/validacao/api-python/fixtures/rss"
```

O diretório irmão `fixtures/official/` é usado para o cartaz; nenhum pedido HTTP é
feito neste modo. O snapshot real contém Euromilhões 083/2026, data 16/10/2026 e 13
escalões. O M1lhão permanece pendente se a cópia não tiver uma data confirmada.

5. Rever os resultados e as revisões, incluindo `/v1/draws/latest`, `/v1/sync` e
   `/v1/rss/overview` na aplicação de staging. O último mantém a forma anterior
   `{data,conflicts}`; a auditoria do cartaz fica em `official_observations` e no
   relatório do coletor, sem novo endpoint de escrita.
6. Após aprovação da instalação, colocar os ficheiros revistos na aplicação
   existente e reiniciar Passenger pelo painel. **Não modificar o Cron existente**:
   o comando `collect_results.py --rss --config ...` continua igual. Na CLI,
   `cartaz` é `true` por omissão, mesmo para a configuração anterior sem essa chave.
   `cartaz: false` permite conservar o modo de três RSS. `enabled` mantém o mesmo
   significado e continua necessário para pedidos remotos.
7. A primeira execução autorizada cria apenas `official_observations`, de forma
   aditiva. Não existe migração destrutiva ou mudança de `PRAGMA user_version`.
   Confirmar que Cron e Passenger continuam a usar a mesma base.

Os caminhos do executável acima são os convencionais do cPanel; usar o executável
real indicado pelo painel, caso seja diferente. Nada foi executado no alojamento
pelo desenvolvimento. A autorização para alterar código de produção/Cron não é
substituída pela preparação deste pacote.

## Regras de associação e dados pendentes

- A data vem de `Data do Sorteio` no cartaz, associada ao `Sorteio: NNN/AAAA` e à
  chave da mesma zona do HTML. Não se usa a opção selecionada de outro concurso,
  uma data do rodapé ou a publicação RSS. A chave e a ordem de saída devem concordar.
- Euromilhões e M1lhão usam sempre `(game,drawId)`. O cartaz Euromilhões não confirma
  datas, códigos ou prémios M1lhão. Para M1lhão continuam válidos um anúncio oficial
  previamente guardado no RSS jackpots ou uma data administrativa revista com origem
  HTTPS; na falta disso, a observação fica `pending_draw_date`. Não se assume o dia
  do Euromilhões por partilharem a publicação RSS.
- Cada escalão 1–13 tem identidade de acertos, montante unitário, vencedores Portugal
  e total. Validam-se intervalos, integridade, duplicados e contagens PT <= total.
  Valores monetários são cêntimos inteiros, sem floats.
- Notas `(1)`/`(2)` em escalões sem vencedores preservam `amountCents: null`. Nunca
  se segue a nota até ao jackpot previsto para atribuir um prémio individual. Zero
  explícito num escalão não atribuído é normalizado para `null`; números positivos
  com zero vencedores são rejeitados.
- Se falta uma categoria, montante devido ou contagem necessária, o resultado é
  `numbers_confirmed`, não `complete`. A tabela inteira ausente deixa as 13 categorias
  desconhecidas. Data/cabeçalho/chave ambíguos ou inválidos impedem a importação do
  cartaz; a observação RSS pode continuar pendente. Valores ausentes não são inferidos.
- Todos os feeds são guardados/comparados antes da reconciliação. Um cartaz válido
  pode confirmar um concurso mesmo se um RSS estiver indisponível; uma divergência
  explícita para o mesmo jogo/concurso impede a confirmação automática.
- Um concurso novo é inserido via `Store.import_rows()`. Um parcial só passa a
  `complete` se chave, data e campos já conhecidos forem compatíveis; fica uma nova
  revisão. Dados parciais posteriores não apagam dados antigos ou fazem downgrade.
  Concursos `complete` compatíveis não mudam nem criam revisão; divergentes são
  registados para análise e não são substituídos. A mesma resposta repetida não
  duplica concursos, revisões ou snapshots válidos.

## Proveniência, disponibilidade e compatibilidade

O leitor usa apenas a biblioteca padrão (`urllib`, `HTMLParser`, SQLite), HTTPS
fixo para `https://www.jogossantacasa.pt/web/SCCartazResult/euroMilhoes`, timeout de
20 segundos, limite de 1 MiB, limite de profundidade HTML e recusa de redirects.
Não acede a contas de jogadores, endpoints privados ou links fornecidos no HTML.
Mudanças de estrutura inesperadas falham de forma explícita; não há extração
aproximada ou completamento por valores conhecidos.

A tabela adicional `official_observations` guarda URL, hash dos bytes, jogo,
concurso, primeira importação, candidato analisado, estado e motivos de conflito.
`published_at` fica **null**: a data do sorteio não é uma publicação oficial do HTML.
RSS conserva os seus instantes de publicação/importação nas tabelas existentes.
A observação e a revisão do concurso são persistidas na mesma transação SQLite.

O `flock` existente abrange também o cartaz. Falhas do cartaz não impedem os RSS ou
M1lhão; falhas RSS não apagam resultados anteriores. Os logs distinguem erro,
pendente, correspondência e conflito. O relatório passa a incluir `feeds.cartaz`;
os códigos de saída anteriores mantêm-se. As estatísticas continuam calculadas
sobre o histórico SQLite e com cobertura explicitamente não auditada.

Testes executados: **76 testes Python passam**, incluindo o HTML real guardado na
auditoria de 17/10/2026 e os três XML reais; novos concursos, repetição, promoção
com duas revisões, dados pendentes, conflitos de data/chave/montante, escalões
incompletos, `null`, independência M1lhão, falhas parciais, lock e contratos HTTP.
Nenhuma dependência experimental Python foi encontrada nos requisitos de produção;
não foram acrescentadas bibliotecas ou removidos módulos necessários.

A consulta de leitura ao cartaz M1lhão em 18/10/2026 foi bloqueada pelo proxy do
ambiente com **403 Forbidden**. Não foi implementado um parser não verificado desse
HTML nem contornado o proxy. Os testes do cartaz Euromilhões usam a captura real
preservada; não comprovam o acesso atual a partir do cPanel ou o formato de páginas
futuras. A validação remota deve ser feita numa cópia após autorização.

## Reversão

Desativar recolhas apenas com aprovação do responsável pelo alojamento; esperar
pelo fim da execução e preservar a base atual antes de restaurar ficheiros.
Repor `collect_results.py` e `rss_import.py` anteriores, retirar o módulo novo se já
não for importado e reiniciar Passenger. A tabela adicional pode permanecer;
**não é necessário apagar dados ou alterar o Cron** para reverter só o código.
As revisões confirmadas entretanto permanecem compatíveis com o Store anterior.
Restaurar um backup da base apenas após revisão, pois pode eliminar correções
legítimas posteriores. Procedimento SQLite/WAL detalhado em `rss-cron-cpanel.md`.
