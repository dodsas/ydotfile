#!/usr/bin/env bash
# ydotfile installer — Claude Code 자산을 로컬에 배치
#
# 사용법:
#   curl -fsSL https://raw.githubusercontent.com/dodsas/ydotfile/main/install.sh | bash
#   curl -fsSL https://raw.githubusercontent.com/dodsas/ydotfile/main/install.sh | bash -s -- local
#   curl -fsSL https://raw.githubusercontent.com/dodsas/ydotfile/main/install.sh | bash -s -- global
#
# 인자:
#   (없음) | local : 현재 디렉토리의 .claude/ 에 설치 (프로젝트 전용)
#   global         : ~/.claude/ 에 설치 (사용자 전역, 어디서나 트리거)

set -euo pipefail

SCOPE="${1:-local}"
REPO_URL="https://github.com/dodsas/ydotfile"
TARBALL="${REPO_URL}/archive/refs/heads/main.tar.gz"

case "$SCOPE" in
  local)
    DEST="$(pwd)/.claude"
    SCOPE_LABEL="프로젝트 (local) — $DEST"
    ;;
  global)
    DEST="$HOME/.claude"
    SCOPE_LABEL="사용자 전역 (global) — $DEST"
    ;;
  -h|--help|help)
    cat <<EOF
Usage: install.sh [local|global]

  local   : <cwd>/.claude/ 에 설치 (기본). 현재 프로젝트에서만 트리거.
  global  : ~/.claude/ 에 설치. 모든 프로젝트에서 트리거.

설치 대상:
  skills/<name>/     — Claude 자동 호출 스킬
  commands/<name>.md — 슬래시 커맨드
  hooks/<name>.sh    — 훅 스크립트

기존 동일 이름 파일은 .bak.<timestamp> 로 백업한 뒤 덮어씁니다.
EOF
    exit 0
    ;;
  *)
    echo "✗ 알 수 없는 인자: $SCOPE" >&2
    echo "  사용법: install.sh [local|global]" >&2
    exit 1
    ;;
esac

echo "▸ scope: $SCOPE_LABEL"

# 임시 디렉토리에 tarball 풀기
TMP="$(mktemp -d)"
trap "rm -rf '$TMP'" EXIT

echo "▸ tarball 다운로드..."
if ! curl -fsSL "$TARBALL" | tar -xz -C "$TMP" --strip-components=1; then
  echo "✗ 다운로드/추출 실패. 네트워크 또는 레포 접근 권한 확인." >&2
  exit 1
fi

mkdir -p "$DEST"

# 카테고리별로 복사. skills/ 는 디렉토리 단위, commands·hooks 는 파일 단위.
TIMESTAMP="$(date +%Y%m%d-%H%M%S)"
INSTALLED_SKILLS=0
INSTALLED_COMMANDS=0
INSTALLED_HOOKS=0
BACKED_UP=0

backup_if_exists() {
  local target="$1"
  if [ -e "$target" ]; then
    mv "$target" "${target}.bak.${TIMESTAMP}"
    BACKED_UP=$((BACKED_UP + 1))
  fi
}

# skills/ — 디렉토리째
if [ -d "$TMP/skills" ]; then
  mkdir -p "$DEST/skills"
  for src in "$TMP/skills"/*/; do
    [ -d "$src" ] || continue
    name="$(basename "$src")"
    backup_if_exists "$DEST/skills/$name"
    cp -R "$src" "$DEST/skills/$name"
    INSTALLED_SKILLS=$((INSTALLED_SKILLS + 1))
  done
fi

# commands/ — 파일
if [ -d "$TMP/commands" ]; then
  mkdir -p "$DEST/commands"
  for src in "$TMP/commands"/*.md; do
    [ -f "$src" ] || continue
    name="$(basename "$src")"
    backup_if_exists "$DEST/commands/$name"
    cp "$src" "$DEST/commands/$name"
    INSTALLED_COMMANDS=$((INSTALLED_COMMANDS + 1))
  done
fi

# hooks/ — 파일 (실행권한 보존)
if [ -d "$TMP/hooks" ]; then
  mkdir -p "$DEST/hooks"
  for src in "$TMP/hooks"/*.sh; do
    [ -f "$src" ] || continue
    name="$(basename "$src")"
    backup_if_exists "$DEST/hooks/$name"
    cp -p "$src" "$DEST/hooks/$name"
    INSTALLED_HOOKS=$((INSTALLED_HOOKS + 1))
  done
fi

echo
echo "✓ 설치 완료"
echo "  skills:   $INSTALLED_SKILLS"
echo "  commands: $INSTALLED_COMMANDS"
echo "  hooks:    $INSTALLED_HOOKS"
[ "$BACKED_UP" -gt 0 ] && echo "  백업:     $BACKED_UP 개 (.bak.${TIMESTAMP})"
echo
echo "▸ Claude Code 세션에서 활성화:"
echo "    /reload-skills"
