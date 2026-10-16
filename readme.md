# Astrum Android E2E com Maestro

O workflow manual inicia um emulador Android com Play Store, abre o link público do Astrum, instala o app pela loja e então executa os flows do Maestro. Não é necessário publicar nem enviar um APK separadamente.

## Executar no GitHub Actions

Em **Actions → Astrum - Android E2E → Run workflow**, mantenha o link da Play Store que você enviou ou informe outro link público. Para permitir a instalação, configure os secrets `PLAY_STORE_EMAIL` e `PLAY_STORE_PASSWORD` em **Settings → Secrets and variables → Actions**. Use as credenciais de uma conta Google autorizada para baixar o app.

Antes de instalar o emulador, o workflow valida que os dois secrets existem e que o e-mail tem formato válido; mensagens de validação não mostram os valores. O Maestro usa esses secrets somente para entrar na Play Store quando ela pedir login. Separadamente, o teste gera um e-mail sintético único em `example.com` e uma senha aleatória para cadastrar no Astrum. O link informado já aponta para o package ID `app.astrum.mobile`, confirmado no código Android local.

## O que o flow faz

O arquivo `.maestro/flows/01-cadastro.yaml` abre a listagem da Play Store no emulador, instala e abre o Astrum, preenche nome, e-mail, senha, sexo e país, e verifica que o cadastro chegou às abas autenticadas “Mapa Geral” e “Perfil”. A data de nascimento é opcional. O app atual autentica imediatamente e confirma o e-mail em segundo plano.

Conta Google da Play Store e conta do Astrum são coisas diferentes. Se a tela de login da loja exigir uma confirmação adicional (por exemplo, verificação de segurança), a automação poderá parar antes do cadastro e será preciso concluir essa configuração da conta fora do workflow.

O backend precisa aceitar cadastro usando endereços sintéticos e criação de perfil. O seletor de países consulta `countriesnow.space` e usa a tabela `countries` como fallback, então o emulador precisa de conectividade. Use um backend de QA. O teste não apaga usuários; a limpeza/retenção deve ser configurada no backend de teste sem usar credenciais `service_role` no app ou no Maestro.

## Executar localmente

Com Maestro CLI e um emulador com Play Store em execução:

```bash
export ASTRUM_APP_ID='app.astrum.mobile'
export ASTRUM_PLAY_STORE_URL='https://play.google.com/store/apps/details?id=app.astrum.mobile&hl=pt_BR'
export ASTRUM_TEST_NAME='Astrum QA'
read -r -p 'Google account email: ' PLAY_STORE_EMAIL
read -r -s -p 'Google account password: ' PLAY_STORE_PASSWORD
echo
export PLAY_STORE_EMAIL PLAY_STORE_PASSWORD
./scripts/run-tests.sh
```

Não coloque credenciais em arquivos versionados nem compartilhe a senha no chat. No GitHub, cadastre-as como Actions secrets. A validação verifica se os valores foram fornecidos e se o e-mail parece válido; apenas um login real pode confirmar se as credenciais estão corretas.

## CI e privacidade

O workflow é manual (`workflow_dispatch`), usa `ubuntu-24.04`, KVM, Pixel 6/API 35 com imagem `google_apis_playstore`, timeout de 45 minutos e concorrência serial por ref. Não há agendamento nem workflow de pull request. Ele publica o relatório JUnit por sete dias e mostra os tempos de preparação, teste e execução total. Vídeos e screenshots não são publicados; ainda assim, use dados de QA, pois relatório de teste pode incluir conteúdo visível na UI.

## Pendências e validação

Neste momento o workflow executa somente o cadastro. Login e logout serão adicionados depois que o cadastro passar. Recuperação de senha, edição de perfil, navegação, atividades, territórios, bicicleta, feed, rankings, clubes e Pro ficam pendentes de inspeção das telas e dependências reais. GPS e conquista territorial exigem também estratégia de localização simulada e validação segura no backend.

Os seletores do cadastro e o package ID foram conferidos no código local do Astrum. O teste ponta a ponta ainda não foi executado neste ambiente. A etapa nova de instalação via Play Store precisa ser validada num runner: se o Google exigir autenticação, será necessário fornecer conta de teste autorizada ou escolher instalação de APK assinado.

## Experimento independente: app iOS no macOS nativo

O workflow manual `.github/workflows/test-astrum-macos.yml` testa a viabilidade de abrir o Astrum iOS como app para Apple Silicon no runner `macos-26`, sem simulador e sem build. Ele coleta versão/arquitetura do macOS, sessão gráfica, App Store, `mas`, permissões de automação observáveis, tempos e resultados em Actions Step Summary. Nenhuma credencial Apple é usada.

O App Store ID foi identificado como `6758635201`. A ficha pública indica compatibilidade com Mac M1 ou posterior, mas classifica o app como “Somente para iPhone” e “Não verificado para macOS”. O experimento abre a ficha no Mac App Store e tenta clicar no botão público de download se a acessibilidade permitir, sem autenticar; também tenta `mas install` sem credenciais e procura o app caso uma das rotas funcione. Se instalado, tenta iniciá-lo e usa AppleScript/System Events para abrir cadastro, preencher um valor de teste não real, verificar e apagar esse valor. Não submete cadastro.

Resultado das execuções: [run inicial](https://github.com/MatheusGothe/astrum/actions/runs/38838711236) e [run com diagnóstico de acessibilidade](https://github.com/MatheusGothe/astrum/actions/runs/38838878284). O runner era macOS 26.6.2 em Apple Silicon (`arm64`), com sessão gráfica ativa, WindowServer e App Store presentes. `mas` 7.0.0 não encontrou o ID `6758635201`; a tentativa pela interface abriu a App Store, mas não encontrou botões acessíveis de instalação (`no_accessible_buttons`). O app não foi instalado, então a etapa de iniciar o Astrum e automatizar o cadastro foi pulada. A classificação do experimento é **falha de instalação**; o job do Actions terminou com sucesso porque coleta e reporta resultados de viabilidade, inclusive falhas da tentativa. A causa específica da interface não ter exposto um botão não foi determinada, então esse resultado não prova que uma conta Apple resolveria o bloqueio.

A documentação atual do projeto `mas` marca iOS/iPadOS como não suportados, o que explica por que essa ferramenta não instalou este app. O experimento não usou Apple ID nem alterou permissões de segurança do macOS.

Referências da investigação: [ficha do Astrum na App Store](https://apps.apple.com/br/app/astrum/id6758635201), [guia Apple para apps de iPhone/iPad em Macs Apple Silicon](https://support.apple.com/en-asia/guide/app-store/fird2c7092da/mac), [limitações documentadas do `mas`](https://github.com/mas-cli/mas#known-issues) e [imagens atuais do GitHub Actions](https://github.com/actions/runner-images#available-images). Para uma versão original obtida pela Apple, a rota é a Mac App Store; o link público não é um pacote instalável direto. App Store Connect/TestFlight são distribuição de teste e normalmente dependem de Apple ID e autorização do tester, não substituem a aquisição pública sem autenticação.
