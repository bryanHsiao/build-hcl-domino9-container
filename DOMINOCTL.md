# DOMINOCTL.md — Optional: manage the container via `dominoctl`

Once your container is running (via `BUILD.md` and optionally `ADDITIONAL-SERVER.md`), the day-to-day operations like `docker stop`, `docker start`, `docker exec ... bash`, `docker logs` can be wrapped behind a friendlier interface.

Daniel Nashed (Nash!Com) maintains `dominoctl` (file name: `domino_container`) in https://github.com/nashcom/domino-startscript — a single bash script that gives you systemd-service-like commands for any Domino container, including older 9.x ones.

After install:

```
domino start
domino stop          # graceful, waits for `server -q` then docker stop -t 120
domino restart
domino status
domino bash          # shell into container as notes user
domino bash root     # shell into container as root
domino logs          # entrypoint log
domino inspect       # detailed metadata (install jq for pretty output)
domino port          # show port mappings
```

It works against this repo's image with no changes to the image itself — purely a host-side wrapper.

## Install (Linux / WSL2 host)

Paste the following on the host, **not inside the container**. Substitute `<your-server.id-password>` and double-check the container/image names match yours.

```bash
# 1. Download dominoctl to /usr/local/bin
sudo curl -fsSL https://raw.githubusercontent.com/nashcom/domino-startscript/main/domino_container \
  -o /usr/local/bin/dominoctl
sudo chmod +x /usr/local/bin/dominoctl
dominoctl --version

# 2. Main config file — tells dominoctl which container + image to manage
sudo mkdir -p /etc/sysconfig
sudo tee /etc/sysconfig/domino_container > /dev/null <<'CFG'
CONTAINER_NAME=domino9
CONTAINER_HOSTNAME=domino9
IMAGE_NAME=domino9:9.0.1fp10
CONTAINER_PORTS="-p 1352:1352 -p 80:80 -p 8585:8585"
CONTAINER_VOLUMES="-v domino9-data:/local/notesdata"
CONTAINER_ENV_FILE=/etc/sysconfig/domino_env
DOMINO_SHUTDOWN_TIMEOUT=120
CFG

# 3. Env file — contains the server.id password
sudo tee /etc/sysconfig/domino_env > /dev/null <<'ENV'
DOMINO_ID_PASSWORD=<your-server.id-password>
ENV
# Permissions: 644 (NOT 600!) — dominoctl runs as your user, not root, and needs to read this file.
# The password is also visible via `docker inspect`, so 600 vs 644 doesn't actually add meaningful protection.
sudo chmod 644 /etc/sysconfig/domino_env

# 4. Convenience alias — type 'domino' instead of 'dominoctl'
echo 'alias domino=dominoctl' >> ~/.bashrc
source ~/.bashrc

# 5. (Optional) Install jq for prettier dominoctl inspect output
sudo apt-get install -y jq       # Ubuntu/Debian
# sudo yum install -y jq         # RHEL/CentOS/Rocky
```

## Verify

```bash
domino status
# Expected output: container name + "Status: running"

domino start
sleep 60
curl -sI http://localhost/
# Expected: HTTP/1.1 200 OK, Server: Lotus-Domino
```

## Two install pitfalls (worth knowing in advance)

These tripped up the original research and are now corrected in the install script above. Recognize them if you see something similar:

### Pitfall 1: `sudo bash` writes alias to wrong `.bashrc`

If you encapsulate the install in a script and run via `sudo bash install.sh`, the `~/.bashrc` inside the script resolves to **`/root/.bashrc`** because $HOME is `/root` under sudo. The alias never reaches your user's shell, and `domino status` returns `command not found`.

Workarounds:

- Add the alias step **outside** of the sudo'd script:
  ```bash
  sudo bash install-dominoctl.sh
  # Then, as your normal user:
  echo 'alias domino=dominoctl' >> ~/.bashrc && source ~/.bashrc
  ```
- Or detect `$SUDO_USER` inside the script and write to that user's `.bashrc`:
  ```bash
  TARGET_USER="${SUDO_USER:-$USER}"
  TARGET_HOME=$(getent passwd "$TARGET_USER" | cut -d: -f6)
  echo 'alias domino=dominoctl' | sudo -u "$TARGET_USER" tee -a "$TARGET_HOME/.bashrc"
  ```

### Pitfall 2: `/etc/sysconfig/domino_env` with mode 600

You might be tempted to `chmod 600` the env file to "protect" the password. **Don't.** `dominoctl` runs as your normal user, not root. It reads the env file directly (not via docker daemon) to pass it via `--env-file` to `docker run`. With mode 600, dominoctl prints:

```
Info: Cannot read configured environment file [/etc/sysconfig/domino_env]!
```

and silently skips `--env-file`. The container starts without `DOMINO_ID_PASSWORD` → Domino blocks at the password prompt (see `TROUBLESHOOTING.md` §5).

Use mode `644`. The password is already visible via `docker inspect` to anyone with docker daemon access, so the threat model 600 protects against doesn't really exist.

## Known limitations against this image

| Command | Works? | Notes |
|---|---|---|
| `domino start / stop / restart / status` | ✅ | These are pure `docker start/stop/...` invocations |
| `domino bash` / `bash root` | ✅ | `docker exec` into the container |
| `domino logs` / `inspect` / `port` | ✅ | Read-only docker queries |
| `domino console` | ⚠️ Partial | `dominoctl console` is `docker attach`. You'll see Domino server output, but stdin is not connected — you can't type commands at the console. To do that you'd need nashcom's `rc_domino` inside the image, which is not in this Dockerfile. Workaround: `domino bash` then `/opt/ibm/domino/bin/server -c "show server"` etc. |
| `domino domino <cmd>` (pass-through) | ❌ | Needs `rc_domino` inside the image. Not present. See "future work" below. |
| `domino setup` (OneTouch JSON) | ❌ | OneTouch is a Domino 12+ feature. Not applicable to 9.x. |

### Port mapping pitfall

`dominoctl start` is just `docker start`. It uses the port mapping from the **first** `docker run` that created the container. **Changing `CONTAINER_PORTS` in the config does not affect a container that already exists.**

To change port mappings:

```bash
dominoctl stop
dominoctl remove                 # or: docker rm -f domino9
# Then manually docker run with new ports — dominoctl 1.5.5 has no
# "create container from config" subcommand:
docker run -d --name domino9 --hostname domino9 \
  -p 1352:1352 -p <new-port>:80 -p 8585:8585 \
  -v domino9-data:/local/notesdata \
  --env-file /etc/sysconfig/domino_env \
  domino9:9.0.1fp10
# Subsequent dominoctl start/stop/restart inherit the new mapping
```

## Future improvements (out of scope for this repo)

To unlock `domino console` and `domino <cmd>`, the right path is to install nashcom's `rc_domino` script **inside** the image and switch the entrypoint to call it. This would also bring graceful start/stop hooks, FIFO console, scheduled NSD, etc. Roughly:

```dockerfile
RUN curl -fsSL https://github.com/nashcom/domino-startscript/archive/refs/heads/main.tar.gz \
    | tar xz -C /tmp \
 && /tmp/domino-startscript-main/install_script
```

(Subject to that script's prerequisites and the HCL EULA.)

PRs welcome.

---
---

# 繁體中文版

# DOMINOCTL.md — 選用：用 `dominoctl` 管理 container

當你的 container 已透過 `BUILD.md`（以及選擇性的 `ADDITIONAL-SERVER.md`）跑起來之後，daily ops 例如 `docker stop`、`docker start`、`docker exec ... bash`、`docker logs` 等指令可以包裝成更友善的介面。

Daniel Nashed（Nash!Com）在 https://github.com/nashcom/domino-startscript 維護 `dominoctl`（檔名為 `domino_container`）— 一個單一 bash script，能為任何 Domino container（包含老的 9.x）提供類似 systemd service 的指令。

安裝完後：

```
domino start
domino stop          # graceful，會等 `server -q` 跑完再 docker stop -t 120
domino restart
domino status
domino bash          # 以 notes user 身分進入 container shell
domino bash root     # 以 root 身分進入 container shell
domino logs          # entrypoint log
domino inspect       # 詳細 metadata（建議裝 jq 以取得格式化輸出）
domino port          # 顯示 port mapping
```

它能直接套用在本 repo 的 image 上、不必動 image 本身 — 純粹是 host 端 wrapper。

## 安裝（Linux / WSL2 host）

下列指令貼在 host 上執行，**不要在 container 內跑**。請把 `<your-server.id-password>` 換成你的密碼，並再次確認 container/image 名稱跟你的環境一致。

```bash
# 1. Download dominoctl to /usr/local/bin
sudo curl -fsSL https://raw.githubusercontent.com/nashcom/domino-startscript/main/domino_container \
  -o /usr/local/bin/dominoctl
sudo chmod +x /usr/local/bin/dominoctl
dominoctl --version

# 2. Main config file — tells dominoctl which container + image to manage
sudo mkdir -p /etc/sysconfig
sudo tee /etc/sysconfig/domino_container > /dev/null <<'CFG'
CONTAINER_NAME=domino9
CONTAINER_HOSTNAME=domino9
IMAGE_NAME=domino9:9.0.1fp10
CONTAINER_PORTS="-p 1352:1352 -p 80:80 -p 8585:8585"
CONTAINER_VOLUMES="-v domino9-data:/local/notesdata"
CONTAINER_ENV_FILE=/etc/sysconfig/domino_env
DOMINO_SHUTDOWN_TIMEOUT=120
CFG

# 3. Env file — contains the server.id password
sudo tee /etc/sysconfig/domino_env > /dev/null <<'ENV'
DOMINO_ID_PASSWORD=<your-server.id-password>
ENV
# Permissions: 644 (NOT 600!) — dominoctl runs as your user, not root, and needs to read this file.
# The password is also visible via `docker inspect`, so 600 vs 644 doesn't actually add meaningful protection.
sudo chmod 644 /etc/sysconfig/domino_env

# 4. Convenience alias — type 'domino' instead of 'dominoctl'
echo 'alias domino=dominoctl' >> ~/.bashrc
source ~/.bashrc

# 5. (Optional) Install jq for prettier dominoctl inspect output
sudo apt-get install -y jq       # Ubuntu/Debian
# sudo yum install -y jq         # RHEL/CentOS/Rocky
```

## 驗證

```bash
domino status
# 預期輸出：container 名稱 + "Status: running"

domino start
sleep 60
curl -sI http://localhost/
# 預期：HTTP/1.1 200 OK，Server: Lotus-Domino
```

## 兩個安裝踩坑（事先知道有幫助）

下列兩個坑曾在原始研究過程中絆住我們，現已在上面的安裝步驟中修正。如果你看到類似症狀，能立刻認出來：

### 坑 1：`sudo bash` 把 alias 寫到錯的 `.bashrc`

如果你把安裝步驟包成一個 script、然後用 `sudo bash install.sh` 執行，script 內的 `~/.bashrc` 會被解析成 **`/root/.bashrc`**，因為 sudo 環境下 $HOME 是 `/root`。alias 永遠進不到你自己 user 的 shell，於是 `domino status` 回應 `command not found`。

解法：

- 把 alias 步驟拉到 sudo'd script **外面**：
  ```bash
  sudo bash install-dominoctl.sh
  # 然後改用你自己的 normal user：
  echo 'alias domino=dominoctl' >> ~/.bashrc && source ~/.bashrc
  ```
- 或在 script 內偵測 `$SUDO_USER` 並寫到那個 user 的 `.bashrc`：
  ```bash
  TARGET_USER="${SUDO_USER:-$USER}"
  TARGET_HOME=$(getent passwd "$TARGET_USER" | cut -d: -f6)
  echo 'alias domino=dominoctl' | sudo -u "$TARGET_USER" tee -a "$TARGET_HOME/.bashrc"
  ```

### 坑 2：`/etc/sysconfig/domino_env` 設成 mode 600

你可能會想「保護密碼」而 `chmod 600` 這個 env 檔。**別這樣做。** `dominoctl` 是以你的 normal user 身分執行、不是 root。它會直接讀 env 檔（不是透過 docker daemon）再以 `--env-file` 傳給 `docker run`。檔案是 600 時，dominoctl 會印：

```
Info: Cannot read configured environment file [/etc/sysconfig/domino_env]!
```

並靜默跳過 `--env-file`。container 啟動時拿不到 `DOMINO_ID_PASSWORD` → Domino 卡在密碼輸入提示（參見 `TROUBLESHOOTING.md` §5）。

請用 mode `644`。密碼本來就能透過 `docker inspect` 被有 docker daemon 權限的人看到，所以 600 想防的威脅模型實際上並不存在。

## 對本 image 的已知限制

| 指令 | 可用？ | 備註 |
|---|---|---|
| `domino start / stop / restart / status` | ✅ | 純粹是 `docker start/stop/...` 呼叫 |
| `domino bash` / `bash root` | ✅ | `docker exec` 進入 container |
| `domino logs` / `inspect` / `port` | ✅ | 唯讀的 docker 查詢 |
| `domino console` | ⚠️ 部分可用 | `dominoctl console` 是 `docker attach`。你會看到 Domino server 輸出，但 stdin 沒接上 — 無法在 console 打指令。要做到那樣得在 image 內裝 nashcom 的 `rc_domino`，本 Dockerfile 沒包含。Workaround：`domino bash` 後執行 `/opt/ibm/domino/bin/server -c "show server"` 之類。|
| `domino domino <cmd>`（pass-through） | ❌ | 需要 image 內有 `rc_domino`，目前沒有。詳見下面 "future work"。|
| `domino setup`（OneTouch JSON） | ❌ | OneTouch 是 Domino 12+ 的功能。對 9.x 不適用。|

### Port mapping 踩坑

`dominoctl start` 只是 `docker start`，它沿用建立 container 時**第一次** `docker run` 的 port mapping。**改 config 內的 `CONTAINER_PORTS` 對已存在的 container 沒有任何效果。**

要改 port mapping：

```bash
dominoctl stop
dominoctl remove                 # or: docker rm -f domino9
# Then manually docker run with new ports — dominoctl 1.5.5 has no
# "create container from config" subcommand:
docker run -d --name domino9 --hostname domino9 \
  -p 1352:1352 -p <new-port>:80 -p 8585:8585 \
  -v domino9-data:/local/notesdata \
  --env-file /etc/sysconfig/domino_env \
  domino9:9.0.1fp10
# Subsequent dominoctl start/stop/restart inherit the new mapping
```

## 未來可考慮的強化（不在本 repo 範圍內）

要解鎖 `domino console` 與 `domino <cmd>`，正確路徑是在 image **內部**安裝 nashcom 的 `rc_domino` script、並把 entrypoint 改成呼叫它。這同時也會帶來 graceful 啟停 hook、FIFO console、排程 NSD 等等。大致長這樣：

```dockerfile
RUN curl -fsSL https://github.com/nashcom/domino-startscript/archive/refs/heads/main.tar.gz \
    | tar xz -C /tmp \
 && /tmp/domino-startscript-main/install_script
```

（前提是該 script 的先決條件與 HCL EULA 允許。）

歡迎 PR。
