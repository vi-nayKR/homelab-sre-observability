# Runbook: Stale or Unverified Backup

## User risk

The newest checksum-verified backup is older than 26 hours or no valid checksum pair exists. This is a recovery-capability incident even if the application still serves traffic.

## Triage

1. Confirm which `backup_type` is missing/stale.
2. Check the durable scheduler's last run and exit status.
3. Check free bytes and inodes on source and destination filesystems.
4. Check network reachability to the database/storage source.
5. Inspect the backup log for the first failure.
6. Verify that a `.sha256` file refers to the expected archive; never mark a corrupt archive successful.

## Mitigation

- Fix the causal scheduler, capacity, permission or connectivity issue.
- Run one reviewed backup manually only after confirming it will not overload or lock the source.
- Validate PostgreSQL custom archives with `pg_restore --list` and verify the checksum.
- Copy the result to the off-host destination.
- Do not delete the previous known-good backup to make room unless retention and recovery impact are understood.

## Recovery verification

- Textfile metric reports `medha_backup_verified{backup_type="..."} 1`.
- Last-success timestamp is current.
- Archive list/checksum succeeds.
- An isolated restore drill is scheduled or completed; archive validation alone is not restore proof.
- Alert resolves after two scrape intervals.

