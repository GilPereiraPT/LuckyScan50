# Aplicação Android LuckyScan50

Flutter 3.35.7 / Dart 3.9.2. Package ID: `com.gilpereira.luckyscan50`. A aplicação usa Riverpod, GoRouter e SQLite através de sqflite, sem geração de código. O esquema local é versionado em `WalletStore.open`; atualizar `version` e adicionar migração antes de alterar o esquema.

## Compilar e instalar

Instalar Flutter 3.35.7, JDK 17/21, Android SDK API 36 e aceitar as licenças aplicáveis. `flutter doctor -v` mostra os requisitos locais.

```sh
flutter pub get --enforce-lockfile
flutter analyze
flutter test
flutter build apk --debug --target-platform android-arm64
adb install -r build/app/outputs/flutter-apk/app-debug.apk
```

A CI `ci-flutter.yml` prepara JDK/Flutter, executa os testes e gera o APK de testes ARM64 como artefacto. Não se confirma a execução da CI apenas por guardar o workflow.

Não há keystore, senha, alias ou assinatura de produção no repositório. Configurar assinatura segura numa tarefa posterior, antes de gerar e distribuir um AAB. A configuração release de testes recebida usa assinatura debug; não é um produto assinado para a loja. Não usar o APK debug para distribuição pública.

## Utilização

1. Registar aposta, indicar o código do recibo e o custo **total**, uma vez.
2. Introduzir concursos `NNN/AAAA` separados por vírgulas e uma chave por linha: `1 2 3 4 5 + 1 2`.
3. Associar os concursos e códigos M1lhão do mesmo comprovativo ao recibo.
4. Confirmar os campos. Identificadores repetidos geram aviso; apostas genuínas com os mesmos números continuam permitidas.
5. Sincronizar resultados. Os concursos que ainda não foram descarregados ou estão parciais mantêm o recibo pendente; prémios desconhecidos nunca são tratados como zero.
6. Registar o montante efetivamente recebido no detalhe. Não se presume levantamento físico para apostas online.

A câmara/galeria e ML Kit funcionam localmente. O parser interpreta âncoras N/E, metadados explícitos e coordenadas, preenchendo os campos que não foram editados manualmente. Mostra apostas incompletas, conflitos e diagnóstico local por etapa. As regressões usam transcrição/observações controladas: falta executar e validar o motor nas fotografias reais vertical e rodada. Não há envio de fotografias, apostas ou códigos para a API.

A sincronização pública consulta ambos os jogos, pagina quando a API o suporta e guarda resultados numa transação. A API publicada 0.1.1 só fornece até 100 concursos por jogo sem metadados de paginação; a aplicação não inventa o histórico em falta. A versão 0.2.0 acrescenta paginação no servidor. Um erro de rede conserva os dados anteriores. Atualização ao regressar à aplicação não equivale a sincronização Android em segundo plano.

## Dados, backup e privacidade

O SQLite e as imagens ficam no diretório privado da aplicação. Backup automático Android foi desativado para evitar cópias não controladas. As exportações partilhadas deixam o dispositivo apenas pela ação do utilizador. CSV contém dados pessoais em claro; escolher um destino privado.

O backup inclui recibos e imagens, encriptados com AES-256-GCM, nonce/salt aleatórios e PBKDF2-HMAC-SHA256 com 210000 iterações. A palavra-passe não é guardada; sem ela não há recuperação. Corrupção ou senha errada impedem restauro. O restauro agrega recibos por ID, conserva os existentes e recria imagens em caminhos privados do novo dispositivo. Não inclui cache oficial nem histórico local de alterações: a cache volta a ser descarregada. Cópias e CSV partilhados externamente não são eliminados pela aplicação.

Eliminar todos os dados remove recibos, histórico, resultados, imagens e ficheiros temporários de exportação criados pela app. Desinstalar também elimina os dados privados. Guardar uma cópia segura antes.

A preferência de tema é guardada na base local. Bloqueio biométrico, notificações, calendário regulamentar e expiração não são apresentados como funcionais.

## Validação necessária em Android real

Testar captura/galeria, permissões, qualidade OCR em comprovativos anonimizados, disposição em ecrãs pequenos e fontes grandes, partilha/restauro entre dispositivos, encerramento e reabertura da app e modo avião. Os testes de widgets e unitários não comprovam os plugins nativos. Usar apenas comprovativos de testes/anonimizados e não importar fixtures de concursos como resultados atuais.

## APK de auditoria 0.2.1+3

A página Sobre identifica a versão e o SHA compilado. Antes de substituir um APK instalado, compare o certificado de assinatura; chaves debug de runners diferentes podem ser incompatíveis. Não desinstale nem elimine dados sem backup. O workflow de desenvolvimento exige testes, assinatura válida, ZIP íntegro, apenas ARM64 e alinhamento ELF/ZIP de 16 KB, e publica APK, checksum SHA-256 e manifesto de verificação. Não existe aprovação de OCR real enquanto faltarem as fotos de referência.

## OCR multi-pass: distribuição suspensa

O protótipo atual preserva a primeira leitura e tenta recuperar colunas verticais através de recortes de linhas, EXIF e passagens adicionais, mantendo proveniência e proteção de edições. Não foi validado nas duas fotografias originais. Não publicar um novo APK sem executar a aceitação Android descrita em [OCR_MULTIPASS.md](../docs/OCR_MULTIPASS.md). A CI não faz upload de APK nesta fase. Fotos de teste privadas são ignoradas pelo Git e devem ser removidas antes de qualquer build distribuído.
