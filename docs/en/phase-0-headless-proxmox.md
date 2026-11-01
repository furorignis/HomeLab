# Phase 0 – Headless Proxmox host

*October 2026 · Proxmox VE 9.2 · [Versione italiana](../it/phase-0-headless-proxmox.md)*

**TL;DR** – A Proxmox VE host managed only from my workstation (web UI and SSH), with key-only SSH, firmware set up for unattended operation and an emergency runbook tested before anything depended on it. The host later became the home router, so "it must come back on its own" stopped being a nice-to-have.

## Goal

Run the server in a corner with no monitor, keyboard or mouse. Every routine task happens remotely; physical access is only for emergencies, and those are planned in advance.

## Hardware

| Part | Model |
|---|---|
| CPU | AMD Ryzen 5 9600X (6 cores / 12 threads) |
| RAM | 32 GB DDR5 |
| System disk | 256 GB NVMe |
| Data disk | 1 TB 2.5" HDD, reused from a laptop |
| Network | onboard Realtek 2.5 GbE (management) + dual-port Intel i226-V card, reserved for the router VM (Phase 2) |

## What I built and why

- **Proxmox VE on the NVMe, ext4.** One disk and no redundancy to manage: ext4 is the simplest choice and leaves no ZFS cache (ARC) to budget on a 32 GB machine that will also run a router and SIEM tests.
- **Static address and a reserved domain.** `192.168.178.3`, hostname `miniserver.home.arpa` (`home.arpa` is reserved for home networks, RFC 8375). Fixed addresses on the host and on my workstation keep the hypervisor reachable even when DHCP or the router VM is down.
- **Free update channel.** Enterprise repositories disabled, `pve-no-subscription` enabled. Updates always with `apt full-upgrade`: a plain `apt upgrade` can leave Proxmox half-upgraded. The subscription pop-up stays: the scripts that remove it patch Proxmox files as root and are overwritten by every update.
- **Key-only SSH.**
  - Before the first login I compared the host's ED25519 fingerprint with the one on the server console instead of blindly accepting it.
  - An ed25519 key with a passphrase, re-encrypted with 100 KDF rounds (`ssh-keygen -p -a 100`) to slow down offline guessing.
  - Hardening in a drop-in file, `/etc/ssh/sshd_config.d/10-hardening.conf`: `PasswordAuthentication no`, `KbdInteractiveAuthentication no`, `PermitRootLogin prohibit-password`. A drop-in survives package upgrades and is removed with one command. `sshd` keeps the first value it reads and the `Include` sits at the top of `sshd_config`, so it wins over the stock `PermitRootLogin yes`: checked with `sshd -T`, not assumed.
  - On Proxmox `/root/.ssh/authorized_keys` is a symlink into the cluster filesystem: keys are appended with `ssh-copy-id`, never copied over it.
- **Firmware for unattended operation.** Power on after AC loss; no "press F1" stop on POST errors; Fast Boot off, so a USB keyboard always works at POST; boot from the NVMe first; IOMMU on for the NIC passthrough of Phase 2. The settings are saved as a BIOS profile, so a CMOS reset can't silently undo them.
- **A tested emergency runbook.** Triage order: ping, web UI, SSH, physical console, so I know at which layer something broke before touching anything. Each failure (SSH down, web UI down, broken network config, lost key, host not booting) has a row with what to do. The web UI shell goes through `pveproxy` on port 8006, not through `sshd`, so a broken SSH configuration cannot lock me out. The root password is also kept offline: a password manager self-hosted on this machine would be unreachable exactly when the machine needs fixing.

## What went wrong and how I fixed it

**A headless server waiting for F1.** After a forced power-off the host stopped at "POSTed in safe mode… press F1": stuck, and invisible without a monitor. The F1 wait was still enabled, because my first test covered a clean shutdown and a power return, not a forced power-off. I disabled *Wait For F1 If Error* and Fast Boot, checked every relevant setting again from photos of the BIOS screens, saved the profile and ran the tests that had been missing: a forced power-off and a power cut longer than 10 seconds. Lesson: test the failure modes, not just the happy path.

**Short power dips.** With a dip of a few seconds the board doesn't register the power loss, so "power on after AC loss" never triggers and the host stays off; sometimes the power button doesn't respond until the plug is pulled. No BIOS setting fixes this. The runbook has the manual workaround; the real fix is a small UPS with NUT, set to cut its output for a few seconds after the shutdown so the board sees the power come back.

**Unknown terminal type.** My terminal (Ghostty) sets `TERM=xterm-ghostty`, which the server didn't know, so tools like `watch` refused to start. Fixed once by installing the terminfo entry on the server: `infocmp -x xterm-ghostty | ssh miniserver -- tic -x -`.

## How it was verified

- Web UI and SSH from the workstation; the key login shows in the log (`Accepted publickey`), a password attempt is refused (`Permission denied (publickey)`).
- Boot with no monitor or keyboard, then reachable over the network.
- Clean shutdown, power removed and restored: the host comes back on its own. After the fix, also a forced power-off and a power cut longer than 10 seconds.
- Runbook paths: web UI shell with SSH out of the picture; physical console login with the root password; installer USB stick, monitor and keyboard ready.

## Still open

- **Two-factor authentication on the web UI** (TOTP with recovery codes). Deferred while the UI is reachable only from the LAN; it is a prerequisite for the VPN (Phase 5). Proxmox 2FA protects the web UI and the API, not SSH or the physical console.
- **UPS with NUT**, for the power dips above.

## Skills

Linux and SSH hardening · Proxmox VE administration · firmware setup for unattended servers · writing and testing runbooks
