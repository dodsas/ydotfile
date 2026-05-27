---
description: ydotfile 레포에서 지정한 자산(skill / command / hook)을 삭제하고 push
argument-hint: "<name1> [name2] ... — 레포 안의 skill 디렉토리명 또는 command/hook 파일명"
---

`$ARGUMENTS` 에 공백 구분된 이름들이 들어온다. 각각을 **ydotfile 레포 캐시 안** 에서 찾아 `git rm` 후 커밋·push.

로컬 `~/.claude/` 나 프로젝트 `.claude/` 의 원본 파일은 **건드리지 않는다** — 오직 원격 dotfile 레포에서만 제거.

## 상수

- 원격: `https://github.com/dodsas/ydotfile.git`
- 캐시 작업 디렉토리: `${YDOTFILE_DIR:-$HOME/.local/share/ydotfile}` (push 와 공유)
- 레포 구조: `skills/<name>/`, `commands/<name>.md`, `hooks/<name>.sh`

## 절차

### 0. 인자 검증

`$ARGUMENTS` 가 비어있으면 사용 예시 보여주고 종료:
```
사용법: /ydotfile-rm <name1> [name2] ...
예시:   /ydotfile-rm smoke.md rotate-secret.md korean-ops-doc
```

### 1. 캐시 레포 최신화

```bash
YDOTFILE_DIR="${YDOTFILE_DIR:-$HOME/.local/share/ydotfile}"
REMOTE="https://github.com/dodsas/ydotfile.git"

if [ ! -d "$YDOTFILE_DIR/.git" ]; then
  mkdir -p "$(dirname "$YDOTFILE_DIR")"
  git clone "$REMOTE" "$YDOTFILE_DIR"
else
  git -C "$YDOTFILE_DIR" fetch origin --quiet
  git -C "$YDOTFILE_DIR" reset --hard origin/main --quiet
fi
```

### 2. 각 인자 → 레포 안 자산 매칭

검색 순서 (위에서 아래로):

| 인자 | 시도하는 레포 경로 | 분류 |
|---|---|---|
| `<arg>` (확장자 없음) | `$YDOTFILE_DIR/skills/<arg>/` | skill |
| 〃 | `$YDOTFILE_DIR/commands/<arg>.md` | command |
| 〃 | `$YDOTFILE_DIR/hooks/<arg>.sh` | hook |
| `<arg>.md` | `$YDOTFILE_DIR/commands/<arg>.md` | command |
| `<arg>.sh` | `$YDOTFILE_DIR/hooks/<arg>.sh` | hook |

매칭 결과 표 출력:
```
인자             → 타입       삭제 대상
ydotfile-push    → command   commands/ydotfile-push.md
korean-ops-doc   → skill     skills/korean-ops-doc/ (디렉토리 + 안의 파일 N개)
(unknown-name)   → ✗ 레포에 없음 (스킵)
```

매칭 0건이면 "삭제할 항목 없음" 으로 종료.

### 3. 명시적 확인 (필수, 가드 강화)

push 보다 위험도 높음. 다음을 명확히 보여준 뒤 **사용자에게 확인** 받기:

- 삭제될 파일 목록 (skill 이면 디렉토리 안 파일까지 펼쳐서)
- 다음 항목 안내:
  - 로컬 `~/.claude/` 와 `<proj>/.claude/` 의 같은 이름 파일은 **건드리지 않음**
  - 이미 이 dotfile 을 다른 PC 에 install.sh 로 받아간 경우, 그쪽은 자동 동기화되지 않음 — 그 PC 에서 install.sh 재실행 필요 (또는 수동 삭제)
  - 커밋 직후 push 까지 자동 진행 (force push 아님 — 일반 commit + push)

확인 받기 전엔 `git rm` 도 하지 말 것.

### 4. 삭제 실행

```bash
cd "$YDOTFILE_DIR"
for path in <matched-paths>; do
  git rm -r "$path"
done
```

- skill 은 `git rm -r` (디렉토리)
- command/hook 은 그냥 `git rm`

### 5. 커밋 메시지

`git status --porcelain` 결과로 카테고리별 카운트:

- 단일: `remove(commands): smoke` / `remove(skills): korean-ops-doc`
- 다중: 첫 줄 `cleanup: 3개 자산 제거` + 본문 카테고리별
  ```
  cleanup: 3개 자산 제거

  skills:   korean-ops-doc
  commands: smoke, rotate-secret
  ```

영문 prefix + 한국어 본문. Co-Authored-By 추가 안 함.

### 6. push

```bash
git -C "$YDOTFILE_DIR" commit -m "<message>"
GIT_TERMINAL_PROMPT=0 git -C "$YDOTFILE_DIR" push origin main
```

- `--force` 절대 금지 — 일반 push 로 충분 (캐시가 최신 상태이므로 fast-forward 됨)
- main 외 브랜치면 중단

### 7. 결과 출력

```
✓ pushed: <short-sha>
  제거:
    - commands/smoke.md
    - skills/korean-ops-doc/SKILL.md
  https://github.com/dodsas/ydotfile/commit/<sha>

⚠ 다른 PC 에서 받아간 사본은 자동 갱신되지 않음.
  → 그 PC 에서 install.sh 재실행 또는 수동 삭제.
```

## 안 하는 것

- 로컬 `~/.claude/` 또는 프로젝트 `.claude/` 의 원본 파일 삭제 (오직 dotfile 레포에서만)
- force push, amend, rebase
- main 외 브랜치 작업
- 일괄 삭제 (`*`, `--all`) — 사고 위험. 인자는 반드시 명시
- 다른 PC 의 사본 자동 동기화 (install.sh 가 단방향 복사라 책임 영역 밖)
