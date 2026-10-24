# LuckyScan50 — preparação para Google Play (24-10-2026)

Base revista: branch `feat/manual-draw-picker`, incluindo PR #15 (Android 0.2.15+17). A auditoria recebida avaliou um APK **0.2.4 profile**, pelo que **não** descreve o estado atual da assinatura nem da otimização.

## Verificado no código

- `app/android/app/build.gradle.kts` tem assinatura privada para release, sem fallback silencioso para chave debug; R8 e shrinkResources estão ativos.
- `.github/workflows/signed-apk.yml` constrói APK ARM64 release assinado e verifica certificado, estrutura e alinhamento de 16 KB.
- `app/pubspec.yaml`: 0.2.15+17. Não reutilizar `versionCode=17` numa nova publicação.
- O projeto dispõe de política de privacidade em `website/privacidade.html`, mas a publicação HTTPS e a URL pública devem ser confirmadas.
- A interface de privacidade permite consentir ou retirar estatísticas facultativas. A ativação de proprietário usa uma API separada. Os avisos por email **podem transmitir emails, dados de apostas e recibos**; logo, não declarar «sem recolha de dados».
- A API tem um domínio técnico pertencente a outra entidade; migrar para domínio/subdomínio independente antes de comercializar.
- `image_picker` **e** `file_picker` estão ambos nas dependências. Não remover `file_picker` sem verificar funcionalidades de importação e backup.
- O reconhecimento ML Kit continua bundled; qualquer passagem a unbundled tem risco operacional em dispositivos sem serviços/modelos disponíveis. Medir antes de mudar.

## AAB para teste fechado — fluxo proposto

Workflow manual `.github/workflows/play-aab.yml`. Usa os quatro segredos GitHub já esperados pelo APK release:

- `ANDROID_KEYSTORE_BASE64`
- `ANDROID_KEYSTORE_PASSWORD`
- `ANDROID_KEY_ALIAS`
- `ANDROID_KEY_PASSWORD`

Executa a validação Flutter, gera `flutter build appbundle --release --target-platform android-arm,android-arm64,android-x64`, confirma assinatura JAR e SHA-256 do certificado esperado, verifica integridade do ZIP, manifesto base e presença das três arquiteturas. Guarda artefacto AAB e checksum (14 dias). **Não faz submissão automática nem valida políticas da Play Console.** Guardar cópia segura da chave de upload (não no repositório). Confirmar no primeiro envio se é a mesma chave que ficará registada no Play App Signing.

## Antes do lançamento

1. **Google Play / lotarias:** solicitar avaliação da elegibilidade em Play Console. O LuckyScan50 não aceita apostas, mas **acompanha recibos, resultados e prémios** de jogos a dinheiro real. O facto de não cobrar apostas não assegura por si só aceitação. As restrições de publicidade para funcionalidades complementares de lotarias são especialmente relevantes. Não publicar publicidade de jogo nem assumir antecipadamente que uma versão paga é permitida na categoria selecionada. Não declarar que é uma «app de jogo licenciada» sem fundamento.
2. **Dados e privacidade:** completar Data safety com base na app inteira e SDKs — email e dados de recibos sincronizados nos avisos opcionais, identificadores de licença, telemetria facultativa, IP/segurança do servidor, exportações e fornecedores de envio. Rever prazo de retenção e eliminação efetiva do lado do servidor, incluindo backups. A política pública foi atualizada nesta branch, mas o endereço HTTPS público e um **link clicável dentro da app** permanecem por verificar/implementar.
3. **Marca e conteúdo:** usar identidade visual original, aviso de independência e indicação de confirmação de prémios pelos canais oficiais. Não prometer previsões nem maiores probabilidades de ganhar; validar a classificação de conteúdo em vez de presumir o resultado IARC.
4. **Compatibilidade:** confirmar `targetSdkVersion=36` no AAB final, ícone adaptativo + monocromático, acessibilidade/contraste, Android 15/16 edge-to-edge, navegação, modo offline, câmara, OCR, múltiplos concursos e integração M1lhão.
5. **Comercialização:** publicidade, compras e funcionalidades premium não estão instaladas na release 0.2.15; rever Data safety e políticas antes de as integrar.
6. **Operação:** testar a API e o envio de email em produção com consentimento, apagar/remover dados locais e remotos, verificação do certificado de upload, pré-lançamento e teste fechado (12 testadores durante 14 dias em contas pessoais criadas depois de 13-11-2023).

## Referências oficiais

- Política sobre jogos a dinheiro real: https://support.google.com/googleplay/android-developer/answer/9877032
- Requisitos de dados: https://support.google.com/googleplay/android-developer/answer/10787469
- Políticas de dados pessoais: https://support.google.com/googleplay/android-developer/answer/10144311
- Play App Signing: https://support.google.com/googleplay/android-developer/answer/9842756
- Testes de contas pessoais recentes: https://support.google.com/googleplay/android-developer/answer/14151465
- API level exigida: https://developer.android.com/google/play/requirements/target-sdk

**Estado:** material de preparação para revisão e testes, não declaração de «pronto a publicar».
