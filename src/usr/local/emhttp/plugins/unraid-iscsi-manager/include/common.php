<?php

define('IZM_SCRIPT', '/usr/local/emhttp/plugins/unraid-iscsi-manager/scripts/zvol-manager.sh');
define('IZM_ISCSI_SCRIPT', '/usr/local/emhttp/plugins/unraid-iscsi-manager/scripts/iscsi-map.sh');
define('IZM_SESSIONS_SCRIPT', '/usr/local/emhttp/plugins/unraid-iscsi-manager/scripts/iscsi-sessions.sh');

require_once '/usr/local/emhttp/plugins/unraid-iscsi-manager/include/i18n.php';

function izm_h($value) {
    return htmlspecialchars((string)$value, ENT_QUOTES | ENT_SUBSTITUTE, 'UTF-8');
}

function izm_run(array $args) {
    $cmd = 'bash ' . escapeshellarg(IZM_SCRIPT);
    foreach ($args as $arg) {
        $cmd .= ' ' . escapeshellarg((string)$arg);
    }
    $cmd .= ' 2>&1';
    $out = [];
    $ret = 0;
    exec($cmd, $out, $ret);
    return [$ret, trim(implode("\n", $out))];
}

function izm_script_lines($script) {
    if (!is_file($script)) return [];
    $cmd = 'bash ' . escapeshellarg($script) . ' 2>&1';
    $lines = [];
    $ret = 0;
    exec($cmd, $lines, $ret);
    return $ret === 0 ? $lines : [];
}

function izm_rows(array $args, $columns) {
    [$ret, $output] = izm_run($args);
    if ($ret !== 0 || $output === '') return [];
    $rows = [];
    foreach (preg_split('/\R/', $output) as $line) {
        if ($line === '') continue;
        $parts = explode("\t", $line);
        $parts = array_pad($parts, $columns, '');
        $rows[] = array_slice($parts, 0, $columns);
    }
    return $rows;
}

function izm_bytes($value) {
    if (!is_numeric($value) || $value === '') return (string)$value;
    $n = (float)$value;
    $units = ['B', 'KiB', 'MiB', 'GiB', 'TiB', 'PiB'];
    $i = 0;
    while ($n >= 1024 && $i < count($units) - 1) {
        $n /= 1024;
        $i++;
    }
    if ($i === 0) return number_format($n, 0) . ' ' . $units[$i];
    $digits = $n >= 100 ? 0 : ($n >= 10 ? 1 : 2);
    return number_format($n, $digits) . ' ' . $units[$i];
}

function izm_block($value) {
    if (!is_numeric($value)) return (string)$value;
    $n = (int)$value;
    if ($n >= 1024 && $n % 1024 === 0) return ($n / 1024) . 'K';
    return (string)$n;
}

function izm_creation($value) {
    if (ctype_digit((string)$value)) return date('Y-m-d H:i:s', (int)$value);
    return (string)$value;
}

function izm_load_pools() {
    $rows = izm_rows(['pools'], 5);
    $out = [];
    foreach ($rows as $row) {
        [$name, $size, $alloc, $free, $health] = $row;
        $out[] = compact('name', 'size', 'alloc', 'free', 'health');
    }
    return $out;
}

function izm_load_pool_trim_info() {
    $rows = izm_rows(['pool-trim-info'], 2);
    $out = [];
    foreach ($rows as $row) {
        [$name, $autotrim] = $row;
        $out[$name] = compact('name', 'autotrim');
    }
    return $out;
}

function izm_load_volumes() {
    $rows = izm_rows(['volumes'], 8);
    $out = [];
    foreach ($rows as $row) {
        [$name, $volsize, $used, $refer, $compression, $volblocksize, $refreservation, $origin] = $row;
        $pool = explode('/', $name, 2)[0];
        $provision = ($origin !== '' && $origin !== '-')
            ? 'Clone'
            : ((is_numeric($refreservation) && (int)$refreservation > 0) ? 'Thick' : 'Thin');
        $out[] = compact('name', 'pool', 'volsize', 'used', 'refer', 'compression', 'volblocksize', 'refreservation', 'origin', 'provision');
    }
    return $out;
}

function izm_load_volume_discard_info() {
    $rows = izm_rows(['volume-discard-info'], 4);
    $out = [];
    foreach ($rows as $row) {
        [$name, $supported, $max, $granularity] = $row;
        $out[$name] = compact('name', 'supported', 'max', 'granularity');
    }
    return $out;
}

function izm_load_snapshots($volume) {
    if ($volume === '') return [];
    $rows = izm_rows(['snapshots', $volume], 4);
    $out = [];
    foreach ($rows as $row) {
        [$name, $creation, $used, $refer] = $row;
        $out[] = compact('name', 'creation', 'used', 'refer');
    }
    return $out;
}

function izm_load_iscsi_mappings() {
    $lines = izm_script_lines(IZM_ISCSI_SCRIPT);
    if (empty($lines)) return [];

    $out = [];
    foreach ($lines as $line) {
        if ($line === '') continue;
        $row = array_pad(explode("\t", $line), 8, '');
        [$iqn, $tpg, $lun, $backstore, $device, $alua, $zvol, $unmap] = array_slice($row, 0, 8);
        $out[] = compact('iqn', 'tpg', 'lun', 'backstore', 'device', 'alua', 'zvol', 'unmap');
    }
    return $out;
}

function izm_mappings_by_zvol(array $mappings) {
    $out = [];
    foreach ($mappings as $mapping) {
        if (($mapping['zvol'] ?? '') === '') continue;
        $out[$mapping['zvol']][] = $mapping;
    }
    return $out;
}

function izm_load_iscsi_sessions(array $mappings = []) {
    $lines = izm_script_lines(IZM_SESSIONS_SCRIPT);
    if (empty($lines)) return [];

    $byBackstore = [];
    $byTarget = [];
    foreach ($mappings as $mapping) {
        $backstore = $mapping['backstore'] ?? '';
        if ($backstore !== '') $byBackstore[$backstore][] = $mapping;
        $targetKey = ($mapping['iqn'] ?? '') . "\x1f" . ($mapping['tpg'] ?? '');
        if (($mapping['iqn'] ?? '') !== '') $byTarget[$targetKey][] = $mapping;
    }

    $out = [];
    $seen = [];
    foreach ($lines as $line) {
        if ($line === '') continue;
        $row = array_pad(explode("\t", $line), 12, '');
        [
            $sid, $alias, $initiator, $sessionState, $connectionState, $address,
            $transport, $mappedLun, $backstore, $mode, $reportedTargetIqn, $reportedTargetTpg
        ] = array_slice($row, 0, 12);

        if ($backstore !== '') {
            $matches = $byBackstore[$backstore] ?? [null];
        } elseif ($reportedTargetIqn !== '') {
            $targetKey = $reportedTargetIqn . "\x1f" . $reportedTargetTpg;
            $matches = $byTarget[$targetKey] ?? [null];
        } else {
            $matches = [null];
        }

        foreach ($matches as $mapping) {
            $targetIqn = $mapping['iqn'] ?? $reportedTargetIqn;
            $targetTpg = $mapping['tpg'] ?? $reportedTargetTpg;
            $targetLun = $mapping['lun'] ?? '';
            $zvol = $mapping['zvol'] ?? '';
            $unmap = $mapping['unmap'] ?? 'unknown';
            $effectiveBackstore = $mapping['backstore'] ?? $backstore;
            $effectiveMappedLun = $mappedLun;
            if ($effectiveMappedLun === '' && preg_match('/^Lun([0-9]+)$/i', $targetLun, $m)) {
                $effectiveMappedLun = $m[1];
            }

            $dedupeKey = implode('|', [$initiator, $targetIqn, $targetLun, $effectiveBackstore]);
            if (isset($seen[$dedupeKey])) continue;
            $seen[$dedupeKey] = true;

            $dynamic = ($sid === 'dynamic');
            $backstore = $effectiveBackstore;
            $mappedLun = $effectiveMappedLun;
            $out[] = compact(
                'sid', 'alias', 'initiator', 'sessionState', 'connectionState', 'address',
                'transport', 'mappedLun', 'backstore', 'mode', 'targetIqn', 'targetTpg',
                'targetLun', 'zvol', 'unmap', 'dynamic'
            );
        }
    }
    return $out;
}

function izm_sessions_by_zvol(array $sessions) {
    $out = [];
    foreach ($sessions as $session) {
        $zvol = $session['zvol'] ?? '';
        if ($zvol === '') continue;
        $out[$zvol][] = $session;
    }
    return $out;
}

function izm_zfs_state() {
    [$ret, $output] = izm_run(['pools']);
    return [$ret === 0, $output];
}

function izm_csrf() {
    global $var;
    return izm_h($var['csrf_token'] ?? '');
}

function izm_styles() {
    echo <<<'CSS'
<style>
.izm-wrap { max-width:1500px; }
.izm-grid { display:grid; grid-template-columns:repeat(auto-fit,minmax(360px,1fr)); gap:16px; margin:16px 0; }
.izm-card { border:1px solid rgba(127,127,127,.35); border-radius:8px; padding:16px; margin:16px 0; background:rgba(127,127,127,.04); }
.izm-title { font-size:18px; font-weight:600; margin-bottom:12px; }
.izm-sub { opacity:.75; margin:-6px 0 14px; line-height:1.5; }
.izm-row { display:flex; flex-wrap:wrap; gap:10px 14px; align-items:flex-end; margin:10px 0; }
.izm-field { display:flex; flex-direction:column; gap:5px; min-width:150px; flex:1; }
.izm-field label { font-weight:600; }
.izm-field input[type=text], .izm-field select { width:100%; box-sizing:border-box; }
.izm-table { width:100%; border-collapse:collapse; }
.izm-table th, .izm-table td { padding:8px 10px; border-bottom:1px solid rgba(127,127,127,.25); text-align:left; vertical-align:middle; }
.izm-table th { font-weight:600; }
.izm-table code { white-space:nowrap; }
.izm-ok, .izm-err, .izm-warn { white-space:pre-wrap; border-radius:6px; padding:11px 13px; margin:12px 0; }
.izm-ok { background:rgba(40,167,69,.13); border:1px solid rgba(40,167,69,.35); }
.izm-err { background:rgba(220,53,69,.13); border:1px solid rgba(220,53,69,.35); }
.izm-warn { background:rgba(255,193,7,.13); border:1px solid rgba(255,193,7,.35); }
.izm-actions { display:flex; gap:8px; align-items:center; flex-wrap:wrap; }
.izm-actions form { display:inline-block; margin:0; }
.izm-small { font-size:12px; opacity:.75; }
.izm-targets { display:grid; grid-template-columns:repeat(auto-fit,minmax(260px,1fr)); gap:8px; margin:12px 0; }
.izm-target { padding:9px 10px; border:1px solid rgba(127,127,127,.25); border-radius:5px; }
.izm-target.disabled { opacity:.38; }
.izm-pill { display:inline-block; border:1px solid rgba(127,127,127,.35); border-radius:999px; padding:2px 7px; font-size:12px; }
.izm-pill-ok { border-color:rgba(40,167,69,.5); background:rgba(40,167,69,.12); }
.izm-pill-live { border-color:rgba(0,123,255,.55); background:rgba(0,123,255,.13); }
.izm-pill-warn { border-color:rgba(255,193,7,.5); background:rgba(255,193,7,.12); }
.izm-lun-tree { border-top:1px solid rgba(127,127,127,.22); }
.izm-iqn { padding:12px 8px 7px; font-weight:600; }
.izm-lun-row { margin-left:24px; padding:6px 8px 10px 18px; border-left:1px solid rgba(127,127,127,.28); display:grid; grid-template-columns:minmax(70px,100px) minmax(220px,1fr) minmax(220px,1fr) minmax(170px,auto); gap:10px; align-items:center; }
.izm-lun-device { opacity:.8; overflow-wrap:anywhere; }
.izm-dot { font-size:10px; vertical-align:2px; margin-right:5px; }
.izm-code { padding:8px 10px; border:1px solid rgba(127,127,127,.25); border-radius:5px; font-family:monospace; display:inline-block; }
@media (max-width:900px) { .izm-lun-row { grid-template-columns:1fr; } }
@media (max-width:700px) { .izm-table { display:block; overflow-x:auto; } }
</style>
CSS;
    izm_i18n_emit_script();
}

function izm_notices($message, $error, $zfsAvailable, $zfsOutput = '') {
    if (!$zfsAvailable) {
        echo '<div class="izm-err"><strong>ZFS is not available.</strong><br>' . izm_h($zfsOutput ?: 'zfs/zpool commands were not found') . '</div>';
        return;
    }
    if ($message !== '') echo '<div class="izm-ok">' . izm_h($message) . '</div>';
    if ($error !== '') echo '<div class="izm-err">' . izm_h($error) . '</div>';
}
