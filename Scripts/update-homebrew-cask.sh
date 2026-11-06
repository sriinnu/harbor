#!/usr/bin/env bash
#
# update-homebrew-cask.sh [X.Y.Z]   (default: MARKETING_VERSION from Config/version.env)
#
# Points the cask (sriinnu/homebrew-tap → Casks/harbor.rb) at a published
# release: sets `version`, computes `sha256` from the zip ATTACHED TO THE
# RELEASE (what users download, never a local build), and lands it through a
# signed commit and a PR on the tap. The first release copies Casks/harbor.rb
# from this repo as the template. Ported from tokmeter's update-brew-cask.sh.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=lib/signing.sh
source "$ROOT/Scripts/lib/signing.sh"
source "$ROOT/Config/version.env"

VERSION="${1:-$MARKETING_VERSION}"
[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo "usage: update-homebrew-cask.sh X.Y.Z" >&2; exit 1; }

REPO="${REPO:-sriinnu/harbor}"
TAP="${TAP:-sriinnu/homebrew-tap}"
TAG="v${VERSION}"
ZIPNAME="Harbor-${VERSION}.zip"

echo "==> Downloading ${ZIPNAME} from release ${TAG} to compute sha256"
tmp="$(mktemp -d)"
gh release download "$TAG" --repo "$REPO" --pattern "$ZIPNAME" --dir "$tmp"
SHA="$(shasum -a 256 "$tmp/$ZIPNAME" | awk '{print $1}')"
rm -rf "$tmp"
echo "    sha256: $SHA"

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
echo "==> Cloning tap ${TAP}"
gh repo clone "$TAP" "$work/tap" -- --depth 1 >/dev/null 2>&1

cask="$work/tap/Casks/harbor.rb"
if [[ ! -f "$cask" ]]; then
  echo "==> First release: adding Casks/harbor.rb from this repo's template"
  cp "$ROOT/Casks/harbor.rb" "$cask"
fi

perl -i -pe 's/(version ")[^"]+(")/${1}'"$VERSION"'${2}/' "$cask"
perl -i -pe 's/(sha256 ")[^"]+(")/${1}'"$SHA"'${2}/' "$cask"

echo "==> Cask now:"
grep -E 'version |sha256 ' "$cask" | sed 's/^/    /'

git -C "$work/tap" add Casks/harbor.rb
if git -C "$work/tap" diff --cached --quiet; then
  echo "==> Cask already at ${VERSION} with this sha256: nothing to push."
  exit 0
fi

branch="chore/harbor-${VERSION}"
# Rerunnable: an earlier run may have pushed the branch or opened the PR.
if [[ "$(gh pr view "$branch" --repo "$TAP" --json state -q .state 2>/dev/null || true)" != "OPEN" ]]; then
  if git -C "$work/tap" ls-remote --exit-code --heads origin "$branch" >/dev/null 2>&1; then
    git -C "$work/tap" fetch -q --depth 1 origin "$branch"
    git -C "$work/tap" diff --quiet --cached FETCH_HEAD -- Casks/harbor.rb \
      || { echo "ERROR: ${TAP} already has a ${branch} branch with a different cask; delete it by hand." >&2; exit 1; }
    echo "==> ${branch} is already pushed with this cask"
  else
    git -C "$work/tap" switch -q -c "$branch"
    signed "cask commit" git -C "$work/tap" commit -q -S -m "harbor ${VERSION}"
    git -C "$work/tap" push -q -u origin "$branch"
  fi
  gh pr create --repo "$TAP" --base main --head "$branch" \
    --title "harbor ${VERSION}" \
    --body "Points the cask at ${TAG}. sha256 computed from the zip attached to the release."
fi
gh pr merge "$branch" --repo "$TAP" --squash --delete-branch
echo "==> Merged: brew install --cask sriinnu/tap/harbor now serves ${VERSION}"
