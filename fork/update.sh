#!/usr/bin/env bash
# Pull upstream (lvalen91/carlink), keep this fork's commits on top, and build the signed
# Play bundle. Run in Git Bash on the PC from the repo root:
#
#   bash fork/update.sh            # merge upstream/main, then build
#   bash fork/update.sh --no-pull  # build what's checked out
#
# Output: $KDIR/carlink-play-v<versionCode>.aab, ready for Play Console -> Internal testing.
# After merging a NEW upstream release, reset forkRevision to 1 in app/build.gradle.kts;
# bump it for fork-only changes (Play rejects a versionCode it has already seen).
set -euo pipefail

KDIR=${CARLINK_SIGNING_DIR:-/c/Users/justi/Documents/carlink-signing}
BUILD_ROOT=${CARLINK_BUILD_ROOT:-/c/Users/justi/.cache/gradle-builds/carlink-native}
export JAVA_HOME=${JAVA_HOME:-"/c/Program Files/Android/Android Studio/jbr"}

cd "$(git rev-parse --show-toplevel)"

if [[ "${1:-}" != "--no-pull" ]]; then
  if [[ -n "$(git status --porcelain --untracked-files=no)" ]]; then
    echo "working tree has uncommitted changes; commit or stash first" >&2
    exit 1
  fi
  git remote get-url upstream >/dev/null 2>&1 ||
    git remote add upstream https://github.com/lvalen91/carlink.git
  git fetch -q upstream
  before=$(git rev-parse HEAD)
  git merge --no-edit upstream/main
  if [[ "$before" != "$(git rev-parse HEAD)" ]]; then
    echo "merged upstream: $(git log -1 --format=%s upstream/main)"
    echo "remember: reset forkRevision if upstream bumped appVersionCode"
  fi
fi

PW=$(sed -n 's/^store password: //p' "$KDIR/carlink-upload-passwords.txt")
[[ -n "$PW" ]] || { echo "no 'store password:' line in $KDIR/carlink-upload-passwords.txt" >&2; exit 1; }
export CARLINK_KEYSTORE_FILE="$(cygpath -m "$KDIR/carlink-upload.jks")"
export CARLINK_KEYSTORE_PASSWORD="$PW" CARLINK_KEY_ALIAS=carlink-upload CARLINK_KEY_PASSWORD="$PW"

./gradlew --no-daemon -q testSideloadDebugUnitTest :app:bundlePlayRelease

AAB="$BUILD_ROOT/app/outputs/bundle/playRelease/app-play-release.aab"
CODE=$(sed -n 's/.*val appVersionCode = \([0-9]*\).*/\1/p' app/build.gradle.kts)
REV=$(sed -n 's/^val forkRevision = \([0-9]*\).*/\1/p' app/build.gradle.kts)
OUT="$KDIR/carlink-play-v$((CODE * 100 + REV)).aab"
cp "$AAB" "$OUT"
echo "built $OUT ($(wc -c <"$OUT") bytes), version $((CODE / 100)).$(printf %02d $((CODE % 100)))-j$REV"
echo "upload it: Play Console -> Carlink -> Test and release -> Internal testing -> Create new release"
