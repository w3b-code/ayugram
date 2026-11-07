import datetime
import importlib.util
from pathlib import Path
import plistlib
import shutil
import subprocess
import tempfile
import unittest

REPO = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location("fake_profiles", REPO / "scripts/refresh-fake-profiles.py")
fake_profiles = importlib.util.module_from_spec(spec)
spec.loader.exec_module(fake_profiles)


@unittest.skipUnless(shutil.which("openssl"), "OpenSSL required")
class FakeProfileTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        directory = self.root / fake_profiles.PROFILES
        directory.mkdir(parents=True)
        key, certificate = self.root / "key.pem", self.root / "certificate.pem"
        subprocess.run(["openssl", "req", "-x509", "-newkey", "rsa:2048", "-nodes", "-keyout", str(key), "-out", str(certificate), "-days", "1", "-subj", "/CN=Test"], check=True, capture_output=True)
        self.now = datetime.datetime(2026, 10, 31, 12, 0, 0)
        for name, expiration in [("Telegram", datetime.datetime(2026, 10, 30, 17, 6, 30)), ("Widget", datetime.datetime(2030, 1, 1))]:
            plist = self.root / (name + ".plist")
            plist.write_bytes(plistlib.dumps({
                "ExpirationDate": expiration,
                "Entitlements": {"application-identifier": "C67CF9S4VU.ph.telegra.Telegraph." + name},
                "DeveloperCertificates": [b"certificate"],
            }))
            subprocess.run(["openssl", "smime", "-sign", "-binary", "-nodetach", "-outform", "der", "-signer", str(certificate), "-inkey", str(key), "-in", str(plist), "-out", str(directory / (name + ".mobileprovision"))], check=True, capture_output=True)

    def profile(self, name):
        return fake_profiles.read_profile(self.root / fake_profiles.PROFILES / (name + ".mobileprovision"))

    def test_expired_profile_gets_a_later_date_and_keeps_its_contents(self):
        self.assertEqual(fake_profiles.refresh(self.root, now=self.now), 1)
        refreshed = self.profile("Telegram")
        self.assertGreater(refreshed["ExpirationDate"], self.now + datetime.timedelta(days=3000))
        self.assertEqual(refreshed["Entitlements"]["application-identifier"], "C67CF9S4VU.ph.telegra.Telegraph.Telegram")
        self.assertEqual(refreshed["DeveloperCertificates"], [b"certificate"])
        self.assertEqual(self.profile("Widget")["ExpirationDate"], datetime.datetime(2030, 1, 1))
        self.assertEqual(fake_profiles.refresh(self.root, now=self.now), 0)

    def test_missing_profiles_are_an_error(self):
        with self.assertRaises(ValueError):
            fake_profiles.refresh(self.root / "missing", now=self.now)


if __name__ == "__main__":
    unittest.main()
