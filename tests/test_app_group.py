import importlib.util
from pathlib import Path
import plistlib
import shutil
import subprocess
import tempfile
import unittest

REPO = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location("app_group", REPO / "scripts/configure-app-group.py")
app_group = importlib.util.module_from_spec(spec)
spec.loader.exec_module(app_group)


class AppGroupConfigurationTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        build = self.root / "Telegram/BUILD"
        build.parent.mkdir(parents=True, exist_ok=True)
        body = '    <key>CFBundleDisplayName</key>\n    <string>Telegram</string>\n    """\n)\n'
        build.write_text(app_group.PLIST_ANCHOR + body + app_group.MAIN_PLIST_ANCHOR + body)
        for relative, count in app_group.SOURCES.items():
            path = self.root / relative
            path.parent.mkdir(parents=True, exist_ok=True)
            source = ("let appGroupName = " + app_group.ORIGINAL + "\n") * count
            if relative == app_group.APP_DELEGATE:
                source += app_group.FALLBACK + "        }\n"
            path.write_text(source)

    def test_same_group_for_main_app_and_every_extension(self):
        self.assertEqual(app_group.configure(self.root, "group.example.ayugram.5"), 10)
        for relative, count in app_group.SOURCES.items():
            text = (self.root / relative).read_text()
            self.assertEqual(text.count(app_group.LOOKUP), count)
            self.assertNotIn('"group.example.ayugram.5"', text)
        fragments = (self.root / "Telegram/BUILD").read_text().split('"""')[1::2]
        self.assertEqual(len(fragments), 2)
        for fragment in fragments:
            plist = plistlib.loads(('<plist version="1.0"><dict>' + fragment + '</dict></plist>').encode())
            self.assertEqual(plist["AyuGramAppGroup"], "group.example.ayugram.5")
        delegate = (self.root / app_group.APP_DELEGATE).read_text()
        self.assertLess(delegate.index("try ayuMigrateLegacyAppGroupData"), delegate.index(app_group.FALLBACK))
        helper = self.root / "submodules/TelegramUI/Sources/AyuGram/AyuAppGroupMigration.swift"
        self.assertEqual(helper.read_bytes(), (REPO / "runtime/AyuAppGroupMigration.swift").read_bytes())

    def test_default_resolves_signed_groups_without_a_hardcoded_override(self):
        self.assertEqual(app_group.configure(self.root, ""), 10)
        self.assertNotIn('<key>AyuGramAppGroup</key>', (self.root / 'Telegram/BUILD').read_text())
        for relative in app_group.SOURCES:
            path = self.root / relative
            self.assertIn(app_group.LOOKUP, path.read_text())
            self.assertEqual((path.parent / 'AyuAppGroupResolver.swift').read_bytes(), (REPO / 'runtime/AyuAppGroupResolver.swift').read_bytes())

    def test_invalid_group_rejected_before_writing(self):
        for group in ('group.*', 'group.example"', 'group.example\n', 'example.group', 'group.'):
            with self.subTest(group=group), self.assertRaises(ValueError):
                app_group.configure(self.root, group)

    def test_upstream_change_does_not_leave_partially_configured_tree(self):
        path = self.root / "submodules/WidgetItems/Sources/WidgetItems.swift"
        path.write_text("// upstream changed its container lookup\n")
        before = {p: p.read_bytes() for p in self.root.rglob("*.swift")}
        with self.assertRaises(ValueError):
            app_group.configure(self.root, "group.example.ayugram")
        self.assertEqual(before, {p: p.read_bytes() for p in self.root.rglob("*.swift")})

    def test_missing_main_plist_fragment_rejected_before_writing(self):
        build = self.root / "Telegram/BUILD"
        build.write_text(build.read_text().replace(app_group.MAIN_PLIST_ANCHOR, 'name = "RenamedMainPlist"'))
        before = {p: p.read_bytes() for p in self.root.rglob("*") if p.is_file()}
        with self.assertRaises(ValueError):
            app_group.configure(self.root, "group.example.ayugram")
        self.assertEqual(before, {p: p.read_bytes() for p in self.root.rglob("*") if p.is_file()})

    @unittest.skipUnless(shutil.which("swiftc"), "Swift compiler required")
    def test_generated_lookup_compiles_with_warnings_as_errors(self):
        app_group.configure(self.root, "group.example.ayugram.5")
        widget = self.root / "submodules/WidgetItems/Sources/WidgetItems.swift"
        lookup = widget.read_text().split("let appGroupName = ", 1)[1].strip()
        source = self.root / "LookupRegression.swift"
        source.write_text('''import Foundation
func groupForExtension(_ appBundleIdentifier: String) -> String? {
    guard let lastDotRange = appBundleIdentifier.range(of: ".", options: [.backwards]) else { return nil }
    let baseAppBundleId = String(appBundleIdentifier[..<lastDotRange.lowerBound])
    let appGroupName = ''' + lookup + '''
    return appGroupName
}
''')
        subprocess.run(["swiftc", "-warnings-as-errors", "-typecheck", str(REPO / 'runtime/AyuAppGroupResolver.swift'), str(source)], check=True)


if __name__ == "__main__":
    unittest.main()
