# LuckyScan50 — auditoria de dependências e APK de diagnóstico

Data: 17/10/2026. Base pedida: `df260a3`, branch
`codex/luckyscan50-android-wallet`. Comparação anterior ao multi-pass: `4df2127`.
A autorização atual permite distribuir um APK **de diagnóstico**; não constitui
validação do OCR real, aprovação de produção ou publicação na Google Play.

## Comparação controlada de tamanho

Três builds distinguem limpeza de dependências de novas capacidades de diagnóstico:

| Build ARM64 release | Bytes | MB decimais | Observação |
|---|---:|---:|---|
| Base `df260a3` | 31 730 810 | 31,730810 | Antes da limpeza |
| Apenas limpeza | 31 730 328 | 31,730328 | Sem alterações de código de produção |
| Diagnóstico com exportação | A preencher após compilação | — | Inclui exportação e identificação 0.2.2+4 |

**Efeito isolado da limpeza: −482 bytes (−0,001519%).**
Nos dois primeiros builds: Flutter 3.35.7, JDK 21.0.12.1, ARM64, release,
R8 e resource shrinking ativos, mesma chave de teste e comando:

```sh
flutter build apk --release --target-platform android-arm64 --dart-define=BUILD_SHA=df260a3
```

Esse define de comparação é idêntico nos dois builds; a identificação efetiva do
APK final usa `LUCKYSCAN_BUILD_SHA`. Não se atribui à limpeza a diferença em
relação aos APKs debug anteriores. O release já excluía os plugins Flutter de
desenvolvimento. A comparação ZIP comprova que todos os payloads executáveis,
bibliotecas e modelos ficaram **byte a byte iguais** na limpeza; saíram apenas
`assets/private_receipts/README.txt` e as entradas dos dois AssetManifests.

Inventários completos, versões de **todos** os pacotes Dart, módulos Maven
resolvidos antes/depois, tamanhos, hashes e configuração estão em
[validation/2026-10-17-dependency-cleanup.json](validation/2026-10-17-dependency-cleanup.json).
Nenhuma versão dos pacotes mantidos foi atualizada.

## O que o multi-pass acrescentou

No grafo Dart: `integration_test` (SDK), `flutter_driver` (SDK),
`fuchsia_remote_debug_protocol` (SDK), `process 5.0.4`, `sync_http 0.3.1`,
`webdriver 3.1.0`. São ferramentas de teste, sem utilização em `lib/`.

No Gradle: declaração explícita de `androidx.exifinterface:exifinterface:1.3.7`,
resolvida para **1.4.2**, já exigida pelo `image_picker_android` mantido. A
normalização EXIF de `MainActivity.kt` usa essa API diretamente; a declaração é
mantida. Não houve adição de modelos OCR, Tesseract ou bibliotecas nativas OCR.

O plugin `integration_test` acrescentava ao **debug** a infraestrutura nativa de
instrumentação. O inventário contém todos os transitivos; os módulos que saem
ou deixam de ter aquela versão são:

- `androidx.test:runner:1.2.0`, `rules:1.2.0`, `monitor:1.2.0`;
- `androidx.test.espresso:espresso-core:3.2.0`, `espresso-idling-resource:3.2.0`;
- `junit:junit:4.12`, `org.hamcrest:hamcrest-core:1.3`,
  `hamcrest-library:1.3`, `hamcrest-integration:1.3`;
- `net.sf.kxml:kxml2:2.3.0`, `com.squareup:javawriter:2.1.1`;
- `com.google.guava:guava:28.1-android`, `failureaccess:1.0.1`,
  `listenablefuture:9999.0-empty-to-avoid-conflict-with-guava`;
- `com.google.code.findbugs:jsr305:3.0.2`,
  `com.google.errorprone:error_prone_annotations:2.3.2`,
  `com.google.j2objc:j2objc-annotations:1.3`,
  `org.checkerframework:checker-compat-qual:2.5.5`,
  `org.codehaus.mojo:animal-sniffer-annotations:1.18`.

`javax.inject:javax.inject:1` também aparece no ramo de teste, mas já é exigido
por dependências de produção: fica. `listenablefuture:1.0` fica para produção;
a versão vazia usada pelo Guava de teste deixa de a substituir no debug.
O grafo Maven **release é exatamente igual** antes e depois da limpeza.

## Remoções e isolamento

Saem do grafo da aplicação os seis pacotes Dart acima e
`sqflite_common_ffi 2.3.7+1` / `sqlite3 2.9.4` (já existentes antes do multi-pass).
O SQLite Android continua a ser fornecido pelo `sqflite`, sem alteração.

O teste real de persistência não foi eliminado: `tools/run_flutter_qa.py host`
executa-o numa cópia temporária com FFI. O mesmo runner, em modo `android`,
instala `integration_test` e as fotografias **apenas na cópia temporária**.
Mantém o teste de ambas as orientações e do formulário Android. Lockfiles QA
independentes preservam as versões; os manifestos da aplicação não são trocados
nem alterados pelo runner. Ver [../qa/README.md](../qa/README.md).

A pasta de fotografias deixou de ser um asset da aplicação. O verificador do
APK rejeita imagens de teste em assets e ficheiros `.traineddata`.
`tools/compare_receipt_regions.py` continua exclusivamente desktop, fora do
manifesto Flutter e do APK. Não se integra Tesseract Android sem evidência real.

**Impacto funcional da limpeza: nenhum no código de produção.** A prova binária
acima não substitui testes Android reais, mas impede atribuir perda de funções
às remoções. Offline, SQLite, backup, importação, partilha e ML Kit mantêm-se.

## Dependências mantidas

| Dependência direta | Utilização de produção |
|---|---|
| Flutter / flutter_localizations | Interface e português |
| flutter_riverpod | Estado e providers em `main.dart` |
| go_router | Navegação em `main.dart` |
| sqflite | Persistência local em `wallet_store.dart` |
| path / path_provider | Caminhos e diretórios privados; backup e exportação |
| http | Cliente da API existente em `results_client.dart` |
| intl | Formatação monetária |
| cryptography | Backup cifrado em `backup.dart` |
| image_picker | Câmara e galeria para OCR |
| google_mlkit_text_recognition / commons | ML Kit Latin e imagens nativas |
| file_picker | Importação de backups |
| share_plus | Partilha de backup, CSV e relatório OCR |
| androidx.exifinterface | Orientação EXIF original dos recortes |

`flutter_test` / `flutter_lints` ficam para testes e análise, sem plugins Android
nem modelos adicionais. Pacotes federados para outras plataformas não criam
ABIs Android extra; não são removidos à força dos grafos dos plugins necessários.

As quatro bibliotecas ARM64 release mantidas são:

- `libapp.so`: aplicação Flutter compilada;
- `libflutter.so`: motor Flutter;
- `libdartjni.so`: JNI exigido pelo **path_provider_android de produção**;
- `libmlkit_google_ocr_pipeline.so`: motor OCR Latin offline.

A atribuição anterior de `libdartjni.so` apenas ao FFI era incompleta: o grafo
atual comprova a dependência do `path_provider_android`. Removê-la seria incorreto.
A biblioteca Vulkan observada no debug não pertence ao release e a sua ausência
não é contabilizada como efeito da limpeza.

Ficam **1 486 803 bytes descomprimidos** de recursos ML Kit: modelos Latin
`Latn_ctc`, deteção/segmentação, identificação de escrita/idioma e análise de
layout (`aksara`, `gocr`, `taser`). O modelo de deteção com "vertical" no nome
é parte do pipeline necessário, não um segundo motor. Não há recognizers
chineses, japoneses, coreanos, devanágari nem `traineddata` de Tesseract.
Mantêm-se ícones Material reduzidos, avisos de licença, manifests e perfis dexopt.
A lista exata de cada modelo/recurso, tamanho e SHA-256 está no inventário.

## Relatório OCR exportado

No ecrã de adicionar recibo, após uma leitura: **Exportar relatório OCR**.
Abre a partilha Android de um JSON. Inclui:

- texto, geometria e interpretação da primeira passagem;
- tentativas de orientação e cada recorte, escala, resultados e erros;
- apostas completas/incompletas, números, estrelas e avisos;
- valores candidatos/aceites, passagem de origem, correções e conflitos;
- tempos por passagem e total de processamento (inclui preparação e análise).

Não inclui fotografias, recortes binários, caminhos de origem ou as edições
manuais do formulário. O texto reconhecido pode conter identificadores do
recibo, conforme indicado junto ao botão. O relatório descreve observações OCR,
não certifica automaticamente a leitura. As proteções de edição manual ficam.

## Compilação, assinatura e entrega

O APK final é release otimizado **com assinatura de teste**, para instalação
lateral. A chave local mantém o certificado do APK anterior; nenhuma chave foi
substituída. Os runners GitHub usam a sua chave debug efémera, pelo que APKs de
runs diferentes podem ter assinaturas diferentes. Para atualizar uma instalação
existente é necessário o mesmo certificado; não apagar a carteira para contornar
uma incompatibilidade de assinatura.

O workflow valida análise, testes normais e FFI, compila ARM64, verifica ZIP/CRC,
assinatura, arquitetura ELF AArch64 e alinhamento ELF/ZIP de 16 KB, e guarda APK,
SHA-256 e inventário como artefacto por 14 dias. Publica apenas na branch de
desenvolvimento, em push ou `workflow_dispatch`; pull requests não distribuem.

A interface de execução manual exige o workflow na branch predefinida. Como
`main` ainda não contém este ficheiro, o push da branch de desenvolvimento é a
via disponível sem fazer merge para produção. Link do workflow:
https://github.com/GilPereiraPT/LuckyScan50/actions/workflows/ci-flutter.yml

## Validação efetiva

- `flutter analyze`: sem problemas.
- `flutter test --reporter expanded`: **45 testes aprovados**.
- `python3 tools/run_flutter_qa.py host`: **1 teste real SQLite FFI aprovado**.
- API Python, `python3 -m unittest discover -v`: **13 testes aprovados**.
- Dependências QA Android resolvidas; **não** equivale a executar esse teste.
- Compilações e verificação binária: valores da referência e limpeza acima;
  resultado final registado após a compilação.
- Fotografias reais / OCR nas duas orientações / preenchimento real Android:
  **não executados**, sem fotografias reais nem dispositivo ligado disponíveis.
  Precisão por aposta e latência real continuam **não medidas**.

A API cPanel, os dados de produção, a Google Play e `main` não foram alterados.
