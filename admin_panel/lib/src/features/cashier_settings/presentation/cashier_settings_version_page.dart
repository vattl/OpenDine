import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../../core/admin_api_client.dart';
import '../../cashier_shell/presentation/cashier_tokens.dart';
import '../../version_upgrade/data/app_version_management_repository.dart';
import '../../version_upgrade/domain/app_version_info.dart';
import '../../version_upgrade/domain/app_version_management_model.dart';
import 'cashier_settings_shared.dart';

class CashierSettingsVersionPage extends StatefulWidget {
  const CashierSettingsVersionPage({
    super.key,
    this.client,
    this.repository,
    this.permissions = const {},
    this.section,
    this.currentShopId,
  });

  final AdminApiClient? client;
  final AppVersionManagementRepository? repository;
  final Set<String> permissions;
  final SettingsSectionSpec? section;
  final int? currentShopId;

  @override
  State<CashierSettingsVersionPage> createState() =>
      _CashierSettingsVersionPageState();
}

class _CashierSettingsVersionPageState
    extends State<CashierSettingsVersionPage> {
  late final AppVersionManagementRepository _repository;
  late Future<List<AppVersionPolicyItem>> _policiesFuture;

  String _selectedPlatformTab = 'all';

  // 沙箱模拟状态
  final _simPlatformController = TextEditingController(text: 'windows');
  final _simChannelController = TextEditingController(text: 'pos');
  final _simVersionController = TextEditingController(text: '2.0.2');
  final _simShopIdController = TextEditingController(text: '1');
  bool _simulating = false;
  AppVersionInfo? _simulationResult;
  String? _simulationError;

  @override
  void initState() {
    super.initState();
    if (widget.repository == null && widget.client == null) return;
    _repository = widget.repository ?? RealAppVersionManagementRepository(client: widget.client!);
    _loadPolicies();
  }

  @override
  void dispose() {
    _simPlatformController.dispose();
    _simChannelController.dispose();
    _simVersionController.dispose();
    _simShopIdController.dispose();
    super.dispose();
  }

  void _loadPolicies() {
    setState(() {
      _policiesFuture = _repository.fetchVersionList();
    });
  }

  Future<void> _toggleEnabled(AppVersionPolicyItem item) async {
    try {
      await _repository.toggleVersionEnabled(
        id: item.id,
        enabled: !item.enabled,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
              '${item.platform} (${item.channel}) 策略已${!item.enabled ? '启用' : '停用'}',
          ),
          behavior: SnackBarBehavior.floating,
        ),
      );
      _loadPolicies();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('更新状态失败: $e'),
          backgroundColor: context.cashier.danger,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _deletePolicy(AppVersionPolicyItem item) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除版本策略确认'),
        content: Text(
          '确定要删除平台 ${item.platform}（渠道 ${item.channel}）的版本策略吗？删除后该端客户端更新将失去依据。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xffef4444),
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('确认删除'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        await _repository.deleteVersion(item.id);
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${item.platform} 策略已删除'),
            behavior: SnackBarBehavior.floating,
          ),
        );
        _loadPolicies();
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('删除失败: $e'),
            backgroundColor: context.cashier.danger,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  Future<void> _openEditDialog([AppVersionPolicyItem? existing]) async {
    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => _VersionPolicyEditDialog(
        repository: _repository,
        existing: existing),
    );
    if (saved == true) {
      _loadPolicies();
    }
  }

  Future<void> _runSimulation() async {
    setState(() {
      _simulating = true;
      _simulationError = null;
    });
    try {
      final res = await _repository.simulateUpgradeVerdict(
        platform: _simPlatformController.text.trim(),
        channel: _simChannelController.text.trim(),
        currentVersion: _simVersionController.text.trim(),
        shopId: int.tryParse(_simShopIdController.text.trim()),
      );
      if (mounted) {
        setState(() {
          _simulationResult = res;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _simulationError = e.toString();
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _simulating = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // 权限双重防御门禁：必须精确包含 admin:super
    final isAuthorized = widget.permissions.contains('admin:super');
    if (!isAuthorized) {
      return const _ForbiddenBarrierView(
        key: Key('version-management-forbidden-barrier'),
      );
    }

    if (widget.repository == null && widget.client == null) {
      return const SettingsEmptyState(
        title: '版本服务未连接',
        description: '请连接服务器后查看和管理版本策略。',
      );
    }
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: FutureBuilder<List<AppVersionPolicyItem>>(
        future: _policiesFuture,
        builder: (context, snapshot) {
          final policies = snapshot.data ?? const [];
          final loading =
              snapshot.connectionState == ConnectionState.waiting;

          return ListView(
            padding: const EdgeInsets.all(24),
            children: [
              _buildTopBanner(policies),
              const SizedBox(height: 20),
              _buildMetricsRow(policies),
              const SizedBox(height: 24),
              _buildPlatformTabs(policies),
              const SizedBox(height: 16),
              if (loading)
                const Center(
                  child: Padding(
                    padding: EdgeInsets.all(40),
                    child: CircularProgressIndicator(),
                  ),
                )
              else if (snapshot.hasError)
                _buildErrorCard(snapshot.error.toString())
              else if (policies.isEmpty)
                _buildEmptyCard()
              else
                _buildPolicyCardsGrid(
                  _filterPolicies(policies)),
              const SizedBox(height: 28),
              _buildSandboxPanel(),
            ],
          );
        },
      ),
    );
  }

  Widget _buildTopBanner(List<AppVersionPolicyItem> policies) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      decoration: BoxDecoration(
        color: context.cashier.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: context.cashier.border),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: const Color(0xfffef3c7),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: const Color(0xfffde68a)),
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.shield_outlined, size: 14, color: Color(0xffb45309)),
                SizedBox(width: 4),
                Text(
                  '超级管理员 (admin:super) 专属',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: Color(0xffb45309),
                  ),
                ),
              ],
            ),
          ),
          const Spacer(),
          OutlinedButton.icon(
            key: const Key('btn-refresh-version-policies'),
            onPressed: _loadPolicies,
            icon: const Icon(Icons.refresh_rounded, size: 16),
            label: const Text('刷新策略'),
          ),
          const SizedBox(width: 12),
          FilledButton.icon(
            key: const Key('btn-add-version-policy'),
            onPressed: () => _openEditDialog(),
            icon: const Icon(Icons.add_rounded, size: 16),
            label: const Text('发布新版策略'),
          ),
        ],
      ),
    );
  }

  Widget _buildMetricsRow(List<AppVersionPolicyItem> policies) {
    final activeCount = policies.where((p) => p.enabled).length;
    final forceCount = policies.where((p) => p.forceUpdate && p.enabled).length;
    final grayCount = policies
        .where((p) =>
            p.grayShopIds != null && p.grayShopIds!.trim().isNotEmpty && p.enabled,
        )
        .length;
    final platforms = policies.map((p) => p.platform).toSet().length;

    return Row(
      children: [
        Expanded(
          child: _MetricCard(
            label: '覆盖平台',
            value: '$platforms',
            sub: 'Windows · Android · iOS',
            accent: context.cashier.selected,
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: _MetricCard(
            label: '生效策略',
            value: '$activeCount',
            sub: '总发布策略 ${policies.length} 条',
            accent: context.cashier.selected,
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: _MetricCard(
            label: '强更拦截中',
            value: '$forceCount',
            sub: forceCount > 0 ? '包含强制阻断策略' : '全部建议更新',
            accent: const Color(0xffef4444),
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: _MetricCard(
            label: '灰度分流中',
            value: '$grayCount',
            sub: grayCount > 0 ? '白名单门店先行测试' : '全门店发布',
            accent: const Color(0xfff59e0b),
          ),
        ),
      ],
    );
  }

  Widget _buildPlatformTabs(List<AppVersionPolicyItem> policies) {
    final platforms = [
      'all',
      'windows',
      'android',
      'ios'];
    return Row(
      children: [
        for (final p in platforms)
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: ChoiceChip(
              key: Key('chip-platform-$p'),
              label: Text(
                p == 'all'
                    ? '全部平台 (${policies.length})'
                    : p == 'windows'
                        ? 'Windows (${policies.where((x) => x.platform == 'windows').length})'
                        : p == 'android'
                            ? 'Android (${policies.where((x) => x.platform == 'android').length})'
                            : 'iOS (${policies.where((x) => x.platform == 'ios').length})',
              ),
              selected: _selectedPlatformTab == p,
              onSelected: (val) {
                if (val) setState(() => _selectedPlatformTab = p);
              },
            ),
          ),
      ],
    );
  }

  List<AppVersionPolicyItem> _filterPolicies(
      List<AppVersionPolicyItem> policies,
  ) {
    if (_selectedPlatformTab == 'all') return policies;
    return policies
        .where((x) => x.platform.toLowerCase() == _selectedPlatformTab)
        .toList();
  }

  Widget _buildPolicyCardsGrid(List<AppVersionPolicyItem> policies) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final crossCount = constraints.maxWidth >= 900 ? 2 : 1;
        return GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: crossCount,
            crossAxisSpacing: 16,
            mainAxisSpacing: 16,
            mainAxisExtent: 290,
          ),
          itemCount: policies.length,
          itemBuilder: (context, idx) {
            final item = policies[idx];
            return _PolicyCard(
              key: Key('policy-card-${item.id}'),
              item: item,
              onToggleEnabled: () => _toggleEnabled(item),
              onEdit: () => _openEditDialog(item),
              onDelete: () => _deletePolicy(item),
              onTestSimulator: () {
                _simPlatformController.text = item.platform;
                _simChannelController.text = item.channel;
                _simVersionController.text = item.minSupported ?? '1.0.0';
                _simShopIdController.text = widget.currentShopId?.toString() ?? '1';
                _runSimulation();
              },
            );
          },
        );
      },
    );
  }

  Widget _buildSandboxPanel() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: context.cashier.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: context.cashier.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.science_outlined,
                  size: 20, color: context.cashier.selected,
              ),
              const SizedBox(width: 8),
              const Text(
                '升级决断沙箱 (推演客户端版本与灰度匹配结果)',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: TextField(
                  key: const Key('sandbox-input-platform'),
                  controller: _simPlatformController,
                  decoration: const InputDecoration(
                    labelText: '平台 (windows/android/ios)',
                    isDense: true,
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  key: const Key('sandbox-input-channel'),
                  controller: _simChannelController,
                  decoration: const InputDecoration(
                    labelText: '渠道 (pos/mobile)',
                    isDense: true,
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  key: const Key('sandbox-input-version'),
                  controller: _simVersionController,
                  decoration: const InputDecoration(
                    labelText: '客户端当前版本 (如 2.0.2)',
                    isDense: true,
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  key: const Key('sandbox-input-shop-id'),
                  controller: _simShopIdController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: '门店 ID (灰度判定)',
                    isDense: true,
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              FilledButton.icon(
                key: const Key('sandbox-run-button'),
                onPressed: _simulating ? null : _runSimulation,
                icon: _simulating
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.play_arrow_rounded, size: 18),
                label: const Text('运行决断'),
              ),
            ],
          ),
          if (_simulationError != null) ...[
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xfffef2f2),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xfffecaca)),
              ),
              child: Text(
                '模拟调用失败: $_simulationError',
                style: const TextStyle(color: Color(0xffb91c1c), fontSize: 13),
              ),
            ),
          ],
          if (_simulationResult != null) ...[
            const SizedBox(height: 14),
            Container(
              key: const Key('sandbox-result-box'),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: const Color(0xfff0fdf4),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xffbbf7d0)),
              ),
              child: Row(
                children: [
                  Icon(
                    _simulationResult!.hasUpdate
                        ? Icons.check_circle_outline_rounded
                        : Icons.info_outline_rounded,
                    size: 20,
                    color: const Color(0xff15803d),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      '决断结果: hasUpdate=${_simulationResult!.hasUpdate} · '
                      'upgradeType=${_simulationResult!.upgradeType.name.toUpperCase()} · '
                      'installMode=${_simulationResult!.installMode.name} · '
                      '目标最新版本: v${_simulationResult!.latest}',
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: Color(0xff166534),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildEmptyCard() {
    return Container(
      padding: const EdgeInsets.all(40),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: context.cashier.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: context.cashier.border),
      ),
      child: const Text('暂无已配置的版本策略，请点击右上角「发布新版策略」新增。'),
    );
  }

  Widget _buildErrorCard(String error) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xfffef2f2),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xfffecaca)),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline, color: Color(0xffb91c1c)),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              '加载策略失败: $error',
              style: const TextStyle(color: Color(0xffb91c1c)),
            ),
          ),
          OutlinedButton(
            onPressed: _loadPolicies,
            child: const Text('重试')),
        ],
      ),
    );
  }
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({
    required this.label,
    required this.value,
    required this.sub,
    required this.accent,
  });

  final String label;
  final String value;
  final String sub;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: context.cashier.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: context.cashier.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style:
                  TextStyle(fontSize: 13, color: context.cashier.inkMuted),
          ),
          const SizedBox(height: 6),
          Text(
            value,
            style: TextStyle(
              fontSize: 26,
              fontWeight: FontWeight.w800,
              color: accent,
            ),
          ),
          const SizedBox(height: 4),
          Text(sub,
              style:
                  TextStyle(fontSize: 12, color: context.cashier.inkMuted),
          ),
        ],
      ),
    );
  }
}

class _PolicyCard extends StatelessWidget {
  const _PolicyCard({
    super.key,
    required this.item,
    required this.onToggleEnabled,
    required this.onEdit,
    required this.onDelete,
    required this.onTestSimulator,
  });

  final AppVersionPolicyItem item;
  final VoidCallback onToggleEnabled;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final VoidCallback onTestSimulator;

  @override
  Widget build(BuildContext context) {
    final pLower = item.platform.toLowerCase();
    final badgeBg = pLower == 'windows'
        ? const Color(0xffe0f2fe)
        : (pLower == 'android'
            ? const Color(0xffdcfce7)
            : const Color(0xffffedd5));
    final badgeFg = pLower == 'windows'
        ? const Color(0xff0369a1)
        : (pLower == 'android'
            ? const Color(0xff15803d)
            : const Color(0xffc2410c));

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: context.cashier.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: item.enabled
              ? context.cashier.border
              : context.cashier.border.withValues(alpha: 0.5),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: badgeBg,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  '${item.platform.toUpperCase()} · ${item.channel}',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: badgeFg,
                  ),
                ),
              ),
              const Spacer(),
              Text(
                item.enabled ? '已启用' : '已停用',
                style: TextStyle(
                  fontSize: 12,
                  color: item.enabled
                      ? const Color(0xff166534)
                      : context.cashier.inkMuted,
                ),
              ),
              const SizedBox(width: 4),
              Transform.scale(
                scale: 0.8,
                child: Switch(
                  value: item.enabled,
                  onChanged: (_) => onToggleEnabled(),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                'v${item.latest}',
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: const Color(0xfff1f5f9),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  '#${item.versionCode}',
                  style: const TextStyle(
                    fontSize: 11,
                    color: Color(0xff64748b),
                    fontFamily: 'monospace',
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: item.forceUpdate
                      ? const Color(0xfffee2e2)
                      : const Color(0xfff0fdf4),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  item.forceUpdate ? '强制升级' : '建议升级',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: item.forceUpdate
                        ? const Color(0xffb91c1c)
                        : const Color(0xff166534),
                  ),
                ),
              ),
              const SizedBox(width: 6),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: const Color(0xfff3e8ff),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  item.installMode,
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: Color(0xff6b21a8),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: const Color(0xfff8fafc),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: const Color(0xfff1f5f9)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    '最低兼容: ${item.minSupported != null ? 'v${item.minSupported}' : '不限'}',
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
                Expanded(
                  child: Text(
                    '灰度: ${item.grayShopIds != null && item.grayShopIds!.isNotEmpty ? '门店[${item.grayShopIds}]' : '全门店'}',
                    style: TextStyle(
                      fontSize: 12,
                      color: item.grayShopIds != null &&
                              item.grayShopIds!.isNotEmpty
                          ? const Color(0xffb45309)
                          : const Color(0xff15803d),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: const Color(0xffe2e8f0)),
              ),
              width: double.infinity,
              child: SingleChildScrollView(
                child: Text(
                  item.releaseNotes != null && item.releaseNotes!.isNotEmpty
                      ? item.releaseNotes!
                      : '暂无发布日志说明',
                  style: TextStyle(
                    fontSize: 12,
                    color: context.cashier.inkMuted,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton.icon(
                onPressed: onTestSimulator,
                icon: const Icon(Icons.science_outlined, size: 14),
                label: const Text('沙箱模拟', style: TextStyle(fontSize: 12)),
              ),
              const SizedBox(width: 4),
              OutlinedButton.icon(
                onPressed: onEdit,
                icon: const Icon(Icons.edit_outlined, size: 14),
                label: const Text('编辑', style: TextStyle(fontSize: 12)),
              ),
              const SizedBox(width: 4),
              IconButton(
                onPressed: onDelete,
                icon: const Icon(Icons.delete_outline,
                    size: 16, color: Color(0xffef4444),
                ),
                tooltip: '删除策略',
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _VersionPolicyEditDialog extends StatefulWidget {
  const _VersionPolicyEditDialog({
    required this.repository,
    this.existing});

  final AppVersionManagementRepository repository;
  final AppVersionPolicyItem? existing;

  @override
  State<_VersionPolicyEditDialog> createState() =>
      _VersionPolicyEditDialogState();
}

class _VersionPolicyEditDialogState extends State<_VersionPolicyEditDialog> {
  final _formKey = GlobalKey<FormState>();

  late String _platform;
  late final TextEditingController _channelController;
  late final TextEditingController _latestController;
  late final TextEditingController _versionCodeController;
  late final TextEditingController _minSupportedController;
  late bool _forceUpdate;
  late String _installMode;
  late String _packageType;
  late final TextEditingController _fileSizeController;
  late final TextEditingController _sha256Controller;
  late final TextEditingController _grayShopIdsController;
  late final TextEditingController _downloadUrlController;
  late final TextEditingController _releaseNotesController;
  late bool _enabled;

  bool _saving = false;
  bool _isUploading = false;
  String? _uploadedFileName;

  Future<void> _handlePickAndUploadPackage() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['exe', 'apk', 'zip', 'msi', 'dmg', 'pkg', 'deb', 'rpm', 'appimage', 'wgt', 'tar', 'gz', 'bin',
        ],
        withData: true,
      );
      if (result == null || result.files.isEmpty) return;
      final file = result.files.single;
      final path = file.path;
      final bytes = file.bytes;
      if (path == null && (bytes == null || bytes.isEmpty)) {
        if (mounted) {
          ScaffoldMessenger.of(context,
          ).showSnackBar(
            const SnackBar(content: Text('无法读取所选文件，请重新选择')));
        }
        return;
      }

      setState(() => _isUploading = true);

      final uploadResult = await widget.repository.uploadPackage(
        filePath: path,
        fileBytes: bytes,
        fileName: file.name,
        platform: _platform,
        channel: _channelController.text.trim(),
      );

      if (!mounted) return;

      setState(() {
        _isUploading = false;
        _uploadedFileName = uploadResult.fileName;
        _downloadUrlController.text = uploadResult.downloadUrl;
        _sha256Controller.text = uploadResult.sha256;
        _fileSizeController.text = uploadResult.fileSize.toString();
        if (uploadResult.packageType.isNotEmpty) {
          _packageType = uploadResult.packageType;
        }

        final versionRegex = RegExp(r'(\d+\.\d+\.\d+(?:\+\d+)?)');
        final match = versionRegex.firstMatch(uploadResult.fileName);
        if (match != null) {
          final matchedVer = match.group(1)!;
          if (_latestController.text.isEmpty || _latestController.text == '2.1.0') {
            final pureVer = matchedVer.split('+')[0];
            _latestController.text = pureVer;
            if (matchedVer.contains('+')) {
              final codeStr = matchedVer.split('+')[1];
              final code = int.tryParse(codeStr);
              if (code != null) {
                _versionCodeController.text = code.toString();
              }
            }
          }
        }
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('安装包上传成功并已自动提取元数据: ${uploadResult.fileName}')),
      );
    } catch (e) {
      if (mounted) {
        setState(() => _isUploading = false);
        ScaffoldMessenger.of(context,
        ).showSnackBar(
          SnackBar(content: Text('上传失败: $e')));
      }
    }
  }

  bool _isVerifyingUrl = false;

  Future<void> _handleVerifyDownloadUrl() async {
    final url = _downloadUrlController.text.trim();
    if (url.isEmpty) {
      ScaffoldMessenger.of(context,
      ).showSnackBar(
        const SnackBar(content: Text('请先输入安装包下载地址')));
      return;
    }
    setState(() => _isVerifyingUrl = true);
    try {
      final res = await widget.repository.verifyDownloadUrl(
        downloadUrl: url,
        expectedSha256: _sha256Controller.text.trim(),
      );
      if (!mounted) return;
      setState(() => _isVerifyingUrl = false);

      final isHtml = res['isHtmlFallback'] == true;
      final matched = res['hashMatched'] == true;
      final actualSha = res['actualSha256']?.toString();
      final fileSize = res['fileSize'];

      if (isHtml) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('直链异常：服务器返回了网页(HTML)而非安装包！请检查 Nginx 代理配置或直链有效性。',
            ),
            backgroundColor: context.cashier.danger,
            behavior: SnackBarBehavior.floating,
          ),
        );
      } else if (!matched) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('哈希不一致！远端真实哈希: $actualSha'),
            backgroundColor: context.cashier.warning,
            behavior: SnackBarBehavior.floating,
            action: actualSha != null
                ? SnackBarAction(
                    label: '填入真实哈希',
                    textColor: Colors.white,
                    onPressed: () {
                      setState(() {
                        _sha256Controller.text = actualSha;
                        if (fileSize != null) {
                          _fileSizeController.text = fileSize.toString();
                        }
                      });
                    },
                  )
                : null,
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('直链探测成功：文件有效且 SHA-256 校验一致 (大小: $fileSize 字节)'),
            backgroundColor: const Color(0xff16a34a),
            behavior: SnackBarBehavior.floating,
          ),
        );
        if (_fileSizeController.text.isEmpty && fileSize != null) {
          setState(() {
            _fileSizeController.text = fileSize.toString();
          });
        }
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _isVerifyingUrl = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('探测直链失败: $e'),
          backgroundColor: context.cashier.danger,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _platform = e?.platform ?? 'windows';
    _channelController = TextEditingController(text: e?.channel ?? 'pos');
    _latestController = TextEditingController(text: e?.latest ?? '2.1.0');
    _versionCodeController =
        TextEditingController(text: (e?.versionCode ?? 20100).toString(),
    );
    _minSupportedController =
        TextEditingController(text: e?.minSupported ?? '2.0.0',
    );
    _forceUpdate = e?.forceUpdate ?? false;
    _installMode = e?.installMode ?? (_platform == 'ios' ? 'store_redirect' : 'silent');
    _packageType = e?.packageType ?? 'full';
    _fileSizeController =
        TextEditingController(text: e?.fileSize?.toString() ?? '',
    );
    _sha256Controller = TextEditingController(text: e?.sha256 ?? '');
    _grayShopIdsController = TextEditingController(text: e?.grayShopIds ?? '');
    _downloadUrlController = TextEditingController(text: e?.downloadUrl ?? '');
    _releaseNotesController =
        TextEditingController(text: e?.releaseNotes ?? '',
    );
    _enabled = e?.enabled ?? true;
  }

  @override
  void dispose() {
    _channelController.dispose();
    _latestController.dispose();
    _versionCodeController.dispose();
    _minSupportedController.dispose();
    _fileSizeController.dispose();
    _sha256Controller.dispose();
    _grayShopIdsController.dispose();
    _downloadUrlController.dispose();
    _releaseNotesController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);

    try {
      final req = SaveVersionPolicyRequest(
        id: widget.existing?.id,
        platform: _platform,
        channel: _channelController.text.trim(),
        latest: _latestController.text.trim(),
        versionCode: int.tryParse(_versionCodeController.text.trim()) ?? 0,
        minSupported: _minSupportedController.text.trim().isEmpty
            ? null
            : _minSupportedController.text.trim(),
        forceUpdate: _forceUpdate,
        packageType: _packageType,
        installMode: _installMode,
        fileSize: int.tryParse(_fileSizeController.text.trim()),
        sha256: _sha256Controller.text.trim().isEmpty
            ? null
            : _sha256Controller.text.trim(),
        grayShopIds: _grayShopIdsController.text.trim().isEmpty
            ? null
            : _grayShopIdsController.text.trim(),
        downloadUrl: _downloadUrlController.text.trim().isEmpty
            ? null
            : _downloadUrlController.text.trim(),
        releaseNotes: _releaseNotesController.text.trim().isEmpty
            ? null
            : _releaseNotesController.text.trim(),
        enabled: _enabled,
      );

      await widget.repository.saveVersionPolicy(req);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('版本策略保存成功'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('保存失败: $e'),
          backgroundColor: const Color(0xffef4444),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 680, maxHeight: 720),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      widget.existing == null ? '发布新平台版本策略' : '编辑版本更新策略',
                      style: const TextStyle(
                          fontSize: 18, fontWeight: FontWeight.w700,
                      ),
                    ),
                    const Spacer(),
                    IconButton(
                      onPressed: () => Navigator.of(context).pop(false),
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
                const Divider(),
                Expanded(
                  child: ListView(
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: DropdownButtonFormField<String>(
                              isExpanded: true,
                              initialValue: _platform,
                              decoration: const InputDecoration(
                                labelText: '操作系统 / 终端平台 *',
                                border: OutlineInputBorder(),
                                isDense: true,
                              ),
                              items: const [
                                DropdownMenuItem(
                                    value: 'windows',
                                    child: Text('Windows (桌面收银端)'),
                                ),
                                DropdownMenuItem(
                                    value: 'android',
                                    child: Text('Android (移动运营/POS)'),
                                ),
                                DropdownMenuItem(
                                    value: 'ios',
                                    child: Text('iOS (苹果移动端)'),
                                ),
                                DropdownMenuItem(
                                    value: 'desktop',
                                    child: Text('Desktop (桌面运营端)'),
                                ),
                                DropdownMenuItem(
                                    value: 'pos_sunmi',
                                    child: Text('pos_sunmi (商米POS定制端)'),
                                ),
                              ],
                              onChanged: (val) {
                                if (val != null) {
                                  setState(() {
                                    _platform = val;
                                    if (_platform == 'ios') {
                                      _channelController.text = 'mobile';
                                      _installMode = 'store_redirect';
                                    } else if (_platform == 'android') {
                                      _channelController.text = 'mobile';
                                      _installMode = 'interactive';
                                    } else if (_platform == 'windows' ||
                                        _platform == 'desktop') {
                                      _channelController.text = 'pos';
                                      _installMode = 'silent';
                                    } else if (_platform == 'pos_sunmi') {
                                      _channelController.text = 'pos';
                                      _installMode = 'silent';
                                    }
                                  });
                                }
                              },
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: TextFormField(
                              controller: _channelController,
                              decoration: const InputDecoration(
                                labelText: '渠道标识 (channel) *',
                                border: OutlineInputBorder(),
                                isDense: true,
                              ),
                              validator: (val) =>
                                  val == null || val.trim().isEmpty
                                      ? '渠道标识不能为空'
                                      : null,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      Row(
                        children: [
                          Expanded(
                            child: TextFormField(
                              controller: _latestController,
                              decoration: const InputDecoration(
                                labelText: '最新版本号 (SemVer, 如 2.1.0) *',
                                border: OutlineInputBorder(),
                                isDense: true,
                              ),
                              validator: (val) {
                                if (val == null || val.trim().isEmpty) {
                                  return '最新版本号不能为空';
                                }
                                if (!RegExp(r'^\d+(\.\d+)+.*$',
                                )
                                    .hasMatch(val.trim())) {
                                  return '格式必须符合语义化版本 (如 2.1.0)';
                                }
                                return null;
                              },
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: TextFormField(
                              controller: _versionCodeController,
                              keyboardType: TextInputType.number,
                              decoration: const InputDecoration(
                                labelText: '构建号 (versionCode) *',
                                border: OutlineInputBorder(),
                                isDense: true,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      Row(
                        children: [
                          Expanded(
                            child: TextFormField(
                              controller: _minSupportedController,
                              decoration: const InputDecoration(
                                labelText: '最低兼容版本 (minSupported)',
                                border: OutlineInputBorder(),
                                isDense: true,
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: DropdownButtonFormField<String>(
                              isExpanded: true,
                              initialValue: _installMode,
                              decoration: const InputDecoration(
                                labelText: '安装执行模式 *',
                                border: OutlineInputBorder(),
                                isDense: true,
                              ),
                              items: const [
                                DropdownMenuItem(
                                    value: 'silent',
                                    child: Text('silent (后台静默更新)'),
                                ),
                                DropdownMenuItem(
                                    value: 'interactive',
                                    child: Text('interactive (系统交互弹窗)'),
                                ),
                                DropdownMenuItem(
                                    value: 'store_redirect',
                                    child: Text('store_redirect (应用市场落地)'),
                                ),
                              ],
                              onChanged: (val) {
                                if (val != null) {
                                  setState(() => _installMode = val);
                                }
                              },
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      Row(
                        children: [
                          Expanded(
                            child: SwitchListTile(
                              title: const Text('强制升级 (FORCE)'),
                              subtitle: const Text('开启后低于该版本的端侧将被模态全屏阻断'),
                              value: _forceUpdate,
                              onChanged: (val) =>
                                  setState(() => _forceUpdate = val),
                            ),
                          ),
                          Expanded(
                            child: SwitchListTile(
                              title: const Text('启用状态 (Enabled)'),
                              value: _enabled,
                              onChanged: (val) => setState(() => _enabled = val),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      TextFormField(
                        controller: _grayShopIdsController,
                        decoration: const InputDecoration(
                          labelText: '灰度门店名单 (逗号分隔，如 1,2；留空代表全门店生效)',
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                      ),
                      const SizedBox(height: 14),
                      Container(
                        key: const Key('box-package-uploader'),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: context.cashier.subtle,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: context.cashier.border),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.cloud_upload_outlined, color: context.cashier.selected, size: 28,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    '上传安装/更新包文件 (v1.2.309 自动提取元数据)',
                                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    _uploadedFileName != null
                                        ? '已上传: $_uploadedFileName'
                                        : '支持 .exe, .apk, .msi, .zip 等格式，自动提取哈希、文件大小与下载直链',
                                    style: TextStyle(fontSize: 12, color: context.cashier.inkSecondary,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 12),
                            if (_isUploading)
                              const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2,
                                ),
                              )
                            else
                              ElevatedButton.icon(
                                key: const Key('btn-pick-and-upload-package'),
                                onPressed: _handlePickAndUploadPackage,
                                icon: const Icon(Icons.file_upload, size: 16),
                                label: Text(_uploadedFileName != null ? '重新上传' : '选择安装包',
                                ),
                              ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 14),
                      TextFormField(
                        controller: _downloadUrlController,
                        decoration: InputDecoration(
                          labelText: '安装包下载地址 / App Store 链接',
                          border: const OutlineInputBorder(),
                          isDense: true,
                          suffixIcon: _isVerifyingUrl
                              ? const Padding(
                                  padding: EdgeInsets.all(12),
                                  child: SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(strokeWidth: 2,
                                    ),
                                  ),
                                )
                              : TextButton.icon(
                                  onPressed: _handleVerifyDownloadUrl,
                                  icon: const Icon(Icons.wifi_tethering, size: 16,
                                  ),
                                  label: const Text('探测直链', style: TextStyle(fontSize: 12),
                                  ),
                                ),
                        ),
                      ),
                      const SizedBox(height: 14),
                      Row(
                        children: [
                          Expanded(
                            child: TextFormField(
                              controller: _fileSizeController,
                              keyboardType: TextInputType.number,
                              decoration: const InputDecoration(
                                labelText: '文件大小 (字节)',
                                border: OutlineInputBorder(),
                                isDense: true,
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            flex: 2,
                            child: TextFormField(
                              controller: _sha256Controller,
                              decoration: const InputDecoration(
                                labelText: 'SHA-256 完整性哈希 (64位)',
                                border: OutlineInputBorder(),
                                isDense: true,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      TextFormField(
                        controller: _releaseNotesController,
                        maxLines: 4,
                        decoration: const InputDecoration(
                          labelText: '更新日志与发版说明',
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    OutlinedButton(
                      onPressed:
                          _saving ? null : () => Navigator.of(context).pop(false),
                      child: const Text('取消'),
                    ),
                    const SizedBox(width: 12),
                    FilledButton(
                      key: const Key('btn-submit-version-policy'),
                      onPressed: _saving ? null : _submit,
                      child: _saving
                          ? const SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Text('保存发布策略'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ForbiddenBarrierView extends StatelessWidget {
  const _ForbiddenBarrierView({super.key});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        margin: const EdgeInsets.all(32),
        constraints: const BoxConstraints(maxWidth: 580),
        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 48),
        decoration: BoxDecoration(
          color: context.cashier.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xfffecaca)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 16,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: const BoxDecoration(
                color: Color(0xfffee2e2),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.lock_person_outlined,
                size: 48,
                color: Color(0xffdc2626),
              ),
            ),
            const SizedBox(height: 20),
            const Text(
              '访问受限：无权限访问此模块',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w700,
                color: Color(0xff991b1b),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              '版本管理为系统级发版核心控制中心，根据企业发布与数据安全合规准则，'
              '仅限超级管理员 (admin:super) 权限账号访问与配置。'
              '当前操作员账号权限不足，系统已实施安全阻断。',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                height: 1.6,
                color: context.cashier.inkMuted,
              ),
            ),
            const SizedBox(height: 24),
            OutlinedButton.icon(
              onPressed: () => Navigator.of(context).maybePop(),
              icon: const Icon(Icons.arrow_back, size: 16),
              label: const Text('返回上一页'),
            ),
          ],
        ),
      ),
    );
  }
}
