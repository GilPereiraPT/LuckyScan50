# OCR de talões físicos — linhas N/E com Google ML Kit

## Decisão

Usar **Google ML Kit já incluído na aplicação**. Não adicionar RapidOCR,
Tesseract ou outros runtimes ao APK. Esta alteração acrescenta a interpretação
estrita das sequências reconhecidas após as âncoras **N** e **E**.

- N: dez dígitos, cinco pares de 01 a 50, estritamente crescentes.
- E: quatro dígitos, dois pares distintos de 01 a 12.
- Cada par N/E identificado pertence à mesma aposta; conferir a contagem com
  `5 AP SIMPLES` ou outro cabeçalho compatível quando presente.
- Contagem/preço são **verificações**, nunca fontes para preencher dígitos.
- Não remover caracteres inesperados para forçar um comprimento: `儿4`,
  `0577` (estrelas fora do intervalo) e sequências truncadas ficam em revisão.
- O PDF digital permanece numa via distinta, sem depender de marcadores N/E.

## Código nesta branch

`app/lib/domain/receipt_ne_lines.dart`: interpreta sequências N/E estritas.
`app/lib/domain/receipt_parser.dart`: utiliza a nova interpretação em linhas
textuais ancoradas N/E quando a sequência integral está disponível.
`app/test/receipt_ne_lines_test.dart`: regressões com o talão de cinco apostas,
casos inválidos e associação N/E.

## Integração geométrica pendente de validação Android

A implementação já existente em `receipt_scanner.dart`,
`receipt_multipass.dart` e no canal `receipt_crops` é responsável pelos
recortes nativos e passagens reais do ML Kit. **Esta mudança não demonstra que
o motor agora consiga ler os quatro dígitos de todas as linhas E da fotografia.**

Próxima etapa técnica: ancorar linhas N/E nas observações e caixas de texto
efetivamente reconhecidas; criar recortes separados de cada linha física
respeitando inclinação/perspetiva; reaplicar ML Kit por linha; entregar ao
interpretador apenas o texto à direita da âncora, na ordem visual, com
proveniência. Se a leitura completa falhar, manter as alternativas por célula
como diagnóstico, sem juntar fragmentos de posições incertas.

**Aceitação**: executar no Android o talão físico real (5 pares completos,
25 números + 10 estrelas), o PDF digital (3 apostas), testar alterações de
orientação e confirmar que edições manuais são preservadas. Não publicar APK
automática ou declarar os testes reais aprovados sem execução e evidência.

## Estado

Código e testes adicionados ao GitHub. A execução de Flutter/ML Kit não foi
possível nesta sessão; nenhuma compilação nem validação de APK foi realizada.
