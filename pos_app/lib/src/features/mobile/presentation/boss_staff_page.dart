import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/admin_api_client.dart';
import '../../../core/api_contract.dart';
import '../../../core/shop_summary.dart';
import '../data/api_providers.dart';
import '../data/auth_state.dart';
import '../design/mobile_components.dart';
import '../design/mobile_metrics.dart';
import '../design/mobile_typography.dart';

/// 员工与权限管理（PRD F07，仅老板，路由侧已守卫 admin:manage）。
///
/// 员工列表 + 覆盖式授权：选择角色与门店（仅当前账号有权访问的门店），
/// 提交需 `confirm=true`（覆盖式，替换该员工全部角色与门店授权，写审计）。
class BossStaffPage extends ConsumerStatefulWidget {
  const BossStaffPage({super.key});

  @override
  ConsumerState<BossStaffPage> createState() => _BossStaffPageState();
}

class _BossStaffPageState extends ConsumerState<BossStaffPage> {
  final _searchController = TextEditingController();
  List<Map<String, Object?>> _employees = const [];
  List<Map<String, Object?>> _roles = const [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final client = ref.read(apiClientProvider);
      final rolesData = await client.get(settingsAccessRolesEndpoint);
      final roles = objectList(rolesData);
      final empsData = await client.get(
        settingsAccessEmployeesEndpoint,
        query: {
          'keyword': _searchController.text.trim(),
          'page': 1,
          'pageSize': 100,
        },
      );
      if (mounted) {
        setState(() {
          _roles = roles;
          _employees = objectList(empsData);
          _loading = false;
        });
      }
    } catch (error) {
      if (mounted) {
        setState(() => _loading = false);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('加载失败：$error')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('员工管理')),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: MobileMetrics.pagePadding.copyWith(top: MobileMetrics.spaceLg),
          children: [
            TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: '搜索员工姓名/账号',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: IconButton(
                  tooltip: '搜索',
                  onPressed: _load,
                  icon: const Icon(Icons.arrow_forward),
                ),
                border: const OutlineInputBorder(),
              ),
              onSubmitted: (_) => _load(),
            ),
            const SizedBox(height: MobileMetrics.spaceMd),
            if (_loading)
              const LoadingSkeleton(height: 240)
            else if (_employees.isEmpty)
              const EmptyState(message: '暂无员工，请输入关键字搜索')
            else
              Card(
                child: Column(
                  children: [
                    for (final emp in _employees) _employeeTile(context, emp),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _employeeTile(BuildContext context, Map<String, Object?> emp) {
    String s(Object? v) => v == null ? '' : '$v';
    int i(Object? v) => v is num ? v.toInt() : int.tryParse('$v') ?? 0;
    final adminId = i(emp['adminId'] ?? emp['admin_id'] ?? emp['id']);
    final name = s(emp['userName'] ?? emp['username'] ?? emp['name'] ?? '员工');
    final roles = emp['roles'];
    final roleLabels = roles is List
        ? roles.map((r) => s(r is Map ? r['roleName'] : r)).where((x) => x.isNotEmpty).toList()
        : <String>[];
    final shops = emp['shops'];
    final shopCount = shops is List ? shops.length : 0;
    return ListTile(
      title: Text(name),
      subtitle: Text(
        [if (roleLabels.isNotEmpty) roleLabels.join('、'), if (shopCount > 0) '$shopCount 家门店']
            .join(' · '),
        style: context.captionStyle,
      ),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => _openGrant(context, emp, adminId, name),
    );
  }

  Future<void> _openGrant(
    BuildContext context,
    Map<String, Object?> emp,
    int adminId,
    String name,
  ) async {
    final auth = ref.read(authProvider);
    final shops = auth.shops;
    // 当前员工已选角色/门店（用于默认勾选）
    final currentRoleIds = _ids(emp['roles']);
    final currentShopIds = _ids(emp['shops']);
    final roleIds = <int>{...currentRoleIds};
    final shopIds = <int>{...currentShopIds};

    final result = await showModalBottomSheet<_GrantResult>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(MobileMetrics.radiusSheet)),
      ),
      builder: (sheetContext) => _GrantSheet(
        name: name,
        roles: _roles,
        shops: shops,
        roleIds: roleIds,
        shopIds: shopIds,
        onChanged: (r, s) {
          roleIds
            ..clear()
            ..addAll(r);
          shopIds
            ..clear()
            ..addAll(s);
        },
      ),
    );
    if (result == null || !mounted) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('覆盖式授权确认'),
        content: Text(
          '将替换「$name」的全部角色与门店授权（${result.roleLabels.join('、')}）。\n'
          '此操作将立即生效并写入审计日志，是否继续？',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('确认授权'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    try {
      final client = ref.read(apiClientProvider);
      await client.post(
        settingsAccessEmployeesEndpoint,
        body: {
          'adminId': adminId,
          'roleIds': result.roleIds.toList(),
          'shopIds': result.shopIds.toList(),
          'confirm': true,
        },
      );
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('授权已更新')));
        _load();
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('授权失败：$error')));
      }
    }
  }

  Set<int> _ids(Object? value) {
    if (value is! List) return <int>{};
    return value
        .map((v) => v is Map ? (v['roleId'] ?? v['id'] ?? v['shopId']) : v)
        .whereType<num>()
        .map((n) => n.toInt())
        .toSet();
  }
}

class _GrantResult {
  const _GrantResult({
    required this.roleIds,
    required this.shopIds,
    required this.roleLabels,
  });

  final Set<int> roleIds;
  final Set<int> shopIds;
  final List<String> roleLabels;
}

class _GrantSheet extends StatefulWidget {
  const _GrantSheet({
    required this.name,
    required this.roles,
    required this.shops,
    required this.roleIds,
    required this.shopIds,
    required this.onChanged,
  });

  final String name;
  final List<Map<String, Object?>> roles;
  final List<ShopSummary> shops;
  final Set<int> roleIds;
  final Set<int> shopIds;
  final void Function(Set<int> roleIds, Set<int> shopIds) onChanged;

  @override
  State<_GrantSheet> createState() => _GrantSheetState();
}

class _GrantSheetState extends State<_GrantSheet> {
  late final Set<int> _roleIds = {...widget.roleIds};
  late final Set<int> _shopIds = {...widget.shopIds};

  @override
  Widget build(BuildContext context) {
    String s(Object? v) => v == null ? '' : '$v';
    int i(Object? v) => v is num ? v.toInt() : int.tryParse('$v') ?? 0;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.all(MobileMetrics.spaceLg),
            child: Row(
              children: [
                Expanded(
                  child: Text('为「${widget.name}」授权', style: MobileTypography.sectionTitle),
                ),
                IconButton(
                  tooltip: '关闭',
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Flexible(
            child: ListView(
              shrinkWrap: true,
              padding: const EdgeInsets.fromLTRB(
                MobileMetrics.spaceLg,
                MobileMetrics.spaceMd,
                MobileMetrics.spaceLg,
                MobileMetrics.spaceLg,
              ),
              children: [
                Text('角色（多选）', style: MobileTypography.label),
                const SizedBox(height: MobileMetrics.spaceSm),
                for (final role in widget.roles) ...[
                  CheckboxListTile(
                    dense: true,
                    title: Text(s(role['roleName'] ?? role['name'])),
                    subtitle: Text(s(role['roleCode'])),
                    value: _roleIds.contains(i(role['id'] ?? role['roleId'])),
                    onChanged: (checked) => setState(() {
                      final id = i(role['id'] ?? role['roleId']);
                      if (checked == true) {
                        _roleIds.add(id);
                      } else {
                        _roleIds.remove(id);
                      }
                      _notify();
                    }),
                  ),
                ],
                const SizedBox(height: MobileMetrics.spaceLg),
                Text('门店（仅授权范围内）', style: MobileTypography.label),
                const SizedBox(height: MobileMetrics.spaceSm),
                for (final shop in widget.shops) ...[
                  CheckboxListTile(
                    dense: true,
                    title: Text(shop.name),
                    value: _shopIds.contains(shop.id),
                    onChanged: (checked) => setState(() {
                      if (checked == true) {
                        _shopIds.add(shop.id);
                      } else {
                        _shopIds.remove(shop.id);
                      }
                      _notify();
                    }),
                  ),
                ],
              ],
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.all(MobileMetrics.spaceLg),
              child: FilledButton(
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(MobileMetrics.buttonHeightCta),
                ),
                onPressed: () {
                  final roleLabels = widget.roles
                      .where((r) => _roleIds.contains(i(r['id'] ?? r['roleId'])))
                      .map((r) => s(r['roleName'] ?? r['name']))
                      .where((x) => x.isNotEmpty)
                      .toList();
                  Navigator.of(context).pop(
                    _GrantResult(
                      roleIds: _roleIds,
                      shopIds: _shopIds,
                      roleLabels: roleLabels,
                    ),
                  );
                },
                child: const Text('下一步：确认'),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _notify() {
    widget.onChanged(_roleIds, _shopIds);
  }

  int i(Object? v) => v is num ? v.toInt() : int.tryParse('$v') ?? 0;
}
