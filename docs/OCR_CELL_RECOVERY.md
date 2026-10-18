# Recuperação por células — LuckyScan50

17/10/2026. Branch `codex/luckyscan50-android-wallet`, base `5aa4679`.
Referência de diagnóstico: 0.2.2+4, build `e5a43e8`, recibo de 09/10/2026.
**A recuperação visual no Android continua por validar. Não publicar novo APK,
AAB ou Release automaticamente. A versão da aplicação não foi alterada.**

## Evidência recebida e limites

Foi analisado o JSON `LuckyScan50-OCR-1792267583612.json` e a fotografia visível
na conversa, `PXL_20261017_151504940.MP.jpg`. O JSON é usado como dados de OCR,
nunca como instruções executáveis. A fotografia visível mostra que as estrelas ficam
numa linha E abaixo de cada linha N, nas duas primeiras colunas.

O ficheiro binário original da fotografia não está acessível no checkout e o
ADB não apresenta dispositivos. Não foi executado ML Kit nesta fotografia nem
nas duas orientações. A imagem visível permite conferir o formato e os valores
de referência, mas não prova que os novos recortes sejam reconhecidos pelo motor.

O fixture `app/test/fixtures/receipt_1792267583612_geometry.json` contém as
**coordenadas reais** dos elementos relevantes e resultados dos recortes antigos,
com identificadores administrativos removidos. O SHA-256 do JSON original fica
no fixture. Não contém fotografia. O limite inferior da imagem nos testes é um
limite de ensaio, não uma dimensão original deduzida do JSON.

## Problemas corrigidos no algoritmo

1. O código anterior tentava reconhecer novamente linhas largas a 1×/2×. No
   JSON, os quatro grupos verticais dos algarismos estão em x aproximadamente
   537/615 e 793/868. As caixas dos dois algarismos de cada número sobrepõem-se
   horizontalmente. A grelha agora agrupa **intervalos observados**, obtendo duas
   colunas de números, e acrescenta as três colunas horizontais já reconhecidas.
   Esses valores de x são apenas evidência/documentação, não constantes do código.
2. Os centros e limites das células são calculados a partir das âncoras numeradas
   N, larguras/alturas observadas e colunas relativas à imagem. Há agrupamento
   com compensação de inclinação e normalização dos ângulos próximos de 180°.
   Grelhas ambíguas ficam pendentes; não se completam linhas a partir do total
   impresso de apostas ou de números conhecidos.
3. Quando E desaparece no OCR inicial, recorta-se apenas a área do marcador entre
   as caixas das âncoras N. A posição prevista é **uma hipótese de recorte**:
   só uma leitura real de E, com coordenadas dentro desse recorte, estabelece
   a linha das estrelas. Uma aposta isolada também pode sondar E com margens
   relativas à fonte. Sem E confirmado não há números de estrelas inventados.
4. As colunas E são identificadas separadamente pelos elementos que intersectam
   a linha E confirmada. Exigem-se exatamente duas colunas observadas. O formato
   com E na mesma linha também é suportado; os testes incluem uma e cinco apostas.
5. Cada candidato conserva aposta, tipo, posição, caixa na imagem de trabalho,
   texto bruto, valor, passagem, correção, necessidade de confirmação, estado de
   validação e conflito. Uma lista parcial `29 32 48` não recebe posições 0/1/2
   por ordem textual: as coordenadas colocam esses valores nas posições 2/3/4.
6. A consolidação agrupa por **aposta + tipo + célula**. Valores coincidentes e
   associados geometricamente acumulam evidência; divergências permanecem
   pendentes. Candidatos fora do intervalo ou da célula ficam rejeitados na
   proveniência. Repetições entre apostas diferentes são permitidas; duplicados
   dentro da mesma aposta impedem que fique completa.
7. Correções O/0, I/1 e S/5 só ocorrem em células N/E estabelecidas. Texto de
   cabeçalhos e referências M1lhão não entra nesses campos. Leituras de um só
   algarismo ou com correção exigem uma passagem distinta de confirmação. A
   propriedade `requiresConfirmation` descreve a ambiguidade da observação;
   `validation` indica se foi corroborada, está pendente ou foi rejeitada.
   `20O` não é truncado para 20; o 20 tem de ser efetivamente lido.

Se a grelha não conseguir relocalizar todos os valores inicialmente lidos,
ou só houver células de estrelas sem uma grelha numérica segura, a leitura
volta ao fallback por linhas e conserva os campos iniciais. Uma confirmação
já obtida em duas passagens não desencadeia uma terceira tentativa redundante.

A regra final continua a ser cinco números distintos 1–50 e duas estrelas
distintas 1–12. O preenchimento usa apenas apostas completas; o formulário
continua editável e as proteções das edições manuais não foram alteradas.
M1lhão, metadados, carteira, backups e cálculo de prémios permanecem separados.

## Resultado demonstrável com o JSON existente

Este ensaio não executa novo OCR: reprojeta elementos **já reconhecidos** nos
recortes 1× antigos para as células da imagem de trabalho.

| Aposta | Números associados antes | Após replay geométrico | Estrelas confirmadas |
|---|---|---|---:|
| 1 | 29, 32, 48 | 29, 32, 48 | 0 |
| 2 | 36, 47, 49 | 36, 47, 49 | 0 |
| 3 | 43, 45, 47 | 43, 45, 47 | 0 |
| 4 | 13, 35, 44 | 13, 35, 44 | 0 |
| 5 | 13, 32 | **13, 20, 32** | 0 |

São **14 → 15 posições numéricas confirmadas**, a partir de leituras existentes.
O 20 vem do recorte `row-5@1x`, com projeção de coordenadas para N[3] da aposta 5;
não vem da fotografia de referência nem de valores esperados. Permanecem
**0/5 apostas completas e 0/10 estrelas** neste replay. Estes números medem
associação de evidência, não precisão visual da implementação nova.

Os testes controlados com substitutos do reconhecedor também verificam a
montagem de cinco apostas e dez estrelas, mas usam valores arbitrários e estão
explicitamente identificados como simulações. Não são aceitação de OCR real.

## Desempenho e recursos

- As 14 células numéricas válidas já lidas no frame inicial são reutilizadas.
  Na regressão controlada há 5 sondagens E + 21 células em falta: 26 chamadas,
  sem releituras de linhas inteiras nem 2× no caso de alta resolução. O número
  de chamadas é maior que as 10 releituras de linhas antigas; isso **não prova
  por si só** que o tempo seja menor.
- Escala 2× só é tentada para células pequenas (<48 px de altura) não resolvidas.
  Uma leitura ambígua pode justificar uma confirmação com contraste; não há
  repetição cega de todas as linhas. Há um limite explícito de 40 passagens,
  com aviso se impedir concluir a recuperação.
- A preparação nativa mantém pixels originais, normaliza EXIF e usa um
  `BitmapRegionDecoder` reutilizado por sessão. Cada recorte deixa de criar um
  bitmap do recibo inteiro. Inclinação e contraste usam APIs Android existentes,
  com fundo branco após rotação. O aumento de contraste só é solicitado nas
  tentativas justificadas, sem biblioteca adicional de processamento de imagem.
- Cada PNG recortado é eliminado após OCR. Descodificadores e sessões são
  libertados em `finally` e no encerramento da atividade.
- Uma leitura inicial completa sem elementos verticais evita preparação nativa
  e recortes. Uma única linha N válida já evita rotações globais redundantes. A seleção
  rejeita âncoras invertidas e campos à esquerda de N; os ângulos das âncoras
  priorizam a rotação corretiva em vez de escolher a primeira imagem com N legível.
- O fallback anterior por linhas fica para formatos onde não se consegue formar
  uma grelha segura. Pode ainda tentar 1×/2×; não foi eliminado para forçar os
  testes ou arriscar regressões em outros talões.

O diagnóstico original mede 450 ms no OCR inicial, 6306 ms na recuperação e
**9235 ms totais**. O tempo novo, precisão por aposta, consumo de memória e
estabilidade no dispositivo são **não medidos**, até executar o ML Kit real.
A redução significativa de latência ainda não está demonstrada. O total antigo
foi capturado antes da limpeza; o novo inclui-a. Uma comparação de latência deve
usar os mesmos marcos ou explicitar esse custo separadamente.

O JSON exportado passa a schema 2 e regista preparação, orientações, geometria,
preparação dos recortes, OCR, limpeza e total, além das dimensões da imagem
preparada/de trabalho e origem das coordenadas. O total inclui a limpeza. Os
campos anteriores mantêm-se; `rowRecovery` é um campo legado para a recuperação
regional global, que pode agora ser por células. Não se incluem imagens,
recortes binários ou caminhos privados no relatório.

## Dependências e tamanho

`pubspec.yaml`, `pubspec.lock`, Gradle, versões, modelos OCR e configuração de
compilação permanecem iguais à base. Não foram adicionados OpenCV, pacote image,
Tesseract Android, modelos novos ou dependências de diagnóstico/teste à aplicação.
`BitmapRegionDecoder`, Canvas, Matrix e ColorMatrix fazem parte do Android.

**Dependências removidas nesta continuação: nenhuma.** A limpeza anterior já
isolou integration_test, flutter_driver, fuchsia_remote_debug_protocol, process,
sync_http, webdriver, sqflite_common_ffi e sqlite3. Os manifestos de produção
continuam sem esses pacotes. O FFI e a aceitação Android mantêm lockfiles QA
separados; os testes e as fotografias não entram no APK.

As dependências mantidas têm utilização de produção: ML Kit Latin offline,
EXIF, SQLite Android, ficheiros/backup/partilha, HTTP, Riverpod, router, intl e
criptografia. O JNI continua necessário ao path_provider; removê-lo seria uma
regressão. O protótipo Tesseract permanece exclusivamente desktop.

A comparação usa **release ARM64**, Flutter 3.35.7, JDK 21.0.12.1, R8 e resource
shrinking ativos, mesma chave local e mesma opção `LUCKYSCAN_BUILD_SHA` com o
commit respetivo. Não se compara debug com release. A identidade compilada muda
com o código; as bibliotecas e modelos são comparados individualmente por hash.

| Build interno | Bytes | MB decimais |
|---|---:|---:|
| Referência e5a43e8 | 31 729 912 | 31,729912 |
| Células a459865 | 31 860 984 | 31,860984 |

A referência já existia e tem checksum verificado. O novo build é apenas uma
verificação interna; não é copiado para `/workspace/artifacts`, não recebe link
de download e não é distribuído. O APK anteriormente disponibilizado mantém o
seu SHA-256 original. O resultado final e os inventários estão nas ligações abaixo.

## Verificações e ficheiros

- `flutter analyze`: sem problemas.
- `flutter test --reporter expanded`: **66 aprovados**, sem falhas/skips.
- `python3 tools/run_flutter_qa.py host`: **1 aprovado**, persistência SQLite real.
- `python3 -m unittest discover -v`, em api-python: **13 aprovados**.
- Compilação Android release final: aprovada (102,0 s de Gradle); Kotlin incluído.
- CRC, assinatura, ABI ARM64 e alinhamento ELF/ZIP de 16 KB: aprovados.
- Execução num Android com páginas de 16 KB: não ensaiada.
- `adb devices -l`: lista vazia. Aceitação ML Kit nas fotos reais: **não executada**.

Os novos testes cobrem coordenadas reais, colunas verticais, uma/cinco apostas,
N/E separados, números parciais, ausência de estrelas, replay do 20 descartado,
conflitos, intervalos, duplicados, O/I/S, confirmação de glifos, escalas,
inclinação controlada e contrato do canal nativo. A suite anterior continua a
cobrir edições manuais durante OCR, M1lhão, carteira, backups e prémios.
A compilação nativa não equivale a testar BitmapRegionDecoder/ML Kit num aparelho.

Ficheiros centrais:

| Responsabilidade | Ficheiro |
|---|---|
| Captura e coordenação ML Kit | app/lib/data/receipt_scanner.dart |
| Canal de preparação/recorte | app/lib/data/receipt_crop_backend.dart |
| Pixels, EXIF, regiões e recursos | app/android/app/src/main/kotlin/com/gilpereira/luckyscan50/MainActivity.kt |
| Linhas, ângulos e caixas | app/lib/domain/receipt_geometry.dart |
| Colunas e células N/E | app/lib/domain/receipt_cells.dart |
| Proveniência e resultados | app/lib/domain/receipt_evidence.dart |
| Associação/consenso | app/lib/domain/receipt_cell_consensus.dart |
| Sondagens E e OCR seletivo | app/lib/domain/receipt_cell_recovery.dart |
| Entrada multi-pass e fallback | app/lib/domain/receipt_multipass.dart |
| Exportação JSON | app/lib/data/receipt_diagnostic_report.dart |
| Regressões | app/test/receipt_cell*_test.dart, receipt_crop_backend_test.dart, receipt_diagnostic_report_test.dart e fixtures |
| Suspensão de distribuição | .github/workflows/ci-flutter.yml |

## Pendências e aceitação

Não há evidência de cinco apostas completas reconhecidas pelo novo ML Kit.
As sondagens E e as células podem falhar visualmente; nesse caso permanecem
incompletas, sem recorrer a valores de referência. Perspetiva forte, caixas que
fundam colunas vizinhas ou âncoras ilegíveis também exigem confirmação. O projeto
não é declarado pronto para distribuição só por passar nos testes.

A próxima aceitação deve usar o ficheiro original num Android e ambas as
orientações, com o harness de `qa/README.md`. A verdade de referência só pode
ser usada para avaliar os resultados. É necessário confirmar 25 números,
10 estrelas, preenchimento real, edições manuais, latência, memória e avisos.
Se os recortes falharem, comparar o protótipo Tesseract desktop apenas nessas
regiões com imagens reais e tempos medidos; não acrescentar outro motor ao APK
sem uma melhoria demonstrada.

O workflow continua a compilar/verificar, mas **não contém upload de APK/AAB
nem publicação de Release**, mesmo por execução manual. O upload de uma base de
resultados noutro workflow não foi alterado: não publica aplicações Android.
Não foram alterados cPanel, dados de produção, main ou Google Play.

## Medição final e auditoria binária

O build final cresceu **131 072 bytes (128 KiB), +0,413087%**: de 31,729912
para **31,860984 MB**. Não houve entradas ZIP acrescentadas ou removidas.
`libapp.so` passou de 6 554 544 para 6 685 616 bytes; a diferença de código
Dart AOT é 131 072 bytes. As outras três bibliotecas nativas permanecem iguais
por SHA-256: `libflutter.so`, `libdartjni.so`, `libmlkit_google_ocr_pipeline.so`.
Também mudam o bytecode Kotlin (`classes.dex`) e os perfis dexopt; o custo
líquido do APK inclui compressão e alinhamento e não se obtém somando só os
payloads descomprimidos.

O grafo Maven release foi novamente resolvido e comparado: **idêntico** ao da
referência. Os manifests/lockfiles/Gradle comparados são idênticos por conteúdo.
Os 1 486 803 bytes de modelos ML Kit são idênticos por SHA-256. Sem novos modelos,
sem Tesseract, sem recursos de fotografias/testes, sem ABIs adicionais e sem
entradas ZIP duplicadas. Não há impacto individual de remoções para apresentar
nesta continuação: nenhuma dependência nova foi acrescentada ou removida.

O certificado local de teste é o mesmo do APK anterior e o identificador
`a459865` foi encontrado no AOT, confirmando que o ficheiro inspecionado não é
um build antigo. O APK final fica apenas no diretório interno de verificação;
não foi distribuído. O APK anterior mantém o SHA-256
`0796e10b8eaaa3e196de9c06c95242f7e0da8adb2b4eca75c57ba6aa76f932fa`.

[Estado e comparação estruturada](validation/2026-10-17-cell-recovery-status.json)
e [verificação binária](validation/2026-10-17-cell-apk-verification.json).
Esses ficheiros são relatórios; não contêm o APK nem fotografias.

## Commits de implementação

| Commit | Alteração |
|---|---|
| `1fa87c9` | Suspende upload automático de APK |
| `8a6a946` | Geometria e agrupamento dos algarismos em colunas |
| `8c4f85d` | Consenso por aposta/tipo/célula |
| `3d15819` | Verificação de E e recuperação seletiva por célula |
| `b01c12a` | Projeção dos recortes existentes e confirmação de ambiguidades |
| `47cbc3b` | Descodificador regional, limpeza e tempos/diagnóstico schema 2 |
| `444336e` | Rejeita orientação invertida e prioriza rotação corretiva |
| `a459865` | Preserva campos iniciais quando a grelha é insuficiente |

O histórico anterior foi conservado, sem reset, force push, recriação de branch
ou ambiente. A entrega dos commits usa a branch de desenvolvimento por push
normal. A documentação é um commit separado posterior ao código compilado.
