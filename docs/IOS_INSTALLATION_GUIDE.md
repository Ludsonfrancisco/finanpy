# Guia de Instalação do Lar Finance no iPhone (iOS)

Este guia explica como instalar o aplicativo nativo **Lar Finance** no seu **iPhone** e no da sua **esposa** de forma 100% gratuita utilizando o instalador `.ipa` gerado pelo GitHub Actions.

---

## 📋 Pré-requisitos
1. Seu computador com **Windows**.
2. Cabo USB para conectar o iPhone ao computador.
3. Programa gratuito **Sideloadly** instalado no Windows ([Download no site oficial sideloadly.io](https://sideloadly.io/)).
4. Seu **Apple ID** comum (e-mail e senha que você usa na App Store).

---

## 🚀 Passo a Passo de Instalação

### 1. Baixar o arquivo `.ipa` gerado no GitHub
1. Acesse o repositório do seu projeto no **GitHub**.
2. Clique na aba **Actions** no topo.
3. Clique na última execução da pipeline (*CI*) que foi concluída com sucesso.
4. No rodapé da página, na seção **Artifacts**, clique em **`lar-finance-ios-ipa-...`** para baixar o arquivo zip.
5. Extraia o arquivo `.zip` para obter o arquivo **`lar-finance.ipa`**.

---

### 2. Instalar no iPhone com o Sideloadly
1. Abra o **Sideloadly** no seu computador.
2. Conecte o seu iPhone ao computador usando o cabo USB (se o iPhone perguntar *"Confiar neste computador?"*, toque em **Confiar** e digite o código de desbloqueio).
3. No Sideloadly:
   - O seu iPhone aparecerá selecionado no campo **iDevice**.
   - No campo **Apple ID**, digite o seu e-mail da conta Apple.
   - Arraste o arquivo **`lar-finance.ipa`** para dentro do quadrado com o ícone do Sideloadly (ou clique para selecionar o arquivo).
4. Clique no botão **Start**.
5. Se for a primeira vez, o Sideloadly pedirá a senha do seu Apple ID para assinar o aplicativo com seu certificado pessoal gratuito da Apple.
6. Aguarde a barra de progresso chegar em **100% (Done)**. O ícone do **Lar Finance** aparecerá na tela do seu iPhone!

---

### 3. Autorizar a Abertura do App no iPhone (Apenas no 1º uso)
Por segurança, a Apple exige que você confirme o desenvolvedor nas configurações do iPhone na primeira vez:
1. No iPhone, abra **Ajustes** > **Geral** > **VPN e Gerenciamento de Dispositivos**.
2. Toque no seu e-mail do Apple ID em *App do Desenvolvedor*.
3. Toque em **"Confiar em [Seu Nome/Email]"** e confirme.
4. *(No iOS 16 ou superior)*: Se solicitado, ative o *Modo de Desenvolvedor* em **Ajustes** > **Privacidade e Segurança** > **Modo de Desenvolvedor** (o iPhone reiniciará uma vez).

---

### 4. Instalar no iPhone da Esposa
Para instalar no iPhone dela, basta:
1. Conectar o iPhone dela no cabo USB.
2. No Sideloadly, selecionar o iPhone dela.
3. Clicar em **Start** (pode usar o mesmo Apple ID ou o dela).
4. Fazer o passo 3 no iPhone dela.

---

🎉 **Pronto!** O aplicativo **Lar Finance** nativo estará rodando no iPhone com toda a velocidade, animações, gráficos analíticos e sincronização offline.
