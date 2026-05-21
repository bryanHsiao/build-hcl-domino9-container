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

## Troubleshooting

| Symptom | Action |
|---|---|
| "Network Communication error" on Connect dialog | Verify host port matches `-p <host>:8585` mapping; verify TCP reachable via `Test-NetConnection` |
| Same dialog but error after clicking OK (not Ping) | Most likely the bundled J9 JVM OOM. This Dockerfile already patches it (`-Xmx512m`). If you still see it, see [TROUBLESHOOTING.md](TROUBLESHOOTING.md) §3. |
| Wizard says "Cannot find server in Domino directory" | The existing server's `names.nsf` does not have a Server document for the new server name. Have your admin pre-register it (step 1). |
| `names.nsf` replication appears to hang | Check directory size on the existing server; large directories (10000+ persons) can take 10–20 min. Look at `docker logs domino9` for replicate progress. |
| Wizard finishes but server keeps relaunching wizard on restart | This Dockerfile uses `^Setup=[0-9]` heuristic to detect setup-complete, which is correct for Domino 9 (no `ServerName=` line in notes.ini). If you still see this, manually check `docker exec domino9 grep "^Setup=" /local/notesdata/notes.ini` |
| Server starts but HTTP not listening | Check that `HTTP` is in the `ServerTasks=` line of `notes.ini`. If missing, `docker exec domino9 /opt/ibm/domino/bin/server -c "load http"` |

See [TROUBLESHOOTING.md](TROUBLESHOOTING.md) for deeper diagnosis.
