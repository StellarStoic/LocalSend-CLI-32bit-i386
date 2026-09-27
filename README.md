# LocalSend CLI for 32-bit x86 (i386)

Getting **LocalSend** working on a 32-bit-only x86 laptop.

LocalSend has never shipped a 32-bit Linux build: verified across all 27 GitHub releases
(1.3.1 → 1.18.2) the artifacts are `linux-x86-64` and `linux-arm-64` only, and Flutter's Linux
embedder targets x64/arm64/riscv64 — so the official app cannot be built for i386 either. This repo
cross-compiles a third-party CLI that speaks the same protocol (v2/v3) for `linux/386`, verifies it
against a stdlib-only protocol client, and ships the binary with its hash.

## What's here

* **`localsend-386/`** — cross-compile, install and verify the 32-bit LocalSend CLI. Includes
  `desktop/` for real menu entries (**LocalSend**, **LocalSend (receive)**, and a danger-gated
  auto-accept launcher) with icons, a helper to pin a stable device name, and `patches/` showing
  exactly what this build changes against upstream. Releases carry the built binary and its sha256.
* **`docs/LOCALSEND-DISCOVERY.md`** — why LocalSend discovery fails on Linux, and the two layers
  that do it: a kill-switch VPN routing the discovery multicast into the tunnel, and ufw's
  default-deny policy dropping it inbound.
* **`docs/issue-silent-receive-failures.md`** — the full debugging session behind
  [issue #1](https://github.com/StellarStoic/localsend-cli-i386/issues/1), including the eight traps
  that hid the cause.

## Quick start

```bash
sha256sum -c SHA256SUMS                       # from the release
sudo install -m0755 localsend-cli-386 /usr/local/bin/localsend-cli
localsend-cli --version                       # localsend-cli v1.3.2-local.4 (linux/386)
localsend-cli --help                          # every command, env var and worked example
```

Receiving? Run it where it can prompt you, or install the menu entries from `localsend-386/desktop/`.
It prints the name peers see for this machine, which is the thing you otherwise have to walk to
another device to discover:

```
INFO [IdeaPad] LocalSend receive mode
INFO   device name : IdeaPad
INFO   fingerprint : 0786dcbd203aef22…
INFO   port        : 53317
```

## Credits / upstream (none of this is my code)

* **LocalSend** — <https://github.com/localsend/localsend> (Apache-2.0), <https://localsend.org>.
  The app this repo works around. Not affiliated with or endorsed by the project.
* **localsend-cli** — <https://github.com/tingkai-c/localsend-cli> (MIT), a fork of
  <https://github.com/meowrain/localsend-go>. This is the code that gets cross-compiled here.
* **LocalSend protocol** — <https://github.com/localsend/protocol>.

## Is there a supported 32-bit path I'm missing?

As of September 2026, no: no LocalSend build for `linux-i386` in any release, no 32-bit Linux Python
from `python-build-standalone` (i686 exists only for Windows), and no 32-bit Linux Node.js since
v9.11.2 (2018).

## Requirements

* Go 1.22+ if you build it yourself — or just take a released binary, which needs nothing on the
  target machine.
* A 64-bit machine to build from. Cross-compiling is the whole point; do not compile on the target.

## See also

**<https://github.com/StellarStoic/netbook-32bit-toolkit>** — the Kali i386 upgrade automation and
the Hermes-on-i686 feasibility analysis built for the same machine (a Lenovo IdeaPad S10-2, Intel
Atom N280, 2 GB RAM, 32-bit only), if you want the rest of the story behind this client.

## License

MIT for the scripts in this repository (see `LICENSE`). Upstream projects keep their own licenses;
nothing from them is vendored here.
