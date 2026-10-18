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

## 2026-10-17 — Coletor RSS periódico e pacote cPanel

Base preservada `0ea62c9c6ca504fb52cc4d9938bee5920c3c7bb3`. Auditados
`rss_import.py`, `store.py`, `collect_results.py` e `app.py`. Store e o ponto de
entrada de desenvolvimento mantidos; nenhuma alteração Android, de dependências
ou de produção. O coletor agora tem `--rss` com configuração explícita, HTTPS
direto aos três feeds, bloqueio não bloqueante partilhado com inbox, tratamento
independente de erros, staging antes de promover concursos, datas anunciadas em
snapshots anteriores ou confirmadas administrativamente e quarentena de conflitos.
Recusa base inexistente para impedir uma base vazia desligada da API. O modo
`--inbox` continua compatível e não faz HTTP. Exemplo de configuração vem desativado.

Estatísticas acrescentam `coverage`: amostra, período disponível e histórico
integral não auditado. Não se apresenta `drawCount: 1` como cobertura desde 2004.
Investigação histórica limitada ao material já preservado: página oficial SC
com 30 concursos recentes e três RSS sem arquivo; identificado o arquivo oficial
FDJ como candidato ainda por consultar/validar. Não houve download ou carga
histórica, nem se declarou validado um arquivo não consultado.

Validação: **55 testes Python passam**, com os três XML reais preservados,
transportes simulados/bloqueados, idempotência, lock inbox/RSS, falhas parciais,
conflitos de chave/data, promoção de concurso com data anunciada diferente da
publicação, backup consistente e aviso de cobertura. Nenhum pedido de recolha
remota foi executado nesta tarefa. O teste HTTP usa mocks; não comprova acesso
atual ao fornecedor a partir do cPanel. Não foram repetidos testes Flutter ou
compilação: o Android não foi alterado.

Preparados `backup_results.py`, exemplos privados de configuração e datas,
`tools/package_cpanel_api.py`, instruções de instalação, Cron a cada 30 minutos e
rollback. ZIP tem módulos na raiz para extrair dentro de `api-luckyscan50`,
validação separada e hashes, sem dados/configuração de produção. O Cron assume
os caminhos convencionais do virtualenv cPanel e deve ser conferido no painel;
nenhum Cron, deployment ou migração remota foi executado.

Documentação: `docs/rss-cron-cpanel.md` e `docs/historical-results-sources.md`.

## 2026-10-17 — APK 0.2.3+5 autorizado para teste OCR

A pedido explícito do utilizador, gerado APK de diagnóstico ARM64 com contagem
variável e posições pendentes do commit `0ea62c9`. Código compilado `a2abf69`,
versão exibida e Android `0.2.3+5`; identificador do commit confirmado no binário.
API e dependências inalteradas nesta entrega. Não há publicação Google Play ou
ativação de workflow de distribuição automática.

Executados `flutter analyze --no-pub` (sem problemas), `flutter test --no-pub`
(**83 testes passam**) e `flutter build apk --release --target-platform android-arm64
--no-pub --dart-define=LUCKYSCAN_BUILD_SHA=a2abf69` (sucesso, 144,4 s).
`tools/verify_apk.py` confirmou CRC, assinatura, exclusivamente ARM64/AArch64,
quatro bibliotecas nativas e alinhamento ELF/ZIP de 16 KB; nenhum modelo Tesseract
ou imagem de teste privada. Certificado igual ao APK 0.2.2 anterior, permitindo
atualização com o mesmo applicationId e versionCode aumentado para 5.

Artefacto `/workspace/artifacts/LuckyScan50-diagnostic-0.2.3-arm64.apk`,
31 860 984 bytes (31,86 MB), SHA-256
`bcfa5ccffc2ed3fde0db200052e00982085bb1b61ab606179ca27f21143ef01e`.
Comparação com a compilação release anterior 0.2.2: +131 072 bytes (+0,4131%).
Relatório: `docs/validation/2026-10-17-dynamic-ocr-apk.json`.

`adb devices -l` não encontrou dispositivos. Instalação, leitura da fotografia
nas duas orientações e preenchimento automático real continuam por testar no
Android do utilizador. O APK é entregue para permitir esse teste; não se declara
OCR real validado por passar nos testes automatizados. O relatório exportado pela
aplicação identifica `0.2.3+5` e `a2abf69`, preservando a primeira passagem e a
análise dinâmica de recortes/identificadores, sem fotos incluídas por defeito.

## 2026-10-18 — Confirmação automática do cartaz Euromilhões

Base preservada `e29937db18a4802adcab7500080f68b3bf97c678`. Acrescentado
`official_cartaz.py`, ligado ao coletor CLI existente sem mudar o comando Cron.
O cartaz fornece explicitamente identificador, data, chave e 13 escalões; os três
RSS mantêm papéis independentes. Não se atribui pubDate ao sorteio, não se infere
uma data M1lhão a partir do Euromilhões e não se usam jackpots ou Portal como
montantes unitários. Na falta de confirmação, mantêm-se estados pendentes.

Reconciliação sob o lock atual e transação partilhada com `Store.import_rows()`:
novos concursos, promoção de parcial compatível para completo com nova revisão,
repetições sem revisões extras e conflitos sem substituição silenciosa.
Concursos completos nunca são automaticamente corrigidos. Auditoria aditiva em
`official_observations`, com URL, hash, primeira importação, candidato e motivos;
publicação HTML desconhecida permanece null. Nenhuma migração destrutiva.

**76 testes Python passam**, incluindo o cartaz real integral guardado na auditoria
anterior e os três XML reais; 13 escalões verificados contra o fixture, casos de
montantes/vencedores em falta, notas de prémios não atribuídos, concursos novos,
repetição, duas revisões na promoção, conflitos e contratos latest/sync/overview.
Nenhuma dependência adicional: produção continua só com biblioteca padrão.

A tentativa de leitura pública do cartaz M1lhão foi bloqueada pelo proxy com 403.
Sem contorno de rede ou parser desse HTML não verificado: datas M1lhão continuam
através de anúncio oficial guardado ou ficheiro administrativo verificado.
Não se comprovou acesso atual ao cartaz a partir do cPanel nesta tarefa.

Não alterados Android, dependências, endpoints, SQLite de produção, instalação
Passenger ou Cron existente. Não foi feito deploy ou executada recolha contra a
base de produção. Documentação e ficheiros a atualizar em
`docs/official-results-cpanel.md`. Empacotamento cPanel mantém módulos na raiz,
configuração privada e dados fora do ZIP, com testes separados.

Na entrega, o primeiro push foi recusado porque a branch remota tinha avançado
até `95a6781`. Integrado esse histórico pelo merge `2c1ee93`, sem conflitos e sem
force push, preservando alterações Android/CI e imagens feitas em paralelo.
A árvore `api-python`, documentação e empacotador permaneceu idêntica ao commit
validado `66368c8`; o ZIP dessa implementação continua a corresponder ao código
backend integrado. Não foram reescritas alterações alheias ou criado/publicado APK.

## 2026-10-18 — Estabilização geométrica N/E e release privada

Base remota preservada: `feb9c45e553a0beee7277c51e82e1fcfbee76508`.
Reprodução inicial: 78 testes Flutter aprovados e seis falhas. Corrigida a
associação geométrica com coordenadas compensadas pela inclinação, índices
impressos independentes da posição, passo normalizado pela diferença entre
índices e limites N/E por aposta. Valores equidistantes ou associações ambíguas
ficam pendentes; uma linha E parcial conserva os valores efetivamente lidos.
Nenhuma expectativa dos testes foi enfraquecida e nenhum valor foi inferido.

Validação local: `flutter pub get --enforce-lockfile`, formatação dos cinco
diretórios pedidos e verificação sem alterações, `flutter analyze` sem problemas,
84 testes Flutter aprovados; 76 testes Python API, 10 testes Node e typecheck,
um teste SQLite isolado e três testes de segurança do verificador APK aprovados.
Corrigido o preparador SQLite para copiar apenas os assets públicos de branding,
sem fotografias ou ficheiros de assinatura. Sem dependências Android adicionais.

Versão preparada: 0.2.4+6. `signed-apk.yml` executa a validação reutilizável antes
da release ARM64. Exige os quatro secrets Android existentes, não admite fallback
para chave debug, verifica certificado contra o keystore configurado, CRC, ABI,
alinhamento ELF/ZIP de 16 KB e assets. Publica apenas
`LuckyScan50-signed-arm64.apk`. Branding permitido apenas quando corresponde
byte a byte ao ficheiro público versionado; outros assets de imagem/modelos
Tesseract são recusados. A tarefa Gradle sem chave privada foi testada e falhou
explicitamente, como previsto. Não se gerou uma chave alternativa local.

`gh` 2.46.0 disponível. O proxy recusa CONNECT a `api.github.com` (domínio fora da
política permitida), antes da autenticação: a validade/permissões do token não
pôde ser determinada. A página pública de Actions em `github.com` é acessível e
será usada para consultar as execuções. Não houve contorno de proxy.
O estado final do run/artifact deve ser confirmado após o push; esta entrada não
constitui prova de APK compilada ou descarregada. OCR real em Android com as
fotografias nas duas orientações continua sem validação neste ambiente.
Backend, SQLite de produção e Cron não foram modificados.

Verificação adicional: a preparação QA Android foi corrigida para acrescentar
as fotografias privadas na secção assets existente, sem duplicar a chave YAML.
`python3 tools/run_flutter_qa.py android --resolve-only` passou; não executa OCR.
O descodificador do secret base64 aceita quebras de linha sem deixar de validar
os caracteres. A execução remota `39126707826` aprovou a validação completa e
iniciou o job de assinatura; aguarda-se o seu resultado e artefacto.

### Resultado remoto confirmado — APK assinada publicada

Código compilado: `fb8179e12d98f91b53df19579cab62cc6e45674d`.
Workflow `.github/workflows/signed-apk.yml`, execução
https://github.com/GilPereiraPT/LuckyScan50/actions/runs/39127946222 : **success**,
7m23s. Validação completa: 1m25s; assinatura/compilação/verificação/upload: 5m53s.
A página do GitHub confirma um artefacto `LuckyScan50-signed-arm64-APK`, ID
`12137002388`, com o APK `LuckyScan50-signed-arm64.apk` (0.2.4+6).
Ligação autenticada:
https://github.com/GilPereiraPT/LuckyScan50/actions/runs/39127946222/artifacts/12137002388
Retenção configurada: 14 dias.

Tamanho mostrado pelo GitHub para o **arquivo do artefacto**: 15.3 MB; não é uma
medição do APK descomprimido. Digest do arquivo publicado:
`cff9680199f890b2593ed1fd4b16dba08fc59e371b5981d84e2ff2b6a693b76a`.
Este digest não é apresentado como SHA256 do APK.

As três tentativas anteriores chegaram à verificação final, mas não publicaram
artefactos: `39126707826`, `39127028191`, `39127277273`. A anotação detalhada
revelou `Missing signing certificate digest`. Fixados os build-tools de
verificação em 35.0.0, reproduzida localmente a leitura do certificado e a rejeição
de debug com essa versão; o run seguinte passou. Não se relaxou a exigência de
correspondência entre o certificado do APK e o DER exportado do keystore privado.
O run verde executou também CRC, inventário de assets, ABI ARM64 única,
alinhamento ELF e ZIP de 16 KB e upload com erro se o APK estiver ausente.

**Limite de verificação:** confirmei o sucesso dos dois jobs e a existência,
nome, ID e digest do artefacto na página pública. A transferência autenticada
não pôde ser reproduzida localmente: a ligação de download retorna 404 na sessão
sem login; API/gh continuam bloqueados pelo proxy. Não se inventaram o tamanho
descomprimido nem a impressão digital do certificado, disponíveis no resumo do
job para utilizadores autenticados. Não houve instalação num dispositivo nem
validação do OCR real com as duas fotografias. A APK está publicada; a precisão
real e a experiência de instalação continuam a exigir o teste no Android.

Proposta de configuração do ambiente guardada para acrescentar apenas
`api.github.com` aos domínios personalizados. É um rascunho confirmado pelo
serviço; precisa de revisão, gravação e publicação nas definições do ambiente.
Não foi aplicado à rede da sessão nem alterou o token injetado.

## 2026-10-18 — Auditoria integral, PR #10 e estatísticas oficiais

Nova base confirmada `a37ad82d8c7d8c5d5ed37b50506cd07b4c17b8eb`,
`codex/mlkit-ne-line-structure`, isolada em worktree sem mudar o checkout anterior.
Relatório completo em `docs/auditoria-tecnica-integral.md`: arquitetura, branches,
causas/evidências/gravidades, propostas, medidas, testes e limitações.

Publicadas sem force push:
- `audit/luckyscan50-integral-20261018` — código
  `ab5484ea3492f517e74860bc232ea4499784db56`, correções conservadoras
  OCR/carteira/validação e CI Node24/Ubuntu24, diagnóstico manual, sem schema novo.
- `feat/luckyscan50-official-statistics-20261018` — código
  `e01b747e5237a23d11898f8ef2e11a9f9b0afbc2`, dependente da primeira:
  API/snapshots/CLI opt-in e cache/ecrã Android nas settings existentes.

Baseline103 Flutter; core isolado133 Flutter/80 Python; integração138 Flutter,
105 Python,10 Node,7 SQLite real FFI e7 verificador APK; format/analyze aprovados.
Actions verdes do código integrado:
https://github.com/GilPereiraPT/LuckyScan50/actions/runs/39170768974 e
https://github.com/GilPereiraPT/LuckyScan50/actions/runs/39170768976 .
Sem APK novo: Profile baseline/final bloqueado por403 no download do engine em
storage.googleapis.com. Sem chave privada local, assinatura substituta ou AAB.
Inspeção histórica separa bytes APK de ZIP e não atribui diferenças debug/release
a limpeza de dependências. Não foi removida dependência necessária.

Fonte SCEstatisticas/SCMotorBusca/SCCartazResult bloqueada por CONNECT403.
Nenhuma captura real17/10/2026 03:00 validada; os25 testes novos de estatísticas
usam fixtures sintéticas, API expõe snapshotReferenceVerified:false, não existem
62 valores reais importados nem histórico completo declarado. Prazos90/12/60 e
recebimentos por prémio são proposta pendente de fonte/migração, não funcionalidade
anunciada como concluída. OCR real Android permanece não demonstrado.

Dois `gh pr create --draft` falharam: POST api.github.com/graphql Forbidden.
Nenhum PR foi criado ou merge feito; textos guardados em docs/pull-requests.
Comparações para abrir PR1 e PR2 dependente, respetivamente:
https://github.com/GilPereiraPT/LuckyScan50/compare/codex/mlkit-ne-line-structure...audit/luckyscan50-integral-20261018?expand=1
https://github.com/GilPereiraPT/LuckyScan50/compare/audit/luckyscan50-integral-20261018...feat/luckyscan50-official-statistics-20261018?expand=1

Produção, Cron, SQLite real, assinaturas, main e Play não foram alterados.
Rascunho de rede guardado com api.github.com, www.jogossantacasa.pt e
storage.googleapis.com; necessita revisão/gravação/publicação nas definições,
não foi aplicado nem contornado na sessão.
