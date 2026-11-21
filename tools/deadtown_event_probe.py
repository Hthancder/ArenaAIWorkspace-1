#!/usr/bin/env python3
"""Translate the limited legacy GMX actions used by Dead Town for VM compilation probes.

This is not a game converter: generated code alone is not a packaged game and
is not proven equivalent to GameMaker's action execution semantics. A separate
disposable VM experiment may attach matching events for diagnostics only.
Unknown action kinds fail closed instead of being dropped.
"""
from __future__ import annotations

import argparse
import json
from pathlib import Path
import xml.etree.ElementTree as ET


class UnsupportedAction(ValueError):
    pass


def close_trailing_block_comment(source: str) -> str:
    """Stop an action's unterminated comment from consuming following actions.

    GameMaker accepts the end of an individual code action as the end of a
    comment. Once actions are concatenated, restore that boundary explicitly.
    """
    state = 'code'
    i = 0
    while i < len(source):
        c = source[i]
        pair = source[i:i + 2]
        if state == 'code':
            if pair == '//':
                state = 'line'
                i += 2
                continue
            if pair == '/*':
                state = 'block'
                i += 2
                continue
            if c in ('"', "'"):
                state = c
        elif state == 'line':
            if c in '\r\n':
                state = 'code'
        elif state == 'block':
            if pair == '*/':
                state = 'code'
                i += 2
                continue
        else:
            if c == '\\':
                i += 2
                continue
            if c == state:
                state = 'code'
        i += 1
    if state == 'block':
        return source + '\n*/\n'
    if state in ('"', "'"):
        raise UnsupportedAction('unterminated string in code action')
    return source


def translate_actions(actions: list[ET.Element]) -> str:
    def field(a: ET.Element, key: str) -> str:
        value = a.findtext(key)
        if value is None:
            raise UnsupportedAction(f'missing action {key}')
        return value

    def args(a: ET.Element) -> list[str]:
        return [(x.findtext('string') or '') for x in a.findall('./arguments/argument')]

    def require_context(a: ET.Element) -> None:
        if field(a, 'whoName') != 'self' or field(a, 'relative') != '0':
            raise UnsupportedAction('non-self or relative action')

    def statement(i: int) -> tuple[str, int]:
        if i >= len(actions):
            raise UnsupportedAction('missing statement')
        a = actions[i]
        aid = field(a, 'id')
        require_context(a)
        if aid == '422':  # DnD begin/end group
            items = []
            i += 1
            while i < len(actions) and field(actions[i], 'id') != '424':
                child, i = statement(i)
                items.append(child)
            if i >= len(actions):
                raise UnsupportedAction('unclosed action block')
            require_context(actions[i])
            return '{\n' + '\n'.join(items) + '\n}', i + 1
        if aid in ('424', '421'):
            raise UnsupportedAction(f'unexpected block marker {aid}')
        if aid == '603':
            values = args(a)
            if len(values) != 1:
                raise UnsupportedAction('execute-code expects one argument')
            # Newlines ensure a trailing GML comment cannot swallow the brace.
            return '{\n' + close_trailing_block_comment(values[0]) + '\n}', i + 1
        if aid == '301':
            values = args(a)
            if len(values) != 2 or not values[1].isdigit() or not 0 <= int(values[1]) <= 11:
                raise UnsupportedAction('unsupported alarm arguments')
            if not values[0].strip():
                raise UnsupportedAction('empty alarm value')
            return f'alarm[{values[1]}] = ({values[0]});', i + 1
        if aid in ('612', '408'):
            values = args(a)
            if aid == '612':
                if len(values) != 3 or values[2] != '0':
                    raise UnsupportedAction('only equal comparison is supported')
                condition = f'(({values[0]}) == ({values[1]}))'
            else:
                if len(values) != 1:
                    raise UnsupportedAction('if expression expects one argument')
                condition = f'({values[0]})'
            if field(a, 'isnot') == '-1':
                condition = f'!({condition})'
            elif field(a, 'isnot') != '0':
                raise UnsupportedAction('unknown isnot flag')
            yes, i = statement(i + 1)
            result = f'if ({condition})\n{yes}'
            if i < len(actions) and field(actions[i], 'id') == '421':
                require_context(actions[i])
                no, i = statement(i + 1)
                result += f'\nelse\n{no}'
            return result, i
        raise UnsupportedAction(f'unsupported action {aid}')

    output = []
    index = 0
    while index < len(actions):
        text, index = statement(index)
        output.append(text)
    return '\n'.join(output) + '\n'


def extract_events(project: Path) -> list[dict[str, object]]:
    result: list[dict[str, object]] = []
    for file in sorted((project / 'objects').glob('*.object.gmx')):
        name = file.name.removesuffix('.object.gmx')
        root = ET.parse(file).getroot()
        for event in root.findall('./events/event'):
            try:
                code = translate_actions(event.findall('action'))
            except UnsupportedAction as exc:
                raise UnsupportedAction(f'{name} {event.attrib}: {exc}') from exc
            result.append({'object': name, 'attributes': dict(event.attrib), 'gml': code})
    return result


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('project', type=Path)
    parser.add_argument('output', type=Path)
    args = parser.parse_args()
    if not (args.project / 'objects').is_dir():
        parser.error('project has no objects directory')
    events = extract_events(args.project)
    args.output.write_text(json.dumps(events, ensure_ascii=False), encoding='utf-8')
    print(f'Prepared {len(events)} event bodies for compilation probe; not event bindings or a game.')


if __name__ == '__main__':
    main()
