# Disclaimer — Important Before You Use

This repository documents **how to self-build a container image for HCL Domino 9.0.x**. It does **not** distribute HCL Domino binaries.

Read this page completely before using the build assets in this repo.

## What this repository contains

| Type | What |
|---|---|
| Build scripts | `Dockerfile`, `entrypoint.sh`, `silent.properties`, `.gitignore` |
| Documentation | `README.md`, `BUILD.md`, `ADDITIONAL-SERVER.md`, `TROUBLESHOOTING.md`, `DOMINOCTL.md`, this file |
| License | MIT (for the scripts + docs above) |

## What this repository explicitly does NOT contain

- HCL Domino installer media (any `.tar` file with installer binaries)
- HCL Domino fix pack media
- Built Docker images (`.tar` or `.tgz` of `docker save` output)
- Any `server.id`, `cert.id`, `notes.ini`, `names.nsf`, or other identity / configuration files
- Any company-specific server names, hostnames, or credentials

If you find any of the above accidentally committed, please open an issue.

## HCL Software EULA

HCL Domino 9 is **proprietary software** owned by HCL Technologies. To use the build assets in this repo legally, **you** must:

1. Have a valid HCL Domino 9 entitlement (PVU, Authorized User, or equivalent) covering the deployment you intend to run.
2. Obtain HCL Domino 9 installation media (`DOMINO_9.0.1_64_BIT_LIN_XS_EN.tar` and the relevant Fix Pack such as `domino901FP10_linux64_x86.tar`) directly from HCL FlexNet Operations Portal:
   https://hclsoftware.flexnetoperations.com/
3. Comply with all terms of the HCL Software License Agreement applicable to your entitlement.

The MIT license on this repository covers ONLY the scripts and documentation that I (the maintainer) authored. It does **not** grant any license to HCL Domino itself.

## HCL Support Boundary

- HCL's official Docker support began with **Domino 10.0.1 FP3**.
- Domino 9.x running in a container is **"unsupported but works"**: technically functional and verified in this research, but **outside HCL's official supported configuration**.
- If you need to file an HCL Support case, HCL Support may require you to reproduce the issue on a certified bare-metal or VM platform first.

This repository is **not affiliated with HCL Technologies**.

## Domino 9 End-of-Marketing / End-of-Support

- **2024-06-01**: HCL Domino 9 entered End of Marketing.
- **2026-06-01**: HCL Domino 9 entered End of Support.

The build assets here are intended for:

- Internal Dev / Test / QA environments
- Legacy server preservation (e.g., running old NSF databases that have not been migrated)
- Migration testing (rehearsing upgrades to Domino 12/14)

They are **not recommended as a replacement for a properly supported production deployment**.

## RHEL UBI 7 Base Image

The primary build (`dockerfiles/domino9.0.1-fp10-ubi7/`) uses Red Hat Universal Base Image 7.9. UBI is freely redistributable per the [Red Hat UBI EULA](https://www.redhat.com/en/about/ubi-licensing). UBI 7 itself has passed full support and is in Extended Life Support (ELS) until 2028.

A secondary UBI 8 attempt is documented as **not directly buildable** due to Perl 5.30 namespace strictness and missing `cpio` — details in `TROUBLESHOOTING.md`.

## No Warranty

The build scripts and documentation are provided "AS IS" under the MIT License. Use at your own risk. The maintainer has run them successfully against Domino 9.0.1 FP10 on Windows 11 + WSL2 + Docker Engine 29.5.2, but cannot guarantee success in other environments or with other versions.

## Reporting Issues

If you find bugs in the build scripts or documentation, please open an issue on this repository. For HCL Domino product bugs, contact HCL Support through the normal channels (you will need your entitlement information).

---
---

# 繁體中文版

# 免責聲明 — 使用前必讀

本 repo 記錄的是**如何自建 HCL Domino 9.0.x 的 container image**。**不**散布 HCL Domino binary。

在使用本 repo 內任何 build 資產前，請完整讀完本頁。

## 本 repo 內容物

| 類型 | 內容 |
|---|---|
| Build 腳本 | `Dockerfile`、`entrypoint.sh`、`silent.properties`、`.gitignore` |
| 文件 | `README.md`、`BUILD.md`、`ADDITIONAL-SERVER.md`、`TROUBLESHOOTING.md`、`DOMINOCTL.md`、本檔案 |
| License | MIT（涵蓋上述腳本與文件） |

## 本 repo 明確**不**包含

- HCL Domino installer 媒體（任何含 installer binary 的 `.tar` 檔）
- HCL Domino fix pack 媒體
- 已 build 的 Docker image（`docker save` 輸出的 `.tar` 或 `.tgz`）
- 任何 `server.id`、`cert.id`、`notes.ini`、`names.nsf` 或其他身分/設定檔
- 任何公司專屬的 server 名稱、hostname、或憑證

如果你發現以上任何一項被不小心 commit 進來，請開 issue。

## HCL Software EULA

HCL Domino 9 是 HCL Technologies 擁有的**專屬軟體**。要合法使用本 repo 內的 build 資產，**你**必須：

1. 持有有效的 HCL Domino 9 entitlement（PVU、Authorized User 或同等授權），涵蓋你打算運行的部署。
2. 直接從 HCL FlexNet Operations Portal 取得 HCL Domino 9 安裝媒體（`DOMINO_9.0.1_64_BIT_LIN_XS_EN.tar` 以及相關的 Fix Pack 例如 `domino901FP10_linux64_x86.tar`）：
   https://hclsoftware.flexnetoperations.com/
3. 遵守你的 entitlement 所適用的所有 HCL Software License Agreement 條款。

本 repo 的 MIT license **僅**涵蓋我（維護者）撰寫的腳本與文件。它**不**授予你任何使用 HCL Domino 本身的權利。

## HCL Support Boundary

- HCL 官方 Docker support 從 **Domino 10.0.1 FP3** 開始。
- 在容器內跑 Domino 9.x 屬於**「unsupported but works」**：技術上可用、本研究也驗證過，但**不在 HCL 官方 supported configuration 範圍內**。
- 如果你需要對 HCL Support 開 case，HCL Support 可能會要求你先在認證的 bare-metal 或 VM 平台上重現問題。

本 repo **與 HCL Technologies 無從屬關係**。

## Domino 9 End-of-Marketing / End-of-Support

- **2024-06-01**：HCL Domino 9 進入 End of Marketing。
- **2026-06-01**：HCL Domino 9 進入 End of Support。

本 repo 的 build 資產適用於：

- 內部 Dev / Test / QA 環境
- Legacy server 保存（例如跑尚未遷移的舊 NSF 資料庫）
- 遷移測試（演練升級到 Domino 12/14）

**不建議**用來取代有正規 support 的 production 部署。

## RHEL UBI 7 Base Image

主要的 build（`dockerfiles/domino9.0.1-fp10-ubi7/`）使用 Red Hat Universal Base Image 7.9。UBI 依 [Red Hat UBI EULA](https://www.redhat.com/en/about/ubi-licensing) 可自由再散布。UBI 7 本身已過完整 support 期，進入 Extended Life Support (ELS)，至 2028 年。

次要的 UBI 8 嘗試已 documented 為**無法直接 build**，原因是 Perl 5.30 namespace 嚴格化以及缺少 `cpio` — 詳見 `TROUBLESHOOTING.md`。

## 無擔保聲明

本 build 腳本與文件依 MIT License「AS IS」提供。風險自負。維護者已在 Windows 11 + WSL2 + Docker Engine 29.5.2 上對 Domino 9.0.1 FP10 成功跑過，但不保證在其他環境或其他版本下也能成功。

## 回報問題

如果你在 build 腳本或文件中發現 bug，請在本 repo 開 issue。HCL Domino 產品本身的 bug 請循正常管道聯絡 HCL Support（你需要提供你的 entitlement 資訊）。
