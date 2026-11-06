# LuckyScan50 — resultados recentes sempre alimentados (Euromilhões e M1lhão)

## Contrato atual da API (sem mudanças na APK)

A API de produção continua a consultar **exclusivamente** a base privada de resultados;
uma leitura HTTP nunca recolhe dados da Santa Casa nem altera a base SQLite.

- `GET /v1/draws?game=euromilhoes&limit=100&offset=0` — mais recentes primeiro, paginação `hasMore` (o Android já percorre as páginas).
- `GET /v1/draws?game=milhao&limit=100&offset=0` — histórico M1lhão, com códigos.
- `GET /v1/draws/latest?game=euromilhoes` e `?game=milhao` — último concurso **guardado**, não confirmação independente de que a origem está atualizada.
- `GET /v1/draws/euromilhoes/086/2026` e `.../088/2026`; `GET /v1/draws/milhao/010/2026` — provas de cobertura para o caso observado.

Não anunciar "está atualizado" só por obter HTTP 200: devem existir os resultados esperados no armazenamento e os seus estados devem ser `complete` quando o operador publicar os prémios.

## Dois processos de recolha

**1. Coletor frequente**: no `collect_results.py --rss` a configuração passa a permitir `milhao: true` (ativado por omissão no modo CLI, com `enabled: true`). A cada execução lê as três fontes RSS existentes, o último cartaz Euromilhões (`cartaz: true`) e o último cartaz M1lhão (`milhao: true`), com falhas independentes. Os resultados só entram depois de validação de concurso, data, chave/código e prémios. Uma incompatibilidade não substitui o anterior.

**2. Recuperação diária**: executar `atualizar_resultados_90_dias.py` uma vez por dia. Usa o seletor público dos cartazes oficiais, recolhe os concursos apresentados do intervalo de 90 dias por jogo, confirma IDs/datas e importa faltas ou promoções de parcial para completo. Se não houver alterações não cria novas revisões nem backups grandes. Uma falha no Euromilhões não impede tentar o M1lhão e vice-versa. Regista um resumo JSON e devolve um código de saída diferente de zero quando existirem falhas, conflitos ou prémios parciais.

A atualização é **periódica**, não instantânea. Depende da publicação oficial, da disponibilidade dos cartazes e de tarefas agendadas no alojamento. Uma falha deve ser visível nos relatórios/alertas; não se inventam resultados.

## Instalação no cPanel — sem terminal

1. Fazer uma cópia consistente da base SQLite e guardar os ficheiros de configuração atuais. **Não substituir** `results.sqlite3`, `.env`, `rss-collector.json`, ficheiros privados ou configurações Passenger pelo ZIP do GitHub.
2. Copiar os módulos atualizados `collect_results.py`, `official_milhao.py`, `historical_results.py`, o novo `atualizar_resultados_90_dias.py` e os testes (fora da pasta pública), preservando `passenger_wsgi.py`, `store.py`, `official_cartaz.py`, `rss_import.py` e as restantes dependências compatíveis.
3. Confirmar em **Setup Python App** do cPanel que `LUCKYSCAN_DATABASE` aponta para a mesma base SQLite privada que a aplicação Passenger utiliza. No Cron, as variáveis Passenger não são necessariamente herdadas: o processo diário pode ler `rss-collector.json` da pasta Python se tiver `enabled: true`, `database` correto e caminho absoluto.
4. Rever `rss-collector.json` na pasta `api-python`: manter `enabled: true` **apenas depois de validar a instalação**, `cartaz: true` e `milhao: true`. Não substituir um ficheiro de configuração privado pelo exemplo.
5. No **Cron Jobs** do cPanel, manter/verificar o comando existente para a recolha frequente (por exemplo a cada 30 minutos):

```cron
*/30 * * * * "$HOME/virtualenv/api-luckyscan50/3.12/bin/python" "$HOME/api-luckyscan50/collect_results.py" --rss --config "$HOME/api-luckyscan50/rss-collector.json"
```

6. Adicionar a tarefa de recuperação diária, por exemplo às 06:15 (hora do servidor):

```cron
15 6 * * * "$HOME/virtualenv/api-luckyscan50/3.12/bin/python" "$HOME/api-luckyscan50/atualizar_resultados_90_dias.py"
```

Os comandos são exemplos: confirmar no painel o nome real da aplicação, executável, pasta e fuso horário do servidor. Não criar tarefas duplicadas. Utilizar o email de notificações do Cron para receber relatórios de erros.

## Verificação depois do deployment

1. No cPanel, executar `atualizar_resultados_90_dias.py` pela ferramenta de execução Python, ou aguardar pelo primeiro Cron.
2. Confirmar JSON com `status: ok`, `exitCode: 0`, `games.euromilhoes` e `games.milhao`. `up_to_date` significa sem alterações novas; `conflicts_no_import`, `partialDraws`, `failed` e `exitCode: 1` requerem revisão.
3. Confirmar na API a presença dos concursos 086/2026, 088/2026 e M1lhão 010/2026 e que os dados correspondem aos cartazes publicados. Verificar também `pagination.hasMore`.
4. Abrir a APK e tocar em atualizar. O estado dos bilhetes deverá ser recalculado com base nos resultados agora guardados, sem mexer na carteira local.

**Esta alteração no GitHub não constitui instalação ou execução no alojamento.** Depois de deploy e Cron verificados, a APK atual não precisa de alterações para consultar os novos concursos.
