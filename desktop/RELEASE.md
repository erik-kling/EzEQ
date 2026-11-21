# Desktop builds and releases

Run the **Desktop builds** workflow on `main` with **publish** set to `none` to build test artifacts. The workflow also builds changes to desktop code on pushes and pull requests. Extract the outer GitHub artifact ZIP to find the Windows installer or the Mac test archive.

## Windows 11 x64

Use x64 Python 3.12 and Inno Setup 6. From the repository root, run:

```powershell
python -m pip install -r desktop/requirements.txt "pyinstaller>=6,<7"
./desktop/windows/build.ps1
```

The build reads the pinned vendor URL and SHA-256 in the script. It uses the complete original VB-CABLE ZIP. If the vendor changes the download, only update the pin after verifying the official package.

Before release, test on a clean Windows 11 Intel or AMD system:

- Install offline with administrator permission. Test an already working VB-CABLE installation, install and restart on a fresh machine, and cancel driver setup and retry.
- Verify a Windows 10 machine and a Windows on ARM machine are refused. On Windows 11, verify a standard user can run the installed app after setup.
- Play two apps through CABLE Input. Verify both stereo channels, a bass cut, mute, volume, two presets, and persistence after restart.
- Switch playback to speakers and a USB DAC. Stop and quit EzEQ, restore the physical output in Windows, and verify direct audio. Uninstall EzEQ and confirm VB-CABLE remains available.

## macOS 14.2 and newer

On a Mac with Xcode and a current macOS SDK, run `./desktop/macos/build.sh` from the repository root. The result is a universal app at `desktop/dist/EzEQ.app`. The test app has an ad hoc signature.

Before release, exercise the app on an Apple Silicon and an Intel Mac, including macOS 14.2:

- Deny system audio capture permission, verify direct playback, then grant permission and start again.
- Play two apps together. Verify the output is stereo, the controls affect it in real time, and there is no unprocessed duplicate or feedback.
- Switch from speakers to headphones and a USB DAC while running. Include a device that exposes its own input, confirm that input does not feed the output, and try 44.1 and 48 kHz. Test that unplugging the DAC, stopping, quitting, and an audio start failure leave direct playback available.
- Verify existing preview settings and five presets load, rename in place, and persist.
- Sign and notarize using the workflow, then open the resulting DMG on a clean Mac with Gatekeeper enabled and confirm installation and playback.

For notarization, set these GitHub Actions secrets: `MAC_CERTIFICATE` (base64 Developer ID Application .p12), `MAC_CERTIFICATE_PASSWORD`, `MAC_SIGNING_IDENTITY`, `MAC_NOTARY_KEY` (base64 App Store Connect .p8), `MAC_NOTARY_KEY_ID`, and `MAC_NOTARY_ISSUER_ID`. Store these in GitHub Actions secrets, not in the repository.

## Publish

Once the native acceptance checks pass, run **Desktop builds** on main. Select `windows` or `macos` and check **native_tests_passed**. The workflow publishes the platform’s installer and checksum, verifies the public download, and links it from the top of the README. It keeps developer test archives in Actions. The Mac signing step must succeed before a Mac installer can be published.
