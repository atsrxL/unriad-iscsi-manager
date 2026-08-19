<?php
require_once '/usr/local/emhttp/plugins/unraid-iscsi-manager/include/common.php';

define('IZM_STATUS_CLONE_SCRIPT', '/usr/local/emhttp/plugins/unraid-iscsi-manager/scripts/clone-manager.sh');

header('Content-Type: application/json; charset=UTF-8');
header('Cache-Control: no-store, no-cache, must-revalidate, max-age=0');

$lang = (string)($_GET['lang'] ?? 'en');
$zh = stripos($lang, 'zh') === 0;
$t = static function ($en, $cn) use ($zh) { return $zh ? $cn : $en; };

function izm_status_action_reply($ok, $message, array $extra = []) {
    http_response_code($ok ? 200 : 400);
    echo json_encode(array_merge([
        'ok' => (bool)$ok,
        'message' => (string)$message,
    ], $extra), JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES);
    exit;
}

function izm_status_action_clone_run(array $args) {
    $cmd = 'bash ' . escapeshellarg(IZM_STATUS_CLONE_SCRIPT);
    foreach ($args as $arg) $cmd .= ' ' . escapeshellarg((string)$arg);
    $cmd .= ' 2>&1';
    $out = [];
    $ret = 0;
    exec($cmd, $out, $ret);
    return [$ret, trim(implode("\n", $out))];
}

try {
    if (($_SERVER['REQUEST_METHOD'] ?? 'GET') !== 'POST') {
        izm_status_action_reply(false, $t('POST is required.', '仅支持 POST 请求。'));
    }

    [$zfsAvailable, $zfsOutput] = izm_zfs_state();
    if (!$zfsAvailable) {
        izm_status_action_reply(false, $zfsOutput ?: $t('ZFS is not available.', 'ZFS 不可用。'));
    }

    $action = trim((string)($_POST['action'] ?? ''));
    $ret = 1;
    $out = $t('Unknown action.', '未知操作。');

    switch ($action) {
        case 'create_snapshot':
            $zvol = trim((string)($_POST['zvol'] ?? ''));
            $name = trim((string)($_POST['snapshot_name'] ?? ''));
            if ($zvol === '') izm_status_action_reply(false, $t('ZVOL is required.', '缺少 ZVOL。'));
            [$ret, $out] = izm_run(['create-snapshot', $zvol, $name]);
            break;

        case 'delete_snapshot':
            $snapshot = trim((string)($_POST['snapshot'] ?? ''));
            if ($snapshot === '') izm_status_action_reply(false, $t('Snapshot is required.', '缺少快照。'));
            [$ret, $out] = izm_run(['delete-snapshot', $snapshot]);
            break;

        case 'clone_snapshot':
            $snapshot = trim((string)($_POST['snapshot'] ?? ''));
            $name = trim((string)($_POST['clone_name'] ?? ''));
            if ($snapshot === '') izm_status_action_reply(false, $t('Snapshot is required.', '缺少来源快照。'));
            [$ret, $out] = izm_run(['clone-snapshot', $snapshot, $name]);
            break;

        case 'delete_clone':
            $clone = trim((string)($_POST['clone'] ?? ''));
            if ($clone === '') izm_status_action_reply(false, $t('Clone is required.', '缺少 Clone。'));
            [$ret, $out] = izm_status_action_clone_run(['delete', $clone]);
            break;

        default:
            izm_status_action_reply(false, $t('Unknown action.', '未知操作。'));
    }

    if ($ret !== 0) {
        $out = preg_replace('/^ERROR:\s*/m', '', $out ?: $t('Operation failed.', '操作失败。'));
        izm_status_action_reply(false, $out);
    }

    izm_status_action_reply(true, $out ?: $t('Operation completed.', '操作完成。'));
} catch (Throwable $e) {
    izm_status_action_reply(false, get_class($e) . ': ' . $e->getMessage());
}
