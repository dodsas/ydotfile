# ydotfile

Claude Code (CLI) 의 슬래시 커맨드·스킬·훅을 여러 PC·여러 프로젝트에서 공유하기 위한 dotfile 레포.

---

## 빠른 적용 — 한 줄 설치

### 사용자 전역 (`~/.claude/`) — 어디서나 트리거

```bash
curl -fsSL https://raw.githubusercontent.com/dodsas/ydotfile/main/install.sh | bash -s -- global
```

### 현재 프로젝트만 (`<cwd>/.claude/`)

```bash
# 인자 생략 시 기본 local
curl -fsSL https://raw.githubusercontent.com/dodsas/ydotfile/main/install.sh | bash

# 또는 명시적으로
curl -fsSL https://raw.githubusercontent.com/dodsas/ydotfile/main/install.sh | bash -s -- local
```

### 설치 후 Claude Code 세션에서

```
/reload-skills
```

세션 재시작 없이 새 스킬·커맨드가 즉시 인식됨.

---

## 디렉토리 구조

```
ydotfile/
├── README.md
├── install.sh
├── skills/<name>/SKILL.md   — Claude 자동 호출 스킬 (디렉토리째)
├── commands/<name>.md       — 슬래시 커맨드
└── hooks/<name>.sh          — 훅 스크립트 (선택)
```

`install.sh` 가 위 카테고리를 그대로 `$DEST/{skills,commands,hooks}/` 로 복사한다.

---

## 자산 목록

### Skills (자연어 트리거)

| 이름 | 설명 |
|---|---|
| `claude-cli-bridge` | 로컬 Claude CLI 를 subprocess 로 호출하는 표준 래퍼 패턴 (timeout, JSON, is_error 처리) |
| `fastapi-jwt-2stage` | FastAPI 의 "API_KEY → JWT → Bearer" 2단 인증 보일러플레이트 |
| `rootless-podman-deploy` | rootless Podman 단일 컨테이너 배포 함정 정리 (`keep-id`, linger, SELinux) |
| `jenkins-push-deploy` | git push → Jenkins → SSH → podman-compose 5-stage CD 템플릿 |
| `korean-ops-doc` | 한국어 운영문서 작성 스타일 가이드 (표 + "왜/주의" 블록 + 트러블슈팅) |
| `ydotfile-sync` | "dotfile에 올려/내려/삭제" 자연어 요청을 `/ydotfile-push` 또는 `/ydotfile-rm` 으로 redirect |

### Commands (슬래시)

| 슬래시 | 설명 |
|---|---|
| `/ydotfile-push <name>...` | 지정한 자산을 이 레포로 push (양쪽 스코프에서 자동 검색) |
| `/ydotfile-rm <name>...` | 이 레포에서 지정한 자산 제거 후 push |
| `/rollback [sha]` | `git revert` + push 로 직전 배포 롤백 (webhook 자동배포 가정) |

---

## 활용 흐름

### A. 새 PC 셋업 (1분)

```bash
# 1. 전역 설치
curl -fsSL https://raw.githubusercontent.com/dodsas/ydotfile/main/install.sh | bash -s -- global

# 2. (선택) gh CLI 로 push 자격 한 번에
brew install gh && gh auth login

# 3. Claude Code 세션에서
/reload-skills
```

이후 `/ydotfile-push`, `/ydotfile-rm` 가 즉시 사용 가능. 자연어로 "dotfile에 올려" 라고 해도 `ydotfile-sync` 가 트리거.

### B. 새 프로젝트에 한정 적용

```bash
cd <project>
curl -fsSL https://raw.githubusercontent.com/dodsas/ydotfile/main/install.sh | bash -s -- local
```

이 프로젝트의 `.claude/` 에만 들어가 해당 디렉토리 안에서만 트리거.

### C. 자산 추가·갱신·삭제

레포 owner 가 자기 PC 에서:

```
/ydotfile-push <name1> <name2> ...    # 추가/갱신
/ydotfile-rm   <name1> <name2> ...    # 제거
```

다른 PC 사용자는 변경 반영을 위해 install.sh 를 다시 실행 (덮어쓰기, 기존 파일은 `.bak.<ts>` 로 자동 백업).

---

## 안전장치

- **백업**: 같은 이름 파일이 이미 있으면 `.bak.<YYYYMMDD-HHMMSS>` 로 보존 후 덮어씀
- **단방향**: install.sh 는 받기만 함 — 로컬 변경이 자동으로 dotfile 레포에 올라가지 않음. 그건 `/ydotfile-push` 의 역할
- **삭제 비동기화**: dotfile 레포에서 자산을 제거해도 install.sh 가 받는 측 파일을 지우지 않음. 필요하면 수동 삭제

---

## 라이선스 / 비고

내부 사용. 외부 배포 전 정책 확인 필요.
