# LuckyScan50 0.2.15 — proprietário e estatísticas

## Estado

Implementação local da API, painel privado e integração Android. A publicação no
servidor e a criação das credenciais reais são passos de instalação; este código
não altera o alojamento existente. Não acrescenta SDKs de publicidade, anúncios,
compras Google Play nem uma assinatura. `AppServices.premium` / `adsAllowed`
constituem o ponto central para essas funcionalidades futuras. Uma compra só
poderá atribuir direitos depois da verificação do comprovativo no servidor;
eventos de telemetria não concedem direitos e o endpoint rejeita compras alegadas.

## Configuração no servidor cPanel/Passenger

Publicar `api-python/app_services.py` juntamente com a versão atualizada de
`passenger_wsgi.py`, mantendo os restantes módulos da API. Definir no ambiente:

- `LUCKYSCAN_APP_DATABASE`: caminho absoluto para SQLite numa pasta privada,
  fora de `public_html`, distinta das bases de resultados e de emails.
- `LUCKYSCAN_APP_SECRET`: segredo aleatório com pelo menos 32 caracteres.
- `LUCKYSCAN_ADMIN_TOKEN`: outra chave aleatória com pelo menos 32 caracteres,
  diferente do segredo anterior e das chaves de ativação.

Gerar cada segredo com `python -c "import secrets; print(secrets.token_urlsafe(32))"`
no servidor e guardar num gestor de palavras-passe. Nunca colocar segredos no
GitHub, APK, URL ou configuração pública. Sem a configuração necessária os novos
serviços devolvem 503; a carteira e os resultados continuam independentes.
Reiniciar a aplicação Passenger após a configuração e usar exclusivamente HTTPS.
O utilizador do processo deve poder escrever na pasta privada. A base é criada
com permissões 0600; a pasta também deve ter acesso limitado ao utilizador do serviço.

### Gerir através do plugin WordPress 1.1.0

Depois de instalar a API Python e o plugin atualizado, abrir **Definições →
LuckyScan50 API** no WordPress. Configurar a chave administrativa igual a
`LUCKYSCAN_ADMIN_TOKEN` do servidor Python, ou definir a constante privada
`LUCKYSCAN50_APP_ADMIN_TOKEN` no `wp-config.php`. A chave não é a chave de email.
Pode consultar estatísticas, criar uma chave de proprietário e revogar licenças.
A chave de ativação é apresentada apenas ao criá-la; não fica armazenada no
WordPress. Esta opção substitui a necessidade de usar os comandos abaixo.

### Ativar a instalação do proprietário

No ambiente do servidor, a partir da pasta `api-python`:

```sh
python app_services.py create-owner
```

O comando apresenta o ID e uma chave individual uma única vez. A base guarda
apenas a derivação SHA-256 da chave. Na app, abrir **Definições** e manter premida
a linha **LuckyScan50 · Gil Pereira · versão ...** no rodapé. Introduzir a chave
no ecrã reservado. A API associa a licença à instalação e devolve uma sessão.
A chave de ativação não fica guardada na app. A sessão e o identificador da
instalação são cifrados com AES-GCM e chave não exportável do Android Keystore.
As cópias de segurança do Android estão desativadas e a exportação da carteira
não inclui estas credenciais.

A sessão é validada ao abrir e retomar a app, expira após 30 dias sem validação e
é renovada nas validações online. Uma nova execução da app precisa de confirmar
o direito na API; a carteira offline continua disponível. A revogação é aplicada
na próxima validação online. O gesto escondido apenas abre o ecrã: não ativa
qualquer direito sem uma chave válida no servidor.

Para revogar uma licença, substituir `123` pelo ID verdadeiro:

```sh
python app_services.py revoke-owner --id 123
```

Para outro dispositivo, criar outra licença. Para substituir um dispositivo
perdido, revogar a anterior e criar uma nova. A opção de desativação na app apaga
a sessão local; a revogação administrativa deve ser feita no servidor.

### Consultar o painel

Abrir, por HTTPS, no domínio existente da API:

`/admin/app`

Introduzir `LUCKYSCAN_ADMIN_TOKEN` no formulário privado. A sessão dura uma hora,
com cookie `Secure`, `HttpOnly` e `SameSite=Strict`. O painel permite terminar a
sessão e consultar os dados em JSON em `/admin/app/statistics`. A API de consulta
aceita também o token administrativo no cabeçalho Bearer. Nunca enviar esse token
para a app dos utilizadores. A licença de proprietário não dá acesso ao painel.
As respostas privadas não são armazenadas em cache.

## Estatísticas e privacidade

Em **Definições → Privacidade e estatísticas de utilização**, cada utilizador
pode ativar a partilha. Está desligada por defeito e não cria identificadores nem
faz pedidos de telemetria antes do consentimento. O acesso a resultados e a
validação de proprietário são comunicações operacionais separadas.

Eventos permitidos:

| Evento | Significado |
| --- | --- |
| `app_open` | Abertura/retoma; no máximo um evento a cada 30 minutos |
| `scan_camera` | Leitura concluída a partir da câmara |
| `scan_import` | Leitura concluída a partir de imagem importada |
| `scan_error` | Falha na leitura ou no preenchimento do formulário |
| `receipt_saved_manual` | Gravação manual concluída |
| `receipt_saved_import` | Gravação no formulário de revisão concluída |

Cada evento contém apenas ID aleatório do evento, tipo, versão e plataforma.
O servidor atribui a data UTC e associa-o a um identificador aleatório de
estatísticas, separado da instalação de proprietário. Não recebe imagens,
conteúdo de OCR, apostas, códigos M1lhão, montantes, emails nem identificadores
de publicidade. Os eventos não representam pessoas nem toda a base de utilizadores.
A mesma pessoa pode ter várias instalações. As contagens de leituras são leituras
concluídas, não tentativas; a gravação na revisão pode ser uma atualização de recibo.

Não existe fila persistente de eventos offline: uma falha de rede pode perder
contagens. Isto é adequado a métricas de produto, não a contabilidade de vendas.
O servidor limita registos por IP e eventos por instalação, valida os campos e
elimina duplicados pelo ID do evento. Estes limites não tornam as métricas uma
medição antifraude ou uma prova de faturação.

Desligar a partilha impede novos envios e pede a eliminação dos eventos e do
identificador no servidor. Se a API não estiver acessível, o pedido fica pendente
no dispositivo e é repetido na próxima abertura. A interface mostra esse estado.
A API não guarda IPs nos eventos; usa uma derivação HMAC diária para limitar abusos.
Os registos de acesso do servidor são independentes: configurar retenção e acesso
no alojamento e refletir essa informação na política de privacidade pública e na
declaração de segurança de dados do Google Play antes do lançamento.

### Retenção

A limpeza de eventos e identificadores inativos com mais de 90 dias ocorre nos
pedidos à API. Para garantir limpeza mesmo quando não há tráfego, configurar
**antes de ativar a recolha em produção** uma execução diária no cron do servidor:

```sh
python /CAMINHO_PRIVADO/api-python/app_services.py purge
```

Usar o executável Python e as variáveis de ambiente da aplicação Passenger.
Configurar também a expiração das cópias de segurança da base privada; a eliminação
na base ativa não elimina automaticamente backups antigos. Os totais do painel
referem-se apenas aos dados que permanecem na janela de retenção.

## Verificação antes de disponibilizar

1. Testar a API num ambiente isolado com base privada de teste e HTTPS.
2. Criar uma licença, ativar um dispositivo e confirmar revogação e expiração.
3. Confirmar que não há pedidos de métricas com a partilha desligada.
4. Ativar a partilha, usar a leitura e guardar um recibo; consultar as contagens.
5. Desligar a partilha e confirmar eliminação; repetir com a API temporariamente
   indisponível e verificar a repetição do pedido.
6. Configurar retenção, política pública e declaração Google Play antes de lançar.

## Validação nesta implementação

- 143 testes Python da API aprovados, incluindo 12 testes dos novos serviços.
- Análise estática Dart dos ficheiros da app e testes novos sem erros ou avisos.
- Seis verificações do cliente executadas com o motor Flutter 3.35.7 e dependências
  do lockfile: consentimento inicial, campos permitidos, limitação de aberturas,
  retirada durante registo em curso, eliminação offline/reinício e revogação.
  A execução usou um lançador local com os mesmos casos e matchers dos testes,
  sem arrancar o Flutter CLI nem fazer pedidos a serviços de metadados do ambiente.
  A suite completa `flutter test` e a compilação Android não foram executadas.
- Formatação Dart e `git diff --check` aprovados.

Os comandos normais para repetir os testes num ambiente Flutter configurado são:

```sh
cd api-python
python -m unittest discover -p 'test_*.py'
cd ../app
flutter pub get --enforce-lockfile
flutter analyze
flutter test test/app_services_test.dart test/milhao_draw_options_test.dart
```
