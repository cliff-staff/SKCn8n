#!/usr/bin/env bash
# 產生 n8n 加密金鑰（N8N_ENCRYPTION_KEY）。
#
# 這把金鑰用來加解密資料庫中所有憑證。遺失它就等於所有已存的
# API key / 密碼 / OAuth token 全部救不回來，只能重新輸入。
# 因此：產生後請立刻備份到公司的密碼管理系統。
set -euo pipefail

cd "$(dirname "$0")/.."

KEY_FILE="secrets/n8n_encryption_key"

if [ -f "$KEY_FILE" ]; then
	echo "已存在 $KEY_FILE，不覆蓋。"
	echo "若要重新產生，請先自行備份並刪除該檔案（注意：換金鑰會使既有憑證失效）。"
	exit 0
fi

mkdir -p secrets
umask 077
openssl rand -hex 32 >"$KEY_FILE"

# n8n 容器以 uid 1000（node）執行。compose 的 secrets 是以 bind mount
# 方式把 host 檔案掛進容器，容器看到的權限就是 host 上的權限，而且
# Compose 在非 Swarm 模式會忽略 secret 的 uid/gid/mode 設定。
# 所以這裡必須讓 uid 1000 讀得到，否則 n8n 會以
#   EACCES: permission denied, open '/run/secrets/n8n_encryption_key'
# 不斷重啟。
chmod 400 "$KEY_FILE"
if [ "$(id -u)" -eq 0 ]; then
	chown 1000:1000 "$KEY_FILE"
else
	echo "警告：目前不是 root，無法自動設定擁有者。" >&2
	echo "      請執行：sudo chown 1000:1000 $KEY_FILE" >&2
fi

echo "已產生 $KEY_FILE"
echo
echo "請立即備份這把金鑰到安全的地方，例如公司的密碼管理系統："
echo
cat "$KEY_FILE"
echo
