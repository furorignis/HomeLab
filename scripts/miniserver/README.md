# Miniserver alerting scripts

Health checks and Telegram alerts for the Proxmox VE host that also runs the home
router (OPNsense as a VM). Everything here runs on the host as root, from
`/usr/local/bin` and systemd units.

## What it does

| Component | Trigger | Purpose |
|---|---|---|
| `tg-notify` | called by the others | Sends `[hostname] message` to a Telegram bot. |
| `homelab-check` | `homelab-check.timer`, every 5 min | Proxmox storage state and usage, LVM thin pool, SMART, disk temperatures, failed systemd units. |
| `opnsense-check` | `opnsense-check.timer`, every minute | Router VM running, OPNsense API, PPPoE session, WAN gateway status from dpinger, public IP changes. |
| `homelab-weekly` | `homelab-weekly.timer`, Mondays 09:00 | Summary: uptime, kernel, pending updates, storage, disks, failed units. |
| `homelab-boot-notify` | `homelab-boot-notify.service`, at boot | Boot notice, with how long internet took to come back. |
| `ssh-login-notify` | PAM (`pam_exec`) | Notice for every SSH login: user and source address. |

## Design choices

- **Alerts on state changes only.** Each open problem is a file in the state directory: one ⚠️ when it appears, one ✅ when it clears, nothing in between. The state is updated only after Telegram has accepted the message, so a failed send is retried on the next run.
- **Outages survive the loss of internet.** When the router is down the host cannot reach Telegram: `opnsense-check` saves the start time at once and, as soon as it can, sends cause, time window and duration.
- **Secrets stay in `/etc/homelab/`.** Bot token, chat ID and the OPNsense API key live in `*.env` files (mode 600) on the host; this repository only has empty examples. Credentials reach `curl` through a config on stdin (`-K -`), never as arguments, so they do not show up in the process list.
- **Least privilege for the router API.** A dedicated OPNsense user with only the two privileges the checks need, reached over an isolated management bridge (`vmbr1`) with no physical port.
- **No public IP on disk.** Only its SHA-256 hash is stored to detect changes; messages never contain it.
- **Messages in Italian, code in English.** The alerts are read by the owner on a phone.

## Layout

```
bin/        scripts, installed to /usr/local/bin
systemd/    units, installed to /etc/systemd/system
env/        empty examples for /etc/homelab/*.env
pam/        line to add to /etc/pam.d/sshd
install.sh  installs or checks all of the above
```

## Installation

On the host, as root:

1. Create `/etc/homelab/telegram.env` (and `opnsense.env` where an OPNsense VM is monitored) from `env/`, then `chmod 600` them.
2. Run `./install.sh`. It installs only new or changed files, reloads systemd, restarts changed timers and enables them; `opnsense-check.timer` only where `opnsense.env` exists. It never touches secrets or PAM.
3. For SSH login alerts, append the line in `pam/sshd.snippet` to `/etc/pam.d/sshd` (keep a backup of the original).

From a workstation, without leaving files on the host:

```sh
tar -C scripts/miniserver -cf - bin systemd install.sh |
  ssh miniserver 'd=$(mktemp -d); tar -C "$d" --no-same-owner -xf -; "$d/install.sh"; rc=$?; rm -rf "$d"; exit $rc'
```

`./install.sh --check` only reports differences between this directory and the host (exit 1 if any). The repository is the source of truth: nothing is edited on the server directly.

## Testing

Each change in the history was tested on the host before and after. Checks that can be repeated:

- **Outage simulation**, without touching the router or the real state:
  `t=$(mktemp -d); OPNSENSE_CHECK_STATE=$t OPNSENSE_CHECK_VMID=999 opnsense-check` reports a stopped VM and sends a real alert; `OPNSENSE_CHECK_STATE=$t opnsense-check` then sends the recovery with its duration. Remove `$t` afterwards.
- **Failed unit:** `systemd-run --unit=test-fail --property=Type=oneshot /bin/false`, run `homelab-check` (alert), then `systemctl reset-failed test-fail.service` and run it again (recovery).
- **Secrets out of the process list:** put a wrapper named `curl` first in `PATH` that checks its own arguments for the token and then calls the real `curl`.

## Requirements

Proxmox VE (`pvesm`, `qm`, `lvs`), `smartmontools`, `curl`, `python3`, a Telegram bot.

## Known limits

- While internet is down nothing can be sent: the outage alert and the recovery arrive together when it comes back.
- A crash of `homelab-check` itself cannot be reported by it: it appears in the weekly summary under failed units.
