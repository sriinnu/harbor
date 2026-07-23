---
summary: "Mobile-first response and terminal runbook for removing the exposed OAuth secret from Harbor history."
read_when:
  - Rotating the leaked Harbor OAuth secret
  - Rewriting Harbor Git history before making the repository public
---

# Credential incident response and history rewrite

This runbook is for the GitHub OAuth client secret that was previously committed to Harbor. It is written so the urgent part can be done from a phone and the irreversible Git work waits for a Mac.

> [!WARNING]
> Keep the repository private until every terminal step is complete and verified. Reverting a commit or deleting a file does not remove a credential from Git history.

## Do now — phone only

1. In GitHub, go to Settings, Developer settings, OAuth Apps, then open the Harbor OAuth application.
2. Generate a replacement secret if the app still needs to operate, update any legitimate secure use, then delete the compromised secret. Official guidance: https://docs.github.com/en/apps/oauth-apps/building-oauth-apps/best-practices-for-creating-an-oauth-app
3. Revoke user tokens issued by that app if the old secret may have been used outside Harbor. Treat affected accounts as needing to sign in again.
4. Keep sriinnu/harbor private. Do not merge unrelated work, create tags, or accept pushes until the rewrite is finished.
5. Inspect and remove any credential-bearing Actions logs, artifacts, Pages deployments, releases, issue or pull-request comments, snippets, and LFS objects. Forks require their own cleanup.

## Before the rewrite — Mac

1. Merge the public-readiness PR while the repository is still private, or ensure its current-source changes are included.
2. Tell collaborators to stop pushing. Afterwards they must discard old clones and clone again.
3. Temporarily allow an administrator to force-push the repository's branches.
4. Install a current git-filter-repo.

    brew install git-filter-repo
    git filter-repo --version

5. Authenticate Git over SSH or with the GitHub CLI. Do not put a token in a shell command or remote URL.
6. Make a private encrypted backup. It retains the revoked secret, so never upload or share it.

## Rewrite all visible branches and tags

Run this in a new empty directory. The secret is entered interactively, so it never lands in shell history or this document.

    SCRUB_ROOT="$PWD/harbor-scrub-20260723"
    mkdir -p "$SCRUB_ROOT"
    git clone --mirror git@github.com:sriinnu/harbor.git "$SCRUB_ROOT/harbor-pre-scrub.git"
    git -C "$SCRUB_ROOT/harbor-pre-scrub.git" fsck --full
    git -C "$SCRUB_ROOT/harbor-pre-scrub.git" bundle create "$SCRUB_ROOT/harbor-pre-scrub.bundle" --all

    git clone --mirror "$SCRUB_ROOT/harbor-pre-scrub.git" "$SCRUB_ROOT/harbor-rewrite.git"
    read -r -s -p 'Paste the revoked old OAuth secret: ' HARBOR_OLD_SECRET; echo
    printf 'literal:%s==>***REDACTED_GITHUB_OAUTH_CLIENT_SECRET***\n' "$HARBOR_OLD_SECRET" > "$SCRUB_ROOT/replacements.txt"
    unset HARBOR_OLD_SECRET
    chmod 600 "$SCRUB_ROOT/replacements.txt"

    cd "$SCRUB_ROOT/harbor-rewrite.git"
    git filter-repo --sensitive-data-removal --replace-text "$SCRUB_ROOT/replacements.txt"
    rm -f "$SCRUB_ROOT/replacements.txt"
    git remote add origin git@github.com:sriinnu/harbor.git

Use one replacement rule for every distinct leaked value. Do not put the original secret into a script, commit message, issue, or chat message.

## Verify locally before pushing

Re-enter the old secret interactively. The following checks must report clean; do not print the secret.

    read -r -s -p 'Paste the revoked old OAuth secret: ' HARBOR_OLD_SECRET; echo
    git log --all --format=%B | grep -Fq -- "$HARBOR_OLD_SECRET" && echo FOUND_IN_COMMIT_MESSAGES || echo clean

    while read -r commit; do
      git grep -I -F --quiet "$HARBOR_OLD_SECRET" "$commit" -- && echo FOUND_IN_COMMIT_CONTENT && break
    done < <(git rev-list --all)

    unset HARBOR_OLD_SECRET
    git fsck --full
    git for-each-ref --format='%(refname)'
    grep -c '^refs/pull/.*/head$' .git/filter-repo/changed-refs || true

Also run a redacting scanner such as gitleaks against every ref.

## Force-push only ordinary branches and tags

Do not use git push --mirror because it can attempt to update GitHub-managed pull-request refs.

    git push origin --force --prune 'refs/heads/*:refs/heads/*'
    git push origin --force --prune 'refs/tags/*:refs/tags/*'

Then fresh-clone from GitHub and repeat the non-printing verification.

## GitHub cleanup and follow-up

1. Ask GitHub Support to remove sensitive-data caches and affected pull-request views. Follow: https://docs.github.com/en/authentication/keeping-your-account-and-data-secure/removing-sensitive-data-from-a-repository
2. Recreate or close affected pull requests and re-sign rewritten tags or release artifacts.
3. Require all collaborators to delete old clones and clone again.
4. Enable secret scanning and push protection.
5. Re-run CI, the repository secret scan, and the release checklist.
6. Only then consider changing repository visibility.

## What this does not solve

Rewriting history reduces exposure from GitHub refs. It cannot recall copies already cloned, cached, or seen by a third party. Secret rotation is the real containment step.
