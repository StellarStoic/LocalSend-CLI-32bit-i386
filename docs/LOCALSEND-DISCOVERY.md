# Why LocalSend discovery fails on Linux (and how to fix it)

LocalSend discovers peers by sending JSON announcements to the multicast group
`224.0.0.167:53317` (RFC 2365, administratively scoped). On Linux there are two
independent, outbound and inbound, ways to break that — and they stack, so fixing one
leaves the symptom intact. Both were hit in practice on a ThinkPad running Ubuntu with
a WireGuard VPN and ufw.

Symptom: the device list stays empty in both directions, or one direction only, while
plain unicast works fine (SSH/ping to the same host is fine).

## Layer 1 — outbound: the VPN routes multicast into the tunnel

A kill-switch VPN (Mullvad's client is the reference case) sends every process's traffic
into the tunnel unless it carries the routing mark `0x6d6f6c65`. Its "LAN sharing"
feature only exempts **private unicast** ranges, so multicast falls through:

```
$ ip route get 224.0.0.167
multicast 224.0.0.167 dev wg0-mullvad table 1836018789 src 10.x.x.x
```

The announcement is handed to the tunnel interface, where no LAN peer can hear it, and
the app's own membership is set up on that interface too, so it is deaf as well.

Fix — mark packets to that group for exclusion, using the pattern from
<https://mullvad.net/help/split-tunneling-with-linux-advanced>:

```nft
table inet excludeTraffic {
    chain excludeOutgoing {
        type route hook output priority 0; policy accept;
        ip daddr 224.0.0.167 ct mark set 0x00000f41 meta mark set 0x6d6f6c65
    }
}
```

After the rule, `ip route get 224.0.0.167 mark 0x6d6f6c65` shows the LAN interface, and a
capture on the LAN interface shows the announcement while the tunnel interface shows
nothing. Persist it with a small systemd unit that runs `nft -f` at boot; make it
idempotent by deleting the table first, so re-running is safe.

Do **not** copy the "allow incoming" half of that documentation example for multicast.
`ct mark set` cannot work for multicast — conntrack does not track it, and nftables
drops packets it cannot attach a ct mark to. Mullvad's input chain already accepts any
packet whose source is in a private range, so nothing is needed there anyway.

## Layer 2 — inbound: ufw's default deny (the one people miss)

ufw's default `deny (incoming)` policy drops LocalSend's multicast. Its stock rule set
carves out exceptions for exactly two multicast services:

```
ip daddr 224.0.0.251 udp dport 5353 accept     # mDNS
ip daddr 239.255.255.250 udp dport 1900 accept # SSDP
```

`224.0.0.167` is not among them, and the chain's multicast passes (`fib daddr type
multicast return` in `ufw-not-local`) only hand the packet on to be evaluated — they do
not accept it. So the packet is counted as received by the kernel (`InMcastPkts`
climbs, mDNS traffic flows normally) and is then dropped before any socket sees it.

Fix:

```bash
sudo ufw allow from 192.168.0.0/24 to any port 53317 proto udp   # discovery
sudo ufw allow from 192.168.0.0/24 to any port 53317 proto tcp   # transfers
```

Scoping to the LAN keeps it minimal; ufw rules survive reboots.

## Distinguishing the layers when debugging

| Observation | Meaning |
|---|---|
| `InMcastPkts` rises during a peer's burst, socket receives nothing | arriving, then dropped — check the inbound firewall (ufw, iptables/nftables) |
| `InMcastPkts` flat during a burst | not arriving — AP/switch filtering, IGMP snooping without a querier, or wrong subnet/VLAN |
| Works one direction only | the *receiving* machine's firewall, not the network |
| Peers visible but transfers fail | same port over TCP — check the TCP rule as well |

Test with a listener bound to the group on a free port first (for example 53999): if the
free port receives but 53317 does not, something on 53317 is competing for delivery
rather than the network being broken.

## Names: every device shows *its own* self-declared alias

LocalSend generates a placeholder name on first run ("Great Carrot", "Sour Potato") and
keeps it until changed. Peers display whatever the other device advertises, so a device
appearing as "Sour Potato" can only be renamed **on that device** — there is no way to
override a peer's name centrally. Check yours in:

```
~/.var/app/org.localsend.localsend_app/data/localsend_app/shared_preferences.json
    flutter.ls_alias: 'Great Carrot'
```

For this toolkit's CLI the equivalent is `device_name:` in
`~/.config/localsend-cli/config.yaml`. Note the CLI generates a **new** random name on
every launch when that key is unset (`NameOfDevice` is `yaml:"-"`, resolved at runtime),
so an unconfigured install changes identity each time it starts — always pin it.

Finally: a client only announces while it is actively scanning. A desktop LocalSend
sitting on the Receive tab broadcasts nothing, so "nobody can see me" may just mean the
Send tab is closed.

## Worked example, including the traps that hid these layers

[`issue-silent-receive-failures.md`](issue-silent-receive-failures.md) is the full
debugging session: three stacked causes (VPN routing, sender-side ufw, receiver-side ufw
allowing only SSH) plus the eight traps that made it expensive — a live ufw ruleset behind
an `inactive` service, a failed `sudo -n` reading as a clean machine, silent drops versus
RSTs, `ss -tan state syn-recv | wc -l` counting its own header, multicast being impossible
to `ct mark`, a headless receiver that cannot prompt, `pkill -f` killing the shell that
runs it, and backgrounded `sudo -S` losing its password to `/dev/null`.

Tracked as [issue #1](https://github.com/StellarStoic/LocalSend-CLI-32bit-i386/issues/1).
