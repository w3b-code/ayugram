#!/usr/bin/env python3
"""Give Telegram's fake provisioning profiles a later expiration date when theirs has passed.

The build only reads these profiles (openssl smime -verify -noverify, security cms -D) for the
bundle ids and entitlements of the unsigned IPA; their CMS signer is never trusted. The real
signature comes from the sideloading tool. Profiles are re-signed with a throwaway certificate.
"""
import argparse
import datetime
import plistlib
import subprocess
import tempfile
from pathlib import Path

PROFILES = 'build-system/fake-codesigning/profiles'


def utc_now():
    return datetime.datetime.now(datetime.timezone.utc).replace(tzinfo=None)


def read_profile(path: Path) -> dict:
    data = subprocess.run(['openssl', 'smime', '-inform', 'der', '-verify', '-noverify', '-in', str(path)], check=True, capture_output=True).stdout
    return plistlib.loads(data)


def refresh(root: Path, now=None, margin_days=30, valid_days=3650) -> int:
    now = now or utc_now()
    profiles = sorted((root / PROFILES).glob('*.mobileprovision'))
    if not profiles:
        raise ValueError(f'No provisioning profiles in {PROFILES}')
    refreshed = 0
    with tempfile.TemporaryDirectory() as temp:
        temp_path = Path(temp)
        key, certificate = temp_path / 'key.pem', temp_path / 'certificate.pem'
        subprocess.run(['openssl', 'req', '-x509', '-newkey', 'rsa:2048', '-nodes', '-keyout', str(key), '-out', str(certificate), '-days', str(valid_days), '-subj', '/CN=AyuGram fake provisioning'], check=True, capture_output=True)
        for path in profiles:
            profile = read_profile(path)
            expiration = profile.get('ExpirationDate')
            if isinstance(expiration, datetime.datetime) and expiration > now + datetime.timedelta(days=margin_days):
                continue
            profile['ExpirationDate'] = now + datetime.timedelta(days=valid_days)
            unsigned = temp_path / (path.name + '.plist')
            unsigned.write_bytes(plistlib.dumps(profile))
            subprocess.run(['openssl', 'smime', '-sign', '-binary', '-nodetach', '-outform', 'der', '-signer', str(certificate), '-inkey', str(key), '-in', str(unsigned), '-out', str(path)], check=True, capture_output=True)
            refreshed += 1
    return refreshed


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('telegram', type=Path)
    count = refresh(parser.parse_args().telegram)
    print(f'Refreshed {count} expiring fake provisioning profiles' if count else 'Fake provisioning profiles are valid')
