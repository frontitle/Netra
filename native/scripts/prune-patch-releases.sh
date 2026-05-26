#!/usr/bin/env bash
# 删除 GitHub 上已过期的 0.1.x 小版本 Release，仅保留「最新」与里程碑 0.x。
# 用法: ./native/scripts/prune-patch-releases.sh v0.1.4-beta
# 需要: gh CLI 且已登录
set -euo pipefail

KEEP_TAG="${1:?Usage: $0 <tag-to-keep> e.g. v0.1.4-beta}"
REPO="${GITHUB_REPO:-frontitle/Netra}"

echo "Repository: $REPO"
echo "Keeping: $KEEP_TAG"

while IFS= read -r tag; do
  [[ -z "$tag" ]] && continue
  # 匹配 v0.1.N-beta 且不是当前保留版本
  if [[ "$tag" =~ ^v0\.1\.[0-9]+-beta$ ]] && [[ "$tag" != "$KEEP_TAG" ]]; then
    echo "Deleting release $tag ..."
    gh release delete "$tag" --repo "$REPO" --yes --cleanup-tag || true
  fi
done < <(gh release list --repo "$REPO" --limit 100 --json tagName -q '.[].tagName')

echo "Done. Remaining releases:"
gh release list --repo "$REPO" --limit 20
