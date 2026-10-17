# LuckyScan50 API — Python/Passenger

Compatível com o cPanel Python 3.12.15, com aplicação WSGI/Passenger.

## No cPanel
- Application root: `api-luckyscan50`
- Application URL: `luckyscan50-api.policlinicosdesantoandre.com`
- Startup file: `passenger_wsgi.py`
- Entry point: `application`
- Python: `3.12.15`

Enviar os ficheiros desta pasta para `/home3/policli1/api-luckyscan50/`, **fora da pasta pública do website**. Nunca copiar a pasta `backend/` inteira para o domínio.

Instalar as dependências com o comando do ambiente virtual indicado pelo cPanel:
```bash
pip install -r requirements.txt
```
Reiniciar a aplicação no cPanel e testar:
```
https://luckyscan50-api.policlinicosdesantoandre.com/health
```

O resultado esperado é JSON `{"ok":true,"service":"luckyscan50-results","version":"0.1.0"}`.

Sem dados importados, `/v1/draws/latest` devolve 404: é **correto e seguro**.
A aplicação é só de leitura HTTP; a importação é exclusivamente por CLI local:
```bash
python import_result.py caminho/resultado-validado.json
```

Definir a variável de ambiente `LUCKYSCAN_RESULTS_FILE` para um caminho absoluto fora da pasta pública, se possível. Não enviar ao servidor exemplos não verificados nem fotografias com informações pessoais.

## Limitações
- Ainda não inclui recolha automática de resultados da Santa Casa.
- Ainda não inclui autenticação de administradores ou notificações push.
- Persistência em JSON serve testes e baixa concorrência; migrar para base transacional na produção.
- O envio por SFTP/File Manager e a instalação no cPanel são operações a realizar pelo proprietário do alojamento.
