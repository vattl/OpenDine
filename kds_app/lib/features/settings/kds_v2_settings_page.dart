import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:kds_app/core/api/kds_api.dart';
import 'package:kds_app/core/config/api_base_util.dart';
import 'package:kds_app/core/config/kds_app_config.dart';
import 'package:kds_app/core/config/kds_connection_mode.dart';
import 'package:kds_app/core/storage/app_prefs.dart';
import 'package:kds_app/core/storage/kds_file_logger.dart';
import 'package:kds_app/core/theme/kds_theme.dart';
import 'package:kds_app/features/auth/session_provider.dart';
import 'package:kds_app/features/board_v2/kds_queue_tasks_dialog.dart';
import 'package:kds_app/features/board_v2/kds_v2_board_provider.dart';
import 'package:kds_app/features/diagnostics/kds_inspector_modal.dart';
import 'package:kds_app/core/diagnostics/kds_probe_service.dart';

/// D026 可见烤制岗中文标签；空 = 三岗全选（旧设备兼容）。
const _kGrillTagLabels = <String, String>{
  'meat_grill': '荤烤',
  'veg_grill': '素烤',
  'seafood_special': '海鲜',
};

String _grillTagsLabel(List<String>? tags) {
  final effective =
      (tags ?? const []).where((t) => _kGrillTagLabels.containsKey(t)).toList();
  if (effective.isEmpty) return '三岗全选（荤烤/素烤/海鲜）';
  return effective.map((t) => _kGrillTagLabels[t]).join('、');
}

/// 设备设置页 — 深色工业风，与看板/实时日志页统一。
///
/// 布局：分组卡片（设备 / 显示与操作 / 声音与提示 / 数据与日志 / 关于）。
/// 交互：开关即时生效并记审计日志；可点行带水波纹反馈；
/// 收银端地址点击复制；退出设备二次确认，防止误触退出。
class KdsV2SettingsPage extends ConsumerWidget {
  const KdsV2SettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final prefs = ref.watch(appPrefsProvider);
    final session = ref.watch(sessionProvider);
    final board = ref.watch(kdsV2BoardProvider);
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: const Color(0xFF1E1E1E),
      appBar: AppBar(
        backgroundColor: const Color(0xFF2D2D2D),
        foregroundColor: Colors.white,
        elevation: 0,
        title: const Text('设备设置'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.pop(),
        ),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 680),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(14, 8, 14, 24),
            children: [
              // ── 设备 ──────────────────────────────────────────────
              _SettingsGroup(
                title: '设备',
                children: [
                  _DeviceHero(
                    device: session.device,
                    wsOnline: ref.watch(wsConnectedProvider),
                    channel: session.activeChannel,
                  ),
                  _DividerLine(),
                  _TapRow(
                    icon: Icons.lan_outlined,
                    theme: const Color(0xFF7EC8E3),
                    title: '收银端地址',
                    subtitle: session.apiBase.isEmpty ? '未配置' : session.apiBase,
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.edit_outlined,
                              size: 18, color: Colors.white54),
                          tooltip: '修改局域网地址',
                          onPressed: () =>
                              _editLanAddress(context, ref, session.apiBase),
                        ),
                      ],
                    ),
                    onTap: () async {
                      KdsFileLogger.info('[UI] 设置：复制收银端地址');
                      await Clipboard.setData(
                        ClipboardData(text: session.apiBase),
                      );
                      if (!context.mounted) return;
                      _showToast(context, '已复制收银端地址');
                    },
                  ),
                  _DividerLine(),
                  _TapRow(
                    icon: Icons.cloud_outlined,
                    theme: const Color(0xFF68D391),
                    title: '云端服务地址',
                    subtitle: session.cloudApiBase.isEmpty
                        ? '未配置 (点击配置容灾云端基址)'
                        : session.cloudApiBase,
                    trailing: const Icon(Icons.edit_outlined,
                        size: 18, color: Colors.white54),
                    onTap: () =>
                        _editCloudAddress(context, ref, session.cloudApiBase),
                  ),
                  _DividerLine(),
                  _TapRow(
                    icon: Icons.alt_route,
                    theme: const Color(0xFFFFA94D),
                    title: '连接模式',
                    subtitle:
                        '${session.connectionMode.label} · 当前活跃通道: ${session.activeChannel.label}',
                    trailing: const Icon(Icons.lock_outline,
                        size: 18, color: Colors.white54),
                  ),
                  _DividerLine(),
                  _KvBlock(
                    entries: [
                      (
                        '活跃通道',
                        '${session.activeChannel.label} (基址: ${session.effectiveActiveBase})',
                      ),
                      (
                        '版本',
                        '${board.configVersion ?? board.config['version'] ?? '—'} · 超时按菜品出餐时长判定',
                      ),
                      (
                        '路由',
                        board.config['allowed_queues'] ??
                            session.device?.workflows
                                .map((e) => e.apiValue)
                                .join(', ') ??
                            '—',
                      ),
                      ('可见岗', _grillTagsLabel(session.device?.screenTags)),
                      ('固定目录', '${board.catalog.length} 项'),
                    ],
                  ),
                ],
              ),

              // ── 显示与操作 ────────────────────────────────────────
              _SettingsGroup(
                title: '显示与操作',
                children: [
                  prefs.when(
                    data: (value) => _SwitchRow(
                      key: const ValueKey('fixed-dish-switch'),
                      icon: Icons.view_agenda_outlined,
                      theme: const Color(0xFF0CB960),
                      title: '固定菜品',
                      subtitle: Text(
                        value.fixedDishOrderEnabled
                            ? '按收银端分类和菜品顺序固定位置并合并显示'
                            : '按下单时间先进先出，菜品独立显示',
                      ),
                      value: value.fixedDishOrderEnabled,
                      onChanged: (enabled) async {
                        KdsFileLogger.info(
                            '[UI] 设置：固定菜品 → ${enabled ? '开' : '关'}');
                        await value.setFixedDishOrderEnabled(enabled);
                        ref.invalidate(appPrefsProvider);
                        if (!context.mounted) return;
                        _showToast(context, '固定菜品 → ${enabled ? '开' : '关'}');
                      },
                    ),
                    loading: () => const _LoadingRow(),
                    error: (error, _) => _ErrorRow(error: '$error'),
                  ),
                  _DividerLine(),
                  prefs.when(
                    data: (value) => _SwitchRow(
                      key: const ValueKey('merge-same-dish-name-switch'),
                      icon: Icons.merge_type,
                      theme: const Color(0xFF0CB960),
                      title: '非固定模式同名合并',
                      subtitle: Text(
                        value.mergeSameDishNameEnabled
                            ? '同名菜品忽略规格合并显示，仍按履约渠道分开'
                            : '每条菜品明细独立显示，规格不参与合并',
                      ),
                      value: value.mergeSameDishNameEnabled,
                      onChanged: (enabled) async {
                        KdsFileLogger.info(
                            '[UI] 设置：非固定模式同名合并 → ${enabled ? '开' : '关'}');
                        await value.setMergeSameDishNameEnabled(enabled);
                        ref.invalidate(appPrefsProvider);
                        if (!context.mounted) return;
                        _showToast(
                            context, '非固定模式同名合并 → ${enabled ? '开' : '关'}');
                      },
                    ),
                    loading: () => const _LoadingRow(),
                    error: (error, _) => _ErrorRow(error: '$error'),
                  ),
                  _DividerLine(),
                  prefs.when(
                    data: (value) => _SwitchRow(
                      key: const ValueKey('advance-quantity-dialog-switch'),
                      icon: Icons.dialpad,
                      theme: const Color(0xFF0CB960),
                      title: '划菜数量弹窗',
                      subtitle: const Text('打开后单击卡片先选择划出数量；关闭后单击整卡划出，长按才选数量'),
                      value: value.advanceQuantityDialogEnabled,
                      onChanged: (enabled) async {
                        KdsFileLogger.info(
                            '[UI] 设置：划菜数量弹窗 → ${enabled ? '开' : '关'}');
                        await value.setAdvanceQuantityDialogEnabled(enabled);
                        ref.invalidate(appPrefsProvider);
                        if (!context.mounted) return;
                        _showToast(context, '划菜数量弹窗 → ${enabled ? '开' : '关'}');
                      },
                    ),
                    loading: () => const _LoadingRow(),
                    error: (error, _) => _ErrorRow(error: '$error'),
                  ),
                  _DividerLine(),
                  prefs.when(
                    data: (value) {
                      final prepVal = board.config['enable_prep_workflow'] ??
                          board.config['prep_enabled'] ??
                          value.prepFlowEnabled;
                      final currentEnabled = prepVal is bool
                          ? prepVal
                          : (prepVal is num ? prepVal != 0 : '$prepVal' == '1');
                      return _SwitchRow(
                        key: const ValueKey('prep-flow-switch'),
                        icon: Icons.dining_outlined,
                        theme: const Color(0xFF0CB960),
                        title: '配菜流程',
                        subtitle: Text(
                          currentEnabled
                              ? '新订单先进入待配菜（局域网实时同步）'
                              : '已关闭，待制作看板自动合并待配菜（局域网实时同步）',
                        ),
                        value: currentEnabled,
                        onChanged: (enabled) async {
                          try {
                            await ref
                                .read(kdsV2BoardProvider.notifier)
                                .setPrepFlowEnabled(enabled);
                            ref.invalidate(appPrefsProvider);
                            if (!context.mounted) return;
                            _showToast(
                                context, '配菜流程 → ${enabled ? '开' : '关'}');
                          } catch (error) {
                            if (!context.mounted) return;
                            _showToast(context, '同步待配菜流程失败：$error');
                          }
                        },
                      );
                    },
                    loading: () => const _LoadingRow(),
                    error: (error, _) => _ErrorRow(error: '$error'),
                  ),
                ],
              ),

              // ── 声音与提示 ────────────────────────────────────────
              _SettingsGroup(
                title: '声音与提示',
                children: [
                  prefs.when(
                    data: (value) => _SwitchRow(
                      icon: Icons.notifications_active_outlined,
                      theme: const Color(0xFFFFB300),
                      title: '新单提示音',
                      subtitle: const Text('仅保存在当前设备，不保存订单业务数据'),
                      value: value.newOrderSoundEnabled,
                      onChanged: (enabled) async {
                        KdsFileLogger.info(
                            '[UI] 设置：新单提示音 → ${enabled ? '开' : '关'}');
                        await value.setNewOrderSoundEnabled(enabled);
                        ref.invalidate(appPrefsProvider);
                        if (!context.mounted) return;
                        _showToast(context, '新单提示音 → ${enabled ? '开' : '关'}');
                      },
                    ),
                    loading: () => const _LoadingRow(),
                    error: (error, _) => _ErrorRow(error: '$error'),
                  ),
                ],
              ),

              // ── 数据与日志 ────────────────────────────────────────
              _SettingsGroup(
                title: '数据与日志',
                children: [
                  _TapRow(
                    key: const ValueKey('settings-queue-tasks'),
                    icon: Icons.pending_actions_outlined,
                    theme: const Color(0xFFFFB300),
                    title: '队列任务',
                    subtitle: board.pendingSyncCount > 0
                        ? '${board.pendingSyncCount} 项待处理，打开查看同步状态'
                        : '查看待同步、重试中和需要裁决的任务',
                    trailing: board.pendingSyncCount > 0
                        ? Text(
                            board.pendingSyncCount > 99
                                ? '99+'
                                : '${board.pendingSyncCount}',
                            style: const TextStyle(
                              color: Color(0xFFFFB300),
                              fontWeight: FontWeight.w800,
                            ),
                          )
                        : null,
                    onTap: () {
                      KdsFileLogger.info('[PAGE] 打开设置页 → 队列任务');
                      showDialog<void>(
                        context: context,
                        builder: (_) => Consumer(
                          builder: (context, dialogRef, __) {
                            final current = dialogRef.watch(kdsV2BoardProvider);
                            return KdsQueueTasksDialog(
                              tasks: current.overlays,
                              pendingCount: current.pendingSyncCount,
                            );
                          },
                        ),
                      );
                    },
                  ),
                  _DividerLine(),
                  _TapRow(
                    icon: Icons.radar_rounded,
                    theme: const Color(0xFF00D2FC),
                    title: '全链路探测中心',
                    subtitle: '流转图谱、收银端双向流水比对、网络节点一键探针测速',
                    onTap: () {
                      KdsFileLogger.info('[PAGE] 打开设置页 → 全链路探测窗口');
                      showKdsInspectorModal(context);
                    },
                  ),
                  _DividerLine(),
                  _TapRow(
                    icon: Icons.terminal,
                    theme: const Color(0xFF7C3AED),
                    title: '查看日志',
                    subtitle: '实时日志：操作记录、WS 连接、告警与错误（文件日志保留 7 天）',
                    onTap: () {
                      KdsFileLogger.info('[PAGE] 打开设置页 → 查看日志');
                      context.push('/logs');
                    },
                  ),
                  _DividerLine(),
                  _TapRow(
                    icon: Icons.cleaning_services_outlined,
                    theme: const Color(0xFFFFA726),
                    title: '清除本地缓存并重置',
                    subtitle: '清理旧登录凭据、离线看板快照、待同步队列与设备指纹缓存',
                    onTap: () async {
                      final confirmed = await _confirmClearCache(context);
                      if (!confirmed) return;
                      KdsFileLogger.info('[AUTH] 设置页清除所有本地缓存');
                      await ref.read(sessionProvider.notifier).clearAllCache();
                      if (context.mounted) context.go('/login');
                    },
                  ),
                ],
              ),

              // ── 关于 ──────────────────────────────────────────────
              _SettingsGroup(
                title: '关于',
                children: [
                  const _TapRow(
                    icon: Icons.info_outline,
                    theme: Color(0xFFDBDBDB),
                    title: '版本号',
                    trailing: Text(
                      KdsAppConfig.appVersion,
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 15,
                        color: Colors.white,
                        letterSpacing: 0.3,
                      ),
                    ),
                  ),
                  _DividerLine(),
                  _TapRow(
                    icon: Icons.logout,
                    theme: scheme.error,
                    title: '退出设备',
                    titleColor: scheme.error,
                    subtitle: '退出后需要重新登录才能查看订单看板',
                    onTap: () async {
                      final confirmed = await _confirmLogout(context);
                      if (!confirmed) return;
                      KdsFileLogger.info('[AUTH] 设置页退出设备');
                      await ref.read(sessionProvider.notifier).logout();
                      if (context.mounted) context.go('/login');
                    },
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 底部居中 toast — 复制/开关等操作的统一轻量反馈。
  void _showToast(BuildContext context, String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          behavior: SnackBarBehavior.floating,
          margin: const EdgeInsets.fromLTRB(180, 0, 180, 24),
          duration: const Duration(milliseconds: 1400),
          backgroundColor: const Color(0xE6000000),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
        ),
      );
  }

  /// 退出二次确认 — 防止误触退出导致后厨断线重登。
  Future<bool> _confirmLogout(BuildContext context) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF2D2D2D),
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        title: const Text(
          '退出设备',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
        ),
        content: const Text(
          '退出后需要重新登录才能查看订单看板，确定要退出吗？',
          style: TextStyle(color: Colors.white70, height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('退出'),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  /// 清除缓存二次确认
  Future<bool> _confirmClearCache(BuildContext context) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF2D2D2D),
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        title: const Text(
          '清除本地缓存并重置',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
        ),
        content: const Text(
          '此操作将彻底清除本机保存的所有旧登录凭据、离线看板快照、待同步队列和硬件指纹缓存，并将设备重置为全新状态。\n\n确定要清除吗？',
          style: TextStyle(color: Colors.white70, height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('确认清除'),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  void _editLanAddress(BuildContext context, WidgetRef ref, String current) {
    final controller = TextEditingController(text: current);
    bool isTesting = false;
    String? testResult;
    bool? isSuccess;

    showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (dialogCtx, setModalState) => AlertDialog(
          backgroundColor: const Color(0xFF2D2D2D),
          title:
              const Text('修改收银端局域网地址', style: TextStyle(color: Colors.white)),
          content: SizedBox(
            width: 440,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextField(
                  controller: controller,
                  style: const TextStyle(color: Colors.white),
                  decoration: const InputDecoration(
                    hintText: KdsAppConfig.lanApiBaseExample,
                    hintStyle: TextStyle(color: Colors.white38),
                    helperText:
                        '可选局域网代理 (如: https://192.168.1.100:17026，清空则仅直连云端)',
                    helperStyle: TextStyle(color: Colors.white54),
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    OutlinedButton.icon(
                      icon: isTesting
                          ? const SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Color(0xFF7EC8E3),
                              ),
                            )
                          : const Icon(Icons.network_check,
                              size: 16, color: Color(0xFF7EC8E3)),
                      label: Text(
                        isTesting ? '正在探测…' : '测试地址可用性',
                        style: const TextStyle(
                            color: Color(0xFF7EC8E3), fontSize: 13),
                      ),
                      onPressed: isTesting
                          ? null
                          : () async {
                              final text = controller.text.trim();
                              if (text.isEmpty) {
                                setModalState(() {
                                  testResult = '请先输入局域网地址后再测试';
                                  isSuccess = false;
                                });
                                return;
                              }
                              if (!isValidApiBase(text)) {
                                setModalState(() {
                                  testResult =
                                      '地址格式无效，示例：https://192.168.1.100:17026';
                                  isSuccess = false;
                                });
                                return;
                              }
                              setModalState(() {
                                isTesting = true;
                                testResult = null;
                                isSuccess = null;
                              });
                              final token = ref.read(sessionProvider).token;
                              final result = await KdsProbeService.probeLanBase(
                                text,
                                token: token ?? '',
                              );
                              setModalState(() {
                                isTesting = false;
                                isSuccess = result.isSuccess;
                                testResult = result.isSuccess
                                    ? '🟢 连通正常 (${result.durationMs}ms) · ${result.message}'
                                    : '🔴 连通异常 (${result.durationMs}ms) · ${result.message}';
                              });
                            },
                    ),
                  ],
                ),
                if (testResult != null) ...[
                  const SizedBox(height: 10),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    decoration: BoxDecoration(
                      color: (isSuccess ?? false)
                          ? const Color(0xFF065F46).withValues(alpha: 0.25)
                          : const Color(0xFF7F1D1D).withValues(alpha: 0.25),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(
                        color: (isSuccess ?? false)
                            ? const Color(0xFF10B981).withValues(alpha: 0.4)
                            : const Color(0xFFEF4444).withValues(alpha: 0.4),
                      ),
                    ),
                    child: Text(
                      testResult!,
                      style: TextStyle(
                        fontSize: 12,
                        color: (isSuccess ?? false)
                            ? const Color(0xFF6EE7B7)
                            : const Color(0xFFFCA5A5),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () async {
                final text = controller.text.trim();
                if (text.isNotEmpty && !isValidApiBase(text)) {
                  _showToast(context, '地址格式无效');
                  return;
                }
                if (text.isNotEmpty && !isPrivateLanApiBase(text)) {
                  _showToast(context, '仅允许配置私有局域网地址');
                  return;
                }
                if (kReleaseMode &&
                    text.isNotEmpty &&
                    !isSecurePrivateLanApiBase(text)) {
                  _showToast(context, '正式版收银端地址必须使用 HTTPS');
                  return;
                }
                Navigator.pop(ctx);
                await ref.read(sessionProvider.notifier).updateApiBase(text);
                if (context.mounted) {
                  _showToast(
                    context,
                    text.isEmpty ? '局域网地址已清空（仅使用云端直连）' : '局域网地址已更新',
                  );
                }
              },
              child: const Text('保存'),
            ),
          ],
        ),
      ),
    );
  }

  void _editCloudAddress(BuildContext context, WidgetRef ref, String current) {
    final controller = TextEditingController(text: current);
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF2D2D2D),
        title: const Text('修改云端服务地址', style: TextStyle(color: Colors.white)),
        content: TextField(
          controller: controller,
          style: const TextStyle(color: Colors.white),
          decoration: const InputDecoration(
            hintText: KdsAppConfig.cloudApiBaseExample,
            hintStyle: TextStyle(color: Colors.white38),
            helperText: '云端权威服务地址，系统默认主通道 (例如: https://api.yourdomain.com)',
            helperStyle: TextStyle(color: Colors.white54),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () async {
              final text = controller.text.trim();
              if (text.isNotEmpty && !isValidApiBase(text)) {
                _showToast(context, '云端地址格式无效');
                return;
              }
              Navigator.pop(ctx);
              await ref.read(sessionProvider.notifier).updateCloudApiBase(text);
              if (context.mounted) _showToast(context, '云端地址已更新');
            },
            child: const Text('保存'),
          ),
        ],
      ),
    );
  }
}

// ── 布局组件 ─────────────────────────────────────────────────────────

/// 设备概览卡：设备名 + 门店/屏幕/流程 + 连接状态灯与当前通道。
class _DeviceHero extends StatelessWidget {
  const _DeviceHero({
    required this.device,
    required this.wsOnline,
    this.channel = KdsActiveChannel.lan,
  });

  final KdsDevice? device;
  final bool wsOnline;
  final KdsActiveChannel channel;

  @override
  Widget build(BuildContext context) {
    final name = (device?.deviceName?.trim().isNotEmpty ?? false)
        ? device!.deviceName!
        : '后厨设备 #${device?.id ?? '—'}';
    final screenLabel = device?.screenTag.label ?? '—';
    final flows = device?.workflows.map((w) => w.label).join(' / ');
    final meta = '门店 #${device?.shopId ?? '—'} · 屏幕 $screenLabel'
        '${(flows == null || flows.isEmpty) ? '' : ' · 流程 $flows'}';
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: const Color(0xFF7EC8E3).withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(
              Icons.tablet_android,
              size: 22,
              color: Color(0xFF7EC8E3),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                    height: 1.2,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  meta,
                  style: const TextStyle(
                    fontSize: 12,
                    color: Colors.white54,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          _WsStatusPill(online: wsOnline, channel: channel),
        ],
      ),
    );
  }
}

/// 连接状态灯：在线绿 / 离线灰，并标记当前通道（收银端/云端）。
class _WsStatusPill extends StatelessWidget {
  const _WsStatusPill({
    required this.online,
    this.channel = KdsActiveChannel.lan,
  });

  final bool online;
  final KdsActiveChannel channel;

  @override
  Widget build(BuildContext context) {
    final color = online ? KdsColors.wsOnline : KdsColors.wsOffline;
    final channelPrefix = channel == KdsActiveChannel.cloud ? '云端' : '收银端';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: online
            ? color.withValues(alpha: 0.14)
            : Colors.white.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
              boxShadow: online
                  ? [
                      BoxShadow(
                        color: color.withValues(alpha: 0.8),
                        blurRadius: 6,
                      ),
                    ]
                  : null,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            online ? '$channelPrefix在线' : '$channelPrefix离线',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

/// 键值区：只读配置按 key/value 拆行展示，替代大段副标题。
class _KvBlock extends StatelessWidget {
  const _KvBlock({required this.entries});

  final List<(String, String)> entries;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (var i = 0; i < entries.length; i++) ...[
          if (i > 0)
            const Divider(
              height: 1,
              indent: 66,
              endIndent: 0,
              color: Color(0x14FFFFFF),
            ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 92,
                  child: Text(
                    entries[i].$1,
                    style: const TextStyle(
                      fontSize: 12,
                      color: Colors.white38,
                      height: 1.5,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    entries[i].$2,
                    style: const TextStyle(
                      fontSize: 13,
                      color: Colors.white54,
                      height: 1.5,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

/// 分组卡片容器：深色底 + 细边框 + 圆角，子行用分隔线隔开。
class _SettingsGroup extends StatelessWidget {
  const _SettingsGroup({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(6, 0, 6, 8),
            child: Text(
              title.toUpperCase(),
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: Colors.white38,
                letterSpacing: 1.5,
              ),
            ),
          ),
          Container(
            decoration: BoxDecoration(
              color: const Color(0xFF242424),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.white.withValues(alpha: 0.07)),
            ),
            clipBehavior: Clip.antiAlias,
            child: Column(children: children),
          ),
        ],
      ),
    );
  }
}

/// 行间分隔线：左侧对齐图标，弱化但保留视觉分组。
class _DividerLine extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return const Divider(
      height: 1,
      indent: 66,
      endIndent: 0,
      color: Color(0x14FFFFFF),
    );
  }
}

/// 可点击行：图标 + 标题/副标题 + 尾随控件，带水波纹按压反馈。
class _TapRow extends StatelessWidget {
  const _TapRow({
    super.key,
    required this.icon,
    required this.theme,
    required this.title,
    this.subtitle,
    this.trailing,
    this.onTap,
    this.titleColor,
  });

  final IconData icon;
  final Color theme;
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;
  final Color? titleColor;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              _RowIcon(icon: icon, theme: theme),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: titleColor ?? Colors.white,
                        height: 1.2,
                      ),
                    ),
                    if (subtitle != null) ...[
                      const SizedBox(height: 3),
                      Text(
                        subtitle!,
                        style: const TextStyle(
                          fontSize: 12,
                          color: Colors.white54,
                          height: 1.4,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (trailing != null) ...[
                const SizedBox(width: 12),
                trailing!,
              ] else if (onTap != null) ...[
                const SizedBox(width: 12),
                const Icon(
                  Icons.chevron_right,
                  size: 20,
                  color: Colors.white30,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// 开关行：Switch 即时生效，激活色与看板在线绿一致。
class _SwitchRow extends StatelessWidget {
  const _SwitchRow({
    super.key,
    required this.icon,
    required this.theme,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  final IconData icon;
  final Color theme;
  final String title;
  final Widget subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Row(
          children: [
            _RowIcon(icon: icon, theme: theme),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                      height: 1.2,
                    ),
                  ),
                  const SizedBox(height: 3),
                  DefaultTextStyle(
                    style: const TextStyle(
                      fontSize: 12,
                      color: Colors.white54,
                      height: 1.4,
                    ),
                    child: subtitle,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Switch(
              value: value,
              onChanged: onChanged,
              activeTrackColor: KdsColors.wsOnline,
              activeThumbColor: Colors.white,
              inactiveTrackColor: const Color(0xFF3A3A3A),
              inactiveThumbColor: const Color(0xFF9E9E9E),
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
          ],
        ),
      ),
    );
  }
}

/// 图标底托：主题色 15% 透明圆角方块。
class _RowIcon extends StatelessWidget {
  const _RowIcon({required this.icon, required this.theme});

  final IconData icon;
  final Color theme;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 38,
      height: 38,
      decoration: BoxDecoration(
        color: theme.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(9),
      ),
      child: Icon(icon, size: 20, color: theme),
    );
  }
}

class _LoadingRow extends StatelessWidget {
  const _LoadingRow();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(horizontal: 16, vertical: 18),
      child: LinearProgressIndicator(minHeight: 2),
    );
  }
}

class _ErrorRow extends StatelessWidget {
  const _ErrorRow({required this.error});

  final String error;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Text(
        '设置读取失败：$error',
        style: const TextStyle(fontSize: 12, color: Color(0xFFFF6B6B)),
      ),
    );
  }
}
