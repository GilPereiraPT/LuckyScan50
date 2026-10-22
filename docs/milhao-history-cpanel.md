# Histórico M1lhão — últimos 90 dias

Carregar na raiz da aplicação Python: historical_results.py (nova versão comum, compatível com Euromilhões), official_milhao.py e atualizar_milhao_90_dias.py. Executar o último em Setup Python App, sem argumentos. Requer LUCKYSCAN_DATABASE já configurada para a base existente de resultados, não a de emails.

Usa o catálogo público e POST selectContest da página oficial M1lhão, independentemente do Euromilhões. A data, o código e o montante do prémio vêm da resposta de cada concurso. Valida o concurso devolvido, um único código de três letras e cinco dígitos, um vencedor e o montante unitário. Múltiplos códigos ou estrutura ambígua param a carga para revisão; não se escolhe o primeiro silenciosamente. Prémio ausente fica pendente, sem valor inventado.

Valida toda a carga numa cópia SQLite, verifica conflitos contra dados existentes/RSS, guarda HTML e hashes e cria backup consistente antes da importação transacional. A repetição não cria concursos/revisões duplicados. A cópia e o manifesto ficam em data/history-imports/INSTANTE, com permissões privadas.

O relatório mostra o intervalo inclusivo de 90 dias em Lisboa, a cobertura disponível, novos/inalterados/conflitos e a data efetivamente mais recente da fonte. Não garante que a fonte esteja atualizada até hoje: a consulta inicial de 20/10/2026 devolveu 009/2026 de 25/09/2026. Não se geram códigos, datas ou números de concurso para preencher lacunas. O histórico completo continua por auditar.

Os testes locais de estrutura são controlados, não capturas originais. O workflow Inspect official Milhao history verifica adicionalmente o parser contra a página oficial real e conserva os bytes como artefacto. A validação do formulário POST e dos concursos históricos faz-se durante a recolha; se a seleção for ignorada ou uma resposta falhar, não são importados resultados dessa carga.

Depois de status=imported, sincronizar a app. Não é necessário novo APK. Não altera as definições de email nem o cron.
