# Task 3 — Home Flutter compacta e desktop

## Implementação

- A posição financeira passou a usar `HomeFinancialSurface` com a key
  `home-position-card`, acento mineral e hierarquia iniciada diretamente por
  `Saldo consolidado`, conforme a decisão Impeccable v4.
- Compromissos e gasto mensal passaram a cards de apoio com keys próprias,
  acentos champanhe/danger e valores tabulares. Eles empilham abaixo de 560 px
  ou com texto ampliado e usam linha quando há largura suficiente.
- Movimentações recentes passaram a painel financeiro com texto contextual,
  preservando linhas, semântica, valores assinados, divisores e adaptação a
  texto ampliado.
- No compacto, a ordem é posição, compromissos, gasto e movimentações. No
  desktop, posição (5/9) e métricas (4/9) compartilham o topo; atenção/retry e
  movimentações ocupam a largura completa abaixo.
- O bloco de atenção/retry foi extraído para `_AttentionSection` e é reutilizado
  pelos dois layouts. Sync, offline, erro, cache, privacidade, owner selector,
  foco de teclado e pull-to-refresh não tiveram seus fluxos alterados.
- Os seis goldens da Home foram atualizados após inspeção dos renders em
  Android, iOS e Windows, claro e escuro.

## Arquivos

- `mobile/lib/features/home/presentation/home_screen.dart`
- `mobile/lib/features/home/presentation/widgets/balance_header.dart`
- `mobile/lib/features/home/presentation/widgets/commitments_summary.dart`
- `mobile/lib/features/home/presentation/widgets/recent_transactions.dart`
- `mobile/test/features/home/home_screen_test.dart`
- `mobile/test/goldens/home_{mobile,ios,windows}_{light,dark}.png`

## RED / GREEN

- RED: os testes `compact home preserves shared financial order without
  overflow` e `desktop home keeps metrics beside position and recent activity
  visible` falharam individualmente porque `home-position-card` não existia.
- GREEN: após a implementação mínima, ambos passaram individualmente; a suíte
  focada terminou com 30/30 testes e a suíte de goldens com 6/6.

## Comandos e resultados

- `flutter test ... --plain-name <novo teste>` — RED esperado nos dois casos;
  depois GREEN, 1/1 em cada execução.
- `flutter test test/features/home/home_screen_test.dart test/accessibility/home_accessibility_test.dart test/design_system/lar_theme_test.dart` — 30/30.
- `dart format --output=none --set-exit-if-changed lib/features/home test/features/home test/design_system/lar_theme_test.dart` — 13 arquivos, 0 alterados.
- `flutter analyze` — sem issues.
- `flutter test --update-goldens test/features/home/home_goldens_test.dart` e
  nova execução sem update — 6/6.
- `flutter test` — 381/381.
- `git diff --check` — limpo; apenas avisos informativos de conversão LF/CRLF.

## Self-review

- O diff fica restrito à Home, aos dois novos testes e às baselines visuais
  diretamente afetadas.
- Não há roxo, gradiente, glow ou `IntrinsicHeight` na composição alterada.
- A semântica de privacidade continua sem expor dígitos; os testes de 320 px a
  200%, foco Windows, alvos Android/iOS e refresh Cupertino seguem verdes.
- Os renders claro/escuro foram inspecionados antes da atualização das
  baselines e correspondem à hierarquia Casa de Valores 2.0 aprovada.

## Concerns

- Não há concern funcional conhecido. A validação foi feita por widget/golden
  tests no host Windows; não houve execução manual em aparelho físico.
- O runner informa dependências mais recentes incompatíveis com as constraints
  atuais e tag `golden` não declarada em `dart_test.yaml`; são avisos preexistentes
  e não causaram falha.
