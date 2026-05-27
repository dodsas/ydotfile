---
description: 지정한 Claude 자산(skill / command / hook)을 ydotfile 레포로 push
argument-hint: "<name1> [name2] ... — skill 디렉토리명 또는 command/hook 파일명"
---

`$ARGUMENTS` 에 공백 구분된 이름들이 들어온다. 각각을 프로젝트 `.claude/` 와 사용자 `~/.claude/` 양쪽에서 찾아 매칭되는 자산을 ydotfile 레포에 복사·커밋·push 한다.

## 상수

- 원격: `https://github.com/dodsas/ydotfile.git` (HTTPS — `gh` CLI 가 git credential 관리)
- 캐시 작업 디렉토리: `${YDOTFILE_DIR:-$HOME/.local/share/ydotfile}` (env override 가능)
- 레포 안 디렉토리 구조 (평면):
  ```
  ydotfile/
  ├── skills/<name>/SKILL.md   (+ skill 안의 부속 파일들 모두)
  ├── commands/<name>.md
  └── hooks/<name>.sh
  ```

## 절차

### 0. 인자 검증

`$ARGUMENTS` 가 비어있으면 사용 예시 보여주고 종료:
```
사용법: /ydotfile-push <name1> [name2] ...
예시:   /ydotfile-push smoke.md claude-cli-bridge
```

### 1. 캐시 레포 준비

```bash
YDOTFILE_DIR="${YDOTFILE_DIR:-$HOME/.local/share/ydotfile}"
REMOTE="https://github.com/dodsas/ydotfile.git"

if [ -d "$YDOTFILE_DIR/.git" ]; then
  ORIGIN=$(git -C "$YDOTFILE_DIR" remote get-url origin 2>/dev/null || echo "")
  if [ "$ORIGIN" != "$REMOTE" ]; then
    echo "⚠ 기존 캐시($YDOTFILE_DIR)의 origin 이 $ORIGIN 입니다. 충돌 가능."
    # 사용자에게 다른 경로 쓸지 물어보기
  fi
  git -C "$YDOTFILE_DIR" fetch origin --quiet
  git -C "$YDOTFILE_DIR" reset --hard origin/main --quiet
else
  mkdir -p "$(dirname "$YDOTFILE_DIR")"
  git clone "$REMOTE" "$YDOTFILE_DIR"
fi
```

clone 실패 시 (`gh` 미인증 / 권한 없음) stderr 그대로 사용자에게 보여주고 종료. **이때 `gh auth status` 로 인증 상태 진단 권장**. 미인증이면 `gh auth login` 안내.

### 2. 각 인자 해석 — 자산 타입과 소스 경로 결정

검색 순서 (위에서 아래로, 양쪽 스코프):

| 인자 | 시도하는 경로 | 분류 |
|---|---|---|
| `<arg>` (확장자 없음) | `<proj>/.claude/skills/<arg>/SKILL.md` | skill |
| 〃 | `~/.claude/skills/<arg>/SKILL.md` | skill |
| 〃 | `<proj>/.claude/commands/<arg>.md` | command |
| 〃 | `~/.claude/commands/<arg>.md` | command |
| 〃 | `~/.claude/hooks/<arg>.sh` | hook |
| `<arg>.md` (확장자 .md) | `<proj>/.claude/commands/<arg>.md` | command |
| 〃 | `~/.claude/commands/<arg>.md` | command |
| `<arg>.sh` | `~/.claude/hooks/<arg>.sh` | hook |

`<proj>` = 현재 working directory 에서 위로 거슬러 올라가며 `.claude/` 가 있는 첫 디렉토리. 없으면 프로젝트 스코프 건너뜀.

**같은 인자가 양쪽 스코프(프로젝트 + 글로벌)에 동시에 매칭되면** `AskUserQuestion` 으로 "어느 쪽을 올릴까요?" 한 번 물어보기. 둘 다 매칭이 0건이면 그 인자만 건너뛰고 경고 한 줄 출력.

매칭 결과를 표로 한 번 보여준 뒤 다음 단계로:
```
인자             → 타입       소스
claude-cli-bridge → skill     <proj>/.claude/skills/claude-cli-bridge/
smoke.md          → command   <proj>/.claude/commands/smoke.md
(unknown-name)    → ✗ 매칭 없음 (스킵)
```

### 3. 복사

- **skill**: `cp -R <src-skill-dir>/. <YDOTFILE_DIR>/skills/<name>/` — SKILL.md 외 부속 파일(스크립트·예제 등)까지 모두 따라감.
- **command**: `cp <src> <YDOTFILE_DIR>/commands/<name>.md` (파일명 그대로).
- **hook**: `cp <src> <YDOTFILE_DIR>/hooks/<name>.sh` (실행권한 보존: `cp -p`).

복사 전 캐시 안 대상 경로의 `mkdir -p` 보장.

### 4. 변경 요약 + 명시적 확인

```bash
git -C "$YDOTFILE_DIR" status --short
git -C "$YDOTFILE_DIR" diff --stat
```

결과를 사용자에게 보여주고, 변경 없음이면 "변경 없음 — 종료" 로 마무리. 변경 있으면 **사용자에게 push 진행 여부 명시 확인**.

### 5. 커밋 메시지 자동 생성

`git -C "$YDOTFILE_DIR" status --porcelain` 결과를 보고 분류:
- 모두 신규(`??` 또는 `A`)이면 prefix `add`
- 모두 수정이면 `update`
- 혼합이면 `sync`
- 자산 카테고리(skills/commands/hooks)별 카운트

메시지 패턴:
- 단일 자산: `add(skills): claude-cli-bridge` / `update(commands): smoke`
- 다중: 첫 줄 `sync: 3개 자산 업로드` + 본문에 카테고리별 목록
  ```
  sync: 3개 자산 업로드

  skills:   claude-cli-bridge
  commands: smoke, deploy-status
  ```

본 톤: 영문 prefix + 한국어 본문. 작성자 코-크레딧 라인은 **추가하지 않음** (사용자 dotfile 레포라 노이즈).

### 6. 커밋 + push

```bash
git -C "$YDOTFILE_DIR" add -A
git -C "$YDOTFILE_DIR" commit -m "<message>"
git -C "$YDOTFILE_DIR" push origin main
```

- `--force` 류 절대 사용 금지
- 현재 브랜치가 `main` 이 아니면 중단하고 사용자 확인 요구
- push 실패(non-fast-forward 등) 시 그대로 보고 + `git pull --rebase` 후 재시도 권장만 (자동 rebase 안 함)

### 7. 결과 출력

```
✓ pushed: <short-sha>
  파일:
    + skills/claude-cli-bridge/SKILL.md
    M commands/smoke.md
  https://github.com/dodsas/ydotfile/tree/main
```

## 안 하는 것

- pull / sync-back (단방향)
- 비밀값 마스킹·필터링 (사용자 책임)
- main 외 브랜치 / PR
- force push, amend, rebase 자동 수행
- 커밋에 Co-Authored-By 추가
