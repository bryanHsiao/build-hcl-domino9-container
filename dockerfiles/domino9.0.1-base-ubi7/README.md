# Build context for `domino9:9.0.1` base (no Fix Pack) on RHEL UBI 7

## What this directory is for

Build a Domino **9.0.1 base** image (no FP applied). Useful when you want to:

- Decouple base from FP for clearer layering / version tracking
- Reuse one base image to test multiple FP levels (FP8, FP9, FP10)
- Reduce build context size (one less ~441 MB tar)
- Match how some shops deploy: "always start from clean base, then patch"

For the "one-shot base + FP10" image, see `../domino9.0.1-fp10-ubi7/` instead.

## Files committed here

| File | What |
|---|---|
| `Dockerfile` | Two-stage build, base 9.0.1 silent install only, no FP |
| `entrypoint.sh` | Same as the FP10 variant (first-run / configured-run detection, `DOMINO_ID_PASSWORD`) |
| `silent.properties` | Same as the FP10 variant — InstallShield Options File |
| `.gitignore` | Excludes installer media |

## Files you must add (NOT committed)

| File | Where to get |
|---|---|
| `DOMINO_9.0.1_64_BIT_LIN_XS_EN.tar` (~834 MB) | HCL FlexNet Operations Portal |

⚠️ Do not commit. Repo `.gitignore` excludes `*.tar`.

## Build

```bash
docker build -t domino9:9.0.1 .
```

## Then what?

See [../../BASE-AND-FP-LAYERS.md](../../BASE-AND-FP-LAYERS.md) for the
two recommended ways to apply a Fix Pack after this base:

- **Approach A (layered Dockerfile, recommended)** — build a derived image
  `FROM domino9:9.0.1` that just adds the FP. Reproducible.
- **Approach B (runtime install + docker commit)** — boot the base
  container, `docker exec` the FP install, `docker commit` the result.
- Plus how to choose between them + caveats.

---
---

# 繁體中文版

# `domino9:9.0.1` base（不含 Fix Pack）在 RHEL UBI 7 上的 build context

## 這個目錄的用途

Build 一個 Domino **9.0.1 base** image（不套用任何 FP）。適合下列情境：

- 想把 base 與 FP 解耦，layer 結構/版本追蹤更清楚
- 想用同一個 base image 測多個 FP level（FP8、FP9、FP10）
- 想減少 build context 大小（少一個約 441 MB 的 tar）
- 對應某些公司的部署慣例：「永遠從乾淨 base 開始，再套 patch」

如果要做「一次完成 base + FP10」的 image，請改用 `../domino9.0.1-fp10-ubi7/`。

## 已 commit 進來的檔案

| 檔案 | 內容 |
|---|---|
| `Dockerfile` | 兩階段 build，只跑 9.0.1 base silent install，不含 FP |
| `entrypoint.sh` | 與 FP10 變體相同（first-run / configured-run 偵測、`DOMINO_ID_PASSWORD`） |
| `silent.properties` | 與 FP10 變體相同 — InstallShield Options File |
| `.gitignore` | 排除 installer 媒體 |

## 你必須額外放入的檔案（**不**會 commit）

| 檔案 | 從哪取得 |
|---|---|
| `DOMINO_9.0.1_64_BIT_LIN_XS_EN.tar`（約 834 MB） | HCL FlexNet Operations Portal |

⚠️ 不要 commit。Repo 的 `.gitignore` 預設排除 `*.tar`。

## Build

```bash
docker build -t domino9:9.0.1 .
```

## 然後呢？

請見 [../../BASE-AND-FP-LAYERS.md](../../BASE-AND-FP-LAYERS.md)，內含兩種建議的 Fix Pack 套用方式：

- **Approach A（layered Dockerfile，推薦）** — 寫一個 `FROM domino9:9.0.1` 的衍生 image，只負責加上 FP。可重現性高。
- **Approach B（runtime install + docker commit）** — 啟動 base 容器、`docker exec` 跑 FP install、再 `docker commit` 出結果。
- 以及如何在兩者之間選擇 + 注意事項。
