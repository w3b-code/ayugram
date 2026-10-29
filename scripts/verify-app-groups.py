#!/usr/bin/env python3
"""Check the runtime App Group in the built app and every embedded iOS extension."""
import argparse
import os
from pathlib import Path
import plistlib
import re
import zipfile


BUNDLE_PLIST = re.compile(r'^Payload/[^/]+\.app/(?:PlugIns/[^/]+\.appex/)?Info\.plist$')


def verify(ipa: Path, configured_group: str = '') -> int:
    with zipfile.ZipFile(ipa) as archive:
        bundles = {name: plistlib.loads(archive.read(name)) for name in archive.namelist()
                   if BUNDLE_PLIST.fullmatch(name)}
    main = [info for name, info in bundles.items() if '/PlugIns/' not in name]
    if len(main) != 1 or not isinstance(main[0].get('CFBundleIdentifier'), str):
        raise ValueError('IPA must contain exactly one main iOS app')
    default_group = 'group.' + main[0]['CFBundleIdentifier']
    expected = configured_group.strip() or default_group
    notification_service = False
    for name, info in bundles.items():
        actual = info.get('AyuGramAppGroup', default_group)
        if actual != expected:
            raise ValueError(f'{name}: runtime App Group {actual!r} does not match {expected!r}')
        extension = info.get('NSExtension', {})
        if extension.get('NSExtensionPointIdentifier') == 'com.apple.usernotifications.service':
            notification_service = True
    if not notification_service:
        raise ValueError('IPA is missing its notification service extension')
    return len(bundles)


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('ipa', type=Path)
    args = parser.parse_args()
    count = verify(args.ipa, os.environ.get('AYUGRAM_APP_GROUP', ''))
    print(f'Verified the same runtime App Group in the main app and {count - 1} extensions')
