# LuckyScan50 — site público

Site estático em português de Portugal, pensado para GitHub Pages no repositório GilPereiraPT/LuckyScan50. Não contém contas, formulários de apostas, credenciais nem dados de carteiras.

Páginas: apresentação, ajuda, privacidade e utilização. O painel interativo é identificado como demonstração, não uma captura real da app. O logótipo e o banner são os recursos de marca existentes no repositório. Não são anunciados preços, testemunhos ou distribuição Google Play.

## Publicação

O workflow LuckyScan50 website valida HTML, ligações locais, sintaxe JavaScript e interações com um DOM de teste. Confirma também o checksum do APK assinado existente antes de o publicar na versão GitHub v0.2.8. Não compila um APK novo nem altera o cPanel.

O site é preparado apenas a partir de website/ e distribuído como artefacto, sem incluir a API, bases de dados ou ficheiros privados. Quando GitHub Pages estiver ativo com Source=GitHub Actions, o workflow publica em https://gilpereirapt.github.io/LuckyScan50/.

Se Pages ainda não estiver ativo: Settings → Pages → Build and deployment → Source → GitHub Actions. Depois abrir Actions → LuckyScan50 website → execução mais recente → Re-run all jobs. Esta ativação administrativa não é efetuada pela ligação GitHub utilizada nesta entrega.

A publicação é disparada por alterações em website/, nas verificações do site e no workflow, no ramo feat/manual-draw-picker. Também aceita workflow_dispatch. Rever o ramo ao integrar na linha principal. O workflow não publica código de outro ramo sem o respetivo commit de disparo.

## Limites de verificação

Sem ambiente de navegador disponível nesta sessão, a revisão visual responsiva deve ser concluída no endereço publicado. As verificações em CI não substituem uma revisão num dispositivo real. Os conteúdos seguem as capacidades confirmadas na versão 0.2.8 e explicitam a cobertura incompleta dos resultados e as dependências dos avisos.
