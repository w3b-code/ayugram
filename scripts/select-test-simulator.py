#!/usr/bin/env python3
import json
from pathlib import Path
import re
import subprocess
import uuid


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
    # The upstream runner hides simctl's creation error and returns only SIM_ERROR.
    # Create a fresh device using the exact runtime/device identifiers, boot it,
    # and pass its destination to XCTest so failures retain the actual diagnosis.
    simulator = subprocess.check_output([
        'xcrun', 'simctl', 'create', 'AyuGram-tests-' + uuid.uuid4().hex[:8],
        selected['identifier'], runtime['identifier'],
    ], text=True).strip()
    subprocess.run(['xcrun', 'simctl', 'boot', simulator], check=True)
    subprocess.run(['xcrun', 'simctl', 'bootstatus', simulator, '-b'], check=True, timeout=240)
    with (root / '.bazelrc').open('a') as configuration:
        configuration.write('\ntest --test_arg=--destination=platform=ios_simulator,id=' + simulator + '\n')
    print('Booted database test destination:', simulator, flush=True)


if __name__ == '__main__':
    import argparse
    parser = argparse.ArgumentParser()
    parser.add_argument('telegram', type=Path)
    configure(parser.parse_args().telegram)
