---
name: ydotfile-sync
description: 사용자가 자기 Claude 자산(스킬·커맨드·훅)을 dotfile/닷파일 레포(특히 ydotfile)로 업로드·동기화·백업하거나, 반대로 레포에서 자산을 제거·정리하려 할 때 사용. "이거 dotfile/닷파일에 올려줘", "ydotfile에 push", "백업해줘", "닷파일에서 빼줘", "dotfile에서 삭제해줘", "ydotfile 정리" 같은 자연어 요청을 받았을 때 슬래시 커맨드 /ydotfile-push 또는 /ydotfile-rm 로 안내한다. "dotfile" 과 "닷파일" 은 같은 의미로 취급.
---

# ydotfile-sync (redirect)

사용자가 자기 Claude 자산을 GitHub `dodsas/ydotfile` 레포로 **올리거나 (push)** **내리려는 (rm)** 상황에서 트리거된다. 직접 git 작업을 하지 말고, 의도에 맞는 슬래시 커맨드로 안내·실행하도록 redirect 한다.

## 의도 분류 (가장 먼저)

발화의 동사로 push / rm 을 판단한다.

| 동사·표현 | 의도 | redirect |
|---|---|---|
| "올려", "push", "업로드", "백업", "동기화", "공유" | upload | `/ydotfile-push` |
| "빼", "지워", "삭제", "제거", "내려", "정리" | remove | `/ydotfile-rm` |

모호하면 (예: "ydotfile 손봐줘") 사용자에게 어느 쪽인지 한 번 물어본다.

## 절차

1. **의도 분류** — 위 표 기준.
2. **이름 추출** — 발화에서 자산 이름을 뽑는다 (예: "smoke 커맨드 올려줘" → `smoke`).
3. **이름이 명확하면** 한 줄 안내:
   ```
   /ydotfile-push <name>    또는    /ydotfile-rm <name>
   ```
4. **이름이 모호하면** ("전부", "최근에 만든 것들", "쓸모없어진 것들") 후보 목록을 의도별 위치에서 모아 보여주고 사용자가 고르게 한다:
   - **upload 후보** (로컬 자산):
     - `<project-root>/.claude/skills/*/SKILL.md`
     - `<project-root>/.claude/commands/*.md`
     - `~/.claude/skills/*/SKILL.md`, `~/.claude/commands/*.md`, `~/.claude/hooks/*.sh`
   - **remove 후보** (레포 캐시 안):
     - `${YDOTFILE_DIR:-~/.local/share/ydotfile}/skills/*/`
     - 〃`/commands/*.md`
     - 〃`/hooks/*.sh`
5. 사용자가 후보를 고르면 그 이름들로 해당 슬래시 호출.

## 안 하는 것

- 직접 `git clone / commit / push / rm` — 모두 `/ydotfile-push` 와 `/ydotfile-rm` 이 가드·명시적 확인까지 갖춰 처리한다.
- 양방향 sync, 새 PC 셋업 (`install.sh` 부트스트랩) — 별도 작업.
- 사용자가 명시하지 않은 파일까지 묶음으로 처리 (특히 rm 은 위험).
- upload 와 remove 를 한 번에 섞어 실행 — 의도별로 한 슬래시씩.

## 참고

- 슬래시 커맨드 본체:
  - `~/.claude/commands/ydotfile-push.md`
  - `~/.claude/commands/ydotfile-rm.md`
- 캐시 작업 디렉토리: `~/.local/share/ydotfile/` (env `YDOTFILE_DIR` 로 override, push/rm 가 공유)
- 원격: `https://github.com/dodsas/ydotfile.git` (HTTPS, macOS keychain 또는 `gh` CLI 자격 관리)
