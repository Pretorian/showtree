#!/usr/bin/env bash
#
# vtree - print a visual tree of a directory (defaults to the current directory)
#
# Install:
#   chmod +x vtree && mv vtree /usr/local/bin/     (or ~/bin, ~/.local/bin, etc.)
#
# Works with bash 3.2+ (macOS default) and Linux. No dependencies beyond bash.

set -u

VERSION="1.0.0"

# ---- defaults ---------------------------------------------------------------
max_depth=0       # 0 = unlimited
show_hidden=0
dirs_only=0
use_color=1
ascii=0
ignore_pats=()
ndirs=0
nfiles=0

usage() {
  cat <<EOF
Usage: vtree [options] [directory]

Print a visual tree of a directory. Defaults to the current directory.

Options:
  -L <n>        Descend at most <n> levels deep
  -a            Include hidden files (dotfiles)
  -d            List directories only
  -I <pattern>  Ignore entries matching a glob; separate several with '|'
                  e.g. -I 'node_modules|.git|*.pyc'
  -A            Use plain ASCII lines instead of Unicode box characters
  -n            No color
  -h            Show this help
  -v            Show version

Examples:
  vtree                    # tree of current directory
  vtree -L 2               # only two levels deep
  vtree -a -I '.git'       # show dotfiles but skip .git
  vtree -d ~/projects      # directories only, in ~/projects
EOF
}

# ---- parse options ----------------------------------------------------------
while getopts ":L:adI:Anhv" opt; do
  case "$opt" in
    L)
      case "$OPTARG" in
        ''|*[!0-9]*) echo "vtree: -L needs a positive number" >&2; exit 2 ;;
      esac
      [ "$OPTARG" -gt 0 ] || { echo "vtree: -L needs a positive number" >&2; exit 2; }
      max_depth=$OPTARG ;;
    a) show_hidden=1 ;;
    d) dirs_only=1 ;;
    I) IFS='|' read -r -a ignore_pats <<< "$OPTARG" ;;
    A) ascii=1 ;;
    n) use_color=0 ;;
    h) usage; exit 0 ;;
    v) echo "vtree $VERSION"; exit 0 ;;
    :) echo "vtree: option -$OPTARG requires an argument" >&2; exit 2 ;;
    \?) echo "vtree: unknown option -$OPTARG (try -h)" >&2; exit 2 ;;
  esac
done
shift $((OPTIND - 1))

root="${1:-.}"
if [ ! -d "$root" ]; then
  echo "vtree: '$root' is not a directory" >&2
  exit 1
fi

# ---- appearance -------------------------------------------------------------
# Turn off color when output is piped or NO_COLOR is set (https://no-color.org)
if [ ! -t 1 ] || [ -n "${NO_COLOR:-}" ]; then
  use_color=0
fi

if [ "$use_color" -eq 1 ]; then
  C_DIR=$'\033[1;34m'    # bold blue
  C_EXE=$'\033[1;32m'    # bold green
  C_LNK=$'\033[1;36m'    # bold cyan
  C_ERR=$'\033[31m'      # red
  C_DIM=$'\033[2m'       # dim
  C_OFF=$'\033[0m'
else
  C_DIR=''; C_EXE=''; C_LNK=''; C_ERR=''; C_DIM=''; C_OFF=''
fi

if [ "$ascii" -eq 1 ]; then
  T_MID='|-- '; T_END='`-- '; T_BAR='|   '
else
  T_MID='├── '; T_END='└── '; T_BAR='│   '
fi
T_GAP='    '

shopt -s nullglob
[ "$show_hidden" -eq 1 ] && shopt -s dotglob

is_ignored() {
  local name=$1 p
  for p in ${ignore_pats[@]+"${ignore_pats[@]}"}; do
    # shellcheck disable=SC2254
    case "$name" in $p) return 0 ;; esac
  done
  return 1
}

# ---- recursive walk ---------------------------------------------------------
walk() {
  local dir=$1 prefix=$2 depth=$3
  local e name dirs=() files=() entries=()

  # Collect entries: directories first, then files, each sorted by the glob
  for e in "$dir"/*; do
    name=${e##*/}
    is_ignored "$name" && continue
    if [ -d "$e" ] && [ ! -L "$e" ]; then
      dirs+=("$e")
    elif [ "$dirs_only" -eq 0 ]; then
      files+=("$e")
    fi
  done
  entries=(${dirs[@]+"${dirs[@]}"} ${files[@]+"${files[@]}"})

  local count=${#entries[@]} i=0 branch next
  for e in ${entries[@]+"${entries[@]}"}; do
    i=$((i + 1))
    if [ "$i" -eq "$count" ]; then
      branch=$T_END; next=$T_GAP
    else
      branch=$T_MID; next=$T_BAR
    fi
    name=${e##*/}

    if [ -L "$e" ]; then
      printf '%s%s%s%s%s -> %s\n' "$prefix" "$branch" "$C_LNK" "$name" "$C_OFF" "$(readlink "$e")"
      nfiles=$((nfiles + 1))
    elif [ -d "$e" ]; then
      printf '%s%s%s%s%s\n' "$prefix" "$branch" "$C_DIR" "$name" "$C_OFF"
      ndirs=$((ndirs + 1))
      if [ "$max_depth" -eq 0 ] || [ "$depth" -lt "$max_depth" ]; then
        if [ -r "$e" ] && [ -x "$e" ]; then
          walk "$e" "$prefix$next" $((depth + 1))
        else
          printf '%s%s%s[permission denied]%s\n' "$prefix$next" "$T_END" "$C_ERR" "$C_OFF"
        fi
      fi
    elif [ -x "$e" ]; then
      printf '%s%s%s%s%s\n' "$prefix" "$branch" "$C_EXE" "$name" "$C_OFF"
      nfiles=$((nfiles + 1))
    else
      printf '%s%s%s\n' "$prefix" "$branch" "$name"
      nfiles=$((nfiles + 1))
    fi
  done
}

# ---- run --------------------------------------------------------------------
abs_root=$(cd "$root" && pwd)
printf '%s%s%s\n' "$C_DIR" "$abs_root" "$C_OFF"
walk "$root" "" 1

d_word="directories"; [ "$ndirs" -eq 1 ] && d_word="directory"
f_word="files";       [ "$nfiles" -eq 1 ] && f_word="file"
if [ "$dirs_only" -eq 1 ]; then
  printf '\n%s%d %s%s\n' "$C_DIM" "$ndirs" "$d_word" "$C_OFF"
else
  printf '\n%s%d %s, %d %s%s\n' "$C_DIM" "$ndirs" "$d_word" "$nfiles" "$f_word" "$C_OFF"
fi