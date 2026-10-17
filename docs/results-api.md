# LuckyScan50 — Motor de resultados

## Estado atual
A API disponibiliza concursos **previamente validados e importados**. Ainda **não existe recolha automática ativada** da página JSC: a existência de HTML público não comprova permissão para reutilização automatizada. O servidor não valida bilhetes físicos; apenas distribui resultados. Não inserir credenciais ou imagens no backend.

## Desenvolvimento
```bash
cd backend
npm install
npm run lint
npm test
npm run import:result -- fixtures/euromilhoes-083-2026.json
npm run build
npm start
```

A fixture é um exemplo de regressão de parser/dados baseado num resultado real; não deve ser interpretada como fonte atual. O campo `retrievedAt` nela indica a data de elaboração da fixture, não a hora de recolha do site.

## API somente de leitura
- `GET /health`
- `GET /v1/draws/latest?game=euromilhoes`
- `GET /v1/draws/latest?game=milhao`
- `GET /v1/draws?game=euromilhoes&limit=30`
- `GET /v1/draws/euromilhoes/083/2026`

Sem ficheiro importado, devolve 404 e `no_validated_results`. Não devolve números inventados.

## Estrutura do resultado
Cada concurso inclui identificador, data, origem HTTPS, momento de importação, 5 números, 2 estrelas, 13 escalões com valores **em cêntimos**, vencedores e estado. Quando o escalão não tem vencedores e a página apresenta uma previsão em vez de valor atribuído, `amountCents=null`, não zero.

## Produção
O armazenamento JSON é **apenas de desenvolvimento/instância única** e não é seguro para escritas concorrentes. Em produção substituir por MySQL ou PostgreSQL transacional, com controlo de versões e acesso autenticado ao importador. Não expor endpoint público de escrita.

## Alojamento
Verificar no cPanel suporte Node.js, versão, processos persistentes, cron e MySQL. Caso só haja PHP, manter um job de importação externo e disponibilizar resultados por uma API PHP read-only sobre dados replicados, sem alterar o website.
