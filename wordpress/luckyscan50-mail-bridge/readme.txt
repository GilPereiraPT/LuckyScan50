=== LuckyScan50 Mail Bridge ===
Version: 1.0.0
Requires PHP: 7.4

Recebe pedidos privados da API LuckyScan50 e envia via wp_mail/FluentSMTP.

Instalar e ativar; depois abrir Definições > LuckyScan50 Mail.
Copiar o URL e a chave apresentados para as variáveis privadas da API.
Nunca colocar a chave na APK nem enviar a chave em capturas partilhadas.

Remetente fixo: luckyscan50@gmail.com.
Exige HTTPS, FluentSMTP (ou outro transporte wp_mail funcional) e MySQL com GET_LOCK.
A instalação não envia mensagens de teste nem altera as definições globais do FluentSMTP.

O guia completo está em INSTALAR_WORDPRESS.md no pacote cPanel.
