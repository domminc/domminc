# Claude Code 확장 도구 설치 — Mac mini 상시 가동용

한도가 끝나도 작업을 이어가고, 세션이 바뀌어도 지난 맥락을 기억하게 만드는 도구 다섯 개를
Mac mini에 설치하고 검증합니다. 설치는 `setup-mac.sh`가 하고, 이 문서는 사람이 직접 해야 하는
단계와 밖에서 쓰는 방법을 정리합니다.

| 도구 | 하는 일 | 설치 주체 | 상시 실행 |
|---|---|---|---|
| OmniRoute | 여러 AI 서비스를 한 창구로 묶고, 한도가 차면 다른 곳으로 넘김 | 스크립트 | 로그인 시 자동 (127.0.0.1:20128) |
| Headroom | 보내는 내용을 압축해 토큰 절약 | 스크립트 | 로그인 시 자동 (127.0.0.1:8787) |
| claude-mem | 작업 기록을 저장했다가 다음 세션에 알려줌 | 스크립트 | 로그인 시 워커 기동 (127.0.0.1:37700) |
| claude-code-setup | 프로젝트에 맞는 자동화·설정 추천 | 클로드 코드 안에서 직접 | — |
| Task Observer | 작업을 지켜보고 반복 개선점을 스킬로 정리 | 스킬 폴더 직접 배치 | — |

---

## 1. 실행

```zsh
git clone https://github.com/domminc/domminc.git
cd domminc/tools/claude-code-setup
bash setup-mac.sh            # 확인 → 없는 것만 설치 → 자동 시작 등록 → 검증
```

| 옵션 | 용도 |
|---|---|
| `--check` | 설치 없이 현재 상태 확인·검증만 (언제 다시 돌려도 안전) |
| `--no-autostart` | 로그인 시 자동 시작(LaunchAgent) 등록 생략 |
| `--yes` | Node·Python을 Homebrew로 설치할지 묻는 질문에 자동 yes |

스크립트가 지키는 원칙

- 이미 설치된 것은 다시 설치하지 않음
- 기존 설정 파일을 덮어쓰거나 지우지 않음 (claude-mem 설치 전 `~/.claude-backups/<시각>/`에 백업)
- `.zshrc` 등 셸 설정을 수정하지 않음 (필요하면 추가할 한 줄을 안내만 함)
- 하나 설치 → 실행 확인 → 다음으로. 실패하면 거기서 멈춤
- 키·토큰 값은 화면·로그에 남기지 않음
- 전체 로그: `~/Library/Logs/claude-tools/setup-<시각>.log`

마지막 요약이 **모두 PASS일 때만 "완료"**로 표시하고, 아니면 남은 조치를 목록으로 보여줍니다.

> **Python 주의** — macOS 기본 `python3`는 3.9라 기준(3.10+) 미달입니다. 스크립트가
> `brew install python@3.12`를 제안합니다. Headroom은 시스템 파이썬과 충돌하지 않도록
> 전용 가상환경(`~/.venvs/headroom`)에 설치합니다.

---

## 2. 스크립트 실행 후 직접 할 일

### ① OmniRoute에 AI 서비스 연결 (필수 — 안 하면 검증이 401로 실패)

1. 브라우저에서 `http://localhost:20128` (대시보드) 열기
2. 사용할 AI 공급자를 연결 (API 키 입력 또는 OAuth 로그인)
3. OmniRoute API 키 발급
4. 키를 화면에 찍지 않고 재검증:

```zsh
read -rs OMNIROUTE_API_KEY && export OMNIROUTE_API_KEY   # 붙여넣고 Enter (화면에 안 보임)
bash setup-mac.sh --check
```

### ② 클로드 코드 안에서 두 가지

```
/plugin install claude-code-setup@claude-plugins-official
```

Task Observer는 받은 스킬 폴더를 아래 위치에 둡니다. `SKILL.md`가 폴더 바로 안에 있어야 합니다.

```
~/.claude/skills/task-observer/SKILL.md
```

### ③ Headroom을 클로드 코드에 연결 (선택)

설치만으로는 클로드 코드가 Headroom을 거치지 않습니다. `headroom doctor`의 경고가 이것입니다.

| 방식 | 방법 | 장단점 |
|---|---|---|
| **A. 필요할 때만 (권장 시작점)** | `claude` 대신 `headroom wrap claude`로 실행 | 설정 파일 변경 없음. 문제 있으면 그냥 `claude`로 실행하면 끝 |
| B. 항상 | `~/.claude/settings.json`의 `env`에 `ANTHROPIC_BASE_URL=http://127.0.0.1:8787` 추가 | 모든 세션이 절약됨. 대신 Headroom이 꺼지면 클로드 코드가 응답하지 않음 |

A로 며칠 써 보고 `headroom doctor`의 savings(절감량)를 확인한 뒤 B로 갈지 정하는 것을 권합니다.
비용 상한은 `headroom proxy --budget 10` 또는 환경변수 `HEADROOM_BUDGET`으로 걸 수 있습니다.

### ④ 잠자기 끄기 (상시 가동 필수)

스크립트가 현재 설정을 확인해 알려줍니다. 잠들면 원격 접속과 서버가 모두 끊깁니다.

```zsh
sudo pmset -a sleep 0 disksleep 0 womp 1
```

시스템 설정 → 에너지에서 **정전 후 자동 시동**도 켜 두면, 정전 뒤에도 알아서 복구됩니다.
자동 로그인이 켜져 있어야 LaunchAgent가 재부팅 직후 바로 뜹니다.

---

## 3. 밖에서 쓰기

GitHub는 **설치 방법을 보관**하는 곳이고, 밖에서 **작업하는 통로**는 Mac mini 원격 접속입니다.
둘은 역할이 다릅니다.

```
[휴대폰·노트북] ── Claude 앱 ──────────────▶ [Mac mini: claude remote-control]  ← 일상 작업
[휴대폰·노트북] ── Tailscale + SSH ────────▶ [Mac mini: 터미널]                 ← 관리·복구
[아무 컴퓨터]   ── git clone ──────────────▶ [이 저장소: 스크립트·문서]          ← 새 기기 세팅
```

### 방법 1 — Claude 앱으로 원격 조종 (일상 작업, 권장)

Mac mini에서 작업할 프로젝트 폴더로 가서 실행합니다. 이 세션이 휴대폰·웹의 Claude Code 앱에
나타나고, 밖에서 그대로 이어서 쓸 수 있습니다. 작업은 Mac mini에서 돌기 때문에 claude-mem 기억과
Headroom 절약이 그대로 적용됩니다.

```zsh
brew install tmux
tmux new -s claude          # 터미널 창을 닫아도 살아 있는 작업 공간
cd ~/작업폴더
claude remote-control
# Ctrl+b 누른 뒤 d → 빠져나와도 계속 실행됨. 다시 들어가기: tmux attach -t claude
```

Claude Desktop 앱을 Mac mini에 켜 두는 방법도 있습니다.

### 방법 2 — Tailscale + SSH (관리·복구용)

서버가 멈췄을 때 밖에서 재시작하거나 로그를 보는 용도입니다.

1. Mac mini와 휴대폰·노트북에 Tailscale 설치 후 같은 계정으로 로그인 (개인 무료)
2. Mac mini: 시스템 설정 → 일반 → 공유 → **원격 로그인** 켜기
3. 밖에서: `ssh 사용자명@mac-mini` (Tailscale이 붙여 준 기기 이름) → `tmux attach -t claude`

### 하지 말 것

- 공유기 포트포워딩으로 20128·8787·37700 포트를 인터넷에 열지 않습니다. 스크립트는 세 서버를
  모두 `127.0.0.1`(Mac mini 자신만 접근 가능)에 묶어 둡니다. 밖에서는 위 두 방법으로만 접근합니다.

---

## 4. GitHub에 올리는 것과 올리지 않는 것

| 올림 (이 폴더) | 절대 올리지 않음 |
|---|---|
| `setup-mac.sh`, 이 README | API 키, OmniRoute API 키 |
| | `~/.omniroute/.env`, `~/.omniroute/storage.sqlite` (공급자 인증 정보) |
| | `~/.claude-mem/` (작업 기억 — 코드·대화 내용이 들어 있음) |
| | `~/.claude-backups/` |

> 이 저장소(`domminc/domminc`)는 **공개 저장소이자 GitHub 프로필 첫 화면**입니다. 스크립트에 비밀
> 정보는 없지만, 개인 작업 환경 파일을 포트폴리오와 분리하고 싶다면 비공개 저장소로 옮기는 것을
> 권합니다.

---

## 5. 상태 확인과 되돌리기

```zsh
# 상태
bash setup-mac.sh --check
launchctl list | grep claude-tools
tail -f ~/Library/Logs/claude-tools/com.claude-tools.omniroute.log

# 서버 재시작
launchctl kickstart -k gui/$(id -u)/com.claude-tools.omniroute
launchctl kickstart -k gui/$(id -u)/com.claude-tools.headroom-proxy
```

전부 제거하려면 아래를 실행합니다. 각 줄은 독립적이라 필요한 것만 골라 실행해도 됩니다.

```zsh
for l in omniroute headroom-proxy claude-mem-worker; do
  launchctl bootout gui/$(id -u)/com.claude-tools.$l 2>/dev/null
  rm -f ~/Library/LaunchAgents/com.claude-tools.$l.plist
done
npm uninstall -g omniroute                                 # OmniRoute (데이터 ~/.omniroute 는 남음)
rm -f "$(brew --prefix)/bin/headroom"; rm -rf ~/.venvs/headroom   # Headroom
npx --yes claude-mem@latest uninstall                      # claude-mem (플러그인·설정)
# 설정 복원이 필요하면: ~/.claude-backups/<시각>/ 의 파일을 ~/.claude/ 로 복사
```

---

## 참고: 클라우드 리허설에서 확인된 것 (2026-09-26, Linux 컨테이너)

| 항목 | 결과 |
|---|---|
| OmniRoute 3.8.50 | 설치·서버 기동·`doctor` 실패 0건. 공급자 미연결 상태에서 `/v1/models`는 401 |
| Headroom 0.39.0 | 시스템 pip 설치는 OS 패키지(PyJWT) 충돌로 실패 → **가상환경 설치로 해결**. 프록시 기동 후 `doctor` 실패 0건·경고 6건 |
| claude-mem 13.28.0 | 기본 `install`은 대화형 → `--ide claude-code --provider claude` 지정 시 무인 설치. `doctor` 통과 |

claude-mem은 `--provider claude` 설정에서 기억 요약을 사용자의 Anthropic 요금제로 처리합니다.
사용량이 조금 늘 수 있습니다.
