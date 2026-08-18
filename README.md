# iSCSI ZVOL Manager for Unraid

A lightweight Unraid WebGUI plugin for managing ZFS volumes intended to be used as iSCSI LUN backstores.

## Install

In **Unraid → Plugins → Install Plugin**, paste:

```text
https://github.com/atsrxL/unriad-iscsi-manager/releases/latest/download/unraid-iscsi-manager.plg
```

Then open **Settings → iSCSI ZVOL Manager**.

## V1 features

- Create ZVOLs on a selected ZFS pool.
- Thin (sparse) or thick (reserved) provisioning.
- LZ4 compression on/off.
- `volblocksize`: 4K, 8K, 16K, 32K, 64K, 128K.
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
- Best-effort `targetcli` / `fuser` checks to catch active exports or users before refresh.

## Important safety notes

This plugin manages block devices. Before Refresh/Rebase, disconnect the source and all selected target LUNs from every iSCSI initiator and target mapping.

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
./scripts/build-release.sh
```

Artifacts are written to `dist/`:

```text
dist/unraid-iscsi-manager.plg
dist/unraid-iscsi-manager-<version>.txz
```

Pushing a release-related change to `main` runs the GitHub Actions workflow and publishes/replaces the release whose tag matches `VERSION`.

## Current scope / roadmap

V1 focuses on safe ZFS lifecycle operations. Good next steps are direct integration with the specific Unraid iSCSI target plugin, explicit LUN session discovery/offline handling, backup cleanup/retention, promote-to-base, and cross-pool replication.
