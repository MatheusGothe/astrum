# Astrum Android E2E com Maestro

Suíte de interface Android acionada manualmente por GitHub Actions. Os fluxos individuais ficam em `.maestro/flows`; o workflow prepara o emulador, instala o APK verificado e executa a suíte.

## Fluxo implementado: cadastro

O fluxo `01-cadastro.yaml` usa as telas reais encontradas no checkout local `astrum-mob` (Expo Router). Na tela de autenticação, alterna para cadastro e preenche nome, e-mail, senha, sexo e país. Data de nascimento é opcional. O app exige sexo e país e, quando o cadastro tem sessão, navega para as tabs autenticadas. O código informa “Conta criada! Você já pode usar o Astrum enquanto confirma seu e-mail.”; portanto a confirmação por e-mail é posterior e não bloqueia a autenticação. O fluxo verifica a mensagem de sucesso e a tab real “Mapa Geral”.

O checkout do app não faz parte deste repositório e nenhum código dele foi copiado. Os textos usados são os rótulos existentes no fluxo de autenticação em português. Não foram encontrados testIDs/accessibility IDs próprios para essa tela; seletores textuais podem precisar de atualização quando o app mudar. O identificador de pacote deve ser fornecido pela configuração do repositório.

## APK e integridade

O repositório original só continha um workflow de benchmark que instalava Maestro e iniciava Android API 35; ele foi preservado e ampliado. Não foi encontrado APK local nem uma origem configurada. O script `scripts/download-apk.sh` requer URL HTTPS e SHA-256 correspondente, e valida o arquivo antes da instalação. Não há URL presumida.

Configure os GitHub Actions Secrets `ASTRUM_APK_URL` e `ASTRUM_APK_SHA256`, ou forneça `apk_url` e `apk_sha256` na execução manual. URLs com credenciais embutidas não devem ser usadas. Também configure:

- Secret `ASTRUM_TEST_PASSWORD`: senha que o app aceita para a conta recém-cadastrada.
- Repository variable `ASTRUM_TEST_EMAIL_DOMAIN`: domínio de QA que aceite catch-all ou plus-addressing.
- Repository variable `ASTRUM_APP_ID`: applicationId Android. O checkout local informa `app.astrum.mobile`; confirme que o APK pertence à mesma aplicação.
- Repository variable `ASTRUM_TEST_NAME`: nome exibido no cadastro automatizado.

O script gera um endereço novo em cada execução no formato `astrum-e2e+<timestamp-run-id-random>@<domínio>`, portanto o domínio deve aceitar catch-all ou plus-addressing. O teste não precisa abrir a caixa de entrada porque o app deixa a pessoa autenticada enquanto confirma o e-mail em segundo plano. O workflow não imprime valores de credenciais.

O backend precisa aceitar cadastro por e-mail e criação de perfil. O seletor de países tenta `countriesnow.space` e usa a tabela `countries` como fallback, então o emulador precisa de acesso à rede e ao serviço configurado. A configuração atual do app acessível nesta máquina autentica imediatamente e envia confirmação em segundo plano. Se o projeto/ambiente de APK exigir confirmação antes da sessão ou aplicar CAPTCHA/limites, o fluxo precisa de mailbox de QA e tratamento específico. Não há estratégia de limpeza porque excluir contas exige credencial administrativa; nenhuma conta de produção será apagada. Use um projeto Supabase isolado de teste e uma rotina de retenção aprovada.

## Rodar localmente

Requisitos: Android SDK/emulador em execução, `adb`, Java compatível com Maestro, Maestro CLI e `artifacts/astrum.apk` (baixado pelo script), ou o APK instalado manualmente. O pacote requer config e variáveis de cadastro válidas:

```bash
export APK_URL='https://.../astrum.apk'
export APK_SHA256='<sha256 de 64 caracteres>'
./scripts/download-apk.sh

export ASTRUM_APP_ID='app.astrum.mobile'
export ASTRUM_TEST_NAME='Astrum QA'
export ASTRUM_TEST_EMAIL_DOMAIN='<domínio catch-all de QA>'
export ASTRUM_TEST_PASSWORD='<senha de QA>'
adb install -r artifacts/astrum.apk
./scripts/run-tests.sh
```

Não grave essas variáveis em arquivos versionados. `.env.example` lista somente os nomes de origem do APK; o Maestro recebe variáveis diretamente do processo. A senha não é incluída nos relatórios.

## GitHub Actions

Abra **Actions → Astrum - Android E2E → Run workflow**. Forneça URL e SHA-256 como inputs ou configure os secrets indicados. O runner `ubuntu-24.04` mantém KVM, emulador Pixel 6/API 35, timeout de 45 minutos e concorrência serial por ref. O job falha se download, checksum, instalação ou algum flow falhar. O resumo inclui tempo total e por etapa. O relatório JUnit texto é publicado por sete dias.

Não há agendamento ou execução em pull requests. Não são enviados vídeos/screenshots. Mesmo relatórios JUnit podem carregar dados da UI dependendo da versão do Maestro; retenção é curta, não use contas ou dados pessoais reais em CI público. O workflow não recebe `service_role`.

## Próximos fluxos

Login pode ser coberto após disponibilizar conta de QA isolada. Logout, recuperação de senha, edição de perfil, navegação, atividades, territórios, bicicleta, feed, rankings, clubes e Pro permanecem pendentes de validação das telas, estados e dependências reais do APK/backend. GPS e conquistas territoriais precisam definir estratégia de localização simulada e validação segura de estado no backend antes de automatizar.

## Estado da validação

Foi possível validar os nomes dos campos, obrigatoriedade e comportamento de confirmação pela leitura do código local do app. O `applicationId` também foi confirmado como `app.astrum.mobile`. Não foi possível executar o E2E: este repositório não tem APK nem domínio/credenciais/backend de QA configurados. Logo, o fluxo é uma implementação inicial baseada em UI real, ainda não declarado funcional até ser executado no emulador.
