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
chmod 600 "$KEY_FILE"

echo "已產生 $KEY_FILE"
echo
echo "請立即備份這把金鑰到安全的地方，例如公司的密碼管理系統："
echo
cat "$KEY_FILE"
echo
