# Sprint 4 — Task 8 report: privacidade, acessibilidade e adaptação nativa

## Entrega

- `values.hidden` é uma preferência global persistida em `LocalSettings`; a Home recebe o mesmo controller para todos os seus `FinancialAmount`.
- Valores ocultos têm texto mascarado e semântica exatamente `Valor oculto`, sem algarismos. As linhas de movimentação também não expõem o valor original pela semântica agregada.
- `PrivacyShield` cobre o shell financeiro nos estados `inactive`, `paused`, `hidden` e `detached`; no retorno, restaura a preferência persistida.
- Android aplica `FLAG_SECURE`; iOS instala/remove uma superfície opaca sem dados financeiros no ciclo de background/foreground.
- O seletor anuncia explicitamente a visão selecionada. Os controles existentes preservam tooltip/label, ordem visual de foco, alvos nativos (48 dp Android / 44 pt iOS) e o layout já testado para texto a 200% em 320 px.

## Evidência TDD

1. RED observado para `ValueVisibilityController`: import/contratos ausentes; GREEN com persistência e reconstrução do controller.
2. RED observado para semântica ocultada: `Valor financeiro oculto` divergente do requisito; GREEN com `Valor oculto` sem dígitos.
3. RED observado para `PrivacyShield`: widget ausente; GREEN para cobertura em lifecycle e restauração em `resumed`.
4. RED observado para a integração Home: parâmetro de controller ausente; GREEN comprovando que todos os `FinancialAmount` renderizados recebem o estado global oculto.
5. RED observado para anúncio do seletor; GREEN com `Eu, selecionado`.

## Validação

- `flutter test test/app test/accessibility test/features/home` — passou (42 testes).
- Rodada visual batched: os seis goldens aprovados da Home (mobile, iOS e Windows; claro/escuro) passaram na mesma execução. Não foi necessário segundo ciclo visual.
- `flutter analyze` — passou, sem issues.
- `dart format --output=none --set-exit-if-changed lib test` — passou.
- `flutter test` (suíte Flutter completa) — passou (161 testes).
- `flutter build windows --debug` — passou.
- `flutter build apk --debug` — passou; Gradle emitiu warnings de compatibilidade de acesso nativo Java e XML de SDK, sem falha de build.
- iOS não foi compilado nem executado: Windows não fornece Xcode/simulador. A validação de iOS nesta task é pelos testes/goldens Flutter e inspeção do código nativo.

## Limites conhecidos

- No Windows, o `PrivacyShield` Flutter protege o conteúdo enquanto o app está no estado coberto. Miniaturas do SO são apenas melhor esforço e não constituem fronteira de segurança.
- `FLAG_SECURE` é a fronteira Android para screenshots/recentes; não há permissões novas, push, biometria ou escrita financeira.

## Onda corretiva pós-review

- O projeto usa `SceneDelegate`; a cobertura nativa iOS foi movida para `sceneWillResignActive` e `sceneDidEnterBackground`, com overlay opaco idempotente na janela da cena. A remoção ocorre apenas em `sceneDidBecomeActive`; os callbacks ineficazes foram removidos do `AppDelegate`.
- O `PrivacyShield` mantém a superfície opaca durante `onResumed` e só a remove após a conclusão bem-sucedida. Um epoch de lifecycle impede uma conclusão antiga de descobrir uma transição inativa posterior.
- `ValueVisibilityController` serializa restore/toggle/write. Um write falho não publica a alteração em memória; leituras antigas não sobrescrevem um toggle enfileirado.
- `FinancialAmount(hidden: true, minorUnits: null)` agora mascara o valor e anuncia `Valor oculto`, sem expor `Indisponível`.
- A prova de layout passou a executar realmente em 320 logical px com escala 2.0. O teste de teclado verifica Tab na ordem privacidade → seletor → retry → navegação, além de Space/Enter para privacidade e retry.

### Evidência adicional

- REDs observados para conclusão antecipada do shield, completion obsoleto, corrida restore/toggle, toggles concorrentes, write falho, valor nulo oculto e ausência dos callbacks SceneDelegate.
- GREEN focado: `flutter test test/app test/accessibility test/features/home` — passou (48 testes); `flutter analyze` — passou.
- O teste iOS é estático e verifica a SceneDelegate/remoção do AppDelegate neste Windows. Build e runtime iOS seguem explicitamente pendentes de macOS/Xcode.
- Fechamento da onda: `flutter test` — passou (168 testes); `dart format --output=none --set-exit-if-changed lib test` e `git diff --check` — passaram. Builds reais `flutter build windows --debug` e `flutter build apk --debug` — passaram.

## Onda final de acessibilidade e falha de persistência

- RED observado: uma falha de `values.hidden` disparada pela Home não tinha feedback seguro. GREEN: a Home aguarda o toggle, preserva o estado já consistente do controller e anuncia somente `Não foi possível atualizar a privacidade`; detalhes de storage e da exceção não são exibidos.
- A matriz de widgets exerce Windows em 1366×768: Tab chega, em ordem, a privacidade, seletor, retry e `NavigationRail`; Space/Enter ativam privacidade, seletor, retry e navegação. O teclado ativa `FocusHighlightMode.traditional` no foco Material e o `MouseRegion` real do controle de privacidade recebe hover.
- A matriz mede alvos reais: Android ≥48 logical px para privacidade, seletor e retry; iOS ≥44 logical px para privacidade e seletor, dentro de `SafeArea`. A prova em 320 logical px / escala 2.0 permanece no teste da Home.
- Com `MediaQuery.disableAnimations=true`, o feedback novo de falha usa `AnimationStyle.noAnimation`; o teste verifica que a animação do `SnackBar` já está concluída.

### Evidência final

- `flutter test test/app test/accessibility test/features/home` — passou (52 testes).
- `flutter test` — passou (172 testes); `flutter analyze` — passou, sem issues; format e `git diff --check` — passaram.
