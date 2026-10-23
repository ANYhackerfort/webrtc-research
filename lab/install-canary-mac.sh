#!/usr/bin/env bash
set -euo pipefail
[[ $(uname -s) == Darwin ]] || { echo 'Run this installer on macOS.' >&2; exit 1; }
for app in '/Applications/Google Chrome Canary.app' "$HOME/Applications/Google Chrome Canary.app"; do
  if [[ -x $app/Contents/MacOS/'Google Chrome Canary' ]]; then
    "$app/Contents/MacOS/Google Chrome Canary" --version
    echo "Already installed: $app"
    exit 0
  fi
done
mkdir -p "$HOME/Downloads"
dmg=${CANARY_DMG:-}
task_tmp_dir=$(mktemp -d "${TMPDIR:-/tmp}/scream-canary-install-XXXXXX")
mkdir "$task_tmp_dir/mount"
mounted=false
cleanup() {
  if $mounted; then hdiutil detach "$task_tmp_dir/mount" -quiet || return; fi
  [[ ! -d $task_tmp_dir/staged ]] || rm -rf "$task_tmp_dir/staged"
  rmdir "$task_tmp_dir/mount" "$task_tmp_dir" 2>/dev/null || true
}
trap cleanup EXIT
if [[ -z $dmg ]]; then
  dmg=$(mktemp "$HOME/Downloads/GoogleChromeCanary-XXXXXX")
  mv "$dmg" "$dmg.dmg"
  dmg="$dmg.dmg"
  echo 'Downloading Chrome Canary directly from Google…'
  curl -fL --retry 2 https://dl.google.com/chrome/mac/universal/canary/GoogleChromeCanary.dmg -o "$dmg"
fi
[[ -r $dmg ]] || { echo "Installer is unreadable: $dmg" >&2; exit 1; }
hdiutil attach "$dmg" -readonly -nobrowse -mountpoint "$task_tmp_dir/mount" -quiet
mounted=true
source_app="$task_tmp_dir/mount/Google Chrome Canary.app"
mkdir "$task_tmp_dir/staged"
staged_app="$task_tmp_dir/staged/Google Chrome Canary.app"
# Do not copy Finder metadata/resource forks that invalidate strict bundle checks.
ditto --norsrc --noextattr "$source_app" "$staged_app"
codesign --verify --deep --strict "$staged_app"
signing_info=$(codesign -dv --verbose=4 "$staged_app" 2>&1)
grep -Fxq 'TeamIdentifier=EQHXZ8M8AV' <<< "$signing_info" || {
  echo 'The app does not have the expected Google signing identity.' >&2
  exit 1
}
if [[ -w /Applications ]]; then
  destination='/Applications/Google Chrome Canary.app'
else
  mkdir -p "$HOME/Applications"
  destination="$HOME/Applications/Google Chrome Canary.app"
fi
[[ ! -e $destination ]] || { echo "Destination already exists: $destination" >&2; exit 1; }
mv "$staged_app" "$destination"
"$destination/Contents/MacOS/Google Chrome Canary" --version
echo "Installed: $destination"
echo "Installer saved: $dmg"
