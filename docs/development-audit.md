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


## Recuperação por células com diagnóstico real — continuação

Base preservada `5aa4679`, branch `codex/luckyscan50-android-wallet`.
Analisados o JSON real `LuckyScan50-OCR-1792267583612.json` e a fotografia visível
na conversa. O fixture conserva geometria/recortes, sem identificadores
administrativos ou fotografias. Foi identificado que quatro palavras verticais
correspondem a pares de caixas de algarismos sobrepostas em duas colunas.

Implementadas células relativas às âncoras N, sondagem e verificação do marcador
E entre linhas, colunas separadas para estrelas, consenso por aposta/tipo/posição,
proveniência com caixas/estados e correções numéricas com confirmação. Campos
iniciais que não possam ser associados são conservados pelo fallback. A seleção
de orientação rejeita âncoras invertidas. A preparação nativa reutiliza
BitmapRegionDecoder; recortes são eliminados após OCR e o JSON regista fases e
limpeza, sem fotografias. Edições manuais, M1lhão, carteira e prémios preservados.

No replay dos resultados **já existentes** no JSON, o 20 do recorte `row-5@1x`
passa a N[3] da quinta aposta: 14 → 15 posições numéricas confirmadas. Permanecem
0 apostas completas e 0 estrelas nesse replay; não é uma recuperação visual nova.
Precisão e latência reais no Android não foram medidas. ADB sem dispositivos,
sem emulador/KVM e sem binário da fotografia disponível no checkout para o harness.
A imagem recebida é visível para inspeção humana, não uma prova de execução ML Kit.

Validação final: **66 testes Flutter**, **1 SQLite FFI**, **13 Python** aprovados;
análise estática e formatação sem problemas. Compilação release ARM64 do código
`a459865` aprovada; assinatura/CRC/ABI/ELF e ZIP de 16 KB verificados. As falhas
intermédias de estilo e configuração XDG foram corrigidas; a compilação final
inclui Kotlin com o ambiente ativado corretamente.

Comparação release ARM64 equivalente: **31 729 912 → 31 860 984 bytes**,
**+131 072 bytes (+0,413087%)**. Cresce o código; não se acrescentaram bibliotecas
ou modelos. Grafo Maven release, pubspec/lock/Gradle e três bibliotecas externas
permanecem iguais; libapp.so inclui a lógica nova. A limpeza anterior já isolou
as dependências de teste. Modelos Latin offline mantidos, Tesseract só desktop.

Não foi publicado novo APK/AAB/Release e a etapa de upload Android foi removida
do workflow, incluindo execuções manuais. O APK anterior em artifacts não foi
alterado. Commits pequenos `1fa87c9`, `8a6a946`, `8c4f85d`, `3d15819`, `b01c12a`,
`47cbc3b`, `444336e`, `a459865`; relatório em [OCR_CELL_RECOVERY.md](OCR_CELL_RECOVERY.md).
Sem merge para main, mudanças em cPanel, migração de dados ou publicação Play.
Aceitação com as duas orientações num Android continua obrigatória e pendente.

## 2026-10-17 — RSS oficiais e auditoria de prémios

Base preservada: `1bc1b822ac0a1e6d9caffaca2c328461710ce815`, branch
`codex/luckyscan50-android-wallet`. Sem alterações Android/OCR, dependências,
versão, APK ou produção. Os bundles anteriores não foram alterados.

Implementado `api-python/rss_import.py`: três fontes HTTPS fixas, XML/HTML,
validação estrita, montantes em cêntimos, concursos separados por jogo, datas
normalizadas, auditoria/proveniência e quarentena de conflitos. Transação comum
com o Store existente, idempotência, preservação de concursos já guardados e
resistência a falhas. O novo GET `/v1/rss/overview` devolve resultados observados,
previsões e indicadores `portal_only`, separados das categorias oficiais.
Sem data de sorteio confirmada separadamente, não cria concurso no histórico.
As estatísticas usam o histórico completo de chaves confirmadas, com
`scope=stored_confirmed_keys` e revalidação HTTP; não há cache interna a invalidar.
A carteira continua a exigir `complete` para cálculo de prémios.

Verificação real por leituras HTTPS: os três feeds `/web/SCRss/` responderam 200
sem redirects. XML ISO-8859-1 originais guardados em `api-python/fixtures/rss/`,
com hashes no manifest. Resultados: Euromilhões 083/2026, 7/15/16/22/35 + 4/6;
M1lhão 009/2026, PTM 09893. Próximos: 084/2026 em 20/10, 59 milhões previstos;
010/2026 em 30/10, 1 milhão anunciado. Portal mantém valores do último sorteio
separados dos históricos e não transforma SEM DADOS em ausência de vencedor.

A API instalada reportou versão 0.1.1. A página oficial do Euromilhões e a resposta
da API para 083/2026 coincidem nas **13 categorias**, valores unitários e contagens
de vencedores. Categoria 5: 101,06 €, distinta dos 224,64 € do Portal.
O código de origem é importação administrativa JSON, sem coletor de categorias;
a cadeia histórica dessa importação não pode ser provada apenas pelo `sourceUrl`.
Evidência pública de leitura: `docs/validation/rss-source-audit-20261017.json`.
Relatório e instruções: `docs/rss-integration.md`.

Validação efetivamente executada nesta tarefa:

- `PYTHONDONTWRITEBYTECODE=1 python3 -m unittest discover -v`: **38 testes passam**,
  incluindo os 13 testes anteriores, XML reais, seis codificações, entidades,
  referências monetárias, intervalos, identidade/data, conflitos, falhas parciais,
  replay, quatro importações concorrentes, rollback e estatísticas do histórico.
- CLI sobre `/tmp/luckyscan50-rss-final-check.sqlite3`: três feeds importados;
  Euromilhões com data confirmada inserido uma vez, M1lhão pendente de data;
  repetição não cria revisão nem concurso duplicado.
- Coletor `run_remote` real sobre `/tmp/luckyscan50-rss-live-validation.sqlite3`:
  seis observações aceites, zero conflitos; zero concursos criados sem datas
  confirmadas. Nenhuma escrita ou migração de base remota.
- `git diff --check`: sem erros.

Não executados Flutter/análise/compilação Android nesta tarefa exclusivamente
backend; não se usa a suíte Python para declarar OCR validado. Não foram gerados
ou publicados APK, Release, versão de produção ou Cron. A integração está preparada
para revisão e validação local; a ativação no cPanel continua fora desta entrega.

## 2026-10-17 — Contagem dinâmica OCR e posições pendentes

Base preservada `7a251f96192ca942e3dbacc38c423a274259903a`, branch de desenvolvimento
existente. Implementada análise de separadores por luminância reduzida no dispositivo,
coluna sequencial N, pares N/E com limites por aposta, total variável e lacunas sem
renumeração. Rodapés deixam de poder prolongar a zona de apostas. Identificadores
incompatíveis com a sequência geram aviso. Recortes e orçamento de células adaptados
a 1–20 apostas (limite de segurança OCR já existente), incluindo índices de dois
algarismos. O formulário conserva posições pendentes com `?`, impede a gravação até
à sua correção e preserva edições manuais. Diagnóstico inclui contagem, lacunas,
separadores e recortes; não inclui pixels de luminância nem fotografias.

Validação executada: `flutter analyze --no-pub` sem problemas; suíte Flutter completa
com **83 testes a passar**; Kotlin Android ARM64 `:app:compileReleaseKotlin --offline`
com **BUILD SUCCESSFUL** em 52 s. Testes novos cobrem 1/2/5/12/20 apostas, lacunas
2/10, identificadores mal lidos, N/E parcialmente ilegíveis, orçamento acima de 40
passagens, separadores sintéticos inclinados e rodapés/códigos. Mantidas regressões
do diagnóstico geométrico real e testes de proteção das edições. `git diff --check`
sem erros. Não foi repetida a suíte Python: não há alteração da API nesta tarefa.

Não alterados API, dependências/lock, modelos OCR, versão ou workflow de publicação.
Não executado empacotamento/publicação de APK nem OCR real num Android. Fotografias
reais e tempo adicional no dispositivo continuam por validar; não se declara OCR
integralmente validado. Relatório: `docs/OCR_DYNAMIC_BETS.md`.
