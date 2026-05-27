---
name: fastapi-jwt-2stage
description: FastAPI 에서 "장기 API_KEY → 단기 JWT → Bearer 인증" 2단 인증을 붙일 때 사용. 게이트웨이형 마이크로서비스에 자주 나오는 구조. python-jose + HTTPBearer + pydantic-settings 조합.
---

# FastAPI 2-Stage Auth (API_KEY → JWT → Bearer)

이 레포 `server/auth.py` + `server/main.py` 의 `/auth/token` 가 레퍼런스.

## 왜 2단인가

| 항목 | API_KEY (장기) | JWT (단기) |
|---|---|---|
| 수명 | 교체까지 영구 | 보통 15–60 분 |
| 보관 | 서버 + 발급자만 | 클라이언트 어디든 |
| 검증 | 평문 비교 | 서명 검증 (서버 stateless) |
| 폐기 | 값 교체 | secret 교체 → 모든 토큰 무효화 |

→ 장기 비밀을 매 요청마다 노출시키지 않고, 서버 측 세션 저장 없이 인증 가능.

## 의존성

```
fastapi
uvicorn
python-jose[cryptography]   # JWT
pydantic-settings           # .env 로딩
```

## 핵심 구조

### config.py — `.env` → Settings

```python
from pydantic_settings import BaseSettings, SettingsConfigDict

class Settings(BaseSettings):
    api_key: str = "change-me"
    jwt_secret: str = "replace-me"
    jwt_algorithm: str = "HS256"
    jwt_expire_minutes: int = 60

    model_config = SettingsConfigDict(env_file=".env", extra="ignore")

settings = Settings()
```

### auth.py — 발급/검증

```python
from datetime import datetime, timedelta, timezone
from fastapi import Depends, HTTPException, status
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
from jose import JWTError, jwt
from config import settings

bearer_scheme = HTTPBearer(auto_error=True)

def create_access_token(subject: str) -> tuple[str, int]:
    expires_in = settings.jwt_expire_minutes * 60
    expire = datetime.now(timezone.utc) + timedelta(seconds=expires_in)
    payload = {"sub": subject, "exp": expire, "iat": datetime.now(timezone.utc)}
    token = jwt.encode(payload, settings.jwt_secret, algorithm=settings.jwt_algorithm)
    return token, expires_in

def verify_token(creds: HTTPAuthorizationCredentials = Depends(bearer_scheme)) -> str:
    try:
        payload = jwt.decode(creds.credentials, settings.jwt_secret,
                             algorithms=[settings.jwt_algorithm])
    except JWTError:
        raise HTTPException(401, "Invalid or expired token",
                            headers={"WWW-Authenticate": "Bearer"})
    sub = payload.get("sub")
    if not sub:
        raise HTTPException(401, "Token missing subject",
                            headers={"WWW-Authenticate": "Bearer"})
    return sub
```

### main.py — 발급 엔드포인트 + 보호 엔드포인트

```python
from fastapi import Depends, FastAPI, HTTPException
from pydantic import BaseModel
from auth import create_access_token, verify_token
from config import settings

app = FastAPI()

class TokenRequest(BaseModel):
    api_key: str
    client_id: str | None = None

class TokenResponse(BaseModel):
    access_token: str
    token_type: str = "bearer"
    expires_in: int

@app.post("/auth/token", response_model=TokenResponse)
async def issue_token(req: TokenRequest):
    if req.api_key != settings.api_key:
        raise HTTPException(401, "Invalid API key")
    token, expires_in = create_access_token(req.client_id or "default")
    return TokenResponse(access_token=token, expires_in=expires_in)

@app.get("/secure")
async def secure(sub: str = Depends(verify_token)):
    return {"hello": sub}
```

## Swagger UI 와 잘 어울리게

`HTTPBearer` 사용 시 우측 상단 **Authorize** 버튼이 자동 생긴다. 값 입력란에 **토큰만** 붙여넣기 — `Bearer ` 접두사는 자동 첨부됨. 사용자에게 안내 필요.

## 운영 체크리스트

- [ ] `API_KEY`, `JWT_SECRET` 을 기본값에서 충분히 긴 랜덤값(`openssl rand -hex 32`)으로 교체
- [ ] `.env` 는 `.gitignore` 에 넣고 호스트에서만 관리
- [ ] 외부 노출 시 HTTPS 프록시 뒤에 둘 것 (Bearer 평문 전송)
- [ ] **즉시 폐기**가 필요하면 `JWT_SECRET` 교체 후 재기동 — 발급된 모든 토큰 무효화 (서버 상태가 없으므로 토큰 단위 revoke 불가)
- [ ] 알고리즘은 `HS256` (대칭) — 다중 검증자가 필요하면 `RS256`/`EdDSA` 로 비대칭 전환 고려

## 함정

- `jose` vs `pyjwt`: 둘 다 흔하지만 API 다름. 위 코드는 `python-jose` 기준
- `datetime.utcnow()` (deprecated) 대신 `datetime.now(timezone.utc)` 사용
- `WWW-Authenticate: Bearer` 헤더 빠뜨리면 일부 클라이언트가 재인증 흐름 못 탐
- 토큰 만료 시 자동 갱신 로직은 서버가 아니라 **클라이언트** 책임 — 401 받으면 `/auth/token` 재호출
