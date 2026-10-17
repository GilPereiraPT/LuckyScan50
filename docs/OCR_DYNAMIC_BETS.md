# Contagem dinâmica de apostas — 17/10/2026

O total deixa de depender de cinco apostas: o plano geométrico usa os identificadores
impressos da coluna N e a sua sequência. Foram preservados Google ML Kit Latin,
dependências, API e proteção de edições manuais. Não há publicação de APK.

## Deteção e segmentação

1. A imagem continua normalizada por EXIF e pela orientação OCR existente. Mesmo
   uma primeira leitura sintaticamente completa passa agora pela análise estrutural.
2. O backend nativo já existente disponibiliza luminância reduzida, com o lado
   maior até 1024 px, usando `BitmapFactory` e `ByteArray`. Estes pixels ficam no
   dispositivo; não entram no relatório, na API ou nos logs.
3. `receipt_rules.dart` procura linhas contínuas/tracejadas nas colunas observadas,
   compensando inclinação até 15°. Exige cobertura distribuída por 12 segmentos,
   papel claro acima/abaixo e pequena espessura. Não usa algarismos como separadores;
   os testes excluem um código de barras denso. As linhas anterior/posterior à zona
   de apostas fornecem limites visuais; sem separadores fiáveis, mantém as âncoras
   OCR e os limites estruturais de texto, sem inventar linhas a partir de pixels.
4. `planBetCrops` agrupa N numerados ou provisórios numa coluna coerente, aceita
   identificadores de dois algarismos e delimita o fim com o separador ou texto de
   rodapé (`TOTAL`, Euromilhões com M1lhão, etc.). Números isolados, montantes,
   códigos e elementos N depois desse limite não criam apostas.
5. O total visual corresponde ao maior identificador aceite na sequência. Lacunas
   geram posições pendentes; não deslocam os identificadores seguintes. Um salto
   incompatível com identificadores posteriores fica assinalado e não aumenta o
   total automaticamente. Uma linha sem identificador mantém associação provisória
   e exige confirmação, mesmo que os sete valores tenham sido lidos.
6. A distância por aposta usa a diferença entre identificadores: entre N1 e N3,
   por exemplo, o intervalo visual é dividido por dois para delimitar os recortes,
   sem criar valores ou um recorte sem âncora para N2. Isto impede que N1 absorva
   os números ou as estrelas da aposta seguinte.
7. Cada aposta requer cinco números distintos 1–50 e duas estrelas distintas
   1–12. A grelha N/E e os recortes adaptam-se ao total observado. O orçamento de
   células passa de 40 fixas para até 15 passagens por linha observada (sete
   células com eventual repetição e uma sonda E), preservando o salto de células
   já reconhecidas. O limite de segurança preexistente de **20 apostas OCR** é
   partilhado pelo parser e segmentação; índices superiores geram aviso. Isto não
   constitui validação de um limite oficial de todos os tipos de talão.

O cabeçalho explícito continua útil no fallback textual, incluindo placeholders
quando faltam observações. Quando a estrutura visual fornece uma contagem diferente,
prevalece esta e há aviso; não se criam linhas apenas para satisfazer um cabeçalho
OCR possivelmente errado. Sem evidência suficiente não se afirma ter recuperado
um total exato. Uma aposta inteiramente invisível no fim e sem marcador/cabeçalho
legível continua a exigir verificação manual.

## Formulário e relatório

`ScannedReceipt.lines` continua a representar apenas apostas completas para os
consumidores existentes. O preenchimento do formulário usa agora `formLines`, com
uma linha por posição: campos pendentes aparecem como `?`, em vez de eliminar essa
linha e deslocar as seguintes. Partes completas sem conflito podem ser mantidas;
valores parciais sem posição segura permanecem no diagnóstico. O formulário exige
substituir os `?` antes de guardar. A regra que protege texto introduzido pelo
utilizador, incluindo durante a leitura, mantém-se.

O relatório exportado acrescenta `detectedBetCount`, `missingIdentifiers`,
`headerRule`, `footerRule` e os limites/identificadores dos recortes. Regista também
`ruleDetection` nos tempos e o número de separadores. Falhas de raster têm indicador
`ruleDetectionUnavailable` e mantêm o fallback OCR. Não exporta a luminância ou fotos.

## Verificação executada

- `flutter analyze --no-pub`: sem problemas.
- `flutter test --no-pub --reporter expanded`: **83 testes passam**, incluindo
  regressões anteriores e 17 casos dinâmicos. Cobrem 1, 2, 5, 12 e 20 apostas,
  lacunas 2/10, identificadores de dois algarismos, identificador errado intermédio,
  N sem número, E em falta, rodapés com algarismos/N, contagem textual contraditória,
  preenchimento sem deslocar posições e mais de 40 leituras em 12 apostas.
- Separadores testados com raster sintético tracejado, horizontal e inclinado,
  incluindo rejeição de um código de barras. Não são fotografias reais.
- Mantidos os testes com a geometria real de
  `receipt_1792267583612_geometry.json`, incluindo as cinco sondas E e a recuperação
  anterior de observações válidas.
- `./gradlew --offline :app:compileReleaseKotlin -Ptarget-platform=android-arm64
  -Ptarget=lib/main.dart`: **BUILD SUCCESSFUL**, 52 s. Compila o código nativo e
  dependências necessárias, sem executar a tarefa de empacotar/publicar APK.
- `git diff --check`: sem erros. API, `pubspec.yaml`, lock e workflows inalterados.

Não foi executado OCR real num dispositivo Android nesta tarefa. Estes resultados
não demonstram que todas as fotografias ou o talão anterior já são integralmente
reconhecidos. O tempo adicional da análise de luminância no Android e a leitura dos
separadores nas fotografias reais continuam por medir; os tempos estão instrumentados.
Não houve alteração de versão, publicação de APK ou mudança de API/produção.
