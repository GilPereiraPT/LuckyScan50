# API Python LuckyScan50

Produção: **Python 3.12, Passenger/WSGI nativo**, biblioteca padrão apenas. O ponto de entrada continua a ser `passenger_wsgi.py:application`. Não requer Flask, ASGI nem processo permanente. O backend TypeScript permanece como referência e regressão.

## Desenvolvimento

```sh
cd api-python
python3 -m unittest discover -v
PORT=3001 python3 app.py
```

`app.py` serve apenas desenvolvimento. Em Passenger configurar application root fora da pasta pública, startup `passenger_wsgi.py`, entry point `application`. Copiar **todos os módulos Python e a pasta migrations**. Não alterar o WordPress nem outras aplicações. A alteração do repositório não faz deploy.

## Dados e migração

Sem `LUCKYSCAN_DATABASE`, continua a ler `LUCKYSCAN_RESULTS_FILE` (por omissão `data/results.json`). Assim, a atualização do código não migra nem substitui dados implicitamente.

Antes da mudança, guardar uma cópia externa do diretório de dados. Escolher um caminho privado absoluto e dar acesso de leitura/escrita apenas ao utilizador Passenger. Testar numa cópia:

```sh
python3 import_result.py /caminho/privado/results.json --legacy --database /caminho/privado/results.sqlite3
```

A migração valida todo o JSON, rejeita duplicados, guarda uma cópia `.HASH.bak` dos bytes originais e importa numa transação. Não altera o JSON. A repetição é idempotente. Só depois de verificar os resultados configurar `LUCKYSCAN_DATABASE=/caminho/privado/results.sqlite3` e reiniciar Passenger no painel. As leituras nunca criam bases vazias silenciosamente; uma base ausente devolve 503 nos endpoints de dados. `/health` verifica o processo, não a integridade da base.

O comando legado `python3 import_result.py ficheiro.json`, sem configuração SQLite, continua a atualizar `LUCKYSCAN_RESULTS_FILE` com bloqueio, substituição atómica e cópia de cada versão anterior. SQLite é recomendado para produção.

Importação administrativa de um objeto ou lista JSON previamente conferida:

```sh
python3 import_result.py /caminho/validado.json --database /caminho/privado/results.sqlite3
```

Cada correção preserva a versão anterior em `revisions`. A atualização de `retrievedAt` isolada não cria revisão. Um resultado completo não pode regredir para parcial. Registos M1lhão legados sem `amountCents` continuam legíveis; o prémio permanece desconhecido e nunca é inferido.

## Cron: inbox e RSS, sem ativação automática

O modo `collect_results.py --inbox` é um adaptador de **caixa de entrada administrativa local**, sem HTTP. O modo `--rss`, descrito abaixo, usa os três RSS públicos oficiais. Nenhum modo acede a contas de jogadores ou endpoints internos.

```sh
python3 collect_results.py --database /caminho/privado/results.sqlite3 --inbox /caminho/privado/inbox
```

O diretório deve existir. `flock` impede execuções simultâneas; cada ficheiro é transacional, fica retido e pode ser corrigido e repetido. Erros produzem código de saída 1. Não regista conteúdos de bilhetes nem credenciais. Um JSON parcial permanece `numbers_confirmed`; um novo ficheiro completo cria revisão. O modo inbox não faz pedidos HTTP; o modo RSS usa uma tentativa limitada por fonte em cada ciclo.

Depois de validar caminhos, permissões e execução manual no cPanel, o proprietário pode configurar Cron para terça/sexta após publicação, tendo em conta o fuso horário do alojamento. Não ativar Cron nesta tarefa. Alternativa: workflow manual `validate-results.yml` valida um ficheiro previamente revisto no GitHub e produz uma base como artefacto, sem deploy nem acesso ao alojamento.

## Recuperação

Desativar importações antes de restaurar. Guardar a base atual e usar a API SQLite backup para uma cópia consistente (não copiar uma base durante escrita). Restaurar a cópia privada com permissões adequadas, executar `PRAGMA integrity_check`, testar endpoints e só então reativar importações. Para rollback de migração, remover a variável `LUCKYSCAN_DATABASE` e apontar para o JSON original preservado; isso não reverte correções posteriores da base. Esquemas futuros desconhecidos são rejeitados pelo importador.

Os contratos e limitações estão em `../docs/results-api.md`.

## RSS oficiais (validação local)

`rss_import.py` importa resultados, previsões e indicadores do Portal em tabelas
separadas. Não altera concursos existentes; conflitos ficam em quarentena.
Não atribui prémios com base no Portal ou no jackpot. A data do sorteio anterior
exige confirmação explícita; não é inferida da publicação RSS.

Ver [integração, auditoria de prémios e comandos locais](../docs/rss-integration.md).
GET `/v1/rss/overview` é uma extensão JSON de leitura. Não há Cron ou deployment
automático. Estatísticas usam o histórico completo de chaves confirmadas e
`scope=stored_confirmed_keys`, com revalidação HTTP em cada pedido.

### Coletor periódico RSS

`collect_results.py --inbox` mantém o comportamento JSON. O novo modo `--rss`
usa os três feeds oficiais com HTTPS e o bloqueio da mesma base. Requer SQLite
existente e configuração explícita; `rss-collector.example.json` vem desativado.
O modo `--fixtures` executa a recolha offline sem HTTP. Não ativa Cron ou migra JSON.

Ver [instalação, comando Cron e rollback](../docs/rss-cron-cpanel.md) e
[investigação do histórico desde 2004](../docs/historical-results-sources.md).
`backup_results.py` cria backups SQLite consistentes sem sobrescrever ficheiros.
Estatísticas acrescentam `coverage` para distinguir a amostra guardada de um
histórico integral não auditado.

## Cartaz oficial e prémios automáticos

O coletor CLI passa a consultar o cartaz Euromilhões com o mesmo lock do RSS,
por omissão (`cartaz: true`, opcional). Datas explícitas e os 13 escalões completos
permitem promover parciais compatíveis com revisão; divergências ficam em quarentena.
Não usa pubDate como data, jackpot como prémio unitário ou valores Portal como escalões.

Ver [ficheiros a atualizar e instalação sem mudar Cron](../docs/official-results-cpanel.md).

## Proprietário e estatísticas da app

Os serviços opcionais de proprietário, métricas com consentimento e painel
privado estão descritos em [configuração dos serviços da app](../docs/OWNER_AND_APP_STATISTICS.md).
No pacote cPanel, consulte `INSTALAR_PROPRIETARIO_E_ESTATISTICAS.md`.
