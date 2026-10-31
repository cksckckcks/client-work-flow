---
name: start
description: GitHub 작업 시작 단계. 자연어 요구사항으로 이슈를 만들거나 기존 이슈(#번호/URL)를 불러오고, 저장소 컨벤션에 맞는 브랜치를 git worktree로 만든다. "/start 로그인 폼 검증 추가", "/start #123", "이슈 만들고 브랜치 따줘" 같은 요청에 사용. /workflow의 1단계이며 단독 호출도 가능.
---

# Start — 이슈 + 브랜치

입력 하나를 받아 **이슈 번호가 확정된 작업용 worktree**를 만들고 상태 파일에 기록한다.

입력: `$ARGUMENTS`
- `#123`, `123`, `https://github.com/<owner>/<repo>/issues/123` → 기존 이슈 사용
- 그 외 텍스트 → 새 이슈 생성

이 단계는 사용자 승인 없이 끝까지 진행한다. 이슈 생성은 되돌리기 쉬운 작업이고, push/PR 전 승인은 `/ship`이 담당한다.

## 1. 사전 점검

아래 중 하나라도 실패하면 즉시 멈추고 무엇이 문제인지 한국어로 알린다.

```bash
git rev-parse --show-toplevel          # git 저장소인가
gh auth status -h github.com           # gh 로그인 되어 있는가
gh repo view --json nameWithOwner,defaultBranchRef -q '.nameWithOwner + " " + .defaultBranchRef.name'   # 원격이 GitHub인가
```

## 2. 컨벤션 읽기

다음 순서로 찾고, 찾은 출처를 `conventions_source`로 기록한다.

1. 저장소 루트의 `CLAUDE.md` 또는 `AGENTS.md` 안의 `## Git Conventions` 섹션 (이 섹션만 규칙으로 취급한다)
   - `branch:` 브랜치 패턴, `base:` base 브랜치
2. `.github/ISSUE_TEMPLATE/` (이슈 본문 형식)
3. 기본값
   - branch: `{type}/#{issue}-{name}`
   - base: 저장소 기본 브랜치 (`defaultBranchRef`)

## 3. 이슈 확보

**기존 이슈:**
```bash
gh issue view <번호> --json number,title,body,state,url
```
- 이슈가 닫혀 있으면 멈추고 알린다.
- 상태 파일(5단계 경로)이 이미 있으면 새로 만들지 말고, 기록된 `stage`와 `worktree`를 보고하고 끝낸다. 이어서 진행하려면 `/workflow #번호`를 쓰라고 안내한다.

**새 이슈:**
- 요구사항을 이슈 제목(70자 이내, 명확한 동작)과 본문으로 정리한다.
- 이슈 템플릿이 있으면 가장 맞는 템플릿을 고르고 그 섹션 구조를 그대로 채운다. YAML 폼(`.yml`)은 각 필드의 `label`을 `### 제목`으로 써서 채운다.
- 템플릿이 없으면 기본 형식:
  ```markdown
  ## 배경
  ## 요구사항
  ## 수용 기준
  - [ ] 검증 가능한 기준 1
  - [ ] ...
  ```
- **수용 기준은 반드시 작성한다.** `/build`가 이 목록으로 완료를 판정한다.
- 템플릿 frontmatter의 `labels`는 `gh label list`에 실제로 있는 것만 붙인다.

```bash
gh issue create --title "<제목>" --body-file <본문 임시파일> [--label <label>]
```
출력된 URL에서 이슈 번호를 얻는다.

## 4. 브랜치 + worktree

- `type`: 이슈 내용으로 추론 — `feat` | `fix` | `docs` | `style` | `refactor` | `perf` | `test` | `chore`
- `name`: 구현 내용이 드러나는 영어 kebab-case, 40자 이내 (예: `login-form-validation`). 한국어 이슈도 영어로 옮긴다.
- 패턴에 대입: 기본값이면 `feat/#123-login-form-validation`
- 브랜치 이름의 `#` 때문에 **셸에서는 항상 따옴표로 감싼다.**
- worktree 디렉터리 이름에는 `#`을 쓰지 않는다.

```bash
# worktree 안에서 실행해도 원래 저장소를 기준으로 삼는다
ROOT=$(dirname "$(git rev-parse --path-format=absolute --git-common-dir)")
REPO=$(basename "$ROOT")
WT="$(dirname "$ROOT")/$REPO.worktrees/<번호>-<name>"
git fetch origin "<base>"
git worktree add -b "<branch>" "$WT" "origin/<base>"
```

브랜치가 이미 있으면 새로 만들지 말고 `git worktree add "$WT" "<branch>"`로 연결한다.

## 5. 상태 파일

경로: worktree 사이에서 공유되고 커밋되지 않는 git 내부 디렉터리.

```bash
STATE_DIR="$(git rev-parse --path-format=absolute --git-common-dir)/workflow"
mkdir -p "$STATE_DIR"
# 파일: $STATE_DIR/<번호>.json
```

내용 (JSON, Write 도구로 작성):

```json
{
  "issue": 123,
  "issue_url": "https://github.com/<owner>/<repo>/issues/123",
  "title": "<이슈 제목>",
  "repo": "<owner>/<repo>",
  "base": "main",
  "branch": "feat/#123-login-form-validation",
  "worktree": "/abs/path/<repo>.worktrees/123-login-form-validation",
  "conventions_source": "CLAUDE.md#Git Conventions | .github templates | defaults",
  "stage": "started",
  "updated_at": "<ISO-8601>"
}
```

## 6. 보고

이슈 URL, 브랜치, worktree 경로, 사용한 컨벤션 출처를 짧게 알린다. 단독 호출이면 다음 단계로 `/build #<번호>`를 안내한다.

보고의 **마지막 줄은 항상 `issue=<번호>`** 로 끝낸다. `/workflow`는 이 줄로 이슈 번호를 확정한다.
