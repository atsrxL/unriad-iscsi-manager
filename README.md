# iSCSI ZVOL Manager for Unraid

A lightweight Unraid WebGUI plugin for managing ZFS volumes intended to be used as iSCSI LUN backstores.

## Install

In **Unraid → Plugins → Install Plugin**, paste:

```text
https://github.com/atsrxL/unriad-iscsi-manager/releases/latest/download/unraid-iscsi-manager.plg
```

Then open **Settings → iSCSI ZVOL Manager**.

## WebGUI pages

The plugin is split into five native Unraid tabs:

1. **Z Status** — ZPOOL status, ZVOL properties, configured LIO mappings, active iSCSI sessions, and pool TRIM controls.
2. **ZVOL Creator** — create thin/thick ZVOLs with compression and volblocksize controls.
3. **Snapshot Manager** — create/delete snapshots, view snapshot → clone dependencies, create clones, and safely delete clones.
4. **Snapshot Refresher** — use one ZVOL as the new base and safely refresh selected same-pool targets.
5. **Misc** — automatic/per-backstore SCSI UNMAP controls and Windows space-reclaim instructions.

## Z Status / iSCSI visibility

Configured LUN mappings are read from Linux LIO configfs under `/sys/kernel/config/target/iscsi`. Live sessions are read from `targetcli sessions detail` with a configfs `dynamic_sessions` fallback for demo/dynamic ACL targets, so the UI can distinguish:

- **Mapped / Offline** — an IQN/LUN/backstore exists but no initiator is currently logged in;
- **Connected** — an open LIO session is present.

For active sessions Z Status displays target IQN/LUN, ZVOL, initiator IQN, initiator IP where it can be determined, session state, connection state, transport, and access mode.

The page also reports LIO `emulate_tpu` as **UNMAP on/off** and checks the ZVOL block device's Linux discard capability.

## V1 features

- Create ZVOLs on a selected ZFS pool.
- Thin (sparse) or thick (reserved) provisioning.
- LZ4 compression on/off.
- `volblocksize`: 4K, 8K, 16K, 32K, 64K, 128K.
- Z Status:
  - ZPOOL size, allocated/free space, health, and autotrim;
  - ZVOL size, ZFS Used, Referenced, provisioning mode, compression, block size, origin, and discard support;
  - IQN → LUN → LIO backstore → ZVOL mapping view;
  - active initiator/session/IP/login-state view;
  - manual pool TRIM run/resume, suspend, cancel, and autotrim on/off.
- Snapshot manager:
  - create snapshot;
  - show snapshots as parent nodes with their direct dependent clones underneath;
  - show clone size, used space, origin, and iSCSI state;
  - delete snapshot, with dependent-clone protection and a disabled delete action while clones exist;
  - clone snapshot;
  - automatic `-clone1`, `-clone2`, ... naming with the next generated name shown in the form;
  - custom clone leaf name;
  - safely delete clones with non-recursive `zfs destroy`;
  - refuse clone deletion when the target is not actually a clone, is mapped/active/local-busy, or still has snapshots;
  - separate **Unique Used** and **Referenced Data** accounting.
- Refresh / rebase workflow:
  - select one current ZVOL as source;
  - create a new source snapshot;
  - select multiple target ZVOLs in the same pool;
  - rename old targets to timestamped backup names;
  - recreate the original target names as CoW clones of the new source snapshot;
  - attempt automatic rollback of a target rename if cloning fails.
- Misc:
  - show currently mapped LIO block backstores;
  - enable/disable SCSI UNMAP per ZVOL backstore through `emulate_tpu=1/0`;
  - optional **Auto-enable UNMAP** policy, persisted in `/boot/config/plugins/unraid-iscsi-manager/settings.cfg`;
  - while that policy is On, check once per minute for mapped block backstores that resolve to ZVOLs and enable `emulate_tpu=1` when needed;
  - ignore physical disks and other block backstores that do not resolve to `/dev/zvol/...`;
  - verify the live LIO value after manual changes;
  - provide Windows reconnect/ReTrim instructions.

The automatic UNMAP policy defaults to **Off**. Turning it Off later stops future enforcement but intentionally leaves existing `emulate_tpu` values unchanged. Use the per-backstore control when you explicitly want to turn one Off.

## TRIM / space reclaim semantics

There are two separate discard layers:

- **Inside a ZVOL:** deleting a file in NTFS/ext4 only marks filesystem blocks free. ZFS does not know those logical blocks are unused until the consumer sends discard/TRIM/SCSI UNMAP. For Windows iSCSI volumes, enable UNMAP for the LIO backstore, reconnect the iSCSI disk so Windows re-queries its capabilities, then run ReTrim, for example:

```powershell
Optimize-Volume -DriveLetter F -ReTrim -Verbose
```

Alternative:

```text
defrag F: /L /V
```

- **At the ZPOOL layer:** `zpool trim <pool>` informs the physical SSD/thin backing devices about ZFS pool extents that are already free. It does not discover free blocks inside NTFS/ext4 by itself.
- **Snapshots:** there is no meaningful snapshot TRIM operation. Snapshots intentionally pin old blocks. Deleting unneeded snapshots is what allows those blocks to become free in the pool.

A thick ZVOL may still reserve capacity through `refreservation` even after guest discard reduces referenced data.

## Important safety notes

This plugin manages block devices. Before Refresh/Rebase, disconnect the source and target initiators and remove their LIO mappings.

The mapping removal requirement is intentional: the refresher renames the old ZVOL and creates a new block device at the original dataset name. An existing LIO block backstore can remain attached to the old device after the rename, so leaving the mapping configured could cause the IQN to continue serving the backup instead of the newly created clone.

Clone deletion is deliberately conservative: it never uses recursive destroy. A clone that is iSCSI mapped, actively connected, locally busy, or has snapshots is rejected rather than cascading through dependencies.

The Misc UNMAP controls only change LIO's `emulate_tpu` attribute. They do **not** run `blkdiscard` and do not discard an entire ZVOL.

V1 only refreshes ZVOLs within the same ZFS pool. Cross-pool replication is intentionally left for a future `zfs send | zfs receive` implementation.

The plugin does **not** expose a general-purpose ZVOL-delete action in V1. Removing a snapshot with dependent clones is also blocked rather than using dangerous recursive `zfs destroy -R` behavior.

## ZFS model

ZFS itself is the source of truth. The plugin does not maintain a separate database describing snapshot/clone relationships. Created volumes and clones receive user properties such as:

```text
unraid-iscsi-manager:managed=yes
unraid-iscsi-manager:role=volume|clone|backup
```

## Build locally

```bash
bash scripts/build-release.sh
```

Artifacts are written to `dist/`:

```text
dist/unraid-iscsi-manager.plg
dist/unraid-iscsi-manager-<version>.txz
```

Pushing a release-related change to `main` runs the GitHub Actions workflow and publishes/replaces the release whose tag matches `VERSION`.

## Current scope / roadmap

The next logical step is direct LIO orchestration for safe offline/unmap → refresh → backstore remap, backup retention/cleanup, promote-to-base, and cross-pool replication.
