# Histórico dos últimos 90 dias — Euromilhões

O coletor consulta o formulário público oficial Jogos Santa Casa. Usa apenas IDs que constam do seletor, envia selectContest por POST e exige que a resposta identifique exatamente o concurso pedido. Não infere datas ou chaves. Recolhe no máximo 60 opções, a um pedido por segundo, com timeout e limite de tamanho. Os resultados só são importados depois de todas as respostas selecionadas serem validadas numa cópia SQLite. Qualquer conflito impede a carga inteira.

## cPanel sem Terminal

1. Colocar historical_results.py e atualizar_historico_90_dias.py na raiz da aplicação Python, ao lado de official_cartaz.py, rss_import.py e store.py. Estes módulos já constam do pacote cPanel mais recente.
2. Preservar a variável LUCKYSCAN_DATABASE que aponta para a base existente de resultados. Não utilizar a base de emails.
3. Em Setup Python App → Executar script python, executar atualizar_historico_90_dias.py com o caminho absoluto da aplicação. Este invólucro aplica a importação autorizada, não é uma simulação. A duração depende do servidor oficial e do catálogo (até alguns minutos). Se o painel interromper o processo, consultar o relatório antes de repetir.
4. O relatório apresenta from/to (90 dias incluindo hoje em Lisboa), selectedCount, changed, unchanged, partialDraws, conflicts, oldestAvailable e latestAvailable. startBoundaryCovered=false significa que o catálogo não chega ao início solicitado. completeHistoryAudited permanece false: cobertura não se comprova apenas pela contagem ou pela periodicidade esperada.
5. Uma cópia SQLite consistente anterior à carga e os HTML originais com SHA-256 ficam em data/history-imports/INSTANTE (ou no diretório da base configurada), com permissões privadas. Preservar estes ficheiros.
6. Depois de status=imported, sincronizar na app. Não é necessário novo APK. Concursos incompletos conservam estado numbers_confirmed; não são inventados montantes de prémios.

O módulo historical_results.run() faz apenas pré-visualização por omissão. A execução pelo invólucro atualizar_historico_90_dias.py aplica as alterações. Não são enviados emails nem alterado o cron.

M1lhão não está incluído nesta carga: tem catálogo, códigos e numeração próprios. Exige parser e validação separados. A disponibilidade do formulário POST deve ser confirmada a partir do alojamento: os testes usam o HTML real preservado e transportes simulados, não provam a disponibilidade atual de todas as respostas oficiais. Se o servidor ignorar a seleção ou devolver erro, o processo para sem importar.
