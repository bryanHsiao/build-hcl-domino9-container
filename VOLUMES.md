# VOLUMES.md — Named volume vs bind mount for `/local/notesdata`

The examples in `BUILD.md`, `ADDITIONAL-SERVER.md`, and `DOMINOCTL.md` all use **Docker named volumes** (`docker volume create domino9-data`, `-v domino9-data:/local/notesdata`). That's the docker-idiomatic default and works fine.

But for **dev / test / single-host** scenarios — especially on Windows + WSL2 where you want to inspect / edit `notes.ini` or grab `IBM_TECHNICAL_SUPPORT/console.log` from Windows Explorer — a **bind mount** at `/local/notesdata` (the same path inside and outside the container) is materially nicer.

This page compares the two and gives a working bind-mount recipe.

## Quick comparison

| Aspect | Named volume | Bind mount |
|---|---|---|
| Docker idiom | ✅ Recommended default | ⚠️ Acceptable for dev/test |
| `docker run` portability across hosts | ✅ Volume name only, no path baked in | ❌ Embeds `/local/notesdata` host path |
| Permission isolation | ✅ Managed by docker daemon | ⚠️ Host UID/GID must match (1000:1000) |
| Direct file access from host | ❌ Need `sudo` into `/var/lib/docker/volumes/.../_data` | ✅ `cd /local/notesdata` works |
| **Windows Explorer access (WSL2)** | ❌ Buried under `\\wsl$\<distro>\var\lib\docker\...` requiring root | ✅ `\\wsl$\<distro>\local\notesdata` directly |
| Backup with plain `tar` | ❌ Need helper container (`docker run --rm -v vol:/data alpine tar ...`) | ✅ `tar czf backup.tgz -C /local/notesdata .` |
| Mental model for Domino admin | ⚠️ "Where did docker put it?" | ✅ "It's `/local/notesdata`, same as bare metal" |
| Risk of accidental host modification | ✅ Low (docker-only access) | ⚠️ Any host process with write access can change files |
| Production / cross-host deployment | ✅ Preferred | ❌ Path dependency is fragile |

**Quick rule:**

- Single dev/test host where YOU want to touch the data → **bind mount**
- CI, automated builds, multi-host clusters, "I just want to ship the container" → **named volume**

## Recipe — bind mount setup

This is the workflow this repo's maintainer uses on a personal Windows 11 + WSL2 dev machine.

### Prerequisites

- Container image already built or loaded (see `BUILD.md`)
- You're inside the WSL distro that runs Docker
- Your UNIX user inside the WSL distro is `uid 1000` (the default for the first user)

### Steps

```bash
# 1. Create host directory at /local/notesdata
sudo mkdir -p /local/notesdata
sudo chown 1000:1000 /local/notesdata
sudo chmod 700 /local/notesdata

# 2a. (First-time setup, fresh data) — just docker run, wizard will populate
docker run -d \
  --name domino9 \
  --hostname domino9 \
  --restart unless-stopped \
  -p 1352:1352 -p 80:80 -p 8585:8585 \
  -v /local/notesdata:/local/notesdata \
  domino9:9.0.1fp10

# 2b. (Restore from a saved data tar) — extract before docker run
#     If you have a backup tar from a previously configured server:
sudo tar xzf /path/to/notesdata-backup.tar.gz -C /local/notesdata
sudo chown -R 1000:1000 /local/notesdata
docker run -d \
  --name domino9 \
  --hostname domino9 \
  --restart unless-stopped \
  -p 1352:1352 -p 80:80 -p 8585:8585 \
  -v /local/notesdata:/local/notesdata \
  -e DOMINO_ID_PASSWORD='your-server.id-password' \
  domino9:9.0.1fp10

# 3. Verify
sleep 60
curl -sI http://localhost/
ls -la /local/notesdata | head -10
```

### From Windows Explorer (WSL2)

```
\\wsl$\<your-distro-name>\local\notesdata
```

For example: `\\wsl$\Ubuntu-domino9\local\notesdata`

You can browse, copy out logs, edit `notes.ini` directly — anything you'd do on a bare-metal Domino server.

### dominoctl config for bind mount

If you also use `dominoctl` (per `DOMINOCTL.md`), update `/etc/sysconfig/domino_container`:

```bash
CONTAINER_NAME=domino9
CONTAINER_HOSTNAME=domino9
IMAGE_NAME=domino9:9.0.1fp10
CONTAINER_PORTS="-p 1352:1352 -p 80:80 -p 8585:8585"
# Bind mount instead of named volume:
CONTAINER_VOLUMES="-v /local/notesdata:/local/notesdata"
CONTAINER_ENV_FILE=/etc/sysconfig/domino_env
DOMINO_SHUTDOWN_TIMEOUT=120
```

Everything else (`domino_env`, alias, etc.) stays the same as in `DOMINOCTL.md`.

## Migrating named volume → bind mount (or back)

### Named volume → bind mount

```bash
# 1. Stop container
docker stop domino9

# 2. Prepare host directory
sudo mkdir -p /local/notesdata
sudo chown 1000:1000 /local/notesdata
sudo chmod 700 /local/notesdata

# 3. Copy named volume content into the host directory
docker run --rm \
  -v domino9-data:/src:ro \
  -v /local/notesdata:/dst \
  alpine \
  sh -c "cd /src && tar cf - . | (cd /dst && tar xf -)"

# 4. Recreate container with bind mount
docker rm -f domino9
docker run -d \
  --name domino9 \
  -p 1352:1352 -p 80:80 -p 8585:8585 \
  -v /local/notesdata:/local/notesdata \
  -e DOMINO_ID_PASSWORD='your-server.id-password' \
  domino9:9.0.1fp10

# 5. After verifying it works, optionally remove the old volume
# docker volume rm domino9-data
```

### Bind mount → named volume

Reverse direction:

```bash
docker stop domino9
docker volume create domino9-data
docker run --rm \
  -v /local/notesdata:/src:ro \
  -v domino9-data:/dst \
  alpine \
  sh -c "cd /src && tar cf - . | (cd /dst && tar xf -)"
docker rm -f domino9
docker run -d --name domino9 \
  -p 1352:1352 -p 80:80 -p 8585:8585 \
  -v domino9-data:/local/notesdata \
  -e DOMINO_ID_PASSWORD='your-server.id-password' \
  domino9:9.0.1fp10
```

## What about backups?

Both approaches can be backed up cleanly:

```bash
# Named volume
docker run --rm \
  -v domino9-data:/data:ro \
  -v "$(pwd):/backup" \
  alpine \
  tar czf /backup/notesdata-$(date +%Y%m%d).tar.gz -C /data .

# Bind mount (stop container first to ensure consistent state)
docker stop domino9
sudo tar czf notesdata-$(date +%Y%m%d).tar.gz -C /local/notesdata .
docker start domino9
```

The resulting tarballs are interchangeable — you can restore a named-volume backup into a bind-mount setup or vice versa.

## What this maintainer actually uses

For day-to-day work on a single Windows 11 + WSL2 dev machine: **bind mount at `/local/notesdata`**. The Windows Explorer access alone is worth it for poking at logs and config files. The "real" production-grade portability of named volumes is irrelevant when there's only one host.

For the public-facing examples in `BUILD.md` etc. this repo still uses named volume as the default, because:

1. It works on every supported docker host (no path dependency)
2. It's the docker-recommended default
3. New users don't have to think about host-side directory permissions

This page exists so dev/test users can deliberately switch — knowing exactly what they're trading off.

---
---

# 繁體中文版

# VOLUMES.md — Named volume 還是 bind mount 來掛 `/local/notesdata`

`BUILD.md`、`ADDITIONAL-SERVER.md`、`DOMINOCTL.md` 內的範例都用 **Docker named volumes**（`docker volume create domino9-data`、`-v domino9-data:/local/notesdata`）。這是 docker 慣用做法、運作沒問題。

但對 **dev / test / 單 host** 情境 — 特別是 Windows + WSL2 想從 Windows 檔案總管直接看 `notes.ini`、撈 `IBM_TECHNICAL_SUPPORT/console.log` — **bind mount** 把 `/local/notesdata` 直接掛到 host 同名路徑會方便得多。

本頁比較兩者並提供可用的 bind mount recipe。

## 快速對照

| 角度 | Named volume | Bind mount |
|---|---|---|
| Docker 慣例 | ✅ 推薦預設 | ⚠️ dev/test 可接受 |
| `docker run` 跨 host 可攜性 | ✅ 只用 volume 名稱、不寫 host 路徑 | ❌ host 路徑 `/local/notesdata` 寫死 |
| Permission 隔離 | ✅ docker daemon 管理 | ⚠️ host UID/GID 必須對應（1000:1000） |
| 從 host 直接看檔 | ❌ 需 `sudo` 進 `/var/lib/docker/volumes/.../_data` | ✅ `cd /local/notesdata` 就行 |
| **Windows Explorer 看（WSL2）** | ❌ 埋在 `\\wsl$\<distro>\var\lib\docker\...` 還要 root | ✅ `\\wsl$\<distro>\local\notesdata` 直接看 |
| 用純 `tar` 備份 | ❌ 要 helper container（`docker run --rm -v vol:/data alpine tar ...`） | ✅ `tar czf backup.tgz -C /local/notesdata .` |
| Domino admin 心智模型 | ⚠️「docker 把它放哪了？」 | ✅「就是 `/local/notesdata`，跟 bare metal 一樣」 |
| Host 意外改檔風險 | ✅ 低（只有 docker 能碰） | ⚠️ host 上任何有寫權限的 process 都能動 |
| 生產 / 跨 host 部署 | ✅ 較佳 | ❌ 路徑相依不穩 |

**快速判斷準則：**

- 單 dev/test host、你想直接摸資料 → **bind mount**
- CI、自動化 build、多 host cluster、「我只想把 container ship 出去」 → **named volume**

## Recipe — bind mount 設定

本 repo 維護者在自己 Windows 11 + WSL2 dev 機器上就是用這套。

### 前置需求

- Image 已 build 好或 load 進來（見 `BUILD.md`）
- 你在跑 Docker 的那個 WSL distro 內
- 該 distro 的 UNIX 主用戶是 `uid 1000`（第一個建立的 user 預設值）

### 步驟

```bash
# 1. host 端建 /local/notesdata 目錄
sudo mkdir -p /local/notesdata
sudo chown 1000:1000 /local/notesdata
sudo chmod 700 /local/notesdata

# 2a. （全新設定、空資料）— 直接 docker run，wizard 會把它填滿
docker run -d \
  --name domino9 \
  --hostname domino9 \
  --restart unless-stopped \
  -p 1352:1352 -p 80:80 -p 8585:8585 \
  -v /local/notesdata:/local/notesdata \
  domino9:9.0.1fp10

# 2b. （從備份 tar 還原）— docker run 前先解進去
#     如果你有一份既有設定好的 server 備份 tar：
sudo tar xzf /path/to/notesdata-backup.tar.gz -C /local/notesdata
sudo chown -R 1000:1000 /local/notesdata
docker run -d \
  --name domino9 \
  --hostname domino9 \
  --restart unless-stopped \
  -p 1352:1352 -p 80:80 -p 8585:8585 \
  -v /local/notesdata:/local/notesdata \
  -e DOMINO_ID_PASSWORD='your-server.id-password' \
  domino9:9.0.1fp10

# 3. 驗證
sleep 60
curl -sI http://localhost/
ls -la /local/notesdata | head -10
```

### 從 Windows 檔案總管看（WSL2）

```
\\wsl$\<你的-distro-名稱>\local\notesdata
```

例如：`\\wsl$\Ubuntu-domino9\local\notesdata`

可以瀏覽、複製 log 出來、直接編輯 `notes.ini` — 像 bare-metal Domino server 一樣。

### bind mount 的 dominoctl 設定

如果你同時用 `dominoctl`（見 `DOMINOCTL.md`），把 `/etc/sysconfig/domino_container` 改成：

```bash
CONTAINER_NAME=domino9
CONTAINER_HOSTNAME=domino9
IMAGE_NAME=domino9:9.0.1fp10
CONTAINER_PORTS="-p 1352:1352 -p 80:80 -p 8585:8585"
# 改 bind mount，不用 named volume：
CONTAINER_VOLUMES="-v /local/notesdata:/local/notesdata"
CONTAINER_ENV_FILE=/etc/sysconfig/domino_env
DOMINO_SHUTDOWN_TIMEOUT=120
```

其他（`domino_env`、alias 等）跟 `DOMINOCTL.md` 一樣。

## 從 named volume 遷移到 bind mount（或反向）

### Named volume → bind mount

```bash
# 1. 停容器
docker stop domino9

# 2. host 端準備目錄
sudo mkdir -p /local/notesdata
sudo chown 1000:1000 /local/notesdata
sudo chmod 700 /local/notesdata

# 3. 把 named volume 內容搬進 host 目錄
docker run --rm \
  -v domino9-data:/src:ro \
  -v /local/notesdata:/dst \
  alpine \
  sh -c "cd /src && tar cf - . | (cd /dst && tar xf -)"

# 4. 砍 container，用 bind mount 重建
docker rm -f domino9
docker run -d \
  --name domino9 \
  -p 1352:1352 -p 80:80 -p 8585:8585 \
  -v /local/notesdata:/local/notesdata \
  -e DOMINO_ID_PASSWORD='your-server.id-password' \
  domino9:9.0.1fp10

# 5. 驗證 OK 後，舊 volume 可以砍掉釋出空間
# docker volume rm domino9-data
```

### Bind mount → named volume

反向流程：

```bash
docker stop domino9
docker volume create domino9-data
docker run --rm \
  -v /local/notesdata:/src:ro \
  -v domino9-data:/dst \
  alpine \
  sh -c "cd /src && tar cf - . | (cd /dst && tar xf -)"
docker rm -f domino9
docker run -d --name domino9 \
  -p 1352:1352 -p 80:80 -p 8585:8585 \
  -v domino9-data:/local/notesdata \
  -e DOMINO_ID_PASSWORD='your-server.id-password' \
  domino9:9.0.1fp10
```

## 備份呢？

兩種掛法都能乾淨備份：

```bash
# Named volume
docker run --rm \
  -v domino9-data:/data:ro \
  -v "$(pwd):/backup" \
  alpine \
  tar czf /backup/notesdata-$(date +%Y%m%d).tar.gz -C /data .

# Bind mount（先停容器確保一致性）
docker stop domino9
sudo tar czf notesdata-$(date +%Y%m%d).tar.gz -C /local/notesdata .
docker start domino9
```

產出的 tarball 兩種方式可互通 — 你可以把 named volume 的備份還原到 bind mount 環境，反之亦然。

## 本 repo 維護者實際用什麼

日常工作（單台 Windows 11 + WSL2 dev 機）：**bind mount 在 `/local/notesdata`**。光是 Windows 檔案總管能直接看就值得了，方便撈 log 跟改 config。named volume 那種「真正生產級可攜性」對只有一台 host 的情境不太相關。

公開 repo 內 `BUILD.md` 等檔案的對外範例還是維持 named volume 為預設，因為：

1. 在所有支援的 docker host 都能跑（無路徑相依）
2. 是 docker 官方建議的預設
3. 新手不用想 host 端目錄權限

本頁存在的目的就是讓 dev/test 使用者**有意識地**選擇切換 — 清楚知道在 trade 什麼。
