# FP10 as a layered image on top of `domino9:9.0.1`

This Dockerfile demonstrates Approach A of [../../BASE-AND-FP-LAYERS.md](../../BASE-AND-FP-LAYERS.md): you already built `domino9:9.0.1` (no FP), and now you want a separate `domino9:9.0.1fp10` image that just adds the Fix Pack.

## Why this approach

- **One base, many FPs**: build `domino9:9.0.1fp7`, `domino9:9.0.1fp10` etc. from the same base
- **Faster FP rebuild**: when a new FP comes out, only the FP layer changes; base layers stay cached
- **Auditable**: docker history clearly shows which FP layer was added
- **Reproducible**: same as approach in `../domino9.0.1-fp10-ubi7/` but split for clarity

## Prerequisites

1. `domino9:9.0.1` already exists in your local docker images:
   ```bash
   docker images domino9
   # REPOSITORY  TAG     IMAGE ID  SIZE
   # domino9     9.0.1   <id>      ~1.4GB
   ```
   If not, build it first via `../domino9.0.1-base-ubi7/`.

2. `domino901FP10_linux64_x86.tar` placed in this directory.

## Build

```bash
docker build -t domino9:9.0.1fp10 .
```

Build takes ~3-4 minutes (just the FP install — base is cached as the FROM layer).

## Customize for other FPs

To build an FP8 image from the same base:

```bash
cd ../domino9.0.1-fp10-on-base
cp /path/to/domino901FP8_linux64_x86.tar .
docker build -t domino9:9.0.1fp8 \
  --build-arg BASE_IMAGE=domino9:9.0.1 \
  -f Dockerfile-fp8 \
  .
```

(You'd need a parallel Dockerfile-fp8 with `COPY domino901FP8_linux64_x86.tar` etc. — left as exercise; the structure is identical.)

---
---

# 繁體中文版

# FP10 以 layered image 形式疊在 `domino9:9.0.1` 上

本 Dockerfile 示範 [../../BASE-AND-FP-LAYERS.md](../../BASE-AND-FP-LAYERS.md) 的 Approach A：你已經 build 好 `domino9:9.0.1`（不含 FP），現在想要一個獨立的 `domino9:9.0.1fp10` image，純粹只把 Fix Pack 疊上去。

## 為什麼採這種做法

- **一個 base、多個 FP**：可從同一個 base build 出 `domino9:9.0.1fp7`、`domino9:9.0.1fp10` 等
- **FP rebuild 更快**：新 FP 出來時只有 FP layer 變動，base layer 維持 cache
- **可稽核**：docker history 清楚顯示加入了哪個 FP layer
- **可重現**：與 `../domino9.0.1-fp10-ubi7/` 的做法相同，只是拆開以求結構清晰

## 前置需求

1. 本機 docker images 內已存在 `domino9:9.0.1`：
   ```bash
   docker images domino9
   # REPOSITORY  TAG     IMAGE ID  SIZE
   # domino9     9.0.1   <id>      ~1.4GB
   ```
   如果還沒有，請先用 `../domino9.0.1-base-ubi7/` build 出來。

2. 把 `domino901FP10_linux64_x86.tar` 放進本目錄。

## Build

```bash
docker build -t domino9:9.0.1fp10 .
```

Build 約需 3-4 分鐘（只跑 FP install — base 部分以 FROM layer 形式被 cache）。

## 套用到其他 FP

要從同一個 base build 出 FP8 image：

```bash
cd ../domino9.0.1-fp10-on-base
cp /path/to/domino901FP8_linux64_x86.tar .
docker build -t domino9:9.0.1fp8 \
  --build-arg BASE_IMAGE=domino9:9.0.1 \
  -f Dockerfile-fp8 \
  .
```

（你會需要寫一支對應的 Dockerfile-fp8，內含 `COPY domino901FP8_linux64_x86.tar` 等 — 留作練習；結構完全相同。）
