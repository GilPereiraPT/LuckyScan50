=== LuckyScan50 Mail Bridge ===
Version: 1.1.0
Requires PHP: 7.4

Recebe pedidos privados da API LuckyScan50 e envia via wp_mail/FluentSMTP.

Instalar e ativar; depois abrir Definições > LuckyScan50 Mail.
Copiar o URL e a chave apresentados para as variáveis privadas da API.
Nunca colocar a chave na APK nem enviar a chave em capturas partilhadas.

Remetente fixo: luckyscan50@gmail.com.
Exige HTTPS, FluentSMTP (ou outro transporte wp_mail funcional) e MySQL com GET_LOCK.
A instalação não envia mensagens de teste nem altera as definições globais do FluentSMTP.

O guia completo está em INSTALAR_WORDPRESS.md no pacote cPanel.

Versão 1.1.0: Definições > LuckyScan50 API permite consultar estatísticas e criar/revogar
chaves de proprietário. Exige o pacote Python atualizado e LUCKYSCAN_ADMIN_TOKEN.
A chave administrativa não é a chave de email e nunca é enviada para a app.
Pode defini-la em LUCKYSCAN50_APP_ADMIN_TOKEN no wp-config.php, ou no ecrã privado
do plugin. O formulário fica vazio e não volta a revelar a chave guardada.
Mantém compatibilidade com a configuração e a tabela de emails da versão 1.0.0.
