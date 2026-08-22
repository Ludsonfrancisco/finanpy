import argparse
import colorsys
import json
import math
import re
import sys
from collections.abc import Callable
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
FIXED_INTEGER_GROUPS = {
    'spacing': {
        'xxs': 4, 'xs': 8, 'sm': 12, 'md': 16, 'lg': 24, 'xl': 32, 'xxl': 48,
    },
    'radius': {'sm': 8, 'md': 12, 'lg': 16, 'xl': 24, 'pill': 9999},
    'border': {'default': 1, 'focus': 2},
    'motion.duration': {'fast': 160, 'standard': 200, 'slow': 240},
    'breakpoint': {'desktop': 900},
}
REQUIRED_ELEVATIONS = {'flat', 'raised', 'modal'}
ELEVATION_FIELDS = {'offsetY', 'blur', 'lightOpacity', 'darkOpacity'}
REQUIRED_TYPOGRAPHY_STYLES = {
    'caption', 'label', 'body', 'title', 'headline', 'financial',
}
TYPOGRAPHY_STYLE_FIELDS = {'fontSize', 'lineHeight', 'fontWeight'}
MAPPING_RULES = (
    ('color', {'primitive', 'semantic'}, True),
    ('color.primitive', set(), False),
    ('color.semantic', {'light', 'dark'}, True),
    ('color.semantic.light', set(), False),
    ('color.semantic.dark', set(), False),
    ('elevation', REQUIRED_ELEVATIONS, False),
    ('motion', {'duration', 'standardCurve'}, True),
    ('typography', {'webFontFamily', 'weights', 'styles'}, True),
    ('typography.styles', REQUIRED_TYPOGRAPHY_STYLES, False),
)
DART_RESERVED_WORDS = {
    'abstract', 'as', 'assert', 'async', 'await', 'base', 'break', 'case',
    'catch', 'class', 'const', 'continue', 'covariant', 'default', 'deferred',
    'do', 'dynamic', 'else', 'enum', 'export', 'extends', 'extension',
    'external', 'factory', 'false', 'final', 'finally', 'for', 'Function',
    'get', 'hide', 'if', 'implements', 'import', 'in', 'interface', 'is',
    'late', 'library', 'macros', 'mixin', 'new', 'null', 'of', 'on',
    'operator', 'part', 'required', 'rethrow', 'return', 'sealed', 'set',
    'show', 'static', 'super', 'switch', 'sync', 'this', 'throw', 'true',
    'try', 'typedef', 'var', 'void', 'while', 'when', 'with', 'yield',
}


class ContractError(ValueError):
    pass


def _reject_duplicate_keys(pairs: list[tuple[str, Any]]) -> dict[str, Any]:
    result: dict[str, Any] = {}
    for key, value in pairs:
        if key in result:
            raise ContractError(f'duplicate JSON key: {key}')
        result[key] = value
    return result


def load_contract(path: Path) -> dict[str, Any]:
    try:
        value = json.loads(
            path.read_text(encoding='utf-8'),
            object_pairs_hook=_reject_duplicate_keys,
        )
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


def _resolve(
    contract: dict[str, Any],
    value: Any,
    visited: set[str] | None = None,
) -> Any:
    if not isinstance(value, str):
        return value
    match = REFERENCE.fullmatch(value)
    if not match:
        return value
    reference = match.group(1)
    visited = set() if visited is None else visited
    if reference in visited:
        raise ContractError(f'cyclic token reference: {reference}')
    resolved = _lookup(contract, reference)
    return _resolve(contract, resolved, {*visited, reference})


def _rgb(hex_color: str) -> tuple[int, int, int]:
    return tuple(int(hex_color[index:index + 2], 16) for index in (1, 3, 5))


def _is_purple(hex_color: str) -> bool:
    red, green, blue = (channel / 255 for channel in _rgb(hex_color))
    hue, saturation, _ = colorsys.rgb_to_hsv(red, green, blue)
    return 230 <= hue * 360 <= 330 and saturation > 0.05


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


def _schema_value(contract: dict[str, Any], dotted_path: str) -> Any:
    value: Any = contract
    for segment in dotted_path.split('.'):
        if not isinstance(value, dict) or segment not in value:
            raise ContractError(f'missing required field: {dotted_path}')
        value = value[segment]
    return value


def _require_mapping(
    value: Any,
    path: str,
    required: set[str],
    exact: bool,
) -> dict[str, Any]:
    if not isinstance(value, dict):
        raise ContractError(f'{path} must be an object')
    missing = required - value.keys()
    if missing:
        raise ContractError(f'{path} missing required fields: {sorted(missing)}')
    unexpected = value.keys() - required if exact else set()
    if unexpected:
        raise ContractError(f'{path} has unexpected fields: {sorted(unexpected)}')
    return value


def _require_number(
    value: Any,
    path: str,
    *,
    integer: bool = False,
    minimum: float | None = None,
    maximum: float | None = None,
) -> int | float:
    expected_type = int if integer else (int, float)
    if isinstance(value, bool) or not isinstance(value, expected_type):
        kind = 'an integer' if integer else 'a number'
        raise ContractError(f'{path} must be {kind}')
    if isinstance(value, float) and not math.isfinite(value):
        raise ContractError(f'{path} must be finite')
    if minimum is not None and value < minimum:
        raise ContractError(f'{path} must be at least {minimum}')
    if maximum is not None and value > maximum:
        raise ContractError(f'{path} must be at most {maximum}')
    return value


def _validate_schema(contract: dict[str, Any]) -> None:
    _require_mapping(contract, 'contract', REQUIRED_TOP_LEVEL, False)
    if type(contract['schemaVersion']) is not int or contract['schemaVersion'] != 1:
        raise ContractError('schemaVersion must be the integer 1')

    for path, required, exact in MAPPING_RULES:
        _require_mapping(_schema_value(contract, path), path, required, exact)
    if not contract['color']['primitive']:
        raise ContractError('color.primitive must not be empty')

    for path, expected in FIXED_INTEGER_GROUPS.items():
        values = _require_mapping(_schema_value(contract, path), path, set(expected), True)
        for name, expected_value in expected.items():
            value = _require_number(values[name], f'{path}.{name}', integer=True)
            if value != expected_value:
                raise ContractError(f'{path}.{name} must be {expected_value}')

    curve = contract['motion']['standardCurve']
    if not isinstance(curve, list) or len(curve) != 4:
        raise ContractError('motion.standardCurve must contain four numbers')
    for index, value in enumerate(curve):
        _require_number(value, f'motion.standardCurve[{index}]')
    if curve != [0.2, 0, 0, 1]:
        raise ContractError('motion.standardCurve must be [0.2, 0, 0, 1]')

    for name, elevation in contract['elevation'].items():
        path = f'elevation.{name}'
        values = _require_mapping(elevation, path, ELEVATION_FIELDS, True)
        _require_number(values['offsetY'], f'{path}.offsetY', minimum=0)
        _require_number(values['blur'], f'{path}.blur', minimum=0)
        _require_number(
            values['lightOpacity'], f'{path}.lightOpacity', minimum=0, maximum=1,
        )
        _require_number(
            values['darkOpacity'], f'{path}.darkOpacity', minimum=0, maximum=1,
        )

    families = contract['typography']['webFontFamily']
    if not isinstance(families, list) or not families:
        raise ContractError('typography.webFontFamily must be a non-empty list')
    if any(not isinstance(family, str) or not family.strip() for family in families):
        raise ContractError('typography.webFontFamily entries must be non-empty strings')

    weights = contract['typography']['weights']
    if not isinstance(weights, list):
        raise ContractError('typography.weights must be a list')
    for index, weight in enumerate(weights):
        _require_number(weight, f'typography.weights[{index}]', integer=True, minimum=1)
    if weights != [400, 500, 600, 700]:
        raise ContractError('typography.weights must be 400, 500, 600, 700')

    for name, style in contract['typography']['styles'].items():
        path = f'typography.styles.{name}'
        values = _require_mapping(style, path, TYPOGRAPHY_STYLE_FIELDS, True)
        font_size = _require_number(values['fontSize'], f'{path}.fontSize')
        line_height = _require_number(values['lineHeight'], f'{path}.lineHeight')
        font_weight = _require_number(
            values['fontWeight'], f'{path}.fontWeight', integer=True,
        )
        if font_size <= 0:
            raise ContractError(f'{path}.fontSize must be greater than zero')
        if line_height <= 0:
            raise ContractError(f'{path}.lineHeight must be greater than zero')
        if font_weight not in weights:
            raise ContractError(f'{path}.fontWeight must use typography.weights')


def _reject_identifier_collisions(
    names: list[str],
    normalize: Callable[[str], str],
    target: str,
) -> None:
    identifiers: dict[str, str] = {}
    for name in names:
        identifier = normalize(name)
        previous = identifiers.get(identifier)
        if previous is not None and previous != name:
            raise ContractError(
                f'{target} identifier collision: {previous!r} and {name!r} '
                f'both normalize to {identifier!r}'
            )
        identifiers[identifier] = name


def _validate_identifier_collisions(contract: dict[str, Any]) -> None:
    primitives = list(contract['color']['primitive'])
    _reject_identifier_collisions(primitives, _kebab, 'CSS')
    _reject_identifier_collisions(
        primitives,
        lambda name: _dart_identifier(name),
        'Dart',
    )

    for mode in ('light', 'dark'):
        semantic = list(_flatten(contract['color']['semantic'][mode]))
        _reject_identifier_collisions([*primitives, *semantic], _kebab, 'CSS')
        _reject_identifier_collisions(
            semantic,
            lambda name: _dart_identifier(_camel(name)),
            'Dart',
        )

    for group in ('spacing', 'radius', 'border', 'breakpoint'):
        names = list(contract[group])
        _reject_identifier_collisions(names, _kebab, 'CSS')
        _reject_identifier_collisions(
            names,
            lambda name: _dart_identifier(name),
            'Dart',
        )

    for group in ('elevation',):
        names = list(contract[group])
        _reject_identifier_collisions(names, _kebab, 'CSS')
        _reject_identifier_collisions(names, lambda name: name, 'Dart')

    duration_names = list(contract['motion']['duration'])
    _reject_identifier_collisions(duration_names, _kebab, 'CSS')
    _reject_identifier_collisions(
        duration_names,
        lambda name: _dart_identifier(f'{name}Milliseconds'),
        'Dart',
    )

    style_names = list(contract['typography']['styles'])
    _reject_identifier_collisions(style_names, _kebab, 'CSS')
    for suffix in ('FontSize', 'LineHeight', 'FontWeight'):
        _reject_identifier_collisions(
            style_names,
            lambda name, suffix=suffix: _dart_identifier(f'{name}{suffix}'),
            'Dart',
        )


def _validate_contract(contract: dict[str, Any]) -> None:
    _validate_schema(contract)

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
        for name, color in resolved.items():
            if not isinstance(color, str) or not HEX_COLOR.fullmatch(color):
                raise ContractError(f'{mode}.{name} must resolve to a valid color')
            if _is_purple(color):
                raise ContractError(f'purple family is forbidden: {mode}.{name}')
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

    _validate_identifier_collisions(contract)


def validate_contract(contract: dict[str, Any]) -> None:
    try:
        _validate_contract(contract)
    except ContractError:
        raise
    except (AttributeError, KeyError, TypeError, ValueError) as error:
        raise ContractError(f'invalid design token contract: {error}') from error


def _kebab(value: str) -> str:
    return re.sub(r'(?<!^)(?=[A-Z])', '-', value).replace('.', '-').lower()


def _camel(value: str) -> str:
    parts = value.split('.')
    return parts[0] + ''.join(part[:1].upper() + part[1:] for part in parts[1:])


def _dart_identifier(value: str) -> str:
    return f'{value}Value' if value in DART_RESERVED_WORDS else value


def _css_font_family(families: list[str]) -> str:
    return ', '.join(f'"{item}"' if ' ' in item else item for item in families)


def _rgba(hex_color: str, opacity: float) -> str:
    red, green, blue = _rgb(hex_color)
    return f'rgba({red}, {green}, {blue}, {_number(opacity)})'


def _number(value: int | float) -> str:
    return str(value)


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
    curve = ', '.join(_number(value) for value in contract['motion']['standardCurve'])
    lines.append(f'  --lar-motion-curve-standard: cubic-bezier({curve});')
    lines.append(
        f'  --lar-font-family-sans: {_css_font_family(contract["typography"]["webFontFamily"])};'
    )
    for name, style in contract['typography']['styles'].items():
        key = _kebab(name)
        lines.append(f'  --lar-font-size-{key}: {style["fontSize"]}px;')
        lines.append(f'  --lar-line-height-{key}: {_number(style["lineHeight"])};')
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
    return f'{value}.0' if isinstance(value, int) else _number(value)


def render_dart(contract: dict[str, Any]) -> str:
    validate_contract(contract)
    lines = [
        '// Generated from design/tokens.json. Do not edit manually.',
        "import 'package:flutter/material.dart';",
        '',
        'abstract final class LarGeneratedColors {',
    ]
    for name, color in sorted(contract['color']['primitive'].items()):
        lines.append(f'  static const {_dart_identifier(name)} = {_dart_color(color)};')
    lines.append('}')

    for mode in ('Light', 'Dark'):
        semantic = _flatten(contract['color']['semantic'][mode.lower()])
        lines.extend(['', f'abstract final class LarGenerated{mode}Colors {{'])
        for name, value in sorted(semantic.items()):
            identifier = _dart_identifier(_camel(name))
            lines.append(f'  static const {identifier} = {_dart_color(_resolve(contract, value))};')
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
            lines.append(f'  static const {_dart_identifier(name)} = {_dart_double(value)};')
        lines.append('}')

    lines.extend(['', 'abstract final class LarGeneratedMotion {'])
    for name, value in contract['motion']['duration'].items():
        identifier = _dart_identifier(f'{name}Milliseconds')
        lines.append(f'  static const {identifier} = {value};')
    curve = ', '.join(_number(value) for value in contract['motion']['standardCurve'])
    lines.append(f'  static const standardCurve = Cubic({curve});')
    lines.append('}')

    lines.extend(['', 'abstract final class LarGeneratedTypography {'])
    for name, style in contract['typography']['styles'].items():
        lines.append(f'  static const {_dart_identifier(f"{name}FontSize")} = {_dart_double(style["fontSize"])};')
        lines.append(f'  static const {_dart_identifier(f"{name}LineHeight")} = {_number(style["lineHeight"])};')
        lines.append(f'  static const {_dart_identifier(f"{name}FontWeight")} = FontWeight.w{style["fontWeight"]};')
    lines.append('}')

    lines.extend(['', 'abstract final class LarGeneratedElevation {'])
    for name, value in contract['elevation'].items():
        lines.append(f'  static const {_dart_identifier(f"{name}OffsetY")} = {_dart_double(value["offsetY"])};')
        lines.append(f'  static const {_dart_identifier(f"{name}Blur")} = {_dart_double(value["blur"])};')
        lines.append(f'  static const {_dart_identifier(f"light{name.title()}Opacity")} = {_number(value["lightOpacity"])};')
        lines.append(f'  static const {_dart_identifier(f"dark{name.title()}Opacity")} = {_number(value["darkOpacity"])};')
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
