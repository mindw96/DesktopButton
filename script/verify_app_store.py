#!/usr/bin/env python3
"""Verify the Store bundle before export/upload; --release checks distribution output."""

import argparse
import pathlib
import plistlib
import re
import subprocess

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("app", type=pathlib.Path)
parser.add_argument("--release", action="store_true")
args = parser.parse_args()
contents = args.app / "Contents"
info = plistlib.loads((contents / "Info.plist").read_bytes())
assert info["CFBundleIdentifier"] == "com.onebutton.desktop"
assert info["CFBundleName"] == "Folder In Bar"
assert info["LSApplicationCategoryType"] == "public.app-category.utilities"
assert info["ITSAppUsesNonExemptEncryption"] is False
assert not any(key.startswith("SU") for key in info), "Store bundle contains updater settings"
assert not list(contents.rglob("Sparkle.framework")), "Store bundle embeds Sparkle"
assert not list(contents.rglob("FolderNameMigrationHelper.app")), "Store bundle embeds rename helper"

binary = contents / "MacOS" / info["CFBundleExecutable"]
libraries = subprocess.check_output(["otool", "-L", str(binary)], text=True)
assert "Sparkle" not in libraries, "Store executable links Sparkle"
subprocess.run(["codesign", "--verify", "--deep", "--strict", str(args.app)], check=True)
signed = subprocess.run(["codesign", "-d", "--entitlements", ":-", str(args.app)],
                        capture_output=True, check=True)
entitlements = plistlib.loads(signed.stdout)
for key in ("com.apple.security.app-sandbox",
            "com.apple.security.files.user-selected.read-only",
            "com.apple.security.files.bookmarks.app-scope"):
    assert entitlements.get(key) is True, f"Missing required entitlement: {key}"
for key in ("com.apple.security.network.client",
            "com.apple.security.files.user-selected.read-write",
            "com.apple.security.cs.disable-library-validation"):
    assert not entitlements.get(key), f"Unexpected entitlement: {key}"
assert not any("temporary-exception" in key for key in entitlements)

assert info["CFBundleDevelopmentRegion"] == "en"
def read_localized_plist(path):
    # Xcode can emit localized property lists as UTF-16 XML.
    return plistlib.loads(subprocess.check_output(["plutil", "-convert", "xml1", "-o", "-", str(path)]))

for language, connect in (("en", "Connect Folder"), ("ko", "폴더 연결")):
    localized = contents / "Resources" / f"{language}.lproj"
    strings = read_localized_plist(localized / "Localizable.strings")
    plurals = read_localized_plist(localized / "Localizable.stringsdict")
    permission = read_localized_plist(localized / "InfoPlist.strings")
    assert strings["Connect Folder"] == connect, f"Missing {language} translation"
    assert "%lld items" in plurals, f"Missing {language} item-count plural rules"
    assert permission["NSDesktopFolderUsageDescription"], f"Missing {language} permission description"

privacy = plistlib.loads((contents / "Resources" / "PrivacyInfo.xcprivacy").read_bytes())
assert privacy["NSPrivacyTracking"] is False
assert privacy["NSPrivacyTrackingDomains"] == []
assert privacy["NSPrivacyCollectedDataTypes"] == []
assert privacy["NSPrivacyAccessedAPITypes"] == [{
    "NSPrivacyAccessedAPIType": "NSPrivacyAccessedAPICategoryUserDefaults",
    "NSPrivacyAccessedAPITypeReasons": ["CA92.1"],
}, {
    "NSPrivacyAccessedAPIType": "NSPrivacyAccessedAPICategoryFileTimestamp",
    "NSPrivacyAccessedAPITypeReasons": ["3B52.1"],
}]
if args.release:
    architectures = subprocess.check_output(["lipo", "-archs", str(binary)], text=True).split()
    assert {"arm64", "x86_64"}.issubset(architectures), "Store release must be Universal"
    assert not entitlements.get("com.apple.security.get-task-allow")
    signature = subprocess.run(["codesign", "-d", "--verbose=4", str(args.app)],
                               capture_output=True, text=True, check=True).stderr
    assert re.search(r"^Authority=(Apple Distribution:|3rd Party Mac Developer Application:)",
                     signature, re.MULTILINE), "Store distribution signing certificate required"
    assert "TeamIdentifier=4J7HGK26PF" in signature.splitlines(), "Wrong signing team"
    profile_data = subprocess.check_output([
        "security", "cms", "-D", "-i", str(contents / "embedded.provisionprofile")
    ])
    profile = plistlib.loads(profile_data)
    assert profile["TeamIdentifier"] == ["4J7HGK26PF"], "Wrong provisioning profile team"
    provisioned = profile["Entitlements"]
    app_identifier = provisioned.get("com.apple.application-identifier",
                                     provisioned.get("application-identifier"))
    assert app_identifier == "4J7HGK26PF.com.onebutton.desktop", "Wrong provisioned app identifier"
    assert not provisioned.get("com.apple.security.get-task-allow")
    assert not provisioned.get("get-task-allow")
print(f"Store bundle verified: {info['CFBundleShortVersionString']} ({info['CFBundleVersion']})")
