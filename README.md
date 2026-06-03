# Sentinel P2P Systemd — GitHub Release Package

> One-command automated Sentinel dVPN node installer with systemd persistence, anti-lockout protection, and agent-friendly operation.

This repository contains the complete, ready-to-distribute package for deploying a Sentinel dVPN node as a persistent systemd service. It is designed for autonomous agents, bots, and unattended Linux servers.

---

## Package Contents

```
Sentinel-P2P-Systemd-for-agents-bots/
├── .gitignore
├── LICENSE
├── README.md
├── Sentinel-P2P-Systemd-for-agents-bots.tgz
└── sources/
    ├── sentinel-install.sh                 # Master installer
    ├── sentinel-install-services.sh
    ├── sentinel-env.sh
    ├── sentinel-ip-vpnbypass.sh
    ├── .env
    ├── .country_filter
    ├── SAMPLES.md
    ├── MyScripts/                          # All operational scripts
#   - sentinel-disconnect.sh added (clean wg-quick + process cleanup)
#   - sentinel-wg-monitord.sh + dedicated sentinel-wg-monitord.service added
    ├── ServiceFiles/                       # systemd unit templates
    ├── otherfiles/
    └── hiddenfiles/
```

---

## Operational Notes

- **Installation directory:** All dVPN files are installed under `~/sentinel-dvpncli/`. The installer manages this directory — no manual intervention needed.
- **Keyring:** Uses a dedicated `main` keyring with `test` backend for unattended (systemd) operation. No interactive login required.
- **Wallet:** Created during install — address stored in `~/sentinel-dvpncli/.address`. Fund this address after installation.
- **Anti-lockout:** `sentinel-ip-vpnbypass.sh` runs automatically during install to preserve your SSH session when WireGuard activates.
- **WG Monitor:** Dedicated `sentinel-wg-monitord.service` continuously watches WireGuard state and triggers `sentinel-ip-vpnbypass.sh` on interface UP/DOWN transitions.

---

## Quick Usage Guide

- PreWhitelist (whitelist-gws.lst the IPs where you are SSHing from ( the current IP auto adds at systemctl start , to avoid lockout)
- Prefill fav-providers.lst
- Fund the wallet on the address after install or get it from  <installdir>/sentinel-dvpncli/.address
- systemctl start|stop sentinel-favs-dvpn.service |  sentinel-dvpn.service 
- enjoy

---

## Installation Overview (9 Steps)

The master installer (`sentinel-install.sh`) performs the following:

| Step | Action |
|------|--------|
| 1 | Collect wallet passphrase (`-p` or interactive) |
| 2 | Clone `sentinel-dvpncli` repository |
| 3 | Copy config files (`.env`, `sentinel-env.sh`, `.country_filter`) |
| 4 | Install prerequisites (Go 1.24, WireGuard, V2Ray, expect, jq, dig) + create symlinks |
|   | **Note:** Cloud/VMs may lack kernel WireGuard support — handled gracefully by the scripts |
| 5 | Build `sentinel-dvpncli` binary and symlink to `/usr/local/bin/` |
| 6 | Install systemd services |
| 6.5 | Run `sentinel-ip-vpnbypass.sh` (anti-lockout) + copy `whitelist-gws.lst` |
| 7 | Create wallet + import mnemonic into test keyring |
| 8 | Print summary + wallet address |

---

## Quick Start

```bash
tar -xzf Sentinel-P2P-Systemd-for-agents-bots.tgz
cd install-package
sudo bash sentinel-install.sh -p "your-passphrase"
```

After installation, fund the address shown in `~/sentinel-dvpncli/.address`.

---

## Generated / Important Files

| File | Purpose | Notes |
|------|---------|-------|
| `~/sentinel-dvpncli/.address` | Wallet address | Created during install |
| `~/sentinel-dvpncli/.mnemonic` | BIP-39 seed | chmod 600 |
| `~/sentinel-dvpncli/.passphrase` | Keyring passphrase | chmod 600 |
| `~/sentinel-dvpncli/blacklist-nodes.lst` | Auto-blacklisted nodes | Managed by `sentinel-connect.sh` |
| `~/sentinel-dvpncli/whitelist-gws.lst` | SSH bypass IPs | Anti-lockout |
| `~/.best-sentinel-node` | Cached best node | Updated by selector scripts |
| `fav-providers.lst` | Preferred nodes | Used with `-f` flag |

---

## Operational Scripts

All scripts live in `~/sentinel-dvpncli/MyScripts/` after installation.

| Script | Flags | Description |
|--------|-------|-------------|
| `sentinel-connect.sh` | `-f` | Main connect with retry + provider fault detection + auto blacklist |
| `sentinel-disconnect.sh` | — | Clean WireGuard teardown + process cleanup (used by ExecStop=) |
| `sentinel-wg-monitord.sh` | — | WG state monitor daemon (started via ExecStartPre, detects UP/DOWN for anti-lockout apply & cleanup) |
| `sentinel-select-best-node.sh` | `-C` | Pick 1 random WireGuard node from top 10 out of 500 (default) |
| `sentinel-best-nodes.sh` | `-C` | List top nodes |
| `sentinel-auto-nodes.sh` | `-C` | Top 5 by downlink speed |
| `sentinel-balance.sh` | — | Balance + explorer link |
| `sentinel-cancel-session.sh` | `-a` | Cancel sessions |
| `sentinel-ip-vpnbypass.sh` | — | Imprint current SSH IP into routing rules |

**Usage examples:**
```bash
bash ~/sentinel-dvpncli/MyScripts/sentinel-connect.sh -f
bash ~/sentinel-dvpncli/MyScripts/sentinel-select-best-node.sh -C DE,NL,FR,US
```

---

## Systemd Services

- `sentinel-dvpn.service` — Random best node
- `sentinel-favs-dvpn.service` — Uses `fav-providers.lst` only

---

## Configuration

All settings are in `~/sentinel-dvpncli/.env`.

**Country filter precedence:**
1. `.country_filter` file (highest)
2. `COUNTRY_FILTER` variable in `.env`
3. Hardcoded `NL,DE,FR,US,SG,GB,CA,CH,FI,SE` fallback

All node selection scripts support runtime override with `-C CN1,CN2`.

---

## Anti-Lockout Protection

When WireGuard takes over the default route, SSH can drop.

`sentine-ip-vpnbypass.sh` solves this by adding the current SSH source IP as a high-priority exception. It runs automatically during install and can be re-run manually later.

---

## Blacklist Behavior

`sentinel-connect.sh` detects "provider fault" (session created on-chain but WireGuard interface fails to come up). It then:
- Adds the node to `blacklist-nodes.lst`
- Cancels the bad session
- Selects a new non-blacklisted node
- Starts a fresh session

---

## License

MIT License — see `LICENSE` file.

Built on the [Sentinel dVPN](https://sentinel.co) protocol.  
Automation and packaging by RaccoonClaw / TT-Tech Org (non profit) 

## Disclaimer

This software is provided **"as is"**, without warranty of any kind, express or implied.

The author(s) shall **not be held liable** for any damages, legal consequences, or issues arising from the use, misuse, or inability to use this software. This includes, but is not limited to, any actions taken by law enforcement, government agencies, or third parties.

By using this software, you acknowledge that you are solely responsible for your own actions and compliance with all applicable laws in your jurisdiction.

Binary reference: commit `4463e4c` | tag `4.0.0-59-g4463e4c`
