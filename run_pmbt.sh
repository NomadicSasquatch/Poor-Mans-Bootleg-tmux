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
    run_pmbt.sh -n N [--mode windows|bg] [--ui wt] [-k] \
    [-s script] [-p "python launcher"] [-t title] [-- extra...]

Modes:
    windows -> Spawn N visible terminals (tabs/windows) and run each worker there
    bg ------> Run N workers concurrently in background, write logs, no terminals

UI backends (mode=windows):
    wt ------> Windows Terminal tabs (recommended)

-k / --keep-open:
    In windows mode, keep terminal open after the command, for debugging

-s
    Path to script that is going to be executed in every terminal

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

# defaults for flags
NUM=""
MODE="windows"
UI="wt"
KEEP_OPEN=0
SCRIPT_PATH="C:/Users/Example/Poor-Mans-Bootleg-tmux/tester.py"
# eg 'py -3 -m pytest'
PYTHON_STR='pytest'
# change to just generic title tbh
TITLE_PREFIX="Spawned_Window"
LOG_DIR="./logs"
CWD="$(pwd)"
EXTRA=()

# arg parsing
while [[ $# -gt 0 ]]; do
  case "$1" in
    -n|--num) NUM="$2"; shift 2;;
    --mode) MODE="$2"; shift 2;;
    --ui) UI="$2"; shift 2;;
    -k|--keep-open) KEEP_OPEN=1; shift;;
    -s|--script) SCRIPT_PATH="$2"; shift 2;;
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
[[ -n "$NUM" ]] || { echo "Error: --num is required" >&2; usage; exit 1; }
[[ "$NUM" =~ ^[1-9][0-9]*$ ]] || { echo "Error: --num must be a positive integer" >&2; exit 1; }
[[ "$MODE" == "windows" || "$MODE" == "bg" ]] || { echo "Error: --mode windows|bg" >&2; exit 1; }
[[ "$UI" == "wt" ]] || { echo "Error: --ui wt" >&2; exit 1; }