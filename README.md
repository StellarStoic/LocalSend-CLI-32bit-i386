# netbook-32bit-toolkit

Tooling for keeping a 32-bit-only x86 laptop (Intel Atom N2xx / Pineview class) alive on a
modern-ish Debian-derived system — plus a recipe for getting **LocalSend** working on it.

Written while rescuing a Lenovo IdeaPad S10-2 (Intel Atom N280, 2 GB RAM, i686 only) running
Kali Linux rolling:

1. **`localsend-386/`** — LocalSend has never shipped a 32-bit Linux build (verified across all
   27 GitHub releases, 1.3.1 → 1.18.2; Flutter's Linux embedder targets x64/arm64/riscv64 only,
   so building the official app for i386 is impossible). This directory cross-compiles a
   third-party CLI that speaks the same protocol v2/v3, for `linux/386`, and verifies it with a
   protocol-level test client.
2. **`kali-i386-upgrade/`** — automation that takes a stranded i386 Kali install through a
   ~2.5-year Debian bookworm → trixie + 64-bit `time_t` (t64) migration: 3053 package operations,
   detached from SSH, with mirror-conflict recovery and stale-package unblocking.
3. **`hermes-i686/`** — a preflight check and lockfile analyser for the question "can
   [Hermes Agent](https://hermes-agent.nousresearch.com/docs) run natively on this thing?".
   Short answer: no, and the analyser shows exactly which dependencies say so.

## Credits / upstream (none of this is my code)

* **LocalSend** — <https://github.com/localsend/localsend> (Apache-2.0), <https://localsend.org>.
  The app this repo works around; not affiliated.
* **localsend-cli** — <https://github.com/tingkai-c/localsend-cli> (MIT), a fork of
  <https://github.com/meowrain/localsend-go>. This is the code that gets cross-compiled here.
* **localsend protocol** — <https://github.com/localsend/protocol>.
* **Hermes Agent** — <https://github.com/NousResearch/hermes-agent>.

## Is there a supported 32-bit path I'm missing?

As of September 2026, no: no LocalSend build for `linux-i386` in any release, no 32-bit Linux
Python from `python-build-standalone` (i686 exists only for Windows), no 32-bit Linux Node.js
since v9.11.2 (2018), and Kali stopped building i386 kernels/images in 2024.4 (packages
continued, kernels did not). The i386 package index still exists on kali-rolling, which is why
the upgrade in `kali-i386-upgrade/` works at all.

## Requirements

* A 32-bit **or** 64-bit Linux box to build from (cross-compiling is the whole point — you do
  not want to compile on the target).
* Go 1.22+ (for the LocalSend CLI), and optionally rustup if you go down the Hermes rabbit hole.
* SSH access to the target machine, with passwordless sudo for the upgrade scripts
  (they read the password from a file you control — see `kali-i386-upgrade/README.md`).

## Read this before touching a real machine

`docs/PITFALLS.md` is the distilled version of what actually went wrong on a real run —
two Kali packaging bugs, a mirror desync, a helper-in-`/tmp` trap, and a genuinely dangerous
`apt autoremove`. It is the most useful file in this repo.

## License

MIT for the scripts in this repository (see `LICENSE`). Upstream projects keep their own
licenses; nothing from them is vendored here.
