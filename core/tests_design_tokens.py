import copy
import importlib.util
import tempfile
from pathlib import Path

from django.test import SimpleTestCase

PROJECT_ROOT = Path(__file__).resolve().parents[1]
CONTRACT_PATH = PROJECT_ROOT / 'design' / 'tokens.json'
GENERATOR_PATH = PROJECT_ROOT / 'scripts' / 'generate_design_tokens.py'
DELETE = object()


def load_generator(test_case):
    test_case.assertTrue(
        GENERATOR_PATH.exists(),
        'the shared design-token generator must exist',
    )
    spec = importlib.util.spec_from_file_location('design_token_generator', GENERATOR_PATH)
    test_case.assertIsNotNone(spec)
    test_case.assertIsNotNone(spec.loader)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def mutate_contract(contract, dotted_path, value):
    segments = dotted_path.split('.')
    parent = contract
    for segment in segments[:-1]:
        parent = parent[segment]
    if value is DELETE:
        del parent[segments[-1]]
    else:
        parent[segments[-1]] = value


class DesignTokenGeneratorTest(SimpleTestCase):
    def test_load_contract_rejects_duplicate_json_keys(self):
        generator = load_generator(self)
        with tempfile.TemporaryDirectory() as temporary_directory:
            contract_path = Path(temporary_directory) / 'tokens.json'
            contract_path.write_text(
                '{"schemaVersion": 1, "schemaVersion": 2}',
                encoding='utf-8',
            )

            with self.assertRaisesRegex(generator.ContractError, 'duplicate JSON key'):
                generator.load_contract(contract_path)

    def test_contract_is_valid_and_renders_both_platforms(self):
        generator = load_generator(self)
        contract = generator.load_contract(CONTRACT_PATH)

        generator.validate_contract(contract)
        css = generator.render_css(contract)
        dart = generator.render_dart(contract)

        self.assertIn('--lar-color-surface-canvas: #091311;', css)
        self.assertIn('[data-lar-theme="light"]', css)
        self.assertIn('font-variant-numeric: tabular-nums', css)
        self.assertIn('abstract final class LarGeneratedColors', dart)
        self.assertIn('abstract final class LarGeneratedDarkColors', dart)
        self.assertIn('static const desktop = 900.0;', dart)

    def test_contract_rejects_purple(self):
        generator = load_generator(self)
        contract = generator.load_contract(CONTRACT_PATH)
        invalid = copy.deepcopy(contract)
        invalid['color']['primitive']['forbiddenPurple'] = '#7C3AED'

        with self.assertRaisesRegex(generator.ContractError, 'purple family'):
            generator.validate_contract(invalid)

    def test_contract_rejects_violet(self):
        generator = load_generator(self)
        contract = generator.load_contract(CONTRACT_PATH)
        invalid = copy.deepcopy(contract)
        invalid['color']['primitive']['forbiddenViolet'] = '#8A2BE2'

        with self.assertRaisesRegex(generator.ContractError, 'purple family'):
            generator.validate_contract(invalid)

    def test_contract_rejects_lavender(self):
        generator = load_generator(self)
        contract = generator.load_contract(CONTRACT_PATH)
        invalid = copy.deepcopy(contract)
        invalid['color']['primitive']['forbiddenLavender'] = '#E6E6FA'

        with self.assertRaisesRegex(generator.ContractError, 'purple family'):
            generator.validate_contract(invalid)

    def test_contract_rejects_inaccessible_semantic_text(self):
        generator = load_generator(self)
        contract = generator.load_contract(CONTRACT_PATH)
        invalid = copy.deepcopy(contract)
        invalid['color']['semantic']['dark']['text']['muted'] = '#31403A'

        with self.assertRaisesRegex(generator.ContractError, 'contrast'):
            generator.validate_contract(invalid)

    def test_contract_rejects_semantic_color_reference_to_spacing(self):
        generator = load_generator(self)
        contract = generator.load_contract(CONTRACT_PATH)
        invalid = copy.deepcopy(contract)
        invalid['color']['semantic']['dark']['accent']['selection'] = '{spacing.md}'

        with self.assertRaisesRegex(generator.ContractError, 'valid color'):
            generator.validate_contract(invalid)

    def test_contract_rejects_semantic_literal_purple(self):
        generator = load_generator(self)
        contract = generator.load_contract(CONTRACT_PATH)
        invalid = copy.deepcopy(contract)
        invalid['color']['semantic']['dark']['accent']['selection'] = '#7C3AED'

        with self.assertRaisesRegex(generator.ContractError, 'purple family'):
            generator.validate_contract(invalid)

    def test_contract_rejects_missing_renderer_consumed_fields(self):
        generator = load_generator(self)
        contract = generator.load_contract(CONTRACT_PATH)
        missing_paths = (
            'color.semantic.dark.shadow.color',
            'spacing.md',
            'radius.md',
            'border.focus',
            'elevation.modal',
            'elevation.flat.offsetY',
            'elevation.raised.blur',
            'elevation.modal.lightOpacity',
            'elevation.modal.darkOpacity',
            'motion.standardCurve',
            'typography.webFontFamily',
            'typography.weights',
            'typography.styles.financial',
            'typography.styles.caption.fontSize',
            'typography.styles.label.lineHeight',
            'typography.styles.body.fontWeight',
            'breakpoint.desktop',
        )

        for dotted_path in missing_paths:
            with self.subTest(dotted_path=dotted_path):
                invalid = copy.deepcopy(contract)
                mutate_contract(invalid, dotted_path, DELETE)

                try:
                    generator.validate_contract(invalid)
                except generator.ContractError:
                    pass
                except Exception as error:  # noqa: BLE001 - proves contract boundary
                    self.fail(f'{dotted_path} leaked {type(error).__name__}: {error}')
                else:
                    self.fail(f'{dotted_path} was accepted')

    def test_contract_rejects_incompatible_renderer_values(self):
        generator = load_generator(self)
        contract = generator.load_contract(CONTRACT_PATH)
        invalid_values = (
            ('schemaVersion', True),
            ('color.primitive', []),
            ('color.semantic.dark.accent.selection', 16),
            ('spacing.md', 16.0),
            ('spacing.md', 10**1000),
            ('radius.pill', 9999.0),
            ('radius.giant', '24'),
            ('border.default', True),
            ('elevation.flat.offsetY', '0'),
            ('elevation.raised.blur', -1),
            ('elevation.raised.lightOpacity', 1.1),
            ('elevation.decorative', {}),
            ('motion.duration.standard', 200.0),
            ('motion.standardCurve', [0.2, 0, 0, True]),
            ('typography.webFontFamily', 'Segoe UI'),
            ('typography.webFontFamily', ['Segoe UI', '']),
            ('typography.weights', [400, 500, 600, 700.0]),
            ('typography.styles.caption', 12),
            ('typography.styles.caption.fontSize', '12'),
            ('typography.styles.caption.lineHeight', 0),
            ('typography.styles.caption.fontWeight', 450),
            ('typography.styles.decorative', {}),
            ('breakpoint.desktop', 900.0),
            ('breakpoint.mobile', '600'),
        )

        for dotted_path, value in invalid_values:
            with self.subTest(dotted_path=dotted_path, value=value):
                invalid = copy.deepcopy(contract)
                mutate_contract(invalid, dotted_path, value)

                try:
                    generator.validate_contract(invalid)
                except generator.ContractError:
                    pass
                except Exception as error:  # noqa: BLE001 - proves contract boundary
                    self.fail(f'{dotted_path} leaked {type(error).__name__}: {error}')
                else:
                    self.fail(f'{dotted_path} was accepted')

    def test_contract_rejects_indirect_reference_cycle(self):
        generator = load_generator(self)
        contract = generator.load_contract(CONTRACT_PATH)
        invalid = copy.deepcopy(contract)
        invalid['color']['semantic']['dark']['text']['muted'] = (
            '{color.semantic.dark.text.secondary}'
        )
        invalid['color']['semantic']['dark']['text']['secondary'] = (
            '{color.semantic.dark.text.muted}'
        )

        try:
            generator.validate_contract(invalid)
        except generator.ContractError as error:
            self.assertRegex(str(error), 'cyclic token reference')
        except RecursionError as error:
            self.fail(f'indirect cycle leaked RecursionError: {error}')
        else:
            self.fail('indirect cycle was accepted')

    def test_dart_normalizes_reserved_identifiers(self):
        generator = load_generator(self)
        contract = generator.load_contract(CONTRACT_PATH)

        dart = generator.render_dart(contract)

        self.assertIn('static const defaultValue = 1.0;', dart)
        self.assertNotIn('static const default =', dart)

    def test_contract_rejects_normalized_css_identifier_collisions(self):
        generator = load_generator(self)
        contract = generator.load_contract(CONTRACT_PATH)
        invalid = copy.deepcopy(contract)
        invalid['color']['primitive']['mineralTone'] = '#112211'
        invalid['color']['primitive']['mineral-tone'] = '#223322'

        with self.assertRaisesRegex(generator.ContractError, 'CSS identifier collision'):
            generator.validate_contract(invalid)

    def test_contract_rejects_cross_layer_css_identifier_collisions(self):
        generator = load_generator(self)
        contract = generator.load_contract(CONTRACT_PATH)
        invalid = copy.deepcopy(contract)
        invalid['color']['primitive']['accentMineral'] = '#112211'

        with self.assertRaisesRegex(generator.ContractError, 'CSS identifier collision'):
            generator.validate_contract(invalid)

    def test_contract_rejects_normalized_dart_identifier_collisions(self):
        generator = load_generator(self)
        contract = generator.load_contract(CONTRACT_PATH)
        invalid = copy.deepcopy(contract)
        invalid['color']['primitive']['default'] = '#112211'
        invalid['color']['primitive']['defaultValue'] = '#223322'

        with self.assertRaisesRegex(generator.ContractError, 'Dart identifier collision'):
            generator.validate_contract(invalid)

    def test_numeric_rendering_preserves_contract_precision(self):
        generator = load_generator(self)
        contract = generator.load_contract(CONTRACT_PATH)

        css = generator.render_css(contract)
        dart = generator.render_dart(contract)

        self.assertIn('--lar-line-height-caption: 1.333333;', css)
        self.assertIn('--lar-line-height-label: 1.428571;', css)
        self.assertIn('static const captionLineHeight = 1.333333;', dart)
        self.assertIn('static const labelLineHeight = 1.428571;', dart)

    def test_check_detects_stale_generated_output_without_writing(self):
        generator = load_generator(self)
        with tempfile.TemporaryDirectory() as temporary_directory:
            root = Path(temporary_directory)
            contract_target = root / 'design' / 'tokens.json'
            contract_target.parent.mkdir(parents=True)
            contract_target.write_text(
                CONTRACT_PATH.read_text(encoding='utf-8'),
                encoding='utf-8',
            )

            self.assertEqual(generator.generate(root=root, check=False), 0)
            css_path = root / 'static' / 'css' / 'design-tokens.css'
            css_path.write_text('stale\n', encoding='utf-8')

            self.assertEqual(generator.generate(root=root, check=True), 1)
            self.assertEqual(css_path.read_text(encoding='utf-8'), 'stale\n')


class WebTokenIntegrationTest(SimpleTestCase):
    def test_base_template_loads_tokens_without_structural_hex_colors(self):
        template = (PROJECT_ROOT / 'templates' / 'base.html').read_text(encoding='utf-8')

        self.assertIn("{% load static %}", template)
        self.assertIn("{% static 'css/design-tokens.css' %}", template)
        self.assertIn('var(--lar-font-family-sans)', template)
        self.assertIn('var(--lar-color-surface-canvas)', template)
        self.assertNotRegex(template, r'#[0-9A-Fa-f]{3,8}\b')
        self.assertNotIn('radial-gradient', template)

    def test_tailwind_palette_supports_opacity_and_accessible_solid_fills(self):
        template = (PROJECT_ROOT / 'templates' / 'base.html').read_text(encoding='utf-8')
        template_sources = '\n'.join(
            path.read_text(encoding='utf-8')
            for path in (PROJECT_ROOT / 'templates').rglob('*.html')
        )

        for utility in ('bg-mineral/20', 'border-danger/30', 'shadow-champagne/20'):
            self.assertIn(utility, template_sources)

        for token in ('--lar-color-mineral', '--lar-color-danger'):
            self.assertIn(
                f"rgb(from var({token}) r g b / <alpha-value>)",
                template,
            )

        self.assertIn('var(--lar-color-accent-mineral)', template)
        self.assertIn('var(--lar-color-state-danger)', template)

        generator = load_generator(self)
        contract = generator.load_contract(CONTRACT_PATH)
        for token in ('mineral', 'danger'):
            self.assertGreaterEqual(
                generator._contrast('#FFFFFF', contract['color']['primitive'][token]),
                4.5,
            )
