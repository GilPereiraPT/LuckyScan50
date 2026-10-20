# Contador agregado do website

A página principal envia um único POST de pageview por carregamento para /v1/website/visits. Cada carregamento conta, incluindo uma atualização da página. Não conta visitantes únicos nem tenta reconhecer dispositivos. Não utiliza cookies, armazenamento do navegador ou identificadores de visitantes.

O módulo website_stats.py conserva apenas total e started_at numa SQLite separada website-stats.sqlite3, ao lado da base de resultados indicada por LUCKYSCAN_DATABASE. Pode configurar um caminho absoluto diferente com LUCKYSCAN_WEBSITE_STATS_DATABASE. O caminho da base de resultados não pode ser usado para o contador. Ficheiros novos são criados com permissões 600.

## Ativar no cPanel

1. Carregar website_stats.py e passenger_wsgi.py da mesma revisão para a raiz api-luckyscan50. Preservar todos os outros módulos, bases e variáveis.
2. Reiniciar a aplicação Python no cPanel. Não é necessário cron, pacote Python, alteração do APK ou nova variável no caso normal.
3. Abrir o website publicado e confirmar o número no rodapé. GET https://luckyscan50-api.policlinicosdesantoandre.com/v1/website/visits permite consultar total, startedAt e metric sem incrementar.

O contador começa em zero ao ser ativado. Não recupera visitas anteriores e não apresenta um número fictício se o serviço estiver indisponível. O site apresenta Indisponível e continua a funcionar normalmente nesse caso. Não repete automaticamente um POST que falhou ou expirou, pois pode já ter sido contado.

CORS e POST são limitados à origem https://gilpereirapt.github.io, a origem do website atual. A origem não autentica pessoas e pode ser imitada por clientes externos: a contagem é indicativa e não é uma métrica antifraude. O alojamento pode manter registos técnicos independentes, como descrito na privacidade. Ao migrar para um domínio próprio, atualizar a origem permitida.
