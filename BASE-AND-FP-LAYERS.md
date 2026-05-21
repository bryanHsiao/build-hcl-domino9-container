# BASE-AND-FP-LAYERS.md — Decouple Domino 9.0.1 base from Fix Pack

The primary build in this repo bakes Domino 9.0.1 base **and** FP10 into a single image in one go (see `dockerfiles/domino9.0.1-fp10-ubi7/`). That's the simplest path and matches HCL's official container approach for newer versions.

But sometimes you want to **separate the base install from the Fix Pack install**. Reasons:

- "I want to test FP7, FP9, FP10 against the same base — without rebuilding 7 minutes of base install three times"
- "I only have entitlement for the base today; FP comes later"
- "We policy-require base/patch separation in CI"
- "I want to follow the traditional Domino-on-Linux mental model where you `./install` base first, then `./install -script` the FP"

This document covers the three workable approaches and their trade-offs.

## Table of contents

- [Approach A — Two layered images (recommended)](#approach-a--two-layered-images-recommended)
- [Approach B — Runtime install + docker commit](#approach-b--runtime-install--docker-commit)
- [Approach C — Persistent FP via volume (not recommended)](#approach-c--persistent-fp-via-volume-not-recommended)
- [Side-by-side comparison](#side-by-side-comparison)
- [What about no-FP-at-all? (just running 9.0.1 base)](#what-about-no-fp-at-all-just-running-901-base)

---

## Approach A — Two layered images (recommended)

You build **two separate images**:

1. `domino9:9.0.1` — base only, from `dockerfiles/domino9.0.1-base-ubi7/`
2. `domino9:9.0.1fp10` — FP10 layered on top, from `dockerfiles/domino9.0.1-fp10-on-base/`

The FP Dockerfile is a tiny derived image whose `FROM` is the base. Build:

```bash
# Step 1 — base image (~10 min first time)
cd dockerfiles/domino9.0.1-base-ubi7
cp /path/to/DOMINO_9.0.1_64_BIT_LIN_XS_EN.tar .
docker build -t domino9:9.0.1 .

# Step 2 — FP10 layered on top (~3-4 min, base layers cached)
cd ../domino9.0.1-fp10-on-base
cp /path/to/domino901FP10_linux64_x86.tar .
docker build -t domino9:9.0.1fp10 .
```

Use `domino9:9.0.1fp10` for actual deployment.

### Pros

- **Reproducible**: `Dockerfile` defines the FP version → no drift
- **Cached base**: rebuilding a different FP only repeats the small FP layer
- **Standard docker idiom**: `FROM <base>` is how layered images are designed to work
- **Multiple FPs from one base**: build `domino9:9.0.1fp7` and `domino9:9.0.1fp10` from same `domino9:9.0.1` without re-installing the base

### Cons

- Need two `docker build` invocations and two Dockerfiles to maintain
- Final image has 1 more layer than the single-shot variant (negligible — image size ~ same)

### When to choose A

- You'll likely want to compare or roll back between FP levels
- You have CI that builds images and want efficient layer caching
- You want a clean immutable-image deployment story
- **In doubt, choose A** — it's the docker-native answer

---

## Approach B — Runtime install + docker commit

You boot the base image, `docker exec` the FP install steps interactively, then `docker commit` the changed container as a new image.

This is closest to the "在 VM 內裝 FP" mental model from bare-metal Domino administration.

### Steps

```bash
# 1. Build the base image (once)
cd dockerfiles/domino9.0.1-base-ubi7
docker build -t domino9:9.0.1 .

# 2. Boot the base container (use a name we can refer to)
docker volume create domino9-fpprep-data
docker run -d \
  --name domino9-fpprep \
  -p 11352:1352 -p 18080:80 -p 18585:8585 \
  -v domino9-fpprep-data:/local/notesdata \
  domino9:9.0.1
# Container enters setup-listener mode. Do NOT do setup wizard yet — we want
# to apply FP first so the resulting image is "9.0.1 FP10 + ready for setup".

# 3. Copy the FP tar into the container
docker cp domino901FP10_linux64_x86.tar domino9-fpprep:/tmp/

# 4. Stop the container BEFORE the FP install — FP modifies binaries that
#    the server process is using, will corrupt if hot-patched.
docker stop domino9-fpprep

# 5. Run the FP install via `docker run` against the stopped container's
#    state (use --rm and override entrypoint with /bin/bash).
docker run --rm \
  --user root \
  -v domino9-fpprep-data:/local/notesdata \
  --volumes-from domino9-fpprep \
  --entrypoint bash \
  domino9:9.0.1 \
  -c '
    set -e
    mkdir -p /tmp/fp10
    cp /tmp/domino901FP10_linux64_x86.tar /tmp/fp10/
    cd /tmp/fp10
    tar xf domino901FP10_linux64_x86.tar
    cd linux64/domino
    export NUI_NOTESDIR=/opt/ibm/domino
    ./install -script script.dat
    rm -rf /tmp/fp10
    echo "[ok] FP10 installed into /opt/ibm/domino"
  '

# Note: the above is a SIMPLIFIED illustration. The actual situation is
# more nuanced because `docker run --rm` against a STOPPED container's
# volumes is unusual. The truly clean way is:
#
#   docker start domino9-fpprep
#   docker exec --user root domino9-fpprep bash -c '...install steps...'
#
# But then the running server's binaries are being modified, which is
# risky. See "caveat 1" below.

# 6. Once FP install completed cleanly inside the container, commit to
#    a new image:
docker commit \
  --change 'LABEL fp.version="10" fp.installed_at="2026-05-21T22:00:00Z"' \
  domino9-fpprep \
  domino9:9.0.1fp10-runtime

# 7. Verify
docker images domino9
# REPOSITORY  TAG                   IMAGE ID  SIZE
# domino9     9.0.1fp10-runtime     <id>      ~1.6GB
# domino9     9.0.1                 <id>      ~1.4GB

# 8. Cleanup the prep container
docker rm domino9-fpprep
docker volume rm domino9-fpprep-data

# 9. Use the new image for actual deployment
docker run -d --name domino9 \
  -p 1352:1352 -p 80:80 -p 8585:8585 \
  -v domino9-data:/local/notesdata \
  domino9:9.0.1fp10-runtime
```

### Caveats

1. **Server must be stopped during FP install**. FP modifies `/opt/ibm/domino/notes/latest/linux/*` — the same binaries a running server has open. Hot-patching corrupts memory mappings and crashes the server, or worse leaves it in inconsistent state. The `docker stop` step is mandatory.

2. **`docker exec` modifications are ephemeral**. If you `docker exec` install the FP into a running container and then `docker rm` that container without `docker commit`, **the FP is gone**. Next `docker run` from the original image boots back to base. This is the #1 mistake newcomers to docker make with this approach.

3. **`docker commit` is not declarative**. The resulting image has no `Dockerfile` you can re-run. Six months later, you won't easily remember the exact `docker exec` you ran. Use approach A if you care about reproducibility.

4. **Image size grows**. The FP install touches many files; the resulting overlay layer adds the deltas as a new fat layer. Image is slightly larger than approach A's equivalent.

### When to choose B

- You're prototyping / experimenting and don't need reproducibility
- You're using a legacy build pipeline that doesn't support multi-stage / FROM-chained Dockerfiles
- You explicitly want "feel like Domino-on-VM" mental model
- One-off migration from a bare-metal Domino 9.0.1 base + FP10 install

---

## Approach C — Persistent FP via volume (not recommended)

Theoretically you could mount `/opt/ibm/domino` as a volume too, so the FP files survive across container recreation:

```bash
docker volume create domino9-program
docker run ... \
  -v domino9-program:/opt/ibm/domino \
  -v domino9-data:/local/notesdata \
  domino9:9.0.1
# Then docker exec to install FP into the volume
```

**Don't do this.** Reasons:

- Volume mount over an existing directory hides the image's `/opt/ibm/domino/` content. You'd need to populate the volume with the base install via a copy step. Operationally painful.
- Mixing "program files in volume" with "data files in volume" breaks the docker mental model where image = immutable program, volume = mutable data.
- If you `docker pull` or rebuild the base image (e.g., to pick up a UBI 7 security update), the new base's `/opt/ibm/domino` is masked by the old volume's content. You lose your security update.
- Backup / restore semantics get weird: program code is now mixed into your data backup.

Listed here for completeness only. Use A or B.

---

## Side-by-side comparison

| Aspect | A: Layered images | B: Runtime + commit | C: Volume |
|---|---|---|---|
| Reproducible | ✅ Dockerfile defines it | ❌ ad-hoc | ❌ |
| Fast multi-FP test | ✅ cached base | ❌ rebuild each time | ⚠️ ok-ish |
| docker history shows version | ✅ FP layer visible | ⚠️ only via LABEL | ❌ |
| Mental model match for Domino admin | ⚠️ "everything in Dockerfile" | ✅ "install FP into container" | ❌ |
| Standard docker idiom | ✅ | ⚠️ | ❌ |
| Recommended | **✅** | ⚠️ for one-offs | ❌ |

---

## What about no-FP-at-all? (just running 9.0.1 base)

You can absolutely deploy `domino9:9.0.1` as-is, **without** any FP. This is supported by Domino (FP is optional) but:

- The base 9.0.1 dates from 2013 and has known CVEs (Java, OpenSSL, TLS protocols) fixed in later FPs
- HCL Support boundary for 9.0.1 base (without FP10) is even more constrained than 9.0.1 FP10
- You won't get the SHA-2 / TLS 1.2 / modern CSRF fixes from FP8+

Practical recommendation: even for Dev / Test, apply at least FP10 (the final 9.x FP). The full image `dockerfiles/domino9.0.1-fp10-ubi7/` does this in one shot — use it unless you have a specific reason to keep base and FP separate.

---

## See also

- `BUILD.md` — main SOP (uses the one-shot `domino9.0.1-fp10-ubi7/` build)
- `TROUBLESHOOTING.md` §2 — why FP installer needs `-script` not `-silent`
- `TROUBLESHOOTING.md` §6 — why UBI 8 doesn't work as a base

---
---

# 繁體中文版

# BASE-AND-FP-LAYERS.md — 把 Domino 9.0.1 base 與 Fix Pack 解耦

本 repo 主要的 build 流程是把 Domino 9.0.1 base **和** FP10 一次 bake 進同一個 image（參見 `dockerfiles/domino9.0.1-fp10-ubi7/`）。那是最簡單的路徑，也對齊 HCL 在新版本上的官方 container 做法。

但有時候你會想**把 base 安裝與 Fix Pack 安裝分開**。常見理由：

- 「我想在同一個 base 上測 FP7、FP9、FP10 — 不想為了測 3 次而重跑 base 的 7 分鐘安裝 3 次」
- 「我今天只有 base 的 entitlement，FP 之後才會拿到」
- 「公司 CI policy 要求 base/patch 分離」
- 「我想沿用傳統 Domino-on-Linux 的心智模型 — 先 `./install` 裝 base，再 `./install -script` 裝 FP」

本文件介紹三種可行方案與各自的 trade-off。

## 目錄

- [方案 A — 兩個 layered images（推薦）](#方案-a--兩個-layered-images推薦)
- [方案 B — Runtime install + docker commit](#方案-b--runtime-install--docker-commit)
- [方案 C — 把 FP 持久化在 volume 內（不推薦）](#方案-c--把-fp-持久化在-volume-內不推薦)
- [三方案並列比較](#三方案並列比較)
- [那如果完全不裝 FP？（只跑 9.0.1 base）](#那如果完全不裝-fp只跑-901-base)

---

## 方案 A — 兩個 layered images（推薦）

你 build **兩個獨立的 image**：

1. `domino9:9.0.1` — 只裝 base，來自 `dockerfiles/domino9.0.1-base-ubi7/`
2. `domino9:9.0.1fp10` — 在 base 上疊 FP10，來自 `dockerfiles/domino9.0.1-fp10-on-base/`

FP 的 Dockerfile 是一個小小的衍生 image、其 `FROM` 就是 base。Build：

```bash
# Step 1 — base image (~10 min first time)
cd dockerfiles/domino9.0.1-base-ubi7
cp /path/to/DOMINO_9.0.1_64_BIT_LIN_XS_EN.tar .
docker build -t domino9:9.0.1 .

# Step 2 — FP10 layered on top (~3-4 min, base layers cached)
cd ../domino9.0.1-fp10-on-base
cp /path/to/domino901FP10_linux64_x86.tar .
docker build -t domino9:9.0.1fp10 .
```

實際部署用 `domino9:9.0.1fp10`。

### 優點

- **可重現**：`Dockerfile` 定義了 FP 版本 → 不會 drift
- **base 有 cache**：換 FP 重 build 時只重做小小的 FP layer
- **標準 docker 慣用法**：`FROM <base>` 就是 layered images 原本被設計來用的方式
- **同一 base 可衍生多個 FP**：可從同一個 `domino9:9.0.1` build 出 `domino9:9.0.1fp7` 和 `domino9:9.0.1fp10`，不必重裝 base

### 缺點

- 要維護兩個 `docker build` 動作與兩個 Dockerfile
- 最終 image 比單發版本多 1 個 layer（可忽略 — image 大小 ~ 相同）

### 何時選 A

- 你有可能需要比較或回退不同 FP 版本
- 你有 CI 在 build image、想善用 layer cache
- 你想要乾淨的 immutable-image 部署故事
- **拿不定主意時請選 A** — 它是 docker-native 的答案

---

## 方案 B — Runtime install + docker commit

啟動 base image、用 `docker exec` 互動式跑 FP 安裝步驟、再 `docker commit` 改動後的 container 為新 image。

這最接近 bare-metal Domino 管理時代「在 VM 內裝 FP」的心智模型。

### 步驟

```bash
# 1. Build the base image (once)
cd dockerfiles/domino9.0.1-base-ubi7
docker build -t domino9:9.0.1 .

# 2. Boot the base container (use a name we can refer to)
docker volume create domino9-fpprep-data
docker run -d \
  --name domino9-fpprep \
  -p 11352:1352 -p 18080:80 -p 18585:8585 \
  -v domino9-fpprep-data:/local/notesdata \
  domino9:9.0.1
# Container enters setup-listener mode. Do NOT do setup wizard yet — we want
# to apply FP first so the resulting image is "9.0.1 FP10 + ready for setup".

# 3. Copy the FP tar into the container
docker cp domino901FP10_linux64_x86.tar domino9-fpprep:/tmp/

# 4. Stop the container BEFORE the FP install — FP modifies binaries that
#    the server process is using, will corrupt if hot-patched.
docker stop domino9-fpprep

# 5. Run the FP install via `docker run` against the stopped container's
#    state (use --rm and override entrypoint with /bin/bash).
docker run --rm \
  --user root \
  -v domino9-fpprep-data:/local/notesdata \
  --volumes-from domino9-fpprep \
  --entrypoint bash \
  domino9:9.0.1 \
  -c '
    set -e
    mkdir -p /tmp/fp10
    cp /tmp/domino901FP10_linux64_x86.tar /tmp/fp10/
    cd /tmp/fp10
    tar xf domino901FP10_linux64_x86.tar
    cd linux64/domino
    export NUI_NOTESDIR=/opt/ibm/domino
    ./install -script script.dat
    rm -rf /tmp/fp10
    echo "[ok] FP10 installed into /opt/ibm/domino"
  '

# Note: the above is a SIMPLIFIED illustration. The actual situation is
# more nuanced because `docker run --rm` against a STOPPED container's
# volumes is unusual. The truly clean way is:
#
#   docker start domino9-fpprep
#   docker exec --user root domino9-fpprep bash -c '...install steps...'
#
# But then the running server's binaries are being modified, which is
# risky. See "caveat 1" below.

# 6. Once FP install completed cleanly inside the container, commit to
#    a new image:
docker commit \
  --change 'LABEL fp.version="10" fp.installed_at="2026-05-21T22:00:00Z"' \
  domino9-fpprep \
  domino9:9.0.1fp10-runtime

# 7. Verify
docker images domino9
# REPOSITORY  TAG                   IMAGE ID  SIZE
# domino9     9.0.1fp10-runtime     <id>      ~1.6GB
# domino9     9.0.1                 <id>      ~1.4GB

# 8. Cleanup the prep container
docker rm domino9-fpprep
docker volume rm domino9-fpprep-data

# 9. Use the new image for actual deployment
docker run -d --name domino9 \
  -p 1352:1352 -p 80:80 -p 8585:8585 \
  -v domino9-data:/local/notesdata \
  domino9:9.0.1fp10-runtime
```

### 注意事項

1. **裝 FP 期間 server 必須停**。FP 會改 `/opt/ibm/domino/notes/latest/linux/*` — 也就是 running server 正在開的同一批 binary。熱 patch 會搞壞 memory mapping、讓 server crash，最糟會留下狀態不一致的環境。`docker stop` 步驟不可省。

2. **`docker exec` 的修改是 ephemeral**。如果你 `docker exec` 進 running container 裝 FP，然後 `docker rm` 該 container 卻沒先 `docker commit`，**FP 就消失了**。下一次 `docker run` 又會從原始 image 啟動成 base 狀態。這是 docker 新手在這套方案上最常犯的第 1 號錯誤。

3. **`docker commit` 不是 declarative 的**。產生的 image 沒有對應的 `Dockerfile` 可重跑。半年後你不會記得當初 `docker exec` 做了什麼。如果在意可重現性，請改用方案 A。

4. **Image 會變大**。FP 安裝會動到大量檔案；產出的 overlay layer 會把 delta 全都疊成一個肥 layer，image 比方案 A 等價版本略大。

### 何時選 B

- 你在做原型 / 實驗、不需要可重現性
- 你用的是 legacy build pipeline、不支援多階段 / FROM-chain 的 Dockerfile
- 你就是想要「跟 Domino-on-VM 一樣的感覺」的心智模型
- 從 bare-metal Domino 9.0.1 base + FP10 安裝做一次性遷移

---

## 方案 C — 把 FP 持久化在 volume 內（不推薦）

理論上你可以把 `/opt/ibm/domino` 也掛成 volume，這樣 FP 檔案可以跨 container 重建還留著：

```bash
docker volume create domino9-program
docker run ... \
  -v domino9-program:/opt/ibm/domino \
  -v domino9-data:/local/notesdata \
  domino9:9.0.1
# Then docker exec to install FP into the volume
```

**不要這樣做。** 理由：

- Volume 掛在既有目錄上會把 image 的 `/opt/ibm/domino/` 內容遮蔽掉。你得另寫一步從 base 安裝拷貝資料填進 volume，operationally 很痛。
- 把「程式檔放 volume」與「資料檔放 volume」混在一起，違反 docker 的心智模型：image = 不可變的程式、volume = 可變的資料。
- 如果 `docker pull` 或重 build base image（例如要拿 UBI 7 的 security update），新 base 的 `/opt/ibm/domino` 會被舊 volume 蓋住，你的 security update 就消失了。
- Backup / restore 語義變得很怪：程式碼會混進你的資料 backup。

只列出來求完整。請用 A 或 B。

---

## 三方案並列比較

| 面向 | A：Layered images | B：Runtime + commit | C：Volume |
|---|---|---|---|
| 可重現 | ✅ Dockerfile 已定義 | ❌ ad-hoc | ❌ |
| 快速測多 FP | ✅ base 有 cache | ❌ 每次都得重 build | ⚠️ 勉強 ok |
| docker history 看得到版本 | ✅ FP layer 可見 | ⚠️ 只能透過 LABEL | ❌ |
| 對 Domino admin 的心智模型 | ⚠️「全寫在 Dockerfile」 | ✅「裝 FP 進 container」 | ❌ |
| 標準 docker 慣用法 | ✅ | ⚠️ | ❌ |
| 推薦度 | **✅** | ⚠️ 適合 one-off | ❌ |

---

## 那如果完全不裝 FP？（只跑 9.0.1 base）

你當然可以直接部署 `domino9:9.0.1`，**完全不裝**任何 FP。這是 Domino 支援的（FP 是 optional）但：

- 9.0.1 base 是 2013 年的版本，後續 FP 修掉的已知 CVE（Java、OpenSSL、TLS protocol）你都沒拿到
- HCL 對 9.0.1 base（沒裝 FP10）的 support boundary 比 9.0.1 FP10 還嚴格
- 你會少掉 FP8+ 才有的 SHA-2 / TLS 1.2 / 新 CSRF 修補

實務建議：就算是 Dev / Test，也至少裝到 FP10（9.x 系列的最後一個 FP）。完整 image `dockerfiles/domino9.0.1-fp10-ubi7/` 一次就能搞定 — 除非你有明確理由要把 base 跟 FP 分開，否則就用它。

---

## 延伸閱讀

- `BUILD.md` — 主 SOP（用的就是一次 build 完的 `domino9.0.1-fp10-ubi7/`）
- `TROUBLESHOOTING.md` §2 — 為什麼 FP installer 要用 `-script` 而非 `-silent`
- `TROUBLESHOOTING.md` §6 — 為什麼 UBI 8 不能當 base
