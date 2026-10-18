# Recuperação OCR por múltiplas passagens — estado de engenharia

> Estado atual: recuperação por células e consolidação geométrica em
> [OCR_CELL_RECOVERY.md](OCR_CELL_RECOVERY.md). Não publicar outro APK
> automaticamente; a validação real Android continua pendente.


17/10/2026. **Não validado nas fotografias reais.** O pedido seguinte autorizou um APK de diagnóstico com exportação, sem certificar o OCR. Ver [DEPENDENCY_APK_AUDIT.md](DEPENDENCY_APK_AUDIT.md); os números debug abaixo são históricos.

## Diagnóstico de entrada e evidência

O utilizador relatou elementos verticais como `ZWZWZWZwZu`, `O000DNOOO0`, `OTOLONMONUM`, `UOrNOrOr` e `OONTODO000`, com ângulos próximos de 90° e alturas de 685–698 px. Os números finais sobrevivem, mas faltam primeiros números das apostas 2–5 e as estrelas. Isto é evidência comunicada de segmentação do motor por colunas; alterar apenas regex não recupera dígitos que o motor não devolveu.

Não foram fornecidos nesta execução os ficheiros das duas fotografias nem o dump completo com X/Y/larguras. As coordenadas dos testes novos são explicitamente controladas, não uma reconstrução inventada das coordenadas reais. Os exemplos de palavras/ângulos/alturas vêm do diagnóstico fornecido.

## Implementação

1. `scanReceiptImage` seleciona a imagem sem reduzir previamente para 3000 px. `scanReceiptFile` permite executar exatamente o mesmo processamento sobre um original no teste Android.
2. A primeira leitura ML Kit do ficheiro original é preservada: texto, elementos, caixas, ângulos e tempos, mesmo se a preparação/recuperação falhar.
3. O canal nativo `luckyscan50/receipt_crops` cria uma cópia privada PNG, sem perdas, com orientação EXIF normalizada. Não modifica o original. As coordenadas partem da orientação upright usada por `InputImage.fromFilePath`.
4. `planBetCrops` usa âncoras N/índices e grupos numéricos horizontais realmente observados. Não usa os cinco resultados conhecidos, número esperado de apostas ou contagem de caracteres verticais para inventar linhas. A contagem esperada só valida completude no fim.
5. Elementos próximos de 90° e com grande razão altura/largura são identificados como colunas problemáticas. Só os que intersectam a zona ancorada participam na extensão vertical da zona. São excluídos da reconstrução normal de palavras por linha, mas permanecem no diagnóstico.
6. Cada recorte cobre toda a largura útil até à margem direita da imagem, incluindo a área de estrelas mesmo se nenhum E/estrela foi inicialmente reconhecido. Limites verticais usam as linhas observadas e margens proporcionais à altura dos caracteres. Não há valores numéricos deduzidos do tamanho da caixa.
7. ML Kit volta a executar sobre cada linha afetada. Uma segunda tentativa a 2× só ocorre quando a primeira não resolve a linha. Sem pelo menos duas linhas localizáveis e havendo elementos verticais, há tentativas explícitas de orientação 90/270/180°, selecionadas por âncoras geométricas observadas, não pelos números esperados.
8. O parser dos recortes exige âncoras N/E. `O` pode ser convertido em `0` apenas num token de um ou dois caracteres composto por O/dígitos, dentro desses campos numéricos. As conversões ficam assinaladas como «confirmar». Não se convertem palavras verticais, códigos, nomes ou identificadores administrativos.
9. Grupos completos de cinco números e duas estrelas podem ser combinados entre passagens compatíveis da mesma linha. Fragmentos sem posição conhecida não são concatenados para fabricar grupos. Leituras contraditórias e índices não confirmados ficam incertos e não entram como apostas completas.
10. Cada aposta tem observações por passagem, valores aceites, tipo N/E, posição, texto bruto, origem, correções e problemas. Uma leitura parcial do full frame é identificada como posição por confirmar. O formulário mantém a política existente que protege edições manuais e alterações efetuadas durante o reconhecimento.
11. Metadados da primeira passagem sobrevivem às mudanças de orientação; metadados contraditórios pedem confirmação.

Os ficheiros temporários ficam no cache privado, são eliminados no `finally` e também no encerramento da Activity. Não são enviados à API, gravados nos logs globais como texto de recibo ou publicados. O serviço nativo executa fora da thread de UI e limita a imagem de preparação a 32 milhões de pixels e cada recorte ampliado a 16 milhões. Uma falha deixa a leitura inicial acessível. Esses limites não são prova de consumo aceitável em todos os aparelhos.

## Componentes

| Ficheiro | Função |
| --- | --- |
| `app/lib/domain/receipt_multipass.dart` | Zona, recortes, deteção vertical, combinação, conflitos e proveniência |
| `app/lib/domain/receipt_parser.dart` | Exclusão de colunas verticais da reconstrução horizontal, sem apagar observações |
| `app/lib/domain/receipt_ocr.dart` | Adaptação ML Kit incluindo largura e ângulo |
| `app/lib/data/receipt_crop_backend.dart` | Interface Dart do canal nativo |
| `app/android/app/src/main/kotlin/com/gilpereira/luckyscan50/MainActivity.kt` | EXIF, rotação, recorte PNG e limpeza |
| `app/lib/data/receipt_scanner.dart` | Primeira passagem, orientações e recuperação |
| `app/lib/main.dart` | Diagnósticos iniciais, passagens e valores por aposta; preenchimento protegido |
| `app/test/receipt_multipass_test.dart` | 13 regressões controladas do diagnóstico e casos-limite |
| `qa/android/integration_test/receipt_real_images_test.dart` | Aceitação nativa e do formulário com as duas fotos reais |
| `tools/compare_receipt_regions.py` | Protótipo Tesseract desktop limitado a regiões N/E |

## Resultados antes/depois: separar medições de simulação

| Aspeto | Antes | Depois desta implementação |
| --- | --- | --- |
| OCR real dos números iniciais/estrelas | Falha relatada pelo utilizador; sem imagem/dump integral neste executor | **Não medido**: fotografias ausentes |
| Cinco apostas completas e dez estrelas nas duas orientações | Não demonstrado | **Não demonstrado**; teste Android preparado, não executado |
| Precisão real por número/estrela/aposta | Não calculável a partir das palavras exemplificadas | **Não medida**; não se atribui 100% aos testes simulados |
| Latência real ML Kit/recortes em Android | Não fornecida | **Não medida**; diagnóstico e driver recolhem tempos durante execução real |
| Planeamento e combinação controlados | Não existiam | Regressões passam, incluindo recuperação de cinco grupos fornecidos por um recognizer falso |
| Proteção das edições manuais | Existente | Preservada; suíte de formulário continua a passar |
| Compilação | APK anterior de auditoria | Kotlin e compilação debug interna passam; nenhum novo APK disponibilizado |

Verificações efetivamente executadas: `flutter analyze` sem problemas; **44 testes Flutter passaram**, dos quais 13 são novos testes de múltiplas passagens; **13 testes Python passaram**. O teste nativo de aceitação não pertence a estes 44 testes e não foi marcado como aprovado/ignorado com sucesso. `adb devices` devolveu lista vazia.

As regressões incluem as cinco palavras verticais, alturas 685–697 px em geometria controlada, zona sem âncoras, recortes largos para estrelas, ausência de dados sem preenchimento inventado, duas escalas, O/0 ancorado e com proveniência, grupos complementares, recorte da linha vizinha, falhas de recorte, colunas administrativas externas, conflito entre leituras completas, índice geométrico incerto e preservação de metadados. Não se ensaiaram pixels reais, EXIF real ou qualidade ML Kit no Android.

## Tamanho do APK: medição interna, não distribuição

Foi compilado um snapshot debug interno para validar dependências/código e medir tamanho, sem criar ligação de download ou upload para esse APK. O ficheiro anterior em `/workspace/artifacts` manteve o checksum original.

| Medição | Bytes |
| --- | ---: |
| APK debug de auditoria anterior | 96 951 732 |
| Snapshot debug interno do protótipo | 119 599 026 |
| Diferença | +22 647 294 (+23,3593%) |

Este snapshot inclui a nova ponte nativa/AndroidX EXIF, suporte `integration_test` e dependências Android de testes, além de diferenças de empacotamento. Não é uma medição isolada do custo dos recortes e não estima o impacto em release/AAB. A comparação de payload ZIP mostrou aproximadamente +1,49 MB de conteúdo comprimido; o resto da diferença de ficheiro envolve o empacotamento. É necessário medir uma configuração de distribuição equivalente depois da aceitação. Não foi adicionado Tesseract ao APK.

Estado estruturado: `docs/validation/2026-10-17-multipass-status.json`.

## Demonstração real obrigatória

Usar um dispositivo Android e as **duas fotografias originais autorizadas**, sem reconstruções artificiais:

1. Manter `vertical.jpg` e `rotated.jpg` numa pasta privada fora da aplicação.
2. Executar na raiz do repositório (cópia QA temporária, dependências isoladas):

```sh
python3 tools/run_flutter_qa.py android --device DEVICE_ID \
  --photos /private/receipts --evidence /private/receipt-real-evidence.json
```

3. O teste chama o ML Kit e os recortes nativos reais, compara os cinco grupos e as dez estrelas com a verdade de referência **apenas para avaliação**, e transfere a saída real para o formulário. O seletor de ficheiros é substituído para selecionar o ficheiro de teste, mas o reconhecimento/recortes não são simulados.
4. O driver produz evidência copiada para o destino `--evidence`: acertos por número/estrela/aposta, orientação, identificação do build e tempos. Falta de imagens ou falha de qualquer aposta/orientação reprova a execução; não há fallback sintético para declarar sucesso.
5. Validar também no aparelho a seleção pela câmara/galeria, as margens visíveis, consumo de memória, edição manual, reentrada e eventuais avisos de O/0. Comparar o diagnóstico inicial com o recuperado.
6. O runner elimina a cópia temporária e os assets privados no fim. O APK distribuído não declara esses assets e o verificador rejeita fotografias de teste. A nova autorização permite distribuir o diagnóstico; a validação funcional continua a exigir a evidência real.

Atenção: o APK de integração local contém as fotos usadas no teste. Não o enviar, publicar ou partilhar. A produção cPanel e os dados de utilizadores não são necessários para este ensaio.

## Protótipo comparativo Tesseract

Ainda não é possível afirmar que os recortes ML Kit falham ou têm sucesso nas fotos reais. Para não bloquear uma comparação posterior, foi criado `tools/compare_receipt_regions.py`. Usa o Tesseract desktop existente, `--psm 7`, whitelist numérica e saída TSV com caixas/confiança. Recebe **recortes reais separados de números e estrelas**, não o recibo inteiro nem códigos alfanuméricos. Não corta um token longo usando valores esperados nem preenche valores ausentes.

Manifesto local de exemplo (caminhos para imagens reais, nunca placeholders usados para alegar precisão):

```json
{
  "rows": [{
    "orientation": "vertical",
    "bet": 1,
    "numbersImage": "real-row-1-numbers.png",
    "starsImage": "real-row-1-stars.png",
    "truth": {"numbers": [6,20,29,32,48], "stars": [4,6]},
    "mlkit": {"numbers": [], "stars": []}
  }]
}
```

```sh
python3 tools/compare_receipt_regions.py local-manifest.json --output local-comparison.json
```

Substituir os campos `mlkit` pelas saídas realmente observadas ou omiti-los; não usar listas vazias como se fossem uma medição. A verdade de referência só calcula o score depois do reconhecimento. O programa falha se não houver imagens/regiões; não cria imagens falsas. `--help` foi executado; nenhum benchmark Tesseract real foi executado por falta das fotografias. Tempos desktop não devem ser comparados diretamente aos tempos do telefone. Uma integração Android de Tesseract depende de resultados favoráveis e de teste de tamanho/memória/compatibilidade próprios; não foi introduzida sem evidência.

## Riscos e próximos passos

- O plano depende de âncoras que sobrevivam ao OCR e de margens adequadas. Se faltarem âncoras, devolve incerteza; não interpola cinco apostas a partir da contagem impressa.
- Falhas de perspetiva, inclinação grande, N/E ausentes e caracteres fundidos ainda podem não ser recuperados. Não se introduziram preenchimentos baseados no recibo conhecido.
- A correspondência de coordenadas entre a interpretação EXIF nativa do ML Kit e os pixels normalizados deve ser verificada nas fotos reais, incluindo EXIF 6/8 e rotação física sem metadados.
- Recortes PNG e tentativas até 2× aumentam CPU, I/O e memória. Os limites e a execução sequencial não substituem medições no aparelho.
- Prioridade seguinte: disponibilizar as fotos e Android, executar a aceitação e inspecionar origem dos valores e recortes por linha. Se persistirem falhas, comparar Tesseract nas regiões efetivamente problemáticas. **O critério de aceitação principal permanece aberto.**
