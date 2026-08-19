<?php
require_once '/usr/local/emhttp/plugins/unraid-iscsi-manager/include/common.php';

header('Content-Type: text/html; charset=UTF-8');
header('Cache-Control: no-store, no-cache, must-revalidate, max-age=0');

$lang = (string)($_GET['lang'] ?? 'en');
$zh = stripos($lang, 'zh') === 0;
$t = static function ($en, $cn) use ($zh) { return $zh ? $cn : $en; };

$var = $var ?? (@parse_ini_file('state/var.ini') ?: []);
$message = '';
$error = '';

try {
    [$zfsAvailable, $zfsOutput] = izm_zfs_state();

    if ($_SERVER['REQUEST_METHOD'] === 'POST') {
        if (!$zfsAvailable) throw new RuntimeException($zfsOutput ?: 'ZFS is not available.');
        $action = (string)($_POST['action'] ?? '');
        $pool = trim((string)($_POST['pool'] ?? ''));
        if ($action === 'set_autotrim') {
            [$ret, $out] = izm_run(['set-autotrim', $pool, (string)($_POST['autotrim'] ?? 'off')]);
        } elseif ($action === 'pool_trim') {
            [$ret, $out] = izm_run(['pool-trim', $pool, (string)($_POST['trim_action'] ?? 'start')]);
        } else {
            $ret = 1;
            $out = 'Unknown action.';
        }
        if ($ret === 0) $message = $out ?: $t('Operation completed.', '操作完成。');
        else $error = preg_replace('/^ERROR:\s*/m', '', $out ?: $t('Operation failed.', '操作失败。'));
    }

    $pools = $zfsAvailable ? izm_load_pools() : [];
    $poolTrim = $zfsAvailable ? izm_load_pool_trim_info() : [];
    $volumes = $zfsAvailable ? izm_load_volumes() : [];
    $discardInfo = $zfsAvailable ? izm_load_volume_discard_info() : [];
    $mappings = $zfsAvailable ? izm_load_iscsi_mappings() : [];
    $mappedByZvol = izm_mappings_by_zvol($mappings);
    $sessions = $zfsAvailable ? izm_load_iscsi_sessions($mappings) : [];
    $sessionsByZvol = izm_sessions_by_zvol($sessions);

    $volumeByName = [];
    $poolVolumeNames = [];
    $snapshotsByVolume = [];
    $snapshotNames = [];
    $clonesByOrigin = [];

    foreach ($volumes as $v) {
        $name = (string)($v['name'] ?? '');
        if ($name === '') continue;
        $volumeByName[$name] = $v;
        $pool = (string)($v['pool'] ?? explode('/', $name, 2)[0]);
        $poolVolumeNames[$pool][] = $name;
    }

    foreach ($volumeByName as $name => $v) {
        $snaps = izm_load_snapshots($name);
        $snapshotsByVolume[$name] = $snaps;
        foreach ($snaps as $s) {
            $sn = (string)($s['name'] ?? '');
            if ($sn !== '') $snapshotNames[$sn] = true;
        }
        $origin = (string)($v['origin'] ?? '');
        if ($origin !== '' && $origin !== '-') $clonesByOrigin[$origin][] = $name;
    }

    foreach ($poolVolumeNames as &$names) { natcasesort($names); $names = array_values($names); }
    unset($names);
    foreach ($clonesByOrigin as &$names) { natcasesort($names); $names = array_values($names); }
    unset($names);

    $pill = static function ($text, $class = '') {
        return '<span class="izm-pill ' . izm_h($class) . '">' . izm_h($text) . '</span>';
    };

    $renderIscsi = static function ($name) use ($mappedByZvol, $sessionsByZvol, $pill, $t) {
        $maps = $mappedByZvol[$name] ?? [];
        $live = $sessionsByZvol[$name] ?? [];
        if ($live) {
            echo $pill($t('Connected', '已连接'), 'izm-pill-live');
            foreach ($live as $s) {
                $ip = trim((string)($s['address'] ?? '')) ?: $t('IP unavailable', 'IP 不可用');
                $iqn = trim((string)($s['initiator'] ?? '')) ?: $t('unknown initiator', '未知 Initiator');
                echo '<div class="izm-small izm-iscsi-detail">' . izm_h($ip . ' · ' . $iqn) . '</div>';
            }
        } elseif ($maps) {
            echo $pill($t('Mapped / Offline', '已映射 / 离线'), 'izm-pill-ok');
            foreach ($maps as $m) {
                $iqn = trim((string)($m['iqn'] ?? '')) ?: $t('unknown target', '未知 Target');
                $lun = trim((string)($m['lun'] ?? '')) ?: $t('unknown LUN', '未知 LUN');
                echo '<div class="izm-small izm-iscsi-detail">' . izm_h($iqn . ' / ' . $lun) . '</div>';
            }
        } else {
            echo $pill($t('Not mapped', '未映射'));
        }
    };

    $renderVolume = null;
    $renderVolume = static function ($name, $depth = 0, $ancestors = []) use (
        &$renderVolume, $volumeByName, $snapshotsByVolume, $clonesByOrigin,
        $discardInfo, $renderIscsi, $pill, $t
    ) {
        if (!isset($volumeByName[$name])) return;
        if ($depth > 20 || isset($ancestors[$name])) {
            echo '<div class="izm-tree-error">' . izm_h($t('Tree cycle/depth guard reached.', '检测到树结构循环或层级过深。')) . '</div>';
            return;
        }
        $ancestors[$name] = true;
        $v = $volumeByName[$name];
        $origin = (string)($v['origin'] ?? '');
        $isClone = $origin !== '' && $origin !== '-';
        $snaps = $snapshotsByVolume[$name] ?? [];
        $discard = (string)($discardInfo[$name]['supported'] ?? 'unknown');
        ?>
        <div class="izm-tree-volume <?=$isClone ? 'is-clone' : 'is-root'?>" style="--depth:<?=$depth?>">
          <div class="izm-tree-row izm-volume-row">
            <div class="izm-tree-main">
              <strong><i class="fa <?=$isClone ? 'fa-code-fork' : 'fa-hdd-o'?>"></i> <code><?=izm_h($name)?></code></strong>
              <div class="izm-tree-sub"><?=izm_h(izm_bytes($v['volsize']))?> · <?=izm_h($v['provision'])?> · <?=izm_h($v['compression'])?> · block <?=izm_h(izm_block($v['volblocksize']))?></div>
              <?php if ($isClone): ?><div class="izm-tree-sub"><?=$t('Origin', '来源')?>: <code><?=izm_h($origin)?></code></div><?php endif; ?>
            </div>
            <div><span class="izm-stat-label"><?=$t('Used / Referenced', '已用 / Referenced')?></span><?=izm_h(izm_bytes($v['used']))?><div class="izm-small"><?=izm_h(izm_bytes($v['refer']))?></div></div>
            <div><span class="izm-stat-label"><?=$t('Snapshots', '快照')?></span><?=count($snaps)?></div>
            <div><span class="izm-stat-label">Discard</span><?php if ($discard === 'yes') echo $pill($t('Supported', '支持'), 'izm-pill-ok'); elseif ($discard === 'no') echo $pill($t('No discard', '不支持 Discard'), 'izm-pill-warn'); else echo '—'; ?></div>
            <div class="izm-tree-iscsi"><span class="izm-stat-label">iSCSI / Initiator</span><?php $renderIscsi($name); ?></div>
          </div>
          <?php foreach ($snaps as $s):
              $snapName = (string)($s['name'] ?? '');
              if ($snapName === '') continue;
              $leaf = strstr($snapName, '@');
              if ($leaf === false) $leaf = $snapName;
              $children = $clonesByOrigin[$snapName] ?? [];
          ?>
          <div class="izm-tree-snapshot" style="--depth:<?=$depth + 1?>">
            <div class="izm-tree-row izm-snapshot-row">
              <div class="izm-tree-main"><strong><i class="fa fa-camera"></i> <?=izm_h($leaf)?></strong><div class="izm-tree-sub"><code><?=izm_h($snapName)?></code></div></div>
              <div><span class="izm-stat-label"><?=$t('Created', '创建时间')?></span><?=izm_h(izm_creation($s['creation']))?></div>
              <div><span class="izm-stat-label"><?=$t('Unique Used', '独占使用')?></span><?=izm_h(izm_bytes($s['used']))?></div>
              <div><span class="izm-stat-label">Referenced</span><?=izm_h(izm_bytes($s['refer']))?></div>
              <div><span class="izm-stat-label">Clone</span><?=$pill((string)count($children))?></div>
            </div>
            <?php foreach ($children as $child) $renderVolume($child, $depth + 2, $ancestors); ?>
          </div>
          <?php endforeach; ?>
        </div>
        <?php
    };
} catch (Throwable $e) {
    http_response_code(500);
    echo '<div class="izm-runtime-error"><strong>' . izm_h($t('Z Status backend error', 'Z Status 后端错误')) . '</strong><br>' . izm_h(get_class($e) . ': ' . $e->getMessage()) . '</div>';
    exit;
}

izm_styles();
$csrf = izm_csrf();
?>
<style>
.izm-resource-tree{display:flex;flex-direction:column;gap:16px}.izm-pool-node{border:1px solid rgba(127,127,127,.32);border-radius:8px;overflow:hidden;background:rgba(127,127,127,.025)}
.izm-pool-head{display:grid;grid-template-columns:minmax(300px,1fr) minmax(430px,.95fr);gap:18px;padding:14px 16px;background:rgba(127,127,127,.045);border-bottom:1px solid rgba(127,127,127,.2)}
.izm-pool-name{font-size:17px;font-weight:600}.izm-pool-meta{display:flex;gap:7px;flex-wrap:wrap;margin-top:8px}.izm-trim-box{display:flex;flex-direction:column;gap:8px}.izm-trim-line{display:grid;grid-template-columns:105px auto 1fr;gap:9px;align-items:center}.izm-trim-label{font-weight:600}.izm-trim-note{font-size:12px;opacity:.7;line-height:1.35}.izm-trim-buttons{display:flex;gap:7px;flex-wrap:wrap}.izm-trim-buttons form{margin:0}
.izm-pool-body{padding:8px 0 12px}.izm-pool-empty{padding:13px 16px;opacity:.7}.izm-tree-volume,.izm-tree-snapshot{margin-left:calc(14px + (var(--depth) * 16px));margin-right:14px;position:relative}.izm-tree-volume:before,.izm-tree-snapshot:before{content:"";position:absolute;left:-10px;top:0;bottom:0;border-left:1px solid rgba(127,127,127,.24)}.izm-tree-volume+.izm-tree-volume{margin-top:7px}.izm-tree-snapshot{margin-top:6px}
.izm-tree-row{display:grid;grid-template-columns:minmax(280px,1.3fr) minmax(120px,.45fr) minmax(90px,.3fr) minmax(115px,.38fr) minmax(280px,1fr);gap:12px;align-items:start;padding:10px 12px;border-radius:5px}.izm-volume-row{background:rgba(127,127,127,.045);border-left:3px solid rgba(127,127,127,.38)}.is-clone>.izm-volume-row{background:rgba(127,127,127,.025);border-left-color:rgba(0,123,255,.35)}.izm-snapshot-row{background:rgba(127,127,127,.018);border-left:2px solid rgba(127,127,127,.2)}
.izm-tree-main{min-width:0}.izm-tree-main strong{display:block;overflow-wrap:anywhere}.izm-tree-main .fa{width:17px;opacity:.62;text-align:center;margin-right:4px}.izm-tree-sub{font-size:12px;opacity:.68;margin-top:4px;overflow-wrap:anywhere}.izm-stat-label{display:block;font-size:11px;opacity:.6;text-transform:uppercase;letter-spacing:.04em;margin-bottom:4px}.izm-tree-iscsi{overflow-wrap:anywhere}.izm-iscsi-detail{margin-top:5px;overflow-wrap:anywhere}.izm-tree-error,.izm-runtime-error{margin:8px 0;padding:8px 10px;border:1px solid rgba(220,53,69,.4);border-radius:5px;background:rgba(220,53,69,.08)}
@media(max-width:1250px){.izm-pool-head{grid-template-columns:1fr}.izm-tree-row{grid-template-columns:1fr 1fr}.izm-tree-main,.izm-tree-iscsi{grid-column:1/-1}}@media(max-width:760px){.izm-trim-line{grid-template-columns:1fr}.izm-tree-volume,.izm-tree-snapshot{margin-left:calc(7px + (var(--depth) * 9px));margin-right:7px}.izm-tree-row{grid-template-columns:1fr}.izm-tree-main,.izm-tree-iscsi{grid-column:auto}}
</style>

<?php if ($message !== ''): ?><div class="izm-ok"><?=izm_h($message)?></div><?php endif; ?>
<?php if ($error !== ''): ?><div class="izm-err"><?=izm_h($error)?></div><?php endif; ?>
<div class="izm-sub"><?=$t('Pool → ZVOL → Snapshot → Clone resource tree, including current iSCSI mapping and initiator information.', '按 Pool → ZVOL → 快照 → Clone 的层级显示资源关系，并直接显示当前 iSCSI 映射及 Initiator 信息。')?></div>

<?php if (!$zfsAvailable): ?>
  <div class="izm-err"><strong><?=$t('ZFS is not available.', 'ZFS 不可用。')?></strong><br><?=izm_h($zfsOutput)?></div>
<?php elseif (empty($pools)): ?>
  <div class="izm-card"><div class="izm-sub"><?=$t('No ZFS pools found.', '未找到 ZFS Pool。')?></div></div>
<?php else: ?>
<div class="izm-resource-tree">
<?php foreach ($pools as $p):
    $poolName = (string)$p['name'];
    $all = $poolVolumeNames[$poolName] ?? [];
    $roots = [];
    foreach ($all as $name) {
        $origin = (string)($volumeByName[$name]['origin'] ?? '');
        if ($origin === '' || $origin === '-' || !isset($snapshotNames[$origin])) $roots[] = $name;
    }
    if (!$roots && $all) $roots = $all;
    $auto = (string)($poolTrim[$poolName]['autotrim'] ?? 'unknown');
?>
<section class="izm-pool-node">
  <div class="izm-pool-head">
    <div>
      <div class="izm-pool-name"><i class="fa fa-database" style="opacity:.65;margin-right:7px"></i><code><?=izm_h($poolName)?></code></div>
      <div class="izm-pool-meta">
        <span class="izm-pill <?=strtoupper((string)$p['health']) === 'ONLINE' ? 'izm-pill-ok' : 'izm-pill-warn'?>"><?=izm_h($p['health'])?></span>
        <span class="izm-pill"><?=izm_h(izm_bytes($p['size']))?> <?=$t('total', '总容量')?></span>
        <span class="izm-pill"><?=izm_h(izm_bytes($p['alloc']))?> <?=$t('allocated', '已分配')?></span>
        <span class="izm-pill"><?=izm_h(izm_bytes($p['free']))?> <?=$t('free', '可用')?></span>
        <span class="izm-pill"><?=count($all)?> ZVOL<?=count($all) === 1 ? '' : 's'?></span>
      </div>
    </div>
    <div class="izm-trim-box">
      <div class="izm-trim-line">
        <div class="izm-trim-label"><?=$t('Automatic TRIM', '自动 TRIM')?></div>
        <form method="post" class="izm-status-form">
          <input type="hidden" name="csrf_token" value="<?=$csrf?>">
          <input type="hidden" name="action" value="set_autotrim">
          <input type="hidden" name="pool" value="<?=izm_h($poolName)?>">
          <select name="autotrim" onchange="this.form.requestSubmit()">
            <option value="off" <?=$auto === 'off' ? 'selected' : ''?>><?=$t('Off', '关')?></option>
            <option value="on" <?=$auto === 'on' ? 'selected' : ''?>><?=$t('On', '开')?></option>
          </select>
        </form>
        <div class="izm-trim-note"><?=$t('Persistent Pool setting. ZFS automatically trims extents it already knows are free.', '持续生效的 Pool 设置。ZFS 自动 TRIM 已经确认空闲的 extent。')?></div>
      </div>
      <div class="izm-trim-line">
        <div class="izm-trim-label"><?=$t('Manual TRIM', '手动 TRIM')?></div>
        <div class="izm-trim-buttons">
          <?php foreach ([
              ['start', $t('Start / Resume', '开始 / 继续'), $t('Start or resume manual TRIM for this pool?', '确定开始或继续此 Pool 的手动 TRIM？')],
              ['suspend', $t('Suspend', '暂停'), $t('Suspend the current manual TRIM job for this pool?', '确定暂停此 Pool 当前的手动 TRIM？')],
              ['cancel', $t('Cancel', '取消'), $t('Cancel the current manual TRIM job for this pool?', '确定取消此 Pool 当前的手动 TRIM？')],
          ] as $ta): ?>
          <form method="post" class="izm-status-form" data-confirm="<?=izm_h($ta[2])?>">
            <input type="hidden" name="csrf_token" value="<?=$csrf?>">
            <input type="hidden" name="action" value="pool_trim">
            <input type="hidden" name="pool" value="<?=izm_h($poolName)?>">
            <input type="hidden" name="trim_action" value="<?=izm_h($ta[0])?>">
            <input type="submit" value="<?=izm_h($ta[1])?>">
          </form>
          <?php endforeach; ?>
        </div>
        <div class="izm-trim-note"><?=$t('One-time Pool job. Suspend pauses it; Start / Resume continues it; Cancel stops it. Separate from Automatic TRIM.', '一次性 Pool 任务：暂停只暂停当前任务；开始 / 继续会启动或恢复；取消会终止。与自动 TRIM 相互独立。')?></div>
      </div>
    </div>
  </div>
  <div class="izm-pool-body">
    <?php if (!$roots): ?>
      <div class="izm-pool-empty"><?=$t('No ZVOLs found in this pool.', '此 Pool 中没有 ZVOL。')?></div>
    <?php else: foreach ($roots as $root): $renderVolume($root); endforeach; endif; ?>
  </div>
</section>
<?php endforeach; ?>
</div>
<?php endif; ?>
