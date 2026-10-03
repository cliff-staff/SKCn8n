#!/usr/bin/env bash
# 從備份還原 n8n。
#
# 用法：
#   ./scripts/restore.sh ./backups/20260101-030000
#
# 還原會「覆蓋」現有資料庫與 n8n 資料卷，執行前會要求確認。
set -euo pipefail

cd "$(dirname "$0")/.."

SRC="${1:-}"
if [ -z "$SRC" ] || [ ! -d "$SRC" ]; then
	echo "用法：$0 <備份目錄>  例如 $0 ./backups/20260101-030000" >&2
	exit 1
fi

if [ ! -f .env ]; then
	echo "錯誤：找不到 .env。" >&2
	exit 1
fi
set -a
# shellcheck disable=SC1091
. ./.env
set +a

echo "即將從 $SRC 還原，這會覆蓋目前的資料庫與 n8n 資料卷。"
read -r -p "確定要繼續嗎？請輸入 yes： " confirm
[ "$confirm" = "yes" ] || {
	echo "已取消。"
	exit 1
}

echo "[1/4] 停止 n8n 與 caddy..."
docker compose stop n8n caddy

echo "[2/4] 還原加密金鑰..."
if [ -f "$SRC/n8n_encryption_key" ]; then
	cp "$SRC/n8n_encryption_key" secrets/n8n_encryption_key
	chmod 600 secrets/n8n_encryption_key
else
	echo "警告：備份中沒有加密金鑰，將沿用現有金鑰（若與備份不符，憑證會解不開）。" >&2
fi

echo "[3/4] 還原 PostgreSQL..."
docker compose up -d postgres
until docker compose exec -T postgres pg_isready -U "$POSTGRES_USER" -d "$POSTGRES_DB" >/dev/null 2>&1; do
	sleep 2
done
gunzip -c "$SRC/postgres.sql.gz" | docker compose exec -T postgres psql -U "$POSTGRES_USER" -d "$POSTGRES_DB"

echo "[4/4] 還原 n8n 資料卷..."
if [ -f "$SRC/n8n-data.tar.gz" ]; then
	docker run --rm \
		-v n8n_n8n-data:/data \
		-v "$(cd "$SRC" && pwd)":/backup:ro \
		alpine:3 \
		sh -c 'rm -rf /data/* && tar xzf /backup/n8n-data.tar.gz -C /data'
fi

echo "啟動服務..."
docker compose up -d

echo "還原完成。請以 docker compose logs -f n8n 確認啟動正常。"
