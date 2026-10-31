# client-work-flow

GitHub 이슈부터 PR까지를 Claude Code 스킬 4개로 처리하는 워크플로입니다.

```
/workflow <요구사항 | #번호 | 이슈 URL>
   │
   ├─ /start  이슈 생성(또는 기존 이슈 로드) → 브랜치 + worktree
   ├─ /build  구현 → lint/typecheck/test/build → 수용 기준 대조 → 코드 리뷰 → UI 캡처
   └─ /ship   커밋 → ✋ 승인 → push → PR 생성
```

- 사람의 확인은 **push/PR 직전 한 번**뿐입니다. 그 전 단계는 자동으로 진행됩니다.
- 각 단계는 `/start`, `/build #123`, `/ship #123`처럼 따로 실행할 수도 있습니다.
- 다른 플러그인이나 스킬 없이 Claude Code 기본 도구, `git`, `gh`만 사용합니다.

## 설치

```bash
git clone <이 저장소 URL> ~/client-work-flow
cd ~/client-work-flow
./install.sh
```

`~/.claude/skills/{start,build,ship,workflow}`에 symlink를 만듭니다. 다시 실행해도 안전하며, `git pull` 후에는 따로 설치할 필요가 없습니다. 같은 이름의 스킬 디렉터리가 이미 있으면(symlink가 아닌 경우) 덮어쓰지 않고 건너뜁니다. 설치 후 Claude Code를 재시작하세요.

### 필요한 도구

| 도구 | 용도 | 필수 |
|---|---|---|
| `git` 2.31+ | worktree, 상태 경로 | ✅ |
| `gh` (`gh auth login` 완료) | 이슈, PR, 미디어 업로드 | ✅ |
| Playwright (`npx playwright install`) | 웹 UI 스크린샷 | UI 작업 시 |
| Android SDK (`emulator`, `adb`) | Android 스크린샷 | Android 작업 시 |
| Xcode (`xcrun simctl`) | iOS 스크린샷 | iOS 작업 시 |
| `ffmpeg` | 녹화 → GIF 변환 | 선택 (없으면 png만 첨부) |

## 사용법

```text
/workflow 로그인 폼에 이메일 형식 검증 추가     # 새 이슈부터 PR까지
/workflow #123                                # 기존 이슈로 시작, 또는 멈춘 단계부터 재개
/start #123                                   # 단계별 실행
/build #123
/ship #123
```

### 동작 규칙

| 항목 | 규칙 |
|---|---|
| 브랜치 | 기본값 `{type}/#{이슈번호}-{구현-내용}` (예: `feat/#123-login-form-validation`) |
| worktree | `../<repo>.worktrees/<번호>-<이름>`. 이슈마다 따로 만들어 여러 작업을 동시에 진행할 수 있음. 의존성 설치와 `.env` 복사는 `/build`가 처리 |
| 커밋 | AngularJS Git Commit Message Convention: `type(scope): subject`, footer에 `Refs #번호` |
| 검증 통과 | 모든 검증 명령 exit 0 + 수용 기준 충족 + 리뷰 blocking 0건. 실패하면 최대 3회 스스로 수정하고, 그래도 실패하면 멈춤 |
| UI 변경 | 웹/에뮬레이터/시뮬레이터에서 실행해 png·GIF 캡처. 확인할 수 없으면 PR에 "⚠️ 스크린샷 필요" 표시 |
| 미디어 | `pr-assets` 브랜치의 `<번호>/`에 업로드. 작업 브랜치에는 커밋되지 않음 |
| PR | `.github` PR 템플릿이 있으면 그 형식, 없으면 요약·변경 내역·구현 결정·검증·수용 기준·리뷰·스크린샷 + `Closes #번호` |
| 상태 | `.git/workflow/<번호>.json` (worktree 사이에서 공유, 커밋되지 않음) |

## 프로젝트별 규칙: `## Git Conventions`

대상 저장소의 `CLAUDE.md` 또는 `AGENTS.md`에 아래 섹션을 넣으면 기본값 대신 이 규칙을 따릅니다. 모든 항목은 선택이고, 빠진 항목에는 기본값을 씁니다. 스킬은 **정확히 이 제목의 섹션**만 읽습니다.

```markdown
## Git Conventions
- branch: `{type}/#{issue}-{name}`
- base: develop
- commit: angular
- verify:
  - pnpm lint
  - pnpm typecheck
  - pnpm test
  - pnpm build
- ui_runtime: web            # web | android | ios
- ui_paths: src/components/**, src/pages/**
- dev_command: pnpm dev
- dev_url: http://localhost:3000
```

이슈와 PR 본문 형식은 `.github/ISSUE_TEMPLATE/`와 `.github/PULL_REQUEST_TEMPLATE.md`가 있으면 그것을 따릅니다.

## 구조

```
skills/
├── start/SKILL.md
├── build/SKILL.md
├── ship/SKILL.md
├── ship/scripts/upload-media.sh
└── workflow/SKILL.md
install.sh
```
