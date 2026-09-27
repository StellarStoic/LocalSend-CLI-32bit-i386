# LocalSend on 32-bit x86 Linux

**The official app cannot run on a 32-bit-only x86 machine, at any version.** Verified, not
assumed:

* All 27 releases of `localsend/localsend` (1.3.1 → 1.18.2, page 1 and 2 of the releases API):
  Linux artifacts are only `linux-x86-64` and `linux-arm-64` (arm64 added in 1.13).
* The oldest release is still 64-bit: `LocalSend-1.3.1.AppImage` → `ELF 64-bit LSB executable,
  x86-64`.
* The project's own CI only contains `build_linux_{deb,tar,appimage}_x64/_arm64` workflows.
* Flutter (what LocalSend is built with) targets Linux desktop as `linux-x64`, `linux-arm64`,
  `linux-riscv64` — there is no 32-bit x86 engine, so building it yourself cannot work either.

What *does* work: a third-party CLI that implements the same LocalSend protocol v2/v3, built for
`linux/386`. It is MIT-licensed and you cross-compile it in a couple of minutes.

| | |
|---|---|
| upstream | <https://github.com/tingkai-c/localsend-cli> (fork of <https://github.com/meowrain/localsend-go>) |
| protocol | <https://github.com/localsend/protocol> |
| our build | ELF 32-bit LSB executable, Intel i386, **statically linked**, ~32 MB |
| verified | received a file over the real protocol from an independent client — sha256 matched |

## Build

```bash
bash build.sh
# -> localsend-cli-386, static, no libc/libssl/GTK/Node needed on the target
```

## Install on the target

```bash
scp localsend-cli-386 target:/tmp/
ssh target 'sudo install -m0755 /tmp/localsend-cli-386 /usr/local/bin/localsend-cli'
ssh target 'localsend-cli --help'
```

## Desktop menu entry (so it's not a terminal-only tool)

`desktop/` holds the launchers, icons and an installer — because a CLI that lives in
`/usr/local/bin` is invisible to someone who works from the application menu:

```bash
scp -r desktop target:/tmp/
ssh target 'sudo bash /tmp/desktop/install-desktop-integration.sh /tmp/localsend-cli-386'
bash desktop/set-device-name.sh "IdeaPad"      # optional: stable name (no sudo needed)
```

That installs:

| path | what |
|---|---|
| `/usr/local/bin/localsend-cli` | the binary |
| `/usr/local/bin/localsend-cli-mode` (+ `-receive`, `-quicksave` symlinks) | one wrapper; the mode follows the name it's called by |
| `/usr/share/applications/localsend-cli.desktop` | **LocalSend** → opens the TUI dashboard in a terminal |
| `/usr/share/applications/localsend-cli-receive.desktop` | **LocalSend (receive)** → approves each sender |
| `/usr/share/applications/localsend-cli-quicksave.desktop` | **LocalSend (receive, auto-accept — DANGER)** → behind the danger gate |
| `/usr/share/icons/hicolor/scalable/apps/localsend-cli{,-warning}.svg` | scalable icons (generic send glyph — deliberately *not* the upstream logo) |

All entries use `Terminal=true`, so the desktop opens them in whatever terminal emulator is
configured — no terminal-specific flags. `desktop-file-validate` passes with no hints, and
`update-desktop-database` is run for you.

### The danger gate, and why it exists in this shape

`--quick-save` accepts *every* incoming transfer from *any* device on the network without asking.
That is a legitimate thing to want (a fixed target on a trusted home LAN) and a terrible default,
so it is exposed as a third menu entry rather than hidden or silently enabled:

* a red block-capital warning that says, in plain words, what will be written where, that there is
  no authentication beyond being on the same LAN, that received files are untrusted input, and
  that it cannot warn you about a filling disk;
* the safer alternative is spelled out inline: plain receive + "accept and pair" once per device;
* it requires **typing the word `danger`** — Enter alone does nothing;
* it refuses to run without a TTY, so a script cannot pipe its way past the gate;
* it is not persisted: closing the window ends it, the next launch is safe again.

### Pre-flight: never fail with a raw bind error

Only one LocalSend can hold a port, so starting a second instance used to die with
`listen tcp :53317: bind: address already in use` — *after* printing a success banner. The wrapper
now checks the port you're actually going to use (`--port=N` is honoured, so a second instance on
another port still works) and explains the conflict instead, including which pid holds it.

### Stable device name

Left unset, the CLI generates a new random adjective+noun **every run**, so the machine shows up as
"Silent Shark", then "Happy Owl", and is impossible to recognise in another device's list.
`set-device-name.sh` pins it in `~/.config/localsend-cli/config.yaml` (backing the file up first).


## A note on the binary in this repo's releases

The released binary is built from upstream `v1.3.2` **plus**
`patches/0001-cli-improvements.patch`:

* `--help` now lists every command with usage notes, environment variables, config file locations
  and a dozen worked examples (upstream's help was a bare command list).
* `--version` / `-V` / `version` exist and print the build target (`linux/386`). Upstream rejects
  the flag with `flag provided but not defined`.
* Flags written **after** the subcommand now actually apply. Upstream's docs promise
  `receive --port=1234` and `--port=1234 receive` are equivalent, but Go's `flag` package stops
  parsing at the first positional token, so the first form was silently ignored — the port stayed
  53317. The patch reorders argv before parsing, carrying `--flag value` pairs along so that
  `--output-dir /some/path` is not split.
* Receive mode prints this device's **own** identity before it starts listening. The alias is what
  every other device shows for this machine, so it belongs in the console too:

  ```
  INFO [IdeaPad] LocalSend receive mode
  INFO   device name : IdeaPad
  INFO   fingerprint : 0786dcbd203aef22…
  INFO   port        : 53317
  ```

  Without it you have to check another device to learn what this one calls itself — and since an
  unset `device_name` makes the CLI invent a new name on every launch, that name is not even
  guessable.
* **Text can be sent from the clipboard or a pipe.** `send-text --clipboard` reads the system
  clipboard and `send-text -` reads stdin (`xclip -o | … send-text -`), so text no longer has to be
  pasted into a file first. The installer adds a **LocalSend (send clipboard)** entry that shows the
  text, offers to edit it, then hands off to the recipient picker. Two supporting fixes came with it:
  a lone `-` is no longer hoisted as a flag by the argv reordering, and the wrapper's port
  pre-flight no longer blocks sending (sending never binds 53317, so a running receiver must not
  stop you from sending).
* **A device no longer offers itself as a send target.** It joins the same multicast group it
  broadcasts to, so it heard its own announcement and listed itself — visible as
  `IdeaPad 192.168.0.58` inside the picker on the IdeaPad. Filtered in both discovery paths by
  fingerprint and by local interface address, so a multi-homed box cannot slip through either.
* **Text pasted into the dashboard no longer vanishes.** The send box only accepted `. / \ : - _`
  and alphanumerics, so a pasted sentence — which arrives as *one* keystroke message holding the whole
  string — was dropped entirely, and spaces were stripped from anything typed. That made it look as
  though there were no way to send text at all. The box now takes printable input of any kind and
  sends what it is given as a message when it is not a file on disk; a mistyped *path* is still
  reported as a missing file rather than quietly sent as prose.
  (`TestDashboardSendBoxAcceptsPastedText` covers it.)

Apply it yourself with `git apply`, or just build without it — the CLI works either way, minus the
documented conveniences. Verified to apply cleanly to upstream `main` == `v1.3.2` (`64b192a`).

Binary history in this repo's releases:

| tag | what changed |
|---|---|
| `v1.3.2-local.1` | richer `--help`, added `--version`. Still silently ignored flags after the subcommand (upstream behaviour). |
| `v1.3.2-local.3` | fixes flag ordering; supersedes local.1. |
| `v1.3.2-local.4` | receive mode names the device in its own console output. |
| `v1.3.2-local.5` | `send-text --clipboard` / `send-text -` (stdin), and a **LocalSend (send clipboard)** menu entry. |
| `v1.3.2-local.6` | stops the device listing **itself** as a send target. |
| `v1.3.2-local.7` | the dashboard send box takes **text**, not only file paths — pasting a sentence works. **Use this one.** |



## Use

```bash
localsend-cli                                     # TUI dashboard (recommended)
localsend-cli --quick-save receive                # headless receive, auto-accept
localsend-cli --output-dir ~/Downloads receive    # explicit landing directory
localsend-cli send /path/to/file                  # pick a peer in the TUI, Space toggles multi-select
localsend-cli send-text "hello"
```

* Default port **53317** (matches the official app), discovery over UDP multicast
  `224.0.0.167:53317`, transfer over HTTPS — so it interoperates with the official apps on
  Android/iOS/desktop out of the box.
* Config: `~/.config/localsend-cli/config.yaml`.
* The first transfer from an unknown device prompts for approval (`Y`), unless you pass
  `--quick-save` or trust the sender's fingerprint.
* Running headless over SSH logs `Error copying to clipboard: exit status 1` — harmless, there is
  no X clipboard to write to.

## Verify it (recommended)

```bash
# on the target
localsend-cli --port=53317 --quick-save --output-dir /tmp/ls-test receive &

# from another machine on the same LAN
python3 send_test.py <target-ip> 53317
sha256sum /tmp/ls-test/localsend-protocol-test.txt   # must match the sha256 printed above
```

`send_test.py` is a stdlib-only LocalSend v2 client written for exactly this check — no official
app, no browser, no dependencies.

## If you would rather not use a CLI

Alternatives that run on 32-bit Linux, none of which interoperate with LocalSend:

* **croc** — official 32-bit Linux builds (`croc_v*_Linux-32bit.tar.gz`), own relay protocol.
* **Syncthing** — official `syncthing-linux-386-*.tar.gz`, continuous folder sync, web UI.
* **PairDrop / Snapdrop** — nothing to install, works in a browser, but does not speak LocalSend.
* `scp` / `rsync` / `python3 -m http.server` — always available, always works.
