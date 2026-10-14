# Secrets policy

This repository is public. This page explains how secrets and personal data are kept out of it.

## What never goes in the repo

- Passwords, private keys (SSH, WireGuard), API tokens, ISP (PPPoE) credentials
- The full OPNsense configuration (`config.xml`): it contains password hashes and keys
- Public IP address, DDNS hostname, personal email addresses
- Details about other people's devices

Private IP addresses (192.168.x.x) are published on purpose: they are not reachable from the internet.

## Defence in depth

| Layer | What it does | Where |
|---|---|---|
| 1. `.gitignore` | Keeps files that hold secrets out of git | `.gitignore` |
| 2. gitleaks | Blocks commits containing known secret formats (keys, tokens) | `.githooks/pre-commit` |
| 3. Personal denylist | Blocks commits containing personal values that no generic rule can know (e.g. ISP username, Wi-Fi name) | `~/.config/homelab/denylist.txt`, outside the repo |
| 4. GitHub secret scanning | Server-side safety net | Planned when the repo goes public |

Design choices:

- **Fail-closed:** if gitleaks or the denylist is missing, the commit is blocked. A check that can silently switch itself off is not a check.
- **Redacted output:** findings are printed as `REDACTED`, so secrets do not end up in terminal logs or screen recordings.
- **Staged content only:** the hook scans exactly what is about to be committed, not the working copy.
- **Identifiers only in the denylist:** it never holds passwords, otherwise it would become a new plaintext secrets file.
- **Commit author email:** commits use the GitHub `noreply` address, because author emails are public in the history.

## Example files

The real file is ignored; a copy with fake values is committed (e.g. `wg0.conf` → `wg0.conf.example`).
Placeholders come from ranges reserved for documentation:

| Real value | Placeholder |
|---|---|
| Password, key, token | `CHANGE_ME` |
| Email / domain | `user@example.com`, `home.example.com` (RFC 2606) |
| Public IP | `203.0.113.10` (RFC 5737) |

## Setup after cloning

Git hooks are not activated automatically by a clone:

```bash
sudo pacman -S gitleaks
git config core.hooksPath .githooks
mkdir -p ~/.config/homelab
touch ~/.config/homelab/denylist.txt
chmod 600 ~/.config/homelab/denylist.txt
```

## How it was tested

| Test | Expected | Result |
|---|---|---|
| Fake GitHub token in a staged file | Blocked by gitleaks (`github-pat`) | Blocked |
| Denylist value in a staged file | Blocked by the denylist check | Blocked |
| Clean file, denylist missing | Blocked (fail-closed) | Blocked |
| Clean commit | Allowed | Allowed |
| Full history scan (`gitleaks git`) | No findings | No leaks found |

## Known limitations

- `git commit --no-verify` skips all hooks: never use it in this repo.
- Hooks run only on machines where they have been activated.
- The denylist only catches exact strings (case-insensitive).
- gitleaks is feature-complete (security fixes only). Betterleaks, by the same authors, will be re-evaluated once its v2 is stable.
