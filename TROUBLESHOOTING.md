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
