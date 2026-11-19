#!/usr/bin/env python3
"""Tìm selector được khai báo trong @interface của SiriX mà chưa có thân hàm.

Lỗi thật đã xảy ra ở 1.1.10–1.1.12: `- (NSString *)headersSummaryForProvider:`
nằm trong `Sources/SXPrefs.h` và được trang cấu hình gọi, nhưng chưa từng được
viết trong `.m`. Objective-C chỉ cảnh báo lúc biên dịch, nên bản phát hành vẫn
ra đời và Settings văng với `unrecognized selector`.
"""
import glob
import re
import sys

HEADERS = glob.glob('Sources/*.h') + glob.glob('Prefs/*.h')
SOURCES = glob.glob('Sources/*.m') + glob.glob('Prefs/*.m')

# Lớp của Apple / của Preferences: chỉ khai báo để biên dịch, không có thân hàm.
EXTERNAL = {'PSListController', 'PSViewController', 'PSSpecifier', 'PSTableCell',
            'PSRootController', 'PSListItemsController', 'PSEditTextCell',
            'PSSecureEditTextCell', 'PSLinkCell', 'PSLinkListCell', 'PSTitleValueCell'}


def declared():
    out = {}
    for path in HEADERS:
        text = open(path, encoding='utf-8').read()
        for match in re.finditer(r'@interface\s+([A-Za-z_]\w*)\s*(?:\([^)]*\))?[^\n]*\n(.*?)@end',
                                 text, re.S):
            cls, body = match.group(1), match.group(2)
            if cls in EXTERNAL:
                continue
            for line in body.split('\n'):
                line = line.strip()
                probe = re.match(r'^[-+]\s*\([^)]*\)\s*(.*)$', line)
                if not probe:
                    continue
                rest = probe.group(1)
                parts = re.findall(r'([A-Za-z_]\w*)\s*:', rest)
                if parts:
                    out.setdefault(cls, set()).add(':'.join(parts) + ':')
                else:
                    name = re.match(r'([A-Za-z_]\w*)', rest)
                    if name:
                        out.setdefault(cls, set()).add(name.group(1))
    return out


def implementations():
    out = {}
    for path in SOURCES:
        text = open(path, encoding='utf-8').read()
        for match in re.finditer(r'@implementation\s+([A-Za-z_]\w*)', text):
            out.setdefault(match.group(1), '')
            out[match.group(1)] += text
    return out


def has_body(body, selector):
    parts = selector.split(':')
    pattern = r'^[-+]\s*\([^)]*\)\s*'
    if selector.endswith(':'):
        for index, part in enumerate(parts[:-1]):
            pattern += re.escape(part) + r'\s*:'
            if index < len(parts) - 2:
                pattern += r'[^;{]*?'
        pattern += r'[^;{]*\{'
    else:
        pattern = r'^[-+]\s*\([^)]*\)\s*' + re.escape(selector) + r'\s*\{'
    return re.search(pattern, body, re.M) is not None


def main():
    declared_map = declared()
    impl_map = implementations()
    missing = []
    for cls, selectors in sorted(declared_map.items()):
        body = impl_map.get(cls)
        if body is None:
            missing.append((cls, '(không có @implementation)'))
            continue
        for selector in sorted(selectors):
            if not has_body(body, selector):
                missing.append((cls, selector))
    # Selector do người dùng tự khai báo trong category không thuộc lớp nào ở trên
    # vẫn được kiểm vì khoá là tên lớp trong @interface.
    if missing:
        print('   ✗ Khai báo nhưng chưa có thân hàm:')
        for cls, selector in missing:
            print(f'      {cls} → {selector}')
        return 1
    total = sum(len(s) for s in declared_map.values())
    print(f'   ✓ {total} selector / {len(declared_map)} lớp đều có thân hàm')
    return 0


if __name__ == '__main__':
    sys.exit(main())
