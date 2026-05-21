# ADDITIONAL-SERVER.md — Join a container to an existing Domino domain

This document covers the most realistic deployment scenario for containerized Domino 9: bringing up a new server to join an **existing** Domino domain (where you already have a directory, certifier ID, and admin user — typically managed by a colleague or a dedicated admin server).

If you want to set up the **first** server of a brand-new domain, see HCL documentation or use OneTouch JSON setup on Domino 12+ (not available on 9.x).

## Prerequisites

| Item | Notes |
|---|---|
| `BUILD.md` §1–§4 completed | Container running in `server -listen 8585` mode |
| **Existing Domino server reachable** | Hostname / IP, accepts NRPC on port 1352 |
| **Existing domain name** | E.g. `MyOrg` |
| **A pre-registered server.id for the new server** | Issued by your Domino admin using `Configuration → Registration → Server` against the existing server. Must include the new server's hierarchical name (e.g. `CN=NewServer/O=MyOrg`). |
| **The server.id's password** | Set by your admin during registration; given to you separately |
| **Admin credentials** | A Notes user with rights to register servers in the existing domain (your normal admin user is usually fine) |
| **HCL Notes Administrator client on a host that can reach the container's port 8585** | The wizard runs in the Java GUI of the Notes Admin app |

Substitute `<placeholders>` below with your actual values.

## Step 1 — Confirm the prerequisite server document exists

Ask your Domino admin to confirm that on the existing server's Domino Directory (`names.nsf`), there is already a Server document for the new server's hierarchical name.

If this step is skipped, the setup wizard will fail later with `Cannot find server in Domino directory`. Fixing it mid-wizard is possible but messy — better to verify up front.

## Step 2 — Container should be in listening mode

```bash
docker logs domino9 | grep "Remote server setup enabled"
# Expected: "Remote server setup enabled on port 8585."
```

If the container is not in this state, see `BUILD.md` §4.

## Step 3 — Stage the server.id inside the container

```bash
# Replace <path-to-your-server.id> with the file your admin gave you
docker cp <path-to-your-server.id> domino9:/local/notesdata/server.id
docker exec --user root domino9 chown notes:notes /local/notesdata/server.id
docker exec --user root domino9 chmod 600 /local/notesdata/server.id

# Verify
docker exec domino9 ls -la /local/notesdata/server.id
# Expected: -rw------- 1 notes notes <size> ... server.id
```

The container path `/local/notesdata/server.id` is what the setup wizard will look for.

## Step 4 — Find `serversetup.exe` on the Notes Admin client host

On Windows, the Notes Administrator client ships with a tool called `serversetup.exe` that talks to a Domino server in listen mode. Find it:

```powershell
Get-ChildItem -Path 'C:\Program Files (x86)\HCL', 'C:\Program Files\HCL', 'C:\Program Files (x86)\IBM', 'C:\Program Files\IBM' -Filter serversetup.exe -Recurse -ErrorAction SilentlyContinue | Select-Object FullName
```

Common locations:

- `C:\Program Files (x86)\HCL\Notes\serversetup.exe` (HCL-branded install)
- `C:\Program Files (x86)\IBM\Notes\serversetup.exe` (older IBM-branded install)

## Step 5 — Launch the remote setup wizard

> **Recommendation**: close the Notes / Admin client GUI first to avoid process conflicts during setup.

In PowerShell (substitute the path you found in step 4):

```powershell
& 'C:\Program Files (x86)\HCL\Notes\serversetup.exe' -remote 127.0.0.1:8585
```

(If you forwarded the container's 8585 to a different host port, use that.)

A Java Swing dialog titled **"Connect To Remote Domino Server"** appears. Confirm:

- Remote Host Address: `127.0.0.1` (or wherever your container is reachable)
- Port: `8585` (the host port mapped to container's 8585)
- Click **Ping** — should succeed
- Click **OK**

Expected next: **"Successfully located remote Domino server"** popup → click OK.

## Step 6 — Walk the wizard

The wizard pages and what to fill (Domino 9.0.1 FP10 specifically; order and exact text may vary slightly between FPs):

| Page | What to set |
|---|---|
| Welcome | Next |
| **Setup type** | **Set up an additional server (in an existing Domino domain)** |
| Use existing server.id | "Use an existing certified server ID file" → path = `/local/notesdata/server.id` (the container-side path) |
| Server name | Auto-populated from the `.id` file (e.g. `CN=YourServer/O=YourOrg`) |
| Domain name | `<your-existing-domain>` (must match exactly, case-sensitive) |
| Connect to existing server (hostname) | `<existing-domino-host>` (DNS name or IP reachable from the container) |
| Connect to existing server (CN) | `<existing-domino-server-CN>` (e.g. `CN=ExistingServer/O=YourOrg`) |
| Admin user name | Your domain admin's hierarchical name |
| Admin user password | Your admin's password |
| Server tasks to load at startup | At minimum check **HTTP** if you want browser access. Defaults are usually fine. |
| Make optional copies of ID files | The list is empty (no new IDs being created — they all exist in the existing domain). Leave the checkbox unchecked. Click Next. |
| Summary review | Verify: server name / domain / existing server / data dir = `/local/notesdata`. Click **Setup**. |

## Step 7 — Wait through `names.nsf` replication

The "Creating the Domino Directory for your domain" progress dialog will go from 0% → 100% over **5–15 minutes** depending on directory size. This is the wizard pulling `names.nsf` from the existing server.

Don't close the dialog mid-progress.

When it completes you'll see "Congratulations, Domino Server Setup is now complete!" → click **Finish**.

## Step 8 — Container needs to be restarted in configured mode

After Finish, the container's `server -listen` Java process exits, and so does the container (since that was its main process).

You also need to provide the `server.id` password to the next boot, otherwise Domino will block at the password prompt:

```bash
# Stop and remove (volume is preserved!)
docker rm -f domino9

# Restart with DOMINO_ID_PASSWORD env var
docker run -d \
  --name domino9 \
  --hostname domino9 \
  -p 1352:1352 -p 80:80 -p 8585:8585 \
  -v domino9-data:/local/notesdata \
  -e DOMINO_ID_PASSWORD='<your-server.id-password>' \
  domino9:9.0.1fp10
```

The entrypoint will now detect `Setup=` in `notes.ini` and boot in **CONFIGURED RUN** mode:

```
[entrypoint] ==== CONFIGURED RUN ====
[entrypoint] notes.ini has Setup= marker, launching server normally.
[entrypoint] Feeding server.id password from DOMINO_ID_PASSWORD env
```

## Step 9 — Verify the running server

```bash
# Wait ~60 seconds for all server tasks to start
docker logs domino9 | grep -E "Server: Started|Mail Router started|Database Server started" | tail -10
```

Expected:

```
Database Server started
Router: Mail Router started for domain <YOUR-DOMAIN>
HTTP Server: Started
LDAP Server: Started
IMAP Server: Started
POP3 Server: Started
```

Quick HTTP smoke test:

```bash
curl -sI http://localhost/
# Expected:
#   HTTP/1.1 200 OK
#   Server: Lotus-Domino
```

NRPC reachability (Notes client connection):

```bash
# From the same host
nc -z localhost 1352 && echo "OK 1352"
```

If both succeed, the additional server is fully operational.

## Step 10 — Optional: install `dominoctl` for daily ops

To run `domino start / stop / restart / status / bash / logs / inspect` instead of long `docker ...` invocations, see [DOMINOCTL.md](DOMINOCTL.md).

## Step 11 — Notes client connectivity: the NetAddress gotcha

After everything above is working, a Notes Administrator client connecting to the container will often hit:

```
找不到伺服器的路徑 / Server path not found
Please check your network or VPN connection. ...
```

**Even though**:

- HTTP (port 80) from a browser works
- `Test-NetConnection 127.0.0.1 -Port 1352` returns True
- The Domino server inside the container shows `Database Server started` and accepting NRPC

### Why this happens

HTTP (port 80) talks pure IP — `localhost` → 127.0.0.1, request goes through, no Domino Directory lookup. **Browser does not care what the server's hierarchical name is.**

NRPC (port 1352) is different:

1. The Notes client TCP-connects to `127.0.0.1:1352` ✓
2. The server replies during NRPC handshake: "I am `CN=YourServer/O=YourOrg`"
3. **The Notes client now looks up `YourServer/YourOrg` in its local `names.nsf`**
4. It finds the Server document (it's been replicated from the master long before)
5. Inside that Server document, the **`NetAddress` field** is `yourserver.yourorg.example.com` — the real corporate DNS name registered by your admin
6. The Notes client then "validates" the connection by trying to reach the server at the registered NetAddress
7. Your laptop's DNS resolves `yourserver.yourorg.example.com` to the real production IP (or fails entirely if you're off-VPN)
8. That real IP is **not** 127.0.0.1, so the validation fails
9. Notes reports "Server path not found"

This is a Domino design choice that protects against DNS hijacking but bites hard when you're intentionally running a container that *masquerades* as a domain member.

### Fix A — hosts file alias (simplest)

Edit `C:\Windows\System32\drivers\etc\hosts` (requires admin):

```
127.0.0.1   yourserver.yourorg.example.com
```

Use the **exact** hostname that's in your server's NetAddress field. Save.

Then in the Notes Admin client "Open Application" dialog, type the **hierarchical name** (`YourServer/YourOrg`) instead of `127.0.0.1`. Notes will:

1. Look up `YourServer/YourOrg` in `names.nsf` → find NetAddress `yourserver.yourorg.example.com`
2. DNS resolve via your edited hosts → 127.0.0.1
3. Connect to container ✓

### Fix B — Connection document in Notes client

In Notes Admin: File → Locations → edit your current location → add a Connection document:

| Field | Value |
|---|---|
| Server name | `YourServer/YourOrg` |
| Use the port | TCPIP |
| Destination server address | `127.0.0.1` |

This Connection document overrides the Server document's NetAddress for that specific server. Cleaner than editing the OS hosts file, but you have to remember to maintain it.

### Caveat

If the hostname you alias to 127.0.0.1 is the **same** as a server you also need to reach normally (e.g., the real production server with the same name), you can only use one at a time. The pragmatic fix: comment out the hosts line when you don't need the container, uncomment when you do.

For permanent mixed access, give the container a different hierarchical name (e.g., `YourServerTest/YourOrg` registered as a separate server doc) — that costs another `Configuration → Registration → Server` round-trip with your admin.

## Troubleshooting

| Symptom | Action |
|---|---|
| "Network Communication error" on Connect dialog | Verify host port matches `-p <host>:8585` mapping; verify TCP reachable via `Test-NetConnection` |
| Same dialog but error after clicking OK (not Ping) | Most likely the bundled J9 JVM OOM. This Dockerfile already patches it (`-Xmx512m`). If you still see it, see [TROUBLESHOOTING.md](TROUBLESHOOTING.md) §3. |
| Wizard says "Cannot find server in Domino directory" | The existing server's `names.nsf` does not have a Server document for the new server name. Have your admin pre-register it (step 1). |
| `names.nsf` replication appears to hang | Check directory size on the existing server; large directories (10000+ persons) can take 10–20 min. Look at `docker logs domino9` for replicate progress. |
| Wizard finishes but server keeps relaunching wizard on restart | This Dockerfile uses `^Setup=[0-9]` heuristic to detect setup-complete, which is correct for Domino 9 (no `ServerName=` line in notes.ini). If you still see this, manually check `docker exec domino9 grep "^Setup=" /local/notesdata/notes.ini` |
| Server starts but HTTP not listening | Check that `HTTP` is in the `ServerTasks=` line of `notes.ini`. If missing, `docker exec domino9 /opt/ibm/domino/bin/server -c "load http"` |
| Notes client "Server path not found" / 「找不到伺服器的路徑」 connecting to `127.0.0.1` (but HTTP works) | NRPC client follows the NetAddress in the server doc. See Step 11 above for the hosts-file fix or Connection-document workaround. |

See [TROUBLESHOOTING.md](TROUBLESHOOTING.md) for deeper diagnosis.

---
---

# 繁體中文版

# ADDITIONAL-SERVER.md — 把容器加入既有 Domino domain

本文件涵蓋 containerized Domino 9 最實際的部署情境：把一台新 server 加入**既有**的 Domino domain（你已經有 Domino Directory、certifier ID、admin 使用者 — 通常是由同事或專門的 admin server 在管理）。

如果你要從零建立**第一台**全新 domain 的 server，請參考 HCL 官方文件，或在 Domino 12+ 用 OneTouch JSON setup（9.x 不支援）。

## 前置需求

| 項目 | 備註 |
|---|---|
| `BUILD.md` §1–§4 已完成 | 容器以 `server -listen 8585` 模式運行中 |
| **可連線到既有的 Domino server** | Hostname / IP，1352 port 接受 NRPC |
| **既有 domain 名稱** | 例如 `MyOrg` |
| **已預先註冊好的新 server.id** | 由你的 Domino admin 在既有 server 上用 `Configuration → Registration → Server` 發行。必須包含新 server 的 hierarchical name（例如 `CN=NewServer/O=MyOrg`）。 |
| **server.id 的密碼** | 由 admin 在註冊時設定，另外給你 |
| **Admin 帳號** | 在既有 domain 內擁有 register server 權限的 Notes user（一般 admin user 通常就夠了） |
| **能連到容器 8585 port 的主機上裝有 HCL Notes Administrator client** | 設定 wizard 跑在 Notes Admin app 的 Java GUI 裡 |

下面的 `<placeholders>` 請換成你的實際值。

## Step 1 — 確認 server 文件前置條件已存在

請 Domino admin 確認既有 server 上的 Domino Directory（`names.nsf`）已經有對應新 server 的 hierarchical name 的 Server 文件。

如果跳過這步，setup wizard 會在後面失敗並顯示 `Cannot find server in Domino directory`。中途修正雖然可行但很麻煩 — 還是事前確認比較好。

## Step 2 — 容器應處於 listening 模式

```bash
docker logs domino9 | grep "Remote server setup enabled"
# Expected: "Remote server setup enabled on port 8585."
```

如果容器不在這個狀態，請見 `BUILD.md` §4。

## Step 3 — 把 server.id 放進容器內

```bash
# Replace <path-to-your-server.id> with the file your admin gave you
docker cp <path-to-your-server.id> domino9:/local/notesdata/server.id
docker exec --user root domino9 chown notes:notes /local/notesdata/server.id
docker exec --user root domino9 chmod 600 /local/notesdata/server.id

# Verify
docker exec domino9 ls -la /local/notesdata/server.id
# Expected: -rw------- 1 notes notes <size> ... server.id
```

容器內路徑 `/local/notesdata/server.id` 就是 setup wizard 會去找的位置。

## Step 4 — 在 Notes Admin client 主機上找到 `serversetup.exe`

在 Windows 上，Notes Administrator client 內建一個叫做 `serversetup.exe` 的工具，可以連到處於 listen 模式的 Domino server。找出它的位置：

```powershell
Get-ChildItem -Path 'C:\Program Files (x86)\HCL', 'C:\Program Files\HCL', 'C:\Program Files (x86)\IBM', 'C:\Program Files\IBM' -Filter serversetup.exe -Recurse -ErrorAction SilentlyContinue | Select-Object FullName
```

常見位置：

- `C:\Program Files (x86)\HCL\Notes\serversetup.exe`（HCL 品牌安裝版本）
- `C:\Program Files (x86)\IBM\Notes\serversetup.exe`（較舊的 IBM 品牌安裝版本）

## Step 5 — 啟動 remote setup wizard

> **建議**：先關掉 Notes / Admin client GUI，避免設定過程中發生 process 衝突。

在 PowerShell 內（路徑換成 step 4 找到的）：

```powershell
& 'C:\Program Files (x86)\HCL\Notes\serversetup.exe' -remote 127.0.0.1:8585
```

（如果你把容器的 8585 forward 到不同的 host port，請改用對應的 port。）

會跳出一個標題為 **"Connect To Remote Domino Server"** 的 Java Swing 對話框。確認：

- Remote Host Address: `127.0.0.1`（或你容器能被連到的位置）
- Port: `8585`（mapping 到容器 8585 的 host port）
- 點 **Ping** — 應該成功
- 點 **OK**

預期接著會出現：**"Successfully located remote Domino server"** popup → 點 OK。

## Step 6 — 走過 wizard

各頁面與填寫內容（針對 Domino 9.0.1 FP10；順序與精確文字可能在不同 FP 間略有差異）：

| 頁面 | 設定 |
|---|---|
| Welcome | Next |
| **Setup type** | **Set up an additional server (in an existing Domino domain)** |
| Use existing server.id | "Use an existing certified server ID file" → path = `/local/notesdata/server.id`（容器端路徑） |
| Server name | 從 `.id` 檔自動帶入（例如 `CN=YourServer/O=YourOrg`） |
| Domain name | `<your-existing-domain>`（必須完全一致，大小寫敏感） |
| Connect to existing server (hostname) | `<existing-domino-host>`（容器能連到的 DNS 名稱或 IP） |
| Connect to existing server (CN) | `<existing-domino-server-CN>`（例如 `CN=ExistingServer/O=YourOrg`） |
| Admin user name | 你 domain admin 的 hierarchical name |
| Admin user password | 你 admin 的密碼 |
| Server tasks to load at startup | 至少勾選 **HTTP** 如果你要瀏覽器存取。預設值通常夠用。 |
| Make optional copies of ID files | 清單是空的（沒有新 ID 被建立 — 全部都已存在於既有 domain）。checkbox 不要勾。點 Next。 |
| Summary review | 確認：server name / domain / existing server / data dir = `/local/notesdata`。點 **Setup**。 |

## Step 7 — 等待 `names.nsf` replication

「Creating the Domino Directory for your domain」的進度對話框會從 0% → 100%，依 Domino Directory 大小耗時 **5–15 分鐘**。這是 wizard 在從既有 server 拉 `names.nsf`。

進度跑到一半不要關掉對話框。

完成時會看到 "Congratulations, Domino Server Setup is now complete!" → 點 **Finish**。

## Step 8 — 容器需以 configured 模式重啟

按下 Finish 後，容器的 `server -listen` Java process 結束，容器也跟著結束（因為那是它的主 process）。

你還需要把 `server.id` 密碼提供給下次開機，否則 Domino 會卡在密碼提示：

```bash
# Stop and remove (volume is preserved!)
docker rm -f domino9

# Restart with DOMINO_ID_PASSWORD env var
docker run -d \
  --name domino9 \
  --hostname domino9 \
  -p 1352:1352 -p 80:80 -p 8585:8585 \
  -v domino9-data:/local/notesdata \
  -e DOMINO_ID_PASSWORD='<your-server.id-password>' \
  domino9:9.0.1fp10
```

entrypoint 現在會偵測到 `notes.ini` 內有 `Setup=`，進入 **CONFIGURED RUN** 模式：

```
[entrypoint] ==== CONFIGURED RUN ====
[entrypoint] notes.ini has Setup= marker, launching server normally.
[entrypoint] Feeding server.id password from DOMINO_ID_PASSWORD env
```

## Step 9 — 驗證運行中的 server

```bash
# Wait ~60 seconds for all server tasks to start
docker logs domino9 | grep -E "Server: Started|Mail Router started|Database Server started" | tail -10
```

預期：

```
Database Server started
Router: Mail Router started for domain <YOUR-DOMAIN>
HTTP Server: Started
LDAP Server: Started
IMAP Server: Started
POP3 Server: Started
```

HTTP 快速 smoke test：

```bash
curl -sI http://localhost/
# Expected:
#   HTTP/1.1 200 OK
#   Server: Lotus-Domino
```

NRPC 連通性（Notes client 連線）：

```bash
# From the same host
nc -z localhost 1352 && echo "OK 1352"
```

兩者都成功的話，additional server 就完全可用了。

## Step 10 — 選用：安裝 `dominoctl` 用於日常維運

要用 `domino start / stop / restart / status / bash / logs / inspect` 取代冗長的 `docker ...` 指令，請見 [DOMINOCTL.md](DOMINOCTL.md)。

## Step 11 — Notes client 連線：NetAddress gotcha

前面都跑完之後，用 Notes Administrator client 連 container 時很常會撞到：

```
找不到伺服器的路徑
請檢查您的網路或 VPN 連線。...
```

**即使**：

- 瀏覽器走 HTTP（port 80）能通
- `Test-NetConnection 127.0.0.1 -Port 1352` 回 True
- Container 內的 Domino server log 顯示 `Database Server started`、NRPC 在 listen

### 為什麼會這樣

HTTP（port 80）走純 IP — `localhost` → 127.0.0.1，連線過去就好，**不查 Domino Directory**。瀏覽器不在乎 server 的 hierarchical name 是什麼。

NRPC（port 1352）不一樣：

1. Notes client 對 `127.0.0.1:1352` TCP-connect ✓
2. NRPC handshake 時，server 回應「我是 `CN=YourServer/O=YourOrg`」
3. **Notes client 此刻去自己本機的 `names.nsf` 查 `YourServer/YourOrg`**
4. 找到 Server document（早就從 master 同步過來了）
5. 該 Server document 內的 **`NetAddress` 欄位**寫的是 `yourserver.yourorg.example.com` — admin 註冊時填的公司真實 DNS name
6. Notes client 接著**用註冊的 NetAddress 重新「驗證」連線**
7. 你筆電的 DNS 把 `yourserver.yourorg.example.com` 解析到真實 production IP（或斷 VPN 時根本解析不到）
8. 那個真實 IP **不是** 127.0.0.1，驗證失敗
9. Notes 報「找不到伺服器的路徑」

這是 Domino 為了防 DNS hijack 的設計，但你刻意跑容器假扮 domain 成員時就會被擋。

### 修法 A — hosts 檔別名（最簡單）

編輯 `C:\Windows\System32\drivers\etc\hosts`（需要 admin 權限），加一行：

```
127.0.0.1   yourserver.yourorg.example.com
```

用 server 的 NetAddress 欄位**確切**的 hostname。存檔。

然後 Notes Admin「開啟應用程式」對話框改打**hierarchical name**（`YourServer/YourOrg`）而非 `127.0.0.1`。Notes 會：

1. 去 `names.nsf` 找 `YourServer/YourOrg` → 找到 NetAddress `yourserver.yourorg.example.com`
2. 透過你修改過的 hosts 解析 → 127.0.0.1
3. 連到 container ✓

### 修法 B — Notes client 加 Connection document

Notes Admin → File → Locations → 編輯目前 location → 加一筆 Connection document：

| 欄位 | 值 |
|---|---|
| Server name | `YourServer/YourOrg` |
| Use the port | TCPIP |
| Destination server address | `127.0.0.1` |

這條 Connection document 會 override 該 server doc 內的 NetAddress。比改 OS hosts 乾淨，但要記得維護。

### 注意

如果你 alias 到 127.0.0.1 的 hostname 跟你**正常工作時也要連的真實 server**同名（例如真正的 production server），那兩者一次只能用一個。實務做法：不用 container 時把 hosts 那行 `#` 註解掉，要用時取消註解。

如果要長期混用，給 container 取**不同**的 hierarchical name（例如 `YourServerTest/YourOrg` 另外註冊一筆 server doc）— 這要再請 admin 跑一次 `Configuration → Registration → Server`。

## 疑難排解

| 症狀 | 處理 |
|---|---|
| Connect 對話框出現「Network Communication error」 | 確認 host port 對應的 `-p <host>:8585` mapping 正確；用 `Test-NetConnection` 確認 TCP 可達 |
| 同一對話框但點 OK 後（非 Ping）才報錯 | 多半是內建 J9 JVM OOM。本 Dockerfile 已經 patch（`-Xmx512m`）。如果仍出現，請見 [TROUBLESHOOTING.md](TROUBLESHOOTING.md) §3。 |
| Wizard 提示「Cannot find server in Domino directory」 | 既有 server 的 `names.nsf` 沒有對應新 server 名稱的 Server 文件。請 admin 預先註冊（step 1）。 |
| `names.nsf` replication 看起來卡住 | 檢查既有 server 上 Domino Directory 大小；大型 directory（10000+ persons）可能需要 10–20 分鐘。看 `docker logs domino9` 內 replicate 進度。 |
| Wizard 跑完，但重啟後 server 又重新跑 wizard | 本 Dockerfile 用 `^Setup=[0-9]` heuristic 偵測 setup-complete，這對 Domino 9 是正確的（notes.ini 內沒有 `ServerName=` 那行）。若仍如此，手動檢查 `docker exec domino9 grep "^Setup=" /local/notesdata/notes.ini` |
| Server 啟動但 HTTP 沒在聽 | 檢查 `notes.ini` 的 `ServerTasks=` 行是否包含 `HTTP`。沒有的話：`docker exec domino9 /opt/ibm/domino/bin/server -c "load http"` |
| Notes client 連 `127.0.0.1` 報「找不到伺服器的路徑」（但 HTTP 通） | NRPC client 會走 server doc 內的 NetAddress 重新驗證。見上方 Step 11 — 用 hosts 別名或 Connection document 修。 |

更深入的診斷見 [TROUBLESHOOTING.md](TROUBLESHOOTING.md)。
