# Phase 1 – Backups

*October 2026 · Proxmox VE 9.2 · [Versione italiana](../it/phase-1-backups.md)*

**TL;DR** – Nightly backups of every VM and container to a separate disk, with retention, failure alerts on Telegram and a restore test that proves the data comes back, all in place before the first risky change. The storage is set up so that a missing disk makes backups fail loudly instead of silently filling the system disk.

## Goal

Be able to restore any VM or container in minutes, before starting the changes that can break things (the router VM, the network cut-over).

## Disk layout

| Disk | Use | Why |
|---|---|---|
| 256 GB NVMe | Proxmox, VM and container disks (LVM-thin pool) | Fast random I/O. Root and swap take their share, so guests get about 140 GB, not 256 |
| 1 TB HDD (2.5", 5400 rpm, SMR) | backups, ISO images, bulk data | Fine for sequential writes; SMR makes it far too slow for VM disks |

Before trusting a second-hand disk I read its SMART data: health PASSED, about 9,000 power-on hours, no reallocated, pending or uncorrectable sectors.

## What I built and why

- **ext4 directly on the HDD, as a "Directory" storage.** No LVM: if the server dies, the disk can be plugged into any Linux PC and read as it is. Formatted with `-m 0`: the default 5 % reserved for root would waste about 46 GB on a data-only disk.
- **A missing disk must not become a full system disk.** The classic failure: the HDD is not mounted, the backup job writes into the empty mount point on the root filesystem, and the NVMe fills up. The storage is marked `is_mountpoint yes`, so Proxmox treats it as offline when nothing is mounted there; the disk is mounted by UUID with `nofail`, so a dead disk doesn't block the boot either. Tested by unmounting it: storage `inactive`, nothing written to the NVMe.
- **One nightly job for everything.** 03:00, all guests (`all 1`, so new VMs and containers are included automatically), compressed with zstd. **Snapshot mode**, not stop mode: once the router is a VM, stop mode would cut internet every night.
- **Retention:** 7 daily, 4 weekly, 3 monthly. Important manual backups (e.g. right after the network cut-over) are marked *protected*, so rotation never deletes them.
- **Alerts only when something is wrong.** Proxmox notifications go to a Telegram bot through a webhook, with a matcher for warnings and errors only: no message for a successful backup, so a message always means action. Local mail to root was disabled: without an SMTP relay it only produced "Undelivered Mail" noise. The bot token sits in Proxmox's secret store, never in this repository.

## What went wrong and how I fixed it

**Retention didn't count what I expected.** After several test backups in one day only one was left: `keep-daily` keeps the *latest* backup of each day, not the last N backups. Correct behaviour, wrong assumption. I now read retention rules as "one per period", and protect the manual backups I want to keep.

**Two log details that look like failures.** The final `TASK OK` is not in the `.log` file next to the archive: it is only in the task log (*Datacenter → Backup*). And the log of a stopped container says `backup mode: stop` even though the job asks for snapshot: a stopped guest has nothing to snapshot. Neither is a failure. The checks I trust: the task status, plus `zstd -t` on the archive.

**The wrong container template.** Picking "the newest Debian template" with `sort -V` selected the arm64 build, because in version order `arm64` sorts after `amd64`. Fix: filter the architecture explicitly, then sort.

**Repartitioning a disk that already held backups.** Later I split the HDD in two, to reserve space for the data of services that will move to a second server. What I learned: `parted` isn't installed on Proxmox, `sgdisk` with `partx -u` is; "the disk is empty" must be checked with `find` over the whole mount, not by looking at the backup folder, because the template cache refills by itself; and the partition that will be deleted one day goes *last*, so the backup partition can later grow into the freed space instead of shrinking a full partition.

## How it was verified

- **Restore test with a marker file.** A test container, running, with a marker file inside; snapshot backup (the log shows the filesystem freeze and thaw); marker deleted from the original; restore with `pct restore` to a new ID. The marker came back, which proves it came from the backup, and the original was never touched. Test guests and archives were deleted afterwards. VM restores were tested later with `qmrestore` (Phase 2).
- Archive integrity with `zstd -t`.
- Failure alert tested with a real failure: HDD unmounted, job started, Telegram message received.
- Reboot: the disk mounts by itself. `umount`: the storage goes inactive and no writes reach the NVMe.

## Still open

- **3-2-1.** Backups and bulk data share one disk in the same box: a dead HDD, a power surge or a fire loses both. An off-site copy is planned.
- **The hypervisor itself.** `vzdump` saves guests, not the host. The host's scripts and systemd units now live in Git with an installer (`scripts/miniserver/`); for the rest, a reinstall follows the written guide.

## Skills

Backup and restore design · retention policies · Linux storage (GPT, ext4, LVM-thin, fstab) · alerting · verifying recovery instead of assuming it
