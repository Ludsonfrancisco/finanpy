# Casa de Valores R2.1 Design Tokens Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Criar um contrato neutro e canônico que gere tokens equivalentes para Web e Flutter, migrar apenas o shell Web compartilhado e impedir divergências pela CI.

**Architecture:** `design/tokens.json` será a única origem editável dos valores. Um gerador Python determinístico produzirá CSS e Dart versionados; as fachadas Flutter existentes e o shell Django consumirão essas saídas sem ativar ainda o tema automático. A implementação ocorrerá na branch `codex/r2-1-design-tokens`, com commit e push ao final de cada task, evitando deploy parcial da `main`.

**Tech Stack:** Python 3.12, biblioteca padrão Python, Django 5.2.13, Flutter/Dart fixado em `mobile/tool/flutter-version.json`, CSS variables, GitHub Actions.

## Global Constraints

- Nome e direção visual: Lar Finance — Casa de Valores 2.0.
- Nunca usar roxo, lavanda, violeta, gradiente azul-roxo, glow ou sombra decorativa.
- Valores Flutter já aprovados permanecem como base; novos textos/estados precisam de contraste mínimo 4,5:1 sobre a superfície base.
- Escala de spacing: `4, 8, 12, 16, 24, 32, 48 px`.
- Escala de radius: `8, 12, 16, 24 px`; pill apenas para seleção, filtro ou status.
- Bordas: `1 px`; foco visível: `2 px`.
- Motion: `160, 200, 240 ms` e curva `cubic-bezier(0.2, 0, 0, 1)`.
- Breakpoint estrutural canônico: `900 px`; o shell não muda de composição nesta task.
- Web permanece escura na R2.1; tema automático, prevenção de flash e assets locais pertencem à R2.2.
- Não editar `staticfiles/`; ele é saída de `collectstatic`.
- Não alterar backend, banco, API, sincronização, conteúdo financeiro ou telas internas.
- Não adicionar dependência Python, Dart ou Node.
- Usar TDD: teste vermelho, implementação mínima, teste verde e revisão antes de cada commit.
- Cada task termina com commit e push da branch; não mesclar em `main` sem autorização do proprietário.

## File Structure

| Caminho | Ação | Responsabilidade |
|---|---|---|
| `design/tokens.json` | criar | contrato único de primitivas e papéis semânticos |
| `scripts/__init__.py` | criar | tornar o gerador importável pelos testes |
| `scripts/generate_design_tokens.py` | criar | validar, gerar e verificar CSS/Dart |
| `static/css/design-tokens.css` | gerar | variáveis CSS Web; nunca editar manualmente |
| `mobile/lib/design_system/lar_tokens.g.dart` | gerar | constantes Flutter; nunca editar manualmente |
| `core/tests_design_tokens.py` | criar | contrato, geração, stale check e shell Web |
| `mobile/lib/design_system/lar_colors.dart` | modificar | fachada de cores geradas |
| `mobile/lib/design_system/lar_spacing.dart` | modificar | fachada de spacing gerado |
| `mobile/lib/design_system/lar_typography.dart` | modificar | tipografia financeira gerada |
| `mobile/lib/design_system/lar_theme.dart` | modificar | remover cores estruturais Dart literais |
| `mobile/test/design_system/lar_theme_test.dart` | modificar | paridade da fachada e restrição de imports |
| `templates/base.html` | modificar | carregar e consumir tokens no shell compartilhado |
| `.github/workflows/ci.yml` | modificar | gate `--check` sem rede |
| `docs/design-system.md` | modificar | declarar o JSON como fonte canônica |
| `docs/ROADMAP.md` | modificar | registrar conclusão da R2.1 |
| `PRD.md` | modificar | atualizar estado e próximo passo sem iniciar R2.2 |
| especificação e este plano | modificar | marcar estado implementado e checkboxes concluídos |

---

### Task 1: Contrato canônico e gerador determinístico

**Files:**
- Create: `design/tokens.json`
- Create: `scripts/__init__.py`
- Create: `scripts/generate_design_tokens.py`
- Create: `core/tests_design_tokens.py`
- Generate: `static/css/design-tokens.css`
- Generate: `mobile/lib/design_system/lar_tokens.g.dart`

**Interfaces:**
- Consumes: a especificação aprovada em `docs/superpowers/specs/2026-08-22-casa-de-valores-r2-1-design-tokens-design.md`.
- Produces: `load_contract(path: Path) -> dict`, `validate_contract(contract: dict) -> None`, `render_css(contract: dict) -> str`, `render_dart(contract: dict) -> str` e `generate(root: Path, check: bool) -> int`.
- Produces: classes Dart `LarGeneratedColors`, `LarGeneratedLightColors`, `LarGeneratedDarkColors`, `LarGeneratedSpacing`, `LarGeneratedRadius`, `LarGeneratedBorders`, `LarGeneratedMotion`, `LarGeneratedTypography`, `LarGeneratedElevation` e `LarGeneratedBreakpoints`.

- [ ] **Step 1: criar a branch isolada para não publicar implementação parcial**

Use `using-git-worktrees` antes deste passo para criar o worktree já associado à
branch `codex/r2-1-design-tokens`. Dentro do worktree, apenas confirme e publique
o upstream:

```powershell
$branch = git branch --show-current
if ($branch -ne 'codex/r2-1-design-tokens') { throw "Branch inesperada: $branch" }
git push -u origin HEAD
```

Expected: branch local acompanha `origin/codex/r2-1-design-tokens`; `main` permanece no último documento aprovado.

- [ ] **Step 2: escrever os testes vermelhos do contrato e do gerador**

Crie `core/tests_design_tokens.py`:

```python
import copy
import tempfile
from pathlib import Path

from django.test import SimpleTestCase

from scripts.generate_design_tokens import (
    ContractError,
    generate,
    load_contract,
    render_css,
    render_dart,
    validate_contract,
)


PROJECT_ROOT = Path(__file__).resolve().parents[1]
CONTRACT_PATH = PROJECT_ROOT / 'design' / 'tokens.json'


class DesignTokenGeneratorTest(SimpleTestCase):
    def test_contract_is_valid_and_renders_both_platforms(self):
        contract = load_contract(CONTRACT_PATH)

        validate_contract(contract)
        css = render_css(contract)
        dart = render_dart(contract)

        self.assertIn('--lar-color-surface-canvas: #091311;', css)
        self.assertIn('[data-lar-theme="light"]', css)
        self.assertIn('font-variant-numeric: tabular-nums', css)
        self.assertIn('abstract final class LarGeneratedColors', dart)
        self.assertIn('abstract final class LarGeneratedDarkColors', dart)
        self.assertIn('static const desktop = 900.0;', dart)

    def test_contract_rejects_purple(self):
        contract = load_contract(CONTRACT_PATH)
        invalid = copy.deepcopy(contract)
        invalid['color']['primitive']['forbiddenPurple'] = '#7C3AED'

        with self.assertRaisesRegex(ContractError, 'purple family'):
            validate_contract(invalid)

    def test_contract_rejects_inaccessible_semantic_text(self):
        contract = load_contract(CONTRACT_PATH)
        invalid = copy.deepcopy(contract)
        invalid['color']['semantic']['dark']['text']['muted'] = '#31403A'

        with self.assertRaisesRegex(ContractError, 'contrast'):
            validate_contract(invalid)

    def test_check_detects_stale_generated_output_without_writing(self):
        with tempfile.TemporaryDirectory() as temporary_directory:
            root = Path(temporary_directory)
            contract_target = root / 'design' / 'tokens.json'
            contract_target.parent.mkdir(parents=True)
            contract_target.write_text(
                CONTRACT_PATH.read_text(encoding='utf-8'),
                encoding='utf-8',
            )

            self.assertEqual(generate(root=root, check=False), 0)
            css_path = root / 'static' / 'css' / 'design-tokens.css'
            css_path.write_text('stale\n', encoding='utf-8')

            self.assertEqual(generate(root=root, check=True), 1)
            self.assertEqual(css_path.read_text(encoding='utf-8'), 'stale\n')
```

- [ ] **Step 3: executar o teste para comprovar o estado vermelho**

Run:

```powershell
python manage.py test core.tests_design_tokens -v 2
```

Expected: `ERROR` durante import com `ModuleNotFoundError: No module named 'scripts.generate_design_tokens'`.

- [ ] **Step 4: criar o contrato JSON aprovado**

Crie `design/tokens.json` exatamente com esta estrutura:

```json
{
  "schemaVersion": 1,
  "color": {
    "primitive": {
      "amber": "#B9782D",
      "black": "#000000",
      "champagne": "#C7A35A",
      "champagneDark": "#A6843D",
      "champagneLight": "#DBB86F",
      "champagneSelectedDark": "#4B4027",
      "champagneSelectedLight": "#E9D9B8",
      "danger": "#B8534F",
      "dangerDark": "#963E3B",
      "dangerLight": "#D66D69",
      "darkBorder": "#31403A",
      "darkCanvas": "#091311",
      "darkElevated": "#171F1B",
      "darkOutline": "#8D958D",
      "darkSurface": "#101B18",
      "darkText": "#E8E3D8",
      "darkTextMuted": "#8D958D",
      "darkTextSecondary": "#A7AEA8",
      "lightBorder": "#CBC5B9",
      "lightCanvas": "#F3EFE6",
      "lightElevated": "#FFFCF5",
      "lightOutline": "#8B8A80",
      "lightSurface": "#FFFCF5",
      "lightText": "#17201D",
      "lightTextMuted": "#6B716C",
      "lightTextSecondary": "#59635D",
      "mineral": "#2F756A",
      "mineralDark": "#23584F",
      "mineralHover": "#28635A",
      "mineralOnDark": "#72B8AC",
      "warningDark": "#8E571F",
      "warningLight": "#DBB86F"
    },
    "semantic": {
      "light": {
        "surface": {
          "canvas": "{color.primitive.lightCanvas}",
          "base": "{color.primitive.lightSurface}",
          "elevated": "{color.primitive.lightElevated}"
        },
        "text": {
          "primary": "{color.primitive.lightText}",
          "secondary": "{color.primitive.lightTextSecondary}",
          "muted": "{color.primitive.lightTextMuted}"
        },
        "border": {
          "default": "{color.primitive.lightBorder}",
          "strong": "{color.primitive.lightOutline}"
        },
        "accent": {
          "champagne": "{color.primitive.champagne}",
          "mineral": "{color.primitive.mineral}",
          "selection": "{color.primitive.champagneSelectedLight}"
        },
        "state": {
          "success": "{color.primitive.mineral}",
          "info": "{color.primitive.mineral}",
          "warning": "{color.primitive.warningDark}",
          "danger": "{color.primitive.danger}"
        },
        "focus": {
          "ring": "{color.primitive.mineral}"
        },
        "shadow": {
          "color": "{color.primitive.darkCanvas}"
        }
      },
      "dark": {
        "surface": {
          "canvas": "{color.primitive.darkCanvas}",
          "base": "{color.primitive.darkSurface}",
          "elevated": "{color.primitive.darkElevated}"
        },
        "text": {
          "primary": "{color.primitive.darkText}",
          "secondary": "{color.primitive.darkTextSecondary}",
          "muted": "{color.primitive.darkTextMuted}"
        },
        "border": {
          "default": "{color.primitive.darkBorder}",
          "strong": "{color.primitive.darkOutline}"
        },
        "accent": {
          "champagne": "{color.primitive.champagne}",
          "mineral": "{color.primitive.mineralOnDark}",
          "selection": "{color.primitive.champagneSelectedDark}"
        },
        "state": {
          "success": "{color.primitive.mineralOnDark}",
          "info": "{color.primitive.mineralOnDark}",
          "warning": "{color.primitive.warningLight}",
          "danger": "{color.primitive.dangerLight}"
        },
        "focus": {
          "ring": "{color.primitive.mineralOnDark}"
        },
        "shadow": {
          "color": "{color.primitive.black}"
        }
      }
    }
  },
  "spacing": {
    "xxs": 4,
    "xs": 8,
    "sm": 12,
    "md": 16,
    "lg": 24,
    "xl": 32,
    "xxl": 48
  },
  "radius": {
    "sm": 8,
    "md": 12,
    "lg": 16,
    "xl": 24,
    "pill": 9999
  },
  "border": {
    "default": 1,
    "focus": 2
  },
  "elevation": {
    "flat": {"offsetY": 0, "blur": 0, "lightOpacity": 0, "darkOpacity": 0},
    "raised": {"offsetY": 4, "blur": 16, "lightOpacity": 0.10, "darkOpacity": 0.24},
    "modal": {"offsetY": 12, "blur": 32, "lightOpacity": 0.16, "darkOpacity": 0.36}
  },
  "motion": {
    "duration": {"fast": 160, "standard": 200, "slow": 240},
    "standardCurve": [0.2, 0, 0, 1]
  },
  "typography": {
    "webFontFamily": ["Segoe UI", "-apple-system", "BlinkMacSystemFont", "Roboto", "system-ui", "sans-serif"],
    "weights": [400, 500, 600, 700],
    "styles": {
      "caption": {"fontSize": 12, "lineHeight": 1.333333, "fontWeight": 400},
      "label": {"fontSize": 14, "lineHeight": 1.428571, "fontWeight": 500},
      "body": {"fontSize": 16, "lineHeight": 1.5, "fontWeight": 400},
      "title": {"fontSize": 20, "lineHeight": 1.4, "fontWeight": 600},
      "headline": {"fontSize": 24, "lineHeight": 1.333333, "fontWeight": 600},
      "financial": {"fontSize": 32, "lineHeight": 1.15, "fontWeight": 600}
    }
  },
  "breakpoint": {
    "desktop": 900
  }
}
```

- [ ] **Step 5: implementar o gerador sem dependências externas**

Crie `scripts/__init__.py` vazio e implemente `scripts/generate_design_tokens.py` com estas responsabilidades e assinaturas completas:

```python
import argparse
import colorsys
import json
import re
import sys
from pathlib import Path
from typing import Any


PROJECT_ROOT = Path(__file__).resolve().parents[1]
CONTRACT_RELATIVE_PATH = Path('design/tokens.json')
CSS_RELATIVE_PATH = Path('static/css/design-tokens.css')
DART_RELATIVE_PATH = Path('mobile/lib/design_system/lar_tokens.g.dart')
REFERENCE = re.compile(r'^\{([a-zA-Z0-9_.]+)\}$')
HEX_COLOR = re.compile(r'^#[0-9A-F]{6}$')
REQUIRED_TOP_LEVEL = {
    'schemaVersion', 'color', 'spacing', 'radius', 'border',
    'elevation', 'motion', 'typography', 'breakpoint',
}
REQUIRED_SEMANTIC = {
    'surface.canvas', 'surface.base', 'surface.elevated',
    'text.primary', 'text.secondary', 'text.muted',
    'border.default', 'border.strong',
    'accent.champagne', 'accent.mineral', 'accent.selection',
    'state.success', 'state.info', 'state.warning', 'state.danger',
    'focus.ring', 'shadow.color',
}


class ContractError(ValueError):
    pass


def load_contract(path: Path) -> dict[str, Any]:
    try:
        value = json.loads(path.read_text(encoding='utf-8'))
    except (OSError, json.JSONDecodeError) as error:
        raise ContractError(f'cannot read design token contract: {error}') from error
    if not isinstance(value, dict):
        raise ContractError('design token contract must be a JSON object')
    return value


def _flatten(value: dict[str, Any], prefix: tuple[str, ...] = ()) -> dict[str, Any]:
    result: dict[str, Any] = {}
    for key, item in value.items():
        path = (*prefix, key)
        if isinstance(item, dict):
            result.update(_flatten(item, path))
        else:
            result['.'.join(path)] = item
    return result


def _lookup(contract: dict[str, Any], dotted_path: str) -> Any:
    value: Any = contract
    for segment in dotted_path.split('.'):
        if not isinstance(value, dict) or segment not in value:
            raise ContractError(f'unknown token reference: {dotted_path}')
        value = value[segment]
    return value


def _resolve(contract: dict[str, Any], value: Any) -> Any:
    if not isinstance(value, str):
        return value
    match = REFERENCE.fullmatch(value)
    if not match:
        return value
    resolved = _lookup(contract, match.group(1))
    if resolved == value:
        raise ContractError(f'cyclic token reference: {value}')
    return _resolve(contract, resolved)


def _rgb(hex_color: str) -> tuple[int, int, int]:
    return tuple(int(hex_color[index:index + 2], 16) for index in (1, 3, 5))


def _is_purple(hex_color: str) -> bool:
    red, green, blue = (channel / 255 for channel in _rgb(hex_color))
    hue, saturation, _ = colorsys.rgb_to_hsv(red, green, blue)
    return 260 <= hue * 360 <= 330 and saturation > 0.15


def _luminance(hex_color: str) -> float:
    channels = []
    for channel in _rgb(hex_color):
        normalized = channel / 255
        channels.append(
            normalized / 12.92
            if normalized <= 0.04045
            else ((normalized + 0.055) / 1.055) ** 2.4
        )
    return 0.2126 * channels[0] + 0.7152 * channels[1] + 0.0722 * channels[2]


def _contrast(foreground: str, background: str) -> float:
    lighter, darker = sorted(
        (_luminance(foreground), _luminance(background)), reverse=True
    )
    return (lighter + 0.05) / (darker + 0.05)


def validate_contract(contract: dict[str, Any]) -> None:
    missing = REQUIRED_TOP_LEVEL - contract.keys()
    if missing:
        raise ContractError(f'missing top-level tokens: {sorted(missing)}')
    if contract['schemaVersion'] != 1:
        raise ContractError('schemaVersion must be 1')

    primitives = contract['color']['primitive']
    for name, color in primitives.items():
        if not isinstance(color, str) or not HEX_COLOR.fullmatch(color):
            raise ContractError(f'color.primitive.{name} must be uppercase #RRGGBB')
        if _is_purple(color):
            raise ContractError(f'purple family is forbidden: color.primitive.{name}')

    for mode in ('light', 'dark'):
        semantic = _flatten(contract['color']['semantic'][mode])
        missing_semantic = REQUIRED_SEMANTIC - semantic.keys()
        if missing_semantic:
            raise ContractError(f'{mode} semantic tokens missing: {sorted(missing_semantic)}')
        resolved = {name: _resolve(contract, value) for name, value in semantic.items()}
        surface = resolved['surface.base']
        for name in (
            'text.primary', 'text.secondary', 'text.muted',
            'state.success', 'state.info', 'state.warning', 'state.danger',
        ):
            ratio = _contrast(resolved[name], surface)
            if ratio < 4.5:
                raise ContractError(
                    f'{mode}.{name} contrast {ratio:.2f}:1 is below 4.5:1'
                )

    if list(contract['spacing'].values()) != [4, 8, 12, 16, 24, 32, 48]:
        raise ContractError('spacing scale must be 4, 8, 12, 16, 24, 32, 48')
    if [contract['radius'][name] for name in ('sm', 'md', 'lg', 'xl')] != [8, 12, 16, 24]:
        raise ContractError('radius scale must be 8, 12, 16, 24')
    if contract['radius']['pill'] != 9999:
        raise ContractError('radius.pill must be 9999')
    if contract['border'] != {'default': 1, 'focus': 2}:
        raise ContractError('border scale must be default=1 and focus=2')
    if list(contract['motion']['duration'].values()) != [160, 200, 240]:
        raise ContractError('motion durations must be 160, 200, 240')
    if contract['motion']['standardCurve'] != [0.2, 0, 0, 1]:
        raise ContractError('motion.standardCurve must be [0.2, 0, 0, 1]')
    if contract['breakpoint']['desktop'] != 900:
        raise ContractError('breakpoint.desktop must be 900')
    if contract['typography']['weights'] != [400, 500, 600, 700]:
        raise ContractError('typography.weights must be 400, 500, 600, 700')


def _kebab(value: str) -> str:
    return re.sub(r'(?<!^)(?=[A-Z])', '-', value).replace('.', '-').lower()


def _camel(value: str) -> str:
    parts = value.split('.')
    return parts[0] + ''.join(part[:1].upper() + part[1:] for part in parts[1:])


def _css_font_family(families: list[str]) -> str:
    return ', '.join(f'"{item}"' if ' ' in item else item for item in families)


def _rgba(hex_color: str, opacity: float) -> str:
    red, green, blue = _rgb(hex_color)
    return f'rgba({red}, {green}, {blue}, {opacity:g})'


def render_css(contract: dict[str, Any]) -> str:
    validate_contract(contract)
    lines = [
        '/* Generated from design/tokens.json. Do not edit manually. */',
        ':root {',
    ]
    for name, color in sorted(contract['color']['primitive'].items()):
        lines.append(f'  --lar-color-{_kebab(name)}: {color};')
    for name, value in contract['spacing'].items():
        lines.append(f'  --lar-space-{_kebab(name)}: {value}px;')
    for name, value in contract['radius'].items():
        lines.append(f'  --lar-radius-{_kebab(name)}: {value}px;')
    for name, value in contract['border'].items():
        lines.append(f'  --lar-border-{_kebab(name)}: {value}px;')
    for name, value in contract['motion']['duration'].items():
        lines.append(f'  --lar-motion-{_kebab(name)}: {value}ms;')
    curve = ', '.join(f'{value:g}' for value in contract['motion']['standardCurve'])
    lines.append(f'  --lar-motion-curve-standard: cubic-bezier({curve});')
    lines.append(
        f'  --lar-font-family-sans: {_css_font_family(contract["typography"]["webFontFamily"])};'
    )
    for name, style in contract['typography']['styles'].items():
        key = _kebab(name)
        lines.append(f'  --lar-font-size-{key}: {style["fontSize"]}px;')
        lines.append(f'  --lar-line-height-{key}: {style["lineHeight"]:g};')
        lines.append(f'  --lar-font-weight-{key}: {style["fontWeight"]};')
    lines.append(f'  --lar-breakpoint-desktop: {contract["breakpoint"]["desktop"]}px;')
    lines.append('}')

    for mode in ('dark', 'light'):
        selector = ':root, [data-lar-theme="dark"]' if mode == 'dark' else '[data-lar-theme="light"]'
        lines.extend(['', f'{selector} {{'])
        semantic = _flatten(contract['color']['semantic'][mode])
        for name, value in sorted(semantic.items()):
            lines.append(f'  --lar-color-{_kebab(name)}: {_resolve(contract, value)};')
        shadow_color = _resolve(contract, semantic['shadow.color'])
        for name, elevation in contract['elevation'].items():
            shadow = (
                f'0 {elevation["offsetY"]}px {elevation["blur"]}px '
                f'{_rgba(shadow_color, elevation[f"{mode}Opacity"])}'
            )
            lines.append(f'  --lar-elevation-{_kebab(name)}: {shadow};')
        lines.append('}')

    lines.extend([
        '',
        ':where(.tabular-nums, .financial-amount, [data-financial-value]) {',
        '  font-variant-numeric: tabular-nums;',
        '}',
        '',
    ])
    return '\n'.join(lines)


def _dart_color(hex_color: str) -> str:
    return f'Color(0xFF{hex_color[1:]})'


def _dart_double(value: int | float) -> str:
    return f'{value}.0' if isinstance(value, int) else f'{value:g}'


def render_dart(contract: dict[str, Any]) -> str:
    validate_contract(contract)
    lines = [
        '// Generated from design/tokens.json. Do not edit manually.',
        "import 'package:flutter/material.dart';",
        '',
        'abstract final class LarGeneratedColors {',
    ]
    for name, color in sorted(contract['color']['primitive'].items()):
        lines.append(f'  static const {name} = {_dart_color(color)};')
    lines.append('}')

    for mode in ('Light', 'Dark'):
        semantic = _flatten(contract['color']['semantic'][mode.lower()])
        lines.extend(['', f'abstract final class LarGenerated{mode}Colors {{'])
        for name, value in sorted(semantic.items()):
            lines.append(f'  static const {_camel(name)} = {_dart_color(_resolve(contract, value))};')
        lines.append('}')

    simple_groups = (
        ('Spacing', contract['spacing']),
        ('Radius', contract['radius']),
        ('Borders', contract['border']),
        ('Breakpoints', contract['breakpoint']),
    )
    for class_name, values in simple_groups:
        lines.extend(['', f'abstract final class LarGenerated{class_name} {{'])
        for name, value in values.items():
            lines.append(f'  static const {name} = {_dart_double(value)};')
        lines.append('}')

    lines.extend(['', 'abstract final class LarGeneratedMotion {'])
    for name, value in contract['motion']['duration'].items():
        lines.append(f'  static const {name}Milliseconds = {value};')
    curve = ', '.join(f'{value:g}' for value in contract['motion']['standardCurve'])
    lines.append(f'  static const standardCurve = Cubic({curve});')
    lines.append('}')

    lines.extend(['', 'abstract final class LarGeneratedTypography {'])
    for name, style in contract['typography']['styles'].items():
        lines.append(f'  static const {name}FontSize = {_dart_double(style["fontSize"])};')
        lines.append(f'  static const {name}LineHeight = {style["lineHeight"]:g};')
        lines.append(f'  static const {name}FontWeight = FontWeight.w{style["fontWeight"]};')
    lines.append('}')

    lines.extend(['', 'abstract final class LarGeneratedElevation {'])
    for name, value in contract['elevation'].items():
        lines.append(f'  static const {name}OffsetY = {_dart_double(value["offsetY"])};')
        lines.append(f'  static const {name}Blur = {_dart_double(value["blur"])};')
        lines.append(f'  static const light{name.title()}Opacity = {value["lightOpacity"]:g};')
        lines.append(f'  static const dark{name.title()}Opacity = {value["darkOpacity"]:g};')
    lines.extend(['}', ''])
    return '\n'.join(lines)


def generate(root: Path = PROJECT_ROOT, check: bool = False) -> int:
    contract = load_contract(root / CONTRACT_RELATIVE_PATH)
    outputs = {
        root / CSS_RELATIVE_PATH: render_css(contract),
        root / DART_RELATIVE_PATH: render_dart(contract),
    }
    stale: list[Path] = []
    for path, expected in outputs.items():
        if check:
            current = path.read_text(encoding='utf-8') if path.exists() else None
            if current != expected:
                stale.append(path.relative_to(root))
            continue
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(expected, encoding='utf-8', newline='\n')
    if stale:
        print('Generated design tokens are stale:', file=sys.stderr)
        for path in stale:
            print(f'  {path}', file=sys.stderr)
        return 1
    return 0


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description='Generate Lar Finance design tokens.')
    parser.add_argument('--check', action='store_true')
    parser.add_argument('--root', type=Path, default=PROJECT_ROOT)
    arguments = parser.parse_args(argv)
    return generate(root=arguments.root.resolve(), check=arguments.check)


if __name__ == '__main__':
    raise SystemExit(main())
```

- [ ] **Step 6: gerar os dois artefatos versionados**

Run:

```powershell
python scripts/generate_design_tokens.py
python scripts/generate_design_tokens.py --check
```

Expected: ambos terminam com exit code 0; o segundo não altera o workspace.

- [ ] **Step 7: executar testes e lint da task**

Run:

```powershell
python manage.py test core.tests_design_tokens -v 2
ruff check scripts/generate_design_tokens.py core/tests_design_tokens.py --config pyproject.toml
git diff --check
```

Expected: 4 testes passam; Ruff e `git diff --check` retornam 0.

- [ ] **Step 8: commitar e publicar a Task 1**

```powershell
git add design/tokens.json scripts/__init__.py scripts/generate_design_tokens.py core/tests_design_tokens.py static/css/design-tokens.css mobile/lib/design_system/lar_tokens.g.dart
git commit -m "feat: generate shared design tokens"
git push origin codex/r2-1-design-tokens
```

Expected: branch remota contém o commit; comunicar ao proprietário o que foi feito e que a próxima task integra o Flutter.

---

### Task 2: Integrar as fachadas Flutter aos tokens gerados

**Files:**
- Modify: `mobile/lib/design_system/lar_colors.dart`
- Modify: `mobile/lib/design_system/lar_spacing.dart`
- Modify: `mobile/lib/design_system/lar_typography.dart`
- Modify: `mobile/lib/design_system/lar_theme.dart`
- Modify: `mobile/test/design_system/lar_theme_test.dart`

**Interfaces:**
- Consumes: classes `LarGenerated*` produzidas pela Task 1.
- Produces: as mesmas APIs públicas `LarColors`, `LarSpacing`, `LarTypography` e `LarTheme`, agora sem valores estruturais duplicados.

- [ ] **Step 1: ampliar o teste Flutter para exigir as fachadas geradas**

Adicione os imports e casos abaixo a `mobile/test/design_system/lar_theme_test.dart`:

```dart
import 'dart:io';

import 'package:lar_finance/design_system/lar_spacing.dart';
import 'package:lar_finance/design_system/lar_tokens.g.dart';
import 'package:lar_finance/design_system/lar_typography.dart';

test('public design-system facades consume generated tokens', () {
  expect(LarColors.darkCanvas, LarGeneratedColors.darkCanvas);
  expect(LarColors.lightTextSecondary, LarGeneratedLightColors.textSecondary);
  expect(LarColors.darkDanger, LarGeneratedDarkColors.stateDanger);
  expect(LarSpacing.md, LarGeneratedSpacing.md);
  expect(
    LarTypography.financial.fontSize,
    LarGeneratedTypography.financialFontSize,
  );
  expect(
    LarTypography.financial.height,
    LarGeneratedTypography.financialLineHeight,
  );
});

test('generated token file is imported only inside design_system', () {
  final violations = Directory('lib')
      .listSync(recursive: true)
      .whereType<File>()
      .where((file) => file.path.endsWith('.dart'))
      .where((file) => !file.path.contains('design_system'))
      .where(
        (file) => file.readAsStringSync().contains('lar_tokens.g.dart'),
      )
      .map((file) => file.path)
      .toList();

  expect(violations, isEmpty);
});
```

- [ ] **Step 2: executar o teste para comprovar o estado vermelho**

Run:

```powershell
Set-Location mobile
flutter test test/design_system/lar_theme_test.dart
Set-Location ..
```

Expected: falha de compilação porque `LarColors.lightTextSecondary` e `LarColors.darkDanger` ainda não existem e as fachadas ainda não usam o arquivo gerado.

- [ ] **Step 3: substituir literais das fachadas por referências geradas**

Reescreva `mobile/lib/design_system/lar_colors.dart` preservando nomes atuais e adicionando papéis semânticos:

```dart
import 'package:flutter/material.dart';

import 'lar_tokens.g.dart';

abstract final class LarColors {
  static const darkCanvas = LarGeneratedColors.darkCanvas,
      darkSurface = LarGeneratedColors.darkSurface,
      darkElevated = LarGeneratedDarkColors.surfaceElevated,
      lightCanvas = LarGeneratedColors.lightCanvas,
      lightSurface = LarGeneratedColors.lightSurface,
      lightElevated = LarGeneratedLightColors.surfaceElevated,
      champagne = LarGeneratedColors.champagne,
      champagneSelectedDark = LarGeneratedColors.champagneSelectedDark,
      champagneSelectedLight = LarGeneratedColors.champagneSelectedLight,
      mineral = LarGeneratedColors.mineral,
      mineralOnDark = LarGeneratedColors.mineralOnDark,
      amber = LarGeneratedColors.amber,
      danger = LarGeneratedColors.danger,
      darkDanger = LarGeneratedDarkColors.stateDanger,
      lightDanger = LarGeneratedLightColors.stateDanger,
      darkText = LarGeneratedColors.darkText,
      darkTextSecondary = LarGeneratedDarkColors.textSecondary,
      darkTextMuted = LarGeneratedDarkColors.textMuted,
      lightText = LarGeneratedColors.lightText,
      lightTextSecondary = LarGeneratedLightColors.textSecondary,
      lightTextMuted = LarGeneratedLightColors.textMuted,
      darkBorder = LarGeneratedDarkColors.borderDefault,
      lightBorder = LarGeneratedLightColors.borderDefault,
      darkOutline = LarGeneratedDarkColors.borderStrong,
      lightOutline = LarGeneratedLightColors.borderStrong,
      darkShadow = LarGeneratedDarkColors.shadowColor,
      lightShadow = LarGeneratedLightColors.shadowColor;

  static const all = <Color>[
    darkCanvas,
    darkSurface,
    darkElevated,
    lightCanvas,
    lightSurface,
    lightElevated,
    champagne,
    champagneSelectedDark,
    champagneSelectedLight,
    mineral,
    mineralOnDark,
    amber,
    danger,
    darkDanger,
    lightDanger,
    darkText,
    darkTextSecondary,
    darkTextMuted,
    lightText,
    lightTextSecondary,
    lightTextMuted,
    darkBorder,
    lightBorder,
    darkOutline,
    lightOutline,
  ];
}
```

Reescreva `mobile/lib/design_system/lar_spacing.dart`:

```dart
import 'lar_tokens.g.dart';

abstract final class LarSpacing {
  static const double xxs = LarGeneratedSpacing.xxs,
      xs = LarGeneratedSpacing.xs,
      sm = LarGeneratedSpacing.sm,
      md = LarGeneratedSpacing.md,
      lg = LarGeneratedSpacing.lg,
      xl = LarGeneratedSpacing.xl,
      xxl = LarGeneratedSpacing.xxl;
}
```

Reescreva `mobile/lib/design_system/lar_typography.dart`:

```dart
import 'package:flutter/material.dart';

import 'lar_tokens.g.dart';

abstract final class LarTypography {
  static const financial = TextStyle(
    fontSize: LarGeneratedTypography.financialFontSize,
    fontWeight: LarGeneratedTypography.financialFontWeight,
    height: LarGeneratedTypography.financialLineHeight,
    fontFeatures: <FontFeature>[FontFeature.tabularFigures()],
  );
}
```

Em `mobile/lib/design_system/lar_theme.dart`, substitua somente os literais estruturais:

```dart
// Tema claro
error: LarColors.lightDanger,
outline: LarColors.lightOutline,
shadow: LarColors.lightShadow,
dividerColor: LarColors.lightBorder,

// Tema escuro
error: LarColors.darkDanger,
outline: LarColors.darkOutline,
shadow: LarColors.darkShadow,
dividerColor: LarColors.darkBorder,
```

Mantenha os demais campos, Material 3, canvases, superfícies e navigation themes existentes. Não introduza seleção automática de tema nesta task.

- [ ] **Step 4: formatar e executar a verificação Flutter focada**

```powershell
Set-Location mobile
dart format lib/design_system test/design_system/lar_theme_test.dart
flutter analyze
flutter test test/design_system/lar_theme_test.dart
Set-Location ..
python scripts/generate_design_tokens.py --check
git diff --check
```

Expected: analyze sem issues, todos os testes do arquivo passam e o gerador permanece sincronizado.

- [ ] **Step 5: commitar e publicar a Task 2**

```powershell
git add mobile/lib/design_system mobile/test/design_system/lar_theme_test.dart
git commit -m "refactor: consume generated Flutter tokens"
git push origin codex/r2-1-design-tokens
```

Expected: branch remota atualizada; comunicar ao proprietário que Flutter preserva a API e que a próxima task migra somente o shell Web.

---

### Task 3: Integrar tokens ao shell Web sem ativar tema automático

**Files:**
- Modify: `core/tests_design_tokens.py`
- Modify: `templates/base.html`

**Interfaces:**
- Consumes: `static/css/design-tokens.css` e variáveis `--lar-*` da Task 1.
- Produces: shell Web escuro sem cores estruturais hexadecimais e com fonte nativa/tabular.

- [ ] **Step 1: escrever o teste vermelho do shell Web**

Adicione a `core/tests_design_tokens.py`:

```python
class WebTokenIntegrationTest(SimpleTestCase):
    def test_base_template_loads_tokens_without_structural_hex_colors(self):
        template = (PROJECT_ROOT / 'templates' / 'base.html').read_text(encoding='utf-8')

        self.assertIn("{% load static %}", template)
        self.assertIn("{% static 'css/design-tokens.css' %}", template)
        self.assertIn('var(--lar-font-family-sans)', template)
        self.assertIn('var(--lar-color-surface-canvas)', template)
        self.assertNotRegex(template, r'#[0-9A-Fa-f]{3,8}\b')
        self.assertNotIn('radial-gradient', template)
```

- [ ] **Step 2: executar o teste para comprovar o estado vermelho**

```powershell
python manage.py test core.tests_design_tokens.WebTokenIntegrationTest -v 2
```

Expected: falha porque `base.html` ainda não carrega o CSS gerado e contém cores hexadecimais e gradientes.

- [ ] **Step 3: carregar tokens e mapear o Tailwind CDN para variáveis**

No início de `templates/base.html`, adicione `{% load static %}` antes do `<!DOCTYPE html>`. No `<head>`, antes do script Tailwind, adicione:

```html
<link rel="stylesheet" href="{% static 'css/design-tokens.css' %}">
```

Preserve o link remoto de Inter até a R2.2, mas faça a aplicação deixar de usá-lo. Substitua `tailwind.config.theme.extend` por este mapeamento:

```javascript
colors: {
  mineral: {
    DEFAULT: 'var(--lar-color-accent-mineral)',
    light: 'var(--lar-color-mineral-on-dark)',
    dark: 'var(--lar-color-mineral-dark)',
    hover: 'var(--lar-color-mineral-hover)',
    muted: 'color-mix(in srgb, var(--lar-color-accent-mineral) 15%, transparent)',
  },
  danger: {
    DEFAULT: 'var(--lar-color-state-danger)',
    light: 'var(--lar-color-danger-light)',
    dark: 'var(--lar-color-danger-dark)',
    muted: 'color-mix(in srgb, var(--lar-color-state-danger) 15%, transparent)',
  },
  champagne: {
    DEFAULT: 'var(--lar-color-accent-champagne)',
    light: 'var(--lar-color-champagne-light)',
    dark: 'var(--lar-color-champagne-dark)',
    muted: 'color-mix(in srgb, var(--lar-color-accent-champagne) 15%, transparent)',
  },
  lar: {
    bg: 'var(--lar-color-surface-canvas)',
    surface: 'var(--lar-color-surface-base)',
    card: 'var(--lar-color-surface-elevated)',
    border: 'var(--lar-color-border-default)',
    borderHover: 'var(--lar-color-border-strong)',
    textPrimary: 'var(--lar-color-text-primary)',
    textSecondary: 'var(--lar-color-text-secondary)',
    textMuted: 'var(--lar-color-text-muted)',
  },
},
fontFamily: {
  sans: ['var(--lar-font-family-sans)'],
},
boxShadow: {
  'glow-mineral': 'var(--lar-elevation-raised)',
  'glow-danger': 'var(--lar-elevation-raised)',
  'glow-champagne': 'var(--lar-elevation-raised)',
  card: 'var(--lar-elevation-raised)',
},
```

Os nomes `glow-*` ficam temporariamente como aliases de compatibilidade, mas deixam de produzir glow. A remoção dos nomes antigos acontecerá tela a tela na R3.

- [ ] **Step 4: substituir o CSS estrutural inline por tokens**

Mantenha os seletores existentes, com estes valores:

```css
::-webkit-scrollbar {
  width: 6px;
  height: 6px;
}
::-webkit-scrollbar-track {
  background: var(--lar-color-surface-canvas);
}
::-webkit-scrollbar-thumb {
  background: var(--lar-color-border-default);
  border-radius: var(--lar-radius-sm);
}
::-webkit-scrollbar-thumb:hover {
  background: var(--lar-color-accent-mineral);
}
.ambient-bg {
  background: var(--lar-color-surface-canvas);
}
.lar-card {
  background: var(--lar-color-surface-elevated);
  border: var(--lar-border-default) solid var(--lar-color-border-default);
  box-shadow: var(--lar-elevation-flat);
  transition:
    border-color var(--lar-motion-standard) var(--lar-motion-curve-standard),
    box-shadow var(--lar-motion-standard) var(--lar-motion-curve-standard);
}
.lar-card:hover {
  border-color: var(--lar-color-border-strong);
}
.tabular-nums {
  font-variant-numeric: tabular-nums;
}
```

No `<body>`, substitua `text-[#E8ECE9]` por `text-lar-textPrimary`. Preserve `class="dark"` no `<html>`; o tema automático é R2.2.

- [ ] **Step 5: executar a verificação Web focada**

```powershell
python manage.py test core.tests_design_tokens -v 2
python manage.py check
python scripts/generate_design_tokens.py --check
ruff check core/tests_design_tokens.py scripts/generate_design_tokens.py --config pyproject.toml
git diff --check
```

Expected: 5 testes passam; check, gerador, Ruff e diff retornam 0.

- [ ] **Step 6: commitar e publicar a Task 3**

```powershell
git add core/tests_design_tokens.py templates/base.html
git commit -m "refactor: apply tokens to web shell"
git push origin codex/r2-1-design-tokens
```

Expected: branch remota atualizada; comunicar que a Web continua escura e que a próxima task fecha CI e documentação.

---

### Task 4: Fechar CI, documentação e verificação integral da R2.1

**Files:**
- Modify: `.github/workflows/ci.yml`
- Modify: `docs/design-system.md`
- Modify: `docs/ROADMAP.md`
- Modify: `PRD.md`
- Modify: `docs/superpowers/specs/2026-08-22-casa-de-valores-r2-1-design-tokens-design.md`
- Modify: `docs/superpowers/plans/2026-08-22-casa-de-valores-r2-1-design-tokens-implementation.md`

**Interfaces:**
- Consumes: gerador, artefatos, testes Flutter e shell Web concluídos nas Tasks 1–3.
- Produces: gate CI offline, documentação coerente e branch pronta para revisão/merge.

- [ ] **Step 1: provar que a CI ainda não executa o gate de paridade**

```powershell
Select-String -Path '.github/workflows/ci.yml' -Pattern 'generate_design_tokens.py --check'
```

Expected: nenhum resultado.

- [ ] **Step 2: adicionar o gate após a instalação Python e antes do Ruff**

Em `.github/workflows/ci.yml`, no job `django`, adicione:

```yaml
      - name: Verify generated design tokens
        run: python scripts/generate_design_tokens.py --check
```

O passo fica depois de `Generate ephemeral Django secret` e antes de `Lint`, garantindo falha rápida sem rede adicional.

- [ ] **Step 3: atualizar somente a documentação da fonte canônica**

Em `docs/design-system.md`:

```markdown
Fonte canônica: `design/tokens.json`. Os artefatos CSS e Dart são gerados por
`scripts/generate_design_tokens.py` e validados na CI; não devem ser editados
manualmente.
```

Substitua a frase provisória que aponta `mobile/lib/design_system/` como fonte
canônica. Preserve as tabelas de direção visual. Ainda não marque roadmap, PRD
ou especificação como concluídos.

- [ ] **Step 4: verificar formato dos artefatos antes da suíte completa**

```powershell
python scripts/generate_design_tokens.py --check
ruff check . --config pyproject.toml
python manage.py check
python manage.py makemigrations --check
Set-Location mobile
dart format --output=none --set-exit-if-changed lib/design_system test/design_system/lar_theme_test.dart
flutter analyze
Set-Location ..
```

Expected: todos os comandos retornam 0; migrations informa `No changes detected`.

- [ ] **Step 5: executar as suítes integrais relevantes**

```powershell
python manage.py test
Set-Location mobile
flutter test --exclude-tags=golden
Set-Location ..
```

Expected: zero failures nas duas suítes. Registrar as contagens exatas observadas no relatório final; não reutilizar contagens históricas.

- [ ] **Step 6: registrar conclusão documental baseada nos resultados reais**

Somente depois do Step 5 verde:

- em `docs/ROADMAP.md`, marque os cinco checkboxes da R2.1 como concluídos e
  acrescente uma linha de evidência com os quatro commits da implementação e as
  contagens reais dos testes;
- em `PRD.md`, substitua “iniciar R2.1” por “R2.1 concluída; próximo passo
  sujeito a autorização: R2.2 — tema e assets”, sem declarar tema automático;
- na especificação, altere o status para
  `implementado e verificado em 22/08/2026`;
- neste plano, marque apenas os checkboxes efetivamente executados.

Não marque R2 nem R2.2 como concluídos.

- [ ] **Step 7: executar verificação final do diff e do contrato**

```powershell
python scripts/generate_design_tokens.py --check
git diff --check
git status --short --branch
git diff --stat origin/main...HEAD
```

Expected: gerador e diff retornam 0; apenas arquivos previstos aparecem; branch é `codex/r2-1-design-tokens`.

- [ ] **Step 8: commitar e publicar a Task 4**

```powershell
git add .github/workflows/ci.yml docs/design-system.md docs/ROADMAP.md PRD.md docs/superpowers/specs/2026-08-22-casa-de-valores-r2-1-design-tokens-design.md docs/superpowers/plans/2026-08-22-casa-de-valores-r2-1-design-tokens-implementation.md
git commit -m "docs: close R2.1 design token foundation"
git push origin codex/r2-1-design-tokens
```

Expected: branch remota contém quatro commits de implementação, workspace limpo e nenhuma mudança em `main`.

- [ ] **Step 9: aguardar CI da branch e entregar para autorização de merge**

```powershell
$runId = gh run list --branch codex/r2-1-design-tokens --workflow CI --limit 1 --json databaseId --jq '.[0].databaseId'
gh run watch $runId --exit-status
```

Expected: todos os jobs obrigatórios verdes. Informar objetivamente:

- contrato JSON e saídas geradas;
- paridade Flutter/Web;
- shell Web tokenizado, ainda escuro;
- testes e contagens reais;
- commits publicados;
- próximo passo: revisar e autorizar merge da R2.1 em `main`.

Não mesclar e não iniciar R2.2 sem autorização explícita.
