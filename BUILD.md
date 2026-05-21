# BUILD.md — Build HCL Domino 9.0.1 FP10 container image

Step-by-step SOP. Read [DISCLAIMER.md](DISCLAIMER.md) first.

## Table of contents

- [1. Prerequisites](#1-prerequisites)
- [2. Obtain installer media](#2-obtain-installer-media)
- [3. Build the image](#3-build-the-image)
- [4. First launch (setup wizard mode)](#4-first-launch-setup-wizard-mode)
- [5. Common failure modes](#5-common-failure-modes)
- [6. Backup and restore](#6-backup-and-restore)

For the additional-server setup flow against an existing Domino domain, see [ADDITIONAL-SERVER.md](ADDITIONAL-SERVER.md) after step 4.

---

## 1. Prerequisites

| Item | Required version / note | Quick verify |
|---|---|---|
| Linux host or WSL2 distro | Ubuntu 22.04 / 24.04, Debian 12, RHEL 9, etc. | `cat /etc/os-release \| head -3` |
| Docker Engine | 20.10+ (29.x tested) | `docker --version` |
| Free disk | At least 5 GB | `df -h /var/lib/docker` |
| RAM available to container | At least 2 GB | `free -h` |
| HCL Domino 9 entitlement | Per HCL EULA | (you / your admin's responsibility) |
| HCL FlexNet account | Active | Browse to https://hclsoftware.flexnetoperations.com/ |

If on Windows + WSL2, create an isolated distro for this work — don't pollute your everyday WSL distro:

```powershell
# In PowerShell
mkdir C:\WSL\Ubuntu-domino9 -Force | Out-Null
wsl --install -d Ubuntu-24.04 --name Ubuntu-domino9 --location C:\WSL\Ubuntu-domino9
# Interactive prompts: pick a UNIX user (e.g. notes) and password
```

Then install Docker CE inside that distro:

```bash
sudo apt-get remove -y docker docker-engine docker.io containerd runc 2>/dev/null || true
sudo apt-get update
sudo apt-get install -y ca-certificates curl
sudo install -m 0755 -d /etc/apt/keyrings
sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
sudo chmod a+r /etc/apt/keyrings/docker.asc
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
sudo apt-get update
sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
if [ -d /run/systemd/system ]; then
  sudo systemctl enable --now docker
else
  sudo service docker start
fi
sudo usermod -aG docker $USER
# Exit, then `wsl --terminate <distro>` from PowerShell, then re-enter for group to take effect
```

Verify Docker works:

```bash
docker run --rm hello-world
```

---

## 2. Obtain installer media

You need **two files** from HCL FlexNet Operations:

| File | Approx size | Description |
|---|---|---|
| `DOMINO_9.0.1_64_BIT_LIN_XS_EN.tar` | ~834 MB | Domino 9.0.1 base for Linux x86_64 |
| `domino901FP10_linux64_x86.tar` | ~441 MB | Fix Pack 10 (the final 9.x FP) |

> **Filename notes**: "XS" in `LIN_XS_EN` is IBM xSeries (= Intel x86_64). "ZS" is zSeries (mainframe — do **not** download this). The Fix Pack uses a different naming style (lowercase, `_linux64_x86`).

### Download steps

1. Browse to https://hclsoftware.flexnetoperations.com/ and log in with your HCL account.
2. Look for "HCL Domino" → version "9.0.1".
3. Under platform filter, choose **Linux 64-bit**.
4. Download `DOMINO_9.0.1_64_BIT_LIN_XS_EN.tar`.
5. Look for the Fix Pack section (sometimes a separate "9.0.1 Fix Packs" entitlement).
6. Download `domino901FP10_linux64_x86.tar`.

If Domino 9 has been EOM'd in your account's catalog (it is EOM'd since 2024-06), HCL Support may need to re-enable historical download access.

### Place files into the build context

```bash
cd dockerfiles/domino9.0.1-fp10-ubi7

# Copy from wherever you downloaded them
cp /path/to/DOMINO_9.0.1_64_BIT_LIN_XS_EN.tar  .
cp /path/to/domino901FP10_linux64_x86.tar       .

# Verify .gitignore is excluding these (it should be)
git status
# Expected output: tar files NOT shown as untracked
```

### (Optional) checksum your own copy

If you have a known-good SHA256 to compare against (from HCL Support / FlexNet release notes / a colleague who already downloaded):

```bash
sha256sum DOMINO_9.0.1_64_BIT_LIN_XS_EN.tar
sha256sum domino901FP10_linux64_x86.tar
```

---

## 3. Build the image

```bash
cd dockerfiles/domino9.0.1-fp10-ubi7
docker build -t domino9:9.0.1fp10 .
```

### Expected timing (on a developer laptop, first build, no cache)

| Phase | Wall time |
|---|---|
| Pull RHEL UBI 7 base | ~30 sec |
| `yum install` build-time packages | ~30 sec |
| COPY 1.27 GB of tar into build context | ~10-30 sec (faster on native Linux than WSL `/mnt/c`) |
| Domino base silent install | ~6-7 min |
| Domino FP10 silent install (script.dat) | ~2 min |
| Runtime stage `yum install` | ~20 sec |
| `COPY --from=builder` of /opt/ibm/domino + /local/notesdata | ~20 sec |
| **Total** | **~10-12 min** |

### Build success criteria

```bash
docker images domino9
# Expected:
#   REPOSITORY   TAG          IMAGE ID    SIZE
#   domino9      9.0.1fp10    <id>        1.48GB
docker image inspect domino9:9.0.1fp10 --format '{{.Size}}'
# Expected: under 3000000000 (3 GB)
```

If build fails, see [TROUBLESHOOTING.md](TROUBLESHOOTING.md). The most common failure modes are:

1. `redhat/ubi7` from docker.io requires auth — Dockerfile uses `registry.access.redhat.com/ubi7/ubi:7.9` (free pull) to avoid this.
2. `Undefined subroutine &DingDong::out` — caused by missing `hostname` command. Dockerfile already includes it; if you see this you may have a corrupted base image.

---

## 4. First launch (setup wizard mode)

```bash
docker volume create domino9-data

docker run -d \
  --name domino9 \
  --hostname domino9 \
  -p 1352:1352 \
  -p 80:80 \
  -p 8585:8585 \
  -v domino9-data:/local/notesdata \
  domino9:9.0.1fp10

# Watch the log
docker logs -f domino9
```

Expected log output:

```
[entrypoint] ==== FIRST RUN ====
[entrypoint] No notes.ini (or no Setup= marker) — entering setup listen mode on port 8585.
[entrypoint] Connect Notes Admin client to <host>:8585 ...
./java ... lotus.domino.setup.WizardManagerDomino -data /local/notesdata -listen 8585
Remote server setup enabled on port 8585.
The Domino setup server is now in listening mode.
```

A few `Error - can't open /proc/sys/...` warnings are expected and non-fatal — the container is non-root and can't read kernel tunables.

### Two paths from here

- **First server in a brand new domain** (uncommon if you're containerizing — usually you'd use `OneTouch` for Domino 12+ instead): use a Notes Admin client to walk the "Set up first server" wizard against port 8585. Out of scope for this SOP.
- **Additional server in an existing domain** (the recommended path): see [ADDITIONAL-SERVER.md](ADDITIONAL-SERVER.md).

---

## 5. Common failure modes

See [TROUBLESHOOTING.md](TROUBLESHOOTING.md) for symptom → diagnosis → fix details.

Quick summary of what to check first:

| Symptom | First thing to check |
|---|---|
| `docker build` exits at COPY step | Are both .tar files present in build context? |
| `docker build` exits during silent install | Read `/tmp/nuish.err` inside the container by `docker build` with `--progress=plain` and check stderr |
| Container exits seconds after `docker run` | `docker logs domino9` — likely password prompt for encrypted `server.id` |
| Notes Admin client "Network Communication error" | Is host port 8585 reachable? `Test-NetConnection 127.0.0.1 -Port 8585` from Windows |
| HTTP gives connection refused | Domino HTTP task not yet started — wait 60s or check `docker logs domino9 \| grep HTTP` |
| WSL2 disk exhausted | `docker system prune -a` (warning: removes images too); consider `wsl --shutdown` and free up VHDX |

---

## 6. Backup and restore

### What to back up

The container's `/local/notesdata/` directory contains all stateful Domino data:

| Path | Why it matters |
|---|---|
| `notes.ini` | Server configuration |
| `server.id` | Server identity (DO NOT lose) |
| `names.nsf` | Domino Directory (~30-200 MB depending on domain) |
| `log.nsf` | Server log database |
| `mail.box` | Inbound mail queue |
| `admin4.nsf` | Admin requests queue |
| `IBM_TECHNICAL_SUPPORT/` | NSD dumps, crash analysis |
| `*.id` files (cert.id, admin.id if present) | Other identity files |
| Any custom NSF / mail files | User data |

### Snapshot of a stopped container's data volume

```bash
docker stop domino9
docker run --rm \
  -v domino9-data:/data \
  -v "$(pwd)":/backup \
  alpine \
  tar czf /backup/domino9-data-$(date +%Y%m%d).tar.gz -C /data .
docker start domino9
```

### Restore to a fresh host

```bash
docker volume create domino9-data
docker run --rm \
  -v domino9-data:/data \
  -v /path/to/backup:/backup \
  alpine \
  tar xzf /backup/domino9-data-YYYYMMDD.tar.gz -C /data
docker run --rm --user root \
  -v domino9-data:/data \
  alpine \
  chown -R 1000:1000 /data

# Then run the container as in §4, but it will boot in CONFIGURED RUN mode
# (entrypoint detects notes.ini and skips setup listener)
docker run -d \
  --name domino9 \
  -p 1352:1352 -p 80:80 -p 8585:8585 \
  -v domino9-data:/local/notesdata \
  -e DOMINO_ID_PASSWORD='your-server.id-password' \
  domino9:9.0.1fp10
```

Note: the UID/GID inside the image is 1000:1000 (user `notes`, group `notes`). When you `tar xzf`, the file ownership in the volume must match this. The `chown -R 1000:1000` step above handles that.

### Image-level backup (entire built image as a tarball)

For migration between hosts or DR snapshots:

```bash
# Export
docker save domino9:9.0.1fp10 | gzip > domino9-9.0.1fp10-image.tgz

# Import on the new host
docker load -i domino9-9.0.1fp10-image.tgz
```

The image tar contains only the immutable Docker image layers — **not** any data volume contents. Restoring on a new host requires both the image tar AND a data-volume tar.

---

_End of BUILD.md. For domain-join flow continue to [ADDITIONAL-SERVER.md](ADDITIONAL-SERVER.md)._

---
---

# 繁體中文版

# BUILD.md — 建置 HCL Domino 9.0.1 FP10 container image

逐步 SOP。請先閱讀 [DISCLAIMER.md](DISCLAIMER.md)。

## 目錄

- [1. 前置需求](#1-前置需求)
- [2. 取得安裝媒體](#2-取得安裝媒體)
- [3. 建置 image](#3-建置-image)
- [4. 首次啟動（setup wizard 模式）](#4-首次啟動setup-wizard-模式)
- [5. 常見故障模式](#5-常見故障模式)
- [6. 備份與還原](#6-備份與還原)

若要進行 additional server 設定流程（加入既有 Domino domain），請在步驟 4 之後參閱 [ADDITIONAL-SERVER.md](ADDITIONAL-SERVER.md)。

---

## 1. 前置需求

| 項目 | 必要版本 / 備註 | 快速驗證 |
|---|---|---|
| Linux 主機或 WSL2 distro | Ubuntu 22.04 / 24.04、Debian 12、RHEL 9 等 | `cat /etc/os-release \| head -3` |
| Docker Engine | 20.10+（已測試 29.x） | `docker --version` |
| 可用磁碟空間 | 至少 5 GB | `df -h /var/lib/docker` |
| container 可用 RAM | 至少 2 GB | `free -h` |
| HCL Domino 9 entitlement | 依 HCL EULA | （你 / 你的管理員自行負責） |
| HCL FlexNet 帳號 | 啟用中 | 瀏覽 https://hclsoftware.flexnetoperations.com/ |

若使用 Windows + WSL2，請為這項工作建立獨立的 distro，避免污染你日常使用的 WSL distro：

```powershell
# In PowerShell
mkdir C:\WSL\Ubuntu-domino9 -Force | Out-Null
wsl --install -d Ubuntu-24.04 --name Ubuntu-domino9 --location C:\WSL\Ubuntu-domino9
# Interactive prompts: pick a UNIX user (e.g. notes) and password
```

然後在該 distro 內安裝 Docker CE：

```bash
sudo apt-get remove -y docker docker-engine docker.io containerd runc 2>/dev/null || true
sudo apt-get update
sudo apt-get install -y ca-certificates curl
sudo install -m 0755 -d /etc/apt/keyrings
sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
sudo chmod a+r /etc/apt/keyrings/docker.asc
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
sudo apt-get update
sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
if [ -d /run/systemd/system ]; then
  sudo systemctl enable --now docker
else
  sudo service docker start
fi
sudo usermod -aG docker $USER
# Exit, then `wsl --terminate <distro>` from PowerShell, then re-enter for group to take effect
```

驗證 Docker 可用：

```bash
docker run --rm hello-world
```

---

## 2. 取得安裝媒體

你需要從 HCL FlexNet Operations 取得**兩個檔案**：

| 檔案 | 約略大小 | 說明 |
|---|---|---|
| `DOMINO_9.0.1_64_BIT_LIN_XS_EN.tar` | ~834 MB | Domino 9.0.1 base for Linux x86_64 |
| `domino901FP10_linux64_x86.tar` | ~441 MB | Fix Pack 10（9.x 的最終 FP） |

> **檔名小註**：`LIN_XS_EN` 中的 "XS" 是 IBM xSeries（= Intel x86_64）；"ZS" 是 zSeries（mainframe，**請勿**下載）。Fix Pack 使用不同的命名風格（小寫、`_linux64_x86`）。

### 下載步驟

1. 瀏覽至 https://hclsoftware.flexnetoperations.com/ 並以你的 HCL 帳號登入。
2. 找尋 "HCL Domino" → 版本 "9.0.1"。
3. 在平台 filter 中選擇 **Linux 64-bit**。
4. 下載 `DOMINO_9.0.1_64_BIT_LIN_XS_EN.tar`。
5. 找尋 Fix Pack 區段（有時是另一個 "9.0.1 Fix Packs" entitlement）。
6. 下載 `domino901FP10_linux64_x86.tar`。

如果 Domino 9 在你帳號的目錄中已被 EOM 化（自 2024-06 起已 EOM），可能需要 HCL Support 重新啟用歷史版本的下載權限。

### 將檔案放入 build context

```bash
cd dockerfiles/domino9.0.1-fp10-ubi7

# Copy from wherever you downloaded them
cp /path/to/DOMINO_9.0.1_64_BIT_LIN_XS_EN.tar  .
cp /path/to/domino901FP10_linux64_x86.tar       .

# Verify .gitignore is excluding these (it should be)
git status
# Expected output: tar files NOT shown as untracked
```

### （選擇性）自行校驗 checksum

若你有已知正確的 SHA256 可比對（來自 HCL Support / FlexNet release notes / 已下載過的同事）：

```bash
sha256sum DOMINO_9.0.1_64_BIT_LIN_XS_EN.tar
sha256sum domino901FP10_linux64_x86.tar
```

---

## 3. 建置 image

```bash
cd dockerfiles/domino9.0.1-fp10-ubi7
docker build -t domino9:9.0.1fp10 .
```

### 預期耗時（開發者筆電、首次 build、無 cache）

| 階段 | 實際時間 |
|---|---|
| 拉取 RHEL UBI 7 base | ~30 秒 |
| `yum install` build 階段套件 | ~30 秒 |
| COPY 1.27 GB tar 至 build context | ~10-30 秒（原生 Linux 比 WSL `/mnt/c` 快） |
| Domino base silent install | ~6-7 分 |
| Domino FP10 silent install（script.dat） | ~2 分 |
| Runtime stage `yum install` | ~20 秒 |
| `COPY --from=builder` 複製 /opt/ibm/domino + /local/notesdata | ~20 秒 |
| **總計** | **~10-12 分** |

### Build 成功判定

```bash
docker images domino9
# Expected:
#   REPOSITORY   TAG          IMAGE ID    SIZE
#   domino9      9.0.1fp10    <id>        1.48GB
docker image inspect domino9:9.0.1fp10 --format '{{.Size}}'
# Expected: under 3000000000 (3 GB)
```

若 build 失敗，請參閱 [TROUBLESHOOTING.md](TROUBLESHOOTING.md)。最常見的故障模式為：

1. 從 docker.io 拉 `redhat/ubi7` 需驗證 — Dockerfile 改用 `registry.access.redhat.com/ubi7/ubi:7.9`（免費 pull）以避免此問題。
2. `Undefined subroutine &DingDong::out` — 由缺少 `hostname` 指令造成。Dockerfile 已內含；若仍出現，可能是 base image 損毀。

---

## 4. 首次啟動（setup wizard 模式）

```bash
docker volume create domino9-data

docker run -d \
  --name domino9 \
  --hostname domino9 \
  -p 1352:1352 \
  -p 80:80 \
  -p 8585:8585 \
  -v domino9-data:/local/notesdata \
  domino9:9.0.1fp10

# Watch the log
docker logs -f domino9
```

預期 log 輸出：

```
[entrypoint] ==== FIRST RUN ====
[entrypoint] No notes.ini (or no Setup= marker) — entering setup listen mode on port 8585.
[entrypoint] Connect Notes Admin client to <host>:8585 ...
./java ... lotus.domino.setup.WizardManagerDomino -data /local/notesdata -listen 8585
Remote server setup enabled on port 8585.
The Domino setup server is now in listening mode.
```

出現少量 `Error - can't open /proc/sys/...` 警告屬正常且非致命 — container 為非 root，無法讀取 kernel tunables。

### 從這裡有兩條路徑

- **全新 domain 的第一台 server**（若你在做容器化，這較少見 — 通常 Domino 12+ 會改用 `OneTouch`）：以 Notes Admin client 連線至 port 8585 走「Set up first server」精靈。不在本 SOP 範圍內。
- **既有 domain 的 additional server**（推薦路徑）：請見 [ADDITIONAL-SERVER.md](ADDITIONAL-SERVER.md)。

---

## 5. 常見故障模式

請參閱 [TROUBLESHOOTING.md](TROUBLESHOOTING.md) 取得「症狀 → 診斷 → 修正」詳情。

優先檢查事項快速摘要：

| 症狀 | 第一個要檢查的事 |
|---|---|
| `docker build` 在 COPY 步驟結束 | 兩個 .tar 檔是否都已放入 build context？ |
| `docker build` 在 silent install 期間結束 | 以 `docker build --progress=plain` 重跑並檢查 stderr，或讀取 container 內的 `/tmp/nuish.err` |
| `docker run` 後 container 數秒內結束 | `docker logs domino9` — 可能是加密的 `server.id` 在等密碼 |
| Notes Admin client 出現 "Network Communication error" | 主機 port 8585 是否可達？在 Windows 用 `Test-NetConnection 127.0.0.1 -Port 8585` 測試 |
| HTTP 顯示 connection refused | Domino HTTP task 尚未啟動 — 等 60 秒或檢查 `docker logs domino9 \| grep HTTP` |
| WSL2 磁碟用盡 | `docker system prune -a`（注意：會連 image 一起移除）；可考慮 `wsl --shutdown` 並釋放 VHDX |

---

## 6. 備份與還原

### 該備份哪些東西

container 的 `/local/notesdata/` 目錄包含所有 Domino 狀態資料：

| 路徑 | 為何重要 |
|---|---|
| `notes.ini` | server 設定 |
| `server.id` | server 身分（切勿遺失） |
| `names.nsf` | Domino Directory（依 domain 大小 ~30-200 MB） |
| `log.nsf` | server log 資料庫 |
| `mail.box` | 收件郵件 queue |
| `admin4.nsf` | 管理請求 queue |
| `IBM_TECHNICAL_SUPPORT/` | NSD dump、crash 分析 |
| `*.id` 檔（cert.id、admin.id 若有） | 其他身分檔案 |
| 任何自訂 NSF / 信箱檔 | 使用者資料 |

### 對已停止 container 的資料 volume 製作快照

```bash
docker stop domino9
docker run --rm \
  -v domino9-data:/data \
  -v "$(pwd)":/backup \
  alpine \
  tar czf /backup/domino9-data-$(date +%Y%m%d).tar.gz -C /data .
docker start domino9
```

### 還原到全新主機

```bash
docker volume create domino9-data
docker run --rm \
  -v domino9-data:/data \
  -v /path/to/backup:/backup \
  alpine \
  tar xzf /backup/domino9-data-YYYYMMDD.tar.gz -C /data
docker run --rm --user root \
  -v domino9-data:/data \
  alpine \
  chown -R 1000:1000 /data

# Then run the container as in §4, but it will boot in CONFIGURED RUN mode
# (entrypoint detects notes.ini and skips setup listener)
docker run -d \
  --name domino9 \
  -p 1352:1352 -p 80:80 -p 8585:8585 \
  -v domino9-data:/local/notesdata \
  -e DOMINO_ID_PASSWORD='your-server.id-password' \
  domino9:9.0.1fp10
```

注意：image 內的 UID/GID 為 1000:1000（user `notes`、group `notes`）。當你執行 `tar xzf` 時，volume 內檔案的擁有者必須與此相符。上面的 `chown -R 1000:1000` 步驟即處理此事。

### Image 層級備份（將整個已 build image 匯出成 tarball）

用於主機間遷移或 DR 快照：

```bash
# Export
docker save domino9:9.0.1fp10 | gzip > domino9-9.0.1fp10-image.tgz

# Import on the new host
docker load -i domino9-9.0.1fp10-image.tgz
```

image tar 只包含不可變的 Docker image layers — **不**包含任何 data volume 內容。在新主機上還原需要 image tar **與** data-volume tar 兩者。

---

_BUILD.md 結束。domain-join 流程請繼續至 [ADDITIONAL-SERVER.md](ADDITIONAL-SERVER.md)。_
