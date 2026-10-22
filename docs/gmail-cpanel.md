# LuckyScan50 — avisos pelo Gmail no cPanel

## O que está preparado

- Gmail SMTP em `smtp.gmail.com:587`, com STARTTLS e certificado validado.
- Subscrição opcional na app, confirmação por email e cancelamento em todas as mensagens.
- Resultados a partir do dia da subscrição, incluindo revisões oficiais; sem envio do histórico completo.
- Lembrete semanal de prémios identificados ainda não registados como recebidos.
- Caducidade: um aviso dentro da antecedência escolhida (1/3/7/14 dias) e outro no último dia, apenas com uma data-limite revista e documentada.
- Fila SQLite privada, deduplicação, limite inicial de 200 tentativas por 24 horas e 20 por execução.
- Sem dependências Python adicionais. Sem credenciais na APK, no repositório ou nos logs.

Os avisos pessoais usam os concursos, chaves, códigos M1lhão e total recebido sincronizados pela app com consentimento explícito. Não são enviadas fotografias, identificadores impressos do recibo nem o custo. Se o recebimento não for atualizado e sincronizado, o servidor pode continuar a lembrar um prémio já levantado. Cada lembrete indica a última sincronização da carteira.

## 1. Conta Gmail

Criar `luckyscan50@gmail.com`, se disponível, ativar a verificação em dois passos e gerar uma palavra-passe de aplicação chamada `LuckyScan50 cPanel`, se a conta disponibilizar essa opção. Utilizar a palavra-passe de aplicação de 16 caracteres. Não usar a palavra-passe principal nem a colocar no chat.

Se a conta não permitir palavras-passe de aplicação, este modo SMTP não pode ser ativado: será necessário implementar OAuth2. Não ativar opções de acesso menos seguro.

Documentação oficial: [palavras-passe de aplicação](https://support.google.com/accounts/answer/185833), [SMTP Gmail](https://support.google.com/mail/answer/7104828), [limites Gmail](https://support.google.com/mail/answer/22839).

## 2. Instalar os módulos

Atualizar os ficheiros Python no diretório da API, incluindo `email_notifications.py`, `send_email_notifications.py` e o `passenger_wsgi.py` atualizado. Manter a base de resultados existente. A base de subscrições é separada e não altera o esquema de resultados.

Copiar `gmail.env.example` para um diretório privado fora de `public_html`, por exemplo `/home/UTILIZADOR/private/luckyscan50/gmail.env`. Substituir `UTILIZADOR` e os caminhos. Criar esse diretório com permissões `700` e o ficheiro com permissões `600`. Não colocar credenciais num diretório servido pela web.

Configurar as variáveis do modelo nas variáveis de ambiente da aplicação Python no cPanel e carregar os mesmos valores no cron. O Passenger não lê automaticamente o ficheiro `.env`. O endereço remetente deve ser a própria conta Gmail autenticada.

Gerar a chave estável das ligações com:

```bash
python3 -c 'import secrets; print(secrets.token_urlsafe(48))'
```

Guardar esse valor apenas em `LUCKYSCAN_EMAIL_SIGNING_KEY`. Alterar essa chave invalida as ligações de confirmação e cancelamento já emitidas; não a regenerar a cada execução.

Definir a palavra-passe de aplicação em `LUCKYSCAN_GMAIL_APP_PASSWORD`, sem espaços. Definir `LUCKYSCAN_EMAIL_ENABLED=1` apenas quando toda a configuração estiver concluída. Reiniciar a aplicação Python no cPanel.

O endereço público tem de ser HTTPS e fixo; as ligações nunca usam o cabeçalho Host recebido. Garantir que o alojamento permite saída para `smtp.gmail.com` na porta 587.

Consultar `GET /v1/email/status`: deve devolver `available: true`. Esse estado valida a presença e o formato da configuração, não confirma as credenciais junto do Gmail. A ligação real só é comprovada no primeiro envio autorizado.

## 3. Cron

Guardar um script privado `run-luckyscan50-email.sh`, com os caminhos reais:

```bash
#!/bin/sh
set -eu
set -a
. /home/UTILIZADOR/private/luckyscan50/gmail.env
set +a
cd /home/UTILIZADOR/CAMINHO_DA_API
exec /home/UTILIZADOR/virtualenv/CAMINHO_DA_API/3.12/bin/python send_email_notifications.py --send
```

Dar permissões `700` ao script e agendar no cPanel a cada cinco minutos:

```cron
*/5 * * * * /home/UTILIZADOR/private/luckyscan50/run-luckyscan50-email.sh >> /home/UTILIZADOR/private/luckyscan50/email-cron.log 2>&1
```

O script usa um bloqueio para impedir duas execuções em simultâneo. O cron de resultados deve continuar ativo. O cron de email usa a mesma base de resultados; não substitui a recolha.

Para uma simulação local sem enviar mensagens, carregar o ambiente e executar `python send_email_notifications.py`, sem `--send`. Este modo apenas conta mensagens novas elegíveis e não as coloca na fila. A confirmação só é enviada pelo cron com `--send`.

## 4. Validar o circuito

Na app, ativar email, indicar um endereço controlado pelo utilizador e guardar. O estado deve ficar `pending`; ainda não são enviados avisos de resultados ou prémios.

Depois do cron, abrir a mensagem de confirmação. Abrir a ligação mostra uma página; tocar em Confirmar ativa a subscrição. Um scanner de ligações que apenas faça GET não a ativa. A ligação expira em 24 horas; guardar novamente após 15 minutos permite pedir uma nova confirmação.

Voltar à app e tocar em **Verificar confirmação e sincronizar**. O estado deve mudar para ativo. Recebimentos, alterações e eliminações posteriores sincronizam a carteira enquanto a app estiver aberta e ligada à Internet. Os emails passam a ser tratados pelo servidor, mesmo com a app fechada.

Verificar o cancelamento pelo rodapé de um email e pela opção na app. Cancelar elimina o email, as chaves e as mensagens em fila dessa subscrição. Uma mensagem já entregue ao Gmail não pode ser retirada. A app exige ligação para cancelar antes de eliminar todos os dados locais, para não perder o acesso à subscrição ainda ativa.

## 5. Datas-limite

O ficheiro `claim-deadlines.example.json` começa vazio. Não são calculados prazos legais por suposição.

Para cada concurso, introduzir apenas uma data confirmada na fonte oficial, com esta estrutura (os campos entre `<...>` são marcadores e têm de ser substituídos):

```json
{
  "euromilhoes:<NNN>/<AAAA>": {
    "deadline": "<AAAA-MM-DD>",
    "verifiedAt": "<AAAA-MM-DD>",
    "sourceUrl": "https://www.jogossantacasa.pt/<fonte-oficial>"
  }
}
```

O formato do concurso, as datas e o domínio oficial são validados. A validação sintática não prova a interpretação jurídica da data: essa revisão tem de preceder a inserção. Sem entrada para o concurso, resultados e prémios continuam a funcionar, mas não é enviado aviso de caducidade. A mudança de dia segue Europe/Lisbon.

## Operação e limites

- O limite de 200 tentativas/24h deixa margem face ao limite público do Gmail pessoal; não garante a aceitação pelo Gmail. Confirmações e repetições contam para o limite.
- Erros temporários com rejeição SMTP explícita podem repetir até três tentativas, com espera. Uma falha de transporte ambígua fica `uncertain` e não é repetida automaticamente, para evitar duplicados. Uma interrupção após entrega SMTP também não permite garantir exatamente uma entrega.
- Um erro de autenticação interrompe o lote. Corrigir a configuração antes de inspecionar e reativar mensagens `failed`. Não reativar mensagens `uncertain` sem verificar a pasta Enviados.
- O estado e os contadores estão na base privada. Não expor endereços ou corpos de mensagens num endpoint público. Os logs do cron só têm contadores e códigos genéricos.
- Pendentes expirados são eliminados após sete dias; corpos de mensagens concluídas são limpos após 30 dias, preservando os identificadores para deduplicação.
- Pedidos de subscrição têm limitação por IP e email. Para um lançamento amplo, acrescentar proteção contra abuso no proxy e rever a capacidade de envio antes de aumentar os limites.
- O envio efetivo, a abertura da porta SMTP e a configuração do cron têm de ser comprovados no alojamento. Os testes automáticos usam transportes simulados e não enviam mensagens reais.

## Endpoints

| Método | Caminho | Função |
|---|---|---|
| GET | `/v1/email/status` | Disponibilidade da configuração, sem segredos |
| POST | `/v1/email/subscription` | Pedir confirmação/atualizar preferências, com consentimento |
| GET | `/v1/email/subscription` | Consultar estado autenticado |
| DELETE | `/v1/email/subscription` | Cancelar e apagar dados pessoais |
| PUT | `/v1/email/watches` | Substituir carteira mínima, só após confirmação |
| GET/POST | `/v1/email/confirm` | Mostrar confirmação/confirmar |
| GET/POST | `/v1/email/unsubscribe` | Mostrar cancelamento/cancelar, incluindo POST One-Click |

Os endpoints da subscrição usam um token aleatório de 256 bits por instalação no cabeçalho Authorization. O servidor só guarda o seu hash. Uma nova instalação não herda esse token pelos backups de recibos; a ligação de cancelamento continua disponível nos emails.
