# LuckyScan50

Carteira Android independente para registar apostas portuguesas do Euromilhões e M1lhão, guardar comprovativos localmente e consultar resultados importados administrativamente.

**Projeto não oficial, sem associação aos Jogos Santa Casa.** Os resultados e prémios apresentados são informativos; prevalece a validação do operador autorizado. As estatísticas não preveem sorteios.

## Estado real: versão de auditoria 0.2.1+3

- Aplicação Flutter Android navegável, português de Portugal, temas claro/escuro.
- Entrada manual de várias chaves e concursos por recibo; Euromilhões e M1lhão associados, com uma única despesa.
- Carteira SQLite privada, pesquisa por identificador/concurso, filtros, registo de recebimentos e histórico de alterações.
- Consulta da API existente, cache offline, sincronização manual e ao regressar à aplicação, cálculo local dos 13 escalões e códigos M1lhão.
- Captura/galeria e OCR local com ML Kit. Interpretação conservadora N/E e preenchimento automático de campos explícitos, com confirmação. Testes textuais e de formulário passam; as fotografias reais ainda não foram validadas.
- Totais financeiros, frequências dos números em cache e pessoais, exportação CSV, backup AES-GCM de recibos e imagens e restauro por ID.
- API de produção Python 3.12 Passenger/WSGI nativo, sem dependências externas, SQLite transacional, migração JSON com cópia, revisões, estatísticas e consulta pública somente de leitura.
- Adaptador administrativo de importação manual/caixa de entrada para execução manual ou futura configuração Cron pelo proprietário.

**Ainda não concluído:** validação OCR com fotografias reais e cobertura de outros formatos de comprovativo, notificações Android, agendamento em segundo plano, prazos com versões regulamentares, bloqueio biométrico, estatísticas pessoais completas por período, exportação XLSX e distribuição assinada. Não existe scraper autorizado nem Cron remoto ativo. A aplicação ainda requer testes num dispositivo Android real para câmara/OCR, seletor de ficheiros, partilha e restauro. Não usar como única prova de direito a prémios.

## Repositório

| Pasta | Função |
| --- | --- |
| `app/` | Aplicação Flutter Android (`com.gilpereira.luckyscan50`) |
| `api-python/` | Backend de produção, Passenger WSGI e SQLite |
| `backend/` | Implementação TypeScript conservada como referência/regressão |
| `shared/` | Escalões partilhados |
| `docs/` | Contratos, auditoria e decisões |

## Desenvolvimento

Flutter **3.35.7**, Dart 3.9.2, Android API 36, minSdk 23, JDK 17 ou 21. Compilação de testes:

```sh
cd app
flutter pub get --enforce-lockfile
flutter analyze
flutter test
flutter build apk --debug --target-platform android-arm64
```

Os testes SQLite de desktop necessitam de `libsqlite3.so` (`libsqlite3-dev` em Debian/Ubuntu). A aplicação Android usa SQLite do sistema. O APK fica em `app/build/app/outputs/flutter-apk/app-debug.apk`. Instalar com `adb install -r <apk>` num dispositivo de testes. Não há assinatura de produção configurada.

```sh
cd api-python
python3 -m unittest discover -v
PORT=3001 python3 app.py
```

O backend de referência continua a suportar `npm install`, `npm run lint`, `npm test -- --maxWorkers=2 --minWorkers=1` e `npm run build` em `backend/`, com Node 22.

Consulte [instalação Android](app/README.md), [Passenger e migrações](api-python/README.md), [contratos HTTP](docs/results-api.md) e [auditoria e limitações](docs/development-audit.md). Nenhum comando faz deploy para o cPanel ou altera o WordPress.

## Auditoria OCR de 17/10/2026

Consulte o [relatório técnico integral](docs/AUDITORIA_TECNICA_LUCKYSCAN50.md) para causas reproduzidas, matriz de funcionalidades, comparação ML Kit/Tesseract e limitações. O APK de auditoria compilado localmente passou verificação de assinatura, ABI e alinhamento de 16 KB; isso não demonstra reconhecimento correto das fotografias ausentes. A CI publica apenas artefactos debug verificados, sem release definitiva.
