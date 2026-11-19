#!/usr/bin/env python3
"""Bắt các khoá specifier của Preferences bị khai sai KIỂU trong plist.

Preferences của Apple gọi `-isEqualToString:` lên một số thuộc tính specifier.
Nếu plist khai báo chúng bằng `<false/>`/`<true/>` thay vì chuỗi, mỗi lần mở
trang là một lần ném `NSInvalidArgumentException`:
    -[__NSCFBoolean isEqualToString:]: unrecognized selector

Đây đúng là lỗi đã làm trang cấu hình OpenAI (và sau đó cả Gemini) văng từ
1.1.10 tới 1.1.13. Bằng chứng từ log thiết bị + git:

  * 1.1.6 (thiết bị build 03:40, commit f0b3e42 03:38) KHÔNG có `autoCaps`
    trong plist → trang Gemini mở được, log ghi "17 specifier".
  * fd6a45c (04:59) thêm `autoCaps` dạng `<false/>` ở CẢ HAI plist.
  * Từ 1.1.10 (build 07:16) log mới có `__NSCFBoolean isEqualToString:`.
  * Địa chỉ đối tượng trong log (0x1fb075af8) giống hệt nhau qua các bản và
    giống nhau ở OpenAI lẫn Gemini — dấu hiệu của một hằng boolean dùng chung,
    không phải đối tượng của tweak.

Địa chỉ đó là `kCFBooleanFalse`, tức giá trị của `<false/>`.
"""
import glob
import plistlib
import sys

# Khoá PHẢI là chuỗi. Giá trị gợi ý trong ngoặc là những gì Preferences chấp nhận.
STRING_KEYS = {
    'autoCaps': ('none', 'sentences', 'words', 'all'),
    'autoCorrection': None,
    'cell': None,
    'detail': None,
    'label': None,
    'key': None,
    'defaults': None,
    'footerText': None,
    'title': None,
    'placeholder': None,
    'action': None,
    'alignment': None,
    'PostNotification': None,
    'confirmation': None,
    'okTitle': None,
    'cancelTitle': None,
    'description': None,
}


def walk(node, path, problems):
    if isinstance(node, dict):
        # `default` chỉ phải là chuỗi với ô nhập chữ; PSSwitchCell dùng boolean
        # hợp lệ nên phải xét theo `cell` của chính specifier đó.
        cell = node.get('cell')
        text_cell = isinstance(cell, str) and ('EditText' in cell)
        for key, value in node.items():
            where = f'{path}/{key}'
            if key == 'default' and text_cell and not isinstance(value, str):
                problems.append((where, type(value).__name__, value))
            elif key in STRING_KEYS and not isinstance(value, str):
                problems.append((where, type(value).__name__, value))
            walk(value, where, problems)
    elif isinstance(node, list):
        for index, value in enumerate(node):
            walk(value, f'{path}[{index}]', problems)


def main():
    files = sorted(glob.glob('Prefs/Resources/*.plist'))
    problems = []
    for path in files:
        try:
            data = plistlib.load(open(path, 'rb'))
        except Exception as error:  # noqa: BLE001
            problems.append((path, 'không đọc được', str(error)))
            continue
        walk(data, '', problems)

    if problems:
        print('   ✗ Khoá specifier sai kiểu (Preferences sẽ văng):')
        for where, kind, value in problems:
            print(f'      {where}: {kind} = {value!r} — phải là chuỗi')
        return 1

    print(f'   ✓ {len(files)} plist: khoá specifier đều đúng kiểu')
    return 0


if __name__ == '__main__':
    sys.exit(main())
