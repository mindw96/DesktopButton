#!/usr/bin/env python3
"""Check release metadata before publishing; archive signing uses Sparkle's CLI."""
import base64
import pathlib
import plistlib
import sys
import xml.etree.ElementTree as ET


def require(condition, message):
    if not condition:
        raise SystemExit(message)


feed, archive, app = map(pathlib.Path, sys.argv[1:])
with (app / 'Contents/Info.plist').open('rb') as file:
    info = plistlib.load(file)
namespace = '{http://www.andymatuschak.org/xml-namespaces/sparkle}'
item = ET.parse(feed).find('channel/item')
require(item is not None, 'Missing update item')
enclosure = item.find('enclosure')
require(enclosure is not None, 'Missing update archive')
require(item.findtext(namespace + 'version') == info['CFBundleVersion'], 'Wrong build number')
require(item.findtext(namespace + 'shortVersionString') == info['CFBundleShortVersionString'], 'Wrong version')
require(item.findtext(namespace + 'minimumSystemVersion') == info['LSMinimumSystemVersion'], 'Wrong minimum OS')
expected_url = (f"https://github.com/mindw96/DesktopButton/releases/download/"
                f"v{info['CFBundleShortVersionString']}/{archive.name}")
require(enclosure.attrib['url'] == expected_url, 'Wrong release download URL')
require(int(enclosure.attrib['length']) == archive.stat().st_size, 'Wrong archive size')
require(len(base64.b64decode(enclosure.attrib[namespace + 'edSignature'], validate=True)) == 64, 'Invalid signature')
require(len(base64.b64decode(info['SUPublicEDKey'], validate=True)) == 32, 'Invalid public key')
require(info['SUFeedURL'] == 'https://raw.githubusercontent.com/mindw96/DesktopButton/main/appcast.xml', 'Wrong feed URL')
print(f"PASS: appcast version {info['CFBundleVersion']}, URL, size, and signature format")
