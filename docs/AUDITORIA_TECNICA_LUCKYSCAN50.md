# Auditoria técnica integral do LuckyScan50

Data: 17/10/2026. Branch de trabalho: `codex/luckyscan50-android-wallet`. Âmbito: aplicação Android, OCR, dados locais, backend de referência/produção, CI e recuperação Git. Sem merge para `main`, deploy cPanel, migração de produção ou publicação de versão definitiva.

## 1. Resumo executivo

O defeito não pode ser atribuído simplesmente ao ML Kit. Foram demonstradas perdas **de interpretação**, mesmo com caracteres corretos: o parser parava no cabeçalho «EUROMILHÕES COM M1LHÃO», não separava `N … E …` na mesma linha e só procurava o euro antes do valor. Os três testes de regressão iniciais falharam no estado recebido e passaram após as correções. Os 12 testes Flutter anteriores passavam sem testar o parser.

Foram implementados parser independente do motor, reconstrução por coordenadas com compensação de inclinação observada, preservação de apostas parciais, metadados explícitos, integração com os controladores e proteção de edições manuais. A transcrição fornecida pelo utilizador recupera as cinco apostas esperadas nos testes. Isso demonstra interpretação e preenchimento, **não precisão OCR das fotografias**.

As fotografias vertical/rodada de 09/10/2026 e os binários originais do logótipo/hero não foram encontrados no checkout, anexos ou diretórios partilhados inspecionados. É obrigatório obtê-los para fechar a aceitação real. Não foram substituídos por imagens artificiais.

## 2. Recuperação e arquitetura atual

O checkout local começou em `cb6a011`, com bundle original íntegro e sem alterações por guardar. O remoto estava em `41daded`, contendo sucessivas alterações de OCR posteriores. A `main` remota estava em `836dcab`. Os commits locais `8c9b80f`, `2575399` e `cb6a011` não eram ancestrais do remoto inicial. Uma branch de preservação `recovery/pre-audit-cb6a011` e um segundo bundle completo `/workspace/LuckyScan50-pre-audit.bundle` foram criados antes da conciliação.

O commit de conciliação `b015a0a` preservou ambos os históricos sem conflitos; foi publicado por push normal. Foi verificado que os três commits recuperados continuam ancestrais de HEAD. Nenhum reset, rebase destrutivo ou push forçado foi usado.

```text
Câmara / galeria (image_picker)
  → InputImage.fromFilePath / ML Kit nativo (Latin)
  → receipt_scanner.dart: tempos e erro por etapa
  → receipt_ocr.dart: adaptação de elementos / bounding boxes / corner points
  → receipt_parser.dart: reconstrução, metadados, apostas e incerteza
  → receipt_autofill.dart: política de transferência para campos
  → AddReceipt: confirmação humana / guardas de completude
  → WalletStore: SQLite local + histórico JSON de alterações
  → ResultsClient: consulta pública, paginação e cache
  → verify / finances: cálculo local em cêntimos
```

`main.dart` continua a concentrar ecrãs, exportação, preferências e formulário; a dimensão superior a mil linhas dificulta testes e manutenção. A separação do scanner/parser/autofill reduz o acoplamento crítico, mas não completa a modularização da UI. `ticket_readers/ticket_reader.dart` mantém modelos paralelos (`TicketLine`, `ParsedTicket`) e uma interface sem implementação/uso no fluxo atual; não foram removidos para evitar eliminar contratos sem análise de consumidores.

Backend principal: Python 3.12 nativo WSGI/Passenger; TypeScript permanece como referência. A presente auditoria não altera a API instalada nem os dados do alojamento.

## 3. Inventário de funcionalidades

«Funcional» significa demonstrado nos testes indicados, não aprovação integral em Android real. «Parcialmente funcional» identifica limites concretos. «Não verificada» significa ausência de evidência suficiente.

| Funcionalidade | Classificação | Evidência e limite |
| --- | --- | --- |
| Entrada manual e validação de chaves | Funcional | Testes de domínio, formulário e persistência; ensaio humano em aparelho pendente |
| Consulta/pesquisa de recibos e navegação | Parcialmente funcional | Ecrãs e teste de navegação; procura por código/concurso, sem cobertura de todos os filtros em aparelho |
| Persistência SQLite | Funcional | Base SQLite real em testes FFI, transações, restauro por ID |
| Câmara/galeria Android | Não verificada | Integração compilada; sem aparelho/fotografias para ensaio nativo |
| Reconhecimento ML Kit das fotos de referência | Não verificada | Faltam fotos e execução Android; testes não chamam motor nativo |
| Interpretação N/E e cinco apostas fornecidas | Funcional | Testes sobre transcrição e observações geométricas controladas |
| Preenchimento automático | Parcialmente funcional | Testes dos controladores reais e preservação de edições; entrada nativa não validada |
| Leitura incompleta 3/5 | Funcional | Preserva 3 apostas completas e slots 4/5; impede gravação sem corrigir contagem/campos |
| Orientação EXIF | Parcialmente funcional | Delegada ao SDK nativo; sem teste das imagens reais |
| Rotação automática de pixels 90/180/270° | Não implementada | Não há detector/transformação própria |
| Compensação geométrica de inclinação | Parcialmente funcional | Teste com tokens inclinados 10°; limitada a ângulos observados até 20°, sem ensaio fotográfico |
| Recorte/perspetiva/binarização | Não implementada | Não acrescentados sem conjunto de comparação real |
| Deteção textual de M1lhão | Funcional | Testes; não inferida pelo preço ou apenas pelo sufixo `M1L` |
| Captura adicional M1lhão | Parcialmente funcional | Fotografar/importar/adiar; códigos explicitamente rotulados; imagem secundária ainda não persistida como anexo autónomo |
| Verificação Euromilhões | Parcialmente funcional | Domínio e cache; falta matriz completa de prémios em integração Android |
| Verificação M1lhão | Parcialmente funcional | Comparação literal de códigos e prémio conhecido; associação de vários códigos a vários concursos ainda é cartesiana |
| Prémios recebidos | Parcialmente funcional | Valor recebido persistido; não reconcilia cada pagamento com uma linha/concurso |
| Duplicados | Parcialmente funcional | Aviso por código de recibo, rejeição de códigos M1lhão repetidos; sem hash de imagem |
| Finanças | Parcialmente funcional | Custo único/recibo, cêntimos e saldos testados; sem histórico financeiro completo por período |
| Estatísticas | Parcialmente funcional | Frequências sobre concursos em cache; não são histórico integral nem previsões |
| Atualização/offline | Parcialmente funcional | Cache preservada em erro, paginação quando suportada, atualização manual/retoma; sem execução de fundo |
| Backup/restauro | Parcialmente funcional | AES-GCM, palavra-passe errada/corrupção e imagens testados; não inclui histórico de alterações/cache, nem comparação entre aparelhos |
| Identidade visual original | Não implementada | Ícone Flutter padrão; hero textual/ícone genérico, originais ausentes |
| Responsividade | Não verificada | Larguras máximas e listas; falta matriz de dispositivos, orientação e fontes grandes |
| Biometria/notificações/prazos regulamentares | Não implementada | Não acrescentados nesta auditoria |
| APK debug ARM64 | Parcialmente funcional | Compilação e integridade aprovadas; instalação/execução em aparelho por verificar |
| AAB e assinatura de produção | Não verificada | Nenhum AAB produzido nem keystore de produção disponibilizado |

## 4. Problemas confirmados e matriz de correções

P1 = pode perder/atribuir incorretamente dados; P2 = limita operação/diagnóstico; P3 = manutenção/apresentação.

| ID / gravidade | Componente / evidência | Causa demonstrada | Correção e validação |
| --- | --- | --- | --- |
| OCR-01 / P1 | Antigo `_parseBetLines`: `if (line.contains('EUROMILH') && line.contains('M1LH')) break` | Cabeçalho válido interrompia a leitura antes das apostas | Removida terminação pelo cabeçalho; regressão com cabeçalho e chave passa |
| OCR-02 / P1 | Antigo `_parseBetLines`, ramo `nMatch` | `E` e estrelas eram passados ao parser numérico como parte dos cinco números | Segmentação explícita N/E na mesma linha e em linhas separadas; testes passam |
| OCR-03 / P2 | Antiga expressão `€\s*(...)` | `TOTAL 11,00 €` não era extraído | TOTAL explícito com euro antes/depois; múltiplos totais exigem confirmação |
| OCR-04 / P1 | Antigo `_parseNumericTokens` | Substituições O/Q/D→0, I/L→1, S→5, B→8 sem marcar incerteza | Não se inventam dígitos; tokens incertos e valores parciais permanecem visíveis |
| OCR-05 / P1 | `AddReceipt.scan`: atribuição incondicional de `lines.text` | Nova leitura podia apagar correções manuais, inclusive durante espera pelo OCR | Política por campo e snapshot no início da operação; testes puros e widget com Future pendente |
| OCR-06 / P1 | `save` não comparava apostas válidas com contagem reconhecida | Três apostas podiam ser gravadas como recibo de cinco | Contagem esperada editável, slots incompletos e guarda antes da persistência; widget demonstra bloqueio |
| OCR-07 / P2 | Parser antigo não extraía data/concurso | Controladores não tinham valores para preencher, independentemente da qualidade do OCR | Data estrita e concurso explícito; ano apenas com evidência, sem usar data atual |
| OCR-08 / P1 | Escolha antiga por maior quantidade de linhas | Duas interpretações válidas contraditórias eram resolvidas pela contagem | Geometria prioritária; conflito pelo índice marca aposta incerta; regressão passa |
| OCR-09 / P2 | `scanMilhao` antigo: picker antes do `try` | Exceções de seleção escapavam ao tratamento; falhas noutros passos eram genéricas | Serviço único com etapa/tipo de erro e libertação do recognizer; feedback local sem despejar dados em logs |
| ABI-01 / P2 | APK inicial continha `armeabi-v7a` e `x86_64` de plugins sem engine correspondente | Filtros de ABI de Flutter 3.35 são aplicados a build types, não apenas defaultConfig | Filtro no build type para pedido ARM64; outros alvos e split-per-ABI mantêm configuração própria; ZIP real verificado |
| CI-01 / P2 | Workflow recebido gerava release de testes com chave debug e upload permissivo | Não havia verificação explícita de conteúdo, assinatura, checksum ou 16 KB | CI de debug com análise, 31 testes, verificador do APK e erro se artefacto ausente |
| VIS-01 / P3 | `mipmap-xxxhdpi/ic_launcher.png`, inspecionado visualmente | É o símbolo padrão do Flutter; não o logótipo LuckyScan50 | Dependência registada, sem substituição silenciosa |
| ARC-01 / P2 | `main.dart`, `ticket_reader.dart` | UI monolítica e modelos paralelos sem uso no scanner | Extraídos scanner/parser/autofill; restante modularização recomendada |

## 5. Hipóteses ainda não demonstradas

1. Qualidade térmica, reflexos, desfoque e redução para `maxWidth:3000` podem eliminar caracteres pequenos. Faltam originais e pares antes/depois para medir.
2. Rotação sem EXIF, etiquetas EXIF incorretas ou perspetiva podem continuar a falhar. Não há prova de que o ML Kit esteja a receber os pixels rodados incorretamente neste caso.
3. Agrupamento por altura mediana e coordenadas projetadas pode misturar linhas muito próximas ou colunas de blocos diferentes. Testes sintéticos não cobrem a distribuição de erros real.
4. Podem estar instalados APKs anteriores. Foi acrescentada versão `0.2.1+3` e SHA de build em Sobre/Definições; não foi possível inspecionar o APK instalado no aparelho do utilizador.
5. Contar apostas ou detetar formato válido não prova que cada dígito foi reconhecido corretamente: uma substituição entre dois números válidos pode escapar à validação estrutural. A confirmação humana continua obrigatória.

## 6. Evidências e localização

- `app/lib/data/receipt_scanner.dart`: captura, ML Kit Latin, tempos OCR/parser e `ReceiptScanFailure(stage,errorType)`.
- `app/lib/domain/receipt_ocr.dart`: adapta `TextElement.boundingBox`, `cornerPoints` e ângulo nativo; preserva linhas do SDK.
- `app/lib/domain/receipt_parser.dart`: `reconstructRows`, `_parseBets`, `parseReceiptObservations`, metadados e conflitos.
- `app/lib/domain/receipt_autofill.dart`: política testável de substituição de campos.
- `app/lib/main.dart`: `_AddReceiptState.scan`, diagnóstico local, campos e `save`.
- `app/test/receipt_ocr_test.dart`: 16 testes do parser/adaptador/autofill, incluindo os três que falharam no estado inicial.
- `app/test/receipt_autofill_widget_test.dart`: 3 testes da UI com serviço de reconhecimento substituído por dados controlados; não executam ML Kit nativo.
- `tools/verify_apk.py`: ZIP/CRC, manifesto/dex, ARM64 real, ELF LOAD, assinatura, alinhamento ZIP e SHA-256.
- `/tmp/luckyscan-ocr-before.log`: três falhas reproduzidas antes da correção; logs de comandos desta sessão não são dados de produção nem fixtures de imagem.

## 7. Diagnóstico detalhado do pipeline OCR

| Etapa | Comportamento observado no código | Diagnóstico/limite |
| --- | --- | --- |
| Fotografia/galeria | image_picker, largura máxima 3000 | Falha de seleção agora tem etapa identificável; recuperação de processo Android morto (`retrieveLostData`) ainda ausente |
| Orientação | image_picker Android copia TAG_ORIENTATION; InputImageConverter chama `InputImage.fromFilePath` nativo | Delegação confirmada no código dos plugins; efeito nas duas fotos reais não medido |
| Pré-processamento | Resize do picker; sem crop/perspetiva/filtros próprios | Não foram acrescentados filtros sem benchmark |
| Reconhecimento | TextRecognizer Latin; texto, blocos, linhas, elementos, caixas e cantos | Motor nativo não executado em testes unitários; caracteres reais desconhecidos |
| Coordenadas | Elementos com centro, altura e ângulo dos cantos | Visíveis no diagnóstico local, sem envio a API ou logging global |
| Reconstrução | Ordenação física após projeção por ângulo mediano; tolerância relativa à altura mediana | Testes com ordem baralhada e 10°; não corrige pixels rodados 90° |
| Parser | Âncoras N/E, 5 números e 2 estrelas, metadados explícitos | Falhas iniciais demonstradas mesmo com texto correto |
| Validação | Intervalos, unicidade, contagem esperada, conflitos, tokens incertos | Validação estrutural não equivale a verdade do bilhete |
| Formulário | Transferência por campo, proteção de edições e confirmação humana | Testes exercitam controladores do ecrã real; nativo substituído no teste |

O diagnóstico local mostra caracteres/tokens, tempos medidos dessa leitura, estratégia, inclinação, coordenadas, linhas reconstruídas, apostas completas, slots incompletos e avisos. Os tempos de testes simulados não são publicados como latência OCR.

## 8. Comparação ML Kit, Tesseract e híbrido

| Aspeto | ML Kit atual | Tesseract | Híbrido |
| --- | --- | --- | --- |
| Integração | Plugin `google_mlkit_text_recognition` 0.15.1, ponte comunitária para SDK Google | Candidato inspecionado: `flutter_tesseract_ocr` 0.4.31, publicado em 01/06/2026 | Manter primeiro motor e acrescentar segundo apenas em regiões incertas |
| Offline | Reconhecedor Latin incluído nas dependências Android | Exige modelos traineddata locais; `eng`/`osd` apenas no Tesseract desktop instalado | Offline se ambos os modelos forem empacotados |
| Geometria | Blocos, linhas, elementos, caixas, cantos e ângulo | API nativa oferece caixas/hOCR/TSV; wrapper inspecionado oferece texto/hOCR | Adaptar ambos a `ReceiptToken`; não partilhar heurísticas específicas do SDK |
| Segmentação | Determinada pelo SDK | PSM configurável: comparar 6 para região, 7 para linha e 11 para texto esparso; whitelist só numa região numérica | Recortar N/E e não aplicar whitelist numérica aos códigos alfanuméricos |
| Manutenção | Versão fixada em lock; 49 dependências têm versões posteriores incompatíveis com os constraints | Data de publicação recente não prova manutenção; fonte tem AGP 7.1.2, jcenter e AAR local | Mais código, modelos, consumo e superfície de manutenção |
| ARM64 / 16 KB | Inspeção das quatro bibliotecas ARM64 do APK encontrou LOAD de 16/64 KB | AAR inspecionado inclui ARM64; os quatro `.so` ARM64 têm LOAD de 16 KB; não foi montado um APK Tesseract | Necessário verificar ELF **e** ZIP da combinação final |
| Impacto | Tamanho real do APK de auditoria na verificação anexa; debug não estima release | AAR distribuído: 14 082 032 bytes comprimidos para várias ABIs; ARM64: 8 318 200 bytes nativos sem compressão, mais traineddata. Não é um delta medido de APK | Pelo menos o segundo motor/modelos, sem estimativa numérica inventada |
| Recibos térmicos | Qualidade real por medir | Qualidade real por medir; não há fundamento para afirmar superioridade | Pode recuperar desacordos, mas precisa de rejeitar conflitos em vez de escolher arbitrariamente |

O arquivo do candidato Tesseract foi descarregado do pub.dev e o SHA-256 verificado antes da inspeção; **não foi adicionado à aplicação**. Há Tesseract 5.5.0 no executor, com `eng` e `osd`, mas não há fotos para o executar. Não há Android/emulador a executar ML Kit aqui.

### Métricas exigidas e resultado disponível

| Métrica nas fotos reais | ML Kit | Tesseract | Híbrido |
| --- | --- | --- | --- |
| Precisão dos 25 números / 10 estrelas | Não medida | Não medida | Não medida |
| Apostas completas corretas / 5 | Não medida | Não medida | Não medida |
| Latência p50/p95 no mesmo Android | Não medida | Não medida | Não medida |
| Pico de memória e variação de APK release | Não medidos | Não medidos | Não medidos |

Protocolo: mesmas fotos originais, mesmo dispositivo/build, aquecimento separado, pelo menos 20 repetições por variante; alinhar previsões pela aposta impressa, contar ausentes/errados sem omitir falhas, guardar saída estruturada anonimizada com coordenadas e versão do motor. Comparar original, EXIF, rotações, deskew, crop, perspetiva, contraste, binarização e ampliação **um fator de cada vez**. Só ativar transformação que melhore métricas sem inventar dígitos. Os testes textuais atuais não substituem estas métricas.

## 9. Preenchimento automático e caso obrigatório

A transcrição de 09/10/2026 nos testes contém as cinco chaves fornecidas, concurso 081, total 11,00 € e os dois identificadores. A data ISO candidata é `2026-10-09`; o ano de `081/2026` vem da data explicitamente presente, nunca do relógio do telefone. Datas impossíveis, várias datas, vários totais ou concursos sem ano suficiente não são resolvidos por adivinhação.

Cada aposta parcial guarda índice, números/estrelas reconhecidos e motivos. Apenas apostas estruturalmente completas entram no campo de chaves. A UI lista as restantes e exige completar/corrigir a contagem antes de guardar. Os campos permanecem editáveis. Uma segunda leitura pode atualizar valores previamente preenchidos por OCR, mas não edições manuais nem alterações feitas enquanto o scanner estava à espera.

A data é agora um campo opcional do JSON do recibo; leitura de registos antigos continua a usar `null`, sem migração destrutiva de SQLite. Confirmação humana da data/código/valor permanece necessária. A interpretação de todos os formatos online e múltiplas datas não está concluída.

## 10. Euromilhões e M1lhão

- A indicação de M1lhão vem de texto explícito, não de uma diferença de preços.
- `782-02213749-M1L` é identificador de recibo, nunca código `ABC 12345`.
- Só um código com rótulo explícito «CÓDIGO M1LHÃO» é candidato a preenchimento automático; não se pesquisam quaisquer três letras e cinco algarismos na imagem.
- A UI mostra «Fotografe o boletim do M1lhão»: câmara, galeria e adiar. Não deriva o concurso M1lhão a partir do concurso Euromilhões.
- Os códigos são confirmados/editáveis e não podem repetir-se com/sem espaço no mesmo recibo.
- A despesa continua registada uma vez por recibo; o total 11,00 € do caso é preservado sem recalcular preços não verificados.
- Não foram confirmadas regras oficiais de preços por data/modalidade. A aplicação não apresenta uma discrepância monetária como prova de M1lhão.
- Limites: foto secundária ainda é transitória; modelo não associa individualmente cada código ao concurso correspondente quando há múltiplos códigos/concursos. Não declarar o fluxo M1lhão integralmente concluído.

## 11. Auditoria funcional e de dados

`WalletStore` tem versão 1, tabelas receipts/results/history/settings e escritas transacionais. Códigos iguais geram aviso, enquanto números iguais em recibos genuínos continuam permitidos. A receção de prémios usa cêntimos inteiros; o total pago é agregado por recibo, não por concurso. Um concurso futuro/ausente mantém estado pendente. Prémio desconhecido não é substituído por zero.

`ResultsClient` consulta ambos os jogos e aplica paginação quando há metadados. A API 0.1.1 anteriormente observada não fornece paginação; o cliente para na primeira página sem inventar histórico. A cache permite consulta offline e mantém resultados anteriores se a sincronização falhar. Não há sincronização Android em segundo plano nem tratamento de tombstones/reset do cursor após restauro do servidor.

O backup usa AES-256-GCM, salt/nonce aleatórios e PBKDF2-HMAC-SHA256 (210000 iterações). Há testes de palavra-passe errada, corrupção e restauro das imagens em novo diretório. Restauro agrega por ID, não sobrescreve recibos existentes. Histórico de alterações e cache não fazem parte do backup. Um restauro de ID já existente pode deixar uma imagem restaurada órfã; testar e corrigir numa fase própria. A dimensão do backup é carregada em memória e ainda não tem limites explícitos.

Não há exportação XLSX, reconciliação financeira por escalão/pagamento, regras de caducidade versionadas ou biometria. A existência de classes ou ecrãs não foi usada como prova de operação nativa.

## 12. Identidade visual

O ícone xxxhdpi foi aberto e é o símbolo Flutter padrão. Existem mipmaps para várias densidades, mas não foram encontrados recursos adaptativos próprios (`mipmap-anydpi-v26`), ficheiros originais de logótipo/hero ou assets declarados para eles no pubspec. A página Sobre apresenta composição textual e ícone Material; o ecrã inicial tem cartão azul/dourado, sem hero original.

Há launch_background e estilos Android gerados pelo Flutter, não uma identidade de abertura personalizada. Nenhum recurso genérico foi agora introduzido para substituir os originais. A inclusão/aspeto dos recursos próprios e a sua apresentação em aparelhos são dependências pendentes.

## 13. GitHub Actions, compilação e assinatura

O histórico Git recebido inclui commits a reparar regex truncadas, ciclos e um `\\n` literal no parser: `8bf54d7`, `c4e1d30`, `03d0acf`, `24747af`, `41daded`. Isto é evidência do histórico do código; **não prova os resultados dos runs**. `gh run list` devolveu `Forbidden` no endpoint de API nesta sessão; a página web também não permitiu consultar os runs. Não foi pedido token nem contornado o proxy.

O workflow atual é acionável manualmente e por push na branch de desenvolvimento. Conserva Ubuntu 24.04, Java 17 e Flutter 3.35.7. Executa lockfile, formato, analisador e todos os testes antes do build debug ARM64. O upload exige ficheiro existente e inclui SHA-256 e relatório de verificação. Não faz deploy, merge, tag ou release definitiva.

`verify_apk.py` abre o ZIP real e verifica CRC, manifesto/dex, arquitetura AArch64 dos ELF, presença do engine Flutter, ausência de outras ABIs, alinhamento LOAD mínimo 16 KB, `apksigner verify`, `zipalign -P 16` e package ID. Uma falha bloqueia o upload. Alinhamento não equivale a execução em dispositivo 16 KB: essa prova continua pendente.

Não foi substituída nenhuma chave de assinatura existente. O hash do debug.keystore local é comparado antes/depois do build. A configuração release recebida usa chave debug e minificação para testes; não foi convertida em assinatura de produção. A CI gera/usa debug key no runner: um certificado efémero diferente pode impedir atualização de um APK anterior. Não recomendar desinstalação sem backup dos dados. A continuidade de assinatura com o APK do utilizador exige comparar certificados do ficheiro instalado/original.

As 49 atualizações de dependências indicadas pelo pub não são 49 vulnerabilidades comprovadas. Não foi feito upgrade indiscriminado de Flutter, ML Kit ou plugins durante a investigação. R8 é irrelevante para o APK debug; regras `dontwarn` de idiomas opcionais em release não demonstram, por si, funcionamento de qualquer motor.

## 14. Riscos e correções recomendadas

| Prioridade | Risco restante | Ação verificável |
| --- | --- | --- |
| P1 | Validade estrutural pode aceitar um dígito real mal reconhecido como outro dígito válido | Benchmark com fotos reais, comparação por célula e confirmação humana |
| P1 | Vários códigos M1lhão/concursos sem associação individual | Modelo explícito por participação, migração e teste de prémios sem produto cartesiano |
| P1 | APK de assinatura diferente pode exigir instalação incompatível | Comparar certificados, preservar chave existente e backup antes de qualquer reinstalação |
| P2 | Processo Android morto durante a câmara perde resultado temporário | `retrieveLostData` e rascunho persistente, com testes de ciclo de vida |
| P2 | Orientação/perspetiva/fotos térmicas sem prova real | Conjunto vertical/90° e saídas ML Kit com coordenadas antes de escolher algoritmo |
| P2 | Backup grande e anexos secundários transitórios | Limites/memória, transações de anexos, restauro sem órfãos e teste entre aparelhos |
| P2 | UI extensa e abstrações paralelas | Separar widgets/repositórios, eliminar redundância só após testes de consumidores |
| P3 | Identidade genérica | Integrar binários originais, ícone adaptativo e verificar no APK/dispositivo |

## 15. Plano faseado

1. **Diagnóstico e instrumentação — implementado no código/testes:** scanner por etapas, coordenadas e reconstrução local, causas do parser reproduzidas. Falta captura instrumentada das imagens reais.
2. **Recuperação OCR — parcial:** N/E, metadados, conflitos e deskew geométrico testados. Rotação de pixels, crop/perspetiva e comparação de motores dependem das fotos e Android real.
3. **Preenchimento — implementado e testado com serviço substituído:** controladores, edição e contagem. Validar ponta a ponta com ML Kit real antes de afirmar sucesso do problema original.
4. **M1lhão — parcial:** deteção/captura/adiar/código explícito; falta anexo persistente e associação por participação.
5. **Identidade — pendente de originais:** não bloqueia correção do parser, mas impede declarar identidade concluída.
6. **Qualidade/distribuição — automatizada em código:** testes e verificação de APK; estado efetivo do build nesta sessão na secção 16. Não publicar release definitiva sem aprovação.

## 16. Resultados efetivamente executados

- Estado conciliado antes da correção: `flutter analyze` sem problemas, **12 testes Flutter passaram**; nenhum cobria receipt_ocr.
- Regressões iniciais: **3 testes falharam**, demonstrando cabeçalho, linha N/E e total com euro posterior.
- Estado corrigido: `flutter analyze` sem problemas; **31 testes Flutter passaram** (12 anteriores, 16 de parser/adaptador/autofill e 3 widgets do formulário). Não são testes OCR nativos com fotos reais.
- Python: **13 testes passaram**, sem alteração de dados de produção.
- Backend TypeScript: **10 testes passaram**, `npm run lint` e `npm run build` concluídos.
- Tesseract desktop: `--version` confirmou 5.5.0; `--list-langs` confirmou eng/osd. Não houve execução de reconhecimento sobre fotos porque estas faltam.
- Primeiro APK debug compilou. O verificador rejeitou as bibliotecas de ABIs adicionais; o filtro foi corrigido no nível build type após inspeção do plugin Flutter 3.35. O gate completo da compilação final passou; dados do artefacto abaixo.

### APK de auditoria produzido e verificado

- Código compilado: `75e248f`; versão Android `0.2.1`, código 3; identidade visível `0.2.1+3` e SHA de build.
- Artefacto local: `/workspace/artifacts/LuckyScan50-audit-0.2.1-arm64.apk`.
- Tamanho: **96 951 732 bytes**, build debug (não comparável diretamente a release).
- SHA-256: `bdbc2bbf32d9485f7069c347bd9772802cbbb947e9cdb82ef678f00be5591176`.
- Certificado debug SHA-256: `0695a638827b0ffa1725698204080edd8b76d65971cbe30ff2d5219d2d0ee860`.
- Assinatura, ZIP/CRC, package ID, 4 bibliotecas AArch64, ELF LOAD ≥16 KB e ZIP 16 KB: **aprovados**.
- O hash do keystore local manteve-se igual após a compilação. Nenhuma chave foi substituída.
- Relatório preservado no repositório: `docs/validation/2026-10-17-apk-verification.json`.
- OCR das fotografias reais: **não validado**. Instalação em dispositivo, continuidade de certificado com APK anterior e execução em sistema 16 KB: **não verificadas**.
- Não há ligação confirmada para artefacto de um run GitHub: a consulta de runs continua indisponível nesta sessão; o APK disponível é o compilado e verificado localmente.

Comandos reproduzíveis, em `app/`:

```sh
flutter pub get --enforce-lockfile
dart format --output=none --set-exit-if-changed lib test
flutter analyze
flutter test --reporter expanded
flutter build apk --debug --target-platform android-arm64 --dart-define=LUCKYSCAN_BUILD_SHA="$(git rev-parse HEAD)"
python3 ../tools/verify_apk.py build/app/outputs/flutter-apk/app-debug.apk --build-tools /caminho/android-sdk/build-tools/35.0.0
```

Os testes Linux SQLite necessitam de libsqlite3; o executor usa uma ligação local para a biblioteca do sistema. O relatório `.verification.json` e o ficheiro `.apk.sha256` descrevem o artefacto, sem conter recibos ou imagens pessoais.

## 17. Limitações, dependências e recomendação para o próximo APK

Faltam as duas fotografias originais, uma saída ML Kit real e execução Android no mesmo dispositivo; logótipo/hero/ícones originais; certificado do APK já instalado; acesso à consulta dos runs remotos. Não se inventaram dados para preencher estas lacunas.

Recomenda-se um **APK debug de auditoria 0.2.1+3**, identificado pelo SHA, para recolher diagnóstico local do recibo de referência, confirmar vertical/90°, texto, coordenadas, parser e controladores. A compilação e os testes textuais não permitem anunciar o objetivo fundamental como atingido. Só depois da demonstração reproduzível nas fotos reais se deve considerar uma versão de utilização normal, mantendo confirmação humana e API de produção intacta.

## Adenda: diagnóstico real de palavras verticais e recuperação multi-pass

O diagnóstico posterior fornecido pelo utilizador revela uma falha de segmentação nativa: colunas numéricas foram reconhecidas como palavras verticais (~90°, 685–698 px), perdendo dígitos e estrelas. As correções de parser anteriores não recuperam caracteres ausentes. A continuação implementa recuperação por recortes e um teste Android real, descritos em [OCR_MULTIPASS.md](OCR_MULTIPASS.md).

As validações locais atualizadas são 44 testes Flutter e 13 Python aprovados, análise estática e compilação Kotlin/debug interna aprovadas. A aceitação das duas fotografias e da UI no Android continua não executada por falta de ficheiros e dispositivo. A publicação automática de novos APKs foi suspensa; o APK de auditoria mencionado anteriormente é anterior a esta alteração e não demonstra este novo pipeline.
