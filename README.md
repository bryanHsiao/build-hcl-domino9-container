# build-hcl-domino9-container

> **Self-build an HCL Domino 9.0.x container image** on RHEL UBI 7, validated to run in WSL2 + Docker Engine.

Verified target: **HCL Domino 9.0.1 FP10** (the final 9.x release).

---

## A note on the brand: IBM vs HCL

The 9.0.x series was developed under **IBM** (base 9.0.1 shipped in 2013, FP10 in 2018). The binaries in this image still print `IBM Domino (r) Server` on startup, and the on-disk install paths use `/opt/ibm/domino/...` — that is historically accurate and unchanged by anything in this repo.

**HCL Technologies acquired the Notes/Domino product line from IBM in 2019.** Since then, all entitlements, FlexNet downloads, EULA, support contracts, and product documentation for Domino 9 (and every version since) are administered by HCL. The 9.x binary itself was never rebranded — but the *ecosystem around it* (where you get installers, who you call for support, who maintains fixes for newer versions) is entirely HCL.

This repo's name uses **"hcl-domino9"** to align with that current ecosystem: if you are reading this and thinking about deploying Domino 9, you almost certainly hold an HCL entitlement (not a residual IBM one) and will interact with HCL's portals. The repo is *about* HCL-era Domino 9 operation, even though the *artifact* (the binary itself) is from the IBM era.

---

## Why this repo exists

HCL only ships official container images for Domino 10.0.1 FP3 and newer. For organizations still running Domino 9.x and wanting to containerize for Dev/Test, migration rehearsal, or legacy-server preservation, there is no official path.

This repository documents the complete, working procedure to:

1. Build a container image of Domino 9.0.1 FP10 from HCL's silent installer
2. Boot it in `server -listen` mode for first-time Notes Admin setup
3. Join the container to an existing Domino domain as an additional server
4. Run it as a normal Domino server with HTTP / NRPC / LDAP / IMAP / POP3 / SMTP

The procedure was developed through ~20 build iterations on Windows 11 + WSL2 + Docker Engine 29.5.2 and patched against **five distinct pitfalls** that are not obvious from HCL's official documentation alone.

⚠ **Read [DISCLAIMER.md](DISCLAIMER.md) first.** You must have your own HCL Domino 9 entitlement and installer media. This repo does not distribute HCL software.

## Documentation map

| File | What's in it |
|---|---|
| [DISCLAIMER.md](DISCLAIMER.md) | HCL EULA, support boundary, scope of MIT license, EOM/EOS dates |
| [BUILD.md](BUILD.md) | Step-by-step build SOP: environment, installer media, `docker build`, first launch |
| [ADDITIONAL-SERVER.md](ADDITIONAL-SERVER.md) | Driving the Notes Admin setup wizard to join a container into an existing Domino domain |
| [OPERATIONS.md](OPERATIONS.md) | Day-2 ops: start / stop / restart / status / logs / auto-restart on host reboot (with and without `dominoctl`) |
| [TROUBLESHOOTING.md](TROUBLESHOOTING.md) | The five non-obvious pitfalls already patched in this Dockerfile (read this even if you don't hit problems — it explains why the Dockerfile looks the way it does) |
| [DOMINOCTL.md](DOMINOCTL.md) | Optional: install Daniel Nashed's `dominoctl` host-side wrapper for `domino start / stop / status / restart` |
| [BASE-AND-FP-LAYERS.md](BASE-AND-FP-LAYERS.md) | Alternative: build a 9.0.1 base image, then apply Fix Pack as a separate layer (recommended for testing multiple FPs from one base) |
| `dockerfiles/domino9.0.1-fp10-ubi7/` | Recommended: one-shot 9.0.1 + FP10 in a single image |
| `dockerfiles/domino9.0.1-base-ubi7/` | Alternative: 9.0.1 base only, no FP |
| `dockerfiles/domino9.0.1-fp10-on-base/` | Alternative: FP10 layered on top of a `domino9:9.0.1` image |

## TL;DR for someone who already knows Domino

```bash
# 1. Get installer media from HCL FlexNet (your responsibility)
cd dockerfiles/domino9.0.1-fp10-ubi7
cp ~/Downloads/DOMINO_9.0.1_64_BIT_LIN_XS_EN.tar  .
cp ~/Downloads/domino901FP10_linux64_x86.tar       .

# 2. Build
docker build -t domino9:9.0.1fp10 .

# 3. Run (fresh — setup wizard mode)
docker volume create domino9-data
docker run -d --name domino9 \
  -p 1352:1352 -p 80:80 -p 8585:8585 \
  -v domino9-data:/local/notesdata \
  domino9:9.0.1fp10

# 4. From a Notes Admin client on the host:
#    serversetup.exe -remote 127.0.0.1:8585
#    -> walk through setup wizard

# 5. Stop, remove, restart with server.id password
docker rm -f domino9
docker run -d --name domino9 \
  -p 1352:1352 -p 80:80 -p 8585:8585 \
  -v domino9-data:/local/notesdata \
  -e DOMINO_ID_PASSWORD='your-server.id-password' \
  domino9:9.0.1fp10

# 6. Verify
curl -sI http://localhost/
# HTTP/1.1 200 OK
# Server: Lotus-Domino
```

For the full walkthrough see [BUILD.md](BUILD.md) and [ADDITIONAL-SERVER.md](ADDITIONAL-SERVER.md).

## The five pitfalls already patched in this Dockerfile

The Dockerfile here looks the way it does because of these. See [TROUBLESHOOTING.md](TROUBLESHOOTING.md) for full root-cause analysis:

1. **RHEL UBI 7 doesn't include `hostname`** — `install.pl` triggers an `Undefined subroutine &DingDong::out` Perl error. Fix: `yum install hostname`.
2. **Fix Pack installer rejects `-silent`** — it uses `-script <file>` instead. Fix: drop `-silent` for FP install step.
3. **Bundled IBM J9 JVM has too small default heap** — Notes Admin client connection to setup wizard triggers `java.lang.OutOfMemoryError`. Fix: `sed -i` patch `serversetup` to add `-Xmx512m -Xms128m`.
4. **`notes.ini` has no `ServerName=` line in Domino 9** — entrypoint heuristic must use `^Setup=[0-9]` instead to detect "setup complete".
5. **Password-protected `server.id` hangs server boot** — need to pipe password to `server` via stdin. Fix: `DOMINO_ID_PASSWORD` env var honored by entrypoint.

## What's verified

| Aspect | Status |
|---|---|
| `docker build` on Windows 11 + WSL2 + Docker Engine 29.5.2 | ✅ Image size 1.48 GB |
| Container starts in setup-listener mode | ✅ Port 8585 |
| Notes Admin client `serversetup -remote` completes wizard | ✅ |
| Additional-server setup against existing Domino domain | ✅ `names.nsf` replication ~5-15 min |
| Container boots in normal mode after `DOMINO_ID_PASSWORD` | ✅ All tasks Started |
| HTTP 200 from host browser | ✅ `Server: Lotus-Domino` |
| Image portability (`docker save` → load on fresh distro) | ✅ ~6 minutes end-to-end |
| RHEL UBI 8 secondary build | ❌ Documented as incompatible — see TROUBLESHOOTING.md §6 |

## Build environment used during development

- Host: Windows 11
- WSL: WSL2 with isolated Ubuntu 24.04 LTS distro
- Docker: Docker Engine 29.5.2 (not Docker Desktop, though Docker Desktop should also work)
- Target image: `domino9:9.0.1fp10` (1.48 GB)

For other host environments (native Linux, Mac with Docker Desktop, etc.) the Dockerfile itself should be portable; the host-level prerequisites listed in [BUILD.md](BUILD.md) §1 may need adjusting.

## Status

Single maintainer, hobby / internal-research origin. PRs accepted but no SLA. The maintainer's primary use case is internal Dev/Test with Domino 9.0.1 FP10 — issues with other 9.0.x sub-versions may receive best-effort guidance only.

## License

MIT — for the scripts and documentation in this repository.

See [LICENSE](LICENSE). HCL Domino itself is **not** covered.

---
---

# 繁體中文版

> **在 RHEL UBI 7 上自建 HCL Domino 9.0.x 的 container image**，已於 WSL2 + Docker Engine 完成驗證。

實機驗證版本：**HCL Domino 9.0.1 FP10**（9.x 系列最後一版）。

---

## 關於品牌：IBM vs HCL

Domino 9.0.x 是 **IBM 時代**的產品（9.0.1 base 於 2013 釋出、FP10 於 2018 釋出）。此 image 內的 binary 啟動 log 仍會印 `IBM Domino (r) Server`，安裝路徑也是 `/opt/ibm/domino/...` — 這是歷史事實，本 repo 沒改任何東西。

**HCL Technologies 在 2019 年從 IBM 手中收購了 Notes/Domino 產品線。** 自此之後，Domino 9（以及後續所有版本）的 entitlement、FlexNet 下載、EULA、support 合約、產品文件全部由 HCL 管理。9.x 的 binary 本身沒有被重新 brand — 但**圍繞它的整個生態系**（去哪拿安裝媒體、找誰報問題、誰維護新版本修補）完完全全是 HCL。

本 repo 名字用 **「hcl-domino9」**就是為了對齊現任生態系：如果你今天想部署 Domino 9，你手上的 entitlement 幾乎一定是 HCL 給的（不是 IBM 殘留的），會去操作的也是 HCL 的入口網站。Repo 描述的是 **HCL 時代的 Domino 9 維運作業**，雖然 *artifact 本身*（binary）來自 IBM 時代。

---

## 這個 repo 存在的原因

HCL 從 Domino 10.0.1 FP3 起才提供官方 container image。對於還在跑 Domino 9.x 並想做 Dev/Test 容器化、升級演練、或保留 legacy server 的組織來說，沒有官方路線。

本 repo 完整記錄一條可運作的步驟：

1. 從 HCL silent installer build 出 Domino 9.0.1 FP10 的 container image
2. 啟動為 `server -listen` 模式以便 Notes Admin client 跑首次設定
3. 透過 setup wizard 把容器加入既有的 Domino domain（additional server 流程）
4. 以正常 server 模式運行 HTTP / NRPC / LDAP / IMAP / POP3 / SMTP

整個流程經過 ~20 次 build 迭代於 Windows 11 + WSL2 + Docker Engine 29.5.2 上完成驗證，並針對 HCL 官方文件未明確提及的**五個非顯而易見的踩坑**做了 patch。

⚠ **先讀 [DISCLAIMER.md](DISCLAIMER.md)。** 你必須擁有自己的 HCL Domino 9 entitlement 與安裝媒體。本 repo 不發行任何 HCL 軟體。

## 文件導覽

| 檔案 | 內容 |
|---|---|
| [DISCLAIMER.md](DISCLAIMER.md) | HCL EULA、support boundary、MIT license 涵蓋範圍、EOM/EOS 日期 |
| [BUILD.md](BUILD.md) | 逐步 build SOP：環境、安裝媒體、`docker build`、首次啟動 |
| [ADDITIONAL-SERVER.md](ADDITIONAL-SERVER.md) | 操作 Notes Admin setup wizard 把容器加入既有 Domino domain |
| [OPERATIONS.md](OPERATIONS.md) | Day-2 維運：啟動 / 停止 / 重啟 / 狀態 / logs / host 重開機後自動帶起（含 `dominoctl` 與純 docker 兩種寫法） |
| [TROUBLESHOOTING.md](TROUBLESHOOTING.md) | 本 Dockerfile 已 patched 的五大踩坑（即使你沒遇到問題也建議讀，解釋 Dockerfile 為什麼長這樣） |
| [DOMINOCTL.md](DOMINOCTL.md) | 選用：安裝 Daniel Nashed 的 `dominoctl` host 端 wrapper，可用 `domino start / stop / status / restart` |
| [BASE-AND-FP-LAYERS.md](BASE-AND-FP-LAYERS.md) | 替代做法：先 build 9.0.1 base image，再以獨立 layer 套用 Fix Pack（適合需要從同一 base 測多個 FP 的場景） |
| `dockerfiles/domino9.0.1-fp10-ubi7/` | 推薦：一次 build 出含 9.0.1 + FP10 的單一 image |
| `dockerfiles/domino9.0.1-base-ubi7/` | 替代：只裝 9.0.1 base、不含 FP |
| `dockerfiles/domino9.0.1-fp10-on-base/` | 替代：將 FP10 以 layered image 形式疊在 `domino9:9.0.1` 上面 |

## TL;DR（給已經熟悉 Domino 的人）

```bash
# 1. 從 HCL FlexNet 取得安裝媒體（你的責任）
cd dockerfiles/domino9.0.1-fp10-ubi7
cp ~/Downloads/DOMINO_9.0.1_64_BIT_LIN_XS_EN.tar  .
cp ~/Downloads/domino901FP10_linux64_x86.tar       .

# 2. Build
docker build -t domino9:9.0.1fp10 .

# 3. 啟動（全新 — 進入 setup wizard 模式）
docker volume create domino9-data
docker run -d --name domino9 \
  -p 1352:1352 -p 80:80 -p 8585:8585 \
  -v domino9-data:/local/notesdata \
  domino9:9.0.1fp10

# 4. 從本機的 Notes Admin client 執行：
#    serversetup.exe -remote 127.0.0.1:8585
#    → 走完 setup wizard

# 5. 停掉、移除、帶 server.id 密碼重啟
docker rm -f domino9
docker run -d --name domino9 \
  -p 1352:1352 -p 80:80 -p 8585:8585 \
  -v domino9-data:/local/notesdata \
  -e DOMINO_ID_PASSWORD='你的-server.id-密碼' \
  domino9:9.0.1fp10

# 6. 驗證
curl -sI http://localhost/
# HTTP/1.1 200 OK
# Server: Lotus-Domino
```

完整流程見 [BUILD.md](BUILD.md) 與 [ADDITIONAL-SERVER.md](ADDITIONAL-SERVER.md)。

## 本 Dockerfile 已 patched 的五大踩坑

Dockerfile 之所以這樣寫，是因為下列五個踩坑。完整 root-cause 分析見 [TROUBLESHOOTING.md](TROUBLESHOOTING.md)：

1. **RHEL UBI 7 預設不含 `hostname` 指令** — `install.pl` 會觸發 `Undefined subroutine &DingDong::out` 的 Perl 錯誤。修法：`yum install hostname`。
2. **Fix Pack installer 不接受 `-silent` 旗標** — 它用 `-script <file>` 而非 `-silent`。修法：FP install 步驟拿掉 `-silent`。
3. **內建的 IBM J9 JVM 預設 heap 太小** — Notes Admin client 連到 setup wizard 時觸發 `java.lang.OutOfMemoryError`。修法：用 `sed -i` patch `serversetup` 加上 `-Xmx512m -Xms128m`。
4. **Domino 9 的 `notes.ini` 沒有 `ServerName=` 那行** — entrypoint 必須改用 `^Setup=[0-9]` 偵測「setup 完成」狀態。
5. **加密過的 `server.id` 會卡住 server 啟動** — 必須透過 stdin 把密碼餵給 `server`。修法：entrypoint 認 `DOMINO_ID_PASSWORD` env var。

## 已驗證項目

| 項目 | 狀態 |
|---|---|
| Windows 11 + WSL2 + Docker Engine 29.5.2 環境跑 `docker build` | ✅ Image 1.48 GB |
| 容器啟動進入 setup-listener 模式 | ✅ Port 8585 |
| Notes Admin client `serversetup -remote` 跑完 wizard | ✅ |
| 對既有 Domino domain 跑 additional-server setup | ✅ `names.nsf` replicate 約 5-15 分鐘 |
| 帶 `DOMINO_ID_PASSWORD` 進 normal mode | ✅ 所有 server task 啟動 |
| 從 host 瀏覽器測 HTTP 200 | ✅ `Server: Lotus-Domino` |
| Image 可攜性（`docker save` → 新 distro 內 load） | ✅ 端到端約 6 分鐘 |
| RHEL UBI 8 次 PoC | ❌ 已 documented 為不相容 — 見 TROUBLESHOOTING.md §6 |

## 開發期使用的 build 環境

- Host: Windows 11
- WSL: WSL2 + 隔離專用的 Ubuntu 24.04 LTS distro
- Docker: Docker Engine 29.5.2（不是 Docker Desktop，但 Docker Desktop 應該也能跑）
- 目標 image: `domino9:9.0.1fp10`（1.48 GB）

其他 host 環境（原生 Linux、Mac + Docker Desktop 等）Dockerfile 本身應該可攜；host 層級的前置需求（[BUILD.md](BUILD.md) §1）可能需要微調。

## 維護狀態

單人維護，研究/興趣性質。歡迎 PR，但無 SLA。維護者主要 use case 是 Domino 9.0.1 FP10 的內部 Dev/Test — 其他 9.0.x 次版本的 issue 只能提供 best-effort 協助。

## 授權

MIT — 僅涵蓋本 repo 內的腳本與文件。

詳見 [LICENSE](LICENSE)。HCL Domino 本身**不**在此 license 涵蓋範圍。
