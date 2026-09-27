# Silent receive failures: two firewalls and a VPN can drop LocalSend with no visible error on either side

Filed from a real debugging session between a ThinkPad (sender, official LocalSend app under Flatpak)
and the IdeaPad S10-2 (receiver, this toolkit's `localsend-cli`). Every layer "looked fine" at first
glance and the failure surface was misleading at each step. Documenting it because the failure modes
are all silent, and because two of them cost most of the time for reasons that had nothing to do with
LocalSend.

## Symptom

* Peers visible in the app's device list, but nothing can be sent to the receiver.
* Sending produced either nothing at all, a generic "handshake error", or
  **"the recipient has rejected the request"**.
* The receiver's console showed no approval prompt — as if no request had arrived.
* Meanwhile `ping`, `ssh` and ordinary file transfer between the same two hosts worked perfectly.

## Root causes found (three, stacked — each hid the next)

### 1. Sender: VPN routed the discovery multicast into the tunnel

With Mullvad (any kill-switch VPN with policy routing), the LocalSend discovery group is sent into the
tunnel interface, so no LAN peer can hear it:

```
$ ip route get 224.0.0.167
multicast 224.0.0.167 dev wg0-mullvad table 1836018789 src 10.x.x.x
```

Mullvad's "LAN sharing" only exempts **private unicast** ranges; multicast falls through the gap.
Verified by capture: the announcement appeared on `wg0-mullvad` and never on the Wi-Fi interface.

### 2. Sender: ufw's default-deny dropped the inbound discovery multicast

ufw's stock rule set carries exceptions for exactly two multicast services:

```
ip daddr 224.0.0.251 udp dport 5353 accept     # mDNS
ip daddr 239.255.255.250 udp dport 1900 accept # SSDP
```

`224.0.0.167` is not among them, and the chain's multicast passes
(`fib daddr type multicast return` in `ufw-not-local`) only hand the packet on for evaluation — they do
not accept it. So announcements were counted as received by the kernel (`InMcastPkts` climbed, mDNS
flowed normally) and then dropped before any socket saw them.

### 3. Receiver: ufw allowing only SSH silently swallowed the transfer

The receiver's own ufw contained exactly one rule:

```
22/tcp  ALLOW  192.168.0.0/24   # ssh from LAN
```

everything else inbound → **silent drop**. So the sender's TCP connection sat in `SYN-SENT` forever,
and the receiver answered a SYN with neither SYN-ACK nor RST. The app reported a handshake error or a
rejection, while the actual cause was a filter on the far machine.

## Debugging traps (the expensive part)

1. **A live ruleset can hide behind an "inactive" service.** `systemctl is-active ufw` → `inactive`,
   yet 384 lines of ufw chains with `-P INPUT DROP` were loaded in the kernel. Service state is not a
   firewall check; use `ufw status`, `iptables -S` or `nft list ruleset`.
2. **A privileged read that fails looks exactly like a clean machine.** `sudo -n nft list ruleset`
   returned nothing because sudo could not authenticate non-interactively — read as "no rules exist".
   Always confirm the read succeeded before concluding anything from its emptiness.
3. **A filter answers a SYN with nothing at all; a closed port answers with RST.** Silent drop versus
   refusal is the single most useful discriminator when a connection hangs.
4. **`ss -tan state syn-recv | wc -l` counts the header**, so it reports `1` with zero half-open
   sockets. Use the `Tcp: PassiveOpens` counter from `/proc/net/snmp` around a known connect attempt:
   it increments only when a SYN actually reaches the TCP stack.
5. **Multicast cannot be `ct mark`ed.** conntrack does not track multicast, so the "allow incoming"
   half of Mullvad's documented split-tunnel pattern (which uses `ct mark set`) does not apply to
   discovery traffic — the packet is dropped instead.
6. **A headless receive mode cannot ask.** Started without a TTY it rejects every session with
   *"approval is required but no interactive approval provider is available"*, which the sender sees
   only as a rejection. Run it in a terminal, trust the sender, or use quick-save.
7. **`pkill -f <pattern>` can kill your own shell** when the pattern text appears in the command line
   running it (e.g. the same `sed` command that renames the file). Kill by PID.
8. **Background jobs get stdin from `/dev/null`**, so `sudo -S` fed by a pipe cannot read the password
   and reports "no password was provided". Keep sudo in the foreground and background the child.

## What resolved it

Three independent fixes, all LAN-scoped, none of them LocalSend's fault:

**Sender — keep discovery off the VPN tunnel** (routing only; the fix is the meta mark, not a filter):

```nft
table inet excludeTraffic {
    chain excludeOutgoing {
        type route hook output priority 0; policy accept;
        ip daddr 224.0.0.167 counter ct mark set 0x00000f41 meta mark set 0x6d6f6c65
    }
}
```

**Both machines — let LocalSend through ufw:**

```bash
sudo ufw allow from 192.168.0.0/24 to any port 53317 proto udp comment 'LocalSend discovery'
sudo ufw allow from 192.168.0.0/24 to any port 53317 proto tcp comment 'LocalSend transfer'
```

Both rules are needed: UDP for discovery multicast, TCP for the actual HTTPS transfer.

**Receiver — run the approval prompt somewhere it can prompt**, i.e. in a terminal (the menu entry in
`localsend-386/desktop/` does this), then accept once with `a` to add the sender to the trust list so
it is never asked again.

Result: the text send arrived; a 5140-byte `.txt` landed in `~/Downloads/localsend-cli`, and the
sender's socket went from `SYN-SENT` to `ESTAB`.

## Verification used (reusable)

* `python3` stdlib listener on the discovery group — confirms announcements are received.
* `ls_raw_announce.py` — prints the raw announcement JSON (check `protocol`, `port`, `fingerprint`).
* `Tcp: PassiveOpens` deltas — proves whether a SYN reached the receiver's TCP stack.
* `dumpcap` as an unprivileged member of the `wireshark` group — no root needed for captures.
* `openssl x509 -in cert.pem -outform DER | sha256sum` vs the announced fingerprint — proves pinning
  cannot be the cause before blaming TLS.

## Related

* `docs/LOCALSEND-DISCOVERY.md` — the write-up of layers 1 and 2.
* `v1.3.2-local.4` — receive mode now prints this device's own name, fingerprint and port, which is
  what made "is the receiver even the thing I think it is" answerable at a glance.
