# Estatísticas oficiais: importação auditável e limitações

## Estado verificado em 18/10/2026

Foi acrescentada uma via de importação de **agregados** dos 50 números e 12
estrelas, independente dos concursos individuais existentes. Nenhum snapshot
real de estatísticas foi fornecido nesta tarefa. As consultas HTTPS normais a
`SCEstatisticas`, `SCMotorBusca` e `SCCartazResult` falharam no CONNECT do proxy
com `403 Forbidden`, antes de chegar ao operador. Não houve alteração do proxy,
recolha por outra rota, recolha histórica nem alteração da base de produção.

Por esse motivo **não foi possível validar o snapshot de 17/10/2026 às 03:00**,
a estrutura atual da página, a disponibilidade remota ou os termos de
reutilização. A integração remota permanece opt-in. O adaptador HTML exige um
perfil semântico estrito, testado com HTML sintético; não é uma afirmação de
compatibilidade com o HTML atual dos Jogos Santa Casa. Uma captura real poderá
exigir adaptar esse perfil, com nova fixture e testes, antes de o ativar.

Os testes geram dados sintéticos no código de teste, expressamente identificados
como tal. Esses valores não são os do operador, não são distribuídos como
snapshot de produção e não foram carregados na base de produção.

## Contrato aditivo da API

`GET /v1/statistics/official` devolve `available:false,data:null` enquanto não
existir uma importação válida. Não preenche valores de exemplo. Depois de uma
importação, o contrato é:

```json
{
  "available": true,
  "data": {
    "schemaVersion": 1,
    "game": "euromilhoes",
    "sourceUrl": "https://www.jogossantacasa.pt/web/SCEstatisticas/",
    "updatedAt": "<instante da fonte normalizado para UTC>",
    "coverageStart": "2004-02-13",
    "importedAt": "<instante da importação UTC>",
    "sourceSha256": "<SHA-256 dos bytes efetivamente importados>",
    "validation": "structure_validated",
    "snapshotReferenceVerified": false,
    "numbers": [],
    "stars": []
  },
  "prediction": false,
  "conflicts": 0,
  "comparison": {},
  "notice": "<limitações da fonte e da cobertura>"
}
```

As listas vazias acima ilustram apenas os campos; uma importação válida exige
**50 e 12 elementos completos**, respetivamente. Cada elemento tem exatamente:

- `value`: inteiro, 1–50 ou 1–12.
- `count`: número de saídas, inteiro não negativo.
- `percentage`: decimal exato em string, por exemplo `"12.34"`; nunca NaN,
  infinito ou um número convertido silenciosamente de ponto flutuante.
- `lastDrawId`, `lastDate`: identificador português `NNN/YYYY` e data ISO ou
  ambos `null` apenas quando nunca saiu.
- `drawsSinceLast`: inteiro não negativo; obrigatório quando houve saídas.
- `eligibleDraws`: denominador explícito da fonte ou `null` se não disponível.

Não se aplica o denominador geral às estrelas 10, 11 e 12. Quando existe um
`eligibleDraws` explícito, a percentagem tem de corresponder à contagem e à
precisão decimal publicada. Sem denominador publicado, conserva-se `null`; não
se recupera um denominador por divisão ou pelo calendário. Os limites de
estrelas por período reutilizam `result_statistics.star_limit`.

`comparison` compara contagens com os concursos confirmados guardados cuja data
não ultrapassa a data UTC de atualização do snapshot. Inclui `cutoffDate`,
`coverage`, `countsMatch` e listas com `officialCount`, `storedCount`,
`countDifference`, `officialEligibleDraws` e `storedEligibleDraws`. Diferenças são
esperadas num histórico incompleto. Igualdade de frequências não prova a
existência nem a integridade de todos os concursos: `verification=not_audited`
e `coverage.isCompleteHistory=false` mantêm-se.

Os endpoints `/v1/statistics/numbers`, `/stars`, `/summary`, `/v1/draws/latest`,
`/v1/sync` e `/v1/rss/overview` conservam os respetivos contratos. Estatísticas
oficiais não incrementam o cursor de revisões de concursos nem o `drawCount`.
A aplicação deve manter cache separada, mostrar a atualização, a proveniência e
`snapshotReferenceVerified:false`; não apresentar um snapshot antigo como atual.

## Importação e validações

`official_statistics.py` usa apenas a biblioteca padrão. Impõe HTTPS direto,
URL oficial fixa, timeout de 20 segundos, máximo de 2 MiB e rejeita
redirecionamentos. HTML e JSON têm perfis explícitos: campos/colunas adicionais,
entradas em falta, duplicados, datas sem fuso, concursos inconsistentes,
percentagens inválidas e alterações inesperadas de estrutura são recusados.

O perfil HTML atual exige duas tabelas com legendas `Números` e `Estrelas`,
cabeçalhos `Valor`, `Saídas`, `Percentagem`, `Último concurso`, `Data`,
`Ausências` e, opcionalmente, `Concursos elegíveis`. Exige um único elemento
`time` com `datetime` e fuso explícito e a indicação `Desde 13/02/2004`. Não se
adivinha o fuso horário de uma data impressa sem fuso. Este perfil deve ser
confrontado com uma captura real antes de ativar recolhas remotas.

O JSON normalizado para uma transcrição revista contém exatamente
`schemaVersion,game,sourceUrl,updatedAt,coverageStart,numbers,stars`, com os
campos descritos acima. Não contém os campos de saída `importedAt`,
`sourceSha256`, `validation` ou `snapshotReferenceVerified`. No caso de JSON,
o SHA-256 identifica os bytes dessa transcrição, e não uma captura HTML que
não tenha sido importada; guardar separadamente os bytes originais e o seu
manifesto de auditoria. A validação estrutural não autentica uma transcrição.

## cPanel: preparação numa cópia, sem alterar o Cron atual

Ficheiros Python a atualizar em conjunto:

- `official_statistics.py` (novo).
- `passenger_wsgi.py`, `store.py`, `collect_results.py`.
- Preservar `official_cartaz.py`, `rss_import.py`, `result_statistics.py` e
  restantes módulos compatíveis de que estes dependem.

Não são necessárias novas dependências Python nem Android. Antes de qualquer
instalação aprovada, guardar os ficheiros anteriores e uma cópia consistente
SQLite com `backup_results.py`. Executar primeiro todos os testes offline e
usar uma cópia da base. O comando seguinte é apenas um modelo; substituir os
caminhos e nunca apontar para produção durante a validação:

```sh
/caminho/python3.12 collect_results.py \
  --official-statistics \
  --database /caminho/validacao/results.sqlite3 \
  --statistics-file /caminho/privado/captura-revista.json \
  --statistics-format json
```

O modo local não efetua HTTP. A base tem de existir e passar o preflight
read-only. Não há migração automática de JSON nem inicialização de uma base
SQLite desconhecida. Usa o mesmo ficheiro `.lock` do RSS e da pasta
administrativa, evitando concorrência entre estes coletores. A escrita é
transacional e apenas acrescenta tabelas de snapshots/importações.

Depois da validação de uma captura e do perfil HTML, um pedido remoto explícito
pode usar `--official-statistics --database /caminho/base.sqlite3 --config
/caminho/config.json`, exigindo `enabled:true` na configuração. Isto **não é uma
instrução para instalar ou alterar o Cron atual**. A importação de estatísticas
é um modo independente; não foi acrescentada automaticamente ao ciclo RSS.

Segunda execução do mesmo conteúdo: nenhuma nova linha de snapshot. Conteúdo
diferente com o mesmo instante oficial: conflito, preservando o primeiro
snapshot aceite. Snapshot mais antigo: fica preservado para auditoria e não
substitui o mais recente. Erro HTTP, ficheiro inválido ou estrutura desconhecida:
exit code 1 e cache anterior preservada; conflito: exit code 2.

## Reversão

Parar apenas uma eventual tarefa nova de estatísticas que tenha sido aprovada;
não modificar a tarefa RSS existente. Repor os quatro ficheiros Python
anteriores e reiniciar Passenger pelo procedimento habitual aprovado. As duas
tabelas adicionais podem permanecer: o código anterior ignora-as. Não executar
`DROP`, não repor uma base antiga por cima de concursos entretanto importados e
não eliminar revisões para fazer rollback de código.

## Histórico e regras legais: pendentes de evidência

O Motor de Pesquisa oficial continua a ser a fonte prioritária a investigar.
Ainda não se conhecem paginação, exportação, termos ou cobertura completa. Não
foi criado um raspador de endpoints adivinhados. O plano em
`historical-results-sources.md` mantém staging por concurso, identificação
portuguesa, confrontação, importação idempotente via `Store.import_rows()` e
verificação de cobertura antes de qualquer alegação de histórico integral.
Agregados nunca são usados para criar chaves, datas ou prémios individuais.

Os prazos de recebimento e reclamação de 90/12/60 dias não foram confirmados
por regulamento oficial nesta execução bloqueada. Devem permanecer distinguidos
e condicionados à fonte legal, exceções e confirmação manual de recebimento;
a ausência de registo de pagamento não demonstra que um prémio não foi pago.
