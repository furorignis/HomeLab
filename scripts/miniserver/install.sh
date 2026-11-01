#!/usr/bin/env bash
# Install or update the miniserver alerting scripts and systemd units.
# Run as root on the Proxmox host, from a copy of this directory:
#   ./install.sh          install new or changed files, reload systemd, enable timers
#   ./install.sh --check  only report differences from what is installed (exit 1 if any)
# Never touches /etc/homelab/*.env (secrets) or /etc/pam.d/sshd.
set -euo pipefail

BIN_DST=/usr/local/bin
UNIT_DST=/etc/systemd/system
SRC=$(cd "$(dirname "$0")" && pwd)
CHECK=0
case "${1:-}" in
  --check) CHECK=1 ;;
  "") ;;
  *) echo "usage: $0 [--check]" >&2; exit 2 ;;
esac
[[ $EUID -eq 0 ]] || { echo "run as root" >&2; exit 1; }

diffs=0
changed_units=()

sync_file() {  # sync_file <src> <dst> <mode>
  local src=$1 dst=$2 mode=$3 state
  if [[ ! -e $dst ]]; then state=new
  elif ! cmp -s "$src" "$dst"; then state=changed
  elif [[ $(stat -c %a "$dst") != "$mode" ]]; then state=mode
  else state=same
  fi
  [[ $state == same ]] && return 0
  diffs=$((diffs + 1))
  echo "$state: $dst"
  (( CHECK )) && return 0
  install -m "$mode" -o root -g root "$src" "$dst"
  [[ $dst == "$UNIT_DST"/* ]] && changed_units+=("$(basename "$dst")")
  return 0
}

for f in "$SRC"/bin/*; do sync_file "$f" "$BIN_DST/$(basename "$f")" 755; done
for f in "$SRC"/systemd/*; do sync_file "$f" "$UNIT_DST/$(basename "$f")" 644; done

if (( CHECK )); then
  echo "differences: $diffs"
  exit $(( diffs > 0 ))
fi

[[ -f /etc/homelab/telegram.env ]] \
  || echo "warning: /etc/homelab/telegram.env missing (see env/telegram.env.example)" >&2

systemctl daemon-reload
systemctl enable homelab-boot-notify.service   # runs at the next boot only
systemctl enable --now homelab-check.timer homelab-weekly.timer
if [[ -f /etc/homelab/opnsense.env ]]; then
  systemctl enable --now opnsense-check.timer
else
  echo "skipped opnsense-check.timer: /etc/homelab/opnsense.env not found"
fi
for u in "${changed_units[@]}"; do
  [[ $u == *.timer ]] && systemctl try-restart "$u"
done

grep -qs 'pam_exec.so.*/usr/local/bin/ssh-login-notify' /etc/pam.d/sshd \
  || echo "note: SSH login alerts need the line in pam/sshd.snippet in /etc/pam.d/sshd"
echo "done: $diffs file(s) installed or updated"
