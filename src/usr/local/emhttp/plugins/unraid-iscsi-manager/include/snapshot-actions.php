<?php
require_once '/usr/local/emhttp/plugins/unraid-iscsi-manager/include/common.php';

if (!defined('IZM_SNAPSHOT_CLONE_SCRIPT')) {
    define('IZM_SNAPSHOT_CLONE_SCRIPT', '/usr/local/emhttp/plugins/unraid-iscsi-manager/scripts/clone-manager.sh');
}

function izm_snapshot_action_clone_run(array $args) {
    $cmd = 'bash ' . escapeshellarg(IZM_SNAPSHOT_CLONE_SCRIPT);
    foreach ($args as $arg) $cmd .= ' ' . escapeshellarg((string)$arg);
    $cmd .= ' 2>&1';
    $out = [];
    $ret = 0;
    exec($cmd, $out, $ret);
    return [$ret, trim(implode("\n", $out))];
}

/**
 * Execute one snapshot/clone mutation through the single backend used by both
 * Snapshot Manager and Z Status.
 *
 * Returns [returnCode, output, focusVolume].
 */
function izm_snapshot_action_execute($action, array $input, ?array $volumeNames = null) {
    $action = trim((string)$action);
    $selected = trim((string)($input['selected_zvol'] ?? $input['zvol'] ?? ''));
    $focusVolume = $selected;

    if ($volumeNames === null) {
        $volumeNames = array_column(izm_load_volumes(), 'name');
    }

    if ($selected !== '' && !in_array($selected, $volumeNames, true) && $action !== 'delete_clone') {
        return [1, 'Selected ZVOL no longer exists.', $focusVolume];
    }

    switch ($action) {
        case 'create_snapshot':
            if ($selected === '') return [1, 'Selected ZVOL is required.', $focusVolume];
            return array_merge(
                izm_run(['create-snapshot', $selected, trim((string)($input['snapshot_name'] ?? ''))]),
                [$focusVolume]
            );

        case 'delete_snapshot':
            $snapshot = trim((string)($input['snapshot'] ?? ''));
            if ($snapshot === '') return [1, 'Snapshot is required.', $focusVolume];
            $focusVolume = strstr($snapshot, '@', true) ?: $selected;
            return array_merge(izm_run(['delete-snapshot', $snapshot]), [$focusVolume]);

        case 'clone_snapshot':
            $snapshot = trim((string)($input['snapshot'] ?? ''));
            if ($snapshot === '') return [1, 'Snapshot is required.', $focusVolume];
            $focusVolume = strstr($snapshot, '@', true) ?: $selected;
            return array_merge(
                izm_run(['clone-snapshot', $snapshot, trim((string)($input['clone_name'] ?? ''))]),
                [$focusVolume]
            );

        case 'delete_clone':
            $clone = trim((string)($input['clone'] ?? ''));
            if ($clone === '') return [1, 'Clone is required.', $focusVolume];
            return array_merge(izm_snapshot_action_clone_run(['delete', $clone]), [$focusVolume]);

        default:
            return [1, 'Unknown action.', $focusVolume];
    }
}
