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

App Flutter Android; armazenamento local-first; API Node.js/TypeScript; dados centrais PostgreSQL. Push anuncia disponibilidade de resultados; chaves privadas permanecem no aparelho. Não existe integração autorizada direta com contas JSC no âmbito inicial.
