---
name: build
description: GitHub 작업 구현 단계. /start가 만든 이슈와 worktree에서 이슈 내용을 구현하고, lint/typecheck/test/build 검증, 수용 기준 대조, 서브에이전트 코드 리뷰, UI 변경 시 스크린샷 캡처까지 통과시킨다. "/build #123", "이슈 구현하고 검증해줘" 같은 요청에 사용. /workflow의 2단계이며 단독 호출도 가능.
---

# Build — 구현 + 검증

입력: `$ARGUMENTS` — 이슈 번호(`#123`/`123`). 비어 있으면 현재 브랜치 이름에서 번호를 찾는다.

모든 작업은 상태 파일의 `worktree` 안에서 한다. 원래 저장소 디렉터리의 파일은 건드리지 않는다.
이 단계는 사용자 승인 없이 진행하고, **통과하지 못하면 다음 단계로 넘기지 않는다.**

## 1. 상태 로드

```bash
STATE="$(git rev-parse --path-format=absolute --git-common-dir)/workflow/<번호>.json"
```
- 파일이 없으면 멈추고 `/start #<번호>`를 먼저 실행하라고 안내한다.
- `stage`가 `committed`, `awaiting_approval`, `done`이면 이미 Build를 지났다고 알리고 끝낸다.
- `gh issue view <번호> --json title,body`로 이슈를 다시 읽는다. 본문의 **수용 기준**이 작업 정의다. 수용 기준이 없으면 요구사항에서 검증 가능한 기준을 직접 도출해 기록한다.

## 2. 구현

- 저장소의 기존 패턴, 유틸, 스타일을 먼저 읽고 따른다.
- 이슈 범위를 벗어난 리팩터링이나 새 의존성 추가는 하지 않는다. 꼭 필요하면 이유를 기록한다.
- 기능에 맞는 테스트를 저장소 테스트 관례대로 추가하거나 수정한다.
- 이 단계에서는 **커밋하지 않는다.** 커밋은 `/ship`이 한다.

## 2.5. 의존성 준비

새 worktree에는 설치된 의존성이 없다. 검증 전에 **한 번** 준비한다. 이 단계의 실패는 수정 재시도 횟수에 포함하지 않는다.
- lockfile에 맞는 설치: `pnpm install --frozen-lockfile`, `yarn install --frozen-lockfile`, `npm ci`, `bun install`, `uv sync`/`pip install -e .`, `flutter pub get`, `pod install` 등 저장소에 해당하는 것
- 원래 저장소에 git에 없는 `.env`, `.env.local` 같은 로컬 설정 파일이 있으면 worktree로 복사한다 (내용은 출력하지 않는다)
- 설치가 실패하면 원인을 기록하고 `build_failed`로 멈춘다

## 3. 검증 명령 결정

1. `CLAUDE.md`/`AGENTS.md`의 `## Git Conventions` 섹션에 `verify:` 목록이 있으면 그것만 실행한다.
2. 없으면 저장소에서 탐지해, **존재하는 것만** 실행한다.

| 신호 | 명령 |
|---|---|
| `package.json` scripts | `lint`, `typecheck`(또는 `type-check`, `tsc`), `test`, `build`. 패키지 매니저는 lockfile로 선택 (`pnpm-lock.yaml`→pnpm, `yarn.lock`→yarn, `bun.lockb`→bun, 그 외 npm). test는 watch 모드가 아니게 실행 (`CI=1`) |
| `pyproject.toml` | 설정된 도구만: `ruff check .`, `mypy .`, `pytest` |
| `Cargo.toml` | `cargo clippy`, `cargo test`, `cargo build` |
| `go.mod` | `go vet ./...`, `go test ./...`, `go build ./...` |
| `gradlew` | `./gradlew lint test assembleDebug` (존재하는 task만) |
| `pubspec.yaml` | `flutter analyze`, `flutter test` |
| `Makefile` | `lint`, `test`, `build` 타깃이 있으면 `make <target>` |

검증 명령을 하나도 찾지 못하면 실패로 보지 않되, `verification.note`에 "검증 명령 없음"을 남기고 PR에 경고로 표시되게 한다.

## 4. 통과 기준

다음을 **모두** 만족해야 통과다.

1. **자동 검증**: 3단계의 모든 명령이 exit 0
2. **수용 기준**: 항목마다 `met: true`와 근거(테스트 이름, 실행 결과, 코드 위치)가 있음
3. **코드 리뷰**: 아래 리뷰에서 blocking 이슈 0개

### 코드 리뷰 (서브에이전트)

구현한 본인이 승인하지 않는다. Agent 도구로 새 서브에이전트를 띄워 리뷰를 맡긴다. 프롬프트에는 다음을 넣는다.
- worktree 경로, `git -C <worktree> diff origin/<base>` 결과를 직접 보라는 지시 (새 파일은 `git add -N .`으로 diff에 포함시킨다)
- 이슈 제목, 본문, 수용 기준
- 다음 형식으로만 답하라는 지시:
  ```
  - severity: blocking | major | minor
    file: path:line
    summary: 한 줄
  ```
- blocking 정의: 정확성 버그, 보안 문제, 데이터 손실, 수용 기준 미충족, 빌드나 테스트를 깨뜨리는 변경

major와 minor는 고칠 가치가 있으면 고치되, 통과 여부에는 영향이 없다. 결과는 PR 본문용으로 기록한다.

### 실패 시

실패 원인을 고치고 2~4단계를 다시 실행한다. **수정 재시도는 최대 3회**다. 3회 후에도 실패하면:
- `stage: "build_failed"`, `verification`에 마지막 실패 내용을 기록한다.
- 실패한 명령, 에러 요약, 시도한 수정을 보고하고 **멈춘다.** `/ship`으로 넘어가지 않는다.

## 5. UI 캡처

UI 변경 여부 판단:
- 컨벤션 섹션의 `ui_paths:`가 있으면 변경 파일이 그 경로에 해당하는지로 판단한다.
- 없으면 변경 파일로 추정: `*.tsx`, `*.jsx`, `*.vue`, `*.svelte`, `*.css`, `*.scss`, `*.html`, `*.dart`, `*.swift`, `*.kt`의 UI 코드, `res/layout/*.xml`, `components/`, `pages/`, `screens/`, `views/`, `app/`
- 판단이 애매하면 캡처를 시도한다.

런타임은 컨벤션 섹션의 `ui_runtime:`(`web` | `android` | `ios`)을 따르고, 없으면 스택으로 판단한다 (`package.json`의 웹 프레임워크 → web, `gradlew`/`AndroidManifest.xml` → android, `*.xcodeproj`/`Podfile` → ios, Flutter·React Native는 사용 가능한 쪽).

UI 변경이 있으면 스택에 맞는 런타임에서 실행해 **변경된 화면을 실제로 확인하고** 캡처한다. 작업 브랜치에 섞이지 않도록 커밋되지 않는 git 공통 디렉터리에 저장한다: `$(git rev-parse --path-format=absolute --git-common-dir)/workflow/<번호>-media/`

| 런타임 | 실행 | 캡처 |
|---|---|---|
| 웹 | `dev_command:`(컨벤션) 또는 `dev`/`start` script를 백그라운드로 실행하고 `dev_url:` 또는 출력된 URL 사용 | Playwright: `npx playwright screenshot <url> <file>.png` 또는 짧은 스크립트로 해당 화면까지 이동 후 캡처 |
| Android | `emulator -list-avds`로 AVD 실행, 앱 설치·실행 | `adb exec-out screencap -p > <file>.png`, 동작은 `adb shell screenrecord /sdcard/rec.mp4` 후 `adb pull /sdcard/rec.mp4` |
| iOS | `xcrun simctl boot <device>`, 앱 빌드·설치·실행 | `xcrun simctl io booted screenshot <file>.png`, 동작은 `xcrun simctl io booted recordVideo` |

- 파일 이름은 영어 kebab-case로 짓는다 (공백·한글 없이, 예: `login-error-state.png`). PR 본문 URL에 그대로 들어간다.
- 정적인 변화는 png, 동작이나 전환은 짧은(10초 이내) GIF로 만든다. 영상→GIF 변환에는 `ffmpeg`가 필요하다:
  `ffmpeg -y -i in.mp4 -vf "fps=10,scale=720:-1:flags=lanczos" -loop 0 out.gif`
  `ffmpeg`가 없으면 png만 남기고 GIF는 생략했다고 기록한다.
- 띄운 dev 서버, 에뮬레이터, 시뮬레이터는 캡처 후 종료한다.
- **실행할 수 없거나 화면 확인이 어려우면** 캡처를 건너뛰고 `media.status: "needs_screenshot"`과 이유를 기록한다. 이 경우 Build 실패로 보지 않는다.

## 6. 상태 갱신

```json
{
  "stage": "built",
  "verification": {
    "commands": [{"cmd": "pnpm test", "exit": 0, "summary": "42 passed"}],
    "acceptance": [{"criterion": "...", "met": true, "evidence": "..."}],
    "attempts": 1,
    "note": null
  },
  "review": {"blocking": 0, "findings": [{"severity": "minor", "file": "...", "summary": "..."}]},
  "media": {"status": "captured | needs_screenshot | not_ui", "reason": null, "files": [{"path": "/abs/.../login.png", "caption": "로그인 폼 에러 표시"}]},
  "updated_at": "<ISO-8601>"
}
```

기존 필드는 유지하고 위 필드만 추가하거나 덮어쓴다.

## 7. 보고

검증 결과, 수용 기준 충족 현황, 리뷰 요약, 캡처 결과를 짧게 알린다. 단독 호출이면 다음 단계로 `/ship #<번호>`를 안내한다.
