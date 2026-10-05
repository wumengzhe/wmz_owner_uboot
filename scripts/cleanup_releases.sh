#!/bin/bash
# cleanup_releases.sh - 仅保留最近的 N 个 GitHub Release，删除其余（含对应 tag）。
#
# 用法:
#   ./cleanup_releases.sh [KEEP]        # KEEP 默认 3
#
# 依赖: gh CLI 已认证（GH_TOKEN / GITHUB_TOKEN 需有 contents:write）；
#       仓库默认取 $GITHUB_REPOSITORY（GitHub Actions 自动注入），
#       否则回退到 git remote origin。
#
# 设计要点:
#   - 按 createdAt 升序排，删除最旧的 (总数 - KEEP) 个，保留最新的 KEEP 个。
#   - 总数 <= KEEP 时不删除任何东西（安全）。
#   - 每次删除都带 --cleanup-tag，连 tag 一起清理，避免孤儿 tag。

set -euo pipefail

KEEP="${1:-3}"
if ! [ "$KEEP" -ge 1 ] 2>/dev/null; then
  echo "KEEP 必须是正整数（默认 3）" >&2
  exit 1
fi

REPO="${GITHUB_REPOSITORY:-}"
if [ -z "$REPO" ]; then
  REPO="$(git config --get remote.origin.url 2>/dev/null | sed -E 's#.*[:/]([^/]+/[^/]+?)(\.git)?$#\1#')"
fi
if [ -z "$REPO" ]; then
  echo "无法推断仓库（既没有 \$GITHUB_REPOSITORY，也没有 git remote origin）" >&2
  exit 1
fi

echo "仓库: $REPO"
echo "保留最近 $KEEP 个 Release，删除其余..."

# 列出全部 release，按 createdAt 升序（最旧在前），每行: <createdAt>\t<name>
mapfile -t ALL < <(
  gh release list --repo "$REPO" --limit 1000 \
    --json name,createdAt --jq '.[] | "\(.createdAt)\t\(.name)"' \
    | sort
)

TOTAL="${#ALL[@]}"
echo "共 $TOTAL 个 release。"

if [ "$TOTAL" -le "$KEEP" ]; then
  echo "现存 $TOTAL 个（<= $KEEP），无需清理。"
  exit 0
fi

DELETE_COUNT=$((TOTAL - KEEP))
echo "将删除最旧的 $DELETE_COUNT 个 release："
mapfile -t TO_DELETE < <(printf '%s\n' "${ALL[@]}" | head -n "$DELETE_COUNT")
for line in "${TO_DELETE[@]}"; do
  printf '  - %s\n' "${line#*$'\t'}"
done

for line in "${TO_DELETE[@]}"; do
  name="${line#*$'\t'}"
  echo "删除 release '$name'（含 tag）..."
  if gh release delete "$name" --repo "$REPO" --yes --cleanup-tag; then
    echo "  已删除 '$name'"
  else
    echo "::warning::删除 '$name' 失败（可能已被手动删除或无权限）"
  fi
done

echo "完成。保留最近的 $KEEP 个 release。"
