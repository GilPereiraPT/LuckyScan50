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

Importação administrativa de um objeto ou lista JSON previamente conferida:

```sh
python3 import_result.py /caminho/validado.json --database /caminho/privado/results.sqlite3
```

Cada correção preserva a versão anterior em `revisions`. A atualização de `retrievedAt` isolada não cria revisão. Um resultado completo não pode regredir para parcial. Registos M1lhão legados sem `amountCents` continuam legíveis; o prémio permanece desconhecido e nunca é inferido.

## Cron, sem ativação automática

`collect_results.py` é um adaptador de **caixa de entrada administrativa local**, não um scraper. Não foi identificada documentação suficiente que autorize recolha automática. Não acede a contas de jogadores ou endpoints internos.

```sh
python3 collect_results.py --database /caminho/privado/results.sqlite3 --inbox /caminho/privado/inbox
```

O diretório deve existir. `flock` impede execuções simultâneas; cada ficheiro é transacional, fica retido e pode ser corrigido e repetido. Erros produzem código de saída 1. Não regista conteúdos de bilhetes nem credenciais. Um JSON parcial permanece `numbers_confirmed`; um novo ficheiro completo cria revisão. Não há retries HTTP porque não há fornecedor remoto autorizado.

Depois de validar caminhos, permissões e execução manual no cPanel, o proprietário pode configurar Cron para terça/sexta após publicação, tendo em conta o fuso horário do alojamento. Não ativar Cron nesta tarefa. Alternativa: workflow manual `validate-results.yml` valida um ficheiro previamente revisto no GitHub e produz uma base como artefacto, sem deploy nem acesso ao alojamento.

## Recuperação

Desativar importações antes de restaurar. Guardar a base atual e usar a API SQLite backup para uma cópia consistente (não copiar uma base durante escrita). Restaurar a cópia privada com permissões adequadas, executar `PRAGMA integrity_check`, testar endpoints e só então reativar importações. Para rollback de migração, remover a variável `LUCKYSCAN_DATABASE` e apontar para o JSON original preservado; isso não reverte correções posteriores da base. Esquemas futuros desconhecidos são rejeitados pelo importador.

Os contratos e limitações estão em `../docs/results-api.md`.
