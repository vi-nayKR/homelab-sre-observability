#!/usr/bin/env bash
set -euo pipefail
umask 077

backup_dir="${1:-}"
textfile_dir="${2:-}"

[[ -d "$backup_dir" ]] || {
  echo "backup directory does not exist: $backup_dir" >&2
  exit 1
}
[[ -d "$textfile_dir" ]] || {
  echo "node-exporter textfile directory does not exist: $textfile_dir" >&2
  exit 1
}

checksum_ok() {
  local file="$1"
  local checksum_file="$file.sha256"
  local directory base checksum_base
  [[ -f "$checksum_file" ]] || return 1
  directory="$(dirname "$file")"
  base="$(basename "$file")"
  checksum_base="$(basename "$checksum_file")"
  if command -v sha256sum >/dev/null 2>&1; then
    (cd "$directory" && sha256sum --check --status "$checksum_base") || return 1
  else
    (cd "$directory" && shasum -a 256 --check "$checksum_base" >/dev/null 2>&1) || return 1
  fi
  [[ -f "$directory/$base" ]]
}

file_mtime() {
  local file="$1"
  if stat -c %Y "$file" >/dev/null 2>&1; then
    stat -c %Y "$file"
  else
    stat -f %m "$file"
  fi
}

file_size() {
  local file="$1"
  if stat -c %s "$file" >/dev/null 2>&1; then
    stat -c %s "$file"
  else
    stat -f %z "$file"
  fi
}

newest_verified() {
  local pattern="$1" candidate
  while IFS= read -r candidate; do
    if checksum_ok "$candidate"; then
      printf '%s\n' "$candidate"
      return 0
    fi
  done < <(find "$backup_dir" -maxdepth 1 -type f -name "$pattern" -print0 \
    | xargs -0 stat -f '%m %N' 2>/dev/null \
    | sort -rn \
    | cut -d' ' -f2-)

  while IFS= read -r candidate; do
    if checksum_ok "$candidate"; then
      printf '%s\n' "$candidate"
      return 0
    fi
  done < <(find "$backup_dir" -maxdepth 1 -type f -name "$pattern" -printf '%T@ %p\n' 2>/dev/null \
    | sort -rn \
    | cut -d' ' -f2-)
  return 1
}

temporary="$(mktemp "$textfile_dir/.medha-backup.prom.XXXXXX")"
trap 'rm -f "$temporary"' EXIT

{
  echo '# HELP medha_backup_verified Whether a checksum-verified backup exists (1 yes, 0 no).'
  echo '# TYPE medha_backup_verified gauge'
  echo '# HELP medha_backup_last_success_timestamp_seconds Unix timestamp of the newest checksum-verified backup.'
  echo '# TYPE medha_backup_last_success_timestamp_seconds gauge'
  echo '# HELP medha_backup_last_success_bytes Size of the newest checksum-verified backup.'
  echo '# TYPE medha_backup_last_success_bytes gauge'

  while IFS='|' read -r backup_type pattern; do
    if latest="$(newest_verified "$pattern")"; then
      printf 'medha_backup_verified{backup_type="%s"} 1\n' "$backup_type"
      printf 'medha_backup_last_success_timestamp_seconds{backup_type="%s"} %s\n' \
        "$backup_type" "$(file_mtime "$latest")"
      printf 'medha_backup_last_success_bytes{backup_type="%s"} %s\n' \
        "$backup_type" "$(file_size "$latest")"
    else
      printf 'medha_backup_verified{backup_type="%s"} 0\n' "$backup_type"
    fi
  done <<'PATTERNS'
postgres_dev|db_dev_*.dump
postgres_prod|db_prod_*.dump
seaweedfs_prod|seaweedfs_prod_*.tar.gz
PATTERNS
} >"$temporary"

chmod 0644 "$temporary"
mv "$temporary" "$textfile_dir/medha-backup.prom"
trap - EXIT
