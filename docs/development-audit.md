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


## Continuação da auditoria técnica — 17/10/2026

O acesso ao executor foi recuperado. O bundle original foi novamente verificado e criado `/workspace/LuckyScan50-pre-audit.bundle` antes de conciliar o remoto `41daded` com os três commits locais. O merge `b015a0a` preservou `8c9b80f`, `2575399` e `cb6a011` e foi publicado por push normal, sem force.

Foram demonstradas três falhas do parser recebido (cabeçalho com M1lhão interrompia leitura; N/E na mesma linha; euro posterior ao total). O commit `5a842b5` separa scanner, parser e política de preenchimento, preserva leituras parciais e edições manuais. `293e897` acrescenta gates do APK e `75e248f` completa coordenadas locais e filtros de ABI no build type.

Executado nesta continuação: 13 testes Python, 31 Flutter e 10 TypeScript aprovados; `flutter analyze`, tipos TypeScript e build TypeScript aprovados. As três regressões OCR falharam antes da correção e passaram depois. Os três testes novos de widgets exercitam o formulário real com reconhecimento substituído por transcrição; não são OCR nativo de fotografias.

APK debug 0.2.1+3 ARM64 produzido com código `75e248f`, assinatura/CRC/SHA-256/ABI/alinhamento ELF e ZIP de 16 KB verificados; chave debug local inalterada. O artefacto local está em `/workspace/artifacts/LuckyScan50-audit-0.2.1-arm64.apk`; checksum e manifesto estão ao lado. A consulta de runs GitHub devolveu Forbidden, pelo que não se confirma execução/artefacto remoto. A produção cPanel não foi alterada ou migrada.

As fotografias reais vertical/90° e os binários originais de identidade visual não estão disponíveis. Não se declara o objetivo OCR real concluído. O relatório integral, matriz, comparação fundamentada com Tesseract, riscos e plano estão em [AUDITORIA_TECNICA_LUCKYSCAN50.md](AUDITORIA_TECNICA_LUCKYSCAN50.md).

## Recuperação de colunas verticais — continuação

O diagnóstico real comunicado pelo utilizador identifica palavras verticais a ~90° e 685–698 px. Foi implementado um protótipo de recuperação por zona/linhas observadas, recortes PNG nativos da imagem sem redução prévia, EXIF normalizado, tentativas por linha/2× e orientações alternativas quando faltam âncoras. Preserva leitura inicial, edições manuais, metadados e proveniência por valor; conflitos não são resolvidos por preenchimento conhecido.

Validação desta continuação: 44 testes Flutter e 13 Python passaram; análise estática e compilação Kotlin/debug interna passaram. Não havia fotografias reais nem dispositivos Android no ADB: o teste de aceitação real **não foi executado**, e precisão/latência real permanecem não medidas. O novo teste Android exige ambas as imagens e compara saídas reais e preenchimento do formulário.

Nenhum novo APK foi publicado ou disponibilizado. O upload foi removido do workflow até demonstração real, e há guarda contra fotos privadas nos assets de CI. Foi medido um snapshot debug interno (119 599 026 bytes, +22 647 294 face ao anterior), incluindo suporte de teste e empacotamento; não representa impacto isolado do recorte nem tamanho release. O protótipo Tesseract é desktop e limitado a regiões N/E, sem novo motor no APK. Ver [OCR_MULTIPASS.md](OCR_MULTIPASS.md) e o estado estruturado em `docs/validation/2026-10-17-multipass-status.json`.


## APK de diagnóstico e limpeza — continuação a partir de df260a3

A autorização seguinte permite entregar um APK de diagnóstico sem declarar o
OCR real validado. Commits publicados: `3eee516` (exportação JSON e isolamento
QA) e `e5a43e8` (tempos efetivamente medidos). Histórico anterior preservado;
`/workspace/LuckyScan50-work.bundle` voltou a passar `git bundle verify`.

Comparação release ARM64 idêntica: 31 730 810 → 31 730 328 bytes; limpeza de
482 bytes (0,001519%). Saíram oito pacotes Dart do grafo da aplicação e os
assets de fotografias de teste. Os plugins de teste já eram excluídos do release;
o grafo Maven release, código executável, bibliotecas e modelos ficaram iguais
no build só de limpeza. O SQLite FFI e o integration_test passaram a cópias QA
temporárias. ML Kit Latin e JNI do path_provider permanecem; Tesseract só desktop.

APK final **0.2.2+4**, código `e5a43e8`: **31 729 912 bytes**, assinatura de teste
local anterior preservada, integridade CRC/SHA-256, ARM64 e ELF/ZIP de 16 KB
verificados. Download local: `/workspace/artifacts/LuckyScan50-diagnostic-0.2.2-arm64.apk`.
Relatório exportável inclui primeira passagem, orientações, recortes, apostas,
estrelas, proveniência, conflitos, tempos e erros, sem fotografias por defeito.

Checks finais efetivamente executados: `flutter analyze` sem problemas,
`flutter test` **45 aprovados**, runner SQLite FFI com lockfile **1 aprovado**,
API Python **13 aprovados**; compilação Android release aprovada. Manifesto e
lockfile de produção permaneceram inalterados durante o runner QA.
O teste com as duas fotografias originais e o formulário Android não foi
executado: fotografias indisponíveis e ADB sem dispositivos. Precisão por aposta,
latência real e execução num dispositivo de 16 KB continuam não medidas.

Workflow atualizado com artefactos de diagnóstico (APK, SHA-256, inventário),
retenção de 14 dias e upload só para a branch de desenvolvimento. O arranque
manual pela interface exige o ficheiro na branch predefinida; como não está na
main, o push da branch serve de gatilho. Pushes normais confirmados, sem força.
A consulta de runs pela API continua bloqueada com `Forbidden`; não se afirma
que já existe um artefacto remoto. API cPanel, dados de produção, main e Play
não foram alterados. Relatório e inventários completos em
[DEPENDENCY_APK_AUDIT.md](DEPENDENCY_APK_AUDIT.md).
