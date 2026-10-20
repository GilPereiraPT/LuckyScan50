# LuckyScan50 — enviar pelo WordPress e FluentSMTP

Este modo aproveita o FluentSMTP já configurado em policlinicosdesantoandre.com. O Gmail fica configurado apenas no WordPress. A API mantém subscrições, confirmação, cancelamento, fila e lembretes; a APK continua sem chaves administrativas ou palavras-passe de envio.

## 1. Instalar o plugin

No WordPress, abrir **Plugins → Adicionar novo → Carregar plugin**, selecionar `LuckyScan50-Mail-Bridge-1.0.0.zip`, instalar e ativar.

Abrir **Definições → LuckyScan50 Mail**. A página apresenta dois valores:

- `LUCKYSCAN_WORDPRESS_MAIL_URL`: copiar exatamente o URL apresentado, incluindo www ou qualquer subdiretório.
- `LUCKYSCAN_WORDPRESS_MAIL_KEY`: chave privada criada na ativação do plugin. Copiar apenas para a configuração privada da API. Não enviar pelo chat nem incluir em capturas partilhadas.

Esta chave é exclusiva da ligação API → WordPress; não é a palavra-passe do Gmail ou do WordPress. O acesso à página exige a capacidade administrativa `manage_options`. Pode ser rodada nessa página; nesse caso é preciso atualizar a API e o cron com o novo valor. Como alternativa avançada, pode ser definida na constante `LUCKYSCAN50_MAIL_BRIDGE_KEY` do wp-config.php.

O endpoint exige HTTPS. O WordPress deve reconhecer a ligação como HTTPS, incluindo quando existe um proxy. O URL copiado tem de apontar diretamente para `/wp-json/luckyscan50/v1/mail`, sem redirecionamento. A variante com `?rest_route=` não é suportada nesta versão; utilizar permalinks amigáveis.

## 2. Remetente e FluentSMTP

O plugin define explicitamente `From: LuckyScan50 <luckyscan50@gmail.com>`. O FluentSMTP deve ter uma ligação para esse endereço. Validar primeiro o envio pelo separador **Email Test** e confirmar a receção numa caixa de correio controlada.

Manter **Force From Email** desmarcado para não reescrever os remetentes de outras ligações. Se o site precisa de enviar emails próprios dos Policlínicos, configurar também essa ligação e o encaminhamento por remetente no FluentSMTP. Uma única ligação Gmail pode tornar-se a ligação predefinida do site, mesmo com a opção Force desmarcada. Este plugin não altera essas definições globais.

## 3. Configurar a API no cPanel

Atualizar os ficheiros do pacote `LuckyScan50-WordPress-cPanel-20261020.zip`, preservando bases de dados e configurações privadas existentes. O pacote não contém credenciais nem dados de produção.

Copiar `wordpress.env.example` para um ficheiro privado fora de public_html, por exemplo `/home/UTILIZADOR/private/luckyscan50/wordpress.env`, com permissões `600`. Substituir os caminhos `UTILIZADOR` pelos reais. Usar os mesmos valores nas variáveis de ambiente da aplicação Python no cPanel e no cron.

```ini
LUCKYSCAN_EMAIL_PROVIDER=wordpress
LUCKYSCAN_EMAIL_FROM=luckyscan50@gmail.com
LUCKYSCAN_WORDPRESS_MAIL_URL=https://policlinicosdesantoandre.com/wp-json/luckyscan50/v1/mail
LUCKYSCAN_WORDPRESS_MAIL_KEY=<chave apresentada pelo plugin>
```

Também são necessários os valores privados de `LUCKYSCAN_EMAIL_DATABASE`, `LUCKYSCAN_EMAIL_PUBLIC_URL`, `LUCKYSCAN_EMAIL_SIGNING_KEY` e a origem de resultados usada pela API. Se já existe uma chave de assinatura de emails, preservá-la para manter as ligações de cancelamento já emitidas válidas. Caso seja uma instalação inicial, gerar uma chave com `python3 -c 'import secrets; print(secrets.token_urlsafe(48))'` e guardá-la apenas no servidor.

Não é necessário definir `LUCKYSCAN_GMAIL_APP_PASSWORD` neste modo. A chave do plugin e a chave de assinatura das ligações têm funções diferentes e não devem ser reutilizadas.

Definir `LUCKYSCAN_EMAIL_ENABLED=1` depois de configurar todos os valores e reiniciar a aplicação Python. `GET /v1/email/status` deverá indicar `provider: wordpress` e `available: true`; isto valida a configuração local, não comprova a entrega de um email.

## 4. Cron

Se já existe um cron de emails da versão Gmail, manter apenas uma execução e mudar o ficheiro de ambiente carregado para `wordpress.env`. Não criar um segundo processo paralelo para os mesmos subscritores.

Exemplo de script privado, substituindo os caminhos:

```sh
#!/bin/sh
set -eu
set -a
. /home/UTILIZADOR/private/luckyscan50/wordpress.env
set +a
cd /home/UTILIZADOR/CAMINHO_DA_API
exec /home/UTILIZADOR/virtualenv/CAMINHO_DA_API/3.12/bin/python send_email_notifications.py --send
```

Agendar no cPanel a cada cinco minutos. O cron de recolha de resultados continua separado e ativo. Sem `--send`, o comando é uma simulação e não envia emails.

## 5. Teste completo

Na versão atualizada da app, ativar os avisos por email para um endereço próprio, guardar e aguardar o cron. Confirmar o endereço na ligação recebida, regressar à app e tocar em **Verificar confirmação e sincronizar**. Verificar também o cancelamento no rodapé.

O teste do FluentSMTP comprova apenas WordPress → caixa de correio. O teste acima comprova app → API → WordPress → FluentSMTP → caixa de correio. A instalação dos ficheiros e os testes no alojamento não são efetuados automaticamente ao descarregar os pacotes.

## Proteções e limites

- A ponte não permite anexos, CC/BCC, remetentes arbitrários ou cabeçalhos fornecidos pela app. Recebe apenas um destinatário por pedido autenticado.
- O WordPress guarda o identificador da entrega, uma impressão digital do conteúdo, o estado e a data. Não guarda destinatários ou corpos na tabela da ponte. O FluentSMTP pode ter registos próprios: rever a respetiva retenção nas definições.
- A mesma entrega aceite não é enviada duas vezes. Um pedido com o mesmo ID mas conteúdo diferente é rejeitado. Uma entrega interrompida ou ambígua requer verificar os registos antes de repetir.
- Há um limite adicional de 200 pedidos novos por 24 horas na ponte, além do limite da API e dos limites do Gmail. Os identificadores de entrega são retidos durante 30 dias.
- Se o servidor MySQL não disponibilizar GET_LOCK, a ponte recusa o envio; não desativar o bloqueio sem rever a implementação.
- Uma resposta aceite de wp_mail significa que o método de envio processou o pedido; não garante a chegada à caixa de correio.
- Os emails enviados por esta ponte usam texto simples, com ligações de confirmação e cancelamento. A API por SMTP direto mantém a alternativa HTML.
- Os prazos de levantamento continuam a exigir datas oficiais revistas, no ficheiro privado de datas-limite. Sem data, não é inventado um prazo.

Referências: [wp_mail](https://developer.wordpress.org/reference/functions/wp_mail/), [endpoints REST](https://developer.wordpress.org/rest-api/extending-the-rest-api/adding-custom-endpoints/), [FluentSMTP](https://fluentsmtp.com/docs/fluent-smtp-settings/).

## Personalizar o conteúdo dos emails

Copie `email-templates.example.json` para `email-templates.json`, numa pasta privada do servidor. Defina `LUCKYSCAN_EMAIL_TEMPLATES_FILE` com o caminho absoluto desse ficheiro e reinicie a aplicação Python no cPanel. Sem esta variável, usam-se os textos portugueses incluídos na aplicação.

O ficheiro contém quatro modelos: `confirm` (confirmação), `results` (resultados), `prizes` (prémios por levantar) e `expiry` (prazos a caducar). Em cada um, edite `subject` e `body`. Mantenha os campos entre chavetas presentes no exemplo: são substituídos pelos dados reais. O assunto tem de incluir LuckyScan50 e ocupar uma única linha. Os valores monetários usam vírgula decimal.

O cancelamento da subscrição e o aviso de aplicação não oficial são acrescentados automaticamente. O modelo de confirmação deve manter `{confirm_url}`. JSON inválido ou campos em falta impedem a criação de novas mensagens; os emails já em fila conservam o conteúdo com que foram criados. Para validar antes de ativar: `python3 -m unittest discover -s validacao/api-python` (na pasta do pacote extraído).
