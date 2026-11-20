import sys

analysis = Analysis(
    ["ezeq.py"],
    binaries=[],
    datas=[],
    hiddenimports=[],
)
archive = PYZ(analysis.pure)
app = EXE(
    archive,
    analysis.scripts,
    [],
    exclude_binaries=True,
    name="EzEQ",
    console=False,
)
files = COLLECT(app, analysis.binaries, analysis.datas, name="EzEQ")
if sys.platform == "darwin":
    bundle = BUNDLE(
        files,
        name="EzEQ.app",
        bundle_identifier="app.ezeq.desktop",
        info_plist={
            "NSMicrophoneUsageDescription": "EzEQ captures audio from your selected virtual audio device.",
        },
    )
