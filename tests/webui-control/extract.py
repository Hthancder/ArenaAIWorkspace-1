import pathlib, sys
source = pathlib.Path(sys.argv[1]).read_text()
parts = []
for sig in ('bool stopWebUiFromMenu(bool stopWifi) {', 'void toggleWebUiAutoStartFromMenu() {', 'void loopOptionsWebUi() {'):
    start = source.index(sig)
    depth = 0
    end = source.index('{', start)
    while end < len(source):
        if source[end] == '{': depth += 1
        elif source[end] == '}':
            depth -= 1
            if not depth:
                end += 1
                break
        end += 1
    parts.append(source[start:end])
pathlib.Path(sys.argv[2]).write_text('\n\n'.join(parts))
