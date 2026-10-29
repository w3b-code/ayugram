import importlib.util
from pathlib import Path
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
            self.assertNotIn(app_group.ORIGINAL, text)
            self.assertEqual(text.count('"group.example.ayugram.5"'), count)
        delegate = (self.root / app_group.APP_DELEGATE).read_text()
        self.assertLess(delegate.index("try ayuMigrateLegacyAppGroupData"), delegate.index(app_group.FALLBACK))
        helper = self.root / "submodules/TelegramUI/Sources/AyuGram/AyuAppGroupMigration.swift"
        self.assertEqual(helper.read_bytes(), (REPO / "runtime/AyuAppGroupMigration.swift").read_bytes())

    def test_default_does_not_change_sources(self):
        before = {p: p.read_bytes() for p in self.root.rglob("*.swift")}
        self.assertEqual(app_group.configure(self.root, ""), 0)
        self.assertEqual(before, {p: p.read_bytes() for p in self.root.rglob("*.swift")})

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


if __name__ == "__main__":
    unittest.main()
