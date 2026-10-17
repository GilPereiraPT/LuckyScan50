# Histórico Euromilhões desde 13/02/2004 — investigação

## Conclusão desta entrega

Ainda não há um arquivo integral descarregado, verificado e autorizado para
importação. Não se afirma que o concurso atualmente armazenado representa o
histórico. A API passa a expor `coverage` com `isCompleteHistory=false`,
`verification=not_audited`, início de referência `2004-02-13`, datas e contagem
realmente armazenadas. Não calcula percentagens de cobertura ou frequências de
concursos que não existem na base.

Nesta tarefa não foram efetuadas consultas HTTP, pesquisas remotas ou downloads:
o pedido proíbe recolhas remotas sem autorização. A investigação usa o código,
XML reais previamente fornecidos/guardados e a página oficial preservada da
auditoria anterior. Assim, disponibilidade atual, licença, formatos e cobertura
das fontes históricas candidatas continuam por confirmar.

## Fontes avaliadas e candidatas

| Fonte | Evidência disponível | Adequação/limite |
| --- | --- | --- |
| Jogos Santa Casa, página oficial `https://www.jogossantacasa.pt/web/SCCartazResult/euroMilhoes` | Snapshot anterior verificado contra a API para 083/2026; inclui chave, data, categorias e vencedores PT/total. A lista HTML preservada apresenta 30 concursos, 054–083/2026. | Fonte prioritária para identificação portuguesa e prémios efetivos. Não comprova exportação integral desde 2004; não foi implementada paginação/scraping de endpoints não documentados. |
| Três RSS oficiais | XML reais ISO-8859-1 com resultados recentes/anúncios/indicadores Portal. | Não contêm arquivo integral e não devem ser usados para reconstruir o passado. |
| FDJ, arquivo oficial Euromillions/My Million | Candidato de operador oficial: `https://www.fdj.fr/jeux-de-tirage/euromillions-my-million/historique`. URL e ficheiros não consultados nesta tarefa. | Candidato para chaves/datas desde o lançamento; confirmar cobertura, acesso HTTPS direto, licença e esquema antes de usar. Não fornece necessariamente identificadores portugueses ou vencedores em Portugal; não substituir esses campos por valores franceses. |
| Agregadores ou repositórios de terceiros | Nenhum foi validado aqui. | Podem servir para comparação, não como fonte única de dados confirmados ou de montantes. |

A FDJ é candidata primária para uma exportação histórica; a identificação de um
operador oficial não é prova de que um URL ou arquivo concreto foi validado. O
passo seguinte exige autorização para consultar os metadados e descarregar o
arquivo; não há um comando de recolha histórica ativado nesta entrega.

## Plano de carga segura, após autorização e validação da fonte

1. Confirmar HTTPS direto, termos de reutilização, cobertura desde 13/02/2004 e
   ficheiros/segmentos históricos disponibilizados pelo operador. Guardar bytes
   originais, URL, instante de recolha, SHA-256 e licença num manifesto por arquivo.
2. Converter offline para staging, mantendo origem por concurso e data de sorteio
   separada da data de publicação. Recusar XML/CSV corrompido, colunas desconhecidas,
   números repetidos ou fora de 1–50, datas inválidas e chaves incompletas.
3. Validar estrelas por período: 1–9 antes de 10/05/2011, 1–11 de 10/05/2011 até
   26/09/2016, 1–12 desde 27/09/2016. O importador histórico futuro deverá impor
   estes limites; a validação atual de RSS não demonstra validação do arquivo antigo.
4. Obter mapeamento inequívoco de data e identificador de concurso português.
   Não assumir que a numeração de outro país coincide, nem gerar IDs por posição
   no CSV. M1lhão é um jogo separado, não existente desde o início do Euromilhões,
   e requer a sua própria fonte oficial portuguesa.
5. Verificar duplicados em `(game,drawId)` e divergências de data/chave com o
   histórico existente. A mesma data com IDs inconsistentes deve ser investigada;
   não usar `INSERT OR REPLACE` ou substituir concursos confirmados.
6. Sem prémios oficiais por categoria, manter `numbers_confirmed`, 13 categorias
   com valores/vencedores desconhecidos e jamais inventar zeros ou prémios. Valores
   franceses de vencedores não são `winnersPortugal`. Portal e jackpot previstos
   nunca completam montantes unitários.
7. Confrontar amostras de cada ano/período e as transições do formato com uma
   segunda fonte oficial. Verificar lacunas, cancelamentos e eventuais correções,
   sem inferir chaves a partir da periodicidade esperada.
8. Importar primeiro numa cópia consistente da base, em transação, com relatório
   de novos/iguais/conflitos e teste de segunda execução sem alterações. Aprovar
   o relatório e backup antes de qualquer carga na base usada pelo Passenger.
9. Só apresentar histórico integral quando a cobertura tiver sido auditada. A
   indicação `isCompleteHistory=false` não muda automaticamente pelo número de
   linhas importadas; a contagem sozinha não demonstra completude.

Nenhum arquivo ou concurso histórico foi importado nesta tarefa. O coletor Cron
entregue recolhe apenas os RSS atuais e conserva todos os resultados anteriores.
