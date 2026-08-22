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
