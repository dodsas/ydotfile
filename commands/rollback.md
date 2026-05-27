---
description: git revert 로 직전 배포 롤백 (webhook 으로 자동 재배포)
argument-hint: "[commit-sha] (기본 HEAD)"
---

배포 모델: `main` 브랜치 push → Jenkins webhook → 자동 재배포. 따라서 롤백 = **revert commit 을 새로 만들어 push**.

## 단계

1. `$ARGUMENTS` 가 비어있으면 사용자에게 어느 커밋을 되돌릴지 확인 (`git log --oneline -10` 결과 보여주고 선택). 명시되어 있으면 그대로 사용.
2. 작업트리 더러우면 stash 또는 중단 — 사용자에게 결정 위임.
3. revert 실행 (병합 커밋이면 `-m 1` 필요):
   ```bash
   git revert <SHA>
   ```
   메시지 형식: `revert: <원본 commit message 요약> (#<SHA>)`. 본 레포 commit 톤(fix/chore/feat 영문 + 한국어 본문)에 맞춰서.
4. push 전 확인 받기 ("이 커밋을 main 에 push 하면 자동 배포됩니다. 진행?"):
   ```bash
   git push origin main
   ```
5. Jenkins 빌드 상태 모니터링 안내. webhook 도달 안 보일 때를 위한 fallback: `pollSCM 'H/2 * * * *'` 가 2분 내 픽업.
6. 배포 완료되면 `/smoke` 로 동작 확인 권고.

## 안 해야 할 것

- `git reset --hard` 또는 force-push (main 보호 + 이력 손실)
- `git revert --no-commit` 으로 stage 만 만들고 끝내기 (자동배포 트리거 안 됨)
- 이미지 태그 직접 갈아끼우기 (`Jenkinsfile` 에 빌드별 태그 없음 — git revert 가 원천)
