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

`desktop/` holds a launcher, an icon and an installer — because a CLI that lives in
`/usr/local/bin` is invisible to someone who works from the application menu:

```bash
scp -r desktop target:/tmp/
ssh target 'sudo bash /tmp/desktop/install-desktop-integration.sh /tmp/localsend-cli-386'
```

That installs:

| path | what |
|---|---|
| `/usr/local/bin/localsend-cli` | the binary |
| `/usr/share/applications/localsend-cli.desktop` | menu entry **LocalSend** → opens the TUI dashboard in a terminal |
| `/usr/share/applications/localsend-cli-receive.desktop` | menu entry **LocalSend (receive)** → `localsend-cli receive`, approving each sender |
| `/usr/share/icons/hicolor/scalable/apps/localsend-cli.svg` | scalable icon (a generic send glyph, deliberately *not* the upstream logo) |

Both entries use `Terminal=true`, so the desktop opens them in whatever terminal emulator is
configured — no terminal-specific flags, works on XFCE/qterminal, GNOME, or anything else.
`desktop-file-validate` passes with no hints; `update-desktop-database` is run for you.

## A note on the binary in this repo's releases

The released binary is built from upstream `v1.3.2` **plus** `patches/0001-richer-help-and-version-flag.patch`:

* `--help` now lists every command with usage notes, environment variables, config file locations
  and a dozen worked examples (upstream's help was a bare command list).
* `--version` / `-V` / `version` exist and print the build target (`linux/386`), which is the
  point of this repo. Upstream rejects the flag with `flag provided but not defined`.

Apply it yourself with `git apply`, or just build without it — the CLI works either way.


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
