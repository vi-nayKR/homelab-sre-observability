#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
runtime_dir="$repo_root/evidence/runtime"
pid_file="$runtime_dir/error-load.pid"
log_file="$runtime_dir/error-load.log"
target="${ERROR_LOAD_TARGET:-http://127.0.0.1:8080/work?fail=true}"

run_load() {
  trap 'exit 0' INT TERM
  while true; do
    status="$(curl --silent --output /dev/null --write-out '%{http_code}' \
      --max-time 3 "$target" || true)"
    printf '%s target=%s status=%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$target" "$status"
    sleep 0.2
  done
}

start_load() {
  mkdir -p "$runtime_dir"
  if [[ -f "$pid_file" ]]; then
    existing_pid="$(<"$pid_file")"
    if [[ "$existing_pid" =~ ^[0-9]+$ ]] && kill -0 "$existing_pid" 2>/dev/null; then
      echo "error load is already running with PID $existing_pid" >&2
      exit 1
    fi
  fi
  "$0" run >>"$log_file" 2>&1 &
  load_pid=$!
  printf '%s\n' "$load_pid" >"$pid_file"
  echo "started error load with PID $load_pid; stop it with: $0 stop"
}

stop_load() {
  [[ -f "$pid_file" ]] || {
    echo "no error-load PID file exists" >&2
    exit 1
  }
  load_pid="$(<"$pid_file")"
  [[ "$load_pid" =~ ^[0-9]+$ ]] || {
    echo "invalid PID file" >&2
    exit 1
  }
  if kill -0 "$load_pid" 2>/dev/null; then
    process_command="$(ps -p "$load_pid" -o command= 2>/dev/null || true)"
    [[ "$process_command" == *"error-load.sh run"* ]] || {
      echo "refusing to signal PID $load_pid because it is not the expected load process" >&2
      exit 1
    }
    kill "$load_pid"
  fi
  rm -f "$pid_file"
  echo "stopped error load"
}

case "${1:-}" in
  start) start_load ;;
  stop) stop_load ;;
  run) run_load ;;
  *) echo "usage: $0 <start|stop>" >&2; exit 64 ;;
esac
