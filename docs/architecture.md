# Arquitetura

```text
Fotografia / captura online / entrada manual
                    |
             Leitor por formato
                    |
            Confirmação humana
                    |
       Carteira local (SQLite)
                    |
      Combinações + concursos
                    |
API: resultados + prémios oficiais + regras versionadas
                    |
       Verificador local de prémios
                    |
  Alertas / datas / histórico / estatísticas
```

App Flutter Android; armazenamento local-first; API de produção Python 3.12 Passenger/WSGI nativo; resultados centrais SQLite com revisões e importação administrativa. TypeScript permanece como referência. Push ainda não implementado; chaves privadas permanecem no aparelho. Não existe integração autorizada direta com contas JSC no âmbito inicial.
