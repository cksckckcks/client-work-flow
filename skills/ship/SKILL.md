---
name: ship
description: GitHub 작업 마무리 단계. /build를 통과한 변경을 AngularJS 컨벤션(또는 저장소 컨벤션)으로 커밋하고, 사용자 승인을 받은 뒤 push하고 상세한 PR(검증 결과, 수용 기준, 리뷰, UI 스크린샷 포함)을 만든다. "/ship #123", "커밋하고 PR 올려줘" 같은 요청에 사용. /workflow의 3단계이며 단독 호출도 가능.
---

# Ship — 커밋 + PR

입력: `$ARGUMENTS` — 이슈 번호(`#123`/`123`). 비어 있으면 현재 브랜치 이름에서 번호를 찾는다.

**이 워크플로에서 사용자 승인을 받는 지점은 여기 하나뿐이다.** 로컬 커밋은 자동으로 하지만, push·미디어 업로드·PR 생성은 승인 후에만 한다.

## 1. 상태 로드

```bash
STATE="$(git rev-parse --path-format=absolute --git-common-dir)/workflow/<번호>.json"
```
- `stage`가 `built`, `committed`, `awaiting_approval`이 아니면 멈춘다. `build_failed`나 `started`이면 `/build #<번호>`를 먼저 실행하라고 안내한다. `done`이면 `pr_url`을 알려주고 끝낸다.
- 모든 git 명령은 `git -C "<worktree>"`로 실행한다. 브랜치 이름은 항상 따옴표로 감싼다.

## 2. 컨벤션 읽기

1. `CLAUDE.md`/`AGENTS.md`의 `## Git Conventions` 섹션 (`commit:` 형식 등)
2. `.github/PULL_REQUEST_TEMPLATE.md`, `.github/pull_request_template.md`, `docs/`, 루트, `.github/PULL_REQUEST_TEMPLATE/` 아래 템플릿
3. 기본값: AngularJS Git Commit Message Convention, 아래 기본 PR 형식

## 3. 커밋 (`stage`가 `built`일 때만)

변경을 논리 단위로 나눠 커밋한다(예: 기능 코드와 테스트, 별개의 리팩터링). 억지로 쪼개지 않는다. 한 단위면 커밋 하나로 충분하다.

AngularJS 형식:
```
<type>(<scope>): <subject>

<body>

<footer>
```
- `type`: `feat` | `fix` | `docs` | `style` | `refactor` | `perf` | `test` | `chore`
- `scope`: 변경된 모듈이나 영역 (생략 가능)
- `subject`: 명령형 현재 시제, 첫 글자 소문자, 끝에 마침표 없음, 50자 이내
- `body`: 무엇을 왜 바꿨는지 (선택, 72자 줄바꿈)
- `footer`: `Refs #<번호>`는 필수. 호환성이 깨지면 `BREAKING CHANGE: <설명>`

```bash
git -C "<worktree>" add <파일들>
git -C "<worktree>" commit -F <메시지 임시파일>
```
커밋 후 `stage: "committed"`, `commits: ["<sha> <subject>", ...]`를 기록한다.

## 4. PR 본문 작성

템플릿이 있으면 그 섹션 구조를 그대로 채운다. 템플릿에 없는 아래 항목은 끝에 덧붙인다. 템플릿이 없으면 아래 형식을 쓴다. **내용은 상세하게** 쓴다. 리뷰어가 코드를 열기 전에 무엇을 왜 바꿨는지 알 수 있어야 한다.

```markdown
## 요약
<이 PR이 해결하는 문제와 결과 2~3문장>

## 변경 내역
- <파일/모듈 단위로 무엇을 바꿨는지>

## 구현 결정
- <선택한 방식과 이유, 검토했지만 택하지 않은 대안>

## 검증
| 명령 | 결과 |
|---|---|
| `pnpm test` | ✅ 42 passed |

## 수용 기준
- [x] <기준> — <근거>

## 코드 리뷰
<blocking 0건. major/minor 요약과 반영 여부>

## 스크린샷
<UI 변경 시 이미지. 캡처 실패면 "⚠️ 스크린샷 필요: <이유>">

Closes #<번호>
```

- 제목: 첫 커밋 형식을 따른 `<type>(<scope>): <subject>`
- `verification.note`가 있으면 검증 섹션에 경고로 표시한다.
- `media.status`가 `needs_screenshot`이면 스크린샷 섹션에 **"⚠️ 스크린샷 필요"**와 이유를 남긴다. `not_ui`면 섹션을 뺀다.
- `Closes #<번호>`는 항상 포함한다.

## 5. 승인 게이트

다음을 한 번에 보여주고 AskUserQuestion으로 승인을 받는다.
- 브랜치 → base
- 커밋 목록 (`git -C "<worktree>" log --oneline "origin/<base>..HEAD"`)
- 업로드할 미디어 파일 목록
- PR 제목과 본문 전체

선택지: **승인하고 PR 생성** / **본문 수정** (요청을 반영하고 다시 보여준다) / **보류**

승인 전에는 `stage: "awaiting_approval"`로 기록한다. 보류하면 그 상태로 멈추고, `/workflow #<번호>`나 `/ship #<번호>`로 다시 이어갈 수 있다고 안내한다.

## 6. push, 미디어 업로드, PR 생성 (승인 후)

```bash
git -C "<worktree>" push -u origin "<branch>"
```

미디어가 있으면 이 스킬의 base directory에 있는 `scripts/upload-media.sh`로 `pr-assets` 브랜치에 올린다. 작업 브랜치에는 커밋되지 않는다.
```bash
cd "<worktree>" && bash "<이 스킬의 base directory>/scripts/upload-media.sh" <번호> <파일1> [<파일2> ...]
```
스크립트는 파일마다 `![](URL)`에 쓸 URL을 한 줄씩 출력한다. 4단계 본문의 스크린샷 자리에 `![<caption>](<URL>)`로 넣는다. 업로드에 실패하면 "⚠️ 스크린샷 필요"로 바꾸고 계속 진행한다.

이전 실행이 push 이후에 중단됐을 수 있으므로, 먼저 이 브랜치의 PR이 이미 있는지 확인한다.
```bash
gh pr view "<branch>" --json url,state -q '.state + " " + .url'
```
- 열린 PR이 있으면 새로 만들지 않고 `gh pr edit "<branch>" --title "<제목>" --body-file <본문 임시파일>`로 갱신한다.
- 없으면 생성한다:
```bash
gh pr create --base "<base>" --head "<branch>" --title "<제목>" --body-file <본문 임시파일>
```

## 7. 상태 갱신, 보고

`stage: "done"`, `pr_url`, `updated_at`을 기록하고 PR URL을 알린다.
worktree는 지우지 않는다. 머지 후 `git worktree remove "<worktree>"`로 정리할 수 있다고 한 줄 안내한다.
