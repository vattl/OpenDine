import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../cashier_shell/presentation/cashier_app_theme.dart';
import '../runtime/cashier_database_repair_service.dart';
import '../runtime/cashier_kds_runtime.dart';

/// 数据库启动故障时的多功能修复工作台界面。
class CashierStartupFatalApp extends StatelessWidget {
  const CashierStartupFatalApp({
    super.key,
    required this.error,
    this.onResolved,
    this.repairService,
  });

  final Object error;
  final ValueChanged<CashierKdsRuntime>? onResolved;
  final CashierDatabaseRepairService? repairService;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '收银数据库启动修复',
      theme: CashierAppTheme.light(),
      darkTheme: CashierAppTheme.dark(),
      themeMode: ThemeMode.system,
      home: CashierStartupFatalPage(
        error: error,
        onResolved: onResolved,
        repairService: repairService,
      ),
    );
  }
}

class CashierStartupFatalPage extends StatefulWidget {
  const CashierStartupFatalPage({
    super.key,
    required this.error,
    this.onResolved,
    this.repairService,
  });

  final Object error;
  final ValueChanged<CashierKdsRuntime>? onResolved;
  final CashierDatabaseRepairService? repairService;

  @override
  State<CashierStartupFatalPage> createState() => _CashierStartupFatalPageState();
}

class _CashierStartupFatalPageState extends State<CashierStartupFatalPage> {
  // 异步初始化完成前可空，首帧 build 需判空，避免 LateInitializationError 崩溃
  CashierDatabaseRepairService? _service;
  DatabaseDiagnosticResult? _diagnostic;
  bool _loading = false;
  String? _loadingMessage;
  String? _actionError;
  List<DatabaseBackupInfo> _backups = [];
  bool _showErrorDetails = false;

  @override
  void initState() {
    super.initState();
    _initService();
  }

  Future<void> _initService() async {
    try {
      final service = widget.repairService ??
          await CashierDatabaseRepairService.createDefault();
      if (!mounted) return;
      setState(() {
        _service = service;
        _diagnostic = service.diagnose(widget.error);
      });
      _loadBackups();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _actionError = '故障检测失败: $error';
      });
    }
  }

  Future<void> _loadBackups() async {
    final service = _service;
    if (service == null) return;
    try {
      final backups = await service.getAvailableBackups();
      if (mounted) {
        setState(() => _backups = backups);
      }
    } catch (_) {}
  }

  Future<void> _runAction(String message, Future<CashierKdsRuntime> Function() action) async {
    if (_service == null) return;
    setState(() {
      _loading = true;
      _loadingMessage = message;
      _actionError = null;
    });
    try {
      final runtime = await action();
      if (!mounted) return;
      if (widget.onResolved != null) {
        widget.onResolved!(runtime);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('数据库启动修复成功！')),
        );
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _loadingMessage = null;
        _actionError = '修复失败: $e';
      });
      _loadBackups();
    }
  }

  void _handleRetry() {
    _runAction('正在重试启动收银数据库...', () => _service!.retryStartup());
  }

  void _handleClearLocks() {
    _runAction('正在清理应用临时锁并重试（不会删除数据库辅助文件）...', () => _service!.clearStaleLocksAndRetry());
  }

  Future<void> _handleRestoreFromBackup() async {
    if (_backups.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('未找到可用的历史自动备份快照')),
      );
      return;
    }

    final selected = await showDialog<DatabaseBackupInfo>(
      context: context,
      builder: (ctx) {
        final isDark = Theme.of(ctx).brightness == Brightness.dark;
        return AlertDialog(
          backgroundColor: isDark ? const Color(0xff2d2d2d) : Colors.white,
          title: const Text('选择要还原的备份快照'),
          content: SizedBox(
            width: 480,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '还原前，系统会自动将当前异常的数据库文件归档至 quarantine 隔离目录，绝不丢失现有数据。',
                  style: TextStyle(fontSize: 13, color: Colors.grey),
                ),
                const SizedBox(height: 12),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 280),
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: _backups.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final b = _backups[index];
                      return ListTile(
                        leading: Icon(
                          Icons.backup_outlined,
                          color: index == 0 ? Colors.green : null,
                        ),
                        title: Text(
                          b.formattedTime,
                          style: TextStyle(
                            fontWeight: index == 0 ? FontWeight.bold : FontWeight.normal,
                          ),
                        ),
                        subtitle: Text('大小: ${b.formattedSize}${index == 0 ? ' (最新)' : ''}'),
                        trailing: const Icon(Icons.chevron_right, size: 18),
                        onTap: () => Navigator.of(ctx).pop(b),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('取消'),
            ),
          ],
        );
      },
    );

    if (selected != null) {
      _runAction(
        '正在从 ${selected.formattedTime} 备份还原并重新启动...',
        () => _service!.restoreFromBackup(selected.directory),
      );
    }
  }

  Future<void> _handleQuarantineAndRebuild() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        final isDark = Theme.of(ctx).brightness == Brightness.dark;
        return AlertDialog(
          backgroundColor: isDark ? const Color(0xff2d2d2d) : Colors.white,
          title: const Row(
            children: [
              Icon(Icons.warning_amber_rounded, color: Colors.orange),
              SizedBox(width: 8),
              Text('安全归档并重建全新数据库'),
            ],
          ),
          content: const Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('确定要重建全新的本地收银数据库吗？'),
              SizedBox(height: 10),
              Text(
                '1. 当前异常文件将被安全移至 quarantine 归档目录（历史文件完整保留，不丢数据）。',
                style: TextStyle(fontSize: 13),
              ),
              SizedBox(height: 4),
              Text(
                '2. 系统将初始化空数据库并启动。由于本系统采用云端优先架构，登录后菜品与配置将自动重新同步。',
                style: TextStyle(fontSize: 13),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('取消'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: Colors.red),
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('确认安全归档并重建'),
            ),
          ],
        );
      },
    );

    if (confirmed == true) {
      _runAction('正在安全隔离旧库并初始化全新数据库...', () => _service!.quarantineAndRebuild());
    }
  }

  Future<void> _handleOpenFolder() async {
    final opened = await _service!.openDataFolder();
    if (!mounted) return;
    if (!opened) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('已将本地数据目录路径复制到剪贴板')),
      );
    }
  }

  Future<void> _handleViewLogs() async {
    final logs = await _service!.readRecentLogs();
    if (!mounted) return;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: isDark ? const Color(0xff2d2d2d) : Colors.white,
        title: const Text('本地运行与崩溃日志 (最近记录)'),
        content: SizedBox(
          width: 700,
          height: 420,
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xff1f1f1f) : const Color(0xfff5f5f5),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: isDark ? const Color(0xff4a4a4a) : const Color(0xffe0e0e0),
              ),
            ),
            child: SingleChildScrollView(
              child: SelectableText(
                logs,
                style: const TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 12,
                ),
              ),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              Clipboard.setData(ClipboardData(text: logs));
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('日志内容已复制到剪贴板')),
              );
            },
            child: const Text('复制日志'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('关闭'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surfaceColor = isDark ? const Color(0xff2d2d2d) : Colors.white;
    final canvasColor = isDark ? const Color(0xff232323) : const Color(0xfff8f9fa);
    final borderColor = isDark ? const Color(0xff4a4a4a) : const Color(0xffe5e7eb);
    final inkColor = isDark ? const Color(0xfff2f2f2) : const Color(0xff1f2937);

    return Scaffold(
      backgroundColor: canvasColor,
      body: Stack(
        children: [
          Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 720),
                child: Container(
                  decoration: BoxDecoration(
                    color: surfaceColor,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: borderColor),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: isDark ? 0.3 : 0.06),
                        blurRadius: 20,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  padding: const EdgeInsets.all(32),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // 头部状态
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Colors.red.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: const Icon(
                              Icons.storage_rounded,
                              size: 32,
                              color: Colors.red,
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '本地收银数据库启动异常',
                                  style: TextStyle(
                                    fontSize: 22,
                                    fontWeight: FontWeight.bold,
                                    color: inkColor,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  '系统已为您检测故障原因，并提供以下多级自动修复选项',
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: isDark ? Colors.grey[400] : Colors.grey[600],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 20),

                      // 智能诊断卡片
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: isDark ? const Color(0xff362d1d) : const Color(0xfffffbeb),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: isDark ? const Color(0xff685226) : const Color(0xfffde68a),
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                const Icon(
                                  Icons.offline_bolt_outlined,
                                  size: 18,
                                  color: Color(0xffd97706),
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  _diagnostic?.title ?? '正在检测故障原因…',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 14,
                                    color: Color(0xffd97706),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Text(
                              _diagnostic?.description ??
                                  '正在分析本地数据库文件与运行环境，请稍候…',
                              style: TextStyle(
                                fontSize: 13,
                                color: isDark ? const Color(0xfffef3c7) : const Color(0xff92400e),
                                height: 1.4,
                              ),
                            ),
                            if (_diagnostic != null) ...[
                              const SizedBox(height: 8),
                              Text(
                                '👉 建议：${_diagnostic!.recommendedAction}',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: isDark ? const Color(0xfffcd34d) : const Color(0xffb45309),
                              ),
                            ),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),

                      // 操作失败报错条
                      if (_actionError != null) ...[
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.red.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.red.withValues(alpha: 0.3)),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.error_outline, color: Colors.red, size: 18),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  _actionError!,
                                  style: const TextStyle(fontSize: 13, color: Colors.red),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),
                      ],

                      // 修复功能选项列表
                      Text(
                        '请选择修复方式：',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: inkColor,
                        ),
                      ),
                      const SizedBox(height: 12),

                      // 选项 1：一键重试启动
                      _RepairActionCard(
                        icon: Icons.refresh_rounded,
                        iconColor: Colors.blue,
                        title: '一键重试启动',
                        subtitle: '若此前为短暂锁冲突或外部程序已释放文件，点击此项重新连接',
                        isPrimary: true,
                        onTap: _loading || _service == null ? null : _handleRetry,
                      ),
                      const SizedBox(height: 10),

                      // 选项 2：清理临时锁并重试
                      _RepairActionCard(
                        icon: Icons.cleaning_services_outlined,
                        iconColor: Colors.orange,
                        title: '清理临时锁与缓存修复',
                        subtitle: '自动清理残留进程锁文件及 SQLite -shm 共享内存缓存并重试',
                        onTap: _loading || _service == null ? null : _handleClearLocks,
                      ),
                      const SizedBox(height: 10),

                      // 选项 3：从历史自动备份还原
                      _RepairActionCard(
                        icon: Icons.settings_backup_restore_rounded,
                        iconColor: Colors.teal,
                        title: '从历史自动备份还原',
                        subtitle: _backups.isEmpty
                            ? '正在扫描本地可用自动备份快照...'
                            : '检测到 ${_backups.length} 份可用快照 (最新: ${_backups.first.formattedTime})，安全无损恢复',
                        badgeText: _backups.isNotEmpty ? '${_backups.length} 个备份' : null,
                        badgeColor: Colors.teal,
                        onTap: _loading || _service == null ? null : _handleRestoreFromBackup,
                      ),
                      const SizedBox(height: 10),

                      // 选项 4：安全归档并重建全新库
                      _RepairActionCard(
                        icon: Icons.add_box_outlined,
                        iconColor: Colors.deepPurple,
                        title: '安全归档并重建全新库',
                        subtitle: '隔离现有文件（绝不丢失数据），重建空库。登录后菜品与配置自动拉取',
                        onTap: _loading || _service == null ? null : _handleQuarantineAndRebuild,
                      ),
                      const SizedBox(height: 20),

                      // 辅助工具行
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          TextButton.icon(
                            onPressed: _loading || _service == null ? null : _handleOpenFolder,
                            icon: const Icon(Icons.folder_open, size: 18),
                            label: const Text('打开本地数据目录'),
                          ),
                          TextButton.icon(
                            onPressed: _loading || _service == null ? null : _handleViewLogs,
                            icon: const Icon(Icons.description_outlined, size: 18),
                            label: const Text('查看运行日志'),
                          ),
                          TextButton.icon(
                            onPressed: () {
                              setState(() => _showErrorDetails = !_showErrorDetails);
                            },
                            icon: Icon(
                              _showErrorDetails ? Icons.expand_less : Icons.expand_more,
                              size: 18,
                            ),
                            label: Text(_showErrorDetails ? '收起技术错误' : '查看技术错误'),
                          ),
                        ],
                      ),

                      // 折叠的技术错误详情
                      if (_showErrorDetails) ...[
                        const SizedBox(height: 12),
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: isDark ? const Color(0xff1a1a1a) : const Color(0xfff3f4f6),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: borderColor),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  const Text(
                                    'Exception StackTrace:',
                                    style: TextStyle(
                                      fontFamily: 'monospace',
                                      fontSize: 11,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.grey,
                                    ),
                                  ),
                                  TextButton.icon(
                                    style: TextButton.styleFrom(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                      visualDensity: VisualDensity.compact,
                                    ),
                                    onPressed: () {
                                      Clipboard.setData(ClipboardData(text: widget.error.toString()));
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        const SnackBar(content: Text('已复制错误信息')),
                                      );
                                    },
                                    icon: const Icon(Icons.copy, size: 14),
                                    label: const Text('复制错误', style: TextStyle(fontSize: 12)),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 6),
                              SelectableText(
                                widget.error.toString(),
                                style: TextStyle(
                                  fontFamily: 'monospace',
                                  fontSize: 12,
                                  color: isDark ? Colors.red[300] : Colors.red[800],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),

          // 加载遮罩
          if (_loading)
            Container(
              color: Colors.black.withValues(alpha: 0.55),
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
                  decoration: BoxDecoration(
                    color: surfaceColor,
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: const [
                      BoxShadow(color: Colors.black26, blurRadius: 16),
                    ],
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const CircularProgressIndicator(),
                      const SizedBox(height: 16),
                      Text(
                        _loadingMessage ?? '正在执行修复操作...',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: inkColor,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _RepairActionCard extends StatelessWidget {
  const _RepairActionCard({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.isPrimary = false,
    this.badgeText,
    this.badgeColor,
  });

  final IconData icon;
  final Color iconColor;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;
  final bool isPrimary;
  final String? badgeText;
  final Color? badgeColor;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final borderColor = isPrimary
        ? (isDark ? const Color(0xff1e3a5f) : const Color(0xffbfdbfe))
        : (isDark ? const Color(0xff3f3f46) : const Color(0xffe5e7eb));
    final bgColor = isPrimary
        ? (isDark ? const Color(0xff152538) : const Color(0xffeff6ff))
        : (isDark ? const Color(0xff27272a) : Colors.white);
    final titleColor = isDark ? const Color(0xfff4f4f5) : const Color(0xff111827);
    final subtitleColor = isDark ? const Color(0xffa1a1aa) : const Color(0xff6b7280);

    return Material(
      color: bgColor,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: borderColor, width: isPrimary ? 1.5 : 1.0),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: iconColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, color: iconColor, size: 22),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          title,
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                            color: titleColor,
                          ),
                        ),
                        if (badgeText != null) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: (badgeColor ?? iconColor).withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              badgeText!,
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: badgeColor ?? iconColor,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(
                      subtitle,
                      style: TextStyle(fontSize: 12, color: subtitleColor),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Icon(
                Icons.arrow_forward_ios_rounded,
                size: 14,
                color: isDark ? Colors.grey[500] : Colors.grey[400],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
