---
name: workflow
description: GitHub 개발 전체 흐름을 한 번에 실행하는 오케스트레이터. 요구사항이나 이슈(#번호/URL)를 받아 /start(이슈+브랜치) → /build(구현+검증+리뷰) → /ship(커밋+승인+PR)을 순서대로 실행하고, 중단된 작업은 멈춘 단계부터 재개한다. 이슈별 worktree로 여러 작업을 동시에 진행할 수 있다. "/workflow 로그인 폼 검증 추가", "/workflow #123", "이슈부터 PR까지 해줘" 같은 요청에 사용.
---

# Workflow — Start → Build → Ship

입력: `$ARGUMENTS`
- 자연어 요구사항 → 새 이슈부터 시작
- `#123`, `123`, 이슈 URL → 기존 이슈로 시작, 또는 진행 중이던 작업 재개

**사용자 승인은 `/ship`의 push/PR 직전 한 번뿐이다.** 그 전까지는 묻지 않고 진행한다.

## 1. 사전 점검

```bash
git rev-parse --show-toplevel
gh auth status -h github.com
gh repo view --json nameWithOwner -q .nameWithOwner
```
하나라도 실패하면 시작하지 않고 이유를 알린다 (git 저장소가 아님, gh 미로그인, GitHub 원격 아님).

## 2. 재개 판단

입력이 이슈 번호면 상태 파일을 확인한다.

```bash
STATE="$(git rev-parse --path-format=absolute --git-common-dir)/workflow/<번호>.json"
```

| `stage` | 다음 동작 |
|---|---|
| 파일 없음 | Start부터 |
| `started` | Build부터 |
| `build_failed` | Build부터 (재시도 횟수 초기화). 이전 실패 원인을 먼저 보여준다 |
| `built`, `committed`, `awaiting_approval` | Ship부터 |
| `done` | `pr_url`을 알려주고 끝 |

## 3. 단계 실행

각 단계 스킬을 Skill 도구로 호출한다. 단계 사이에는 **상태 파일로만** 정보를 넘긴다. 이슈 번호 외의 정보를 인자로 넘기지 않는다.

1. `Skill("start", "<입력 그대로>")` → 결과의 마지막 줄 `issue=<번호>`로 이슈 번호를 확정하고, 그 번호의 상태 파일이 `stage: "started"`인지 확인. 최신 파일을 골라 추측하지 않는다 (다른 세션의 작업일 수 있다)
2. `Skill("build", "#<번호>")` → `stage`가 `built`인지 확인
   - `build_failed`면 **여기서 멈춘다.** 실패 원인과 `/workflow #<번호>`로 재개할 수 있다는 안내를 남긴다.
3. `Skill("ship", "#<번호>")` → 승인 게이트를 거쳐 PR 생성
   - 사용자가 보류하면 `awaiting_approval`로 멈추고 재개 방법을 안내한다.

각 단계 뒤에 상태 파일을 다시 읽어 `stage`가 기대값인지 확인한다. 기대값이 아니면 진행하지 않고 보고한다.

## 4. 동시 작업

- 이슈마다 worktree(`<repo>.worktrees/<번호>-<name>`)와 상태 파일(`workflow/<번호>.json`)이 따로 있으므로, 서로 다른 이슈의 `/workflow`를 별도 세션에서 동시에 실행해도 된다.
- 같은 이슈를 두 세션에서 동시에 진행하지 않는다. 시작할 때 상태 파일의 `updated_at`이 10분 이내이고 `stage`가 `done`이 아니면, 다른 세션이 작업 중일 수 있다고 경고하고 계속할지 묻는다.
- 진행 중인 작업 목록이 필요하면 `ls "$(git rev-parse --path-format=absolute --git-common-dir)/workflow/"`의 JSON들을 읽어 이슈, 단계, 브랜치를 표로 보여준다.

## 5. 완료 보고

```
✅ #<번호> <제목>
- 브랜치: <branch>
- 검증: <통과한 명령 수>/<전체>, 수용 기준 <충족>/<전체>, 리뷰 blocking 0
- 스크린샷: 첨부 n개 | 필요 | 해당 없음
- PR: <pr_url>
```
