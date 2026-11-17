#!/usr/bin/env python3
"""Run the native paste/caret regression on the supplied booted iPhone simulator."""
import os
import platform
import plistlib
import subprocess
import sys
import tempfile
import time
import uuid
from pathlib import Path

root = Path(__file__).resolve().parent.parent
if len(sys.argv) != 2:
    sys.exit("Usage: checks/pairing-code-uikit.py BOOTED_SIMULATOR_UDID")
device = sys.argv[1]
simctl = ["xcrun", "simctl"]
identifier = "local.relaypad.pairing-check." + uuid.uuid4().hex
with tempfile.TemporaryDirectory(prefix="relaypad-pairing-check-") as workspace:
    app = Path(workspace) / "CodeChecks.app"
    app.mkdir()
    info = {
        "CFBundleExecutable": "CodeChecks", "CFBundleIdentifier": identifier,
        "CFBundleName": "CodeChecks", "CFBundlePackageType": "APPL", "CFBundleVersion": "1",
        "CFBundleShortVersionString": "1.0", "MinimumOSVersion": "17.0",
        "CFBundleSupportedPlatforms": ["iPhoneSimulator"], "LSRequiresIPhoneOS": True,
        "UILaunchScreen": {}, "UIDeviceFamily": [1],
    }
    (app / "Info.plist").write_bytes(plistlib.dumps(info))
    sdk = subprocess.check_output(["xcrun", "--sdk", "iphonesimulator", "--show-sdk-path"], text=True).strip()
    subprocess.run([
        "xcrun", "--sdk", "iphonesimulator", "swiftc", "-swift-version", "5", "-parse-as-library",
        "-target", platform.machine() + "-apple-ios17.0-simulator", "-sdk", sdk,
        "Shared/RemoteProtocol.swift", "Phone/PairingCodeEdit.swift", "Phone/PairingCodeField.swift",
        "checks/PairingCodeUIKitChecks.swift", "-o", str(app / "CodeChecks"),
    ], cwd=root, check=True)
    subprocess.run(["codesign", "--force", "--sign", "-", str(app)], check=True)
    subprocess.run([*simctl, "install", device, str(app)], check=True)
    try:
        token = uuid.uuid4().hex
        subprocess.run([*simctl, "launch", device, identifier], check=True,
                       env={**os.environ, "SIMCTL_CHILD_RELAYPAD_CHECK_OUTPUT": token})
        data = subprocess.check_output([*simctl, "get_app_container", device, identifier, "data"], text=True)
        result = Path(data.strip()) / "tmp" / token
        for _ in range(240):
            if result.exists():
                message = result.read_text()
                if message != "PASS":
                    sys.exit(message)
                print("UIKit paste, selection, caret and backspace checks passed.")
                break
            time.sleep(0.25)
        else:
            sys.exit("The simulator did not finish the pairing code checks.")
    finally:
        subprocess.run([*simctl, "uninstall", device, identifier], check=True)
