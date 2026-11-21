#!/bin/bash
set -euo pipefail
case "$RELEASE_PLATFORM" in
    windows)
        tag=windows-v1.2.0
        asset=EzEQ-Windows-11-Intel-AMD-x64-Setup.exe
        title='Windows 11 (Intel or AMD, x64)'
        steps='Run Setup. VB-CABLE by VB-Audio is included. Restart if prompted. Open EzEQ and follow the Windows Sound settings guide.'
        ;;
    macos)
        tag=macos-v1.3.0
        asset=EzEQ-macOS-Apple-Silicon-and-Intel.dmg
        title='macOS 14.2+ (Apple Silicon or Intel)'
        steps='Open the disk image and drag EzEQ to Applications. Launch EzEQ and allow system audio capture when prompted.'
        ;;
    *) exit 2 ;;
esac
test -s "release/$asset"
(cd release && sha256sum "$asset" > "$asset.sha256")
url="https://github.com/$GITHUB_REPOSITORY/releases/download/$tag/$asset"
printf '## Download EzEQ for %s\n\n[Download the installer](%s)\n\n%s\n' "$title" "$url" "$steps" > release/notes.md
if gh release view "$tag" >/dev/null 2>&1; then
    released_sha="$(gh api "repos/$GITHUB_REPOSITORY/commits/$tag" --jq .sha)"
    if [[ "$released_sha" != "$GITHUB_SHA" ]]; then
        echo "::error::Release $tag is attached to a different commit. Set a new version before publishing."
        exit 1
    fi
    echo "Release $tag already exists for this commit. Verifying the published installer."
else
    gh release create "$tag" --target "$GITHUB_SHA" --title "EzEQ for $title" \
        --notes-file release/notes.md "release/$asset" "release/$asset.sha256"
fi
curl --fail --silent --show-error --location --retry 4 --retry-all-errors -o "release/public-$asset" "$url"
if ! cmp "release/$asset" "release/public-$asset"; then
    curl --fail --silent --show-error --location -o "release/$asset.sha256" "$url.sha256"
    (cd release && mv "public-$asset" "$asset" && sha256sum -c "$asset.sha256")
else
    curl --fail --silent --show-error --location -o "release/public.sha256" "$url.sha256"
    cmp "release/$asset.sha256" release/public.sha256
fi

# Replace just the platform row and preserve the other platform and README edits.
git fetch origin main
git checkout -B release-readme FETCH_HEAD
DOWNLOAD="- [Download EzEQ for $title]($url)"
export DOWNLOAD RELEASE_PLATFORM
python3 - <<'PY'
import os
import re
from pathlib import Path
readme = Path("README.md")
platform = os.environ["RELEASE_PLATFORM"]
pattern = rf"(?m)^- .* <!-- download:{platform} -->$"
new, count = re.subn(pattern, lambda _: f"{os.environ['DOWNLOAD']} <!-- download:{platform} -->", readme.read_text())
if count != 1:
    raise SystemExit("Expected one platform download row in README.md")
readme.write_text(new)
PY
if ! git diff --quiet -- README.md; then
    git add README.md
    git -c user.name='github-actions[bot]' -c user.email='41898282+github-actions[bot]@users.noreply.github.com' \
        commit -m "Link to the EzEQ $RELEASE_PLATFORM download"
    git push origin HEAD:main
fi
