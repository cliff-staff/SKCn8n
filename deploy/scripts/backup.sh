#!/usr/bin/env bash
# 備份 n8n：PostgreSQL 資料 + 加密金鑰。
#
# 用法：
#   ./scripts/backup.sh              # 備份到 ./backups/<時間戳>/
#   ./scripts/backup.sh /mnt/nas/n8n # 備份到指定目錄（建議指向 NAS 或遠端）
#
# 建議加進 crontab 每日執行：
#   0 3 * * * /opt/n8n/deploy/scripts/backup.sh /mnt/nas/n8n-backups >> /var/log/n8n-backup.log 2>&1
set -euo pipefail

cd "$(dirname "$0")/.."

# 載入 .env 取得資料庫帳密
if [ ! -f .env ]; then
	echo "錯誤：找不到 .env，請先 cp .env.example .env 並填寫。" >&2
	exit 1
fi
set -a
# shellcheck disable=SC1091
. ./.env
set +a

BACKUP_ROOT="${1:-./backups}"
STAMP="$(date +%Y%m%d-%H%M%S)"
DEST="$BACKUP_ROOT/$STAMP"

mkdir -p "$DEST"

echo "[1/3] 匯出 PostgreSQL..."
docker compose exec -T postgres \
	pg_dump -U "$POSTGRES_USER" -d "$POSTGRES_DB" --clean --if-exists \
	| gzip >"$DEST/postgres.sql.gz"

echo "[2/3] 備份加密金鑰..."
cp secrets/n8n_encryption_key "$DEST/n8n_encryption_key"

echo "[3/3] 備份 n8n 資料卷（binary data / storage）..."
docker run --rm \
	-v n8n_n8n-data:/data:ro \
	-v "$(cd "$DEST" && pwd)":/backup \
	alpine:3 \
	tar czf /backup/n8n-data.tar.gz -C /data .

# 記錄本次使用的映像版本，還原時可對齊
docker compose images n8n >"$DEST/images.txt" 2>/dev/null || true

chmod -R go-rwx "$DEST"

echo
echo "備份完成：$DEST"
du -sh "$DEST"/* 2>/dev/null || true
echo
echo "提醒：這份備份含加密金鑰，等同整站控制權，請妥善保管與加密傳輸。"
