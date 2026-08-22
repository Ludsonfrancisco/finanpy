# Dashboard/Home Visual Parity Implementation Plan

**Status:** concluído

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Reorganizar a Dashboard Web e a Home Flutter para compartilharem hierarquia, superfícies e leitura financeira perceptivelmente iguais, sem alterar backend ou sincronização.

**Architecture:** O template Web continuará consumindo o contexto atual de `DashboardView`, mas sua primeira dobra será reordenada e tokenizada. O Flutter continuará consumindo `HomeSnapshot`; componentes visuais reutilizáveis transformarão saldo, compromissos, gasto e movimentações em superfícies Casa de Valores responsivas. Conteúdo analítico sem equivalente no snapshot permanece somente na Web, abaixo da hierarquia comum.

**Tech Stack:** Django 5.2.13, Django Templates, Tailwind CDN atual, CSS tokens `--lar-*`, Flutter 3.47.0, Dart 3.13.0, Material 3, flutter_test e golden tests.

## Global Constraints

- Escopo exclusivo: `Dashboard Web` e `Home Flutter`.
- Não alterar models, migrations, endpoints, serializers, sync, rotas ou navegação.
- Não exibir `Saldo Livre Real` no Flutter usando `balanceMinor` como substituto.
- Usar breakpoint estrutural `900 px` por `LarBreakpoints.desktop`.
- Preservar loading, offline, erro, retry, privacidade, teclado e pull-to-refresh.
- Não usar roxo, gradiente estrutural ou `shadow-glow-*`.
- Web pode manter análises adicionais somente abaixo da primeira hierarquia.
- Cada task termina com commit e push da branch de implementação.
- Não iniciar outra tela ou sprint após este plano.

## File Structure

| Arquivo | Responsabilidade |
|---|---|
| `core/tests_dashboard_design.py` | contrato estrutural e visual estático da Dashboard |
| `templates/dashboard/index.html` | hierarquia, composição responsiva e conteúdo analítico Web |
| `mobile/lib/design_system/lar_radius.dart` | fachada pública dos raios gerados |
| `mobile/lib/features/home/presentation/widgets/home_financial_surface.dart` | superfície reutilizável dos cards da Home |
| `mobile/lib/features/home/presentation/widgets/balance_header.dart` | card dominante de saldo consolidado |
| `mobile/lib/features/home/presentation/widgets/commitments_summary.dart` | cards de compromissos e gasto mensal |
| `mobile/lib/features/home/presentation/widgets/recent_transactions.dart` | painel e linhas de movimentações recentes |
| `mobile/lib/features/home/presentation/home_screen.dart` | ordem e composição compacto/amplo |
| `mobile/test/design_system/lar_theme_test.dart` | contrato da fachada `LarRadius` |
| `mobile/test/features/home/home_screen_test.dart` | comportamento e responsividade da nova hierarquia |
| `mobile/test/features/home/home_goldens_test.dart` | referências visuais multiplataforma |
| `mobile/test/goldens/home_*.png` | seis baselines atualizados |
| `docs/ROADMAP.md` | fechamento da R3.2 com evidências |

---

### Task 1: Redesenhar a Dashboard Web com hierarquia compartilhada

**Files:**
- Create: `core/tests_dashboard_design.py`
- Modify: `templates/dashboard/index.html`

**Interfaces:**
- Consumes: contexto atual de `core.views.DashboardView` sem novos campos.
- Produces: seções ordenadas por `data-dashboard-section` e Dashboard sem hex estrutural, gradiente ou glow.

- [x] **Step 1: escrever os testes vermelhos do contrato visual Web**

```python
from pathlib import Path

from django.test import SimpleTestCase


PROJECT_ROOT = Path(__file__).resolve().parents[1]
DASHBOARD = PROJECT_ROOT / 'templates' / 'dashboard' / 'index.html'


class DashboardVisualParityTest(SimpleTestCase):
    def setUp(self):
        self.template = DASHBOARD.read_text(encoding='utf-8')

    def test_shared_financial_hierarchy_is_explicit_and_ordered(self):
        sections = (
            'context',
            'owner',
            'position',
            'commitments',
            'recent',
            'analytics',
        )
        positions = [
            self.template.index(f'data-dashboard-section="{section}"')
            for section in sections
        ]
        self.assertEqual(positions, sorted(positions))

    def test_dashboard_uses_tokens_without_structural_hex_or_glow(self):
        self.assertNotRegex(self.template, r'#[0-9A-Fa-f]{3,8}\b')
        self.assertNotIn('bg-gradient-', self.template)
        self.assertNotIn('shadow-glow-', self.template)
        for utility in (
            'bg-lar-surface',
            'bg-lar-card',
            'border-lar-border',
            'text-lar-textPrimary',
            'text-lar-textSecondary',
        ):
            self.assertIn(utility, self.template)

    def test_existing_dashboard_actions_and_analytics_remain_available(self):
        for value in (
            "{% url 'transactions:import_ofx' %}",
            "{% url 'transactions:list' %}",
            'monthlyFlowChart',
            'categoryDonutChart',
            'daily_burn_rate',
        ):
            self.assertIn(value, self.template)
```

- [x] **Step 2: executar os testes e confirmar a falha correta**

Run:

```powershell
$env:SECRET_KEY='dashboard-design-test-secret'; python manage.py test core.tests_dashboard_design -v 2
```

Expected: FAIL porque `data-dashboard-section` não existe e o template ainda contém hex, gradiente e glow.

- [x] **Step 3: substituir a primeira hierarquia da Dashboard**

Aplicar em `templates/dashboard/index.html` esta estrutura antes dos blocos analíticos atuais:

```html
<header data-dashboard-section="context"
        class="mb-6 flex flex-col gap-4 lg:flex-row lg:items-end lg:justify-between">
  <div>
    <p class="mb-2 text-xs font-semibold uppercase tracking-[0.18em] text-champagne">Posição financeira</p>
    <h1 class="text-3xl font-semibold tracking-tight text-lar-textPrimary">Visão do Lar</h1>
    <p class="mt-1 text-sm text-lar-textSecondary">Saldo, compromissos e atividade recente em uma leitura.</p>
  </div>
  <a href="{% url 'transactions:import_ofx' %}"
     class="inline-flex min-h-11 items-center justify-center gap-2 rounded-xl border border-mineral/40 bg-mineral/15 px-4 py-2 text-sm font-semibold text-mineral-light transition hover:bg-mineral/25 hover:text-white">
    <span>Importar OFX</span>
  </a>
</header>

<nav data-dashboard-section="owner" aria-label="Responsável financeiro"
     class="mb-6 inline-flex max-w-full gap-1 overflow-x-auto rounded-xl border border-lar-border bg-lar-surface p-1">
  <a href="?owner=household"
     class="rounded-lg px-4 py-2 text-xs font-semibold transition {% if owner_filter == 'household' or not owner_filter %}bg-mineral text-white{% else %}text-lar-textSecondary hover:bg-lar-card hover:text-lar-textPrimary{% endif %}">
    Lar (Geral)
  </a>
  <a href="?owner=self"
     class="rounded-lg px-4 py-2 text-xs font-semibold transition {% if owner_filter == 'self' %}bg-mineral text-white{% else %}text-lar-textSecondary hover:bg-lar-card hover:text-lar-textPrimary{% endif %}">
    Eu
  </a>
  <a href="?owner=spouse"
     class="rounded-lg px-4 py-2 text-xs font-semibold transition {% if owner_filter == 'spouse' %}bg-mineral text-white{% else %}text-lar-textSecondary hover:bg-lar-card hover:text-lar-textPrimary{% endif %}">
    Esposa
  </a>
</nav>

<section data-dashboard-section="position" aria-labelledby="position-title"
         class="mb-5 overflow-hidden rounded-2xl border border-mineral/40 bg-lar-card p-6 lg:p-7">
  <p id="position-title" class="text-xs font-semibold uppercase tracking-[0.16em] text-mineral-light">Saldo Livre Real</p>
  <p class="mt-3 text-4xl font-semibold tracking-tight text-lar-textPrimary tabular-nums lg:text-5xl">
    R$&nbsp;{{ free_cash_balance|floatformat:2 }}
  </p>
  <p class="mt-3 max-w-2xl text-sm leading-6 text-lar-textSecondary">
    Saldo em contas de R$&nbsp;{{ total_balance|floatformat:2 }}, descontando
    R$&nbsp;{{ pending_bills_total|floatformat:2 }} em compromissos do mês.
  </p>
</section>

<section data-dashboard-section="commitments" aria-label="Resumo do mês"
         class="mb-6 grid grid-cols-1 gap-4 sm:grid-cols-2">
  <article class="rounded-2xl border border-lar-border bg-lar-card p-5">
    <p class="text-xs font-semibold uppercase tracking-[0.14em] text-lar-textSecondary">Compromissos próximos</p>
    <p class="mt-3 text-2xl font-semibold text-lar-textPrimary tabular-nums">R$&nbsp;{{ pending_bills_total|floatformat:2 }}</p>
    <a href="{% url 'bills:list' %}" class="mt-4 inline-flex text-sm font-semibold text-mineral-light">Ver contas fixas</a>
  </article>
  <article class="rounded-2xl border border-lar-border bg-lar-card p-5">
    <p class="text-xs font-semibold uppercase tracking-[0.14em] text-lar-textSecondary">Gasto do mês</p>
    <p class="mt-3 text-2xl font-semibold text-danger-light tabular-nums">R$&nbsp;{{ monthly_expenses|floatformat:2 }}</p>
    <a href="{% url 'transactions:list' %}" class="mt-4 inline-flex text-sm font-semibold text-mineral-light">Ver movimentações</a>
  </article>
</section>
```

Não inserir comentários HTML substituindo conteúdo. Manter os links `Lar (Geral)`, `Eu` e `Esposa` completos no `nav`.

- [x] **Step 4: tokenizar e reordenar os blocos existentes**

Aplicar as seguintes regras em todo o template:

```text
#1A221E, #171F1B, #161E1A, #121815, #222C27 -> bg-lar-card/bg-lar-surface conforme elevação
#28352E, #384A41, #24302A -> border-lar-border/border-lar-borderHover
#E8ECE9 -> text-lar-textPrimary
#8D958D -> text-lar-textSecondary
bg-gradient-* e shadow-glow-* -> remover
rounded-2xl permanece nos painéis; badges internos usam rounded-lg ou rounded-full
```

Adicionar `data-dashboard-section="recent"` e `aria-labelledby="recent-title"` à seção completa que já renderiza `recent_transactions`. Adicionar `id="recent-title"` ao título visível dessa seção. Envolver todos os blocos seguintes em uma seção completa com `data-dashboard-section="analytics"` e `aria-label="Análises financeiras"`. `recent` deve anteceder `analytics` no arquivo. Dentro de `analytics`, preservar `daily_burn_rate`, os quatro indicadores, `monthlyFlowChart`, `categoryDonutChart` e maiores gastos.

No JavaScript, obter cores por CSS em vez de hex:

```javascript
const larStyles = getComputedStyle(document.documentElement);
const chartColors = {
  mineral: larStyles.getPropertyValue('--lar-color-mineral').trim(),
  danger: larStyles.getPropertyValue('--lar-color-danger').trim(),
  text: larStyles.getPropertyValue('--lar-color-text-secondary').trim(),
  border: larStyles.getPropertyValue('--lar-color-border-default').trim(),
};
```

- [x] **Step 5: executar testes Web focados e Django completo**

Run:

```powershell
$env:SECRET_KEY='dashboard-design-test-secret'; python manage.py test core.tests_dashboard_design core.tests.DashboardHouseholdScopeTest -v 2
ruff check core/tests_dashboard_design.py --config pyproject.toml
```

Expected: todos passam; nenhum campo de contexto ou comportamento muda.

- [x] **Step 6: commit e push da Dashboard Web**

```powershell
git add core/tests_dashboard_design.py templates/dashboard/index.html
git diff --cached --check
git commit -m "feat(web): redesign financial dashboard hierarchy"
git push origin codex/r3-2-dashboard-home-parity
```

---

### Task 2: Criar as superfícies financeiras reutilizáveis do Flutter

**Files:**
- Create: `mobile/lib/design_system/lar_radius.dart`
- Create: `mobile/lib/features/home/presentation/widgets/home_financial_surface.dart`
- Modify: `mobile/test/design_system/lar_theme_test.dart`
- Modify: `mobile/test/features/home/home_screen_test.dart`

**Interfaces:**
- Consumes: `LarGeneratedRadius`, `LarSpacing` e `ThemeData.colorScheme`.
- Produces: `LarRadius` e `HomeFinancialSurface({required Widget child, Color? accentColor, EdgeInsetsGeometry padding, Key? key})`.

- [x] **Step 1: escrever os testes vermelhos da fachada e da superfície**

Adicionar a `mobile/test/design_system/lar_theme_test.dart`:

```dart
import 'package:lar_finance/design_system/lar_radius.dart';
import 'package:lar_finance/design_system/lar_tokens.g.dart';

test('public radius facade consumes generated tokens', () {
  expect(LarRadius.md, LarGeneratedRadius.md);
  expect(LarRadius.lg, LarGeneratedRadius.lg);
  expect(LarRadius.pill, LarGeneratedRadius.pill);
});
```

Adicionar a `mobile/test/features/home/home_screen_test.dart`:

```dart
testWidgets('financial hierarchy uses one dominant and two supporting surfaces', (
  tester,
) async {
  final controller = _controller(
    _FakeHomeRepository(
      streams: {OwnerScopeKind.household: Stream.value(_snapshot())},
    ),
  );
  addTearDown(controller.dispose);

  await _pumpHome(tester, controller);

  expect(find.byKey(const Key('home-position-card')), findsOneWidget);
  expect(find.byKey(const Key('home-commitment-card')), findsOneWidget);
  expect(find.byKey(const Key('home-expense-card')), findsOneWidget);
});
```

- [x] **Step 2: executar e confirmar falha por símbolos/keys ausentes**

```powershell
Set-Location mobile
flutter test test/design_system/lar_theme_test.dart test/features/home/home_screen_test.dart
```

Expected: FAIL porque `lar_radius.dart` e as três keys ainda não existem.

- [x] **Step 3: implementar `LarRadius`**

```dart
import 'lar_tokens.g.dart';

abstract final class LarRadius {
  static const double sm = LarGeneratedRadius.sm,
      md = LarGeneratedRadius.md,
      lg = LarGeneratedRadius.lg,
      pill = LarGeneratedRadius.pill;
}
```

- [x] **Step 4: implementar `HomeFinancialSurface`**

```dart
import 'package:flutter/material.dart';

import '../../../../design_system/lar_radius.dart';
import '../../../../design_system/lar_spacing.dart';

final class HomeFinancialSurface extends StatelessWidget {
  const HomeFinancialSurface({
    required this.child,
    this.accentColor,
    this.padding = const EdgeInsets.all(LarSpacing.lg),
    super.key,
  });

  final Widget child;
  final Color? accentColor;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final border = accentColor ?? theme.dividerColor;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border.all(color: border.withValues(alpha: 0.55)),
        borderRadius: BorderRadius.circular(LarRadius.lg),
      ),
      child: Padding(padding: padding, child: child),
    );
  }
}
```

- [x] **Step 5: executar testes da fachada e formatação**

```powershell
dart format --output=none --set-exit-if-changed lib/design_system/lar_radius.dart lib/features/home/presentation/widgets/home_financial_surface.dart test/design_system/lar_theme_test.dart test/features/home/home_screen_test.dart
flutter test test/design_system/lar_theme_test.dart
```

Expected: fachada passa; teste de hierarquia continua vermelho até Task 3.

- [x] **Step 6: commit e push dos primitivos Flutter**

```powershell
Set-Location ..
git add mobile/lib/design_system/lar_radius.dart mobile/lib/features/home/presentation/widgets/home_financial_surface.dart mobile/test/design_system/lar_theme_test.dart mobile/test/features/home/home_screen_test.dart
git diff --cached --check
git commit -m "feat(mobile): add financial home surfaces"
git push origin codex/r3-2-dashboard-home-parity
```

---

### Task 3: Redesenhar a Home Flutter em compacto e amplo

**Files:**
- Modify: `mobile/lib/features/home/presentation/home_screen.dart`
- Modify: `mobile/lib/features/home/presentation/widgets/balance_header.dart`
- Modify: `mobile/lib/features/home/presentation/widgets/commitments_summary.dart`
- Modify: `mobile/lib/features/home/presentation/widgets/recent_transactions.dart`
- Modify: `mobile/test/features/home/home_screen_test.dart`
- Modify: `mobile/test/goldens/home_mobile_light.png`
- Modify: `mobile/test/goldens/home_mobile_dark.png`
- Modify: `mobile/test/goldens/home_ios_light.png`
- Modify: `mobile/test/goldens/home_ios_dark.png`
- Modify: `mobile/test/goldens/home_windows_light.png`
- Modify: `mobile/test/goldens/home_windows_dark.png`

**Interfaces:**
- Consumes: `HomeFinancialSurface`, `HomeSnapshot`, `FinancialAmount`, `LarBreakpoints.desktop`.
- Produces: primeira hierarquia com keys `home-position-card`, `home-commitment-card`, `home-expense-card` e `home-recent-card`.

- [x] **Step 1: completar testes vermelhos de ordem e responsividade**

Adicionar a `home_screen_test.dart`:

```dart
testWidgets('compact home preserves shared financial order without overflow', (
  tester,
) async {
  final controller = _controller(
    _FakeHomeRepository(
      streams: {OwnerScopeKind.household: Stream.value(_snapshot())},
    ),
  );
  addTearDown(controller.dispose);

  await _pumpHome(tester, controller, viewportSize: const Size(390, 1200));

  final keys = <Key>[
    const Key('home-position-card'),
    const Key('home-commitment-card'),
    const Key('home-expense-card'),
    const Key('home-recent-card'),
  ];
  final tops = keys.map((key) => tester.getTopLeft(find.byKey(key)).dy).toList();
  expect(tops, orderedEquals(tops.toList()..sort()));
  expect(tester.takeException(), isNull);
});

testWidgets('desktop home keeps metrics beside position and recent activity visible', (
  tester,
) async {
  final controller = _controller(
    _FakeHomeRepository(
      streams: {OwnerScopeKind.household: Stream.value(_snapshot())},
    ),
  );
  addTearDown(controller.dispose);

  await _pumpHome(
    tester,
    controller,
    platform: TargetPlatform.windows,
    viewportSize: const Size(1366, 900),
  );

  final position = tester.getRect(find.byKey(const Key('home-position-card')));
  final commitment = tester.getRect(find.byKey(const Key('home-commitment-card')));
  expect(commitment.left, greaterThan(position.left));
  expect(find.byKey(const Key('home-recent-card')), findsOneWidget);
  expect(tester.takeException(), isNull);
});
```

- [x] **Step 2: executar os testes focados e confirmar falha**

```powershell
Set-Location mobile
flutter test test/features/home/home_screen_test.dart
```

Expected: FAIL por ausência das keys e composição antiga.

- [x] **Step 3: transformar `BalanceHeader` no card dominante**

O eyebrow redundante `Posição financeira` foi removido na revisão visual
aprovada; `Saldo consolidado` inicia diretamente a hierarquia do card.

Envolver o conteúdo atual em:

```dart
HomeFinancialSurface(
  key: const Key('home-position-card'),
  accentColor: Theme.of(context).brightness == Brightness.dark
      ? LarColors.mineralOnDark
      : LarColors.mineral,
  padding: const EdgeInsets.all(LarSpacing.xl),
  child: Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: <Widget>[
      Text('Saldo consolidado', style: textTheme.titleMedium),
      const SizedBox(height: LarSpacing.md),
      financialAmount,
      const SizedBox(height: LarSpacing.sm),
      Text('Soma das contas disponíveis neste responsável.', style: textTheme.bodySmall),
    ],
  ),
)
```

`financialAmount` é o `LayoutBuilder`/`FinancialAmount` atual, sem alterar valor, privacidade ou semântica.

- [x] **Step 4: transformar compromissos e gasto em cards de apoio**

Em `_SummaryValue`, adicionar `required Key cardKey` e `required Color accentColor`; retornar:

```dart
HomeFinancialSurface(
  key: cardKey,
  accentColor: accentColor,
  child: Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: <Widget>[
      Text(label, style: Theme.of(context).textTheme.labelLarge),
      const SizedBox(height: LarSpacing.md),
      FinancialAmount(
        minorUnits: minorUnits,
        hidden: hidden,
        style: Theme.of(context).textTheme.titleLarge?.copyWith(
          fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
          fontWeight: FontWeight.w600,
        ),
      ),
    ],
  ),
)
```

Instanciar `home-commitment-card` com champanhe e `home-expense-card` com danger. Em texto ampliado ou largura menor que `560`, empilhar; caso contrário, manter `Row`.

- [x] **Step 5: transformar movimentações em painel financeiro**

Envolver a coluna de `RecentTransactions` em:

```dart
HomeFinancialSurface(
  key: const Key('home-recent-card'),
  padding: const EdgeInsets.all(LarSpacing.xl),
  child: Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: <Widget>[
      Text('Movimentações recentes', style: Theme.of(context).textTheme.titleLarge),
      const SizedBox(height: LarSpacing.xs),
      Text('Últimas atividades do responsável selecionado', style: Theme.of(context).textTheme.bodySmall),
      const SizedBox(height: LarSpacing.md),
      if (transactions.isEmpty)
        const Text('Nenhuma movimentação neste período')
      else
        for (var index = 0; index < transactions.length; index++) ...[
          _TransactionRow(transaction: transactions[index], hidden: hidden),
          if (index < transactions.length - 1) const Divider(height: 1),
        ],
    ],
  ),
)
```

Preservar integralmente `_TransactionRow`, inclusive semântica, valor assinado, quebra em texto ampliado e divisores.

- [x] **Step 6: reorganizar `_SnapshotContent` para compacto e desktop**

Compacto:

```dart
Column(
  crossAxisAlignment: CrossAxisAlignment.stretch,
  children: <Widget>[
    main,
    const SizedBox(height: LarSpacing.lg),
    RecentTransactions(transactions: recent, hidden: hidden),
  ],
)
```

Desktop: retornar uma `Column` com uma `Row` no topo. Nessa `Row`, posicionar o `BalanceHeader` atual em `Expanded(flex: 5)` e o `CommitmentsSummary` atual em `Expanded(flex: 4)`, separados por `LarSpacing.lg`. Abaixo da `Row`, renderizar o mesmo bloco atual de `AttentionList` e `sync-retry` quando `messages` não estiver vazio; depois de `LarSpacing.lg`, renderizar `RecentTransactions(transactions: recent, hidden: hidden)` ocupando toda a largura. Extrair o bloco de atenção para um widget privado `_AttentionSection` com parâmetros `messages`, `showRetry`, `onRetry` e `retryFocusNode`, de modo que compacto e desktop usem a mesma implementação. Não usar `IntrinsicHeight`; cards de apoio devem se ajustar naturalmente.

- [x] **Step 7: executar testes Flutter focados e acessibilidade**

```powershell
dart format --output=none --set-exit-if-changed lib/features/home test/features/home test/design_system/lar_theme_test.dart
flutter analyze
flutter test test/features/home/home_screen_test.dart test/accessibility/home_accessibility_test.dart test/design_system/lar_theme_test.dart
```

Expected: todos passam, sem overflow em 320 px/200% e sem regressão de foco.

- [x] **Step 8: gerar, inspecionar, verificar e stagear os seis goldens da Home**

```powershell
flutter test --update-goldens test/features/home/home_goldens_test.dart
flutter test test/features/home/home_goldens_test.dart
```

Expected: os seis renders de Android, iOS e Windows passam 6/6 em claro e escuro. Inspecionar cada PNG e confirmar a hierarquia aprovada, ausência de overflow, roxo, glow, gradiente e texto sobreposto. Não aprovar baseline apenas porque o teste foi atualizado.

Somente após a aprovação visual dos seis PNGs:

```powershell
Set-Location ..
git add mobile/test/goldens/home_mobile_light.png mobile/test/goldens/home_mobile_dark.png mobile/test/goldens/home_ios_light.png mobile/test/goldens/home_ios_dark.png mobile/test/goldens/home_windows_light.png mobile/test/goldens/home_windows_dark.png
```

Expected: somente as seis baselines inspecionadas ficam staged junto da implementação da Task 3.

- [x] **Step 9: commit e push da Home Flutter**

```powershell
git add mobile/lib/features/home/presentation mobile/test/features/home/home_screen_test.dart mobile/test/design_system/lar_theme_test.dart mobile/test/goldens/home_*.png
git diff --cached --check
git commit -m "feat(mobile): align home with web dashboard"
git push origin codex/r3-2-dashboard-home-parity
```

---

### Task 4: Revalidar goldens, validar visual real e fechar R3.2

**Files:**
- Verify; modify only if inspection rejects: `mobile/test/goldens/home_mobile_light.png`
- Verify; modify only if inspection rejects: `mobile/test/goldens/home_mobile_dark.png`
- Verify; modify only if inspection rejects: `mobile/test/goldens/home_ios_light.png`
- Verify; modify only if inspection rejects: `mobile/test/goldens/home_ios_dark.png`
- Verify; modify only if inspection rejects: `mobile/test/goldens/home_windows_light.png`
- Verify; modify only if inspection rejects: `mobile/test/goldens/home_windows_dark.png`
- Modify: `docs/ROADMAP.md`
- Modify: `docs/superpowers/specs/2026-08-22-dashboard-home-visual-parity-design.md`
- Modify: `docs/superpowers/plans/2026-08-22-dashboard-home-visual-parity-implementation.md`

**Interfaces:**
- Consumes: Dashboard/Home implementadas e fixtures determinísticas existentes.
- Produces: gate independente sobre as seis referências visuais aprovadas na Task 3, evidência Web em três larguras e documentação fechada.

- [x] **Step 1: reexecutar os seis goldens como gate independente**

```powershell
Set-Location mobile
flutter test test/features/home/home_goldens_test.dart
```

Expected: os seis testes passam 6/6 sem atualizar baselines.

- [x] **Step 2: inspecionar cada golden**

Verificar em claro/escuro:

```text
mobile Android 390x844: posição -> métricas -> recentes, sem corte
iOS 390x844: mesma hierarquia, SafeArea e composição nativa
Windows 1366x768: posição e métricas em faixa ampla; recentes visível
nenhum roxo, glow, gradiente ou texto sobreposto
```

Se qualquer item falhar, e somente nesse caso, corrigir o componente, executar os testes focados, gerar novamente os seis goldens e repetir a inspeção. Não aprovar baseline apenas porque o teste foi atualizado.

- [x] **Step 3: provar que uma nova geração não altera os goldens aprovados**

```powershell
$goldenChanges = git status --porcelain -- 'test/goldens/home_*.png'
if ($goldenChanges) { throw 'Goldens devem estar limpos antes do gate determinístico' }
flutter test --update-goldens test/features/home/home_goldens_test.dart
git diff --exit-code HEAD -- 'test/goldens/home_*.png'
```

Expected: nova geração passa 6/6 e `git diff` retorna zero sem mudança nos seis PNGs aprovados. Se a inspeção do Step 2 tiver reprovado, primeiro corrigir e aprovar visualmente a nova geração; somente então atualizar/stagear as baselines corrigidas e repetir este gate até uma geração subsequente não produzir diff.

- [x] **Step 4: executar a aplicação Web e capturar três larguras autenticadas**

```powershell
Set-Location ..
$env:SECRET_KEY='dashboard-visual-local-secret'; $env:DEBUG='True'; python manage.py runserver 127.0.0.1:8000
```

No navegador autenticado, verificar `/dashboard/` em `375`, `900` e `1280 px`:

```text
ordem: context -> owner -> position -> commitments -> recent -> analytics
sem overflow horizontal
ações Importar OFX, Ver contas fixas e Ver movimentações navegáveis
gráficos ainda renderizados
console sem erro novo
```

- [x] **Step 5: executar todos os gates locais**

Backend:

```powershell
$env:SECRET_KEY='dashboard-final-verification-secret'; $env:DEBUG='False'
python scripts/generate_design_tokens.py --check
ruff check . --config pyproject.toml
python manage.py check
python manage.py makemigrations --check
python manage.py test
```

Flutter:

```powershell
Set-Location mobile
dart format --output=none --set-exit-if-changed .
flutter analyze
flutter test --exclude-tags=golden
flutter test --tags=golden test/features/home/home_goldens_test.dart
```

Expected: zero falhas; Django deve ter pelo menos 604 testes e Flutter sem golden pelo menos 365.

- [x] **Step 6: fechar documentos sem iniciar outra task**

Em `docs/ROADMAP.md`, marcar apenas `R3.2 Dashboard/Home` como concluída e registrar commits, testes, screenshots e CI. Na especificação e neste plano, alterar `Status` para `concluído` e marcar todos os checkboxes executados.

- [x] **Step 7: commit e push de fechamento**

```powershell
Set-Location ..
git add mobile/test/goldens/home_*.png docs/ROADMAP.md docs/superpowers/specs/2026-08-22-dashboard-home-visual-parity-design.md docs/superpowers/plans/2026-08-22-dashboard-home-visual-parity-implementation.md
git diff --cached --check
git commit -m "docs: close dashboard home visual parity"
git push origin codex/r3-2-dashboard-home-parity
```

- [x] **Step 8: aguardar CI exata da branch**

```powershell
$sha = git rev-parse HEAD
$run = gh run list --branch codex/r3-2-dashboard-home-parity --workflow CI --limit 1 --json databaseId,headSha,status,conclusion,url | ConvertFrom-Json
if ($run.headSha -ne $sha) { throw 'CI não corresponde ao HEAD' }
gh run watch $run.databaseId --exit-status
```

Expected: Django, Flutter, Windows/MSIX, Android, iOS e secret scan verdes no HEAD exato.

- [x] **Step 9: comunicar resultado e parar**

Informar objetivamente: telas alteradas, evidências visuais, contagem de testes, commits, branch e CI. Não mesclar, implantar ou iniciar R3.3 sem autorização explícita.
