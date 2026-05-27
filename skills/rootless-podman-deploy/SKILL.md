---
name: rootless-podman-deploy
description: rootless Podman 으로 단일 컨테이너 서비스를 배포할 때 사용. userns_mode keep-id, 호스트 디렉토리 마운트 권한, linger, SELinux Z 라벨, 부팅 시 자동기동 등 자주 막히는 함정 정리. compose 파일 / deploy 스크립트 템플릿 포함.
---

# Rootless Podman 배포 (단일 컨테이너)

이 레포 `compose.yml` + `deploy/deploy.sh` + `Dockerfile` 의 패턴.

## 결정 트리: 왜 rootless 인가

| 모드 | 장점 | 단점 |
|---|---|---|
| **rootful** | 권한 단순, systemd 통합 쉬움 | sudo 필요, 보안 표면 큼 |
| **rootless** (권장) | sudo 없음, 사용자 격리 | uid 매핑·linger·firewalld 등 함정 다수 |

이 스킬은 rootless 전제.

## 핵심 함정 5가지

### 1. `userns_mode: "keep-id"` — 호스트 디렉토리 마운트 권한

- 컨테이너 내부 uid (예: 1000=app) 가 호스트의 podman 실행 사용자 uid 로 매핑됨
- 안 그러면 호스트 소유 디렉토리 (mode 700) 마운트 시 `Permission denied`

```yaml
services:
  app:
    userns_mode: "keep-id"
    volumes:
      - ${SECRETS_DIR:-./secrets}:/home/app/.secrets
```

### 2. SELinux `:Z` 라벨 — 호스트 디렉토리에는 함부로 붙이지 말 것

- `:Z` 는 호스트 디렉토리의 SELinux 컨텍스트를 **컨테이너 전용으로 다시 라벨링**. 호스트 도구가 그 디렉토리 못 쓰게 될 수 있음
- 명명 볼륨(`ysclaude-data:/app/data:Z`) 에는 OK, 호스트 디렉토리(`~/.claude`) 에는 비권장
- 이 레포는 의도적으로 `:Z` 를 뺐다 — 주석으로 명시할 것

### 3. `userns_mode` + pod 동시 사용 불가

- podman-compose 가 기본적으로 모든 서비스를 하나의 pod 에 넣는데, pod 와 userns_mode 동시 설정은 `--userns and --pod cannot be set together` 에러
- 단일 컨테이너면 pod 비활성화:
  ```yaml
  x-podman:
    in_pod: false
  ```

### 4. linger — 로그아웃해도 컨테이너 살아남기

- rootless 컨테이너는 user systemd 인스턴스 하에서 돈다. 사용자가 로그아웃하면 user@UID.service 가 죽고 컨테이너도 같이 죽음
- 해결:
  ```bash
  sudo loginctl enable-linger <user>
  ```
- 진단 도구: 이 레포 `deploy/check-host.sh` 가 12 섹션으로 모든 함정 체크 (linger / KillUserProcesses / systemd unit / 세션 출처 등). 다른 프로젝트에도 그대로 이식 가능

### 5. 호스트 OS 재부팅 — linger 만으로는 부족

- `restart: always` 는 Podman 서비스 재시작에만 적용. 호스트 reboot 후 자동 기동 안 됨
- 두 가지 방법:
  - **(a) user-level systemd unit** 로 부팅 시 `podman-compose up -d` 실행 (간단)
  - **(b) `podman generate systemd`** 로 컨테이너 단위 unit 생성 (정통)
- (a) 예시:
  ```ini
  [Unit]
  Description=app (podman-compose)
  After=network-online.target
  Wants=network-online.target

  [Service]
  Type=oneshot
  RemainAfterExit=yes
  WorkingDirectory=/home/<user>/work/<app>
  ExecStart=/usr/bin/podman-compose up -d
  ExecStop=/usr/bin/podman-compose down

  [Install]
  WantedBy=default.target
  ```
  `~/.config/systemd/user/<app>-compose.service` 위치에 두고 `systemctl --user enable --now`. **linger 가 켜져 있어야** 부팅 시 자동 시작됨

## 배포 스크립트 골격 (`deploy.sh`)

체크 → 비밀파일 보존 → build → down → up → 헬스체크 대기 → 이미지 정리. 이 레포 `deploy/deploy.sh` 참조.

핵심 패턴:

```bash
# 비밀 디렉토리 자동 감지 (env override → 사용자 홈 → placeholder)
if [ -n "${SECRETS_HOST_DIR:-}" ]; then
  : # 그대로 사용
elif [ -d "$HOME/.app-secrets" ] && [ -n "$(ls -A "$HOME/.app-secrets")" ]; then
  export SECRETS_HOST_DIR="$HOME/.app-secrets"
else
  mkdir -p "$APP_DIR/secrets" && export SECRETS_HOST_DIR="$APP_DIR/secrets"
fi

# .env 는 호스트에서 보존, 첫 배포 때만 example 복사
[ -f "$APP_DIR/.env" ] || install -m 600 "$APP_DIR/server/.env.example" "$APP_DIR/.env"

# 헬스체크 대기 루프 (30s 정도)
for i in $(seq 1 30); do
  curl -fsS "http://127.0.0.1:${HOST_PORT}/health" >/dev/null 2>&1 && break
  sleep 1
done

# 이미지 정리 — 다른 서비스 영향 없도록 *이 앱 이미지만* 필터
podman images "${IMAGE_NAME}" --format "{{.Tag}}\t{{.ID}}\t{{.CreatedAt}}" \
  | grep -v -E "^latest\b" | sort -k3 -r \
  | awk -v keep="$IMAGE_RETAIN" 'NR > keep {print $2}' \
  | xargs -r podman rmi 2>/dev/null || true
```

## 방화벽

- firewalld 환경:
  ```bash
  sudo firewall-cmd --permanent --add-port=9091/tcp
  sudo firewall-cmd --reload
  ```
- rootless 는 1024 미만 포트 바인딩 못 함 → HOST_PORT 는 1024+ 로

## OAuth/토큰 갱신이 있는 마운트는 read-write

- read-only 마운트는 token refresh 가 파일을 쓰지 못해 만료 시 401
- 보안과 trade-off — refresh 가 있는 자격파일은 read-write 가 정답
