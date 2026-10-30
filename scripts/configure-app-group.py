#!/usr/bin/env python3
"""Select the provisioned App Group used at runtime after IPA re-signing."""

import argparse
import os
from pathlib import Path
import re


# Explicit counts make an upstream layout change fail before any file is changed.
SOURCES = {
    "submodules/TelegramUI/Sources/AppDelegate.swift": 2,
    "Telegram/NotificationService/Sources/NotificationService.swift": 1,
    "Telegram/NotificationContent/NotificationViewController.swift": 1,
    "Telegram/Share/ShareRootController.swift": 1,
    "Telegram/SiriIntents/IntentHandler.swift": 2,
    "Telegram/WidgetKitWidget/TodayViewController.swift": 1,
    "Telegram/BroadcastUpload/BroadcastUploadExtension.swift": 1,
    "submodules/WidgetItems/Sources/WidgetItems.swift": 1,
}
ORIGINAL = r'"group.\(baseAppBundleId)"'
LOOKUP = 'AyuAppGroupResolver.groupIdentifier(configured: Bundle.main.object(forInfoDictionaryKey: "AyuGramAppGroup") as? String, fallback: ' + ORIGINAL + ')'
PLIST_ANCHOR = '''    name = "AppNameInfoPlist",
    extension = "plist",
    template =
    """
'''
MAIN_PLIST_ANCHOR = PLIST_ANCHOR.replace('"AppNameInfoPlist"', '"TelegramInfoPlist"').replace('template =\n', 'template = \n')
APP_DELEGATE = "submodules/TelegramUI/Sources/AppDelegate.swift"
FALLBACK = "        if maybeAppGroupUrl == nil {\n"
MIGRATION = '''        // Import the previous sideloaded build's private data before opening any database.
        if let sharedUrl = maybeAppGroupUrl, let legacyUrl = try? FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: false) {
            do {
                try ayuMigrateLegacyAppGroupData(from: legacyUrl, to: sharedUrl)
            } catch {
                NSLog("AyuGram: could not import private data into the shared App Group: %@", String(describing: error))
                // Keep using the intact private copy if migration fails (e.g. insufficient space).
                maybeAppGroupUrl = nil
            }
        }
'''


def configure(root: Path, group: str) -> int:
    if group and not re.fullmatch(r"group\.[A-Za-z0-9-]+(?:\.[A-Za-z0-9-]+)*", group):
        raise ValueError("App Group must be a complete identifier starting with group., without wildcards")

    helper = Path(__file__).resolve().parents[1] / "runtime/AyuAppGroupMigration.swift"
    resolver = helper.with_name("AyuAppGroupResolver.swift").read_text()
    updates = {}
    for relative, expected in SOURCES.items():
        path = root / relative
        text = path.read_text()
        if text.count(ORIGINAL) != expected:
            raise ValueError(f"{relative}: expected {expected} App Group references; check the Telegram tag and AyuGram patch")
        # Keep the bundle-derived fallback: some scopes otherwise leave baseAppBundleId
        # unused, which fails the upstream build with -warnings-as-errors.
        updates[path] = text.replace(ORIGINAL, LOOKUP)
        updates[path.parent / 'AyuAppGroupResolver.swift'] = resolver

    # Extensions use AppNameInfoPlist; the app uses TelegramInfoPlist instead.
    # Setting only the former silently leaves Bundle.main on the default group.
    build = root / "Telegram/BUILD"
    build_text = build.read_text()
    for anchor in (PLIST_ANCHOR, MAIN_PLIST_ANCHOR):
        if build_text.count(anchor) != 1:
            raise ValueError("Telegram/BUILD: missing main or extension Info.plist fragment")
        if group:
            build_text = build_text.replace(
                anchor,
                anchor + f"    <key>AyuGramAppGroup</key>\n    <string>{group}</string>\n",
            )
    updates[build] = build_text

    delegate = root / APP_DELEGATE
    if updates[delegate].count(FALLBACK) != 1:
        raise ValueError("AppDelegate: missing AyuGram private-container fallback; apply AyuGram patches first")
    updates[delegate] = updates[delegate].replace(FALLBACK, MIGRATION + FALLBACK)
    updates[root / "submodules/TelegramUI/Sources/AyuGram/AyuAppGroupMigration.swift"] = helper.read_text()

    # Keep the fake signing entitlements unchanged: the fake profiles only permit the
    # original group. Feather supplies the real profile's groups when it re-signs the IPA.
    for path, text in updates.items():
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(text)
    return sum(SOURCES.values())


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("telegram", type=Path)
    args = parser.parse_args()
    count = configure(args.telegram, os.environ.get("AYUGRAM_APP_GROUP", "").strip())
    print(f"Configured {count} runtime App Group references" if count else "Using the default Telegram App Group")
