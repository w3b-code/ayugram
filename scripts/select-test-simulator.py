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
    supported = runtime.get('supportedDeviceTypes')
    supported_ids = {device['identifier'] for device in supported} if supported else None
    candidates = [device for device in reversed(devices) if device['name'].startswith('iPhone')
                  and (supported_ids is None or device['identifier'] in supported_ids)]
    # A runtime image can support only a subset of the device profiles shipped
    # with Xcode. Do not assume that its newest iPhone profile can run this image.
    simulator = None
    for selected in candidates:
        creation = subprocess.run([
            'xcrun', 'simctl', 'create', 'AyuGram-tests-' + uuid.uuid4().hex[:8],
            selected['identifier'], runtime['identifier'],
        ], text=True, capture_output=True)
        if creation.returncode == 0:
            simulator = creation.stdout.strip()
            break
        if 'Incompatible device' not in creation.stderr:
            raise RuntimeError(creation.stderr)
        print('Skipping incompatible simulator:', selected['name'], flush=True)
    if simulator is None:
        raise RuntimeError('No iPhone device profile supports installed runtime ' + runtime['identifier'])
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
