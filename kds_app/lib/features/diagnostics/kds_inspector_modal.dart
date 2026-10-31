import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:kds_app/core/config/kds_connection_mode.dart';
import 'package:kds_app/core/diagnostics/kds_probe_service.dart';
import 'package:kds_app/core/diagnostics/kds_trace_hub.dart';
import 'package:kds_app/core/diagnostics/kds_trace_models.dart';
import 'package:kds_app/core/lan_v2/kds_v2_reducer.dart';
import 'package:kds_app/core/ws/kds_ws_connect_common.dart';
import 'package:kds_app/features/auth/session_provider.dart';
import 'package:kds_app/features/board_v2/kds_v2_board_provider.dart';

/// 调出全链路探测窗口对话框的静态方法
Future<void> showKdsInspectorModal(BuildContext context) {
  return showDialog<void>(
    context: context,
    barrierDismissible: true,
    builder: (ctx) => const Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: EdgeInsets.symmetric(horizontal: 24, vertical: 20),
      child: KdsInspectorWindow(),
    ),
  );
}

/// 格式化 URL 为简要主机名 (host[:port])
String _formatHost(String url) {
  final trimmed = url.trim();
  if (trimmed.isEmpty) return '未配置';
  final withScheme = trimmed.startsWith('http://') ||
          trimmed.startsWith('https://') ||
          trimmed.startsWith('ws://') ||
          trimmed.startsWith('wss://')
      ? trimmed
      : 'http://$trimmed';
  final uri = Uri.tryParse(withScheme);
  if (uri == null || uri.host.isEmpty) return trimmed;
  if (uri.hasPort && uri.port != 80 && uri.port != 443) {
    return '${uri.host}:${uri.port}';
  }
  return uri.host;
}

/// 全链路探测与诊断控制台窗口
class KdsInspectorWindow extends ConsumerStatefulWidget {
  const KdsInspectorWindow({super.key});

  @override
  ConsumerState<KdsInspectorWindow> createState() => _KdsInspectorWindowState();
}

class _KdsInspectorWindowState extends ConsumerState<KdsInspectorWindow>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  StreamSubscription<KdsTraceEntry>? _traceSub;

  // Tab 1: KDS 本地流转
  KdsTraceStage? _selectedStage;
  bool _onlyErrors = false;
  final _searchCtrl = TextEditingController();
  final Set<String> _expandedEntryIds = {};

  // Tab 2: 收银端日志
  bool _loadingCashierLogs = false;
  String? _cashierLogsError;
  List<Map<String, dynamic>> _cashierLogs = const [];
  final Set<int> _expandedCashierLogIds = {};

  // Tab 3: 探针测速
  bool _probing = false;
  KdsProbeReport? _probeReport;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _traceSub = KdsTraceHub.stream.listen((_) {
      if (mounted) setState(() {});
    });
    // 自动加载一次收银端日志与探针
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _fetchCashierLogs();
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    _traceSub?.cancel();
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _fetchCashierLogs() async {
    final session = ref.read(sessionProvider);
    final lanBase = session.apiBase.trim();
    final token = session.token ?? '';
    if (lanBase.isEmpty || token.isEmpty) {
      setState(() {
        _cashierLogsError = '局域网收银端地址或 Token 为空，无法拉取收银端日志';
      });
      return;
    }

    setState(() {
      _loadingCashierLogs = true;
      _cashierLogsError = null;
    });

    try {
      final dio = Dio(BaseOptions(connectTimeout: const Duration(seconds: 4)));
      final res = await dio.get<Map<String, dynamic>>(
        '$lanBase/kds/v2/diagnostics/interaction-logs?limit=50',
        options: Options(headers: {kKdsDeviceTokenHeader: token}),
      );
      final data = res.data?['data'] as Map<String, dynamic>?;
      final rawList = data?['logs'] as List? ?? [];
      final logs =
          rawList.map((e) => (e as Map).cast<String, dynamic>()).toList();
      if (mounted) {
        setState(() {
          _cashierLogs = logs;
          _loadingCashierLogs = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _cashierLogsError = '拉取收银端交互日志失败: $e';
          _loadingCashierLogs = false;
        });
      }
    }
  }

  Future<void> _runProbes() async {
    if (_probing) return;
    setState(() => _probing = true);
    final session = ref.read(sessionProvider);
    try {
      final report = await KdsProbeService.runFullProbe(
        lanBase: session.apiBase,
        cloudBase: session.cloudApiBase,
        token: session.token ?? '',
        shopId: session.device?.shopId ?? 1,
      );
      if (mounted) {
        setState(() {
          _probeReport = report;
          _probing = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _probing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(sessionProvider);
    final board = ref.watch(kdsV2BoardProvider);
    final isWsOnline = board.connected;

    return Container(
      width: 1100,
      height: 750,
      decoration: BoxDecoration(
        color: const Color(0xFF141414),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white12, width: 1.2),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.8),
            blurRadius: 30,
            spreadRadius: 8,
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Scaffold(
          backgroundColor: Colors.transparent,
          body: Column(
            children: [
              // ── 顶部高科技态势 Bar ──────────────────────────────
              _buildTopBar(session, board, isWsOnline),
              // ── Tab 切换与操作栏 ─────────────────────────────────
              _buildTabBarRow(),
              // ── Tab 内容区 ──────────────────────────────────────
              Expanded(
                child: TabBarView(
                  controller: _tabController,
                  children: [
                    _buildKdsTimelineTab(session),
                    _buildCashierAuditTab(),
                    _buildProbesTab(session),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTopBar(SessionState session, KdsV2State board, bool isWsOnline) {
    final isLan = session.activeChannel == KdsActiveChannel.lan;
    final lanHost = _formatHost(session.apiBase);
    final cloudHost = _formatHost(session.cloudApiBase);
    final activeHost = isLan ? lanHost : cloudHost;
    final channelModeText = isLan ? '局域网传输' : '云端传输';
    final channelColor =
        isLan ? const Color(0xFF00D2FC) : const Color(0xFF00E676);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      decoration: const BoxDecoration(
        color: Color(0xFF1F1F1F),
        border: Border(bottom: BorderSide(color: Colors.white10)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: const Color(0xFF00D2FC).withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(
              Icons.radar_rounded,
              color: Color(0xFF00D2FC),
              size: 24,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '餐饮门店 KDS & 收银端 全链路探测中心',
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                    letterSpacing: 0.5,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  '设备: ${session.device?.deviceCode ?? "未登录"} · 门店: ${session.device?.shopId ?? "—"} · 当前传输: $channelModeText [$activeHost]',
                  style: const TextStyle(fontSize: 12, color: Colors.white70),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          // 状态徽章：当前传输主机（醒目标注是局域网传输还是云端传输）
          _Badge(
            label: '$channelModeText: $activeHost',
            color: channelColor,
            icon: isLan ? Icons.lan_outlined : Icons.cloud_outlined,
          ),
          const SizedBox(width: 8),
          // 状态徽章：WebSocket
          _Badge(
            label: isWsOnline ? 'WS 在线' : 'WS 离线',
            color:
                isWsOnline ? const Color(0xFF00E676) : const Color(0xFFFF5252),
            icon: isWsOnline ? Icons.link : Icons.link_off,
          ),
          const SizedBox(width: 8),
          // 状态徽章：最新 Event Seq
          _Badge(
            label: 'Seq: ${board.eventSeq}',
            color: const Color(0xFFFFA726),
            icon: Icons.tag,
          ),
          const SizedBox(width: 8),
          // 状态徽章：未发运待确认
          _Badge(
            label: '待送达: ${board.pendingSyncCount}',
            color: board.pendingSyncCount > 0
                ? const Color(0xFFFF5252)
                : const Color(0xFF9E9E9E),
            icon: Icons.outbox_rounded,
          ),
          const SizedBox(width: 12),
          IconButton(
            icon: const Icon(Icons.close, color: Colors.white70),
            tooltip: '关闭探测窗口',
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      ),
    );
  }

  Widget _buildTabBarRow() {
    return Container(
      color: const Color(0xFF181818),
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            TabBar(
              controller: _tabController,
              isScrollable: true,
              tabAlignment: TabAlignment.start,
              indicatorColor: const Color(0xFF00D2FC),
              indicatorWeight: 3,
              labelColor: const Color(0xFF00D2FC),
              unselectedLabelColor: Colors.white60,
              labelStyle:
                  const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
              tabs: const [
                Tab(
                  icon: Icon(Icons.timeline_rounded, size: 18),
                  text: 'KDS 本地流转图谱',
                ),
                Tab(
                  icon: Icon(Icons.compare_arrows_rounded, size: 18),
                  text: '收银端双向流水对照',
                ),
                Tab(
                  icon: Icon(Icons.speed_rounded, size: 18),
                  text: '全链路探针测速',
                ),
              ],
            ),
            const SizedBox(width: 24),
            TextButton.icon(
              style: TextButton.styleFrom(foregroundColor: Colors.white60),
              icon: const Icon(Icons.delete_sweep_outlined, size: 18),
              label: const Text('清空追踪'),
              onPressed: () {
                KdsTraceHub.clear();
                setState(() {});
              },
            ),
            const SizedBox(width: 6),
            TextButton.icon(
              style: TextButton.styleFrom(foregroundColor: Colors.white60),
              icon: const Icon(Icons.copy_all_outlined, size: 18),
              label: const Text('导出完整链路 JSON'),
              onPressed: _exportAllJson,
            ),
          ],
        ),
      ),
    );
  }

  void _exportAllJson() {
    final list = KdsTraceHub.entries.map((e) => e.toJson()).toList();
    final jsonText = const JsonEncoder.withIndent('  ').convert(list);
    Clipboard.setData(ClipboardData(text: jsonText));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('已复制全链路诊断跟踪 JSON 到剪贴板'),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  // ── Tab 1: KDS 本地流转图谱 ───────────────────────────────────────
  Widget _buildKdsTimelineTab(SessionState session) {
    final lanHost = _formatHost(session.apiBase);
    final cloudHost = _formatHost(session.cloudApiBase);

    final entries = KdsTraceHub.entries.reversed.where((entry) {
      if (_selectedStage != null && entry.stage != _selectedStage) return false;
      if (_onlyErrors && entry.isSuccess) return false;
      final keyword = _searchCtrl.text.trim().toLowerCase();
      if (keyword.isNotEmpty) {
        final match = entry.action.toLowerCase().contains(keyword) ||
            entry.summary.toLowerCase().contains(keyword) ||
            (entry.endpoint?.toLowerCase().contains(keyword) ?? false);
        if (!match) return false;
      }
      return true;
    }).toList();

    return Column(
      children: [
        // 传输模式与主机状态横幅
        _buildTransmissionHostBanner(session),
        // 过滤器条
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          color: const Color(0xFF1C1C1C),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _FilterChip(
                  label: '全部 (${KdsTraceHub.count})',
                  selected: _selectedStage == null && !_onlyErrors,
                  onSelected: () => setState(() {
                    _selectedStage = null;
                    _onlyErrors = false;
                  }),
                ),
                const SizedBox(width: 6),
                _FilterChip(
                  label: '获取 Fetch',
                  color: const Color(0xFF2196F3),
                  selected: _selectedStage == KdsTraceStage.fetch,
                  onSelected: () => setState(() {
                    _selectedStage = KdsTraceStage.fetch;
                    _onlyErrors = false;
                  }),
                ),
                const SizedBox(width: 6),
                _FilterChip(
                  label: '发送 Send',
                  color: const Color(0xFFFF9800),
                  selected: _selectedStage == KdsTraceStage.send,
                  onSelected: () => setState(() {
                    _selectedStage = KdsTraceStage.send;
                    _onlyErrors = false;
                  }),
                ),
                const SizedBox(width: 6),
                _FilterChip(
                  label: '接收 Receive',
                  color: const Color(0xFF4CAF50),
                  selected: _selectedStage == KdsTraceStage.receive,
                  onSelected: () => setState(() {
                    _selectedStage = KdsTraceStage.receive;
                    _onlyErrors = false;
                  }),
                ),
                const SizedBox(width: 6),
                _FilterChip(
                  label: '响应 Response',
                  color: const Color(0xFF9C27B0),
                  selected: _selectedStage == KdsTraceStage.response,
                  onSelected: () => setState(() {
                    _selectedStage = KdsTraceStage.response;
                    _onlyErrors = false;
                  }),
                ),
                const SizedBox(width: 6),
                _FilterChip(
                  label: '仅异常 Error',
                  color: const Color(0xFFFF5252),
                  selected: _onlyErrors,
                  onSelected: () => setState(() {
                    _onlyErrors = true;
                    _selectedStage = null;
                  }),
                ),
                const SizedBox(width: 16),
                SizedBox(
                  width: 220,
                  height: 36,
                  child: TextField(
                    controller: _searchCtrl,
                    style: const TextStyle(fontSize: 13, color: Colors.white),
                    onChanged: (_) => setState(() {}),
                    decoration: InputDecoration(
                      hintText: '搜索指令/单号/路径...',
                      hintStyle:
                          const TextStyle(color: Colors.white38, fontSize: 12),
                      prefixIcon: const Icon(Icons.search,
                          size: 16, color: Colors.white38),
                      filled: true,
                      fillColor: Colors.white10,
                      contentPadding: EdgeInsets.zero,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        // 列表内容
        Expanded(
          child: entries.isEmpty
              ? const Center(
                  child: Text(
                    '暂无符合条件的链路数据',
                    style: TextStyle(color: Colors.white38),
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: entries.length,
                  itemBuilder: (ctx, i) {
                    final entry = entries[i];
                    final isExpanded = _expandedEntryIds.contains(entry.id);
                    return _TraceEntryCard(
                      entry: entry,
                      isExpanded: isExpanded,
                      lanHost: lanHost,
                      cloudHost: cloudHost,
                      onToggle: () {
                        setState(() {
                          if (isExpanded) {
                            _expandedEntryIds.remove(entry.id);
                          } else {
                            _expandedEntryIds.add(entry.id);
                          }
                        });
                      },
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildTransmissionHostBanner(SessionState session) {
    final isLan = session.activeChannel == KdsActiveChannel.lan;
    final lanHost = _formatHost(session.apiBase);
    final cloudHost = _formatHost(session.cloudApiBase);

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFF1F262D),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: isLan
              ? const Color(0xFF00D2FC).withValues(alpha: 0.35)
              : const Color(0xFF00E676).withValues(alpha: 0.35),
        ),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: (isLan ? const Color(0xFF00D2FC) : const Color(0xFF00E676))
                  .withValues(alpha: 0.18),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(
                color: (isLan
                        ? const Color(0xFF00D2FC)
                        : const Color(0xFF00E676))
                    .withValues(alpha: 0.5),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  isLan ? Icons.lan_outlined : Icons.cloud_done_outlined,
                  color:
                      isLan ? const Color(0xFF00D2FC) : const Color(0xFF00E676),
                  size: 16,
                ),
                const SizedBox(width: 6),
                Text(
                  isLan ? '局域网传输 (LAN)' : '云端直连传输 (Cloud)',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: isLan
                        ? const Color(0xFF00D2FC)
                        : const Color(0xFF00E676),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 14),
          // 局域网主机卡片
          Expanded(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: isLan
                    ? const Color(0xFF00D2FC).withValues(alpha: 0.1)
                    : Colors.white.withValues(alpha: 0.04),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(
                  color: isLan
                      ? const Color(0xFF00D2FC).withValues(alpha: 0.4)
                      : Colors.white12,
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.router_outlined,
                    size: 14,
                    color: isLan ? const Color(0xFF00D2FC) : Colors.white54,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    '局域网收银: ',
                    style: TextStyle(
                      fontSize: 12,
                      color: isLan ? Colors.white : Colors.white60,
                      fontWeight: isLan ? FontWeight.bold : FontWeight.normal,
                    ),
                  ),
                  Flexible(
                    child: Text(
                      lanHost,
                      style: TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 12,
                        color: isLan ? const Color(0xFF00D2FC) : Colors.white70,
                        fontWeight: isLan ? FontWeight.bold : FontWeight.normal,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (isLan) ...[
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 4, vertical: 1),
                      decoration: BoxDecoration(
                        color: const Color(0xFF00D2FC),
                        borderRadius: BorderRadius.circular(3),
                      ),
                      child: const Text(
                        '活动',
                        style: TextStyle(
                          fontSize: 9,
                          color: Colors.black,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(width: 10),
          // 云端主机卡片
          Expanded(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: !isLan
                    ? const Color(0xFF00E676).withValues(alpha: 0.1)
                    : Colors.white.withValues(alpha: 0.04),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(
                  color: !isLan
                      ? const Color(0xFF00E676).withValues(alpha: 0.4)
                      : Colors.white12,
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.cloud_queue_rounded,
                    size: 14,
                    color: !isLan ? const Color(0xFF00E676) : Colors.white54,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    '云端服务: ',
                    style: TextStyle(
                      fontSize: 12,
                      color: !isLan ? Colors.white : Colors.white60,
                      fontWeight: !isLan ? FontWeight.bold : FontWeight.normal,
                    ),
                  ),
                  Flexible(
                    child: Text(
                      cloudHost,
                      style: TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 12,
                        color: !isLan ? const Color(0xFF00E676) : Colors.white70,
                        fontWeight: !isLan ? FontWeight.bold : FontWeight.normal,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (!isLan) ...[
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 4, vertical: 1),
                      decoration: BoxDecoration(
                        color: const Color(0xFF00E676),
                        borderRadius: BorderRadius.circular(3),
                      ),
                      child: const Text(
                        '活动',
                        style: TextStyle(
                          fontSize: 9,
                          color: Colors.black,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Tab 2: 收银端双向对照 ─────────────────────────────────────────
  Widget _buildCashierAuditTab() {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          color: const Color(0xFF1C1C1C),
          child: Row(
            children: [
              const Icon(Icons.sync_alt, size: 18, color: Color(0xFF00D2FC)),
              const SizedBox(width: 8),
              const Text(
                '已对接收银机 SQLite 本地审计流水',
                style: TextStyle(color: Colors.white70, fontSize: 13),
              ),
              const Spacer(),
              FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF00D2FC).withValues(alpha: 0.2),
                  foregroundColor: const Color(0xFF00D2FC),
                ),
                icon: _loadingCashierLogs
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Color(0xFF00D2FC),
                        ),
                      )
                    : const Icon(Icons.refresh, size: 16),
                label: const Text('从收银机刷新'),
                onPressed: _loadingCashierLogs ? null : _fetchCashierLogs,
              ),
            ],
          ),
        ),
        if (_cashierLogsError != null)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            margin: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.red.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.redAccent.withValues(alpha: 0.3)),
            ),
            child: Row(
              children: [
                const Icon(Icons.error_outline,
                    color: Colors.redAccent, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _cashierLogsError!,
                    style:
                        const TextStyle(color: Colors.redAccent, fontSize: 13),
                  ),
                ),
              ],
            ),
          ),
        Expanded(
          child: _cashierLogs.isEmpty
              ? Center(
                  child: _loadingCashierLogs
                      ? const CircularProgressIndicator()
                      : const Text('收银端暂未产生交互记录',
                          style: TextStyle(color: Colors.white38)),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: _cashierLogs.length,
                  itemBuilder: (ctx, i) {
                    final log = _cashierLogs[i];
                    final id = log['id'] as int? ?? i;
                    final isExpanded = _expandedCashierLogIds.contains(id);
                    return _CashierLogCard(
                      log: log,
                      isExpanded: isExpanded,
                      onToggle: () {
                        setState(() {
                          if (isExpanded) {
                            _expandedCashierLogIds.remove(id);
                          } else {
                            _expandedCashierLogIds.add(id);
                          }
                        });
                      },
                    );
                  },
                ),
        ),
      ],
    );
  }

  // ── Tab 3: 全链路探针测速 ─────────────────────────────────────────
  Widget _buildProbesTab(SessionState session) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '餐饮门店节点连通性与网络往返测速',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: (session.activeChannel == KdsActiveChannel.lan
                                  ? const Color(0xFF00D2FC)
                                  : const Color(0xFF00E676))
                              .withValues(alpha: 0.18),
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(
                            color: (session.activeChannel == KdsActiveChannel.lan
                                    ? const Color(0xFF00D2FC)
                                    : const Color(0xFF00E676))
                                .withValues(alpha: 0.5),
                          ),
                        ),
                        child: Text(
                          '当前生效: ${session.activeChannel == KdsActiveChannel.lan ? "局域网 (LAN)" : "云端直连 (Cloud)"}',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: session.activeChannel == KdsActiveChannel.lan
                                ? const Color(0xFF00D2FC)
                                : const Color(0xFF00E676),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Text(
                        '局域网收银: ${_formatHost(session.apiBase)} (${session.apiBase.isEmpty ? "未配置" : session.apiBase})  |  云端权威: ${_formatHost(session.cloudApiBase)} (${session.cloudApiBase.isEmpty ? "未配置" : session.cloudApiBase})',
                        style: const TextStyle(
                            color: Colors.white54, fontSize: 12),
                      ),
                    ],
                  ),
                ],
              ),
              const Spacer(),
              FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF00E676),
                  foregroundColor: Colors.black87,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                ),
                icon: _probing
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.black87,
                        ),
                      )
                    : const Icon(Icons.play_arrow_rounded, size: 20),
                label: Text(
                  _probing ? '探测中...' : '开始全链路即时探测',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                onPressed: _probing ? null : _runProbes,
              ),
            ],
          ),
          const SizedBox(height: 24),
          if (_probeReport == null && !_probing)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(40),
              decoration: BoxDecoration(
                color: const Color(0xFF1E1E1E),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.white10),
              ),
              child: const Column(
                children: [
                  Icon(Icons.network_check_rounded,
                      size: 48, color: Colors.white30),
                  SizedBox(height: 12),
                  Text(
                    '点击上方按钮开始即时测速，全面检查 HTTP API 与 WebSocket 双通道延迟',
                    style: TextStyle(color: Colors.white54, fontSize: 14),
                  ),
                ],
              ),
            ),
          if (_probeReport != null) ...[
            GridView.count(
              crossAxisCount: 2,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: 16,
              crossAxisSpacing: 16,
              childAspectRatio: 2.2,
              children: [
                _ProbeResultCard(
                  result: _probeReport!.lanHttp,
                  isActiveChannel:
                      session.activeChannel == KdsActiveChannel.lan,
                ),
                _ProbeResultCard(
                  result: _probeReport!.lanWs,
                  isActiveChannel:
                      session.activeChannel == KdsActiveChannel.lan,
                ),
                _ProbeResultCard(
                  result: _probeReport!.cloudHttp,
                  isActiveChannel:
                      session.activeChannel == KdsActiveChannel.cloud,
                ),
                _ProbeResultCard(
                  result: _probeReport!.cloudWs,
                  isActiveChannel:
                      session.activeChannel == KdsActiveChannel.cloud,
                ),
              ],
            ),
            const SizedBox(height: 16),
            _buildProbeGuidanceCard(_probeReport!),
            const SizedBox(height: 12),
            Text(
              '测速完成于: ${DateFormat('HH:mm:ss.SSS').format(_probeReport!.timestamp)}',
              style: const TextStyle(color: Colors.white38, fontSize: 12),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildProbeGuidanceCard(KdsProbeReport report) {
    final lanHealthy = report.lanHttp.isSuccess && report.lanWs.isSuccess;
    final cloudHealthy = report.cloudHttp.isSuccess && report.cloudWs.isSuccess;

    Color bg;
    Color border;
    IconData icon;
    String title;
    String desc;

    if (lanHealthy && !cloudHealthy) {
      bg = const Color(0xFF1E3A8A).withValues(alpha: 0.15);
      border = const Color(0xFF3B82F6).withValues(alpha: 0.4);
      icon = Icons.info_outline;
      title = '局域网代理畅通 · 云端直连暂不可用';
      desc =
          '当前通过收银端透明代理转发至云端。云端直连网络未通，请检查门店外网连通性。';
    } else if (lanHealthy && cloudHealthy) {
      bg = const Color(0xFF065F46).withValues(alpha: 0.15);
      border = const Color(0xFF10B981).withValues(alpha: 0.4);
      icon = Icons.check_circle_outline;
      title = '全链路双通道完全畅通 · 云端优先';
      desc = '云端主通道与局域网代理均正常，当前默认以云端优先直连保障唯一业务权威。';
    } else if (!lanHealthy && cloudHealthy) {
      bg = const Color(0xFF78350F).withValues(alpha: 0.15);
      border = const Color(0xFFF59E0B).withValues(alpha: 0.4);
      icon = Icons.warning_amber_rounded;
      title = '云端直连畅通 · 局域网代理离线';
      desc = '当前以云端主通道正常运行。局域网收银代理不可达（仅影响局域网容灾通道）。';
    } else {
      bg = const Color(0xFF7F1D1D).withValues(alpha: 0.15);
      border = const Color(0xFFEF4444).withValues(alpha: 0.4);
      icon = Icons.error_outline;
      title = '全链路网络异常';
      desc = '局域网与云端均无法连通，请检查本机网线/WiFi 连接及路由器状态。';
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: border),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: border, size: 22),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  desc,
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 12,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── 辅助卡片组件 ───────────────────────────────────────────────────

class _TraceEntryCard extends StatelessWidget {
  const _TraceEntryCard({
    required this.entry,
    required this.isExpanded,
    required this.onToggle,
    this.lanHost = '',
    this.cloudHost = '',
  });

  final KdsTraceEntry entry;
  final bool isExpanded;
  final VoidCallback onToggle;
  final String lanHost;
  final String cloudHost;

  Color get stageColor => switch (entry.stage) {
        KdsTraceStage.fetch => const Color(0xFF2196F3),
        KdsTraceStage.send => const Color(0xFFFF9800),
        KdsTraceStage.receive => const Color(0xFF4CAF50),
        KdsTraceStage.response => const Color(0xFF9C27B0),
        KdsTraceStage.probe => const Color(0xFF00D2FC),
        KdsTraceStage.system => const Color(0xFF9E9E9E),
      };

  @override
  Widget build(BuildContext context) {
    final timeStr = DateFormat('HH:mm:ss.SSS').format(entry.timestamp);
    final isLan = entry.channel == KdsActiveChannel.lan;
    final channelColor =
        isLan ? const Color(0xFF00D2FC) : const Color(0xFF00E676);
    final channelLabel = isLan ? '局域网' : '云端';
    final rawHost = entry.metadata['host'] ??
        (entry.metadata['baseUrl'] != null
            ? _formatHost(entry.metadata['baseUrl'].toString())
            : null) ??
        (entry.metadata['url'] != null
            ? _formatHost(entry.metadata['url'].toString())
            : null) ??
        (isLan ? lanHost : cloudHost);
    final hostDisplay = _formatHost(rawHost.toString());

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E1E),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: entry.isSuccess
              ? Colors.white10
              : Colors.redAccent.withValues(alpha: 0.4),
        ),
      ),
      child: InkWell(
        onTap: onToggle,
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: stageColor.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: stageColor.withValues(alpha: 0.4)),
                    ),
                    child: Text(
                      entry.stage.label.split(' ').first,
                      style: TextStyle(
                        fontSize: 11,
                        color: stageColor,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: channelColor.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(color: channelColor.withValues(alpha: 0.4)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          isLan ? Icons.lan_outlined : Icons.cloud_outlined,
                          size: 11,
                          color: channelColor,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          '$channelLabel · $hostDisplay',
                          style: TextStyle(
                            fontSize: 10,
                            color: channelColor,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    timeStr,
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 12,
                      color: Colors.white54,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      entry.action,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (entry.durationMs != null) ...[
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: (entry.durationMs! > 200
                                ? Colors.orange
                                : const Color(0xFF00E676))
                            .withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        '${entry.durationMs}ms',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: entry.durationMs! > 200
                              ? Colors.orangeAccent
                              : const Color(0xFF00E676),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                  ],
                  Icon(
                    isExpanded
                        ? Icons.keyboard_arrow_up
                        : Icons.keyboard_arrow_down,
                    size: 20,
                    color: Colors.white38,
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                entry.summary,
                style: TextStyle(
                  fontSize: 12,
                  color: entry.isSuccess ? Colors.white70 : Colors.redAccent,
                ),
              ),
              if (isExpanded) ...[
                const Divider(color: Colors.white10, height: 20),
                _PayloadSection(
                  title: '通信传输与链路主机信息',
                  payload: {
                    'channel': entry.channel.label,
                    'transmission_mode':
                        isLan ? '局域网传输 (LAN)' : '云端直连传输 (Cloud)',
                    'target_host': hostDisplay,
                    if (entry.endpoint != null) 'endpoint': entry.endpoint,
                    if (entry.metadata['baseUrl'] != null)
                      'base_url': entry.metadata['baseUrl'],
                    if (entry.statusCode != null)
                      'status_code': entry.statusCode,
                    if (entry.requestId != null) 'request_id': entry.requestId,
                    if (entry.commandId != null) 'command_id': entry.commandId,
                  },
                ),
                if (entry.requestPayload != null)
                  _PayloadSection(
                    title: '请求载荷 (Request Body)',
                    payload: entry.requestPayload,
                  ),
                if (entry.responsePayload != null)
                  _PayloadSection(
                    title: '响应结果 (Response Body)',
                    payload: entry.responsePayload,
                  ),
                if (entry.metadata.isNotEmpty)
                  _PayloadSection(
                    title: '上下文元数据 (Metadata)',
                    payload: entry.metadata,
                  ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _CashierLogCard extends StatelessWidget {
  const _CashierLogCard({
    required this.log,
    required this.isExpanded,
    required this.onToggle,
  });

  final Map<String, dynamic> log;
  final bool isExpanded;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final timeMs = log['occurred_at_ms'] as int? ?? 0;
    final timeStr = timeMs > 0
        ? DateFormat('HH:mm:ss.SSS')
            .format(DateTime.fromMillisecondsSinceEpoch(timeMs))
        : '—';
    final action = '${log['action'] ?? '—'}';
    final stageLabel = '${log['stage_label'] ?? log['stage'] ?? '—'}';
    final status = '${log['status_label'] ?? log['status'] ?? '—'}';
    final orderNo = log['order_no'] != null ? '#${log['order_no']}' : '';
    final isProblem = '${log['status']}' == 'failed' ||
        '${log['status']}' == 'rejected' ||
        '${log['status']}' == 'no_recipient';

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E1E),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: isProblem ? Colors.redAccent.withValues(alpha: 0.4) : Colors.white10,
        ),
      ),
      child: InkWell(
        onTap: onToggle,
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: const Color(0xFF00D2FC).withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      stageLabel,
                      style: const TextStyle(
                        fontSize: 11,
                        color: Color(0xFF00D2FC),
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    timeStr,
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 12,
                      color: Colors.white54,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      '$action $orderNo',
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: (isProblem ? Colors.red : const Color(0xFF00E676))
                          .withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      status,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: isProblem
                            ? Colors.redAccent
                            : const Color(0xFF00E676),
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Icon(
                    isExpanded
                        ? Icons.keyboard_arrow_up
                        : Icons.keyboard_arrow_down,
                    size: 20,
                    color: Colors.white38,
                  ),
                ],
              ),
              if (isExpanded) ...[
                const Divider(color: Colors.white10, height: 20),
                _PayloadSection(
                  title: '收银端原始交互 JSON',
                  payload: log,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _ProbeResultCard extends StatelessWidget {
  const _ProbeResultCard({
    required this.result,
    this.isActiveChannel = false,
  });

  final KdsProbeItemResult result;
  final bool isActiveChannel;

  @override
  Widget build(BuildContext context) {
    final host = _formatHost(result.url);
    final isLan = result.name.contains('局域网');
    final tagColor = isLan ? const Color(0xFF00D2FC) : const Color(0xFF00E676);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E1E),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isActiveChannel
              ? tagColor.withValues(alpha: 0.6)
              : (result.isSuccess
                  ? const Color(0xFF00E676).withValues(alpha: 0.3)
                  : Colors.redAccent.withValues(alpha: 0.4)),
          width: isActiveChannel ? 1.5 : 1.0,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Row(
            children: [
              Icon(
                result.isSuccess ? Icons.check_circle : Icons.cancel,
                color: result.isSuccess
                    ? const Color(0xFF00E676)
                    : Colors.redAccent,
                size: 20,
              ),
              const SizedBox(width: 8),
              Text(
                result.name,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
              if (isActiveChannel) ...[
                const SizedBox(width: 8),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                  decoration: BoxDecoration(
                    color: tagColor.withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: tagColor.withValues(alpha: 0.5)),
                  ),
                  child: Text(
                    '当前主链路',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      color: tagColor,
                    ),
                  ),
                ),
              ],
              const Spacer(),
              if (result.durationMs > 0)
                Text(
                  '${result.durationMs}ms',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: result.isSuccess
                        ? const Color(0xFF00E676)
                        : Colors.redAccent,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  '目标主机: $host',
                  style: const TextStyle(
                    fontSize: 11,
                    fontFamily: 'monospace',
                    color: Colors.white70,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  result.url.isEmpty ? '—' : result.url,
                  style: const TextStyle(fontSize: 11, color: Colors.white38),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            result.message,
            style: TextStyle(
              fontSize: 12,
              color: result.isSuccess ? Colors.white70 : Colors.redAccent,
            ),
          ),
        ],
      ),
    );
  }
}

class _PayloadSection extends StatelessWidget {
  const _PayloadSection({required this.title, required this.payload});

  final String title;
  final dynamic payload;

  @override
  Widget build(BuildContext context) {
    final text = payload is String
        ? payload as String
        : const JsonEncoder.withIndent('  ').convert(payload);

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: Colors.white54,
                ),
              ),
              const Spacer(),
              InkWell(
                onTap: () {
                  Clipboard.setData(ClipboardData(text: text));
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('已复制 $title'),
                      duration: const Duration(seconds: 1),
                    ),
                  );
                },
                child: const Row(
                  children: [
                    Icon(Icons.copy, size: 12, color: Color(0xFF00D2FC)),
                    SizedBox(width: 4),
                    Text(
                      '复制',
                      style: TextStyle(fontSize: 11, color: Color(0xFF00D2FC)),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: const Color(0xFF101010),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
            ),
            child: SelectableText(
              text,
              style: const TextStyle(
                fontFamily: 'monospace',
                fontSize: 11,
                color: Color(0xFFE0E0E0),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({
    required this.label,
    required this.color,
    required this.icon,
  });

  final String label;
  final Color color;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({
    required this.label,
    required this.selected,
    required this.onSelected,
    this.color = const Color(0xFF00D2FC),
  });

  final String label;
  final bool selected;
  final VoidCallback onSelected;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onSelected,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: selected
              ? color.withValues(alpha: 0.2)
              : Colors.white.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: selected ? color : Colors.white12,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: selected ? FontWeight.bold : FontWeight.normal,
            color: selected ? color : Colors.white70,
          ),
        ),
      ),
    );
  }
}
