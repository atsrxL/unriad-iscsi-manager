<?php

function izm_i18n_locale() {
    global $locale;
    $value = (string)($locale ?? ($_SESSION['locale'] ?? ''));
    return str_replace('-', '_', $value);
}

function izm_i18n_map() {
    static $map = null;
    if ($map !== null) return $map;

    if (stripos(izm_i18n_locale(), 'zh_CN') !== 0) {
        $map = [];
        return $map;
    }

    $map = [
        'iSCSI ZVOL Manager' => 'iSCSI ZVOL 管理器',
        'Z Status' => 'ZFS / iSCSI 状态',
        'ZVOL Creator' => 'ZVOL 创建',
        'Snapshot Manager' => '快照管理',
        'Snapshot Refresher' => '快照刷新',
        'Misc' => '其他',

        'Snapshots are the restore points. Every ZVOL is shown below with all of its snapshots expanded; clones are shown directly under the snapshot they depend on.' => '快照是恢复点。下面会直接列出每个 ZVOL 及其全部快照；Clone 会显示在它所依赖的快照下方。',
        'Snapshots are the restore points. Clones created from a snapshot are shown directly underneath it, so the dependency is visible before you delete anything.' => '快照是恢复点。由快照创建的 Clone 会直接显示在其下方，因此删除前可以清楚看到依赖关系。',
        'Create a ZVOL on a selected ZFS pool for later use as an iSCSI block backstore.' => '在指定 ZFS Pool 上创建 ZVOL，供后续作为 iSCSI 块设备后端使用。',
        'A ZVOL belongs to a ZFS pool. It cannot be pinned to one physical disk inside a multi-device pool.' => 'ZVOL 属于 ZFS Pool，无法指定固定存放在多盘 Pool 中的某一块物理磁盘上。',
        'Use the current state of one ZVOL as a new base and replace selected same-pool targets with CoW clones. Existing targets are retained as timestamped backup ZVOLs.' => '将某个 ZVOL 当前状态作为新的 Base，并用 CoW Clone 替换同一 Pool 中选定的目标。原目标会保留为带时间戳的备份 ZVOL。',
        'Overview of ZFS pools, ZVOLs, LIO mappings, active initiators, and discard/TRIM capability.' => '查看 ZFS Pool、ZVOL、LIO 映射、活动 Initiator 以及 Discard/TRIM 能力。',

        'Create ZVOL' => '创建 ZVOL',
        'Create snapshot' => '创建快照',
        'Create Snapshot' => '创建快照',
        'Create clone' => '创建 Clone',
        'Create Clone' => '创建 Clone',
        'Delete Snapshot' => '删除快照',
        'Delete Clone' => '删除 Clone',
        'Refresh Selected' => '刷新选中目标',
        'Pool capacity' => 'Pool 容量',
        'Refresh targets' => '刷新目标',
        'Safe Refresh behavior' => '安全刷新行为',
        'Active Sessions' => '活动会话',
        'Dependent clones' => '依赖的 Clone',
        'DEPENDENT CLONES' => '依赖的 CLONE',
        'No clones depend on this snapshot.' => '没有 Clone 依赖此快照。',
        'No snapshots found for this ZVOL.' => '此 ZVOL 当前没有快照。',
        'No snapshots yet.' => '当前没有快照。',
        'No ZVOLs found.' => '未找到 ZVOL。',
        'No ZFS pools found.' => '未找到 ZFS Pool。',
        'No active iSCSI sessions detected.' => '未检测到活动 iSCSI 会话。',
        'No IQN/LUN mappings detected under' => '未在以下路径检测到 IQN/LUN 映射：',

        'Leave the name blank to generate' => '名称留空时自动生成',
        'optional custom name' => '可选自定义名称',
        'Clone is created instantly with ZFS CoW and will appear below this snapshot.' => 'Clone 使用 ZFS CoW 即时创建，并会显示在此快照下方。',
        'Unique Used is the space uniquely pinned by a snapshot. A snapshot with dependent clones cannot be deleted until those clones are removed. Clone deletion is non-recursive and is blocked while the clone is mapped to iSCSI, actively connected, locally busy, or has snapshots of its own.' => 'Unique Used 表示该快照独占并固定的空间。存在依赖 Clone 时不能删除快照。删除 Clone 不会递归执行；当 Clone 仍映射到 iSCSI、存在活动连接、本地占用或自身仍有快照时，删除会被阻止。',
        'Delete the dependent clones first' => '请先删除依赖此快照的 Clone',
        'Delete its snapshots first' => '请先删除此 Clone 自己的快照',
        'Delete this snapshot? This cannot be undone.' => '确定删除此快照？此操作无法撤销。',
        'Delete this clone? This destroys the clone ZVOL only and cannot be undone.' => '确定删除此 Clone？仅会销毁该 Clone ZVOL，且无法撤销。',
        'Create this ZVOL?' => '确定创建此 ZVOL？',
        'Refresh selected targets from this source? Old targets will be retained as backup ZVOLs.' => '确定使用此源刷新选中的目标？旧目标会保留为备份 ZVOL。',
        'Selected ZVOL no longer exists.' => '所选 ZVOL 已不存在。',

        'Snapshot name' => '快照名称',
        'Snapshot tree' => '快照列表',
        'Snapshot' => '快照',
        'Snapshots' => '快照',
        'ZVOLs' => 'ZVOL',
        'ZPOOLs' => 'ZFS Pool',
        'Name' => '名称',
        'Size' => '大小',
        'Used' => '已用',
        'Referenced Data' => 'Referenced 数据',
        'Unique Used' => 'Unique Used',
        'Created' => '创建时间',
        'Provisioning' => '制备方式',
        'Provision' => '制备',
        'Compression' => '压缩',
        'Volblocksize' => '块大小',
        'Block' => '块大小',
        'Allocated' => '已分配',
        'Free' => '可用',
        'Health' => '健康状态',
        'Status' => '状态',
        'Actions' => '操作',
        'Source ZVOL' => '源 ZVOL',
        'Targets' => '目标',
        'Session State' => '会话状态',
        'Connection State' => '连接状态',
        'Transport' => '传输协议',
        'Mode' => '模式',
        'LUNs' => 'LUN',
        'Autotrim' => '自动 TRIM',

        'Thin / sparse' => '精简 / Thin',
        'Thick / reserved' => '厚制备 / Thick',
        'Thin' => '精简',
        'Thick' => '厚制备',
        'Mapped / Offline' => '已映射 / 离线',
        'Mapped' => '已映射',
        'Connected' => '已连接',
        'Offline' => '离线',
        'Not mapped' => '未映射',
        'Blocked' => '已阻止',
        'Enabled' => '已启用',
        'Disabled' => '已禁用',
        'Run / Resume' => '运行 / 继续',
        'Suspend' => '暂停',
        'Cancel' => '取消',
        'Apply' => '应用',
        'Save' => '保存',
        'Enable' => '启用',
        'Disable' => '禁用',

        'Operation completed.' => '操作完成。',
        'Operation failed.' => '操作失败。',
        'ZVOL created.' => 'ZVOL 创建完成。',
        'Create failed.' => '创建失败。',
        'ZFS is not available.' => 'ZFS 不可用。',
        'zfs/zpool commands were not found' => '未找到 zfs/zpool 命令',
        'origin:' => '来源：',
        'auto:' => '自动：',
        ' dependent clone' => ' 个依赖 Clone',
        ' dependent clones' => ' 个依赖 Clone',
        ' snapshot' => ' 个快照',
        ' snapshots' => ' 个快照',
    ];

    uksort($map, static function ($a, $b) {
        return strlen($b) <=> strlen($a);
    });
    return $map;
}

function izm_i18n_translate_output($html) {
    $map = izm_i18n_map();
    return $map ? strtr($html, $map) : $html;
}

function izm_i18n_start() {
    static $started = false;
    if ($started || !izm_i18n_map()) return;
    $started = true;
    ob_start('izm_i18n_translate_output');
}
