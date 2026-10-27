#!/usr/bin/env bash
# Deploy the pushed HEAD to this Windows PC: wait for the CI build, download the
# NSIS installer, install it (one UAC prompt), relaunch the app. Run from WSL.
set -euo pipefail

WORKFLOW=build.yml
ARTIFACT=pomotroid-windows-x64
APP_DIR='C:\Program Files\Pomotroid'   # matches productName in src-tauri/tauri.conf.json
EXE_NAME=pomotroid.exe

cd "$(git rev-parse --show-toplevel)"
sha=$(git rev-parse HEAD)
branch=$(git rev-parse --abbrev-ref HEAD)

git fetch -q origin
if ! git branch -r --contains "$sha" | grep -q .; then
  echo "HEAD $sha is not on origin. Push first." >&2
  exit 1
fi

find_run() {
  gh run list --workflow "$WORKFLOW" --commit "$sha" --limit 1 --json databaseId --jq '.[0].databaseId // empty'
}

echo "Looking for a $WORKFLOW run for $sha..."
run_id=""
for _ in $(seq 1 12); do
  run_id=$(find_run)
  [ -n "$run_id" ] && break
  sleep 5
done
if [ -z "$run_id" ]; then
  echo "No run found; dispatching $WORKFLOW on $branch."
  gh workflow run "$WORKFLOW" --ref "$branch"
  for _ in $(seq 1 12); do
    run_id=$(find_run)
    [ -n "$run_id" ] && break
    sleep 5
  done
fi
[ -n "$run_id" ] || { echo "No run appeared for $sha." >&2; exit 1; }

echo "Waiting for run $run_id..."
if ! gh run watch "$run_id" --exit-status --interval 15; then
  echo "Build failed. Failed step logs:" >&2
  gh run view "$run_id" --log-failed >&2 || true
  exit 1
fi

win_tmp=$(powershell.exe -NoProfile -Command '$env:TEMP' | tr -d '\r')
dest="$(wslpath -u "$win_tmp")/pomotroid-deploy"
rm -rf "$dest" && mkdir -p "$dest"
gh run download "$run_id" -n "$ARTIFACT" -D "$dest"
setup=$(find "$dest" -name '*-setup.exe' | head -1)
[ -n "$setup" ] || { echo "No *-setup.exe in artifact." >&2; exit 1; }
echo "Downloaded $(basename "$setup")"

taskkill.exe /IM "$EXE_NAME" /F >/dev/null 2>&1 || true

echo "Installing. Accept the UAC prompt on the Windows desktop."
setup_win=$(wslpath -w "$setup")
powershell.exe -NoProfile -Command \
  "\$p = Start-Process -FilePath '$setup_win' -ArgumentList '/S' -Verb RunAs -Wait -PassThru; exit \$p.ExitCode" \
  || { echo "Install failed or UAC was declined." >&2; exit 1; }

installed="$(wslpath -u "$APP_DIR")/$EXE_NAME"
built="$dest/$EXE_NAME"
if [ "$(stat -c %s "$installed")" != "$(stat -c %s "$built")" ]; then
  echo "Installed $EXE_NAME does not match the built one." >&2
  exit 1
fi

powershell.exe -NoProfile -Command "Start-Process '$APP_DIR\\$EXE_NAME'"
for _ in $(seq 1 10); do
  tasklist.exe /FI "IMAGENAME eq $EXE_NAME" 2>/dev/null | grep -qi "$EXE_NAME" && break
  sleep 1
done
tasklist.exe /FI "IMAGENAME eq $EXE_NAME" 2>/dev/null | grep -qi "$EXE_NAME" \
  || { echo "$EXE_NAME did not start." >&2; exit 1; }

echo "Deployed $sha: installed and running."
