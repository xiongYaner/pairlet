#!/usr/bin/env bash
# Personal nginx deployment; deliberately independent of the upstream Caddy deployment.
set -euo pipefail
cd "$(dirname "$0")/.."
HOST=""
PREPARE_ONLY=0
DIST=relay/build/install/cc-pocket-relay
OUTPUT=""
usage() {
    echo 'Usage: deploy-codebridge-relay.sh --host SSH_TARGET [--dist DIR] [--output DIR]'
    echo '       deploy-codebridge-relay.sh --prepare-only [--dist DIR] [--output DIR]'
    echo 'Requires a tested installDist. Uses existing nginx/unit/DB/APNs configuration.'
}
while [[ $# -gt 0 ]]; do
    case "$1" in
        --host) HOST="${2:?missing SSH target}"; shift 2 ;;
        --dist) DIST="${2:?missing distribution}"; shift 2 ;;
        --output) OUTPUT="${2:?missing output directory}"; shift 2 ;;
        --prepare-only) PREPARE_ONLY=1; shift ;;
        -h|--help) usage; exit 0 ;;
        *) usage >&2; exit 64 ;;
    esac
done
[[ "$PREPARE_ONLY" = 1 || -n "$HOST" ]] || { usage >&2; exit 64; }
[[ -d "$DIST/bin" && -d "$DIST/lib" ]] || { echo 'build :relay:installDist first' >&2; exit 65; }
if [[ -z "$OUTPUT" ]]; then OUTPUT="$(mktemp -d /tmp/codebridge-relay-deploy.XXXXXX)"; fi
mkdir -p "$OUTPUT"
OUTPUT="$(cd "$OUTPUT" && pwd)"
[[ ! -e "$OUTPUT/payload" ]] || { echo 'output payload already exists; choose a fresh output directory' >&2; exit 65; }
mkdir "$OUTPUT/payload"
cp -R "$DIST/bin" "$DIST/lib" "$OUTPUT/payload/"
cp deploy/codebridge/apply-relay.sh "$OUTPUT/payload/"
python3 - "$OUTPUT/payload" <<'PY'
import datetime, hashlib, json, pathlib, subprocess, sys
root = pathlib.Path(sys.argv[1])
commit = subprocess.check_output(['git', 'rev-parse', 'HEAD'], text=True).strip()
# Capture exact inputs even while another release task is editing unrelated iOS files.
paths = [p for p in sorted(root.rglob('*')) if p.is_file()]
inputs = subprocess.check_output(['git', 'ls-files', '-z', 'protocol', 'relay', 'observability', 'observability-sentry', 'gradle', 'settings.gradle.kts', 'build.gradle.kts', 'gradle.properties']).decode().split('\0')
source_hashes = {name: hashlib.sha256(pathlib.Path(name).read_bytes()).hexdigest() for name in inputs if name and pathlib.Path(name).is_file()}
source_fingerprint = hashlib.sha256(json.dumps(source_hashes, sort_keys=True).encode()).hexdigest()
manifest = {'source_commit': commit, 'source_fingerprint_sha256': source_fingerprint,
            'source_files': source_hashes, 'created_at': datetime.datetime.now(datetime.timezone.utc).isoformat(),
            'files': {str(p.relative_to(root)): hashlib.sha256(p.read_bytes()).hexdigest() for p in paths}}
(root / 'release.json').write_text(json.dumps(manifest, sort_keys=True, indent=2) + '\n')
with (root / 'dist.sha256').open('w') as output:
    for p in sorted(root.rglob('*')):
        if p.is_file() and p.name != 'dist.sha256':
            output.write(hashlib.sha256(p.read_bytes()).hexdigest() + '  ' + str(p.relative_to(root)) + '\n')
PY
tar czf "$OUTPUT/dist.tgz" -C "$OUTPUT/payload" bin lib apply-relay.sh release.json dist.sha256
printf 'prepared: %s\n' "$OUTPUT"
if [[ "$PREPARE_ONLY" = 1 ]]; then exit 0; fi
DEPLOY_ID="$(date -u +%Y%m%dT%H%M%SZ)-$$"
REMOTE="/var/tmp/codebridge-relay-deploy-$DEPLOY_ID"
UNIT="codebridge-relay-deploy-$DEPLOY_ID"
SSH=(ssh -o BatchMode=yes "$HOST")
"${SSH[@]}" 'set -eu; test ! -e /etc/cc-pocket-relay/retired-primary; test -f /etc/nginx/conf.d/relay.xiaowanai.cn.conf; systemctl is-active --quiet cc-pocket-relay'
"${SSH[@]}" "set -eu; umask 077; mkdir '$REMOTE'"
scp -o BatchMode=yes "$OUTPUT/dist.tgz" "$HOST:$REMOTE/dist.tgz"
# systemd owns recovery after the uploading connection ends. An unknown result is inspected, never retried blindly.
if ! "${SSH[@]}" "set -eu; tar xzf '$REMOTE/dist.tgz' -C '$REMOTE'; cd '$REMOTE'; sha256sum -c dist.sha256; systemd-run --unit='$UNIT' --collect --wait --property=Type=oneshot --property=TimeoutStartSec=180 /bin/bash '$REMOTE/apply-relay.sh' '$REMOTE' >'$REMOTE/job.log' 2>&1; test \"\$(cat '$REMOTE/result')\" = ok"; then
    echo "Deployment failed or result unknown. Inspect $REMOTE/result, $REMOTE/job.log and $UNIT before retrying." >&2
    exit 1
fi
"${SSH[@]}" "systemctl show cc-pocket-relay --property=MainPID --property=ActiveState; cat '$REMOTE/result'; cat '$REMOTE/backup-path'"
curl -fsS --max-time 15 https://relay.xiaowanai.cn/healthz
printf '\npersonal relay deployment verified\n'
