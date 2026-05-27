---
name: claude-cli-bridge
description: 로컬에 설치된 Claude CLI 를 HTTP/서비스에서 subprocess 로 호출해야 할 때 사용. timeout, JSON 파싱, is_error 처리, FileNotFoundError 친절 메시지까지 들어간 표준 래퍼. /chat 류 엔드포인트를 다른 언어/프레임워크로 옮길 때 이 패턴 그대로 차용.
---

# Claude CLI Bridge 패턴

Claude CLI 를 백엔드에서 호출하는 정석 구조. 이 레포 `server/claude_client.py` 가 레퍼런스 구현.

## CLI 호출 인자

```bash
claude -p --model <model> --output-format json <question>
```

- `-p` : print (non-interactive, stdout 으로 결과)
- `--output-format json` : 구조화된 응답 (`result`, `is_error`, `session_id`, …)
- 모델 alias 권장: `opus`, `sonnet`, `haiku`. 명시적 ID 도 가능

## 응답 처리 체크리스트

1. **timeout** — 기본 300s. asyncio 면 `asyncio.wait_for`, sync 면 `subprocess.run(timeout=)`. CLI 가 멈춰도 영원히 안 죽도록.
2. **FileNotFoundError** — CLI 미설치 / PATH 미반영. `CLAUDE_CLI_PATH` 환경변수로 절대경로 override 가능하도록.
3. **returncode != 0** — stdout 의 JSON `result` 필드가 보통 에러 사유. 없으면 stderr fallback. 502 매핑.
4. **JSON parse 실패** — 그래도 stdout 이 있으면 raw 그대로 리턴 (CLI 버전 차이 방어).
5. **`is_error: true`** — JSON 파싱은 성공했지만 CLI 가 에러로 판단. `result` 를 사유로 502.
6. **빈 stdout** — `Claude CLI returned empty output` 으로 502.

## 보안 / 운영 주의

- **자격증명**: `~/.claude/` (호스트의 인증된 디렉터리) 가 CLI 실행자에 readable 해야 함. 컨테이너면 마운트 + `userns_mode: keep-id` (rootless Podman) 또는 동등한 uid 매핑 필수
- **OAuth refresh**: `~/.claude/.credentials.json` 은 CLI 가 *덮어쓴다*. 마운트를 **read-write** 로 둘 것. `:ro` 면 access token 만료 후 401 로 죽음
- **shell injection 없음**: `subprocess_exec(*args)` 사용. `shell=True` 절대 금지 (질의문이 사용자 입력)
- **요청당 새 프로세스**: 동시성이 높으면 비용 큼. 풀링/큐잉은 별도 설계 필요

## 최소 구현 (Python, async)

```python
import asyncio, json

class ClaudeCliError(Exception): pass

async def ask_claude(question: str, model: str = "opus",
                     cli_path: str = "claude", timeout: int = 300) -> str:
    cmd = [cli_path, "-p", "--model", model, "--output-format", "json", question]
    try:
        proc = await asyncio.create_subprocess_exec(
            *cmd, stdout=asyncio.subprocess.PIPE, stderr=asyncio.subprocess.PIPE)
        stdout, stderr = await asyncio.wait_for(proc.communicate(), timeout=timeout)
    except asyncio.TimeoutError:
        raise ClaudeCliError(f"Claude CLI timed out after {timeout}s")
    except FileNotFoundError:
        raise ClaudeCliError(f"Claude CLI not found at '{cli_path}'")

    output = stdout.decode("utf-8", errors="replace").strip()
    try:
        data = json.loads(output) if output else None
    except json.JSONDecodeError:
        data = None

    if proc.returncode != 0:
        detail = (data or {}).get("result") or stderr.decode(errors="replace") or "no output"
        raise ClaudeCliError(f"Claude CLI exited {proc.returncode}: {detail}")
    if not output:
        raise ClaudeCliError("Claude CLI returned empty output")
    if data and data.get("is_error"):
        raise ClaudeCliError(data.get("result") or "Claude CLI reported error")
    return (data or {}).get("result") or output
```

## 다른 언어로 포팅 시 유지할 것

- timeout / FileNotFoundError / non-zero exit / is_error / empty output, 이 5 가지 분기. 빠뜨리지 말 것
- 에러 메시지에 항상 **exit code** 와 **CLI 의 result 문자열** 동봉 (디버깅에 결정적)
- 환경변수로 cli 경로 / 기본 모델 / timeout 오버라이드 가능하도록
