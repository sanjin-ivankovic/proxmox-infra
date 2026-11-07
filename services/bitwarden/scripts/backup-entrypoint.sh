#!/bin/sh
set -eu

log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $1"
}

# --- Install optional dependencies ---
if [ -n "${BACKUP_R2_BUCKET:-}" ] && [ -n "${BACKUP_R2_ENDPOINT:-}" ]; then
    log "R2 configured — installing aws-cli..."
    apk add --no-cache aws-cli > /dev/null 2>&1
    log "aws-cli installed."
fi

if [ -n "${BACKUP_NAS_TARGET:-}" ]; then
    log "NAS configured — installing rsync and openssh-client..."
    apk add --no-cache rsync openssh-client > /dev/null 2>&1
    log "rsync and openssh-client installed."
fi

# --- Write cron schedule ---
CRON_SCHEDULE="${BACKUP_CRON_SCHEDULE:-0 2 * * *}"

# Cron doesn't inherit Docker env vars, so inline them in the cron entry
ENV_VARS="BW_DB_SERVER=${BW_DB_SERVER}"
ENV_VARS="${ENV_VARS} BW_DB_DATABASE=${BW_DB_DATABASE}"
ENV_VARS="${ENV_VARS} BW_DB_USERNAME=${BW_DB_USERNAME}"
ENV_VARS="${ENV_VARS} BW_DB_PASSWORD=${BW_DB_PASSWORD}"
ENV_VARS="${ENV_VARS} LOCAL_RETENTION=${LOCAL_RETENTION:-7}"

if [ -n "${BACKUP_R2_BUCKET:-}" ]; then
    ENV_VARS="${ENV_VARS} BACKUP_R2_BUCKET=${BACKUP_R2_BUCKET}"
    ENV_VARS="${ENV_VARS} BACKUP_R2_ENDPOINT=${BACKUP_R2_ENDPOINT}"
    ENV_VARS="${ENV_VARS} AWS_ACCESS_KEY_ID=${AWS_ACCESS_KEY_ID:-}"
    ENV_VARS="${ENV_VARS} AWS_SECRET_ACCESS_KEY=${AWS_SECRET_ACCESS_KEY:-}"
    ENV_VARS="${ENV_VARS} BACKUP_R2_RETENTION=${BACKUP_R2_RETENTION:-30}"
fi

if [ -n "${BACKUP_NAS_TARGET:-}" ]; then
    ENV_VARS="${ENV_VARS} BACKUP_NAS_TARGET=${BACKUP_NAS_TARGET}"
    ENV_VARS="${ENV_VARS} BACKUP_NAS_RETENTION=${BACKUP_NAS_RETENTION:-14}"
fi

cat > /etc/crontabs/root <<EOF
${CRON_SCHEDULE} ${ENV_VARS} /scripts/backup.sh >> /var/log/backup.log 2>&1
EOF

log "Backup scheduler started."
log "  Schedule: ${CRON_SCHEDULE}"
log "  Local retention: ${LOCAL_RETENTION:-7} backups"
[ -n "${BACKUP_R2_BUCKET:-}" ] && log "  R2 bucket: ${BACKUP_R2_BUCKET} (${BACKUP_R2_RETENTION:-30} days)"
[ -n "${BACKUP_NAS_TARGET:-}" ] && log "  NAS target: ${BACKUP_NAS_TARGET} (${BACKUP_NAS_RETENTION:-14} days)"

# --- Optional: run backup on startup ---
if [ "${BACKUP_ON_STARTUP:-false}" = "true" ]; then
    log "Running initial backup on startup..."
    /scripts/backup.sh
fi

# --- Start cron in foreground ---
exec crond -f -l 2
