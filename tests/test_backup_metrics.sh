#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
test_root="$(mktemp -d)"
backup_dir="$test_root/backups"
textfile_dir="$test_root/textfile"
mkdir -p "$backup_dir" "$textfile_dir"
trap 'rm -rf "$test_root"' EXIT

write_checksum() {
  local file="$1" directory base
  directory="$(dirname "$file")"
  base="$(basename "$file")"
  if command -v sha256sum >/dev/null 2>&1; then
    (cd "$directory" && sha256sum "$base" >"$base.sha256")
  else
    (cd "$directory" && shasum -a 256 "$base" >"$base.sha256")
  fi
}

printf 'dev backup fixture\n' >"$backup_dir/db_dev_20260824_000000.dump"
printf 'prod backup fixture\n' >"$backup_dir/db_prod_20260824_000000.dump"
printf 'object backup fixture\n' >"$backup_dir/seaweedfs_prod_20260824_000000.tar.gz"
write_checksum "$backup_dir/db_dev_20260824_000000.dump"
write_checksum "$backup_dir/db_prod_20260824_000000.dump"
write_checksum "$backup_dir/seaweedfs_prod_20260824_000000.tar.gz"

"$repo_root/scripts/backup-metrics.sh" "$backup_dir" "$textfile_dir"
metrics="$textfile_dir/medha-backup.prom"
grep -q 'medha_backup_verified{backup_type="postgres_dev"} 1' "$metrics"
grep -q 'medha_backup_verified{backup_type="postgres_prod"} 1' "$metrics"
grep -q 'medha_backup_verified{backup_type="seaweedfs_prod"} 1' "$metrics"
grep -q 'medha_backup_last_success_timestamp_seconds{backup_type="postgres_prod"}' "$metrics"

printf 'corruption\n' >>"$backup_dir/db_prod_20260824_000000.dump"
"$repo_root/scripts/backup-metrics.sh" "$backup_dir" "$textfile_dir"
grep -q 'medha_backup_verified{backup_type="postgres_prod"} 0' "$metrics"
if grep -q 'medha_backup_last_success_timestamp_seconds{backup_type="postgres_prod"}' "$metrics"; then
  echo "corrupt backup incorrectly produced a success timestamp" >&2
  exit 1
fi

echo "backup metrics tests passed"
