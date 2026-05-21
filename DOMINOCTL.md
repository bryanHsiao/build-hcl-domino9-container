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
