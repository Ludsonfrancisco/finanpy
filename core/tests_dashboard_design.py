import re
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
        self.assertNotIn('Posição financeira', self.template)

    def test_dashboard_uses_tokens_without_structural_hex_or_glow(self):
        self.assertNotRegex(self.template, r'#[0-9A-Fa-f]{3,8}\b')
        self.assertNotIn('bg-gradient-', self.template)
        self.assertNotIn('shadow-glow-', self.template)
        self.assertNotRegex(self.template, r'(?i)\b(?:purple|violet)\b')
        for utility in (
            'bg-lar-surface',
            'bg-lar-card',
            'border-lar-border',
            'text-lar-textPrimary',
            'text-lar-textSecondary',
        ):
            self.assertIn(utility, self.template)

    def test_negative_free_cash_balance_uses_danger_token(self):
        conditional = (
            "{% if free_cash_balance >= 0 %}text-lar-textPrimary"
            "{% else %}text-danger-light{% endif %}"
        )
        self.assertIn(conditional, self.template)

    def test_existing_dashboard_actions_and_analytics_remain_available(self):
        for value in (
            "{% url 'transactions:import_ofx' %}",
            "{% url 'transactions:list' %}",
            'monthlyFlowChart',
            'categoryDonutChart',
            'daily_burn_rate',
        ):
            self.assertIn(value, self.template)

    def test_visible_monetary_values_require_grouped_pt_br_format(self):
        monetary_values = re.findall(
            r'R\$&nbsp;{{[^}\r\n]+}}',
            self.template,
        )

        self.assertGreater(len(monetary_values), 0)
        for monetary_value in monetary_values:
            with self.subTest(monetary_value=monetary_value):
                self.assertRegex(
                    monetary_value,
                    r'\|floatformat:"2g"\s*}}$',
                )
