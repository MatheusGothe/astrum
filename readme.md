# Astrum Android E2E com Maestro

O workflow manual inicia um emulador Android com Play Store, abre o link público do Astrum, instala o app pela loja e então executa os flows do Maestro. Não é necessário publicar nem enviar um APK separadamente.

## Executar no GitHub Actions

Em **Actions → Astrum - Android E2E → Run workflow**, mantenha o link da Play Store que você enviou ou informe outro link público. Não é necessário configurar senha, e-mail, domínio de e-mail nem conta Google.

O teste gera automaticamente um e-mail sintético único em `example.com` e uma senha aleatória por execução. Nenhum dos valores é exibido nos logs. Nenhuma senha de conta Google é pedida nem armazenada pelo workflow. O link informado já aponta para o package ID `app.astrum.mobile`, confirmado no código Android local; o flow usa esse package ID para abrir o app instalado.

## O que o flow faz

O arquivo `.maestro/flows/01-cadastro.yaml` abre a listagem da Play Store no emulador, instala e abre o Astrum, preenche nome, e-mail, senha, sexo e país, e verifica que o cadastro chegou às abas autenticadas “Mapa Geral” e “Perfil”. A data de nascimento é opcional. O app atual autentica imediatamente e confirma o e-mail em segundo plano.

O app pode pedir uma conta Google ao iniciar a Play Store ou tentar instalar. Não configuramos login Google, conforme solicitado. Se a Play Store exigir login nesse runner, a instalação falhará antes do teste de cadastro; nesse caso será necessário habilitar uma conta Google de teste no emulador ou usar outro mecanismo oficial de distribuição/instalação. O workflow não tenta contornar controles da loja.

O backend precisa aceitar cadastro usando endereços sintéticos e criação de perfil. O seletor de países consulta `countriesnow.space` e usa a tabela `countries` como fallback, então o emulador precisa de conectividade. Use um backend de QA. O teste não apaga usuários; a limpeza/retenção deve ser configurada no backend de teste sem usar credenciais `service_role` no app ou no Maestro.

## Executar localmente

Com Maestro CLI e um emulador com Play Store em execução:

```bash
export ASTRUM_APP_ID='app.astrum.mobile'
export ASTRUM_PLAY_STORE_URL='https://play.google.com/store/apps/details?id=app.astrum.mobile&hl=pt_BR'
export ASTRUM_TEST_NAME='Astrum QA'
./scripts/run-tests.sh
```

Não coloque a senha em arquivos versionados. `.env.example` lista as variáveis esperadas sem valores secretos.

## CI e privacidade

O workflow é manual (`workflow_dispatch`), usa `ubuntu-24.04`, KVM, Pixel 6/API 35 com imagem `google_apis_playstore`, timeout de 45 minutos e concorrência serial por ref. Não há agendamento nem workflow de pull request. Ele publica o relatório JUnit por sete dias e mostra os tempos de preparação, teste e execução total. Vídeos e screenshots não são publicados; ainda assim, use dados de QA, pois relatório de teste pode incluir conteúdo visível na UI.

## Pendências e validação

Neste momento o workflow executa somente o cadastro. Login e logout serão adicionados depois que o cadastro passar. Recuperação de senha, edição de perfil, navegação, atividades, territórios, bicicleta, feed, rankings, clubes e Pro ficam pendentes de inspeção das telas e dependências reais. GPS e conquista territorial exigem também estratégia de localização simulada e validação segura no backend.

Os seletores do cadastro e o package ID foram conferidos no código local do Astrum. O teste ponta a ponta ainda não foi executado neste ambiente. A etapa nova de instalação via Play Store precisa ser validada num runner: se o Google exigir autenticação, será necessário fornecer conta de teste autorizada ou escolher instalação de APK assinado.
