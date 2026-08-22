import copy
import importlib.util
import tempfile
from pathlib import Path

from django.test import SimpleTestCase

PROJECT_ROOT = Path(__file__).resolve().parents[1]
CONTRACT_PATH = PROJECT_ROOT / 'design' / 'tokens.json'
GENERATOR_PATH = PROJECT_ROOT / 'scripts' / 'generate_design_tokens.py'


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


class DesignTokenGeneratorTest(SimpleTestCase):
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

    def test_contract_rejects_inaccessible_semantic_text(self):
        generator = load_generator(self)
        contract = generator.load_contract(CONTRACT_PATH)
        invalid = copy.deepcopy(contract)
        invalid['color']['semantic']['dark']['text']['muted'] = '#31403A'

        with self.assertRaisesRegex(generator.ContractError, 'contrast'):
            generator.validate_contract(invalid)

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
