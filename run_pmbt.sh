#!/usr/bin/env bash
set -euo pipefail

# sanity check: wt.exe new-tab --title "test" -- bash -lc "echo SHELL=$SHELL && echo HOME=$HOME && exec bash || exec bash"
# to prrevent MSYS/Git Bash from rewriting Windows-ish args (helps with wt/cmd)
export MSYS_NO_PATHCONV=1
export MSYS2_ARG_CONV_EXCL="*"

# ui flag only has windows terminal for now, but could add any desired window eg mintty, but need to write its respective spawning function
usage() {
cat <<'EOF'
Usage:
    run_pmbt.sh -n N [--mode windows|bg] [--ui wt] [--env-file .env|PATH] [-k] \
    [-s script] [-p "python launcher"] [-t title] [-- extra...]

Modes:
    windows -> Spawn N visible terminals (tabs/windows) and run each worker there
    bg ------> Run N workers concurrently in background, write logs, no terminals

UI backends (mode=windows):
    wt ------> Windows Terminal tabs

--env-file PATH:
    Load KEY=VALUE pairs from PATH (default: .env). Safe parser: does not execute code.
    Precedence: defaults < env-file < environment < CLI flags

-k / --keep-open:
    In windows mode, keep terminal open after the command, for debugging

-s
    Path to script that is going to be executed in every terminal

-v
    Path to venv if the script needs it

-p
    Launcher

-t
    Title of the terminals that are being spawned(would be appended with iteration numbers eg Title-1, Title-2, ...)

# TODO: Parse from config json?
-- extra flags:
    The flags and values of the script you are running. Onus is on you to type everything correctly (so the flags/values are valid in the context of the script)

    NOTE: If there are flags in the script that needs to match the iterator count, wrap it in inverted commas. eg '--html-report-${i}.html' instead of --html-report-${i}.
    html. Mainly for generating non conflicting reports

Examples:
    # 4 visible Windows Terminal tabs, keep open:
    ./run_pmbt.sh -n 2 --mode windows -k -p "python" -s "C:/Users/Example/Poor-Mans-Bootleg-tmux/tester.py" --clone_name="garry" --clone_count=5 --greet

    # 4 concurrent background workers + logs:
    ./run_pmbt.sh -n 2 --mode bg -k -p "python" -s "C:/Users/Example/Poor-Mans-Bootleg-tmux/tester.py" --clone_name="garry" --clone_count=5 --greet

    # Running with flags involved in the script itself:
    ./run_pmbt.sh -n 4 --mode windows --ui wt -k --valid_int=2 --valid_bool=False --valid_input_file="C:/Users/Example/Poor-Mans-Bootleg-tmux/Input"
EOF
}

ENV_FILE="${ENV_FILE:-.env}"

load_env_file() {
  local f="$1" line k v
  [[ -f "$f" ]] || return 0

  while IFS= read -r line || [[ -n "$line" ]]; do
    # to handle CRLF
    line="${line%$'\r'}"
    [[ "$line" =~ ^[[:space:]]*$ ]] && continue
    [[ "$line" =~ ^[[:space:]]*# ]] && continue

    # allow: export KEY=VALUE
    if [[ "$line" =~ ^[[:space:]]*export[[:space:]] ]]; then
      line="${line#export }"
      line="${line#"${line%%[![:space:]]*}"}"
    fi

    [[ "$line" =~ ^[A-Za-z_][A-Za-z0-9_]*= ]] || continue

    k="${line%%=*}"
    v="${line#*=}"

    # trim whitespace around key & value
    k="${k%%[[:space:]]*}"
    v="${v#"${v%%[![:space:]]*}"}"
    v="${v%"${v##*[![:space:]]}"}"

    # strip surrounding matching quotes without eval
    if [[ "$v" == \"*\" && "$v" == *\" ]]; then
      v="${v:1:${#v}-2}"
    elif [[ "$v" == \'*\' && "$v" == *\' ]]; then
      v="${v:1:${#v}-2}"
    fi

    # do not override already-set environment variables
    if [[ -z "${!k+x}" ]]; then
      export "$k=$v"
    fi
  done < "$f"
}

# pre scant argv for --env-file so we can load it before main arg parsing
ARGS=("$@")
for ((j=0; j<${#ARGS[@]}; j++)); do
  if [[ "${ARGS[j]}" == "--env-file" ]]; then
    ENV_FILE="${ARGS[j+1]:-}"
    [[ -n "$ENV_FILE" ]] || { echo "Error: --env-file requires a path" >&2; exit 1; }
    break
  fi
done

load_env_file "$ENV_FILE"

# defaults for flags that aare only applied if not set by .env
# 
: "${NUM:=}"
: "${MODE:=windows}"
: "${UI:=wt}"
: "${KEEP_OPEN:=0}"
: "${SCRIPT_PATH:=}"
: "${VENV_PATH:=./venv/}"
: "${PYTHON_STR:=pytest --color=yes}" # eg 'py -3 -m pytest'
: "${TITLE_PREFIX:=Spawned_Window}"
: "${LOG_DIR:=./logs}"
if [[ -z "${CWD+x}" ]]; then
  CWD="$(pwd)"
fi

EXTRA=()

# arg parsing
while [[ $# -gt 0 ]]; do
  case "$1" in
    -n|--num) NUM="$2"; shift 2;;
    --mode) MODE="$2"; shift 2;;
    --ui) UI="$2"; shift 2;;
    --env-file) shift 2;;
    -k|--keep-open) KEEP_OPEN=1; shift;;
    -s|--script) SCRIPT_PATH="$2"; shift 2;;
    -v|--venv-path) VENV_PATH="$2"; shift 2;;
    -p|--python) PYTHON_STR="$2"; shift 2;;
    -t|--title-prefix) TITLE_PREFIX="$2"; shift 2;;
    --log-dir) LOG_DIR="$2"; shift 2;;
    --cwd) CWD="$2"; shift 2;;
    -h|--help) usage; exit 0;;
    --) shift; EXTRA+=("$@"); break;;
    *) EXTRA+=("$1"); shift;;
  esac
done

# flag validation
[[ -n "$NUM" ]] || { echo "Error: --num is required (or set NUM in .env)" >&2; usage; exit 1; }
[[ "$NUM" =~ ^[1-9][0-9]*$ ]] || { echo "Error: --num must be a positive integer" >&2; exit 1; }
[[ "$MODE" == "windows" || "$MODE" == "bg" ]] || { echo "Error: --mode windows|bg" >&2; exit 1; }
[[ "$UI" == "wt" ]] || { echo "Error: --ui wt" >&2; exit 1; }

mkdir -p "$LOG_DIR"
STARTDIR_WIN="$(cygpath -w "$CWD")"
BASH_WIN="$(cygpath -w "$(command -v bash)")"
# some of the scripts have emojis... need appropriate parsing for that otherwise script throws unicode encoding error
UTF8_SETUP="export PYTHONIOENCODING=utf-8"

# tokenising python launcher ie so it supports: -p "py -3 -m pytest"
read -r -a PYTHON_CMD <<< "$PYTHON_STR"
# venv_act="source $(printf '%q' "${VENV_PATH%/}/Scripts/activate")"
# USE_VENV_PY=0 to disable
: "${USE_VENV_PY:=1}"

VENV_PY_POSIX="${VENV_PATH%/}/Scripts/python.exe"

if (( USE_VENV_PY )) && [[ -x "$VENV_PY_POSIX" ]]; then
  case "${PYTHON_CMD[0]}" in
    # common launchers - replace with venv python
    python|python3|py) PYTHON_CMD=("$VENV_PY_POSIX" "${PYTHON_CMD[@]:1}");;
    # if someone uses -p "pytest", make it venv python -m pytest
    pytest) PYTHON_CMD=("$VENV_PY_POSIX" -m pytest "${PYTHON_CMD[@]:1}");;
  esac
fi

# quote argv for embedding into: bash -c "<string>"
bash_join() {
  local out=""
  for a in "$@"; do
    out+="${out:+ }$(printf '%q' "$a")"
  done
  printf '%s' "$out"
}

spawn_wt_tab() {
  local title="$1"; shift
  local cmd_str; cmd_str="$(bash_join "$@")"
  local log="$LOG_DIR/$title.log"

  local keep=""
  if (( KEEP_OPEN )); then
    keep="&& echo && echo Exit code: \$rc && cd $(printf '%q' "$CWD") && exec bash || cd $(printf '%q' "$CWD") && exec bash"
  fi

  echo "DEBUG: Start Dir Win: $STARTDIR_WIN"
  echo "DEBUG: Bash Win: $BASH_WIN"
  echo "DEBUG: Cmd Str: $cmd_str"

  # echo $VIRTUAL_ENV in the entire -c argument in the parent shell has to be wrapped in double quotes first, then single in the actual echo statement since the argument is in double quotes which expands all $ params, and not having double quotes will expand the VIRTUAL_ENV first before wt.exe even runs, giving unbound local error. This makes it such that the param is expanded in the child shell
  local terminal_debug="echo -n 'pwd: ' && pwd && echo 'DEBUG: Venv Check: $VENV_PY_POSIX'"

  # coudl append '2>&1 | tee -a $(printf '%q' "$log") && rc=\$?${keep}' to add logs and redirect standard error, but introduces io contention
  # & suffix brackgrounds the wt.exe launcher process so we can get and track the pid for debug and pkill like in run_bg
  wt.exe -w 0 new-tab --title "$title" --startingDirectory "$STARTDIR_WIN" -- \
    "$BASH_WIN" -c \
    "$terminal_debug && $UTF8_SETUP && $cmd_str $keep" &
}

run_bg() {
  local title="$1"; shift
  ( cd "$CWD" && $UTF8_SETUP && "$@" >"$LOG_DIR/$title.log" 2>&1 ) &
  echo "$!" > "$LOG_DIR/$title.pid"
}

pids=()

for (( i=1; i<=NUM; i++ )); do
  title="${TITLE_PREFIX}-${i}"

  expanded_extra=()
  for arg in "${EXTRA[@]}"; do
    expanded_extra+=("${arg//\$\{i\}/${i}}")
  done

  # per worker argv with no embedded quotes
  worker_cmd=(
    "${PYTHON_CMD[@]}"
    "$SCRIPT_PATH"
    "${expanded_extra[@]}"
  )

  # '#' is interpreted as '/' for better readability when there are '/' within the regex
  # sed -r 's##'

  echo -e "Launching ($MODE/$UI): $title -> ${worker_cmd[*]} \n"

  if [[ "$MODE" == "windows" ]]; then
    if [[ "$UI" == "wt" ]]; then
      spawn_wt_tab "$title" "${worker_cmd[@]}"
    fi
  else
    run_bg "$title" "${worker_cmd[@]}"
  fi

  sleep 1
done

if [[ "$MODE" == "bg" ]]; then
  echo
  echo "Background workers started. Logs in: $LOG_DIR"
  echo "To monitor file: tail -f $LOG_DIR/${TITLE_PREFIX}-{idx}.log"
  wait
fi
