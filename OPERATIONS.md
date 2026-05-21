# OPERATIONS.md — Day-2 operations (start, stop, restart, status)

Once your container has been built and configured (`BUILD.md` and `ADDITIONAL-SERVER.md` done), daily operations are simple. This page consolidates the routine commands you'll use most.

## Prerequisites

You should already have:

- A Docker host running (Linux native, WSL2, or Docker Desktop)
- An image such as `domino9:9.0.1fp10` loaded
- A container such as `domino9` already created at least once via `docker run`
- A data volume such as `domino9-data` preserving your configured state
- (Optional) `dominoctl` installed per [DOMINOCTL.md](DOMINOCTL.md)

If any of the above is missing, start from [BUILD.md](BUILD.md) §1.

## With dominoctl (preferred)

```bash
domino status        # see whether container is running / exited / not-found
domino start         # docker start the existing container, wait for boot
domino stop          # graceful: server -q, then docker stop -t 120
domino restart       # stop + start
domino logs          # tail recent entrypoint + server output
domino bash          # shell into the container as `notes` user
```

A typical sequence after a host reboot:

```bash
domino status
# -> Status: exited (container exists, was stopped on host shutdown)

domino start
# -> container restarts, server boots ~60 seconds

sleep 60
curl -sI http://localhost/
# -> HTTP/1.1 200 OK, Server: Lotus-Domino
```

## Without dominoctl (raw docker commands)

```bash
# Status
docker ps -a --filter name=domino9 --format 'table {{.Names}}\t{{.Status}}\t{{.Ports}}'

# Start an already-existing container (keeps prior port/env config)
docker start domino9

# Stop gracefully (give Domino up to 120 seconds for server -q)
docker stop -t 120 domino9

# Restart
docker restart -t 120 domino9

# Tail logs
docker logs -f domino9

# Shell into container
docker exec -it -u notes domino9 bash

# Smoke test from host
sleep 60 && curl -sI http://localhost/
```

## After a host reboot

WSL2 distros and the Docker daemon do not start automatically on Windows reboot by default. To bring everything back:

```powershell
# In PowerShell (Windows side)
wsl -d Ubuntu-domino9-test -- bash -c "sudo service docker start && docker start domino9-test"
```

Or just:

```powershell
wsl -d Ubuntu-domino9-test
# Inside the distro:
docker start domino9-test
exit
```

On native Linux with systemd, `systemctl enable docker` makes Docker auto-start, and the container's restart policy (below) handles itself.

## Auto-restart container on Docker daemon start

If you want the container to come back automatically whenever the Docker daemon comes up (e.g., after `wsl --shutdown && wsl ...`, or system reboot on native Linux), update the restart policy:

```bash
docker update --restart=unless-stopped domino9
```

Options:

| Value | Behavior |
|---|---|
| `no` (default) | Never auto-restart |
| `on-failure` | Restart only if exit code != 0 |
| `unless-stopped` | Restart unless explicitly `docker stop`ped |
| `always` | Restart even after explicit `docker stop` (after daemon restart) |

`unless-stopped` is the usual choice — survives daemon restarts but respects an intentional stop.

## Server-side operations inside the container

Some Domino-specific operations need to happen inside the running container.

```bash
# Open a server console (read-only — see TROUBLESHOOTING note about stdin):
docker exec -it -u notes domino9 /opt/ibm/domino/bin/server -c "show server"

# Issue a one-off command:
docker exec -u notes domino9 /opt/ibm/domino/bin/server -c "show tasks"
docker exec -u notes domino9 /opt/ibm/domino/bin/server -c "load http"
docker exec -u notes domino9 /opt/ibm/domino/bin/server -c "tell http restart"

# Tail Domino log file (separate from `docker logs`)
docker exec -u notes domino9 tail -f /local/notesdata/IBM_TECHNICAL_SUPPORT/console.log
```

If you have `dominoctl` installed, equivalent forms:

```bash
domino bash             # then run server -c "..." inside
# (dominoctl 1.5.5 does not have a built-in pass-through for arbitrary
#  server commands — see DOMINOCTL.md "known limitations")
```

## Quick cheat sheet

| Goal | dominoctl | docker |
|---|---|---|
| Status | `domino status` | `docker ps -a --filter name=domino9` |
| Start | `domino start` | `docker start domino9` |
| Stop (graceful) | `domino stop` | `docker stop -t 120 domino9` |
| Restart | `domino restart` | `docker restart -t 120 domino9` |
| Logs (entrypoint) | `domino logs` | `docker logs -f domino9` |
| Shell as `notes` | `domino bash` | `docker exec -it -u notes domino9 bash` |
| Shell as `root` | `domino bash root` | `docker exec -it -u root domino9 bash` |
| Auto-restart policy | (use docker) | `docker update --restart=unless-stopped domino9` |
| Smoke test HTTP | `curl -sI http://localhost/` | same |

## When the container won't start

Quick checks before reaching for [TROUBLESHOOTING.md](TROUBLESHOOTING.md):

```bash
# 1. Last 50 lines of the entrypoint / server log
docker logs --tail 50 domino9

# 2. Was the container last killed by SIGTERM or did Domino exit?
docker inspect domino9 --format '{{.State.Status}}: {{.State.Error}} (exit {{.State.ExitCode}})'

# 3. Is the data volume present?
docker volume ls | grep domino9

# 4. Is host port 80 / 1352 / 8585 occupied by something else?
ss -ltn | grep -E ':80 |:1352 |:8585 '   # Linux
# or on Windows PowerShell:
#   Get-NetTCPConnection -LocalPort 80,1352,8585 -ErrorAction SilentlyContinue
```

Common one-line fixes:

| Symptom | Try |
|---|---|
| Container exits ~30s after start, log shows `Enter password` | Missing `-e DOMINO_ID_PASSWORD=...` — recreate container with env var |
| Port already in use | Stop the other process, OR recreate container with different host port mapping |
| `docker start` says "no such container" | The container was `docker rm`-ed. Recreate via the original `docker run` command (volume + image survive) |
| HTTP 200 OK but Notes Admin can't connect on 1352 | Check that 1352 is forwarded (`docker port domino9`); inside container, `load http` may not have loaded — try `domino bash` then `server -c "load http"` |

---
---

# 繁體中文版

# OPERATIONS.md — Day-2 維運（啟動、停止、重啟、看狀態）

容器一旦 build 並設定完成（`BUILD.md` 與 `ADDITIONAL-SERVER.md` 跑過了），daily ops 就很單純了。本頁把你最常用的例行指令整理在一起。

## 前置需求

你應該已經有：

- 一個跑中的 Docker host（原生 Linux、WSL2、或 Docker Desktop）
- 已 load 進來的 image，例如 `domino9:9.0.1fp10`
- 至少 `docker run` 建立過一次的 container，例如 `domino9`
- 保存設定狀態的 data volume，例如 `domino9-data`
- （選用）依 [DOMINOCTL.md](DOMINOCTL.md) 安裝好的 `dominoctl`

以上有任何缺漏，請回到 [BUILD.md](BUILD.md) §1。

## 用 dominoctl（推薦）

```bash
domino status        # 看 container 處於 running / exited / not-found
domino start         # docker start 既有 container，等 server boot
domino stop          # graceful：server -q 後 docker stop -t 120
domino restart       # stop + start
domino logs          # tail 最近的 entrypoint + server 輸出
domino bash          # 以 `notes` user 進 container shell
```

Host 重開機後典型流程：

```bash
domino status
# -> Status: exited（container 還在，只是 host 關機時被停掉了）

domino start
# -> container 重啟，server 約 60 秒內 boot 完

sleep 60
curl -sI http://localhost/
# -> HTTP/1.1 200 OK, Server: Lotus-Domino
```

## 不用 dominoctl（純 docker 指令）

```bash
# 狀態
docker ps -a --filter name=domino9 --format 'table {{.Names}}\t{{.Status}}\t{{.Ports}}'

# 啟動既有 container（保留先前的 port / env 設定）
docker start domino9

# Graceful stop（給 Domino 最多 120 秒跑 server -q）
docker stop -t 120 domino9

# 重啟
docker restart -t 120 domino9

# Tail logs
docker logs -f domino9

# 進 container shell
docker exec -it -u notes domino9 bash

# 從 host 端 smoke test
sleep 60 && curl -sI http://localhost/
```

## Host 重開機之後

WSL2 distro 與 Docker daemon 在 Windows 重開機後**預設不會自動啟動**。要把整套叫回來：

```powershell
# 在 PowerShell（Windows 端）
wsl -d Ubuntu-domino9-test -- bash -c "sudo service docker start && docker start domino9-test"
```

或者：

```powershell
wsl -d Ubuntu-domino9-test
# 進到 distro 後：
docker start domino9-test
exit
```

原生 Linux 有 systemd 的環境，`systemctl enable docker` 會讓 Docker 自啟，container 的 restart policy（見下）會自己處理。

## Docker daemon 啟動時自動帶起 container

如果你希望 docker daemon 一啟動 container 就跟著起來（例如 `wsl --shutdown && wsl ...` 之後、或原生 Linux 重開機後），改 restart policy：

```bash
docker update --restart=unless-stopped domino9
```

可選值：

| 值 | 行為 |
|---|---|
| `no`（預設） | 不會自動重啟 |
| `on-failure` | 只有 exit code != 0 時重啟 |
| `unless-stopped` | 除非你明確 `docker stop`，否則會重啟 |
| `always` | 連你 `docker stop` 過、daemon 重啟後還是重啟 |

實務上選 `unless-stopped`：daemon 重啟還活著、但尊重你刻意停的決定。

## Container 內部的 Domino 端操作

有些 Domino 特定操作要進到跑中的 container 裡做。

```bash
# 開一個 server console（read-only — 注意 TROUBLESHOOTING 提到 stdin 的限制）：
docker exec -it -u notes domino9 /opt/ibm/domino/bin/server -c "show server"

# 下一次性指令：
docker exec -u notes domino9 /opt/ibm/domino/bin/server -c "show tasks"
docker exec -u notes domino9 /opt/ibm/domino/bin/server -c "load http"
docker exec -u notes domino9 /opt/ibm/domino/bin/server -c "tell http restart"

# Tail Domino log 檔（與 `docker logs` 不同）
docker exec -u notes domino9 tail -f /local/notesdata/IBM_TECHNICAL_SUPPORT/console.log
```

裝了 `dominoctl` 的話對應寫法：

```bash
domino bash             # 進去後手動跑 server -c "..."
# （dominoctl 1.5.5 沒有對任意 server command 的內建 pass-through
#  — 見 DOMINOCTL.md「已知限制」）
```

## 速查表

| 目的 | dominoctl | docker |
|---|---|---|
| 看狀態 | `domino status` | `docker ps -a --filter name=domino9` |
| 啟動 | `domino start` | `docker start domino9` |
| Graceful stop | `domino stop` | `docker stop -t 120 domino9` |
| 重啟 | `domino restart` | `docker restart -t 120 domino9` |
| Logs（entrypoint） | `domino logs` | `docker logs -f domino9` |
| Shell（`notes`） | `domino bash` | `docker exec -it -u notes domino9 bash` |
| Shell（`root`） | `domino bash root` | `docker exec -it -u root domino9 bash` |
| Auto-restart policy | （用 docker） | `docker update --restart=unless-stopped domino9` |
| HTTP smoke test | `curl -sI http://localhost/` | 同左 |

## Container 起不來時

跳到 [TROUBLESHOOTING.md](TROUBLESHOOTING.md) 之前可先做的快速檢查：

```bash
# 1. entrypoint / server log 最後 50 行
docker logs --tail 50 domino9

# 2. Container 最後是被 SIGTERM 殺、還是 Domino 自己退出？
docker inspect domino9 --format '{{.State.Status}}: {{.State.Error}} (exit {{.State.ExitCode}})'

# 3. Data volume 還在嗎？
docker volume ls | grep domino9

# 4. Host port 80 / 1352 / 8585 被別的程式占用？
ss -ltn | grep -E ':80 |:1352 |:8585 '   # Linux
# 或 Windows PowerShell:
#   Get-NetTCPConnection -LocalPort 80,1352,8585 -ErrorAction SilentlyContinue
```

常見一行修法：

| 症狀 | 試試 |
|---|---|
| Container 啟動約 30 秒後 exit，log 顯示 `Enter password` | 缺 `-e DOMINO_ID_PASSWORD=...` — 帶 env var 重建 container |
| Port 已被占用 | 停掉另一個程式，或重建 container 改用不同的 host port mapping |
| `docker start` 回 "no such container" | Container 被 `docker rm` 了。用原來的 `docker run` 重建一次（volume 與 image 還在） |
| HTTP 200 OK 但 Notes Admin 連 1352 連不上 | 確認 1352 有 forward（`docker port domino9`）；container 內 `load http` 可能沒載 — 用 `domino bash` 進去跑 `server -c "load http"` |
