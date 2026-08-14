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
