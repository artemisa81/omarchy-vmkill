# VM Killswitch — Omarchy bar widget

A bar-widget plugin for [Omarchy](https://omarchy.org/) that cuts internet
access to [dockur/windows](https://github.com/dockur/windows) VMs from the top
bar — and, optionally, refuses to let them online at all unless the IVPN tunnel
is up and its firewall is armed.

## Why not just run a firewall inside Windows

simplewall, TinyWall and Portmaster all run *inside* the guest, so anything in
the guest with admin rights can switch them off. They are policy tools, not
boundaries.

This filters in the **container's** network namespace instead. The Windows
guest has no handle on that namespace: it cannot see the rules, cannot list
them, and cannot disable them. Privilege escalation inside Windows does not
reach them.

It is also sudo-free. The dockur container already carries `CAP_NET_ADMIN` to
build its tap bridge, and membership of the `docker` group is enough to reach
it — so nothing here needs root on the host.

## What stays working when the VMs are cut off

- **RDP** — the session you watch the VM through.
- **The noVNC console** on `127.0.0.1:8006` / `:8007`.
- **The `/shared` folder** — it is served by the container itself, so it never
  crosses the filtered path.

That is not luck. The block rule reads:

```
-A VMKILL -i docker ! -o docker -m conntrack --ctstate ESTABLISHED,RELATED --ctdir REPLY -j RETURN
-A VMKILL -i docker ! -o docker -j DROP
```

`--ctdir REPLY` means the guest may only emit packets belonging to connections
opened from *outside*. Inbound RDP keeps flowing; every guest-initiated
connection dies at once, including ones already in flight — so no conntrack
flush is needed.

## Require-VPN policy

With **Require VPN** on, a running VM reaches the internet only while IVPN
reports `CONNECTED` *and* its firewall reads `ENABLED`. Anything less holds the
VMs blocked.

The check is fail-closed on purpose. The VM is held until both are true, rather
than opened first and corrected afterwards — opening first would leak the VM's
real address for as long as the tunnel takes to come up, and a Windows guest
starts talking the moment it has a route.

Order matters too, and it is not cosmetic: IVPN's firewall blocks everything
outside the tunnel, so arming it while disconnected takes the *host* off the
network. The widget connects first, and only arms the firewall once the status
actually reads `CONNECTED`.

It only ever connects and arms. It never disconnects and never disarms —
stopping a VM leaves your tunnel exactly as it was.

## Isolate from LAN

On by default, and independent of the internet toggle, because "the VM may
browse the web" and "the VM may reach my Proxmox box" are different permissions
that should not share a switch. It blocks guest-initiated connections to
`10/8`, `172.16/12`, `192.168/16`, `100.64/10` (tailnet) and `169.254/16`.

IPv6 is dropped for the guest unconditionally. There is no global v6 on this
bridge today, so nothing is lost — but if Docker or the host ever gains it, the
v4 rules would silently stop being the whole story.

## Requirements

- Omarchy with the Quickshell plugin system.
- Docker, with your user in the `docker` group.
- `vmkill` on `PATH` (see Install).
- IVPN with `ivpn` on `PATH`, only if you use the require-VPN policy.

## Install

```bash
git clone https://github.com/artemisa81/omarchy-vmkill.git \
  ~/.config/omarchy/plugins/artemisa81.vmkill
ln -sfn ~/.config/omarchy/plugins/artemisa81.vmkill/bin/vmkill ~/.local/bin/vmkill
omarchy plugin enable artemisa81.vmkill
```

## CLI

The widget is a front end for the script; everything works headless too.

```bash
vmkill status --plain   # human-readable state
vmkill on               # cut the internet
vmkill off              # restore it (subject to the VPN policy)
vmkill toggle
vmkill vpn on|off       # require-VPN policy
vmkill lan on|off       # LAN/tailnet isolation
vmkill enforce          # reapply remembered state to whatever is running
vmkill sync             # enforce, then print JSON (what the widget calls)
```

Bind the toggle without the bar:

```
bindd = SUPER SHIFT, K, Cut VM internet, exec, vmkill toggle
```

## Default-deny

With no state file at all — first run, a wiped config, a new machine — the
answer is **blocked**. A killswitch whose failure mode is "open" is not a
killswitch.

## Wiring it into your launcher

Rules live in the container's network namespace, so they vanish whenever the
container is recreated -- which `docker-compose up` does on every launch. The
widget reconciles on every poll and will refill them on its own, but that
leaves a window between the container starting and the first tick, and Windows
starts talking the instant it has a link. Close it by calling `vmkill enforce`
straight after `docker-compose up -d`:

```bash
docker-compose -f "$COMPOSE_FILE" up -d
vmkill enforce >/dev/null 2>&1 || echo "vmkill enforce failed - VM is NOT filtered"
```

`enforce` is idempotent (it will not reset your drop counters) and needs no
shell running, so this also covers launching a VM with the bar down.

## Pin your Docker subnets

Worth doing once, independently of this plugin. Left alone, Docker allocates
compose bridges out of `172.17.0.0/16`-`172.31.0.0/16`, and IVPN hands its
WireGuard tunnel an address inside `172.16.0.0/12`. Those can land on top of
each other -- a host route for the bridge that covers the tunnel's own address.
Pin something clear of it in your compose file:

```yaml
networks:
  default:
    ipam:
      config:
        - subnet: 192.168.244.0/24
          gateway: 192.168.244.1
```

Pick a range that misses your LAN, your homelab and your tailnet as well.

## Interactions

- **left** — open the panel
- **right** — toggle the internet cut
- **middle** — refresh

In the panel: `b` toggle, `v` require-VPN, `l` LAN isolation, `r` refresh.

## License

MIT
