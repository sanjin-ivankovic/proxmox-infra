#!/bin/sh
set -eu

BACKUP_DIR="/backups"
TIMESTAMP=$(date +'%Y%m%d_%H%M%S')
BACKUP_PATH="${BACKUP_DIR}/${TIMESTAMP}"
LOCAL_RETENTION="${LOCAL_RETENTION:-7}"

log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $1"
}

cleanup_on_failure() {
    log "ERROR: Backup failed. Cleaning up partial backup..."
    rm -rf "${BACKUP_PATH}"
}

trap cleanup_on_failure EXIT
# Reset trap on successful completion (set at end of script)
trap_success() { trap - EXIT; }

mkdir -p "${BACKUP_PATH}"

# --- 1. Database backup (consistent via pg_dump) ---
log "Starting PostgreSQL backup..."
PGPASSWORD="${BW_DB_PASSWORD}" pg_dump \
    -h "${BW_DB_SERVER}" \
    -U "${BW_DB_USERNAME}" \
    -d "${BW_DB_DATABASE}" \
    --format=custom \
    --file="${BACKUP_PATH}/bitwarden_vault.dump"

log "Database backup complete."

# --- 2. File backup (config, attachments, data protection keys) ---
log "Starting file backup..."
tar -czf "${BACKUP_PATH}/bitwarden_data.tar.gz" \
    -C /etc/bitwarden .

log "File backup complete."

# --- 3. Checksums for integrity verification ---
cd "${BACKUP_PATH}"
sha256sum bitwarden_vault.dump bitwarden_data.tar.gz > checksums.sha256

BACKUP_SIZE=$(du -sh "${BACKUP_PATH}" | cut -f1)
log "Local backup complete: ${BACKUP_PATH} (${BACKUP_SIZE})"

# --- 4. R2 offsite backup (if configured) ---
if [ -n "${BACKUP_R2_BUCKET:-}" ] && [ -n "${BACKUP_R2_ENDPOINT:-}" ]; then
    log "Uploading to Cloudflare R2: s3://${BACKUP_R2_BUCKET}/${TIMESTAMP}/..."

    aws s3 cp "${BACKUP_PATH}/bitwarden_vault.dump" \
        "s3://${BACKUP_R2_BUCKET}/${TIMESTAMP}/bitwarden_vault.dump" \
        --endpoint-url "${BACKUP_R2_ENDPOINT}"

    aws s3 cp "${BACKUP_PATH}/bitwarden_data.tar.gz" \
        "s3://${BACKUP_R2_BUCKET}/${TIMESTAMP}/bitwarden_data.tar.gz" \
        --endpoint-url "${BACKUP_R2_ENDPOINT}"

    aws s3 cp "${BACKUP_PATH}/checksums.sha256" \
        "s3://${BACKUP_R2_BUCKET}/${TIMESTAMP}/checksums.sha256" \
        --endpoint-url "${BACKUP_R2_ENDPOINT}"

    log "R2 upload complete."

    # Clean old R2 backups
    R2_RETENTION="${BACKUP_R2_RETENTION:-30}"
    CUTOFF_EPOCH=$(($(date +%s) - R2_RETENTION * 86400))
    CUTOFF_DATE=$(date -d "@${CUTOFF_EPOCH}" +'%Y%m%d')
    log "Cleaning R2 backups older than ${R2_RETENTION} days (before ${CUTOFF_DATE})..."

    aws s3 ls "s3://${BACKUP_R2_BUCKET}/" --endpoint-url "${BACKUP_R2_ENDPOINT}" | \
        awk '{print $NF}' | tr -d '/' | while read -r prefix; do
            BACKUP_DATE=$(echo "${prefix}" | cut -c1-8)
            if [ "${BACKUP_DATE}" -lt "${CUTOFF_DATE}" ] 2>/dev/null; then
                log "  Removing old R2 backup: ${prefix}"
                aws s3 rm "s3://${BACKUP_R2_BUCKET}/${prefix}/" \
                    --recursive --endpoint-url "${BACKUP_R2_ENDPOINT}"
            fi
        done

    log "R2 cleanup complete."
else
    log "R2 not configured — skipping offsite backup."
fi

# --- 5. NAS rsync backup (if configured) ---
if [ -n "${BACKUP_NAS_TARGET:-}" ]; then
    log "Syncing to NAS: ${BACKUP_NAS_TARGET}..."

    rsync -az --timeout=60 \
        "${BACKUP_PATH}/" \
        "${BACKUP_NAS_TARGET}/${TIMESTAMP}/"

    log "NAS sync complete."

    # Clean old NAS backups
    NAS_RETENTION="${BACKUP_NAS_RETENTION:-14}"
    NAS_HOST=$(echo "${BACKUP_NAS_TARGET}" | cut -d: -f1)
    NAS_PATH=$(echo "${BACKUP_NAS_TARGET}" | cut -d: -f2)
    # shellcheck disable=SC2029
    ssh -o ConnectTimeout=10 "${NAS_HOST}" \
        "cd '${NAS_PATH}' && ls -dt [0-9]* 2>/dev/null | tail -n +$((NAS_RETENTION + 1)) | xargs -r rm -rf"

    log "NAS cleanup complete."
else
    log "NAS not configured — skipping NAS backup."
fi

# --- 6. Clean old local backups ---
log "Cleaning local backups (keeping last ${LOCAL_RETENTION})..."
# shellcheck disable=SC2012 # ls is safe here — directory names are controlled timestamps (YYYYMMDD_HHMMSS)
ls -dt "${BACKUP_DIR}"/[0-9]* 2>/dev/null | tail -n +$((LOCAL_RETENTION + 1)) | xargs -r rm -rf

log "Backup job finished successfully."
trap_success
