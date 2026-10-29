import importlib.util
from pathlib import Path
import plistlib
import tempfile
import unittest
import zipfile


REPO = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('ipa_groups', REPO / 'scripts/verify-app-groups.py')
ipa_groups = importlib.util.module_from_spec(spec)
spec.loader.exec_module(ipa_groups)


class BuiltAppGroupTests(unittest.TestCase):
    group = 'group.example.ayugram.5'

    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.ipa = Path(self.temp.name) / 'AyuGram.ipa'

    def write_ipa(self, main_group, service_group, include_service=True):
        main = {'CFBundleIdentifier': 'ph.telegra.Telegraph'}
        service = {'CFBundleIdentifier': 'ph.telegra.Telegraph.NotificationService',
                   'NSExtension': {'NSExtensionPointIdentifier': 'com.apple.usernotifications.service'}}
        if main_group is not None:
            main['AyuGramAppGroup'] = main_group
        if service_group is not None:
            service['AyuGramAppGroup'] = service_group
        with zipfile.ZipFile(self.ipa, 'w') as archive:
            archive.writestr('Payload/Telegram.app/Info.plist', plistlib.dumps(main))
            if include_service:
                archive.writestr('Payload/Telegram.app/PlugIns/NotificationService.appex/Info.plist', plistlib.dumps(service))
            archive.writestr('Payload/Telegram.app/Frameworks/Unrelated.framework/Info.plist', plistlib.dumps({}))

    def test_main_and_extension_share_the_configured_group(self):
        self.write_ipa(self.group, self.group)
        self.assertEqual(ipa_groups.verify(self.ipa, self.group), 2)

    def test_extension_only_override_is_rejected_like_build_105(self):
        self.write_ipa(None, self.group)
        with self.assertRaisesRegex(ValueError, 'Payload/Telegram.app/Info.plist'):
            ipa_groups.verify(self.ipa, self.group)

    def test_mismatched_extension_is_rejected(self):
        self.write_ipa(self.group, 'group.other')
        with self.assertRaisesRegex(ValueError, 'NotificationService.appex'):
            ipa_groups.verify(self.ipa, self.group)

    def test_missing_notification_extension_is_rejected(self):
        self.write_ipa(self.group, self.group, include_service=False)
        with self.assertRaisesRegex(ValueError, 'missing its notification service'):
            ipa_groups.verify(self.ipa, self.group)

    def test_unconfigured_build_uses_its_bundle_derived_group(self):
        self.write_ipa(None, None)
        self.assertEqual(ipa_groups.verify(self.ipa), 2)

