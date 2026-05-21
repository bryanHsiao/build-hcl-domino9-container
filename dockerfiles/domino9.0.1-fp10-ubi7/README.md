# Build context for `domino9:9.0.1fp10` on RHEL UBI 7

## What this directory is for

This is the **Docker build context** for the Domino 9.0.1 FP10 image.

## Files committed here

| File | What |
|---|---|
| `Dockerfile` | Two-stage build (builder + runtime), all 5 known pitfalls patched |
| `entrypoint.sh` | First-run vs configured-run detection, SIGTERM trap, `DOMINO_ID_PASSWORD` support |
| `silent.properties` | InstallShield Options File for the base Domino installer (`-G/-W/-P` directives) |
| `.gitignore` | Belt-and-suspenders to keep installer media and ID files out of git |

## Files you must add (NOT committed, by design)

Before `docker build .` will work, place these into this directory:

| File | Where to get |
|---|---|
| `DOMINO_9.0.1_64_BIT_LIN_XS_EN.tar` (~834 MB) | HCL FlexNet Operations Portal — "HCL Domino 9.0.1 for Linux 64-bit" |
| `domino901FP10_linux64_x86.tar` (~441 MB) | HCL FlexNet Operations Portal — "Domino 9.0.1 Fix Pack 10 for Linux 64-bit" |

⚠️ **Do not commit these `.tar` files** — they are HCL-copyrighted material under EULA. The repo's `.gitignore` excludes `*.tar` by default.

## Build

From this directory:

```bash
docker build -t domino9:9.0.1fp10 .
```

For full instructions including environment setup, see [../../BUILD.md](../../BUILD.md).

## Notes on the Dockerfile

- **Base image**: `registry.access.redhat.com/ubi7/ubi:7.9` — Red Hat's freely redistributable image of RHEL 7.9. UBI 7 is in Extended Life Support until 2028.
- **Two stages**: A "builder" stage runs the silent install (heavy, needs `tar`, `bc`, etc.) and a "runtime" stage `COPY --from=builder` to keep the final image leaner.
- **Heap patch**: A `RUN sed -i` line patches the `serversetup` script with `-Xmx512m -Xms128m` to prevent the J9 JVM OOM when remote setup wizard connects. See [../../TROUBLESHOOTING.md](../../TROUBLESHOOTING.md) §3 for why.
- **No `latest` symlink shenanigans**: The image is tagged with the explicit version. Tag `:latest` aliases to the same image.

---
---

# 繁體中文版

# `domino9:9.0.1fp10` 在 RHEL UBI 7 上的 build context

## 這個目錄的用途

這是 Domino 9.0.1 FP10 image 的 **Docker build context**。

## 已 commit 進來的檔案

| 檔案 | 內容 |
|---|---|
| `Dockerfile` | 兩階段 build（builder + runtime），已 patched 全部 5 個已知踩坑 |
| `entrypoint.sh` | first-run 與 configured-run 偵測、SIGTERM trap、支援 `DOMINO_ID_PASSWORD` |
| `silent.properties` | 基底 Domino installer 用的 InstallShield Options File（`-G/-W/-P` directives） |
| `.gitignore` | 雙重保險，確保 installer 媒體與 ID 檔不會被 commit 進 git |

## 你必須額外放入的檔案（依設計**不**會 commit）

在 `docker build .` 能跑之前，請把以下檔案放進本目錄：

| 檔案 | 從哪取得 |
|---|---|
| `DOMINO_9.0.1_64_BIT_LIN_XS_EN.tar`（約 834 MB） | HCL FlexNet Operations Portal — 「HCL Domino 9.0.1 for Linux 64-bit」 |
| `domino901FP10_linux64_x86.tar`（約 441 MB） | HCL FlexNet Operations Portal — 「Domino 9.0.1 Fix Pack 10 for Linux 64-bit」 |

⚠️ **不要把這些 `.tar` 檔 commit 進來** — 它們是 HCL 著作權保護的 EULA 規範資料。本 repo 的 `.gitignore` 預設已排除 `*.tar`。

## Build

從本目錄執行：

```bash
docker build -t domino9:9.0.1fp10 .
```

完整步驟（含環境設定）請見 [../../BUILD.md](../../BUILD.md)。

## Dockerfile 備註

- **Base image**：`registry.access.redhat.com/ubi7/ubi:7.9` — Red Hat 可自由散布的 RHEL 7.9 image。UBI 7 已進入 Extended Life Support，至 2028 年。
- **兩階段 build**：「builder」階段跑 silent install（重型，需要 `tar`、`bc` 等）；「runtime」階段透過 `COPY --from=builder` 把成品搬過去，讓最終 image 比較輕。
- **Heap patch**：用一行 `RUN sed -i` 把 `serversetup` 腳本加上 `-Xmx512m -Xms128m`，避免遠端 setup wizard 連線時 J9 JVM OOM。原因見 [../../TROUBLESHOOTING.md](../../TROUBLESHOOTING.md) §3。
- **沒有 `latest` symlink 的把戲**：image 用明確的版本號 tag。`:latest` 這個 tag 只是指向同一個 image 的 alias。
