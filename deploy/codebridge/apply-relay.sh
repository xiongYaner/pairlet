#!/usr/bin/env bash
# Only swaps the personal relay program. Runs inside a server-owned transient unit.
set -euo pipefail
umask 077
STAGE="${1:?staging directory required}"
ROOT="${2:-/opt/cc-pocket-relay}"
SERVICE="${3:-cc-pocket-relay}"
HEALTH="${4:-http://127.0.0.1:9000/healthz}"
DATABASE="${5:-/var/lib/cc-pocket-relay/relay.db}"
[[ "$STAGE" = /* && "$ROOT" = /* && "$ROOT" != / && "$STAGE" != "$ROOT" ]] || exit 64
[[ -d "$ROOT/bin" && -d "$ROOT/lib" && -f "$DATABASE" ]] || exit 65
[[ ! -e "$STAGE/result" ]] || { echo 'staging already has a deployment result; inspect it before choosing a fresh stage'; exit 65; }
exec 9>"$ROOT/.codebridge-deploy.lock"
flock -n 9 || { echo 'another deployment is active'; exit 75; }
BACKUP="$ROOT/.deploy-backups/$(date -u +%Y%m%dT%H%M%SZ)-$$"
INCOMING="$ROOT/.incoming-$(basename "$STAGE")"
switched=0
healthy() {
    local attempt
    for attempt in 1 2 3 4 5 6 7 8; do
        if systemctl is-active --quiet "$SERVICE" && curl -fsS --max-time 3 "$HEALTH" >/dev/null; then return 0; fi
        sleep 1
    done
    return 1
}
finish() {
    local status=$? result=failed restored=1
    trap - EXIT HUP INT TERM
    if [[ "$status" = 0 ]]; then
        result=ok
    elif [[ "$switched" = 1 ]]; then
        set +e
        systemctl stop "$SERVICE" || restored=0
        if [[ "$restored" = 1 ]]; then
            [[ ! -e "$ROOT/bin" ]] || mv "$ROOT/bin" "$STAGE/failed-bin" || restored=0
            [[ ! -e "$ROOT/lib" ]] || mv "$ROOT/lib" "$STAGE/failed-lib" || restored=0
            cp -a "$BACKUP/bin" "$BACKUP/lib" "$ROOT/" || restored=0
        fi
        if [[ "$restored" = 1 ]] && systemctl reset-failed "$SERVICE" && systemctl start "$SERVICE" && healthy; then
            result=rolled_back
        else
            result=rollback_failed
        fi
    fi
    printf '%s\n' "$result" >"$STAGE/result.tmp"
    mv "$STAGE/result.tmp" "$STAGE/result"
    printf 'relay deployment result: %s\nbackup: %s\n' "$result" "$BACKUP"
    exit "$status"
}
trap finish EXIT
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM

# Validate and copy while the existing service still serves users.
(cd "$STAGE" && sha256sum -c dist.sha256)
test -f "$STAGE/bin/cc-pocket-relay"
test -f "$STAGE/release.json"
[[ -z "$(find "$STAGE/bin" "$STAGE/lib" -type l -print -quit)" ]] || { echo 'symlink payload refused'; exit 65; }
systemctl is-active --quiet "$SERVICE"
mkdir -p "$BACKUP" "$INCOMING"
cp -a "$ROOT/bin" "$ROOT/lib" "$BACKUP/"
systemctl cat "$SERVICE" >"$BACKUP/service.txt"
cp -a "$STAGE/bin" "$STAGE/lib" "$INCOMING/"
chown -R root:root "$INCOMING/bin" "$INCOMING/lib"
chmod +x "$INCOMING/bin/cc-pocket-relay"
# sqlite3.backup is an online, consistent backup; it does not overwrite the live DB.
python3 - "$DATABASE" "$BACKUP/relay.db" <<'PY'
import os, sqlite3, sys
source, target = sys.argv[1:]
with sqlite3.connect('file:' + source + '?mode=ro', uri=True) as live, sqlite3.connect(target) as backup:
    live.backup(backup)
    assert backup.execute('PRAGMA integrity_check').fetchone()[0] == 'ok'
os.chmod(target, 0o600)
PY
cp -a "$STAGE/release.json" "$BACKUP/new-release.json"
printf '%s\n' "$BACKUP" >"$STAGE/backup-path"
# Keep old directories and a copied backup. Rollback restores only program files, never the DB.
switched=1
systemctl stop "$SERVICE"
mv "$ROOT/bin" "$BACKUP/retired-bin"
mv "$ROOT/lib" "$BACKUP/retired-lib"
mv "$INCOMING/bin" "$ROOT/bin"
mv "$INCOMING/lib" "$ROOT/lib"
systemctl reset-failed "$SERVICE"
systemctl start "$SERVICE"
healthy
cp -a "$STAGE/release.json" "$ROOT/.deployed-release.json.next"
mv "$ROOT/.deployed-release.json.next" "$ROOT/deployed-release.json"
echo 'relay active; nginx, credentials and database paths unchanged'
