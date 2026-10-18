# Coletor RSS para cPanel — instalação e reversão

Código preparado para Python 3.12.15 e Passenger WSGI. Esta entrega não instala
ficheiros no alojamento, não configura Cron e não executa recolhas remotas.
Todos os testes novos são offline, com os XML reais já guardados no repositório.
Android, dependências e dados de produção ficam intactos.

Atualização 18/10/2026: ver [cartaz oficial e ficheiros a atualizar](official-results-cpanel.md). O comando Cron existente mantém-se.

## Auditoria

- `rss_import.py`: já tinha HTTPS direto, validação dos três XML reais,
  proveniência, snapshots idempotentes e conflitos. Reutilizado; acrescentada
  proteção de datas posteriores à publicação e persistência da quarentena por
  datas divergentes. O registo de erro deixa de interromper outros feeds se a
  própria auditoria de falha estiver indisponível.
- `store.py`: mantido. Importações transacionais e revisões, chave única
  `(game,drawId)`. O coletor não substitui concursos confirmados. O cartaz oficial pode promover um parcial compatível com uma nova revisão.
- `collect_results.py`: o modo `--inbox` continua compatível e sem HTTP. Novo
  `--rss` consulta as três fontes, usando o mesmo bloqueio `database.sqlite3.lock`.
- `app.py`: mantido; só serve desenvolvimento. O ponto de entrada de produção
  continua `passenger_wsgi.py:application` e não executa recolha durante pedidos.
- Estatísticas: conservam os campos anteriores e acrescentam `coverage`, que
  informa amostra, período armazenado e histórico integral não auditado.

## Comportamento e limites

Fontes fixas HTTPS: `https://www.jogossantacasa.pt/web/SCRss/` seguido de
`rssFeedCartRes`, `rssFeedJackpots` ou `rssFeedPremiosPortal`. Timeout de I/O:
20 segundos; tamanho máximo: 1 MiB por feed; TLS padrão com verificação de
certificados; redirects recusados, incluindo downgrade HTTP. Não consulta os
links HTTP contidos no XML. Sem retries agressivos: nova tentativa no próximo Cron.

A execução remota exige **`--rss` e `enabled: true` na configuração**. O ZIP traz
apenas um exemplo desativado. O coletor recusa criar uma base nova em modo RSS:
exige caminho absoluto de uma base SQLite existente e válida. Não converte JSON
nem muda variáveis Passenger implicitamente. Se a API ainda lê `results.json`,
a recolha SQLite não aparecerá na API até se validar uma conversão e configurar
ambos para a mesma base. Não criar uma base vazia para contornar esta verificação.

Antes de promover novos resultados, guarda e compara os três feeds. Conflitos
ficam em quarentena, com conteúdo, origem, publicação, primeira importação e estado
na base. Um feed indisponível não apaga dados nem impede os restantes. O Portal é
`portal_only`; jackpots são anúncios/previsões, nunca prémios unitários de apostas.
M1lhão mantém numeração e datas independentes. Não há alterações destrutivas de
esquema: apenas criação das tabelas RSS adicionais quando ainda não existem.

**Datas dos sorteios anteriores:** estes RSS não as contêm. Um resultado novo
só entra no histórico se a data tiver sido explicitamente anunciada num snapshot
anterior do RSS de jackpots, para o mesmo jogo e concurso, ou estiver num ficheiro
administrativo de datas confirmadas. Exemplo: anúncio de 084/2026 para 20/10/2026;
quando chega a chave 084/2026, essa data permite a sua inserção. A data de publicação
não é usada como data do sorteio. Na primeira execução, concursos sem uma data
confirmada ficam observações `pending_draw_date`. Se o Cron perder todos os anúncios
relevantes entre execuções, também exige confirmação administrativa da data.
Datas anunciadas divergentes não são escolhidas automaticamente: ambas ficam
registadas, os anúncios são ocultados do overview e o concurso não é promovido.

Resultados RSS sem cartaz completo são `numbers_confirmed`, com prémios por categoria desconhecidos. O cartaz oficial, quando integralmente validado, permite `complete`.
O Android existente exige `complete` para calcular prémios; RSS não substitui a
validação administrativa dos valores efetivos das 13 categorias.

O bloqueio é não bloqueante: uma execução sobreposta é ignorada antes de qualquer
HTTP. O modo inbox usa o mesmo lock. Os importadores administrativos independentes
continuam protegidos pelas transações SQLite; suspender todos os escritores para
uma restauração. Códigos de saída: `0` sucesso/repetição/lock ocupado (os logs
distinguem), `1` falha de transporte/validação/configuração/armazenamento, `2` conflito.
`pendingDate` é um aviso para revisão, não uma data inventada. A chave `offline`
distingue testes locais de uma execução remota.

## Instalação sem ativação automática

1. No cPanel, confirmar application root `api-luckyscan50`, startup
   `passenger_wsgi.py`, entry point `application`, e copiar o executável Python
   indicado pelo painel. Confirmar o valor efetivo de `LUCKYSCAN_DATABASE`.
   Variáveis do Passenger não são automaticamente herdadas pelo Cron.
2. Guardar cópia dos ficheiros Python e da configuração fora da pasta da aplicação.
   Não substituir `data/`, JSON, SQLite, `.env` ou a configuração Passenger.
3. Extrair o ZIP **dentro de `api-luckyscan50`**: os módulos vêm na raiz, sem
   pasta `api/` intermédia. Os testes ficam em `validacao/`; não são dados de produção.
   São incluídos módulos auxiliares e `migrations/001_initial.sql` necessários à
   compatibilidade, sem executar a migração ou qualquer comando na extração.
4. Copiar `rss-collector.example.json` para `rss-collector.json` e editar caminhos
   absolutos para a base SQLite **já usada pela API** e para o ficheiro privado de
   datas. Manter `enabled: false` enquanto valida. Copiar
   `verified-draw-dates.example.json` para esse caminho privado; a lista vazia é
   válida. Restringir configurações, dados e backups ao utilizador da aplicação.
5. Se estiver em modo JSON, parar aqui a ativação do Cron. Preparar uma cópia privada
   do JSON e uma base SQLite de staging com `import_result.py --legacy --database`,
   validar contagens/chaves/categorias, backups e endpoints antes de propor a troca
   da variável `LUCKYSCAN_DATABASE`. Não faz parte desta entrega executar essa troca.
6. Na base SQLite existente, obter backup consistente antes de ativar. Exemplo
   para os caminhos convencionais do cPanel (ajustar se o painel indicar outros):

```sh
APP="$HOME/api-luckyscan50"
PYTHON="$HOME/virtualenv/api-luckyscan50/3.12/bin/python"
"$PYTHON" "$APP/backup_results.py" --config "$APP/rss-collector.json" \
  --output "$HOME/private/luckyscan50/pre-rss.sqlite3"
```

O destino deve estar numa pasta existente e **não existir**. O utilitário usa a
API de backup SQLite, abre a origem em leitura, verifica `integrity_check` e não
sobrescreve backups. Não copiar uma base ativa apenas com `cp`.

7. Executar os testes do ZIP, sem HTTP:

```sh
cd "$HOME/api-luckyscan50"
PYTHON="$HOME/virtualenv/api-luckyscan50/3.12/bin/python"
"$PYTHON" -m unittest discover -s validacao/api-python -v
```

Para testar a CLI, usar uma **cópia da base e uma configuração de validação**,
com caminhos absolutos e `enabled: false`:

```sh
"$PYTHON" collect_results.py --rss --config /caminho/privado/validacao-rss.json \
  --fixtures "$PWD/validacao/api-python/fixtures/rss"
```

Este comando não faz HTTP, mas escreve observações na base de validação indicada.
Não executar com os caminhos de produção durante os testes.

8. Após revisão, reiniciar a aplicação Python pelo painel e verificar `/health`,
   resultados anteriores, `/v1/rss/overview`, `/v1/statistics/numbers` e
   `/v1/statistics/stars`. Sem recolha ativa, os resultados anteriores permanecem.
9. Só quando autorizar a recolha real, alterar `enabled` para `true`, executar
   manualmente uma vez o comando abaixo, rever saída/logs e então registar o Cron.
   Não foi executado qualquer destes passos remotos pelo desenvolvimento.

## Comando exato de Cron

Para application root `$HOME/api-luckyscan50` e o virtualenv cPanel convencional
`$HOME/virtualenv/api-luckyscan50/3.12/bin/python`:

```cron
*/30 * * * * "$HOME/virtualenv/api-luckyscan50/3.12/bin/python" "$HOME/api-luckyscan50/collect_results.py" --rss --config "$HOME/api-luckyscan50/rss-collector.json" >> "$HOME/private/luckyscan50/rss-cron.log" 2>&1
```

No formulário **Cron Jobs** do cPanel: minuto `*/30`, restantes campos `*`;
no campo Command colocar apenas a parte a partir de `"$HOME/virtualenv/...`.
Criar antes a pasta privada do log, com permissões adequadas. Confirmar o executável
no painel: se os caminhos forem diferentes, usar os caminhos reais. O nome e caminho
da base devem corresponder ao Passenger, conforme `rss-collector.json`.
A frequência de 30 minutos é ajustável; não há Cron criado automaticamente.
Rodar o log periodicamente, sem apagar as tabelas de auditoria.

Formato de uma data revista, apenas após confirmação da fonte independente:

```json
[
  {
    "game": "euromilhoes",
    "drawId": "083/2026",
    "date": "2026-10-16",
    "sourceUrl": "https://www.jogossantacasa.pt/web/SCCartazResult/euroMilhoes"
  }
]
```

A data deste exemplo Euromilhões foi verificada na auditoria anterior. Não estender
esse exemplo a M1lhão apenas porque os feeds têm a mesma data de publicação.
Não colocar credenciais, URLs de contas de jogador ou bilhetes pessoais no ficheiro.

## Reversão

1. Remover/desativar a entrada Cron e repor `enabled: false`. Esperar pelo fim de
   qualquer execução, confirmando o lock livre; suspender importações administrativas.
2. Guardar backup consistente do estado atual antes de qualquer reversão de dados.
3. Para reversão de **código**, repor os módulos anteriores e reiniciar Passenger.
   As tabelas RSS são adicionais e podem permanecer: não precisam de ser apagadas.
   Conservar configuração/dados e confirmar os endpoints anteriores.
4. Restaurar a base `pre-rss.sqlite3` **apenas se necessário e após revisão**: pode
   remover concursos ou correções legítimas posteriores ao backup. Com todos os
   escritores parados, preservar a base atual e os eventuais ficheiros WAL/SHM como
   conjunto, restaurar uma cópia do backup consistente e verificar
   `PRAGMA integrity_check`, contagens e resultados. Não misturar WAL/SHM antigos
   com o backup restaurado. Reaplicar alterações posteriores revistas, se necessário.
5. Só reativar escritores após validar. Repor a variável de dados anterior se esta
   tiver sido alterada manualmente; não substituir os dados originais preservados.

## Histórico desde 13/02/2004

Ver [investigação e critérios de aceitação](historical-results-sources.md). Este
coletor não preenche o passado a partir de RSS, não importa fixtures em produção e
não declara histórico integral por haver um concurso. `coverage.isCompleteHistory`
permanece `false`, com `verification=not_audited`, até existir auditoria própria.
