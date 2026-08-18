# iSCSI ZVOL Manager for Unraid

A lightweight Unraid WebGUI plugin for managing ZFS volumes intended to be used as iSCSI LUN backstores.

## Install

In **Unraid → Plugins → Install Plugin**, paste:

```text
https://github.com/atsrxL/unriad-iscsi-manager/releases/latest/download/unraid-iscsi-manager.plg
```

Then open **Settings → iSCSI ZVOL Manager**.

## WebGUI pages

The plugin is split into four native Unraid tabs:

1. **Z Status** — ZPOOL status, ZVOL properties, configured LIO mappings, active iSCSI sessions, and pool TRIM controls.
2. **ZVOL Creator** — create thin/thick ZVOLs with compression and volblocksize controls.
3. **Snapshot Manager** — create/delete snapshots and clone snapshots with automatic or custom names.
4. **Snapshot Refresher** — use one ZVOL as the new base and safely refresh selected same-pool targets.

## Z Status / iSCSI visibility

Configured LUN mappings are read from Linux LIO configfs under `/sys/kernel/config/target/iscsi`. Live sessions are read separately from `targetcli sessions detail`, so the UI can distinguish:

- **Mapped / Offline** — an IQN/LUN/backstore exists but no initiator is currently logged in;
- **Connected** — an open LIO session is present.

For active sessions Z Status displays SID, target IQN/LUN, ZVOL, initiator IQN, initiator IP, session state, connection state, transport, and access mode.

The page also reports LIO `emulate_tpu` as **UNMAP on/off** and checks the ZVOL block device's Linux discard capability.

## V1 features

- Create ZVOLs on a selected ZFS pool.
- Thin (sparse) or thick (reserved) provisioning.
- LZ4 compression on/off.
- `volblocksize`: 4K, 8K, 16K, 32K, 64K, 128K.
- Z Status:
  - ZPOOL size, allocated/free space, health, and autotrim;
  - ZVOL size, used space, provisioning mode, compression, block size, origin, and discard support;
  - IQN → LUN → LIO backstore → ZVOL mapping view;
  - active initiator/session/IP/login-state view;
  - manual pool TRIM run/resume, suspend, cancel, and autotrim on/off.
- Snapshot manager:
  - create snapshot;
  - delete snapshot, with dependent-clone protection;
  - clone snapshot;
  - automatic `-clone1`, `-clone2`, ... naming;
  - custom clone leaf name.
- Refresh / rebase workflow:
  - select one current ZVOL as source;
  - create a new source snapshot;
  - select multiple target ZVOLs in the same pool;
  - rename old targets to timestamped backup names;
  - recreate the original target names as CoW clones of the new source snapshot;
  - attempt automatic rollback of a target rename if cloning fails.

## TRIM / space reclaim semantics

There are two separate discard layers:

- **Inside a ZVOL:** deleting a file in NTFS/ext4 only marks filesystem blocks free. ZFS does not know those logical blocks are unused until the consumer sends discard/TRIM/SCSI UNMAP. For Windows iSCSI volumes, use ReTrim (for example `Optimize-Volume -DriveLetter X -ReTrim -Verbose`) when the storage path advertises UNMAP.
- **At the ZPOOL layer:** `zpool trim <pool>` informs the physical SSD/thin backing devices about ZFS pool extents that are already free. It does not discover free blocks inside NTFS/ext4 by itself.
- **Snapshots:** there is no meaningful snapshot TRIM operation. Snapshots intentionally pin old blocks. Deleting unneeded snapshots is what allows those blocks to become free in the pool.

A thick ZVOL may still reserve capacity through `refreservation` even after guest discard reduces referenced data.

## Important safety notes

This plugin manages block devices. Before Refresh/Rebase, disconnect the source and target initiators and remove their LIO mappings.

The mapping removal requirement is intentional: the refresher renames the old ZVOL and creates a new block device at the original dataset name. An existing LIO block backstore can remain attached to the old device after the rename, so leaving the mapping configured could cause the IQN to continue serving the backup instead of the newly created clone.

V1 only refreshes ZVOLs within the same ZFS pool. Cross-pool replication is intentionally left for a future `zfs send | zfs receive` implementation.

The plugin does **not** expose a ZVOL-delete action in V1. Removing a snapshot with dependent clones is also blocked rather than using dangerous recursive `zfs destroy -R` behavior.

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
