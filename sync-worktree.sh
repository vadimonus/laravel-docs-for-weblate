#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
UPSTREAM_REPO="${UPSTREAM_REPO:-https://github.com/laravel/docs.git}"
BRANCH_PATTERN='^(master|4\.[0-2]|5\.[0-8]|[6-9]\.x|[1-2][0-9]\.x)$'
TARGET_ROOT="$REPO_ROOT/en"
CLONE_DIR="$REPO_ROOT/.cache/laravel-docs"

mkdir -p "$TARGET_ROOT" "$CLONE_DIR"

if [ ! -d "$CLONE_DIR/.git" ]; then
    git clone --quiet --filter=blob:none "$UPSTREAM_REPO" "$CLONE_DIR"
else
    git -C "$CLONE_DIR" remote set-url origin "$UPSTREAM_REPO"
    git -C "$CLONE_DIR" fetch --quiet --prune --tags origin
fi

git -C "$CLONE_DIR" config advice.detachedHead false

mapfile -t BRANCHES < <(
    git -C "$CLONE_DIR" branch -r | sed 's/^[[:space:]]*origin\///' | grep -E "$BRANCH_PATTERN" | sort -u
)

for branch in "${BRANCHES[@]}"; do
    target_dir="$TARGET_ROOT/$branch"

    if [ -d "$target_dir" ]; then
        rm -rf "$target_dir"
    fi

    mkdir -p "$target_dir"

    git -C "$CLONE_DIR" archive --format=tar "origin/$branch" | tar -x -C "$target_dir" >/dev/null || continue
done

if [ -z "$(git -C "$REPO_ROOT" status --porcelain --untracked-files=all -- en)" ]; then
    echo "No changes detected in the docs trees."
    exit 0
fi

git -C "$REPO_ROOT" add --all en

COMMIT_MESSAGE="sync laravel/docs branches $(date '+%Y-%m-%d %H:%M:%S')"

GIT_COMMITTER_NAME="github-actions[bot]" \
GIT_COMMITTER_EMAIL="41898282+github-actions[bot]@users.noreply.github.com" \
git -C "$REPO_ROOT" commit \
    --author="github-actions[bot] <41898282+github-actions[bot]@users.noreply.github.com>" \
    -m "$COMMIT_MESSAGE"

echo "Committed updates for the synced docs branches."

if [ "${PUSH_CHANGES:-false}" = "true" ]; then
    target_ref="${GITHUB_REF_NAME:-main}"

    if ! git -C "$REPO_ROOT" push origin "HEAD:${target_ref}"; then
        echo "Warning: push to origin/${target_ref} failed; local commit was created successfully."
    fi
fi
