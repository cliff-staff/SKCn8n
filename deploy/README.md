# n8n 公司內部自架部署

以 Docker Compose 在單台 Linux VM 上運行 n8n，含 PostgreSQL 與 Caddy（HTTPS）。

**部署情境**：內網專用，網域 `skcn8n.skycloud.tw` 只在公司內部 DNS 解析，
不對外開放。TLS 使用公司既有的 `*.skycloud.tw` 萬用憑證（公開 CA 簽發），
因此**不使用** Let's Encrypt 自動簽發。

## 架構

```
      公司內網（skcn8n.skycloud.tw → VM 內網 IP）
                │  443 / 80
        ┌───────▼────────┐
        │     Caddy      │  載入公司萬用憑證、反向代理、安全標頭
        │   (edge 網路)   │
        └───────┬────────┘
                │  n8n:5678
        ┌───────▼────────┐
        │      n8n       │  工作流引擎（官方映像，社群版）
        │  edge+internal │  資料存於 volume: n8n-data
        └───────┬────────┘
                │  postgres:5432
        ┌───────▼────────┐
        │   PostgreSQL   │  僅在 internal 網路，不對外開放
        │ (internal 網路) │  資料存於 volume: postgres-data
        └────────────────┘
```

- 只有 Caddy 開 80/443（供內網存取）；PostgreSQL 完全無對外路由。
- n8n 同時連 `edge`（對外抓 API、收 webhook）與 `internal`（連資料庫）。
- n8n 本身仍需要能連外網，才能呼叫外部 API（Google Sheets、Slack 等）。

## 前置需求

**VM 規格（建議）**

| 項目 | 最低 | 建議 |
| --- | --- | --- |
| CPU | 2 vCPU | 4 vCPU |
| RAM | 2 GB | 4 GB 以上 |
| 磁碟 | 20 GB | 50 GB SSD（執行紀錄會成長） |
| OS | 任何支援 Docker 的 Linux | Ubuntu 22.04 / 24.04 LTS |

**其他**

- 已安裝 Docker Engine 24+ 與 Compose v2（`docker compose version` 可執行）。
- **公司既有 `*.skycloud.tw` 萬用憑證**（含中繼鏈的 `fullchain.pem` 與 `privkey.pem`）。
  可向核發憑證的 IT 單位索取。
- **內部 DNS 記錄**：`skcn8n.skycloud.tw` → 這台 VM 的內網 IP。
- 內網防火牆對使用者網段開放 80、443（80 僅用於轉址到 443）。
  不需要、也不應該把 80/443 對公網開放。

> **關於這個 fork**：本 repo 是 n8n 官方原始碼的 fork（v2.42 線）。本部署使用的是
> **官方映像** `docker.n8n.io/n8nio/n8n`，因此 fork 只在你需要修改 n8n 原始碼
> （自訂品牌、修改核心行為）時才派得上用場。若只是要掛自寫節點，見下方
> 「自訂節點」，不必自行 build 映像。

## 快速開始

```bash
# 1. 取得部署檔（在 VM 上）
sudo git clone https://github.com/cliff-staff/SKCn8n.git /opt/n8n
sudo chown -R "$USER" /opt/n8n
cd /opt/n8n/deploy

# 2. 建立環境變數檔並修改
cp .env.example .env
vi .env            # 至少改 POSTGRES_PASSWORD（網域已預設 skcn8n.skycloud.tw）

# 3. 放入公司萬用憑證
mkdir -p certs
cp /path/to/fullchain.pem certs/fullchain.pem   # 伺服器憑證 + 中繼憑證
cp /path/to/privkey.pem   certs/privkey.pem     # 私鑰
chmod 600 certs/privkey.pem
chmod 644 certs/fullchain.pem

# 4. 產生加密金鑰（務必備份！）
./scripts/gen-secrets.sh

# 5. 建立檔案節點可用的目錄（容器內以 uid 1000 執行）
mkdir -p local-files && sudo chown 1000:1000 local-files

# 6. 啟動
docker compose up -d

# 7. 觀察啟動狀況（首次啟動會跑資料庫 migration，約 1-2 分鐘）
docker compose logs -f n8n
```

看到 `Editor is now accessible via: https://skcn8n.skycloud.tw` 即完成。
瀏覽 `https://skcn8n.skycloud.tw`，第一次進入會要求建立**擁有者帳號**。

> 憑證檔放錯或缺少中繼憑證時，Caddy 會啟動失敗。用
> `docker compose logs caddy` 確認；看到 `certificate` 相關錯誤就是憑證問題。
> 先用 `openssl x509 -in certs/fullchain.pem -noout -subject -dates` 檢查
> 憑證的主體與有效期限是否正確。

## 首次設定建議

1. **建立擁有者帳號**：第一個註冊的人即為 instance owner，請用公司信箱。
2. **關閉公開註冊**：Settings → 確認沒有開啟任何自助註冊；新成員一律由
   owner/admin 在 Settings → Users 以邀請方式加入（需先設定 SMTP）。
3. **設定 SMTP**：沒有 SMTP 就無法寄邀請信與密碼重設信。設定後
   `docker compose up -d` 重啟生效。
4. **指派 2FA**：Settings → Personal 可啟用 TOTP 兩步驟驗證，建議管理員必開。
5. **規劃專案與權限**：社群版提供 owner/admin/member 三種角色與 Project 分享；
   細緻的 RBAC、SSO/SAML、環境隔離屬 Enterprise 版功能。

## 日常維運

```bash
cd /opt/n8n/deploy

docker compose ps               # 查看狀態
docker compose logs -f n8n      # 追 n8n 日誌
docker compose logs -f caddy    # 追 TLS / 存取日誌
docker compose restart n8n      # 重啟 n8n（不影響資料庫）
docker compose down             # 停止全部（volume 保留，資料不刪）
```

### 升級版本

```bash
cd /opt/n8n/deploy
./scripts/backup.sh             # 升級前一定先備份
vi .env                         # 修改 N8N_VERSION，例如 2.42.2 -> 2.43.0
docker compose pull
docker compose up -d
docker compose logs -f n8n      # 確認 migration 正常
```

> 跨大版本（例如 2.x → 3.x）升級前請先讀官方 breaking changes；n8n 啟動時
> 若偵測到破壞性變更，會在 UI 顯示 migration report。

### 自動備份

```bash
# 加入 crontab：每天凌晨 3 點備份到 NAS
crontab -e
0 3 * * * /opt/n8n/deploy/scripts/backup.sh /mnt/nas/n8n-backups >> /var/log/n8n-backup.log 2>&1
```

## 備份與還原

`./scripts/backup.sh [目標目錄]` 會產出三樣東西：

| 檔案 | 內容 |
| --- | --- |
| `postgres.sql.gz` | 所有工作流、憑證、使用者、執行紀錄 |
| `n8n_encryption_key` | **解開憑證的唯一金鑰** |
| `n8n-data.tar.gz` | binary data、storage 目錄 |

**兩個關鍵觀念**

1. **加密金鑰必須與資料庫一起備份**。只有資料庫而沒有金鑰，所有憑證
   （API key、資料庫密碼、OAuth token）都無法還原。
2. **備份檔等同整站控制權**，內含所有整合的機密。請存於加密儲存、
   限制存取權限，異地保存至少一份。

還原：

```bash
./scripts/restore.sh ./backups/20260101-030000
```

> 備份**不含** `certs/`（TLS 憑證）。還原到新機器時，記得重新放入公司
> 萬用憑證，否則 Caddy 起不來。

## 安全檢查清單

- [ ] `.env`、`secrets/`、`certs/` 未進版控（已由 `.gitignore` 排除）。
- [ ] `POSTGRES_PASSWORD` 為高強度隨機值，非預設。
- [ ] 加密金鑰已備份到公司密碼管理系統（非只存在這台 VM）。
- [ ] `certs/privkey.pem` 權限為 600，且未與他人共用。
- [ ] 萬用憑證到期日已記錄，有續簽提醒。
- [ ] VM 防火牆只對內網網段開放 80/443；22 限制來源 IP；
      **80/443 不對公網開放**。
- [ ] 已關閉自助註冊，新成員一律邀請制。
- [ ] 管理員帳號已啟用 2FA。
- [ ] 定期更新映像版本，留意安全性公告。
- [ ] 定期檢查 `docker compose logs n8n` 是否有異常登入或失敗的執行。

**已預設套用的強化**（見 `docker-compose.yml`）：

- `N8N_SECURE_COOKIE=true`：cookie 僅在 HTTPS 傳輸。
- `N8N_BLOCK_ENV_ACCESS_IN_NODE=true`：節點無法讀取容器環境變數
  （避免工作流作者取得資料庫密碼等機密）。
- `N8N_RESTRICT_FILE_ACCESS_TO=/files`：檔案節點只能存取指定目錄，
  無法讀取容器內其他路徑。
- `N8N_DIAGNOSTICS_ENABLED=false`：不傳送使用統計回 n8n。
- 資料庫不對外開放，僅存在於 internal 網路。
- 執行紀錄自動清理（預設保留 14 天 / 2 萬筆），避免資料庫無限成長。

## 常見問題

**Caddy 啟動失敗 / 憑證錯誤**
1. 確認 `certs/fullchain.pem` 與 `certs/privkey.pem` 都存在且非空。
2. 確認 `fullchain.pem` **有含中繼憑證**（打開應該看到 2 段
   `-----BEGIN CERTIFICATE-----`）。只放葉憑證會讓瀏覽器顯示不受信任。
3. 確認私鑰與憑證是同一組：兩者的公鑰指紋需一致
   ```bash
   openssl x509 -in certs/fullchain.pem -noout -pubkey | openssl md5
   openssl pkey -in certs/privkey.pem -pubout | openssl md5
   ```
4. 看日誌：`docker compose logs caddy`。

**瀏覽器顯示「連線不安全」/ 憑證名稱不符**
- 確認憑證涵蓋 `skcn8n.skycloud.tw`：
  `openssl x509 -in certs/fullchain.pem -noout -ext subjectAltName`
  萬用憑證 `*.skycloud.tw` 只涵蓋**一層**子網域，`skcn8n.skycloud.tw` 符合。
- 確認你是用 `https://skcn8n.skycloud.tw` 存取，而非 IP 或別名。

**內網連不上 `skcn8n.skycloud.tw`**
內部 DNS 還沒建好。在用戶端執行 `nslookup skcn8n.skycloud.tw`，
應回傳這台 VM 的內網 IP；若沒有，請 IT 在內部 DNS 新增 A 記錄。

**憑證到期了怎麼辦**
萬用憑證通常一年到期。更新流程：

```bash
cp /path/to/new/fullchain.pem certs/fullchain.pem
cp /path/to/new/privkey.pem   certs/privkey.pem
chmod 600 certs/privkey.pem
docker compose restart caddy
```

> Caddy **不會**自動續簽手動載入的憑證，請把到期日記進 IT 的行事曆。
> 查目前到期日：`openssl x509 -in certs/fullchain.pem -noout -enddate`

**用 http:// 連不進去**
站台是 HTTPS 專用。Caddy 通常會自動把 80 轉到 443，但即使沒有轉址，
請一律使用 `https://skcn8n.skycloud.tw` 存取即可。

**Webhook 收到的 URL 不對 / 點測試連結連不上**
確認 `.env` 的 `N8N_DOMAIN` 與實際存取網域完全一致，且 n8n 環境變數中的
`N8N_EDITOR_BASE_URL`、`N8N_WEBHOOK_URL` 都是 `https://<同一個網域>`。

**要讓 n8n 信任公司內部的自簽憑證（如內部 API）**
把公司 CA 憑證（`.crt`）放進 `deploy/` 下新增的 `custom-certificates/` 目錄，
然後在 `docker-compose.yml` 的 n8n 服務加上掛載：

```yaml
    volumes:
      - ./custom-certificates:/opt/custom-certificates:ro
```

映像的進入點會自動將該目錄設為信任的 CA（`docker-entrypoint.sh` 內建支援）。

**Read/Write Files 節點要存取檔案**
已掛載 `./local-files` 到容器內 `/files`，並以 `N8N_RESTRICT_FILE_ACCESS_TO=/files`
限制節點只能存取該目錄。在節點中用 `/files/...` 路徑存取。

若目錄權限不對（節點報 EACCES），在 VM 上執行：

```bash
mkdir -p local-files && sudo chown 1000:1000 local-files
```

請勿把主機的敏感目錄（如 `/etc`、`/var/run/docker.sock`）掛進去。
若完全不需要檔案存取，可把 compose 中該行掛載與 `N8N_RESTRICT_FILE_ACCESS_TO` 一併移除。

**要安裝社群節點（community nodes）**
UI → Settings → Community nodes 即可安裝 npm 套件，需 `N8N_COMMUNITY_PACKAGES_ENABLED=true`。
若公司資安政策不允許，設為 `false` 可完全停用。

**自訂節點（自己寫的）**
放在主機的 `deploy/custom-nodes/`，於 `docker-compose.yml` 掛載：

```yaml
    volumes:
      - ./custom-nodes:/home/node/.n8n/custom
```

**要支援 SSO / SAML、Log Streaming、External Secrets、Environments**
這些是 Enterprise 授權功能。取得授權後在 `.env` 填
`N8N_LICENSE_ACTIVATION_KEY`，重啟即生效。社群版已包含無限工作流、
全部節點、專案與使用者管理。

## 檔案說明

```
deploy/
├── docker-compose.yml       # 服務定義（n8n / postgres / caddy）
├── Caddyfile                # 反向代理與 TLS 設定
├── .env.example             # 環境變數範本（複製為 .env 後修改）
├── .gitignore               # 排除 .env / secrets / certs
└── scripts/
    ├── gen-secrets.sh       # 產生加密金鑰
    ├── backup.sh            # 備份（DB + 金鑰 + 資料卷）
    └── restore.sh           # 還原
```

執行期產生、**不進版控**的目錄：

| 目錄 | 內容 | 備註 |
| --- | --- | --- |
| `secrets/` | n8n 加密金鑰 | 遺失即無法還原憑證，務必備份 |
| `certs/` | 公司萬用憑證與私鑰 | 私鑰權限 600 |
| `local-files/` | 檔案節點存取的目錄 | 掛載為容器內 `/files` |
| `backups/` | 備份輸出 | 建議改存到 NAS |

## 之後要擴充時

- **執行量變大、單機 CPU 吃滿** → 改為 queue mode：加入 Redis 與多個 worker
  容器，`EXECUTIONS_MODE=queue`。需要調整 compose 與共用 binary data 儲存。
- **要高可用（HA）** → 多個 main instance + 外部 PostgreSQL，並啟用
  `N8N_MULTI_MAIN_SETUP_ENABLED`。
- **改用公司既有資料庫** → 移除 compose 中的 `postgres` 服務，將
  `DB_POSTGRESDB_HOST` 等指向外部 DB。
- **用 Kubernetes 部署** → 官方提供 Helm chart，可將本目錄的環境變數
  對應過去。

這些都屬於規模化變更，建議先在測試環境驗證再上正式。
