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

1. **Z Status** — ZPOOL status, ZVOL properties, and configured LIO iSCSI IQN/LUN mappings.
2. **ZVOL Creator** — create thin/thick ZVOLs with compression and volblocksize controls.
3. **Snapshot Manager** — create/delete snapshots and clone snapshots with automatic or custom names.
4. **Snapshot Refresher** — use one ZVOL as the new base and safely refresh selected same-pool targets.

The Z Status page reads LIO configfs directly from `/sys/kernel/config/target/iscsi` and correlates block backstores with `/dev/zvol/...` devices. A displayed **Mapped** state means a LUN is configured under an IQN; it does not by itself prove that an initiator currently has an active session.

## V1 features

- Create ZVOLs on a selected ZFS pool.
- Thin (sparse) or thick (reserved) provisioning.
- LZ4 compression on/off.
- `volblocksize`: 4K, 8K, 16K, 32K, 64K, 128K.
- Z Status:
  - ZPOOL size, allocated/free space, and health;
  - ZVOL size, used space, provisioning mode, compression, block size, and origin;
  - IQN → LUN → LIO backstore → ZVOL mapping view.
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
- Best-effort `targetcli` / `fuser` checks to catch exported or busy devices before refresh.

## Important safety notes

This plugin manages block devices. Before Refresh/Rebase, disconnect the source and all selected target LUNs from every iSCSI initiator and take/remove the relevant target mapping as required by your target setup.

The busy check is intentionally only an additional guard. Different iSCSI target implementations can expose their state differently, so the plugin cannot guarantee that every active LUN is detectable.

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

The next logical step is deeper integration with the specific Unraid iSCSI target plugin: active-session discovery, offline/unmap → refresh → remap orchestration, backup retention/cleanup, promote-to-base, and cross-pool replication.
