# Task 7 — Home financeira real somente leitura

## Status

Implementação concluída na branch `codex/sprint-4-flutter-foundation`, partindo da base limpa `33dcaeeea01abb0bdc2761a6c4ece2ebdadfda37`.

A Home lê somente o SQLite local por uma fronteira reativa do `HomeRepository`. Nenhuma chamada de rede, escrita financeira, importação, persistência de privacidade ou proteção de app switcher foi adicionada à feature.

## TDD — RED / GREEN

### Fórmulas, escopos e ordem

- RED inicial: `home_repository_test.dart` não compilou porque `features/home/domain/home_snapshot.dart` e `features/home/data/home_repository.dart` ainda não existiam.
- RED de resolução de owners: o teste não compilou enquanto `readOwnerScopes()` não existia.
- Durante o primeiro GREEN, o caso individual expôs um erro real de binding SQL (`Expected 9 parameters, got 8`) ao introduzir a contagem de contas; a query foi corrigida com predicados/bindings independentes para `COUNT` e `SUM`.
- GREEN final: 5 testes do repositório passaram, incluindo Lar/Eu/Esposa, ausência de contas, ordem determinística e limite de cinco.
- A compatibilidade do caminho anterior foi preservada: os 5 testes de `core/storage/home_snapshot_test.dart` continuaram verdes, incluindo limites civis do mês, janela de 30 dias, desempate e publicação coerente pós-transação.

### Controller, widgets, estados e acessibilidade

- RED: `home_screen_test.dart` não compilou porque `HomeController` e `HomeScreen` não existiam.
- O GREEN intermediário encontrou e corrigiu dois defeitos reais: cancelamento síncrono que bloqueava a troca de escopo e uso de `Expanded` sob altura ilimitada a 200% de texto.
- RED/GREEN adicional: affordance segmentada iOS exigiu `CupertinoSlidingSegmentedControl`; Android/Windows mantêm Material 3.
- RED/GREEN adicional: contraste AA exigiu um verde mineral próprio para canvas escuro.
- RED/GREEN adicional: a semântica de uma movimentação inicialmente omitiria o valor; agora anuncia descrição, tipo, categoria, owner, data e valor assinado, ou `Valor financeiro oculto`.
- GREEN final: 8 testes de tela cobrem loading sem cache, offline sem cache, offline/stale com cache, vazio, Lar/Eu/Esposa, sync failed com cache, valores ocultos e texto a 200%.

### Goldens

- RED: os quatro arquivos de referência não existiam.
- GREEN: mobile claro/escuro e Windows claro/escuro foram gerados com DPR 1 e família Segoe UI carregada explicitamente; Material Icons também é carregada explicitamente no harness.
- Os quatro testes golden passam sem atualização.

## Recálculo financeiro independente dos fixtures

Todos os valores abaixo estão em minor units e foram comparados diretamente com os resultados SQL:

| Escopo | Cálculo do saldo | Saldo | Gasto em agosto | Próximos 30 dias |
|---|---:|---:|---:|---:|
| Lar | `(10.000 + 20.000 + 30.000) + (5.000 + 4.000 + 3.000) - (1.000 + 2.000 + 1.500)` | `67.500` | `3.000` | `4.500` |
| Eu | `10.000 + 5.000 - 1.000` | `14.000` | `1.000` | `1.000` |
| Esposa | `20.000 + 4.000 - 2.000` | `22.000` | `2.000` | `2.000` |
| Conjunto (componente do Lar) | `30.000 + 3.000 - 1.500` | `31.500` | `0` | `1.500` |

O Lar é exatamente a soma dos três componentes. Cada saldo inicial aparece uma vez, e os dados de `Conjunto` não aparecem em `Eu` ou `Esposa`. O caminho financeiro usa `int`, SQL integer `SUM`, `~/` e `%`; não há `double` em `features/home` nem no formatador `FinancialAmount`.

## Arquitetura e comportamento

- `DriftHomeRepository` é a única implementação da leitura Home e depende somente de `AppDatabase`/Drift.
- Uma única `customSelect(...).watch()` observa accounts, categories, transactions, owners e sync state; a leitura agregada e recentes ocorre em uma transação SQLite coerente.
- A query usa somas inteiras e ordena recentes por `date DESC, updated_at DESC, uuid DESC`, com `LIMIT 5`.
- `hasAccountData` impede que o `COALESCE` interno vire `R$ 0,00` quando a origem de contas está ausente.
- `HomeController` resolve os owners locais, troca o escopo de toda a snapshot e ignora eventos tardios de uma assinatura anterior.
- A Home não chama rede. O retry autorizado delega ao `SyncState`/coordenador já existente, fora do repositório Home.
- A ocultação desta task é somente presentacional e testável. Persistência e app switcher permanecem explicitamente para a Task 8.

## Estados verificados

- loading sem cache;
- offline sem cache, com `Indisponível` e retry;
- offline/stale com cache e última sincronização;
- ledger vazio;
- Lar populado;
- Eu isolado;
- Esposa isolada;
- falha de sincronização com cache retido;
- valores ocultos sem remover contexto;
- escala de texto de 200% sem overflow;
- ausência de contas com atenção baseada em evidência;
- estado saudável sem seção de atenção inventada.

## Inspeção visual e Impeccable v4

Método: Flutter nativo, code-first, comparado à referência aprovada `docs/design-assets/casa-de-valores-home-reference.png`. O detector web não foi executado, conforme a regra do Impeccable para plataforma nativa.

### Rodada batched inicial

Os quatro PNGs foram abertos juntos. Gaps materiais encontrados:

1. o shell desktop não fornecia um canvas Material e deixava a área de conteúdo transparente;
2. o harness golden não carregava Material Icons;
3. o saldo ainda tinha pouca dominância em relação à referência;
4. a seleção escura não mantinha o papel restrito de champanhe;
5. o verde mineral original ficava fraco como texto positivo no canvas escuro.

### Onda única de correções

- `AdaptiveShell` desktop passou a fornecer `Scaffold`/canvas real;
- fonte de ícones foi fixada no harness;
- saldo principal ganhou escala responsiva de 40/48 px e algarismos tabulares;
- seleção recebeu tratamento champanhe coerente em claro/escuro;
- `mineralOnDark` foi adicionado e testado com razão de contraste >= 4,5:1;
- `FinancialAmount` passou a herdar corretamente família/cor do tema;
- a semântica completa do valor assinado foi adicionada sem alterar a composição.

### Confirmação e auto-review

A única confirmação visual mostrou:

- hierarquia na ordem exigida: sync/privacidade, seletor, saldo, compromissos/gasto, atenção quando comprovada, recentes;
- mobile em uma única scroll view com safe area e navegação compacta;
- Windows com leitura limitada e painel direito apenas quando existem movimentações reais;
- claro/escuro coerentes, sem roxo, glass, gradiente chamativo, card stacks ou hero-metric genérico;
- ausência de contagens falsas, chevrons mortos, `Ver todas` sem destino ou alertas inventados;
- receitas e despesas diferenciadas por sinal, rótulo e cor;
- foco/teclado e tooltips herdados dos controles nativos Material/Cupertino;
- texto a 200%, sem overflow, e ordem semântica igual à visual.

O finish reviewer do Impeccable foi substituído pela passagem inline degradada porque a execução recebeu proibição explícita de criar subagentes. Veredito: `disposition: ship`.

- persistence: pass — `PRODUCT.md` existe; esta é extensão do mundo aprovado, sem novo concept round ou alteração de `DESIGN.md`.
- fidelity: sync/privacy, seletor, saldo dominante, resumo e recentes são matches; omitir alerta sintético e destinos futuros é adaptação exigida por verdade de produto; tipografia workhorse é adaptação autorizada porque a tipografia gerada da referência não é autoridade.
- ceiling: reached — materiais planos institucionais, divisores, densidade e adaptação mobile/Windows foram usados sem simular material físico.
- material_fixes: nenhum aberto.
- keep: preservar a leitura contínua, o saldo dominante e a ausência deliberada de affordances sem destino.

Capturas finais para revisão:

- `.impeccable/review/mobile-light.png`
- `.impeccable/review/mobile-dark.png`
- `.impeccable/review/windows-light.png`
- `.impeccable/review/windows-dark.png`

Goldens versionados:

- `mobile/test/goldens/home_mobile_light.png`
- `mobile/test/goldens/home_mobile_dark.png`
- `mobile/test/goldens/home_windows_light.png`
- `mobile/test/goldens/home_windows_dark.png`

## Gates executados

| Gate | Resultado |
|---|---|
| `flutter test test/features/home` | PASS — 17 testes |
| `flutter test test/features/home/home_goldens_test.dart` | PASS — 4 goldens |
| `flutter test test/core/storage test/core/sync` | PASS — 59 testes |
| `flutter test test/app test/design_system test/widget_test.dart` | PASS — 20 testes direcionados |
| `flutter test` | PASS — 144 testes |
| `flutter analyze` | PASS — no issues found |
| `dart format --output=none --set-exit-if-changed lib test` | PASS — 61 arquivos, 0 alterações |
| `git diff --check` | PASS — sem erro de whitespace; somente avisos de normalização LF/CRLF do Git no Windows |
| `flutter build windows --debug` | PASS — `build/windows/x64/runner/Debug/lar_finance.exe` |
| `flutter build apk --debug` | PASS — `build/app/outputs/flutter-apk/app-debug.apk` |

Não foi alegado build iOS: esta máquina é Windows e não dispõe de Xcode/simulador Apple.

## Arquivos

### Criados

- `mobile/lib/features/home/domain/home_snapshot.dart`
- `mobile/lib/features/home/data/home_repository.dart`
- `mobile/lib/features/home/application/home_controller.dart`
- `mobile/lib/features/home/presentation/home_screen.dart`
- `mobile/lib/features/home/presentation/widgets/balance_header.dart`
- `mobile/lib/features/home/presentation/widgets/commitments_summary.dart`
- `mobile/lib/features/home/presentation/widgets/attention_list.dart`
- `mobile/lib/features/home/presentation/widgets/recent_transactions.dart`
- `mobile/test/features/home/home_repository_test.dart`
- `mobile/test/features/home/home_screen_test.dart`
- `mobile/test/features/home/home_goldens_test.dart`
- quatro goldens `mobile/test/goldens/home_*.png`
- `.superpowers/sdd/task-7-report.md`

### Modificados

- `mobile/lib/core/storage/local_ledger.dart`
- `mobile/lib/core/sync/sync_models.dart`
- `mobile/lib/app/router.dart`
- `mobile/lib/app/adaptive_shell.dart`
- `mobile/lib/main.dart`
- `mobile/lib/design_system/components/financial_amount.dart`
- `mobile/lib/design_system/components/owner_selector.dart`
- `mobile/lib/design_system/components/sync_status.dart`
- `mobile/lib/design_system/lar_colors.dart`
- `mobile/test/design_system/financial_amount_test.dart`
- `mobile/test/design_system/lar_theme_test.dart`

## Concerns

- O build APK passou, mas o Gradle emitiu avisos não bloqueantes sobre native access futuro e diferença entre a versão XML conhecida pelas command-line tools e a versão do Android SDK. Não afeta o artefato desta task, mas recomenda alinhamento das ferramentas Android em manutenção futura.
- A validação iOS real continua dependente de macOS/Xcode, conforme a spec.
- Persistência da preferência de ocultação e proteção no app switcher não foram implementadas deliberadamente; são Task 8.
- Nenhum concern funcional, financeiro, visual ou de acessibilidade permanece aberto para a Task 7.

---

## Onda consolidada de correções de review — 14/08/2026

### Findings verificados antes da edição

Os cinco achados foram confirmados no HEAD `3f8cc204a6f35aba680e9992a6265b23de803734` antes de alterar a implementação:

1. `HomeController` passava `_now()` uma única vez a `watchSnapshot`, congelando os limites civis usados pela consulta até uma troca manual de owner.
2. O SQL lia `t.type`, mas `HomeTransaction` conservava somente o valor assinado; a UI inferia tipo por `signedAmountMinor >= 0`, classificando despesa zero como receita.
3. `SyncStatusView` formatava diretamente o instante recebido, inclusive quando UTC.
4. O chrome compacto usava `NavigationBar` e `RefreshIndicator` Material também em iOS.
5. O thumb iOS escuro usava `#2F756A` sob texto `#E8E3D8`, com contraste calculado em aproximadamente 4,24:1.

### RED → GREEN

- **Virada civil:** RED de compilação por ausência de `timerFactory`; GREEN injeta relógio/timer determinísticos, agenda a próxima meia-noite local, cancela no `dispose`, recria a assinatura e reagenda. Um RED/GREEN complementar integrou a Home ao `AppSyncLifecycle` existente: ele publica uma geração de resume por `AppResumeScope`, e a Home refaz a projeção no foreground sem registrar um segundo observer, serviço ou background. Um teste cruza 14→15/08 e verifica atraso de 30 segundos e novo agendamento de 24 horas; outro cruza 31/08→01/09 no sinal de resume e comprova nova data de consulta, label `setembro` e agregado mensal alterado de `R$ 8,00` para `R$ 9,00`. O teste de lifecycle comprova que cada `AppLifecycleState.resumed` incrementa exatamente uma geração, independentemente do limiar de sync.
- **Tipo explícito:** RED por ausência de `HomeTransactionType`/`type`; GREEN converte `t.type` do SQLite para o enum de domínio e usa esse enum para rótulo, semântica e cor. Receita zero e despesa zero permanecem distintas com `signedAmountMinor == 0`; o teste de tela comprova rótulos e as cores mineral/on-surface corretas.
- **Horário local:** RED de widget para um instante UTC; GREEN aplica `lastSuccessAt.toLocal()` antes de `DateFormat`.
- **Chrome iOS:** RED encontrou zero `CupertinoTabBar` e manteve o refresh Material; GREEN usa `CupertinoTabBar` com símbolos do pacote oficial `cupertino_icons` e `CupertinoSliverRefreshControl` em um único `CustomScrollView`. Android/Windows continuam com `NavigationBar` e `RefreshIndicator`. Testes exercitam tap em `Mais` e gesto de pull-to-refresh.
- **Contraste:** RED mediu 4,236:1; GREEN usa o thumb champanhe profundo `#4B4027`, com contraste superior a 4,5:1 sob o texto de 13 px, coberto por teste automatizado.

### Goldens e revisão Impeccable/native

- RED visual: `home_ios_light.png` e `home_ios_dark.png` não existiam; os quatro baselines Android/Windows passaram sem diferença.
- GREEN visual: seis goldens passam com tamanho `390×844` para Android/iOS e `1366×768` para Windows, DPR 1 e fontes fixas. O harness carrega Material Icons, Cupertino Icons e fonte de texto determinística.
- Uma inspeção batched comparou referência aprovada + Android claro/escuro + iOS claro/escuro + Windows claro/escuro. A única lacuna material encontrada foram rótulos Ahem no tab bar iOS do harness; a correção consolidada aplicou `CupertinoTextThemeData` com a fonte golden. A única confirmação visual verificou os dois PNGs iOS corrigidos; nenhum polish loop adicional foi feito.
- Capturas anteriores preservadas: `.impeccable/review/mobile-light.png`, `mobile-dark.png`, `windows-light.png`, `windows-dark.png`.
- Capturas novas: `.impeccable/review/ios-light.png` e `.impeccable/review/ios-dark.png`.
- Resultado da auto-revisão: hierarquia e densidade preservadas; sem affordance falsa, roxo, glass, alerta inventado ou AI slop. Touch targets/controles permanecem adaptativos, 200% de texto continua coberto e o contraste do estado selecionado iOS está acima de AA.
- As capturas iOS são goldens determinísticos de Flutter em Windows, não screenshots de Simulator. Validação em Simulator/hardware continua indisponível nesta máquina e não foi alegada.

### Gates finais desta onda

| Gate | Resultado |
| --- | --- |
| RED focado inicial | FAIL esperado — domínio/timer ausentes; tab bar/contraste falharam |
| GREEN funcional focado | PASS — 32 testes |
| `flutter test test/features/home/home_goldens_test.dart` | PASS — 6 goldens |
| suíte focada Home/app/design system/storage/sync | PASS — 106 testes |
| `flutter test` | PASS — 154 testes |
| `flutter analyze` | PASS — nenhum issue |
| `dart format --output=none --set-exit-if-changed lib test` | PASS — 61 arquivos, 0 alterações |
| `git diff --check` | PASS — sem erro de whitespace; apenas avisos LF/CRLF do Git no Windows |
| varreduras `double`, rede na Home e roxo | PASS — nenhuma ocorrência |
| `flutter build windows --debug` | PASS — `build/windows/x64/runner/Debug/lar_finance.exe` |
| `flutter build apk --debug` | PASS — `build/app/outputs/flutter-apk/app-debug.apk` |

### Arquivos desta onda

- Lifecycle/período: `mobile/lib/app/app_lifecycle.dart`, `mobile/lib/features/home/application/home_controller.dart`, `mobile/lib/features/home/presentation/home_screen.dart`.
- Tipo explícito: `mobile/lib/features/home/domain/home_snapshot.dart`, `mobile/lib/features/home/data/home_repository.dart`, `mobile/lib/features/home/presentation/widgets/recent_transactions.dart`.
- iOS/contraste/freshness: `mobile/lib/app/lar_bottom_navigation.dart`, `mobile/lib/design_system/components/owner_selector.dart`, `mobile/lib/design_system/components/sync_status.dart`, `mobile/lib/design_system/lar_colors.dart`.
- Dependência nativa: `mobile/pubspec.yaml`, `mobile/pubspec.lock` (`cupertino_icons 1.0.9`).
- Testes: `mobile/test/features/home/home_repository_test.dart`, `home_screen_test.dart`, `home_goldens_test.dart`, `mobile/test/design_system/financial_amount_test.dart`, `mobile/test/app/adaptive_shell_test.dart`, `mobile/test/core/sync/sync_lifecycle_test.dart`.
- Novos baselines: `mobile/test/goldens/home_ios_light.png`, `mobile/test/goldens/home_ios_dark.png`.

### Concerns após review

- O APK passou com o mesmo aviso não bloqueante de native access futuro do Gradle/JVM.
- Build, Simulator e hardware iOS continuam dependentes de macOS/Xcode; somente o comportamento adaptativo e os goldens iOS determinísticos foram validados no Windows.
- Persistência de privacidade e proteção do app switcher continuam explicitamente fora desta onda e pertencem à Task 8.
- Nenhum finding material desta revisão permanece aberto.
