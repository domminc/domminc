#!/usr/bin/env bash
# Claude Code 확장 도구 설치·검증 스크립트 (macOS, 상시 가동 Mac mini 기준)
#
#   OmniRoute   — 여러 AI 공급자를 한 창구로 묶고 한도 초과 시 우회 (포트 20128)
#   Headroom    — 요청을 압축해 토큰을 아끼는 로컬 프록시           (포트 8787)
#   claude-mem  — 세션이 바뀌어도 지난 작업을 기억하는 플러그인      (포트 37700)
#   claude-code-setup, Task Observer — 클로드 코드 안에서 직접 설치 (README 참고)
#
# 사용법
#   bash setup-mac.sh            확인 → 없는 것만 설치 → 자동 시작 등록 → 검증
#   bash setup-mac.sh --check    설치 없이 확인·검증만
#   bash setup-mac.sh --no-autostart   LaunchAgent 등록 생략
#   bash setup-mac.sh --yes      Homebrew 설치 여부 질문에 모두 yes
#
# 원칙: 기존 설정 파일을 덮어쓰거나 지우지 않는다 / 설치된 것은 다시 설치하지 않는다 /
#       키·토큰 값은 화면과 로그에 남기지 않는다 / 하나 설치하고 검증한 뒤 다음으로 간다.
#
# macOS 기본 bash(3.2)에서도 돌도록 bash 4 문법은 쓰지 않는다.

set -u

CHECK_ONLY=0
AUTOSTART=1
ASSUME_YES=0
for arg in "$@"; do
  case "$arg" in
    --check) CHECK_ONLY=1 ;;
    --no-autostart) AUTOSTART=0 ;;
    --yes|-y) ASSUME_YES=1 ;;
    -h|--help) sed -n '2,20p' "$0"; exit 0 ;;
    *) echo "알 수 없는 옵션: $arg" >&2; exit 2 ;;
  esac
done

MIN_NODE="22.22.2"
MIN_PYTHON="3.10.0"
OMNIROUTE_PORT=20128
HEADROOM_PORT=8787
CLAUDE_MEM_PORT=37700
HEADROOM_VENV="$HOME/.venvs/headroom"
AGENT_DIR="$HOME/Library/LaunchAgents"
LOG_DIR="$HOME/Library/Logs/claude-tools"
STAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP_DIR="$HOME/.claude-backups/$STAMP"

mkdir -p "$LOG_DIR"
LOG_FILE="$LOG_DIR/setup-$STAMP.log"
exec > >(tee -a "$LOG_FILE") 2>&1

# ---------- 출력 도우미 ----------
if [ -t 1 ]; then B=$'\033[1m'; G=$'\033[32m'; Y=$'\033[33m'; R=$'\033[31m'; N=$'\033[0m'; else B=; G=; Y=; R=; N=; fi
step()  { printf '\n%s== %s ==%s\n' "$B" "$1" "$N"; }
ok()    { printf '  %s✔%s %s\n' "$G" "$N" "$1"; }
warn()  { printf '  %s⚠%s %s\n' "$Y" "$N" "$1"; }
fail()  { printf '  %s✘%s %s\n' "$R" "$N" "$1"; }
info()  { printf '    %s\n' "$1"; }
run()   { printf '  $ %s\n' "$*"; "$@"; }

COMMANDS_RUN=""
record() { COMMANDS_RUN="${COMMANDS_RUN}  - $*"$'\n'; }

CREATED=""
created() { CREATED="${CREATED}  - $1"$'\n'; }

ask() {
  [ "$ASSUME_YES" = 1 ] && return 0
  local a
  read -r -p "  $1 [y/N] " a </dev/tty || return 1
  [ "$a" = y ] || [ "$a" = Y ]
}

# $1 >= $2 이면 참 (x.y.z 비교)
ver_ge() {
  local a b i x y
  IFS=. read -r -a a <<< "$1"
  IFS=. read -r -a b <<< "$2"
  for i in 0 1 2; do
    x=${a[$i]:-0}; y=${b[$i]:-0}
    if [ "$((10#$x))" -gt "$((10#$y))" ]; then return 0; fi
    if [ "$((10#$x))" -lt "$((10#$y))" ]; then return 1; fi
  done
  return 0
}

port_up() { # 포트가 HTTP로 응답하면 참 (상태 코드 무관)
  local code
  code=$(curl -s -o /dev/null -m 2 -w '%{http_code}' "http://127.0.0.1:$1/" 2>/dev/null)
  [ -n "$code" ] && [ "$code" != "000" ]
}

wait_port() { # $1 포트, $2 최대 초
  local i=0
  while [ "$i" -lt "$2" ]; do port_up "$1" && return 0; sleep 2; i=$((i + 2)); done
  return 1
}

# ---------- 0. 환경 ----------
step "0. 환경 확인"
if [ "$(uname -s)" != "Darwin" ] && [ "${CLAUDE_TOOLS_ALLOW_NON_MAC:-0}" != 1 ]; then
  fail "macOS 전용 스크립트입니다 (현재: $(uname -s))."
  exit 1
fi
ok "OS: $(sw_vers -productName 2>/dev/null || uname -s) $(sw_vers -productVersion 2>/dev/null)  / 로그: $LOG_FILE"

BREW=""
if command -v brew >/dev/null 2>&1; then
  BREW="$(command -v brew)"
  BREW_PREFIX="$(brew --prefix)"
  ok "Homebrew: $BREW_PREFIX"
else
  BREW_PREFIX=""
  warn "Homebrew가 없습니다. Node·Python이 기준 미달이면 https://brew.sh 의 설치 명령을 먼저 실행하세요."
fi

if command -v claude >/dev/null 2>&1; then
  ok "Claude Code: $(claude --version 2>/dev/null | head -1)"
else
  warn "claude 명령이 없습니다. 클로드 코드를 먼저 설치하세요 (claude-mem 연결과 원격 사용에 필요)."
fi

# ---------- 1. 설치 여부 확인 ----------
step "1. 설치 여부 확인"

NODE_VER=""
if command -v node >/dev/null 2>&1; then NODE_VER="$(node --version | sed 's/[^0-9.]//g')"; fi
record "node --version"
if [ -n "$NODE_VER" ] && ver_ge "$NODE_VER" "$MIN_NODE"; then
  ok "Node $NODE_VER (기준 $MIN_NODE 이상)"
else
  fail "Node ${NODE_VER:-없음} (기준 $MIN_NODE 이상 필요)"
  if [ "$CHECK_ONLY" = 0 ] && [ -n "$BREW" ] && ask "brew install node 로 설치/업그레이드할까요?"; then
    run brew install node; record "brew install node"
    NODE_VER="$(node --version | sed 's/[^0-9.]//g')"
    if ver_ge "$NODE_VER" "$MIN_NODE"; then ok "Node $NODE_VER"; else fail "Node $NODE_VER 여전히 기준 미달"; exit 1; fi
  else
    info "다음 조치: brew install node  (nvm 사용자는 nvm install 22 && nvm use 22)"
    exit 1
  fi
fi

# 기준을 만족하는 파이썬을 새 버전부터 찾는다. macOS 기본 python3(3.9)는 기준 미달이다.
PY=""; PY_VER=""
for c in python3.13 python3.12 python3.11 python3.10 python3; do
  if command -v "$c" >/dev/null 2>&1; then
    v="$("$c" -c 'import sys;print("%d.%d.%d" % sys.version_info[:3])' 2>/dev/null)"
    if [ -n "$v" ] && ver_ge "$v" "$MIN_PYTHON"; then PY="$(command -v "$c")"; PY_VER="$v"; break; fi
  fi
done
record "python3 --version"
if [ -n "$PY" ]; then
  ok "Python $PY_VER ($PY)"
else
  fail "Python 3.10 이상을 찾지 못했습니다 (python3: $(python3 --version 2>&1))"
  if [ "$CHECK_ONLY" = 0 ] && [ -n "$BREW" ] && ask "brew install python@3.12 로 설치할까요?"; then
    run brew install python@3.12; record "brew install python@3.12"
    PY="$BREW_PREFIX/bin/python3.12"; PY_VER="$("$PY" -c 'import sys;print("%d.%d.%d" % sys.version_info[:3])')"
    ok "Python $PY_VER ($PY)"
  else
    info "다음 조치: brew install python@3.12"
    exit 1
  fi
fi

HAVE_OMNIROUTE=0; HAVE_HEADROOM=0; HAVE_CLAUDE_MEM=0
record "omniroute --version"
if command -v omniroute >/dev/null 2>&1; then
  HAVE_OMNIROUTE=1; ok "omniroute $(omniroute --version 2>/dev/null | tail -1) — 이미 설치됨"
else
  warn "omniroute 미설치"
fi

record "headroom --version"
if command -v headroom >/dev/null 2>&1; then
  HAVE_HEADROOM=1; ok "$(headroom --version 2>/dev/null | tail -1) — 이미 설치됨"
elif [ -x "$HEADROOM_VENV/bin/headroom" ]; then
  HAVE_HEADROOM=1; ok "$("$HEADROOM_VENV/bin/headroom" --version | tail -1) — $HEADROOM_VENV 에 설치됨 (PATH 연결은 2단계에서 확인)"
else
  warn "headroom 미설치"
fi

record "npx --yes claude-mem@latest --version"
CM_CLI_VER="$(npx --yes claude-mem@latest --version 2>/dev/null | tail -1)"
PLUGINS_JSON="$HOME/.claude/plugins/installed_plugins.json"
if [ -f "$PLUGINS_JSON" ] && grep -q 'claude-mem' "$PLUGINS_JSON"; then
  HAVE_CLAUDE_MEM=1; ok "claude-mem 플러그인 설치됨 (CLI ${CM_CLI_VER:-?})"
else
  warn "claude-mem 플러그인 미설치 (npx CLI 버전: ${CM_CLI_VER:-확인 실패}) — npx로 실행되는 것과 플러그인 설치는 별개"
fi

# ---------- 2. 없는 것만 하나씩 설치 ----------
if [ "$CHECK_ONLY" = 0 ]; then
  step "2-1. OmniRoute"
  if [ "$HAVE_OMNIROUTE" = 1 ]; then
    ok "건너뜀 (이미 설치됨)"
  else
    NPM_PREFIX="$(npm prefix -g)"
    if [ ! -w "$NPM_PREFIX/lib" ] && [ ! -w "$NPM_PREFIX" ]; then
      fail "npm 전역 폴더($NPM_PREFIX)에 쓰기 권한이 없습니다. sudo로 설치하지 말고 Homebrew node 또는 nvm을 쓰세요."
      exit 1
    fi
    run npm install -g omniroute; record "npm install -g omniroute"
    if command -v omniroute >/dev/null 2>&1 && omniroute --version >/dev/null 2>&1; then
      HAVE_OMNIROUTE=1; ok "omniroute $(omniroute --version | tail -1) 설치 확인"
      created "$NPM_PREFIX/bin/omniroute (전역 CLI)"
    else
      fail "omniroute 설치 후 실행 확인 실패 — 위 npm 로그를 확인하세요."; exit 1
    fi
  fi

  step "2-2. Headroom"
  if [ "$HAVE_HEADROOM" = 1 ] && command -v headroom >/dev/null 2>&1; then
    ok "건너뜀 (이미 설치됨)"
  else
    if [ ! -x "$HEADROOM_VENV/bin/headroom" ]; then
      # 시스템/Homebrew 파이썬을 건드리지 않도록 전용 가상환경에 설치한다.
      run "$PY" -m venv "$HEADROOM_VENV"; record "$PY -m venv $HEADROOM_VENV"
      run "$HEADROOM_VENV/bin/pip" install --upgrade pip
      info "headroom-ai[all]은 torch 등을 포함해 수 GB, 수 분이 걸립니다."
      run "$HEADROOM_VENV/bin/pip" install "headroom-ai[all]"; record "$HEADROOM_VENV/bin/pip install \"headroom-ai[all]\""
      created "$HEADROOM_VENV/ (headroom 전용 가상환경)"
    fi
    if ! "$HEADROOM_VENV/bin/headroom" --version >/dev/null 2>&1; then
      fail "headroom 설치 후 실행 확인 실패 — 위 pip 로그를 확인하세요."; exit 1
    fi
    # PATH에 바로가기를 둔다. 셸 설정 파일(.zshrc)은 수정하지 않는다.
    LINK_DIR="${BREW_PREFIX:+$BREW_PREFIX/bin}"
    [ -z "$LINK_DIR" ] && LINK_DIR="$HOME/.local/bin"
    mkdir -p "$LINK_DIR"
    if [ -e "$LINK_DIR/headroom" ]; then
      warn "$LINK_DIR/headroom 가 이미 있어 바로가기를 만들지 않았습니다."
    else
      run ln -s "$HEADROOM_VENV/bin/headroom" "$LINK_DIR/headroom"
      created "$LINK_DIR/headroom → $HEADROOM_VENV/bin/headroom (바로가기)"
    fi
    case ":$PATH:" in *":$LINK_DIR:"*) ;; *) warn "$LINK_DIR 가 PATH에 없습니다. ~/.zshrc에 직접 추가하세요: export PATH=\"$LINK_DIR:\$PATH\"" ;; esac
    HAVE_HEADROOM=1; ok "$("$HEADROOM_VENV/bin/headroom" --version | tail -1) 설치 확인"
  fi

  step "2-3. claude-mem"
  if [ "$HAVE_CLAUDE_MEM" = 1 ]; then
    ok "건너뜀 (이미 설치됨)"
  else
    # 설치기가 ~/.claude 설정을 수정하므로 작은 설정 파일만 먼저 백업한다.
    mkdir -p "$BACKUP_DIR"
    for f in settings.json settings.local.json CLAUDE.md plugins/installed_plugins.json plugins/known_marketplaces.json; do
      if [ -f "$HOME/.claude/$f" ]; then
        mkdir -p "$BACKUP_DIR/$(dirname "$f")"; cp -p "$HOME/.claude/$f" "$BACKUP_DIR/$f"
      fi
    done
    ok "$HOME/.claude 설정 백업: $BACKUP_DIR"
    created "$BACKUP_DIR/ (설치 전 설정 백업)"
    run npx --yes claude-mem@latest install --ide claude-code --provider claude
    record "npx --yes claude-mem@latest install --ide claude-code --provider claude"
    if [ -f "$PLUGINS_JSON" ] && grep -q 'claude-mem' "$PLUGINS_JSON"; then
      HAVE_CLAUDE_MEM=1; ok "claude-mem 플러그인 등록 확인"
      created "$HOME/.claude/plugins/marketplaces/thedotmack/, $HOME/.claude-mem/ (claude-mem 본체·데이터)"
    else
      fail "claude-mem 플러그인 등록 확인 실패 — 위 설치 로그를 확인하세요."; exit 1
    fi
  fi
fi

# ---------- 3. 상시 가동: 로그인 시 자동 시작 (LaunchAgent) ----------
PATH_FOR_AGENTS="$(dirname "$(command -v node)")${BREW_PREFIX:+:$BREW_PREFIX/bin}:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"

# $1 label, $2 포트(없으면 빈 값), $3 KeepAlive(true/false), $4.. 실행 인자
install_agent() {
  local label="$1" port="$2" keep="$3"; shift 3
  local plist="$AGENT_DIR/$label.plist" args="" a
  for a in "$@"; do args="$args        <string>$a</string>"$'\n'; done
  if [ -f "$plist" ]; then
    ok "$label: 기존 plist 유지 (덮어쓰지 않음)"
  else
    mkdir -p "$AGENT_DIR"
    cat > "$plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key><string>$label</string>
    <key>ProgramArguments</key>
    <array>
$args    </array>
    <key>EnvironmentVariables</key>
    <dict>
        <key>PATH</key><string>$PATH_FOR_AGENTS</string>
        <key>OMNIROUTE_SERVER_HOST</key><string>127.0.0.1</string>
    </dict>
    <key>RunAtLoad</key><true/>
    <key>KeepAlive</key><$keep/>
    <key>StandardOutPath</key><string>$LOG_DIR/$label.log</string>
    <key>StandardErrorPath</key><string>$LOG_DIR/$label.log</string>
</dict>
</plist>
EOF
    ok "$label: $plist 생성"
    created "$plist (로그인 시 자동 시작)"
  fi
  if launchctl print "gui/$(id -u)/$label" >/dev/null 2>&1; then
    ok "$label: 이미 launchd에 등록되어 실행 중"
  elif [ -n "$port" ] && port_up "$port"; then
    warn "$label: 포트 $port 가 이미 사용 중이라 지금은 등록하지 않음 (수동 실행 중인 것을 끄거나 재로그인하면 적용)"
  else
    run launchctl bootstrap "gui/$(id -u)" "$plist" && record "launchctl bootstrap gui/$(id -u) $plist"
  fi
}

if [ "$CHECK_ONLY" = 0 ] && [ "$AUTOSTART" = 1 ]; then
  step "3. 자동 시작 등록 (Mac mini 상시 가동용)"
  # 두 서버 모두 127.0.0.1에만 열어 외부 네트워크에서 직접 접근할 수 없게 한다.
  install_agent com.claude-tools.omniroute "$OMNIROUTE_PORT" true "$(command -v omniroute)" serve
  install_agent com.claude-tools.headroom-proxy "$HEADROOM_PORT" true "$HEADROOM_VENV/bin/headroom" proxy --host 127.0.0.1 --port "$HEADROOM_PORT"
  # claude-mem 워커는 스스로 데몬이 되므로 로그인 때 한 번만 깨운다.
  install_agent com.claude-tools.claude-mem-worker "" false "$(command -v npx)" --yes claude-mem@latest start

  SLEEP_VAL="$(pmset -g 2>/dev/null | awk '$1=="sleep"{print $2; exit}')"
  if [ "$SLEEP_VAL" = "0" ]; then
    ok "시스템 잠자기: 꺼짐 (상시 가동 OK)"
  else
    warn "시스템 잠자기: ${SLEEP_VAL:-확인 불가}분 — 잠들면 원격 접속과 서버가 끊깁니다."
    info "다음 조치(관리자 암호 필요): sudo pmset -a sleep 0 disksleep 0 womp 1"
  fi
fi

# ---------- 4. 연결 검증 ----------
step "4. 연결 검증"
RESULT_OMNI_VER=FAIL; RESULT_MODELS=FAIL; RESULT_HEADROOM=FAIL; RESULT_MEM=FAIL
FIX=""

record "omniroute --version"
if omniroute --version >/dev/null 2>&1; then RESULT_OMNI_VER=PASS; ok "omniroute --version: $(omniroute --version | tail -1)"; else fail "omniroute --version 실패"; fi

port_up "$OMNIROUTE_PORT" || info "OmniRoute 서버 응답을 기다립니다 (최대 60초)…"
wait_port "$OMNIROUTE_PORT" 60 >/dev/null
record "curl http://localhost:$OMNIROUTE_PORT/v1/models"
BODY="$(mktemp)"
if [ -n "${OMNIROUTE_API_KEY:-}" ]; then
  CODE=$(curl -s -m 10 -o "$BODY" -w '%{http_code}' -H "Authorization: Bearer $OMNIROUTE_API_KEY" "http://localhost:$OMNIROUTE_PORT/v1/models")
else
  CODE=$(curl -s -m 10 -o "$BODY" -w '%{http_code}' "http://localhost:$OMNIROUTE_PORT/v1/models")
fi
COUNT=$("$PY" -c 'import json,sys
try: print(len(json.load(open(sys.argv[1])).get("data") or []))
except Exception: print(0)' "$BODY" 2>/dev/null)
rm -f "$BODY"
if [ "$CODE" = 200 ] && [ "$COUNT" -gt 0 ]; then
  RESULT_MODELS=PASS; ok "/v1/models: HTTP 200, 모델 ${COUNT}개"
elif [ "$CODE" = 401 ]; then
  fail "/v1/models: HTTP 401 (인증 필요)"
  FIX="${FIX}  - OmniRoute 401: 대시보드 http://localhost:$OMNIROUTE_PORT 에서 AI 공급자 연결 + OmniRoute API 키 발급 후,"$'\n'"    키를 화면에 찍지 말고 환경변수로 넣어 재검증: read -rs OMNIROUTE_API_KEY && export OMNIROUTE_API_KEY && bash $0 --check"$'\n'
elif [ "$CODE" = 200 ]; then
  fail "/v1/models: HTTP 200 이지만 모델 0개"
  FIX="${FIX}  - OmniRoute 모델 0개: 대시보드에서 AI 공급자(키 또는 OAuth)를 하나 이상 연결하세요."$'\n'
else
  fail "/v1/models: 응답 없음 (HTTP ${CODE:-000})"
  FIX="${FIX}  - OmniRoute 서버 미응답: launchctl kickstart -k gui/$(id -u)/com.claude-tools.omniroute"$'\n'"    (자동 시작 미등록이면 OMNIROUTE_SERVER_HOST=127.0.0.1 omniroute serve) / 로그: $LOG_DIR/com.claude-tools.omniroute.log"$'\n'
fi

HR="$HEADROOM_VENV/bin/headroom"; command -v headroom >/dev/null 2>&1 && HR="$(command -v headroom)"
wait_port "$HEADROOM_PORT" 60 >/dev/null
record "headroom doctor"
HR_OUT="$("$HR" doctor 2>&1)"; HR_RC=$?
printf '%s\n' "$HR_OUT" | sed 's/^/    /'
if [ "$HR_RC" = 0 ]; then
  RESULT_HEADROOM=PASS; ok "headroom doctor: 정상 종료"
elif printf '%s' "$HR_OUT" | grep -Eq '(^|[^0-9])0 failure'; then
  RESULT_HEADROOM=WARN; warn "headroom doctor: 실패 0건이지만 경고로 종료코드 $HR_RC"
  FIX="${FIX}  - Headroom 경고: 클로드 코드를 프록시에 연결하려면 README의 'Headroom 연결' 절을 보고 결정하세요."$'\n'
else
  fail "headroom doctor: 종료코드 $HR_RC"
  FIX="${FIX}  - Headroom 실패: 위 표의 ✗ 항목 조치 문구를 따르세요. 로그: $LOG_DIR/com.claude-tools.headroom-proxy.log"$'\n'
fi

wait_port "$CLAUDE_MEM_PORT" 30 >/dev/null
record "ls ~/.claude/plugins && npx --yes claude-mem@latest doctor"
ls "$HOME/.claude/plugins" 2>/dev/null | sed 's/^/    /'
if [ -f "$PLUGINS_JSON" ] && grep -q 'claude-mem' "$PLUGINS_JSON"; then
  CM_OUT="$(npx --yes claude-mem@latest doctor 2>&1 | grep -v 'npm notice')"
  printf '%s\n' "$CM_OUT" | sed 's/^/    /'
  if printf '%s' "$CM_OUT" | grep -q 'All required checks passed'; then
    RESULT_MEM=PASS; ok "claude-mem: 플러그인 등록 + doctor 통과"
  else
    RESULT_MEM=WARN; warn "claude-mem: 플러그인은 있으나 doctor 미통과"
    if printf '%s' "$CM_OUT" | grep -q 'claude-mem repair'; then
      FIX="${FIX}  - claude-mem 런타임 손상: npx --yes claude-mem@latest repair 후 재검증"$'\n'
    else
      FIX="${FIX}  - claude-mem 워커: npx --yes claude-mem@latest start 후 재검증"$'\n'
    fi
  fi
else
  fail "claude-mem: ~/.claude/plugins 에 없음"
fi

# ---------- 요약 ----------
step "요약"
printf '  %-34s %s\n' "omniroute --version" "$RESULT_OMNI_VER" \
                     "curl /v1/models (모델 목록)" "$RESULT_MODELS" \
                     "headroom doctor" "$RESULT_HEADROOM" \
                     "claude-mem 플러그인" "$RESULT_MEM"
printf '\n  확인된 버전: Node %s / Python %s\n' "$NODE_VER" "$PY_VER"
printf '\n  실행한 명령어:\n%s' "$COMMANDS_RUN"
[ -n "$CREATED" ] && printf '\n  새로 생긴 폴더·파일:\n%s' "$CREATED"
printf '\n  클로드 코드 안에서 직접 할 것:\n'
printf '  - /plugin install claude-code-setup@claude-plugins-official\n'
printf '  - Task Observer 스킬 폴더를 ~/.claude/skills/task-observer/ 에 배치 (SKILL.md 포함)\n'

if [ "$RESULT_OMNI_VER" = PASS ] && [ "$RESULT_MODELS" = PASS ] && [ "$RESULT_HEADROOM" = PASS ] && [ "$RESULT_MEM" = PASS ]; then
  printf '\n  %s완료: 검증 기준을 모두 통과했습니다.%s\n' "$G" "$N"
  exit 0
fi
printf '\n  %s완료 아님 — 남은 조치:%s\n%s' "$R" "$N" "$FIX"
printf '\n  전체 로그: %s\n' "$LOG_FILE"
exit 1
