#!/usr/bin/env python3
import json
from pathlib import Path
import re
import subprocess


def available_runtimes():
    data = json.loads(subprocess.check_output(['xcrun', 'simctl', 'list', 'runtimes', '-j'], text=True))
    return [runtime for runtime in data['runtimes'] if runtime.get('isAvailable') and '.iOS-' in runtime['identifier']]


def configure(root: Path):
    runtimes = available_runtimes()
    if not runtimes:
        subprocess.run(['xcodebuild', '-downloadPlatform', 'iOS'], check=True)
        runtimes = available_runtimes()
    if not runtimes:
        raise RuntimeError('An installed iOS simulator runtime is required for database regression tests')
    runtime = max(runtimes, key=lambda value: tuple(int(p) for p in value['version'].split('.')))
    devices = json.loads(subprocess.check_output(['xcrun', 'simctl', 'list', 'devicetypes', '-j'], text=True))['devicetypes']
    candidates = [device for device in devices if device['name'].startswith('iPhone')]
    selected = next((device for device in candidates if device['name'] == 'iPhone 17'), candidates[0])
    build = root / 'submodules/Postbox/BUILD'
    source = build.read_text()
    pattern = r'(name = "PostboxTestRunner",\s*device_type = ")[^"]+(",\s*os_version = ")[^"]+("\s*,)'
    result, count = re.subn(pattern, lambda match: match[1] + selected['name'] + match[2] + runtime['version'] + match[3], source)
    if count != 1:
        raise RuntimeError('PostboxTestRunner definition changed upstream')
    build.write_text(result)
    print('Database tests:', selected['name'], '/ iOS', runtime['version'])


if __name__ == '__main__':
    import argparse
    parser = argparse.ArgumentParser()
    parser.add_argument('telegram', type=Path)
    configure(parser.parse_args().telegram)
