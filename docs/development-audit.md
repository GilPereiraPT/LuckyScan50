# Auditoria de desenvolvimento — 17/10/2026

## Base inspecionada

HEAD inicial `836dcabd09fa0d47efe8920aaa2e29ad9690c7fe`, branch local `work`, origem `GilPereiraPT/LuckyScan50`. Sem alterações locais iniciais. Inspecionados README, documentação, workflows, módulos Python/TypeScript/Dart, migração SQL de referência e fixture. Não foram encontradas instruções AGENTS.md no checkout.

O Python tinha Flask em `app.py` e uma cópia nativa em `passenger_wsgi.py`; apenas os três testes Flask eram executados. O TypeScript tinha dez testes de domínio e API HTTP sem testes HTTP. Flutter tinha dois módulos Dart e um teste de escalões, sem manifesto ou estrutura Android. A orientação inicial `flutter create` era ainda uma etapa de geração do produto.

A produção principal é Python nativo WSGI/Passenger. A implementação foi unificada e as dependências Flask removidas. `passenger_wsgi.application` mantém o ponto de entrada e os campos de resposta existentes. A configuração padrão continua a ler JSON, sem migração implícita. A mudança de backend para SQLite depende de execução administrativa e configuração explícita no cPanel.

## Evidência de produção, apenas leitura

GET `/health` confirmou 0.1.1 `native_wsgi`; GET do último Euromilhões confirmou 083/2026, 16/10/2026. O payload é aceite pelo validador novo. Nenhum ficheiro foi enviado ao alojamento, nenhuma tarefa Cron foi criada e nenhum site ou aplicação exterior foi alterado.

A página pública Euromilhões pôde ser consultada. Não se confirmou autorização documentada para recolha automatizada nem contrato de integração. Uma página pública não é autorização. Foi implementada importação administrativa extensível, sem scraper ou login. Os testes usam dados sintéticos `example.org`; o resultado live foi apenas lido fora do repositório para compatibilidade.

## Entrega e limites

API: SQLite normalizado, revisões imutáveis, importações transacionais e idempotentes, backup JSON na migração, validação, paginação, filtros, estatísticas e sincronização. Adaptador Cron local com bloqueio, sem recolha remota. Workflow manual alternativo valida JSON revisto sem deploy.

Android: primeira carteira local, navegação, entrada manual, anexos e transcrição OCR, verificação de resultados descarregados, finanças básicas, frequências, exportação e backup encriptado. sqflite foi escolhido como camada SQLite direta para esta primeira versão, sem geração Drift.

A interface declara as funções ainda indisponíveis. Não estão concluídos todos os pontos do caderno de requisitos: extração estruturada OCR, notificações Android, regras regulamentares e prazos versionados, biometria, calendário, estatísticas históricas/pessoais completas, XLSX, sincronização em segundo plano e AAB assinado. Não se devem inventar prazos ou tratar concursos futuros como concluídos. As dependências de autorização para recolha não impedem a carteira e a API administrativa.

Não há credenciais de produção configuradas; não são necessárias para testes locais. A publicação no GitHub e a compilação Android devem ser verificadas pelo resultado dos comandos, não por esta documentação. Os resultados finais da execução são apresentados no relatório da tarefa.

## Resultados desta execução

- Python: 13 testes passaram; leitura HTTP local de health, lista vazia, 404 esperado, estatísticas e snapshot sync verificada. Carregamento Passenger por caminho absoluto também verificado com Python isolado.
- TypeScript: 10 testes passaram e verificação de tipos concluída; compilação validada na preparação do ambiente e novamente pelo script de atualização.
- Flutter: análise estática sem problemas e 12 testes passaram, incluindo widgets, SQLite real, custo único de recibos, resultados parciais, prémios desconhecidos, códigos M1lhão duplicados e backup/restauro com imagens.
- APK: **não produzido** nesta execução. Instalados Flutter 3.35.7, JDK Temurin 21.0.12.1+1 (SHA-256 verificado), Android SDK e NDK. Corrigidos proxy Java e trust store sem desativar TLS. A compilação ficou bloqueada ao descarregar dependências: o proxy passou a devolver HTTP 503 com `remote connection failure` em Maven, Google, npm e GitHub. Não foi possível validar plugins nativos num dispositivo.
- Os commits iniciais, até `c04dd72`, foram publicados na branch `codex/luckyscan50-android-wallet` antes da falha de transporte. Os ajustes posteriores estão guardados em commits locais; é necessário repetir o push quando a rede regressar. A execução de CI remota não foi confirmada.

Próxima sequência: recuperar o transporte de rede, publicar os commits locais, concluir o APK e testar em Android real; depois implementar extração estruturada dos comprovativos, notificações e regras regulamentares versionadas. Não ativar recolha automática sem autorização nem fazer deploy cPanel sem validação e autorização próprias.
