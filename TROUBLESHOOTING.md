# TROUBLESHOOTING.md — The five non-obvious pitfalls

These five issues each cost multiple build/run cycles to identify during the original research. The Dockerfile and entrypoint.sh in this repo **already include the fixes** — this document explains what they are and why, so you can recognize them if you adapt the build for another OS / version.

## §1. `Undefined subroutine &DingDong::out called at install.pl line 65`

### Symptom

`docker build` fails during the base silent install step. Output:

```
IBM Domino for Unix Install Program
------------------------------------
Undefined subroutine &DingDong::out called at /tmp/install_src/domino/tools/install.pl line 65.
exit code: 2
```

If you look at `/tmp/nuish.err` inside the container at that point, you'll see more context — the `install.sh` script redirects stderr there by default (find it via `cat /tmp/nuish.err` after a failed install).

### Root cause

Two layers:

1. **The visible Perl error is misleading**. `install.pl` calls `out()` only if `SysCmd::InitCmds()` returns false. Looking at line 64:
   ```perl
   if ( ! SysCmd::InitCmds(\@reqcmds, \@cmdsnotfound, \$errmsg, $ENV{'NUI_ARCH'})) {
       out($txt{2} . $errmsg);  # ← line 65
       exit 1;
   }
   ```
2. **The real root cause is `@reqcmds` includes `hostname` and `clear`**, and RHEL UBI 7 does **not** install `hostname` by default. So `InitCmds()` finds the missing command and tries to call `out()` for the error message, but `out` is defined in `tty.pl` under `package main::`, while `install.pl` is in `package DingDong;` — so `&DingDong::out` is undefined and Perl crashes before printing the helpful error.

This is technically a bug in IBM's `install.pl` (the `out()` call should be `&main::out()` or the package switch should happen later), but it's worked around by ensuring the actual prerequisites aren't missing in the first place.

### Fix (in this repo)

`Dockerfile` runs:

```dockerfile
RUN yum install -y \
        perl \
        ksh \
        libgcc libstdc++ glibc \
        which procps-ng tar bc \
        hostname ncurses \    # <-- key additions
    && yum clean all
```

`hostname` provides the `hostname` command. `ncurses` provides `clear` (and tput, etc.).

### How to recognize this in another distro

If you see ANY Perl error from `install.pl` early in the silent install (especially `Undefined subroutine`), suspect a missing required command first. Other commands in `@reqcmds`: `mv rm mkdir env stty uname date touch tar chown chgrp cat chmod sh pwd hostname clear`.

## §2. FP installer rejects `-silent`

### Symptom

`docker build` succeeds for the base install (~7 minutes) but fails immediately at the Fix Pack install step:

```
IBM Domino for Unix Install Program
------------------------------------
Installer is initializing. It may take a few minutes, please, wait.

Usage: install [-script <scriptfile>]
exit code: 1
```

### Root cause

The base installer accepts `-silent -options <file>`. The Fix Pack installer accepts **only** `-script <file>`. Passing `-silent` to the FP installer is treated as an unknown argument and triggers the usage message.

This is not documented prominently — discovered by reading the FP's `install` wrapper script after a failed build.

### Fix (in this repo)

`Dockerfile` for the FP step:

```dockerfile
RUN mkdir fp10 \
    && tar xf fp10.tar -C fp10 \
    && cd fp10/linux64/domino \
    && export NUI_NOTESDIR=/opt/ibm/domino \
    && ./install -script script.dat \      # <-- no -silent
    && cd /tmp/install \
    && rm -rf fp10 fp10.tar
```

Also note the `NUI_NOTESDIR` env var pointing to the existing base install location — the FP installer needs this to find what to patch.

## §3. Bundled IBM J9 JVM OutOfMemoryError during setup wizard

### Symptom

Container builds and runs successfully. Setup wizard listens on port 8585. But when a Notes Admin client tries to connect via `serversetup.exe -remote <host>:8585`:

- Notes Admin client: `Network Communication error occurred`
- `docker logs <container>` shows:
  ```
  JVMDUMP039I Processing dump event "systhrow", detail "java/lang/OutOfMemoryError" at ...
  JVMDUMP032I JVM requested System dump using '/opt/ibm/domino/notes/90010/linux/core....dmp' in response to an event
  ```

The dump file gets written and the JVM process dies. Container's main process (entrypoint.sh waiting on the JVM) sees the JVM exit and the container terminates.

### Root cause

The bundled IBM J9 JVM (from 2013, ships with Domino 9.0.1) launches with these flags from the `serversetup` wrapper:

```bash
CMD="$CMD -ss512k -Xmso5M"          # stack only — NOT heap
```

`-ss512k` is initial thread stack, `-Xmso5M` is max stack. **There is no `-Xmx` argument**, so the JVM uses its default heap. For 2013-era J9, the default is something like 64 MB. That's not enough to load Java Swing GUI components when a remote client connects to drive the setup wizard.

Setting `JAVA_TOOL_OPTIONS=-Xmx512m` as an environment variable doesn't help — that 2013 J9 build doesn't honor `JAVA_TOOL_OPTIONS`.

### Fix (in this repo)

Patch the `serversetup` script directly. From the Dockerfile:

```dockerfile
RUN find /opt/ibm/domino -name serversetup -type f -exec \
    sed -i 's|-ss512k -Xmso5M|-ss512k -Xmso5M -Xmx512m -Xms128m|g' {} \; \
 && grep -l "Xmx512m" /opt/ibm/domino/notes/90010/linux/serversetup \
 || (echo "[error] serversetup heap patch failed" && exit 1)
```

After this patch, the launch line becomes:

```
./java -ss512k -Xmso5M -Xmx512m -Xms128m -cp jhall.jar:cfgdomserver.jar:./ndext/...
```

512 MB heap is comfortable for the wizard's Swing GUI even with several client connections.

## §4. Setup-complete detection: `Setup=` not `ServerName=`

### Symptom

First run: setup wizard listens on 8585, you complete it, "Setup complete!" appears. Container exits cleanly. Now you restart the container — but instead of starting the configured Domino server, the entrypoint launches the setup wizard **again**. Worse, after a few seconds the GUI wizard process exits (since the data dir is already configured) and the container dies.

### Root cause

A naive heuristic for "is this data dir already configured?" is to check `notes.ini` for `ServerName=`. **Domino 9 does not write a `ServerName=` line into `notes.ini`** — the server name lives in `MailServer=` and `KeyFileName_Owner=` instead, with the setup-completion marker being a separate `Setup=900100` (or similar version code) line.

Some Domino 12+ versions DO write `ServerName=`, which is probably why the `^ServerName=` check works in newer container projects but not for Domino 9.

### Fix (in this repo)

`entrypoint.sh`:

```bash
if [ -f "$NOTES_INI" ] && grep -qE "^Setup=[0-9]" "$NOTES_INI" 2>/dev/null; then
    # CONFIGURED RUN
else
    # FIRST RUN
fi
```

The `[0-9]` anchor ensures we're matching a real `Setup=900100` style line, not just any `Setup` substring.

## §5. Password-protected `server.id` hangs at boot

### Symptom

After the setup wizard succeeds and you restart the container in normal mode, `docker logs` shows:

```
[00057:00002-000070DE65C55740] IBM Domino (r) Server (64 Bit), Release 9.0.1FP10, January 15, 2018
[00057:00002-000070DE65C55740] The ID file being used is: /local/notesdata/server.id
[00057:00002-000070DE65C55740] Enter password (press the Esc key to abort):
```

Server then hangs forever. Container appears running (status: Up) but uses ~0% CPU. Notes Admin client can't connect; HTTP doesn't respond.

### Root cause

If the `server.id` was registered with a password (the admin's `Configuration → Registration → Server` flow always asks for one), Domino at boot reads the `server.id` and prompts for the password on stdin. In `docker run -d` mode there's no interactive stdin, so the prompt blocks forever.

### Fix (in this repo)

`entrypoint.sh` honors a `DOMINO_ID_PASSWORD` environment variable and pipes it to `server`'s stdin:

```bash
if [ -n "$DOMINO_ID_PASSWORD" ]; then
    printf '%s\n' "$DOMINO_ID_PASSWORD" | "${DOMINO_HOME}/bin/server" &
else
    # Will hang if ID is encrypted
    "${DOMINO_HOME}/bin/server" &
fi
```

To use:

```bash
docker run -d \
  --name domino9 \
  -e DOMINO_ID_PASSWORD='your-id-password' \
  ... \
  domino9:9.0.1fp10
```

### Security trade-offs

- The password is **visible** to anyone with `docker inspect` access — typically root or members of the `docker` group on the host.
- For higher security, look into Docker secrets / external secret managers (out of scope for this repo).
- The `passw0rd`-class trivial passwords sometimes used in testing are *not safe* for production-like environments.

## §6. UBI 8 secondary build attempt (informational)

This repo's primary build uses **RHEL UBI 7**. An attempt to use UBI 8 was made and **failed**, validating that UBI 7 is the correct choice for Domino 9.

### What goes wrong on UBI 8

After fixing the `ksh` package (not in UBI 8 default repos; remove from `yum install`), the silent install fails at:

```
Undefined subroutine &main::Exit called at /tmp/install/linux64/domino/tools/checkminimumos.pl line 52.
Fatal Error:
  cpio
```

Two independent problems:

1. **Perl 5.30 namespace strictness**: UBI 8 ships Perl 5.30 (vs UBI 7's 5.16). The 2013-era Domino install scripts rely on lax Perl 4 / early Perl 5 namespace resolution that 5.30 has tightened. This is similar to the `DingDong::out` problem in §1 but in a different module — and not easily fixable without patching multiple Perl scripts inside the Domino installer (which would arguably violate the HCL EULA's "no reverse engineering" clause).
2. **`cpio` not installed by default in UBI 8 BaseOS**: Domino's installer uses `cpio` to extract `linux64.dat`. UBI 8's minimal BaseOS doesn't include it; adding `cpio` to the yum install list fixes this specific error but the Perl namespace issue still blocks the install.

### What this means

- **UBI 7 is the recommended Domino 9 base** for self-built containers
- **UBI 7's ELS support window ends in 2028** — within that you have time to migrate to Domino 14+ on a modern base
- If UBI 7 is decommissioned by Red Hat before you can migrate Domino, the next best option is **Rocky Linux 7** archive images (RHEL 7 ABI clone, also EOL but works)
- Don't try UBI 8 / UBI 9 / Ubuntu 22+ / Debian 12+ without budgeting significant patching of Domino's install scripts

## Where to look next

- The Dockerfile itself is heavily commented to explain why each step looks the way it does — read it alongside this document.
- For full Domino server console troubleshooting (NSD, fault recovery, etc.), use HCL Support documentation — out of scope for this repo.

---
---

# 繁體中文版

# TROUBLESHOOTING.md — 五個非顯而易見的踩坑

這五個問題在當初研究時每一個都花了多次 build/run 才查出來。本 repo 的 Dockerfile 與 entrypoint.sh **已經內建這些修法** — 本文件解釋它們是什麼、為什麼這樣修，讓你在改寫成其他 OS / 版本時還能辨識出來。

## §1. `Undefined subroutine &DingDong::out called at install.pl line 65`

### 症狀

`docker build` 在 base silent install 步驟失敗。Output：

```
IBM Domino for Unix Install Program
------------------------------------
Undefined subroutine &DingDong::out called at /tmp/install_src/domino/tools/install.pl line 65.
exit code: 2
```

若在當下進入容器看 `/tmp/nuish.err`，會看到更多 context — `install.sh` 預設會把 stderr redirect 到那邊（失敗後可用 `cat /tmp/nuish.err` 查看）。

### 根因

兩層：

1. **這個 Perl 錯誤訊息本身是誤導性的**。`install.pl` 只有在 `SysCmd::InitCmds()` 回傳 false 時才會 call `out()`。看 line 64：
   ```perl
   if ( ! SysCmd::InitCmds(\@reqcmds, \@cmdsnotfound, \$errmsg, $ENV{'NUI_ARCH'})) {
       out($txt{2} . $errmsg);  # ← line 65
       exit 1;
   }
   ```
2. **真正的根因是 `@reqcmds` 包含 `hostname` 與 `clear`**，而 RHEL UBI 7 預設**不會**安裝 `hostname`。所以 `InitCmds()` 發現指令不存在，想 call `out()` 印錯誤訊息，但 `out` 定義在 `tty.pl` 內的 `package main::`，而 `install.pl` 屬於 `package DingDong;` — 結果 `&DingDong::out` 是未定義的，Perl 在印出原本有用的錯誤訊息前就先 crash 了。

技術上這是 IBM 的 `install.pl` 的一個 bug（`out()` 呼叫應該是 `&main::out()`，或者 package 切換應該晚一點發生），不過解法是確保實際的前置需求一開始就沒缺。

### 修法（本 repo）

`Dockerfile` 跑：

```dockerfile
RUN yum install -y \
        perl \
        ksh \
        libgcc libstdc++ glibc \
        which procps-ng tar bc \
        hostname ncurses \    # <-- key additions
    && yum clean all
```

`hostname` 提供 `hostname` 指令。`ncurses` 提供 `clear`（還有 tput 等）。

### 如何在其他 distro 上辨識

如果你看到 silent install 早期出現任何 `install.pl` 的 Perl 錯誤（尤其是 `Undefined subroutine`），先懷疑必要指令缺失。`@reqcmds` 內其他指令：`mv rm mkdir env stty uname date touch tar chown chgrp cat chmod sh pwd hostname clear`。

## §2. FP installer 拒絕 `-silent`

### 症狀

`docker build` 在 base install（~7 分鐘）成功，但 Fix Pack install 步驟一開始就失敗：

```
IBM Domino for Unix Install Program
------------------------------------
Installer is initializing. It may take a few minutes, please, wait.

Usage: install [-script <scriptfile>]
exit code: 1
```

### 根因

base installer 接受 `-silent -options <file>`。Fix Pack installer **只**接受 `-script <file>`。把 `-silent` 傳給 FP installer 會被當成未知參數，觸發 usage 訊息。

這點在 HCL 文件中沒有顯著說明 — 是 build 失敗後讀 FP 的 `install` wrapper script 才發現的。

### 修法（本 repo）

`Dockerfile` 的 FP 步驟：

```dockerfile
RUN mkdir fp10 \
    && tar xf fp10.tar -C fp10 \
    && cd fp10/linux64/domino \
    && export NUI_NOTESDIR=/opt/ibm/domino \
    && ./install -script script.dat \      # <-- no -silent
    && cd /tmp/install \
    && rm -rf fp10 fp10.tar
```

同時注意 `NUI_NOTESDIR` env var 要指向既有的 base install 位置 — FP installer 需要這個來找要 patch 的對象。

## §3. 內建 IBM J9 JVM 在 setup wizard 發生 OutOfMemoryError

### 症狀

容器 build 完成且運行成功。Setup wizard 在 port 8585 listening。但當 Notes Admin client 透過 `serversetup.exe -remote <host>:8585` 嘗試連線時：

- Notes Admin client：`Network Communication error occurred`
- `docker logs <container>` 顯示：
  ```
  JVMDUMP039I Processing dump event "systhrow", detail "java/lang/OutOfMemoryError" at ...
  JVMDUMP032I JVM requested System dump using '/opt/ibm/domino/notes/90010/linux/core....dmp' in response to an event
  ```

dump 檔被寫出，JVM process 死亡。容器主 process（entrypoint.sh 在等 JVM）看到 JVM 結束，容器隨之停止。

### 根因

內建的 IBM J9 JVM（2013 年版，隨 Domino 9.0.1 出貨）由 `serversetup` wrapper 啟動時帶的 flag 是：

```bash
CMD="$CMD -ss512k -Xmso5M"          # stack only — NOT heap
```

`-ss512k` 是初始 thread stack，`-Xmso5M` 是最大 stack。**完全沒有 `-Xmx`**，所以 JVM 用預設 heap。2013 年代的 J9 預設大概是 64 MB，這對於 remote client 連進來驅動 setup wizard 時要載入的 Java Swing GUI 元件來說不夠。

把 `JAVA_TOOL_OPTIONS=-Xmx512m` 設為環境變數沒用 — 2013 年代的 J9 build 不認 `JAVA_TOOL_OPTIONS`。

### 修法（本 repo）

直接 patch `serversetup` script。Dockerfile：

```dockerfile
RUN find /opt/ibm/domino -name serversetup -type f -exec \
    sed -i 's|-ss512k -Xmso5M|-ss512k -Xmso5M -Xmx512m -Xms128m|g' {} \; \
 && grep -l "Xmx512m" /opt/ibm/domino/notes/90010/linux/serversetup \
 || (echo "[error] serversetup heap patch failed" && exit 1)
```

patch 後啟動命令變成：

```
./java -ss512k -Xmso5M -Xmx512m -Xms128m -cp jhall.jar:cfgdomserver.jar:./ndext/...
```

512 MB heap 對 wizard 的 Swing GUI 來說就算多 client 連線也夠用。

## §4. Setup 完成偵測：用 `Setup=` 而非 `ServerName=`

### 症狀

第一次跑：setup wizard listen 在 8585、走完、出現 "Setup complete!"。容器乾淨結束。重啟容器 — 但 entrypoint 沒啟動已設定好的 Domino server，反而**再次**啟動 setup wizard。更糟的是幾秒後 GUI wizard process 結束（因為 data dir 已被設定過），容器跟著死。

### 根因

「這個 data dir 是不是已經設定過」的單純 heuristic 是去 `notes.ini` 找 `ServerName=`。**Domino 9 不會在 `notes.ini` 寫入 `ServerName=` 那行** — server 名稱存在 `MailServer=` 與 `KeyFileName_Owner=`，setup 完成標記則是另一行 `Setup=900100`（或類似 version code）。

某些 Domino 12+ 版本確實會寫 `ServerName=`，這可能就是為什麼 `^ServerName=` 檢查在較新版本的 container 專案上能用，但在 Domino 9 上不行。

### 修法（本 repo）

`entrypoint.sh`：

```bash
if [ -f "$NOTES_INI" ] && grep -qE "^Setup=[0-9]" "$NOTES_INI" 2>/dev/null; then
    # CONFIGURED RUN
else
    # FIRST RUN
fi
```

`[0-9]` anchor 確保我們是 match 真的 `Setup=900100` 樣式那行，而不是任意含 `Setup` 子字串的行。

## §5. 加密的 `server.id` 在 boot 時卡住

### 症狀

setup wizard 跑完、把容器重啟為 normal mode 後，`docker logs` 顯示：

```
[00057:00002-000070DE65C55740] IBM Domino (r) Server (64 Bit), Release 9.0.1FP10, January 15, 2018
[00057:00002-000070DE65C55740] The ID file being used is: /local/notesdata/server.id
[00057:00002-000070DE65C55740] Enter password (press the Esc key to abort):
```

Server 永遠卡住。容器看起來在跑（狀態：Up）但 CPU 使用率 ~0%。Notes Admin client 連不上；HTTP 沒回應。

### 根因

如果 `server.id` 註冊時有設密碼（admin 在 `Configuration → Registration → Server` 流程一定會被要求設一個），Domino 在 boot 時讀 `server.id` 後會在 stdin 提示輸入密碼。在 `docker run -d` 模式下沒有互動式 stdin，所以提示永遠卡住。

### 修法（本 repo）

`entrypoint.sh` 認 `DOMINO_ID_PASSWORD` 環境變數，把它 pipe 給 `server` 的 stdin：

```bash
if [ -n "$DOMINO_ID_PASSWORD" ]; then
    printf '%s\n' "$DOMINO_ID_PASSWORD" | "${DOMINO_HOME}/bin/server" &
else
    # Will hang if ID is encrypted
    "${DOMINO_HOME}/bin/server" &
fi
```

使用方式：

```bash
docker run -d \
  --name domino9 \
  -e DOMINO_ID_PASSWORD='your-id-password' \
  ... \
  domino9:9.0.1fp10
```

### 安全 trade-off

- 密碼對任何能 `docker inspect` 的人來說是**可見的** — 通常是 host 上的 root 或 `docker` 群組成員。
- 想要更高安全性，可考慮 Docker secrets / 外部 secret manager（不在本 repo 範圍內）。
- 測試常用的 `passw0rd` 之類弱密碼**不適合**類正式環境。

## §6. UBI 8 次次 PoC（informational）

本 repo 主要 build 用 **RHEL UBI 7**。曾嘗試改用 UBI 8 並**失敗**，證實 UBI 7 才是 Domino 9 的正確選擇。

### UBI 8 上會出什麼問題

修掉 `ksh` 套件問題（UBI 8 預設 repo 沒有；從 `yum install` 拿掉）後，silent install 在以下地方失敗：

```
Undefined subroutine &main::Exit called at /tmp/install/linux64/domino/tools/checkminimumos.pl line 52.
Fatal Error:
  cpio
```

兩個獨立問題：

1. **Perl 5.30 namespace 嚴格化**：UBI 8 內建 Perl 5.30（UBI 7 是 5.16）。2013 年代的 Domino install script 依賴的是寬鬆的 Perl 4 / 早期 Perl 5 namespace 解析方式，5.30 已收緊。這跟 §1 的 `DingDong::out` 問題類似但發生在不同 module — 不容易修，要 patch Domino installer 內的多個 Perl script（這恐怕違反 HCL EULA 的「不得逆向工程」條款）。
2. **`cpio` 在 UBI 8 BaseOS 預設沒裝**：Domino installer 用 `cpio` 解壓 `linux64.dat`。UBI 8 的最小 BaseOS 沒含 cpio；把 cpio 加進 yum install 清單可修這個特定錯誤，但 Perl namespace 問題仍會擋住 install。

### 這代表什麼

- **UBI 7 是自建 Domino 9 container 的推薦 base**
- **UBI 7 的 ELS 支援窗口會在 2028 年結束** — 在那之前你還有時間遷移到跑在現代 base 上的 Domino 14+
- 如果 UBI 7 在你能遷移 Domino 之前就被 Red Hat 下架，次佳選擇是 **Rocky Linux 7** 歸檔 image（RHEL 7 ABI clone，也已 EOL 但能跑）
- 不要在沒準備好大幅 patch Domino install script 的前提下嘗試 UBI 8 / UBI 9 / Ubuntu 22+ / Debian 12+

## 還可以去哪裡找資料

- Dockerfile 本身有大量註解解釋每一步為什麼這樣寫 — 請搭配本文件一起讀。
- 完整的 Domino server console 疑難排解（NSD、fault recovery 等）請查 HCL Support 文件 — 不在本 repo 範圍內。
