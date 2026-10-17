# LuckyScan 50 — Especificação funcional v1.0

## Âmbito
Portugal: Euromilhões e M1lhão. Carteira local, cópia de segurança opcional, importação de fotografia/captura/PDF, verificação de prémios e acompanhamento estatístico-financeiro.

## Ecrãs
1. Início — resumo e alertas
2. Digitalizar/importar — câmara, galeria e comprovativos
3. Confirmar leitura — campos reconhecidos editáveis
4. Bilhetes — carteira e filtros
5. Detalhe de bilhete — chaves, comprovativo e sorteios
6. Sorteios — resultados oficiais
7. Detalhe de sorteio — números, estrelas e prémios
8. Prémios — por receber, recebidos e não confirmados
9. Estatísticas — vista global
10. Números e estrelas — frequências e comparação pessoal/oficial
11. Finanças — gasto, prémios, saldo e taxa de retorno
12. Calendário — sorteios e prazos
13. Notificações — histórico e preferências
14. Backups — exportação e restauro encriptados
15. Definições — privacidade, aparência e avisos

## Ingestão
- Origem: physical / online / manual.
- Captura de página “Apostas em Jogo” do portal JSC: reconhecer secções Euromilhões e M1lhão com o mesmo código de aposta.
- Um só recibo com várias modalidades; somar componentes do preço exatamente uma vez.
- Cada chave e código ligados a concurso específico.
- Confirmar campos críticos antes da verificação; evitar duplicação entre capturas.
- Nunca guardar credenciais do operador; nunca enviar imagens para a API.

## Verificação
- Resultado pendente / incompleto / confirmado / corrigido.
- Só anunciar montante quando houver valor oficial por escalão validado.
- Calcular prémios por combinação e concurso, depois agregar por recibo.
- M1lhão é motor separado do Euromilhões.
- Distinguir prémios online creditados de prémios físicos recebidos.
- Datas de reclamação por jogo, país e versão regulamentar; não codificar um prazo fixo sem confirmação.

## Estatísticas
- Números apostados versus sorteados, estrelas, ausências, frequências, filtros temporais.
- Despesa apenas uma vez por recibo, independentemente do número de chaves/concursos.
- Distinguir prémios brutos, líquidos, identificados, recebidos e expirados.
- Marcar períodos com despesas em falta como incompletos.
- Histórico oficial concurso-a-concurso para análises anuais; snapshots agregados são complementares.
- Estatísticas não predizem resultados futuros.

## Requisitos de qualidade
- Trabalhar offline para carteira/estatísticas locais.
- Proteger dados no dispositivo e cópias com encriptação.
- Reprocessar correções dos sorteios sem criar prémios duplicados.
- Recuperar sincronização após falta de rede; avisos não são garantidos em tempo real com dispositivo desligado.
- Validar regras, fontes, direitos de acesso e políticas da Google Play antes de lançamento.
