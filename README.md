# LuckyScan 50

Aplicação Android independente para registar e verificar apostas portuguesas do Euromilhões e M1lhão, acompanhar prémios e prazos e analisar estatísticas financeiras e históricas.

> Projeto não oficial, sem associação aos Jogos Santa Casa. Os resultados apresentados são informativos: prevalece a validação pelo operador autorizado.

## Objetivos
- Importar fotografias de recibos físicos e capturas de ecrã de apostas online, com confirmação manual dos campos.
- Arquivar localmente chaves, sorteios, códigos M1lhão e comprovativos.
- Verificar os resultados oficiais após a publicação, com identificação dos 13 escalões.
- Avisar de prémios, sorteios sem prémio e prazos de reclamação.
- Acompanhar valores apostados, prémios apurados/recebidos e frequências dos números.
- Permitir cópias de segurança encriptadas opcionais.

## Estrutura
- `app/`: app Flutter Android e domínio Dart.
- `backend/`: API Node.js/TypeScript e ingestão de resultados (a implementar).
- `shared/`: regras e modelos partilhados.
- `docs/`: requisitos, arquitetura, decisões e limitações.

## Estado
**Fundação do projeto**. Os leitores OCR, a interface, o armazenamento local, as notificações e a recolha oficial de resultados **ainda não estão implementados**. Não utilizar para validar prémios reais.

## Desenvolvimento
```bash
cd app
flutter create --org com.gilpereira --project-name luckyscan50 .
flutter pub get
flutter test

cd ../backend
npm install
npm test
```

A fonte oficial de dados e a viabilidade de publicação nas lojas necessitam de validação antes da distribuição.
