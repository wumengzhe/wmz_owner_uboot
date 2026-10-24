#!/bin/bash
# cleanup_releases.sh - 清理 GitHub Release（含对应 tag），两种模式：
#
# 用法:
#   ./cleanup_releases.sh [KEEP]              # 计数模式：仅保留最近 KEEP 个（默认 3）
#   ./cleanup_releases.sh --keep-run <RUN>    # 按运行号模式：仅保留 tag 以 -<RUN> 结尾的，
#                                            # 删除本次 CI 运行之外的其余全部 release
#
# 依赖: gh CLI 已认证（GH_TOKEN / GITHUB_TOKEN 需有 contents:write）；
#       仓库默认取 $GITHUB_REPOSITORY（GitHub Actions 自动注入），
#       否则回退到 git remote origin。
#
# 设计要点:
#   - 计数模式：按 createdAt 升序排，删除最旧的 (总数 - KEEP) 个；总数 <= KEEP 时不删（安全）。
#   - keep-run 模式：tag 命名约定为 wmz-uboot-<版本>-<variant>-<multi>-<run_number>，
#     同一 run 的多个版本共享同一 run_number 后缀，因此一次发布（可能多个 tag）
#     只会整体保留或整体删除，互不影响。
#   - keep-run 模式下若没有匹配任何 release，报错退出（防止误删全仓）。
#   - 每次删除都带 --cleanup-tag，连 tag 一起清理，避免孤儿 tag。

set -euo pipefail

MODE="count"
KEEP=""
KEEP_RUN=""

if [ "${1:-}" = "--keep-run" ]; then
  MODE="keep-run"
  KEEP_RUN="${2:-}"
  if ! [[ "$KEEP_RUN" =~ ^[0-9]+$ ]]; then
    echo "keep-run 模式需要一个正整数 RUN（GitHub Actions run_number）" >&2
    echo "用法: $0 --keep-run <RUN>" >&2
    exit 1
  fi
else
  KEEP="${1:-3}"
  if ! [ "$KEEP" -ge 1 ] 2>/dev/null; then
    echo "KEEP 必须是正整数（默认 3）" >&2
    exit 1
  fi
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

# gh release list 只按 name（release 名）返回，删除时用的也是 name 字段；
# 本仓约定 release 名与 tag 同名（wmz-uboot-<版本>-<variant>-<multi>-<run>），
# 故直接用 name 匹配后缀即可。
mapfile -t ALL_TAGS < <(
  gh release list --repo "$REPO" --limit 1000 --json tagName --jq '.[].tagName'
)

TOTAL="${#ALL_TAGS[@]}"
echo "共 $TOTAL 个 release。"

if [ "$MODE" = "count" ]; then
  echo "计数模式：保留最近 $KEEP 个 Release，删除其余..."

  # 按 createdAt 升序（最旧在前），每行: <createdAt>\t<tagName>
  mapfile -t ALL < <(
    gh release list --repo "$REPO" --limit 1000 \
      --json tagName,createdAt --jq '.[] | "\(.createdAt)\t\(.tagName)"' \
      | sort
  )

  if [ "$TOTAL" -le "$KEEP" ]; then
    echo "现存 $TOTAL 个（<= $KEEP），无需清理。"
    exit 0
  fi

  DELETE_COUNT=$((TOTAL - KEEP))
  echo "将删除最旧的 $DELETE_COUNT 个 release："
  mapfile -t TO_DELETE < <(printf '%s\n' "${ALL[@]}" | head -n "$DELETE_COUNT")
else
  echo "keep-run 模式：仅保留 tag 以 '-$KEEP_RUN' 结尾的 release，删除其余..."

  TO_DELETE=()
  KEPT=0
  for t in "${ALL_TAGS[@]}"; do
    if [[ "$t" == *-"$KEEP_RUN" ]]; then
      KEPT=$((KEPT + 1))
    else
      TO_DELETE+=("$t")
    fi
  done

  if [ "$KEPT" -eq 0 ]; then
    echo "::error::没有找到 tag 以 '-$KEEP_RUN' 结尾的 release——中止，避免误删全仓。" >&2
    exit 1
  fi

  echo "本次运行（run #$KEEP_RUN）保留 $KEPT 个，将删除其余 $((TOTAL - KEPT)) 个 release："
fi

for t in "${TO_DELETE[@]}"; do
  [ -z "$t" ] && continue
  printf '  - %s\n' "$t"
done

for t in "${TO_DELETE[@]}"; do
  [ -z "$t" ] && continue
  echo "删除 release '$t'（含 tag）..."
  if gh release delete "$t" --repo "$REPO" --yes --cleanup-tag; then
    echo "  已删除 '$t'"
  else
    echo "::warning::删除 '$t' 失败（可能已被手动删除或无权限）"
  fi
done

if [ "$MODE" = "count" ]; then
  echo "完成。保留最近的 $KEEP 个 release。"
else
  echo "完成。仅保留本次运行（run #$KEEP_RUN）的 $KEPT 个 release。"
fi
