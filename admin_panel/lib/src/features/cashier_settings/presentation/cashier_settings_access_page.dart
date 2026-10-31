import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';

import '../../auth/data/access_approval_repository.dart';
import '../../auth/domain/access_approval_models.dart';
import '../data/cashier_settings_repository.dart';
import '../domain/cashier_settings.dart';
import 'cashier_settings_shared.dart';
import '../../cashier_shell/presentation/cashier_tokens.dart';

/// 员工权限（设置 → 员工权限）。
///
/// 8 个分区（SectionSpec）：员工 / 角色 / 权限矩阵 / 接口权限映射 /
/// 权限码管理 / 多店授权 / 变更记录 / 审批记录。全部数据来自真实接口（openapi.yaml），
/// 不包含 mock；授权、删除等敏感操作统一走二次确认并提交 confirm=true。
class CashierSettingsAccessEvaluatePage extends StatefulWidget {
  const CashierSettingsAccessEvaluatePage({
    super.key,
    required this.repository,
    required this.section,
    this.approvalRepository,
  });

  final CashierSettingsRepository repository;
  final SettingsSectionSpec section;

  /// 审批记录数据源（POST /cashier/access/authorize 与
  /// GET /admin/access/approvals 的统一审批中心仓库）。
  final AccessApprovalRepository? approvalRepository;

  @override
  State<CashierSettingsAccessEvaluatePage> createState() =>
      _CashierSettingsAccessEvaluatePageState();
}

class _CashierSettingsAccessEvaluatePageState
    extends State<CashierSettingsAccessEvaluatePage> {
  @override
  Widget build(BuildContext context) {
    final repository = widget.repository;
    return switch (widget.section.id) {
      'employees' => _EmployeesSection(key: const ValueKey('access-employees'), repository: repository,
      ),
      'roles' => _RolesSection(key: const ValueKey('access-roles'), repository: repository,
      ),
      'matrix' => _MatrixSection(key: const ValueKey('access-matrix'), repository: repository,
      ),
      'api-permissions' => _ApiPermissionsSection(key: const ValueKey('access-api-permissions'), repository: repository,
      ),
      'permission-codes' => _PermissionCodesSection(key: const ValueKey('access-permission-codes'), repository: repository,
      ),
      'policies' => _PoliciesSection(key: const ValueKey('access-policies'), repository: repository,
      ),
      'shops' => _ShopsSection(key: const ValueKey('access-shops'), repository: repository,
      ),
      'changes' => _ChangesSection(key: const ValueKey('access-changes'), repository: repository,
      ),
      'approvals' => widget.approvalRepository == null
          ? const _ApprovalsUnavailable()
          : _ApprovalsSection(
              key: const ValueKey('access-approvals'),
              repository: widget.approvalRepository!,
            ),
      _ => const SizedBox.shrink(),
    };
  }
}

// ============================================================
// 员工
// ============================================================

class _EmployeesSection extends StatefulWidget {
  const _EmployeesSection({super.key, required this.repository});

  final CashierSettingsRepository repository;

  @override
  State<_EmployeesSection> createState() => _EmployeesSectionState();
}

class _EmployeesSectionState extends State<_EmployeesSection> {
  static const _pageSize = 10;

  final _keywordController = TextEditingController();
  var _page = 1;
  var _total = 0;
  var _items = <CashierAccessEmployee>[];
  var _loading = true;
  Object? _error;

  var _roles = <CashierAccessRole>[];
  var _shops = <CashierShopRef>[];
  var _admins = <CashierAdministrator>[];
  var _adminsError = false;

  @override
  void initState() {
    super.initState();
    _load();
    _loadReferenceData();
  }

  @override
  void dispose() {
    _keywordController.dispose();
    super.dispose();
  }

  Future<void> _loadReferenceData() async {
    List<CashierAccessRole>? roles;
    List<CashierShopRef>? shops;
    List<CashierAdministrator>? admins;
    var adminsFailed = false;
    try {
      final results = await Future.wait([
        widget.repository.loadAccessRoles(),
        widget.repository.loadShopList(),
      ]);
      roles = results[0] as List<CashierAccessRole>;
      shops = results[1] as List<CashierShopRef>;
    } catch (_) {
      roles = const [];
      shops = const [];
    }
    try {
      final page = await widget.repository.loadAdministrators();
      admins = page.items;
    } catch (_) {
      adminsFailed = true;
    }
    if (!mounted) return;
    setState(() {
      _roles = roles!;
      _shops = shops!;
      _admins = admins ?? const [];
      _adminsError = adminsFailed;
    });
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final result = await widget.repository.loadAccessEmployees(
        keyword: _keywordController.text.trim(),
        page: _page,
        pageSize: _pageSize,
      );
      if (!mounted) return;
      setState(() {
        _items = result.items;
        _total = result.total;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error;
        _loading = false;
      });
    }
  }

  Future<void> _refresh() async {
    await Future.wait([_load(), _loadReferenceData()]);
  }

  void _goPage(int page) {
    if (page < 1 || page > _maxPage) return;
    setState(() => _page = page);
    _load();
  }

  int get _maxPage => (_total / _pageSize).ceil().clamp(1, 1 << 31);



  Future<void> _openAssign({CashierAccessEmployee? employee}) async {
    if (_roles.isEmpty && !_loading) {
      await _loadReferenceData();
    }
    if (!mounted) return;
    final saved = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => _AssignEmployeeDialog(
        repository: widget.repository,
        roles: _roles,
        shops: _shops,
        admins: _admins,
        adminsLoadFailed: _adminsError,
        employee: employee,
        onAssign: (adminId, roleIds, shopIds) async {
          await widget.repository.assignAccessEmployee(
            adminId: adminId,
            roleIds: roleIds,
            shopIds: shopIds,
            confirm: true,
          );
        },
      ),
    );
    if (saved == true && mounted) {
      showSettingsSaved(context, '员工授权已更新');
      await _refresh();
    }
  }

  Future<void> _openCreateOrEditProfile({CashierAccessEmployee? employee,
  }) async {
    if (_roles.isEmpty && !_loading) {
      await _loadReferenceData();
    }
    if (!mounted) return;
    final saved = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => _CreateOrEditEmployeeProfileDialog(
        repository: widget.repository,
        roles: _roles,
        shops: _shops,
        employee: employee,
      ),
    );
    if (saved == true && mounted) {
      showSettingsSaved(
        context,
        employee == null ? '员工档案已创建' : '员工档案已更新');
      await _refresh();
    }
  }

  Future<void> _openDeleteEmployee(CashierAccessEmployee employee) async {
    final deleted = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => _DeleteEmployeeConfirmDialog(
        repository: widget.repository,
        employee: employee,
      ),
    );
    if (deleted == true && mounted) {
      showSettingsSaved(context, '员工账号已删除');
      await _refresh();
    }
  }

  @override
  Widget build(BuildContext context) {
    final roleCount = _roles.length;
    final shopIds = <int>{};
    for (final item in _items) {
      shopIds.addAll(item.shops);
    }
    return ListView(
      key: const PageStorageKey('access-employees'),
      padding: const EdgeInsets.all(20),
      children: [
        _AccessPageHeader(
          title: '员工列表与授权管理',
          subtitle: '支持一人多店与一人多角色；支持新建员工档案、维护岗位姓名、调整授权、四态管控（启用/停用/离职/锁定）、强制下线、查看有效权限及注销员工账号。',
          actions: [
            _ToolbarButton(
              key: const Key('access-employees-refresh'),
              icon: Icons.refresh,
              label: '刷新',
              onPressed: _loading ? null : _refresh,
            ),
            _ToolbarButton(
              key: const Key('access-employees-create'),
              icon: Icons.person_add_alt_1,
              label: '新建员工档案',
              primary: true,
              onPressed: _loading ? null : () => _openCreateOrEditProfile(),
            ),
            _ToolbarButton(
              key: const Key('access-employees-assign'),
              icon: Icons.assignment_ind_outlined,
              label: '授权员工',
              primary: false,
              onPressed: _loading ? null : () => _openAssign(),
            ),
          ],
        ),
        const SizedBox(height: 16),
        _StatsStrip(
          items: [
            _StatItem(label: '员工总数', value: '$_total'),
            _StatItem(label: '当前页', value: '第 $_page 页 / 共 $_total 人', small: true,
            ),
            _StatItem(label: '角色数', value: '$roleCount'),
            _StatItem(label: '覆盖门店', value: '${shopIds.length}'),
          ],
        ),
        const SizedBox(height: 14),
        Row(
          children: [
            Expanded(
              child: SizedBox(
                height: 48,
                child: TextField(
                  key: const Key('access-employees-search'),
                  controller: _keywordController,
                  decoration: InputDecoration(
                    hintText: '搜索员工姓名 / 账号（keyword）',
                    prefixIcon: const Icon(Icons.search, size: 20),
                    filled: true,
                    fillColor: Colors.white,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide(color: context.cashier.border),
                    ),
                    isDense: true,
                  ),
                  onSubmitted: (_) {
                    setState(() => _page = 1);
                    _load();
                  },
                ),
              ),
            ),
            const SizedBox(width: 10),
            SizedBox(
              height: 48,
              child: FilledButton(
                key: const Key('access-employees-search-btn'),
                onPressed: () {
                  setState(() => _page = 1);
                  _load();
                },
                style: FilledButton.styleFrom(
                  backgroundColor: context.cashier.ink,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                child: const Text('搜索'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        if (_loading)
          const SettingsSkeletonLoader(rows: 4)
        else if (_error != null)
          SettingsErrorState(message: '$_error', onRetry: _load)
        else if (_items.isEmpty)
          const SettingsEmptyState(title: '暂无员工', description: '点击右上角「授权员工」为现有账号分配角色与门店。',
          )
        else
          ..._items.map(_buildEmployeeRow),
        const SizedBox(height: 14),
        if (_total > _pageSize)
          _PaginationBar(
            page: _page,
            total: _total,
            pageSize: _pageSize,
            onPrevious: _page > 1 ? () => _goPage(_page - 1) : null,
            onNext: _page < _maxPage ? () => _goPage(_page + 1) : null,
          ),
      ],
    );
  }

  Widget _buildEmployeeRow(CashierAccessEmployee employee) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(18),
      decoration: _surface(context),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          CircleAvatar(
            radius: 20,
            backgroundColor: context.cashier.selectedBackground,
            child: Text(
              employee.realName.isNotEmpty
                  ? employee.realName.substring(0, 1)
                  : (employee.userName.isEmpty
                      ? '#'
                      : employee.userName.substring(0, 1)),
              style: const TextStyle(
                color: Color(0xff075985),
                fontWeight: FontWeight.w700,
                fontSize: 15,
              ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            flex: 1,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 6,
                  runSpacing: 2,
                  children: [
                    Text(
                      employee.realName.isNotEmpty
                          ? employee.realName
                          : employee.userName,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    _EmployeeStatusBadge(status: employee.accountStatus),
                    if (employee.jobTitle.isNotEmpty)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 1,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xfffff1ed),
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(color: const Color(0xffffdcd3)),
                        ),
                        child: Text(
                          employee.jobTitle,
                          style: const TextStyle(
                            fontSize: 11,
                            color: Color(0xffed3d08),
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  '${employee.workNo.isNotEmpty ? '${employee.workNo} · ' : ''}${employee.userName} (ID ${employee.adminId}) · 权限 v${employee.permissionVersion}'
                      '${employee.lastLoginAt != null ? ' · 最近登录 ${_formatLoginTime(employee.lastLoginAt!)}' : ''}',
                  style: TextStyle(
                    fontSize: 12,
                    color: context.cashier.inkMuted,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          Expanded(
            flex: 2,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _TagRow(
                  label: '角色',
                  chips: [
                    for (final role in employee.roles)
                      _AccessChip(
                        text: role.roleName.isEmpty
                            ? role.roleCode
                            : '${role.roleName} ${role.roleCode}',
                        accent: true,
                      ),
                  ],
                ),
                const SizedBox(height: 6),
                _TagRow(
                  label: '门店',
                  chips: [
                    for (final shopId in employee.shops)
                      _AccessChip(text: _shopName(shopId), shop: true),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          TextButton(
            key: Key('access-employee-profile-${employee.adminId}'),
            onPressed: () => _openCreateOrEditProfile(employee: employee),
            child: const Text('编辑档案'),
          ),
          TextButton(
            key: Key('access-employee-edit-${employee.adminId}'),
            onPressed: () => _openAssign(employee: employee),
            child: const Text('调整授权'),
          ),
          PopupMenuButton<String>(
            key: Key('access-employee-more-${employee.adminId}'),
            tooltip: '更多操作',
            onSelected: (value) => _onEmployeeMenuSelected(employee, value),
            itemBuilder: (context) => _employeeMenuItems(employee),
          ),
          TextButton(
            key: Key('access-employee-delete-${employee.adminId}'),
            style: TextButton.styleFrom(
              foregroundColor: context.cashier.danger,
            ),
            onPressed: () => _openDeleteEmployee(employee),
            child: const Text('删除'),
          ),
        ],
      ),
    );
  }

  List<PopupMenuEntry<String>> _employeeMenuItems(
    CashierAccessEmployee employee,
  ) {
    final status = employee.accountStatus;
    final entries = <PopupMenuEntry<String>>[];
    if (status != CashierAccessEmployeeStatus.active) {
      entries.add(
        const PopupMenuItem(
          value: 'enable',
          child: Text('启用账号')));
    }
    if (status == CashierAccessEmployeeStatus.active) {
      entries.add(
        const PopupMenuItem(
          value: 'disable',
          child: Text('停用账号')));
      entries.add(
        const PopupMenuItem(
          value: 'resign',
          child: Text('标记离职')));
    }
    if (status == CashierAccessEmployeeStatus.locked) {
      entries.add(
        const PopupMenuItem(
          value: 'unlock',
          child: Text('解锁账号')));
    }
    if (entries.isNotEmpty) entries.add(const PopupMenuDivider());
    entries.add(
      const PopupMenuItem(
        value: 'force_logout',
        child: Text('强制下线')),
    );
    entries.add(
      const PopupMenuItem(
        value: 'effective_permissions',
        child: Text('查看有效权限'),
      ),
    );
    return entries;
  }

  Future<void> _onEmployeeMenuSelected(
    CashierAccessEmployee employee,
    String value,
  ) async {
    switch (value) {
      case 'enable':
        await _openStatusChange(
          employee,
          CashierAccessEmployeeStatus.active,
          '启用',
          '启用后该员工可正常登录收银端。确定启用「${_employeeDisplayName(employee)}」吗？',
        );
        break;
      case 'disable':
        await _openStatusChange(
          employee,
          CashierAccessEmployeeStatus.disabled,
          '停用',
          '停用后该员工所有会话将立即失效，无法登录收银端。确定停用「${_employeeDisplayName(employee)}」吗？',
        );
        break;
      case 'resign':
        await _openStatusChange(
          employee,
          CashierAccessEmployeeStatus.resigned,
          '标记离职',
          '离职后该员工所有会话将立即失效，历史业务记录仍保留。确定标记「${_employeeDisplayName(employee)}」为离职吗？',
        );
        break;
      case 'unlock':
        await _openStatusChange(
          employee,
          CashierAccessEmployeeStatus.active,
          '解锁',
          '解锁后该员工可重新尝试登录。确定解锁「${_employeeDisplayName(employee)}」吗？',
        );
        break;
      case 'force_logout':
        await _openForceLogout(employee);
        break;
      case 'effective_permissions':
        await _openEffectivePermissions(employee);
        break;
    }
  }

  String _employeeDisplayName(CashierAccessEmployee employee) =>
      employee.realName.isNotEmpty ? employee.realName : employee.userName;

  Future<void> _openStatusChange(
    CashierAccessEmployee employee,
    String status,
    String actionLabel,
    String message,
  ) async {
    final changed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => _EmployeeStatusChangeDialog(
        repository: widget.repository,
        employee: employee,
        status: status,
        actionLabel: actionLabel,
        message: message,
      ),
    );
    if (changed == true && mounted) {
      showSettingsSaved(
        context,
        '已$actionLabel「${_employeeDisplayName(employee)}」· 权限版本已更新',
      );
      await _refresh();
    }
  }

  Future<void> _openForceLogout(CashierAccessEmployee employee) async {
    final displayName = _employeeDisplayName(employee);
    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.logout, color: Color(0xffb91c1c), size: 24),
            SizedBox(width: 10),
            Text('强制下线'),
          ],
        ),
        content: Text(
          '将强制下线「$displayName」的全部活跃会话，其已签发的所有令牌即刻作废，'
          '该员工需重新登录后才能继续使用收银端。确定执行吗？',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            key: const Key('employee-force-logout-confirm'),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('强制下线'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      await widget.repository.forceLogoutEmployee(adminId: employee.adminId);
      if (!mounted) return;
      showSettingsSaved(context, '已强制下线「$displayName」，会话已全部失效');
      await _refresh();
    } catch (error) {
      if (!mounted) return;
      showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('强制下线失败'),
          content: Text('$error'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('知道了'),
            ),
          ],
        ),
      );
    }
  }

  Future<void> _openEffectivePermissions(CashierAccessEmployee employee) async {
    await showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (context) => _EffectivePermissionsDialog(
        repository: widget.repository,
        employee: employee,
        shopName: (id) => _shopName(id),
      ),
    );
  }

  String _shopName(int id) {
    for (final s in _shops) {
      if (s.id == id) return s.name;
    }
    return '门店#$id';
  }

  String _formatLoginTime(DateTime time) {
    final local = time.toLocal();
    String two(int v) => v.toString().padLeft(2, '0');
    return '${local.year}-${two(local.month)}-${two(local.day)} '
        '${two(local.hour)}:${two(local.minute)}';
  }
}

/// 员工账号状态徽标（ACTIVE/DISABLED/RESIGNED/LOCKED）。
class _EmployeeStatusBadge extends StatelessWidget {
  const _EmployeeStatusBadge({required this.status});

  final String status;

  @override
  Widget build(BuildContext context) {
    final (Color bg, Color fg, Color border) = switch (status) {
      CashierAccessEmployeeStatus.active => (
          const Color(0xffe7f6ec),
          const Color(0xff15803d),
          const Color(0xffbbf7d0),
        ),
      CashierAccessEmployeeStatus.disabled => (
          const Color(0xfffff7e6),
          const Color(0xffb45309),
          const Color(0xfffde68a),
        ),
      CashierAccessEmployeeStatus.resigned => (
          const Color(0xfff1f5f9),
          const Color(0xff64748b),
          const Color(0xffcbd5e1),
        ),
      CashierAccessEmployeeStatus.locked => (
          const Color(0xfffee2e2),
          const Color(0xffb91c1c),
          const Color(0xfffecaca),
        ),
      _ => (
          const Color(0xfff1f5f9),
          const Color(0xff64748b),
          const Color(0xffcbd5e1),
        ),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: border),
      ),
      child: Text(
        CashierAccessEmployeeStatus.label(status),
        style: TextStyle(
          fontSize: 11,
          color: fg,
          fontWeight: FontWeight.w600),
      ),
    );
  }
}

/// 员工状态变更确认弹窗（启用/停用/离职/解锁）。
class _EmployeeStatusChangeDialog extends StatefulWidget {
  const _EmployeeStatusChangeDialog({
    required this.repository,
    required this.employee,
    required this.status,
    required this.actionLabel,
    required this.message,
  });

  final CashierSettingsRepository repository;
  final CashierAccessEmployee employee;
  final String status;
  final String actionLabel;
  final String message;

  @override
  State<_EmployeeStatusChangeDialog> createState() =>
      _EmployeeStatusChangeDialogState();
}

class _EmployeeStatusChangeDialogState
    extends State<_EmployeeStatusChangeDialog> {
  var _submitting = false;
  Object? _error;

  Future<void> _handleSubmit() async {
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      await widget.repository.updateEmployeeStatus(
        adminId: widget.employee.adminId,
        status: widget.status,
      );
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _error = _friendlyStatusError(error);
      });
    }
  }

  String _friendlyStatusError(Object error) {
    final text = '$error';
    if (text.contains('不能对当前登录账号') || text.contains('当前登录账号')) {
      return '安全保护：不能对当前登录账号执行停用或注销操作。';
    }
    return text;
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Row(
        children: [
          Icon(Icons.settings_suggest, color: context.cashier.danger, size: 24),
          const SizedBox(width: 10),
          Text('${widget.actionLabel}员工'),
        ],
      ),
      content: SizedBox(
        width: 440,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.message),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: const Color(0xfffee2e2),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  '$_error',
                  style: const TextStyle(
                    fontSize: 13,
                    color: Color(0xffb91c1c),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _submitting
              ? null
              : () => Navigator.of(context).pop(false),
          child: const Text('取消'),
        ),
        FilledButton(
          key: Key('employee-status-confirm-${widget.employee.adminId}'),
          onPressed: _submitting ? null : _handleSubmit,
          child: _submitting
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Text(widget.actionLabel),
        ),
      ],
    );
  }
}

/// 员工最终有效权限查看弹窗（角色命中 + 权限码 + ALLOW/DENY 覆盖）。
class _EffectivePermissionsDialog extends StatefulWidget {  const _EffectivePermissionsDialog({
    required this.repository,
    required this.employee,
    required this.shopName,
  });

  final CashierSettingsRepository repository;
  final CashierAccessEmployee employee;
  final String Function(int shopId) shopName;

  @override
  State<_EffectivePermissionsDialog> createState() =>
      _EffectivePermissionsDialogState();
}

class _EffectivePermissionsDialogState
    extends State<_EffectivePermissionsDialog> {
  int? _shopId;
  CashierEffectivePermissions? _result;
  Object? _error;
  var _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final result = await widget.repository.loadEffectivePermissions(
        adminId: widget.employee.adminId,
        shopId: _shopId,
      );
      if (!mounted) return;
      setState(() {
        _result = result;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final employee = widget.employee;
    return AlertDialog(
      title: Row(
        children: [
          const Icon(Icons.verified_user, color: Color(0xff075985), size: 24),
          const SizedBox(width: 10),
          const Text('有效权限'),
        ],
      ),
      content: SizedBox(
        width: 560,
        child: _loading
            ? const Padding(
                padding: EdgeInsets.all(24),
                child: Center(child: CircularProgressIndicator()),
              )
            : _error != null
                ? Padding(
                    padding: const EdgeInsets.all(12),
                    child: Text('加载失败：$_error'),
                  )
                : _buildResult(context, employee),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('关闭'),
        ),
      ],
    );
  }

  Widget _buildResult(BuildContext context, CashierAccessEmployee employee) {
    final result = _result!;
    final shops = employee.shops;
    return SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            '${result.realName.isNotEmpty ? result.realName : result.userName} '
            '(ID ${result.adminId}) · 权限 v${result.permissionVersion}',
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 10),
          if (shops.isNotEmpty) ...[
            Row(
              children: [
                const Text('门店范围', style: TextStyle(fontSize: 13)),
                const SizedBox(width: 12),
                DropdownButton<int?>(
                  value: _shopId,
                  hint: const Text('全部门店'),
                  items: [
                    const DropdownMenuItem<int?>(
                      value: null,
                      child: Text('全部门店'),
                    ),
                    for (final shopId in shops)
                      DropdownMenuItem<int?>(
                        value: shopId,
                        child: Text(widget.shopName(shopId)),
                      ),
                  ],
                  onChanged: (value) {
                    setState(() => _shopId = value);
                    _load();
                  },
                ),
              ],
            ),
            const SizedBox(height: 10),
          ],
          _InfoBlock(
            title: '角色（${result.roles.length}）',
            child: result.roles.isEmpty
                ? const Text('未绑定角色', style: TextStyle(fontSize: 13))
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (final role in result.roles)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 2),
                          child: Text(
                            '${role.roleName.isEmpty ? role.roleCode : '${role.roleName} (${role.roleCode})'}',
                            style: const TextStyle(fontSize: 13),
                          ),
                        ),
                    ],
                  ),
          ),
          const SizedBox(height: 8),
          _InfoBlock(
            title: 'RBAC 权限码（${result.permissions.length}）',
            child: result.permissions.isEmpty
                ? const Text('无', style: TextStyle(fontSize: 13))
                : Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    children: [
                      for (final code in result.permissions)
                        _AccessChip(text: code),
                    ],
                  ),
          ),
          const SizedBox(height: 8),
          _InfoBlock(
            title: '个性化覆盖（${result.overrides.length}）',
            child: result.overrides.isEmpty
                ? const Text('无显式覆盖', style: TextStyle(fontSize: 13))
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (final override in result.overrides)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 2),
                          child: Text(
                            '${override.effect == CashierAccessPolicyEffect.deny ? '拒绝' : '放行'} '
                            '${override.permissionCode}'
                            '${override.shopId != null ? ' · ${widget.shopName(override.shopId!)}' : ' · 全局'}'
                            '${override.reason.isNotEmpty ? ' · ${override.reason}' : ''}',
                            style: TextStyle(
                              fontSize: 13,
                              color: override.effect ==
                                      CashierAccessPolicyEffect.deny
                                  ? const Color(0xffb91c1c)
                                  : const Color(0xff15803d),
                              fontWeight: FontWeight.w600,
                            ),
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

/// 标题 + 内容的信息块（用于有效权限弹窗分区展示）。
class _InfoBlock extends StatelessWidget {
  const _InfoBlock({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xfff8fafc),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: const Color(0xffe2e8f0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: Color(0xff475569),
            ),
          ),
          const SizedBox(height: 6),
          child,
        ],
      ),
    );
  }
}

// ============================================================
// 角色
// ============================================================

class _RolesSection extends StatefulWidget {
  const _RolesSection({super.key, required this.repository});

  final CashierSettingsRepository repository;

  @override
  State<_RolesSection> createState() => _RolesSectionState();
}

class _RolesSectionState extends State<_RolesSection> {
  var _roles = <CashierAccessRole>[];
  var _permissionCodes = <CashierPermissionCode>[];
  var _loading = true;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final results = await Future.wait([
        widget.repository.loadAccessRoles(),
        widget.repository.loadPermissionCodes(),
      ]);
      if (!mounted) return;
      setState(() {
        _roles = (results[0] as List<CashierAccessRole>);
        _permissionCodes = (results[1] as List<CashierPermissionCode>);
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error;
        _loading = false;
      });
    }
  }

  Future<void> _openRoleDialog({CashierAccessRole? role}) async {
    final saved = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => _RoleEditDialog(
        repository: widget.repository,
        role: role,
        permissionCodes: _permissionCodes,
      ),
    );
    if (saved == true && mounted) {
      showSettingsSaved(context, role == null ? '角色已创建' : '角色已保存');
      await _load();
    }
  }

  Future<void> _deleteRole(CashierAccessRole role) async {
    if (role.adminCount > 0) {
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('无法删除角色'),
          content: Text('角色「${role.roleName}」当前正被 ${role.adminCount} 名员工引用（ROLE_IN_USE）。请先解除关联员工后再删除。',
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('我知道了'),
            ),
          ],
        ),
      );
      return;
    }
    final ok = await showSettingsConfirmDialog(
      context: context,
      title: '删除角色',
      message: '是否确认删除角色「${role.roleName}」（${role.roleCode}）？删除将同时清理其权限绑定，该操作不可撤销。',
      impacts: const ['角色被引用时服务端将拒绝删除（409 ROLE_IN_USE）', '删除记录将写入安全审计日志'],
      destructive: true,
      confirmLabel: '确认删除',
    );
    if (ok != true || !mounted) return;
    try {
      await widget.repository.deleteAccessRole(id: role.id, confirm: true);
      if (!mounted) return;
      showSettingsSaved(context, '角色「${role.roleName}」已删除');
      await _load();
    } catch (error) {
      if (!mounted) return;
      await _showActionError(context, '删除失败', error);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      key: const PageStorageKey('access-roles'),
      padding: const EdgeInsets.all(20),
      children: [
        _AccessPageHeader(
          title: '角色管理',
          subtitle: 'sortOrder 数值小优先级高；被引用角色禁止删除；编辑携带 version 乐观锁并提交 permissionIds（覆盖式绑定权限码）。',
          actions: [
            _ToolbarButton(
              key: const Key('access-roles-refresh'),
              icon: Icons.refresh,
              label: '刷新',
              onPressed: _loading ? null : _load,
            ),
            _ToolbarButton(
              key: const Key('access-roles-create'),
              icon: Icons.add_moderator_outlined,
              label: '新增角色',
              primary: true,
              onPressed: _loading ? null : () => _openRoleDialog(),
            ),
          ],
        ),
        const SizedBox(height: 16),
        if (_loading)
          const SettingsSkeletonLoader(rows: 4)
        else if (_error != null)
          SettingsErrorState(message: '$_error', onRetry: _load)
        else if (_roles.isEmpty)
          const SettingsEmptyState(title: '暂无角色', description: '点击右上角「新增角色」创建第一个角色。',
          )
        else
          ..._roles.map(_buildRoleCard),
      ],
    );
  }

  Widget _buildRoleCard(CashierAccessRole role) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(18),
      decoration: _surface(context),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: context.cashier.row,
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(
              Icons.admin_panel_settings_outlined,
              color: Color(0xff475569),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      role.roleName,
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      role.roleCode,
                      style: TextStyle(
                        fontSize: 12,
                        color: context.cashier.inkMuted,
                        fontFamily: 'monospace',
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: context.cashier.selectedBackground,
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        '优先级 ${role.sortOrder}',
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: Color(0xff075985),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  'v${role.version} · 引用 ${role.adminCount} 名员工',
                  style: TextStyle(fontSize: 13, color: context.cashier.inkMuted,
                  ),
                ),
                if (role.permissions.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      for (final permission in role.permissions)
                        _AccessChip(
                          text: permission.permissionName.isEmpty
                              ? permission.permissionCode
                              : '${permission.permissionName} ${permission.permissionCode}',
                          accent: true,
                        ),
                    ],
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 8),
          TextButton(
            key: Key('access-role-edit-${role.id}'),
            onPressed: () => _openRoleDialog(role: role),
            child: const Text('编辑'),
          ),
          TextButton(
            key: Key('access-role-delete-${role.id}'),
            onPressed: () => _deleteRole(role),
            style: TextButton.styleFrom(
              foregroundColor: context.cashier.danger,
            ),
            child: const Text('删除'),
          ),
        ],
      ),
    );
  }
}

// ============================================================
// 权限矩阵（只读）
// ============================================================

class _MatrixSection extends StatefulWidget {
  const _MatrixSection({super.key, required this.repository});

  final CashierSettingsRepository repository;

  @override
  State<_MatrixSection> createState() => _MatrixSectionState();
}

class _MatrixSectionState extends State<_MatrixSection> {
  var _roles = <CashierAccessRole>[];
  var _permissionCodes = <CashierPermissionCode>[];
  var _loading = true;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final results = await Future.wait([
        widget.repository.loadAccessRoles(),
        widget.repository.loadPermissionCodes(),
      ]);
      if (!mounted) return;
      setState(() {
        _roles = (results[0] as List<CashierAccessRole>);
        _permissionCodes = (results[1] as List<CashierPermissionCode>);
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error;
        _loading = false;
      });
    }
  }

  bool _granted(CashierAccessRole role, int permissionId) {
    for (final p in role.permissions) {
      if (p.id == permissionId) return true;
    }
    return false;
  }

  void _openEvaluate() {
    showDialog<void>(
      context: context,
      builder: (context) => _EvaluateDialog(
        repository: widget.repository,
        permissionCodes: _permissionCodes,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      key: const PageStorageKey('access-matrix'),
      padding: const EdgeInsets.all(20),
      children: [
        _AccessPageHeader(
          title: '权限矩阵',
          subtitle: '角色 × 权限码命中视图（数据来自角色绑定的 permissions，只读）。单员工单权限的精确裁决请使用「权限解释」。',
          actions: [
            _ToolbarButton(
              key: const Key('access-matrix-evaluate'),
              icon: Icons.search,
              label: '权限解释',
              primary: true,
              onPressed: _loading ? null : _openEvaluate,
            ),
          ],
        ),
        const SizedBox(height: 16),
        if (_loading)
          const SettingsSkeletonLoader(rows: 4)
        else if (_error != null)
          SettingsErrorState(message: '$_error', onRetry: _load)
        else if (_roles.isEmpty || _permissionCodes.isEmpty)
          const SettingsEmptyState(title: '暂无矩阵数据', description: '请先在「角色」与「权限码管理」中维护数据。',
          )
        else
          _buildMatrix(context),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: context.cashier.warningBackground,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Text(
            '权限绑定说明：角色权限码在「角色 → 新增/编辑」弹窗中以多选方式维护（保存提交 permissionIds，覆盖式更新）。本矩阵为只读视图，逐格数据来自服务端返回的角色 permissions。',
            style: TextStyle(
              fontSize: 13,
              height: 1.5,
              color: context.cashier.warning,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildMatrix(BuildContext context) {
    final visibleCodes = _permissionCodes.take(12).toList();
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border.all(color: context.cashier.border),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 10),
              child: Text(
                '角色 \\ 权限码',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: context.cashier.inkMuted,
                ),
              ),
            ),
            for (final role in _roles)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10,
                ),
                decoration: BoxDecoration(
                  border: Border(
                    top: BorderSide(color: context.cashier.border),
                  ),
                ),
                child: Row(
                  children: [
                    SizedBox(
                      width: 150,
                      child: Text(
                        '${role.roleName} ${role.roleCode}',
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    for (final code in visibleCodes)
                      SizedBox(
                        width: 64,
                        child: Center(
                          child: _granted(role, code.id ?? 0)
                              ? const Icon(
                                  Icons.check_circle,
                                  size: 16,
                                  color: Color(0xff166534),
                                )
                              : const Icon(
                                  Icons.cancel,
                                  size: 15,
                                  color: const Color(0xffcbd5e1),
                                ),
                        ),
                      ),
                  ],
                ),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
              child: Row(
                children: [
                  for (final code in visibleCodes)
                    SizedBox(
                      width: 64,
                      child: Center(
                        child: Tooltip(
                          message: '${code.permissionName} ${code.permissionCode}',
                          child: Text(
                            code.permissionCode,
                            style: TextStyle(
                              fontSize: 11,
                              color: context.cashier.inkMuted,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ============================================================
// 接口权限映射
// ============================================================

class _ApiPermissionsSection extends StatefulWidget {
  const _ApiPermissionsSection({super.key, required this.repository});

  final CashierSettingsRepository repository;

  @override
  State<_ApiPermissionsSection> createState() => _ApiPermissionsSectionState();
}

class _ApiPermissionsSectionState extends State<_ApiPermissionsSection> {
  var _items = <CashierApiPermission>[];
  var _permissionCodes = <CashierPermissionCode>[];
  var _loading = true;
  var _reloading = false;
  Object? _error;
  var _keyword = '';

  List<CashierApiPermission> get _filteredItems {
    final keyword = _keyword.trim().toLowerCase();
    if (keyword.isEmpty) return _items;
    return [
      for (final item in _items)
        if (item.method.toLowerCase().contains(keyword) ||
            item.pathPattern.toLowerCase().contains(keyword) ||
            item.permissionCode.toLowerCase().contains(keyword) ||
            item.remark.toLowerCase().contains(keyword))
          item,
    ];
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final results = await Future.wait([
        widget.repository.loadApiPermissions(),
        widget.repository.loadPermissionCodes(),
      ]);
      if (!mounted) return;
      setState(() {
        _items = (results[0] as List<CashierApiPermission>);
        _permissionCodes = (results[1] as List<CashierPermissionCode>);
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error;
        _loading = false;
      });
    }
  }

  Future<void> _reload() async {
    setState(() => _reloading = true);
    try {
      await widget.repository.reloadApiPermissions();
      if (!mounted) return;
      showSettingsSaved(context, '内存映射已热刷新');
      await _load();
    } catch (error) {
      if (!mounted) return;
      await _showActionError(context, '热刷新失败', error);
    } finally {
      if (mounted) setState(() => _reloading = false);
    }
  }

  Future<void> _openEdit({CashierApiPermission? item}) async {
    final saved = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => _ApiPermissionEditDialog(
        repository: widget.repository,
        item: item,
        permissionCodes: _permissionCodes,
      ),
    );
    if (saved == true && mounted) {
      showSettingsSaved(context, item == null ? '映射已保存并热生效' : '映射已更新并热生效');
      await _load();
    }
  }

  Future<void> _delete(CashierApiPermission item) async {
    final ok = await showSettingsConfirmDialog(
      context: context,
      title: '删除接口映射',
      message: '即将删除映射 ${item.method} ${item.pathPattern}（${item.permissionCode}）。删除后该接口将失去权限码映射并立即生效。',
      destructive: true,
      confirmLabel: '确认删除',
    );
    if (ok != true || !mounted) return;
    try {
      await widget.repository.deleteApiPermission(item.id ?? 0);
      if (!mounted) return;
      showSettingsSaved(context, '映射已删除');
      await _load();
    } catch (error) {
      if (!mounted) return;
      await _showActionError(context, '删除失败', error);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      key: const PageStorageKey('access-api-permissions'),
      padding: const EdgeInsets.all(20),
      children: [
        _AccessPageHeader(
          title: '接口权限映射',
          subtitle: 'path_pattern → 权限码；同一路径仅一条记录（多方法用 *）。保存/删除即时热生效并写审计。',
          actions: [
            _ToolbarButton(
              key: const Key('access-api-permissions-refresh'),
              icon: Icons.refresh,
              label: '刷新',
              onPressed: _loading ? null : _load,
            ),
            _ToolbarButton(
              key: const Key('access-api-permissions-reload'),
              icon: Icons.sync,
              label: _reloading ? '刷新中…' : '热刷新',
              onPressed: _loading || _reloading ? null : _reload,
            ),
            _ToolbarButton(
              key: const Key('access-api-permissions-create'),
              icon: Icons.add_link,
              label: '新增映射',
              primary: true,
              onPressed: _loading ? null : () => _openEdit(),
            ),
          ],
        ),
        const SizedBox(height: 16),
        SizedBox(
          height: 46,
          child: TextField(
            key: const Key('access-api-permissions-search'),
            onChanged: (value) => setState(() => _keyword = value),
            decoration: InputDecoration(
              hintText: '搜索接口路径 / 权限码 / 方法（keyword）',
              prefixIcon: const Icon(Icons.search, size: 20),
              suffixIcon: _keyword.isEmpty
                  ? null
                  : IconButton(
                      key: const Key('access-api-permissions-search-clear'),
                      icon: const Icon(Icons.clear, size: 18),
                      onPressed: () => setState(() => _keyword = ''),
                    ),
              filled: true,
              fillColor: Colors.white,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(color: context.cashier.border),
              ),
              isDense: true,
            ),
          ),
        ),
        const SizedBox(height: 14),
        if (_loading)
          const SettingsSkeletonLoader(rows: 4)
        else if (_error != null)
          SettingsErrorState(message: '$_error', onRetry: _load)
        else if (_items.isEmpty)
          const SettingsEmptyState(title: '暂无接口映射', description: '点击右上角「新增映射」建立路径到权限码的映射。',
          )
        else if (_filteredItems.isEmpty)
          const SettingsEmptyState(title: '未找到匹配的接口映射', description: '换个关键字试试，或清除搜索条件查看全部映射。',
          )
        else
          _buildTable(context),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: context.cashier.warningBackground,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Text(
            '编辑保存后服务端自动 reload 内存映射并立即生效；手动「热刷新」用于修复数据库直接改动后未生效的场景。',
            style: TextStyle(
              fontSize: 13,
              height: 1.5,
              color: context.cashier.warning,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildTable(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: context.cashier.border),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          const _TableHeader(
            columns: ['方法', '路径模式 path_pattern', '权限码', '备注', '操作'],
          ),
          for (var index = 0; index < _filteredItems.length; index++)
            Container(
              decoration: BoxDecoration(
                border: Border(
                  top: BorderSide(color: context.cashier.border)),
                color: index.isEven ? (Theme.of(context).brightness == Brightness.dark ? context.cashier.surface : Colors.white) : context.cashier.row,
              ),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              child: Row(
                children: [
                  _TableCell(
                    flex: 1,
                    child: _MethodChip(method: _filteredItems[index].method),
                  ),
                  _TableCell(
                    flex: 4,
                    child: Text(
                      _filteredItems[index].pathPattern,
                      style: const TextStyle(
                        fontSize: 13,
                        fontFamily: 'monospace',
                      ),
                    ),
                  ),
                  _TableCell(
                    flex: 3,
                    child: Text(
                      _filteredItems[index].permissionCode,
                      style: const TextStyle(fontSize: 13),
                    ),
                  ),
                  _TableCell(
                    flex: 3,
                    child: Text(
                      _filteredItems[index].remark,
                      style: TextStyle(fontSize: 13, color: context.cashier.inkMuted,
                      ),
                    ),
                  ),
                  _TableCell(
                    flex: 2,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        TextButton(
                          onPressed: () => _openEdit(item: _filteredItems[index]),
                          child: const Text('编辑'),
                        ),
                        TextButton(
                          onPressed: () => _delete(_filteredItems[index]),
                          style: TextButton.styleFrom(
                            foregroundColor: context.cashier.danger,
                          ),
                          child: const Text('删除'),
                        ),
                      ],
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

// ============================================================
// 权限码管理
// ============================================================

class _PermissionCodesSection extends StatefulWidget {
  const _PermissionCodesSection({super.key, required this.repository});

  final CashierSettingsRepository repository;

  @override
  State<_PermissionCodesSection> createState() =>
      _PermissionCodesSectionState();
}

class _PermissionCodesSectionState extends State<_PermissionCodesSection> {
  var _items = <CashierPermissionCode>[];
  var _loading = true;
  Object? _error;


  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final items = await widget.repository.loadPermissionCodes();
      if (!mounted) return;
      setState(() {
        _items = items;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error;
        _loading = false;
      });
    }
  }

  Future<void> _openEdit({CashierPermissionCode? item}) async {
    final saved = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => _PermissionCodeEditDialog(
        repository: widget.repository,
        item: item),
    );
    if (saved == true && mounted) {
      showSettingsSaved(context, item == null ? '权限码已创建' : '权限码已保存');
      await _load();
    }
  }

  Future<void> _delete(CashierPermissionCode item) async {
    final ok = await showSettingsConfirmDialog(
      context: context,
      title: '删除权限码',
      message: '是否确认删除权限码「${item.permissionCode}」（${item.permissionName}）？',
      impacts: const ['权限码被角色或接口映射引用时将拒绝删除', '删除记录将写入安全审计日志'],
      destructive: true,
      confirmLabel: '确认删除',
    );
    if (ok != true || !mounted) return;
    try {
      await widget.repository.deletePermissionCode(item.id ?? 0);
      if (!mounted) return;
      showSettingsSaved(context, '权限码「${item.permissionCode}」已删除');
      await _load();
    } catch (error) {
      if (!mounted) return;
      await _showActionError(context, '删除失败', error);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      key: const PageStorageKey('access-permission-codes'),
      padding: const EdgeInsets.all(20),
      children: [
        _AccessPageHeader(
          title: '权限码管理',
          subtitle: '权限码（t_permission）被角色与接口映射引用；编码唯一、编辑不可改；被引用时禁止删除。',
          actions: [
            _ToolbarButton(
              key: const Key('access-permission-codes-refresh'),
              icon: Icons.refresh,
              label: '刷新',
              onPressed: _loading ? null : _load,
            ),
            _ToolbarButton(
              key: const Key('access-permission-codes-create'),
              icon: Icons.add,
              label: '新增权限码',
              primary: true,
              onPressed: _loading ? null : () => _openEdit(),
            ),
          ],
        ),
        const SizedBox(height: 16),
        if (_loading)
          const SettingsSkeletonLoader(rows: 4)
        else if (_error != null)
          SettingsErrorState(message: '$_error', onRetry: _load)
        else if (_items.isEmpty)
          const SettingsEmptyState(title: '暂无权限码', description: '点击右上角「新增权限码」创建第一个权限码。',
          )
        else
          ..._items.map(_buildCodeCard),
      ],
    );
  }

  Widget _buildCodeCard(CashierPermissionCode item) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(18),
      decoration: _surface(context),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: context.cashier.row,
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(
              Icons.vpn_key_outlined,
              color: Color(0xff475569)),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      item.permissionName,
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      item.permissionCode,
                      style: TextStyle(
                        fontSize: 12,
                        color: context.cashier.inkMuted,
                        fontFamily: 'monospace',
                      ),
                    ),
                    const SizedBox(width: 8),
                    if (item.module.isNotEmpty)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: context.cashier.row,
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          '模块 ${item.module}',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: context.cashier.inkSecondary,
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  item.remark.isEmpty ? '排序 ${item.sortOrder}' : '${item.remark} · 排序 ${item.sortOrder}',
                  style: TextStyle(fontSize: 13, color: context.cashier.inkMuted,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          TextButton(
            key: Key('access-permission-code-edit-${item.id}'),
            onPressed: () => _openEdit(item: item),
            child: const Text('编辑'),
          ),
          TextButton(
            key: Key('access-permission-code-delete-${item.id}'),
            onPressed: () => _delete(item),
            style: TextButton.styleFrom(
              foregroundColor: context.cashier.danger,
            ),
            child: const Text('删除'),
          ),
        ],
      ),
    );
  }
}

// ============================================================
// 策略中心（Policy Engine & ABAC）
// ============================================================

class _PoliciesSection extends StatefulWidget {
  const _PoliciesSection({super.key, required this.repository});

  final CashierSettingsRepository repository;

  @override
  State<_PoliciesSection> createState() => _PoliciesSectionState();
}

class _PoliciesSectionState extends State<_PoliciesSection> {
  final _filterController = TextEditingController();
  var _policies = <CashierAccessPolicy>[];
  var _roles = <CashierAccessRole>[];
  var _shops = <CashierShopRef>[];
  var _loading = true;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _filterController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final results = await Future.wait([
        widget.repository.loadAccessPolicies(),
        widget.repository.loadAccessRoles(),
        widget.repository.loadShopList(),
      ]);
      if (!mounted) return;
      setState(() {
        _policies = results[0] as List<CashierAccessPolicy>;
        _roles = results[1] as List<CashierAccessRole>;
        _shops = results[2] as List<CashierShopRef>;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error;
        _loading = false;
      });
    }
  }

  Future<void> _refresh() async {
    await _load();
  }

  List<CashierAccessPolicy> get _visible {
    final keyword = _filterController.text.trim();
    if (keyword.isEmpty) return _policies;
    final lowered = keyword.toLowerCase();
    return _policies
        .where((p) =>
            p.policyName.toLowerCase().contains(lowered) ||
            p.policyCode.toLowerCase().contains(lowered) ||
            p.permissionCode.toLowerCase().contains(lowered),
        )
        .toList();
  }


  Future<void> _openCreate() async {
    final saved = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => _PolicyEditDialog(
        repository: widget.repository,
        policy: null),
    );
    if (saved == true && mounted) {
      showSettingsSaved(context, '策略已创建');
      await _refresh();
    }
  }

  Future<void> _openEdit(CashierAccessPolicy policy) async {
    final saved = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => _PolicyEditDialog(
        repository: widget.repository,
        policy: policy),
    );
    if (saved == true && mounted) {
      showSettingsSaved(context, '策略已更新');
      await _refresh();
    }
  }

  Future<void> _openAssign(CashierAccessPolicy policy) async {
    final assigned = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => _PolicyAssignDialog(
        repository: widget.repository,
        policy: policy,
        roles: _roles,
        shops: _shops,
      ),
    );
    if (assigned == true && mounted) {
      showSettingsSaved(context, '策略绑定成功');
    }
  }

  Future<void> _openDelete(CashierAccessPolicy policy) async {
    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.delete_outline, color: Color(0xffb91c1c), size: 24),
            SizedBox(width: 10),
            Text('删除策略'),
          ],
        ),
        content: Text(
          '确定删除权限策略「${policy.policyName}」（${policy.policyCode}）吗？'
          '已绑定该策略的角色将不再受其约束。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            key: Key('policy-delete-confirm-${policy.id ?? 0}'),
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xffb91c1c),
            ),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      await widget.repository.deleteAccessPolicy(policy.id ?? 0);
      if (!mounted) return;
      showSettingsSaved(context, '策略已删除');
      await _refresh();
    } catch (error) {
      if (!mounted) return;
      showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('删除失败'),
          content: Text('$error'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('知道了'),
            ),
          ],
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final visible = _visible;
    final enabledCount = _policies.where((p) => p.isEnabled).length;
    return ListView(
      key: const PageStorageKey('access-policies'),
      padding: const EdgeInsets.all(20),
      children: [
        _AccessPageHeader(
          title: '策略中心',
          subtitle:
              '基于业务上下文与动态阈值的权限策略（ABAC）：金额上限、折扣底线、显式 ALLOW/DENY 覆盖，可绑定角色并按门店定向生效。',
          actions: [
            _ToolbarButton(
              key: const Key('access-policies-refresh'),
              icon: Icons.refresh,
              label: '刷新',
              onPressed: _loading ? null : _refresh,
            ),
            _ToolbarButton(
              key: const Key('access-policies-create'),
              icon: Icons.add,
              label: '新建策略',
              primary: true,
              onPressed: _loading ? null : _openCreate,
            ),
          ],
        ),
        const SizedBox(height: 16),
        _StatsStrip(
          items: [
            _StatItem(label: '策略总数', value: '${_policies.length}'),
            _StatItem(label: '已启用', value: '$enabledCount'),
            _StatItem(label: '角色池', value: '${_roles.length} 个角色'),
          ],
        ),
        const SizedBox(height: 16),
        TextField(
          key: const Key('access-policies-filter'),
          controller: _filterController,
          decoration: InputDecoration(
            hintText: '按策略名称 / 编码 / 权限码过滤',
            prefixIcon: const Icon(Icons.search),
            filled: true,
            fillColor: Colors.white,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide(color: context.cashier.border),
            ),
            isDense: true,
          ),
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 16),
        if (_loading)
          const Padding(
            padding: EdgeInsets.all(24),
            child: Center(child: CircularProgressIndicator()),
          )
        else if (_error != null)
          SettingsEmptyState(
            title: '加载失败',
            description: '$_error')
        else if (visible.isEmpty)
          const SettingsEmptyState(
            title: '暂无权限策略',
            description: '点击右上角「新建策略」配置金额上限、折扣底线或显式覆盖规则。',
          )
        else
          for (final policy in visible) _buildPolicyCard(policy),
      ],
    );
  }

  Widget _buildPolicyCard(CashierAccessPolicy policy) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: _surface(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Wrap(
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 6,
                  runSpacing: 4,
                  children: [
                    Text(
                      policy.policyName.isEmpty ? policy.policyCode : policy.policyName,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    _PolicyTypeBadge(type: policy.policyType),
                    _PolicyEffectBadge(effect: policy.effect),
                    if (!policy.isEnabled)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 1,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xfff1f5f9),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: const Text(
                          '已停用',
                          style: TextStyle(
                            fontSize: 11,
                            color: Color(0xff64748b),
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              PopupMenuButton<String>(
                key: Key('access-policy-more-${policy.id ?? 0}'),
                tooltip: '策略操作',
                onSelected: (value) => switch (value) {
                  'edit' => _openEdit(policy),
                  'assign' => _openAssign(policy),
                  'delete' => _openDelete(policy),
                  _ => null,
                },
                itemBuilder: (context) => const [
                  PopupMenuItem(value: 'edit', child: Text('编辑策略')),
                  PopupMenuItem(value: 'assign', child: Text('绑定角色')),
                  PopupMenuItem(value: 'delete', child: Text('删除策略')),
                ],
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            '${policy.permissionCode.isNotEmpty ? '权限码 ${policy.permissionCode}' : '未绑定权限码'}'
            ' · 优先级 ${policy.priority}'
            '${policy.configJson != null && policy.configJson!.isNotEmpty ? ' · 规则 ${policy.configJson}' : ''}',
            style: TextStyle(
              fontSize: 12,
              color: context.cashier.inkMuted),
          ),
        ],
      ),
    );
  }
}

/// 策略类型徽标（金额上限/折扣底线等）。
class _PolicyTypeBadge extends StatelessWidget {
  const _PolicyTypeBadge({required this.type});

  final String type;

  @override
  Widget build(BuildContext context) {
    final isMaxAmount = type == CashierAccessPolicyType.maxAmount;
    final isDiscount = type == CashierAccessPolicyType.minDiscountRate ||
        type == CashierAccessPolicyType.maxDiscountAmount;
    final (Color bg, Color fg, Color border) = isMaxAmount
        ? (const Color(0xffe0f2fe), const Color(0xff0369a1), const Color(0xffbae6fd),
          )
        : isDiscount
            ? (const Color(0xfffff7e6), const Color(0xffb45309), const Color(0xfffde68a),
          )
            : (const Color(0xfff1f5f9), const Color(0xff64748b), const Color(0xffcbd5e1),
          );
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: border),
      ),
      child: Text(
        CashierAccessPolicyType.label(type),
        style: TextStyle(
          fontSize: 11,
          color: fg,
          fontWeight: FontWeight.w600),
      ),
    );
  }
}

/// 策略默认作用徽标（ALLOW 放行 / DENY 拒绝）。
class _PolicyEffectBadge extends StatelessWidget {
  const _PolicyEffectBadge({required this.effect});

  final String effect;

  @override
  Widget build(BuildContext context) {
    final isAllow = effect == CashierAccessPolicyEffect.allow;
    final (Color bg, Color fg, Color border) = isAllow
        ? (const Color(0xffe7f6ec), const Color(0xff15803d), const Color(0xffbbf7d0),
          )
        : (const Color(0xfffee2e2), const Color(0xffb91c1c), const Color(0xfffecaca),
          );
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: border),
      ),
      child: Text(
        CashierAccessPolicyEffect.label(effect),
        style: TextStyle(
          fontSize: 11,
          color: fg,
          fontWeight: FontWeight.w600),
      ),
    );
  }
}

/// 策略创建/编辑表单（金额/折扣阈值等规则以 config_json 提交）。
class _PolicyEditDialog extends StatefulWidget {
  const _PolicyEditDialog({
    required this.repository,
    required this.policy});

  final CashierSettingsRepository repository;
  final CashierAccessPolicy? policy;

  @override
  State<_PolicyEditDialog> createState() => _PolicyEditDialogState();
}

class _PolicyEditDialogState extends State<_PolicyEditDialog> {
  late final TextEditingController _codeController;
  late final TextEditingController _nameController;
  late final TextEditingController _permissionCodeController;
  late final TextEditingController _priorityController;
  late final TextEditingController _configController;
  late String _policyType;
  late String _effect;
  late bool _enabled;
  var _submitting = false;
  Object? _submitError;

  bool get _isEdit => widget.policy != null;

  @override
  void initState() {
    super.initState();
    final policy = widget.policy;
    _codeController = TextEditingController(text: policy?.policyCode ?? '');
    _nameController = TextEditingController(text: policy?.policyName ?? '');
    _permissionCodeController =
        TextEditingController(text: policy?.permissionCode ?? '',
    );
    _priorityController = TextEditingController(text: '${policy?.priority ?? 100}',
    );
    _configController =
        TextEditingController(text: policy?.configJson ?? '');
    _policyType = policy?.policyType ?? CashierAccessPolicyType.maxAmount;
    _effect = policy?.effect ?? CashierAccessPolicyEffect.allow;
    _enabled = policy?.isEnabled ?? true;
  }

  @override
  void dispose() {
    _codeController.dispose();
    _nameController.dispose();
    _permissionCodeController.dispose();
    _priorityController.dispose();
    _configController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final code = _codeController.text.trim();
    final name = _nameController.text.trim();
    final permissionCode = _permissionCodeController.text.trim();
    if (code.isEmpty || name.isEmpty || permissionCode.isEmpty) {
      setState(() => _submitError = '策略编码、名称与权限码为必填项');
      return;
    }
    setState(() {
      _submitting = true;
      _submitError = null;
    });
    final draft = CashierAccessPolicy(
      id: widget.policy?.id,
      policyCode: code,
      policyName: name,
      permissionCode: permissionCode,
      policyType: _policyType,
      effect: _effect,
      priority: int.tryParse(_priorityController.text.trim()) ?? 100,
      enabled: _enabled ? 1 : 0,
      configJson: _configController.text.trim().isEmpty
          ? null
          : _configController.text.trim(),
    );
    try {
      if (_isEdit) {
        await widget.repository.updateAccessPolicy(
          id: widget.policy!.id!,
          policy: draft,
        );
      } else {
        await widget.repository.createAccessPolicy(draft);
      }
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _submitError = error;
        _submitting = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Row(
        children: [
          Icon(Icons.rule, color: context.cashier.ink),
          const SizedBox(width: 10),
          Text(_isEdit ? '编辑策略' : '新建策略'),
        ],
      ),
      content: SizedBox(
        width: 620,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: _DialogField(
                      key: const Key('policy-form-code'),
                      controller: _codeController,
                      label: '策略编码 *（如 MAX_AMOUNT_REFUND_50）',
                      readOnly: _isEdit,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _DialogField(
                      key: const Key('policy-form-name'),
                      controller: _nameController,
                      label: '策略名称 *（如 退款金额上限 50 元）',
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              _DialogField(
                key: const Key('policy-form-permission-code'),
                controller: _permissionCodeController,
                label: '绑定的功能权限码 *（如 order:operate:refund）',
                readOnly: _isEdit,
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const _DialogFieldLabel(label: '策略类型 *'),
                        const SizedBox(height: 6),
                        DropdownButtonFormField<String>(
                          key: const Key('policy-form-type'),
                          initialValue: _policyType,
                          isExpanded: true,
                          decoration: const InputDecoration(
                            border: OutlineInputBorder(),
                            isDense: true,
                          ),
                          items: const [
                            DropdownMenuItem(
                              value: CashierAccessPolicyType.maxAmount,
                              child: Text('金额上限（MAX_AMOUNT）', overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            DropdownMenuItem(
                              value: CashierAccessPolicyType.minDiscountRate,
                              child: Text('折扣底线（MIN_DISCOUNT_RATE）', overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            DropdownMenuItem(
                              value: CashierAccessPolicyType.maxDiscountAmount,
                              child: Text('折扣金额上限（MAX_DISCOUNT_AMOUNT）', overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            DropdownMenuItem(
                              value: CashierAccessPolicyType.maxDailyCount,
                              child: Text('日次数上限（MAX_DAILY_COUNT）', overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            DropdownMenuItem(
                              value: CashierAccessPolicyType.orderStatus,
                              child: Text('订单状态限制（ORDER_STATUS）', overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            DropdownMenuItem(
                              value: CashierAccessPolicyType.timeWindow,
                              child: Text('时间窗口限制（TIME_WINDOW）', overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                          onChanged: (value) {
                            if (value != null) {
                              setState(() => _policyType = value);
                            }
                          },
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const _DialogFieldLabel(label: '默认作用 *'),
                        const SizedBox(height: 6),
                        DropdownButtonFormField<String>(
                          key: const Key('policy-form-effect'),
                          initialValue: _effect,
                          decoration: const InputDecoration(
                            border: OutlineInputBorder(),
                            isDense: true,
                          ),
                          items: const [
                            DropdownMenuItem(
                              value: CashierAccessPolicyEffect.allow,
                              child: Text('放行（ALLOW）'),
                            ),
                            DropdownMenuItem(
                              value: CashierAccessPolicyEffect.deny,
                              child: Text('拒绝（DENY，最高优先级）'),
                            ),
                          ],
                          onChanged: (value) {
                            if (value != null) {
                              setState(() => _effect = value);
                            }
                          },
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: _DialogField(
                      key: const Key('policy-form-priority'),
                      controller: _priorityController,
                      label: '优先级（数值越小越高，默认 100）',
                      number: true,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const _DialogFieldLabel(label: '启用状态'),
                        const SizedBox(height: 6),
                        SwitchListTile(
                          key: const Key('policy-form-enabled'),
                          title: const Text('启用策略', style: TextStyle(fontSize: 14),
                          ),
                          value: _enabled,
                          contentPadding: EdgeInsets.zero,
                          onChanged: (value) => setState(() => _enabled = value),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              _DialogFieldLabel(
                label: '策略规则 JSON（config_json）',
                trailing: '按策略类型填写阈值',
              ),
              const SizedBox(height: 6),
              TextField(
                key: const Key('policy-form-config'),
                controller: _configController,
                maxLines: 4,
                decoration: const InputDecoration(
                  hintText: '示例：{"maxAmount": 50}（金额上限）/ {"minRate": 0.8}（折扣底线）',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
              if (_submitError != null) ...[
                const SizedBox(height: 12),
                Text(
                  '保存失败：$_submitError',
                  style: TextStyle(color: context.cashier.danger, fontSize: 13),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _submitting ? null : () => Navigator.of(context).pop(false),
          child: const Text('取消'),
        ),
        FilledButton(
          key: const Key('policy-form-submit'),
          onPressed: _submitting ? null : _submit,
          child: Text(_isEdit ? '保存' : '创建'),
        ),
      ],
    );
  }
}

/// 策略绑定角色（支持全局或按门店定向生效）。
class _PolicyAssignDialog extends StatefulWidget {
  const _PolicyAssignDialog({
    required this.repository,
    required this.policy,
    required this.roles,
    required this.shops,
  });

  final CashierSettingsRepository repository;
  final CashierAccessPolicy policy;
  final List<CashierAccessRole> roles;
  final List<CashierShopRef> shops;

  @override
  State<_PolicyAssignDialog> createState() => _PolicyAssignDialogState();
}

class _PolicyAssignDialogState extends State<_PolicyAssignDialog> {
  int? _roleId;
  int? _shopId;
  var _submitting = false;
  Object? _submitError;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Row(
        children: [
          const Icon(Icons.assignment_ind, color: Color(0xff075985), size: 24),
          const SizedBox(width: 10),
          Text('绑定策略至角色'),
        ],
      ),
      content: SizedBox(
        width: 460,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '策略：${widget.policy.policyName}（${widget.policy.policyCode}）',
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 14),
            const _DialogFieldLabel(label: '目标角色 *'),
            const SizedBox(height: 6),
            DropdownButtonFormField<int>(
              key: const Key('policy-assign-role'),
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                isDense: true,
              ),
              hint: const Text('选择角色'),
              items: [
                for (final role in widget.roles)
                  DropdownMenuItem<int>(
                    value: role.id,
                    child: Text(
                      '${role.roleName} (${role.roleCode})',
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
              ],
              onChanged: (value) => setState(() => _roleId = value),
            ),
            const SizedBox(height: 14),
            const _DialogFieldLabel(label: '生效门店'),
            const SizedBox(height: 6),
            DropdownButtonFormField<int?>(
              key: const Key('policy-assign-shop'),
              initialValue: _shopId,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                isDense: true,
              ),
              items: [
                const DropdownMenuItem<int?>(
                  value: null,
                  child: Text('全部门店（全局生效）'),
                ),
                for (final shop in widget.shops)
                  DropdownMenuItem<int?>(
                    value: shop.id,
                    child: Text(shop.name),
                  ),
              ],
              onChanged: (value) => setState(() => _shopId = value),
            ),
            if (_submitError != null) ...[
              const SizedBox(height: 12),
              Text(
                '绑定失败：$_submitError',
                style: TextStyle(color: context.cashier.danger, fontSize: 13),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _submitting ? null : () => Navigator.of(context).pop(false),
          child: const Text('取消'),
        ),
        FilledButton(
          key: const Key('policy-assign-confirm'),
          onPressed: _submitting
              ? null
              : () async {
                  final roleId = _roleId;
                  if (roleId == null) {
                    setState(() => _submitError = '请选择目标角色');
                    return;
                  }
                  setState(() {
                    _submitting = true;
                    _submitError = null;
                  });
                  try {
                    await widget.repository.assignAccessPolicy(
                      roleId: roleId,
                      policyId: widget.policy.id ?? 0,
                      shopId: _shopId,
                    );
                    if (!mounted) return;
                    Navigator.of(context).pop(true);
                  } catch (error) {
                    if (!mounted) return;
                    setState(() {
                      _submitting = false;
                      _submitError = error;
                    });
                  }
                },
          child: Text(_submitting ? '绑定中...' : '确认绑定'),
        ),
      ],
    );
  }
}

// ============================================================
// 多店授权
// ============================================================

class _ShopsSection extends StatefulWidget {
  const _ShopsSection({super.key, required this.repository});

  final CashierSettingsRepository repository;

  @override
  State<_ShopsSection> createState() => _ShopsSectionState();
}

class _ShopsSectionState extends State<_ShopsSection> {
  var _employees = <CashierAccessEmployee>[];
  var _shops = <CashierShopRef>[];
  var _loading = true;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final results = await Future.wait([
        widget.repository.loadAccessEmployees(page: 1, pageSize: 100),
        widget.repository.loadShopList(),
      ]);
      if (!mounted) return;
      setState(() {
        _employees = (results[0] as PagedCashierAccessEmployees).items;
        _shops = (results[1] as List<CashierShopRef>);
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error;
        _loading = false;
      });
    }
  }

  String _shopName(int shopId) {
    for (final shop in _shops) {
      if (shop.id == shopId) return shop.name;
    }
    return '门店 #$shopId';
  }

  @override
  Widget build(BuildContext context) {
    final byShop = <int, List<CashierAccessEmployee>>{};
    for (final employee in _employees) {
      for (final shopId in employee.shops) {
        byShop.putIfAbsent(shopId, () => []).add(employee);
      }
    }
    final shopIds = byShop.keys.toList()..sort();

    return ListView(
      key: const PageStorageKey('access-shops'),
      padding: const EdgeInsets.all(20),
      children: [
        _AccessPageHeader(
          title: '多店授权分布',
          subtitle: '按门店聚合员工授权，门店名称来自门店列表。',
          actions: [
            _ToolbarButton(
              key: const Key('access-shops-refresh'),
              icon: Icons.refresh,
              label: '刷新',
              onPressed: _loading ? null : _load,
            ),
          ],
        ),
        const SizedBox(height: 16),
        if (_loading)
          const SettingsSkeletonLoader(rows: 4)
        else if (_error != null)
          SettingsErrorState(message: '$_error', onRetry: _load)
        else if (shopIds.isEmpty)
          const SettingsEmptyState(title: '暂无门店授权', description: '尚未为任何员工分配门店管辖范围。',
          )
        else
          LayoutBuilder(
            builder: (context, constraints) {
              final columns = constraints.maxWidth >= 900 ? 2 : 1;
              final width = (constraints.maxWidth - 12 * (columns - 1)) / columns;
              return Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  for (final shopId in shopIds)
                    SizedBox(
                      width: width,
                      child: _buildShopCard(shopId, byShop[shopId]!),
                    ),
                ],
              );
            },
          ),
      ],
    );
  }

  Widget _buildShopCard(int shopId, List<CashierAccessEmployee> staff) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: _surface(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.storefront, color: Color(0xff075985)),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  _shopName(shopId),
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              SettingsStatusBadge(label: '${staff.length} 人', type: StatusBadgeType.info,
              ),
            ],
          ),
          const SizedBox(height: 10),
          for (final employee in staff)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 12,
                    backgroundColor: context.cashier.selectedBackground,
                    child: Text(
                      employee.userName.isEmpty ? '#' : employee.userName.substring(0, 1),
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: Color(0xff075985),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      employee.roles.isEmpty
                          ? employee.userName
                          : '${employee.userName}（${employee.roles.map((r) => r.roleName.isEmpty ? r.roleCode : r.roleName).join(' + ')}）',
                      style: const TextStyle(fontSize: 13),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
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

// ============================================================
// 变更记录
// ============================================================

class _ChangesSection extends StatefulWidget {
  const _ChangesSection({super.key, required this.repository});

  final CashierSettingsRepository repository;

  @override
  State<_ChangesSection> createState() => _ChangesSectionState();
}

class _ChangesSectionState extends State<_ChangesSection> {
  static const _pageSize = 20;

  var _items = <CashierAccessAuditEntry>[];
  var _page = 1;
  var _total = 0;
  var _loading = true;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final items = await widget.repository.loadAccessAudit(
        page: _page,
        pageSize: _pageSize,
      );
      if (!mounted) return;
      setState(() {
        _items = items;
        _total = items.length == _pageSize ? _page * _pageSize + _pageSize : _page * _pageSize + items.length;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error;
        _loading = false;
      });
    }
  }

  void _goPage(int page) {
    if (page < 1) return;
    setState(() => _page = page);
    _load();
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      key: const PageStorageKey('access-changes'),
      padding: const EdgeInsets.all(20),
      children: [
        _AccessPageHeader(
          title: '权限变更记录',
          subtitle: '员工授权与角色变更审计，保留最近 30 天。',
          actions: [
            _ToolbarButton(
              key: const Key('access-changes-refresh'),
              icon: Icons.refresh,
              label: '刷新',
              onPressed: _loading ? null : _load,
            ),
          ],
        ),
        const SizedBox(height: 16),
        if (_loading)
          const SettingsSkeletonLoader(rows: 4)
        else if (_error != null)
          SettingsErrorState(message: '$_error', onRetry: _load)
        else if (_items.isEmpty)
          const SettingsEmptyState(title: '暂无变更记录', description: '员工授权或角色变更后将在此展示审计日志。',
          )
        else
          ..._items.map(_buildChangeItem),
        if (_items.length >= _pageSize) ...[
          const SizedBox(height: 14),
          _PaginationBar(
            page: _page,
            total: _total,
            pageSize: _pageSize,
            onPrevious: _page > 1 ? () => _goPage(_page - 1) : null,
            onNext: _items.length >= _pageSize ? () => _goPage(_page + 1) : null,
          ),
        ],
      ],
    );
  }

  Widget _buildChangeItem(CashierAccessAuditEntry entry) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
      decoration: _surface(context),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: context.cashier.row,
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(Icons.security, size: 17, color: Color(0xff475569),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  entry.title,
                  style: const TextStyle(fontSize: 13, height: 1.5),
                ),
                if (entry.detail.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    entry.detail,
                    style: TextStyle(fontSize: 12, color: context.cashier.inkMuted,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 12),
          Text(
            _fmtTime(entry.time),
            style: TextStyle(fontSize: 12, color: context.cashier.inkMuted),
          ),
        ],
      ),
    );
  }
}

// ============================================================
// 弹窗：授权员工
// ============================================================

class _AssignEmployeeDialog extends StatefulWidget {
  const _AssignEmployeeDialog({
    required this.repository,
    required this.roles,
    required this.shops,
    required this.admins,
    required this.adminsLoadFailed,
    this.employee,
    required this.onAssign,
  });

  final CashierSettingsRepository repository;
  final List<CashierAccessRole> roles;
  final List<CashierShopRef> shops;
  final List<CashierAdministrator> admins;
  final bool adminsLoadFailed;
  final CashierAccessEmployee? employee;
  final Future<void> Function(int adminId, List<int> roleIds, List<int> shopIds)
      onAssign;

  @override
  State<_AssignEmployeeDialog> createState() => _AssignEmployeeDialogState();
}

class _AssignEmployeeDialogState extends State<_AssignEmployeeDialog> {
  late int? _adminId;
  late final Set<int> _roleIds;
  late final Set<int> _shopIds;
  var _confirming = false;
  var _submitting = false;
  Object? _submitError;

  @override
  void initState() {
    super.initState();
    final employee = widget.employee;
    _adminId = employee?.adminId;
    _roleIds = {...?employee?.roles.map((r) => r.id)};
    _shopIds = {...?employee?.shops};
  }

  List<int> get _sortedRoleIds => _roleIds.toList()..sort();
  List<int> get _sortedShopIds => _shopIds.toList()..sort();

  List<String> _diffImpacts() {
    final employee = widget.employee;
    if (employee == null) return const [];
    final impacts = <String>[];
    for (final role in employee.roles) {
      if (!_roleIds.contains(role.id)) {
        impacts.add('将移除角色：${_roleName(role.id)}');
      }
    }
    for (final id in _sortedRoleIds) {
      if (!employee.roles.any((r) => r.id == id)) {
        impacts.add('将新增角色：${_roleName(id)}');
      }
    }
    for (final shopId in employee.shops) {
      if (!_shopIds.contains(shopId)) {
        impacts.add('将移除门店管辖：${_shopName(shopId)}');
      }
    }
    for (final shopId in _sortedShopIds) {
      if (!employee.shops.contains(shopId)) {
        impacts.add('将新增门店管辖：${_shopName(shopId)}');
      }
    }
    return impacts;
  }

  String _roleName(int id) {
    for (final role in widget.roles) {
      if (role.id == id) return role.roleName;
    }
    return '角色 #$id';
  }

  String _shopName(int id) {
    for (final shop in widget.shops) {
      if (shop.id == id) return shop.name;
    }
    return '门店 #$id';
  }

  String _adminName(int adminId) {
    for (final admin in widget.admins) {
      if (admin.id == adminId) return admin.userName;
    }
    return '员工 #$adminId';
  }

  Future<void> _submit() async {
    if (_adminId == null) {
      setState(() => _submitError = '请先选择要授权的员工');
      return;
    }
    setState(() {
      _submitting = true;
      _submitError = null;
    });
    try {
      await widget.onAssign(_adminId!, _sortedRoleIds, _sortedShopIds);
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _submitError = error;
        _submitting = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Row(
        children: [
          Icon(Icons.admin_panel_settings_outlined, color: context.cashier.ink),
          const SizedBox(width: 10),
          Text(widget.employee == null ? '授权员工' : '调整授权'),
        ],
      ),
      content: SizedBox(
        width: 640,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (widget.employee == null) _buildPickEmployee(),
              const SizedBox(height: 14),
              _DialogFieldLabel(
                label: '角色（可多选，不选表示清空角色）',
                trailing: '${_roleIds.length} 项',
              ),
              const SizedBox(height: 6),
              _OptionGrid(
                key: const Key('access-assign-roles'),
                items: [
                  for (final role in widget.roles)
                    _OptionItem(
                      id: role.id,
                      title: '${role.roleName} ${role.roleCode}',
                      subtitle: '优先级 ${role.sortOrder}',
                    ),
                ],
                selectedIds: _roleIds,
                onToggle: (id) => setState(() {
                  if (!_roleIds.remove(id)) _roleIds.add(id);
                }),
              ),
              const SizedBox(height: 14),
              _DialogFieldLabel(
                label: '管辖门店（可多选）',
                trailing: '${_shopIds.length} 项',
              ),
              const SizedBox(height: 6),
              _OptionGrid(
                key: const Key('access-assign-shops'),
                items: [
                  for (final shop in widget.shops)
                    _OptionItem(id: shop.id, title: shop.name),
                ],
                selectedIds: _shopIds,
                onToggle: (id) => setState(() {
                  if (!_shopIds.remove(id)) _shopIds.add(id);
                }),
              ),
              if (widget.employee != null) ...[
                const SizedBox(height: 14),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: context.cashier.row,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '覆盖式更新：保存后「${_adminName(_adminId!)}」的角色与门店范围将被整体替换（body 带 confirm=true）。',
                        style: TextStyle(
                          fontSize: 12,
                          height: 1.5,
                          color: context.cashier.inkSecondary,
                        ),
                      ),
                      if (_diffImpacts().isNotEmpty) ...[
                        const SizedBox(height: 8),
                        for (final impact in _diffImpacts())
                          Text(
                            impact,
                            style: TextStyle(
                              fontSize: 12,
                              height: 1.5,
                              color: impact.startsWith('将移除')
                                  ? context.cashier.danger
                                  : context.cashier.success,
                            ),
                          ),
                      ],
                    ],
                  ),
                ),
              ],
              if (_submitError != null) ...[
                const SizedBox(height: 12),
                Text(
                  '提交失败：$_submitError',
                  style: TextStyle(color: context.cashier.danger, fontSize: 13),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _submitting ? null : () => Navigator.of(context).pop(false),
          child: const Text('取消'),
        ),
        FilledButton(
          key: const Key('access-assign-submit'),
          onPressed: _submitting
              ? null
              : () {
                  if (!_confirming) {
                    setState(() => _confirming = true);
                    return;
                  }
                  _submit();
                },
          style: FilledButton.styleFrom(
            backgroundColor: context.cashier.ink),
          child: Text(_confirming ? '确认覆盖授权' : '下一步：二次确认'),
        ),
      ],
    );
  }

  Widget _buildPickEmployee() {
    if (widget.adminsLoadFailed) {
      return Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: context.cashier.warningBackground,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Text(
          '无法加载管理员列表（需要 admin:manage 权限），可改为在列表中「调整授权」已有员工。',
          style: TextStyle(fontSize: 12, color: context.cashier.warning),
        ),
      );
    }
    if (widget.admins.isEmpty) {
      return const Text('暂无可授权员工。', style: TextStyle(fontSize: 13));
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _DialogFieldLabel(label: '选择员工（授权现有账号，不创建账号）', trailing: '${widget.admins.length} 人',
        ),
        const SizedBox(height: 6),
        _OptionGrid(
          key: const Key('access-assign-employee'),
          items: [
            for (final admin in widget.admins)
              _OptionItem(
                id: admin.id,
                title: admin.userName,
                subtitle: admin.roles.isEmpty
                    ? 'ID ${admin.id}'
                    : 'ID ${admin.id} · ${admin.roles.map((r) => r.roleName).join('、')}',
              ),
          ],
          selectedIds: _adminId == null ? const {} : {_adminId!},
          onToggle: (id) => setState(() => _adminId = id),
        ),
      ],
    );
  }
}

// ============================================================
// 弹窗：新建 / 编辑员工档案
// ============================================================

class _CreateOrEditEmployeeProfileDialog extends StatefulWidget {
  const _CreateOrEditEmployeeProfileDialog({
    required this.repository,
    required this.roles,
    required this.shops,
    this.employee,
  });

  final CashierSettingsRepository repository;
  final List<CashierAccessRole> roles;
  final List<CashierShopRef> shops;
  final CashierAccessEmployee? employee;

  @override
  State<_CreateOrEditEmployeeProfileDialog> createState() =>
      _CreateOrEditEmployeeProfileDialogState();
}

class _CreateOrEditEmployeeProfileDialogState
    extends State<_CreateOrEditEmployeeProfileDialog> {
  int? _createdAdminId;
  late final TextEditingController _workNoController;
  late final TextEditingController _realNameController;
  late final TextEditingController _jobTitleController;
  late final TextEditingController _userNameController;
  late final TextEditingController _passwordController;
  late final Set<int> _roleIds;
  late final Set<int> _shopIds;

  bool _obscurePassword = true;
  bool _submitting = false;
  Object? _submitError;

  bool get _isEdit => widget.employee != null;

  static const _jobTitlePresets = [
    '店长',
    '副店长',
    '领班',
    '收银员',
    '服务员',
    '后厨主管'];

  @override
  void initState() {
    super.initState();
    final emp = widget.employee;
    _workNoController = TextEditingController(text: emp?.workNo ?? '');
    _realNameController = TextEditingController(text: emp?.realName ?? '');
    _jobTitleController = TextEditingController(text: emp?.jobTitle ?? '');
    _userNameController = TextEditingController(text: emp?.userName ?? '');
    _passwordController = TextEditingController();
    _roleIds = {...?emp?.roles.map((r) => r.id)};
    _shopIds = {...?emp?.shops};
  }

  @override
  void dispose() {
    _workNoController.dispose();
    _realNameController.dispose();
    _jobTitleController.dispose();
    _userNameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_submitting) return;
    final workNo = _workNoController.text.trim();
    final realName = _realNameController.text.trim();
    final jobTitle = _jobTitleController.text.trim();
    final userName = _userNameController.text.trim();
    final password = _passwordController.text.trim();

    if (workNo.isNotEmpty) {
      final workNoRegex = RegExp(r'^[a-zA-Z0-9_\-]+$');
      if (!workNoRegex.hasMatch(workNo) || workNo.length < 2 || workNo.length > 20) {
        setState(() => _submitError = '工号格式不正确：支持2~20位字母、数字、下划线及短横线');
        return;
      }
    }

    if (realName.isEmpty) {
      setState(() => _submitError = '员工姓名不能为空');
      return;
    }
    if (realName.length < 2 || realName.length > 20) {
      setState(() => _submitError = '员工姓名需在 2~20 个字符之间');
      return;
    }

    if (!_isEdit && userName.isEmpty) {
      setState(() => _submitError = '登录用户名不能为空');
      return;
    }

    if (!_isEdit && password.isEmpty) {
      setState(() => _submitError = '新建员工账号必须设置初始密码');
      return;
    }

    if (password.isNotEmpty && password.length < 6) {
      setState(() => _submitError = '密码长度至少为 6 个字符');
      return;
    }

    setState(() {
      _submitting = true;
      _submitError = null;
    });

    try {
      if (_createdAdminId != null) {
        await widget.repository.assignAccessEmployee(
          adminId: _createdAdminId!,
          roleIds: _roleIds.toList()..sort(),
          shopIds: _shopIds.toList()..sort(),
          confirm: true,
        );
      } else if (_isEdit) {
        await widget.repository.updateEmployee(
          adminId: widget.employee!.adminId,
          workNo: workNo,
          realName: realName,
          jobTitle: jobTitle,
          password: password.isNotEmpty ? password : null,
          roleIds: _roleIds.toList()..sort(),
          shopIds: _shopIds.toList()..sort(),
        );
      } else {
        await widget.repository.createEmployee(
          userName: userName,
          password: password,
          workNo: workNo.isNotEmpty ? workNo : null,
          realName: realName,
          jobTitle: jobTitle.isNotEmpty ? jobTitle : null,
          roleIds: _roleIds.toList()..sort(),
          shopIds: _shopIds.toList()..sort(),
        );
      }
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        if (error is EmployeeAssignmentException)
          _createdAdminId = error.adminId;
        _submitError = '$error';
        _submitting = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Row(
        children: [
          Icon(
            _isEdit ? Icons.edit_note_outlined : Icons.person_add_alt_1,
            color: context.cashier.ink,
          ),
          const SizedBox(width: 10),
          Text(_isEdit ? '编辑员工档案' : '新建员工档案'),
        ],
      ),
      content: SizedBox(
        width: 660,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const _DialogFieldLabel(label: '员工工号（唯一凭证）'),
                        const SizedBox(height: 6),
                        TextField(
                          key: const Key('employee-form-work-no'),
                          controller: _workNoController,
                          readOnly: _createdAdminId != null,
                          decoration: InputDecoration(
                            hintText: '如 EMP1001',
                            filled: true,
                            fillColor: Colors.white,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                              borderSide: BorderSide(color: context.cashier.border,
                              ),
                            ),
                            isDense: true,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const _DialogFieldLabel(label: '真实姓名 *'),
                        const SizedBox(height: 6),
                        TextField(
                          key: const Key('employee-form-real-name'),
                          controller: _realNameController,
                          readOnly: _createdAdminId != null,
                          decoration: InputDecoration(
                            hintText: '员工中文姓名',
                            filled: true,
                            fillColor: Colors.white,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                              borderSide: BorderSide(color: context.cashier.border,
                              ),
                            ),
                            isDense: true,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              const _DialogFieldLabel(label: '职务/岗位（单据与交班责任人展示）'),
              const SizedBox(height: 6),
              TextField(
                key: const Key('employee-form-job-title'),
                controller: _jobTitleController,
                readOnly: _createdAdminId != null,
                decoration: InputDecoration(
                  hintText: '如 店长 / 领班 / 收银员',
                  filled: true,
                  fillColor: Colors.white,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide(color: context.cashier.border),
                  ),
                  isDense: true,
                ),
              ),
              const SizedBox(height: 6),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final preset in _jobTitlePresets)
                    ActionChip(
                      label: Text(preset, style: const TextStyle(fontSize: 12)),
                      backgroundColor: _jobTitleController.text == preset
                          ? const Color(0xfffff1ed)
                          : context.cashier.surface,
                      side: BorderSide(
                        color: _jobTitleController.text == preset
                            ? const Color(0xffffdcd3)
                            : context.cashier.border,
                      ),
                      onPressed: _createdAdminId != null
                          ? null
                          : () {
                        setState(() => _jobTitleController.text = preset);
                      },
                    ),
                ],
              ),
              const SizedBox(height: 14),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _DialogFieldLabel(
                          label: _isEdit ? '登录账号（不可修改）' : '登录用户名 *',
                        ),
                        const SizedBox(height: 6),
                        TextField(
                          key: const Key('employee-form-user-name'),
                          controller: _userNameController,
                          enabled: !_isEdit && _createdAdminId == null,
                          decoration: InputDecoration(
                            hintText: '系统唯一用户名',
                            filled: true,
                            fillColor: _isEdit
                                ? const Color(0xfff5f6f7)
                                : Colors.white,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                              borderSide: BorderSide(color: context.cashier.border,
                              ),
                            ),
                            isDense: true,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _DialogFieldLabel(
                          label: _isEdit ? '重置登录密码（选填）' : '登录密码 *',
                        ),
                        const SizedBox(height: 6),
                        TextField(
                          key: const Key('employee-form-password'),
                          controller: _passwordController,
                          readOnly: _createdAdminId != null,
                          obscureText: _obscurePassword,
                          decoration: InputDecoration(
                            hintText: _isEdit ? '留空表示保持原密码不变' : '至少6位字符',
                            filled: true,
                            fillColor: Colors.white,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                              borderSide: BorderSide(color: context.cashier.border,
                              ),
                            ),
                            isDense: true,
                            suffixIcon: IconButton(
                              icon: Icon(
                                _obscurePassword
                                    ? Icons.visibility_off
                                    : Icons.visibility,
                                size: 18,
                              ),
                              onPressed: () => setState(
                                () => _obscurePassword = !_obscurePassword,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              _DialogFieldLabel(
                label: '分配角色（可多选）',
                trailing: '${_roleIds.length} 项',
              ),
              const SizedBox(height: 6),
              _OptionGrid(
                key: const Key('employee-form-roles'),
                items: [
                  for (final role in widget.roles)
                    _OptionItem(
                      id: role.id,
                      title: '${role.roleName} ${role.roleCode}',
                      subtitle: '优先级 ${role.sortOrder}',
                    ),
                ],
                selectedIds: _roleIds,
                onToggle: (id) => setState(() {
                  if (!_roleIds.remove(id)) _roleIds.add(id);
                }),
              ),
              const SizedBox(height: 16),
              _DialogFieldLabel(
                label: '管辖门店（可多选）',
                trailing: '${_shopIds.length} 项',
              ),
              const SizedBox(height: 6),
              _OptionGrid(
                key: const Key('employee-form-shops'),
                items: [
                  for (final shop in widget.shops)
                    _OptionItem(id: shop.id, title: shop.name),
                ],
                selectedIds: _shopIds,
                onToggle: (id) => setState(() {
                  if (!_shopIds.remove(id)) _shopIds.add(id);
                }),
              ),
              if (_submitError != null) ...[
                const SizedBox(height: 14),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: context.cashier.dangerBackground,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                      color: context.cashier.danger.withValues(alpha: 0.3),
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.error_outline, color: context.cashier.danger, size: 18,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          '保存失败：$_submitError',
                          style: TextStyle(
                            color: context.cashier.danger,
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                          ),
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
      actions: [
        TextButton(
          onPressed: _submitting ? null : () => Navigator.of(context).pop(false),
          child: const Text('取消'),
        ),
        FilledButton(
          key: const Key('employee-form-submit'),
          onPressed: _submitting ? null : _submit,
          style: FilledButton.styleFrom(
            backgroundColor: context.cashier.ink),
          child: Text(_submitting ? '提交中...' : _createdAdminId != null
                ? '重试角色与门店授权'
                : (_isEdit ? '保存档案' : '创建员工档案'),
          ),
        ),
      ],
    );
  }
}

// ============================================================
// 弹窗：删除员工二次确认
// ============================================================

class _DeleteEmployeeConfirmDialog extends StatefulWidget {
  const _DeleteEmployeeConfirmDialog({
    required this.repository,
    required this.employee,
  });

  final CashierSettingsRepository repository;
  final CashierAccessEmployee employee;

  @override
  State<_DeleteEmployeeConfirmDialog> createState() =>
      _DeleteEmployeeConfirmDialogState();
}

class _DeleteEmployeeConfirmDialogState
    extends State<_DeleteEmployeeConfirmDialog> {
  var _submitting = false;
  Object? _error;

  /// 服务端 409 ACCESS_EMPLOYEE_HAS_HISTORY：存在历史业务记录，禁止物理删除。
  var _conflict409 = false;

  Future<void> _handleDelete() async {
    setState(() {
      _submitting = true;
      _error = null;
      _conflict409 = false;
    });
    try {
      await widget.repository.deleteEmployee(
        adminId: widget.employee.adminId,
        confirm: true,
      );
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      final text = '$e';
      final hasHistory = text.contains('ACCESS_EMPLOYEE_HAS_HISTORY') ||
          text.contains('已有业务记录') ||
          text.contains('不能物理删除');
      setState(() {
        _submitting = false;
        _conflict409 = hasHistory;
        _error = hasHistory
            ? '该员工名下存在历史订单、收银当班、审计日志或审批流水，系统已拦截物理删除，'
                '防止财务流水与审计记录出现孤儿数据。请改为停用或标记离职，历史记录将完整保留。'
            : text;
      });
    }
  }

  /// 409 引导：改为停用 / 标记离职（保留历史记录，会话立即失效）。
  Future<void> _handleStatusGuide(String status) async {
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      await widget.repository.updateEmployeeStatus(
        adminId: widget.employee.adminId,
        status: status,
      );
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _error = '$e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final emp = widget.employee;
    final displayName = emp.realName.isNotEmpty ? emp.realName : emp.userName;
    return AlertDialog(
      title: Row(
        children: [
          Icon(Icons.warning_amber_rounded, color: context.cashier.danger, size: 24,
          ),
          const SizedBox(width: 8),
          const Text('注销并删除员工'),
        ],
      ),
      content: SizedBox(
        width: 480,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: context.cashier.dangerBackground,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: context.cashier.danger.withValues(alpha: 0.3),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '确定注销并删除员工账号「$displayName」？',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: context.cashier.danger,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '• 员工工号：${emp.workNo.isNotEmpty ? emp.workNo : '未设置'}\n'
                    '• 登录账号：${emp.userName} (ID ${emp.adminId})\n'
                    '• 所属职务：${emp.jobTitle.isNotEmpty ? emp.jobTitle : '无'}\n\n'
                    '操作影响：\n'
                    '该账号的所有历史登录凭证与会话将即刻失效；绑定的角色与门店管辖授权将被永久清空。该操作无法撤销！',
                    style: TextStyle(
                      fontSize: 13,
                      height: 1.5,
                      color: context.cashier.ink,
                    ),
                  ),
                ],
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: _conflict409
                      ? const Color(0xfffff7e6)
                      : context.cashier.dangerBackground,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(
                    color: _conflict409
                        ? const Color(0xfffde68a)
                        : context.cashier.danger.withValues(alpha: 0.3),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _conflict409 ? '$_error' : '删除失败：$_error',
                      style: TextStyle(
                        color: _conflict409
                            ? const Color(0xff92400e)
                            : context.cashier.danger,
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        height: 1.4,
                      ),
                    ),
                    if (_conflict409) ...[
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          OutlinedButton(
                            key: const Key('employee-delete-guide-disable'),
                            onPressed: _submitting
                                ? null
                                : () => _handleStatusGuide(
                                      CashierAccessEmployeeStatus.disabled,
                                    ),
                            child: const Text('改为停用'),
                          ),
                          const SizedBox(width: 8),
                          OutlinedButton(
                            key: const Key('employee-delete-guide-resign'),
                            onPressed: _submitting
                                ? null
                                : () => _handleStatusGuide(
                                      CashierAccessEmployeeStatus.resigned,
                                    ),
                            child: const Text('标记离职'),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _submitting ? null : () => Navigator.of(context).pop(false),
          child: const Text('取消'),
        ),
        FilledButton(
          key: const Key('employee-delete-confirm-btn'),
          style: FilledButton.styleFrom(
            backgroundColor: context.cashier.danger,
          ),
          onPressed: _submitting ? null : _handleDelete,
          child: Text(_submitting ? '处理中...' : '确认彻底注销'),
        ),
      ],
    );
  }
}

// ============================================================
// 弹窗：新增/编辑角色（含权限码多选）
// ============================================================

class _RoleEditDialog extends StatefulWidget {
  const _RoleEditDialog({
    required this.repository,
    required this.role,
    required this.permissionCodes,
  });

  final CashierSettingsRepository repository;
  final CashierAccessRole? role;
  final List<CashierPermissionCode> permissionCodes;

  @override
  State<_RoleEditDialog> createState() => _RoleEditDialogState();
}

class _RoleEditDialogState extends State<_RoleEditDialog> {
  late final TextEditingController _nameController;
  late final TextEditingController _codeController;
  late final TextEditingController _remarkController;
  late final TextEditingController _sortController;
  late final Set<int> _permissionIds;
  var _submitting = false;
  Object? _submitError;

  /// SoD 职责分离冲突预检结果（实时）。
  var _conflicts = <CashierAccessConflict>[];
  var _conflictLoading = false;
  Timer? _conflictDebounce;

  /// 超级管理员豁免理由（HARD 冲突二次确认后携带提交）。
  String? _forceReason;

  bool get _isEdit => widget.role != null;

  @override
  void initState() {
    super.initState();
    final role = widget.role;
    _nameController = TextEditingController(text: role?.roleName ?? '');
    _codeController = TextEditingController(text: role?.roleCode ?? '');
    _remarkController = TextEditingController(text: role?.remark ?? '');
    _sortController =
        TextEditingController(text: '${role?.sortOrder ?? 100}');
    _permissionIds = {
      for (final p in role?.permissions ?? const <CashierPermissionCodeRef>[])
        p.id,
    };
  }

  @override
  void dispose() {
    _conflictDebounce?.cancel();
    _nameController.dispose();
    _codeController.dispose();
    _remarkController.dispose();
    _sortController.dispose();
    super.dispose();
  }

  /// 当前勾选权限码列表（按 id → permissionCode 映射）。
  List<String> _selectedPermissionCodes() {
    final codes = <String>[];
    for (final code in widget.permissionCodes) {
      final id = code.id;
      if (id != null && _permissionIds.contains(id)) {
        codes.add(code.permissionCode);
      }
    }
    return codes;
  }

  /// 防抖触发冲突预检（勾选变化后 300ms 内不重复请求）。
  void _scheduleConflictCheck() {
    _conflictDebounce?.cancel();
    _conflictDebounce = Timer(const Duration(milliseconds: 300), _checkConflicts,
    );
  }

  Future<void> _checkConflicts() async {
    final codes = _selectedPermissionCodes();
    if (codes.length < 2) {
      if (mounted) {
        setState(() {
          _conflicts = const [];
          _conflictLoading = false;
        });
      }
      return;
    }
    setState(() => _conflictLoading = true);
    try {
      final conflicts = await widget.repository
          .checkAccessConflicts(permissionCodes: codes,
      );
      if (!mounted) return;
      setState(() {
        _conflicts = conflicts;
        _conflictLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _conflicts = const [];
        _conflictLoading = false;
      });
    }
  }

  Future<void> _submit({String? forceReason}) async {
    final name = _nameController.text.trim();
    final code = _codeController.text.trim();
    if (name.isEmpty || (!_isEdit && code.isEmpty)) {
      setState(() => _submitError = '请填写角色名称${_isEdit ? '' : '与编码'}');
      return;
    }
    setState(() {
      _submitting = true;
      _submitError = null;
    });
    try {
      final ids = _permissionIds.toList()..sort();
      if (_isEdit) {
        await widget.repository.updateAccessRole(
          id: widget.role!.id,
          version: widget.role!.version,
          roleName: name,
          remark: _remarkController.text.trim(),
          sortOrder: int.tryParse(_sortController.text.trim()) ?? 100,
          permissionIds: ids,
          forceReason: forceReason,
        );
      } else {
        await widget.repository.createAccessRole(
          roleCode: code,
          roleName: name,
          remark: _remarkController.text.trim(),
          sortOrder: int.tryParse(_sortController.text.trim()) ?? 100,
          permissionIds: ids,
          forceReason: forceReason,
        );
      }
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (error) {
      if (!mounted) return;
      final text = '$error';
      // 409 ACCESS_ROLE_CONFLICT：HARD 冲突被服务端拦截，需超级管理员二次确认豁免。
      if (text.contains('ACCESS_ROLE_CONFLICT') || text.contains('严禁冲突')) {
        final reason = await showDialog<String>(
          context: context,
          barrierDismissible: false,
          builder: (context) => const _ForceReasonDialog(),
        );
        if (reason != null && reason.trim().isNotEmpty && mounted) {
          _forceReason = reason.trim();
          await _submit(forceReason: _forceReason);
          return;
        }
        if (!mounted) return;
        setState(() {
          _submitting = false;
          _submitError = error;
        });
        return;
      }
      setState(() {
        _submitError = error;
        _submitting = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final hasHard = _conflicts.any((c) => c.isHard);
    return AlertDialog(
      title: Row(
        children: [
          Icon(Icons.admin_panel_settings_outlined, color: context.cashier.ink),
          const SizedBox(width: 10),
          Text(_isEdit ? '编辑角色' : '新增角色'),
        ],
      ),
      content: SizedBox(
        width: 680,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _DialogField(
                key: const Key('access-role-name'),
                controller: _nameController,
                label: '角色名称',
              ),
              const SizedBox(height: 12),
              _DialogField(
                key: const Key('access-role-code'),
                controller: _codeController,
                label: '角色编码（新增时必填，编辑不可改）',
                readOnly: _isEdit,
              ),
              const SizedBox(height: 12),
              _DialogField(
                key: const Key('access-role-remark'),
                controller: _remarkController,
                label: '备注',
              ),
              const SizedBox(height: 12),
              _DialogField(
                key: const Key('access-role-sort'),
                controller: _sortController,
                label: '优先级（sortOrder，数值小优先级高）',
                number: true,
              ),
              const SizedBox(height: 14),
              _DialogFieldLabel(
                label: '权限码（多选，保存时提交 permissionIds，覆盖式更新）',
                trailing: '${_permissionIds.length} 项',
              ),
              const SizedBox(height: 6),
              _OptionGrid(
                key: const Key('access-role-permissions'),
                items: [
                  for (final code in widget.permissionCodes)
                    _OptionItem(
                      id: code.id ?? 0,
                      title: code.permissionCode,
                      subtitle:
                          '${code.permissionName.isNotEmpty ? code.permissionName : ApprovalPermissionHelper.readableName(code.permissionCode)} · ${code.module}',
                    ),
                ],
                selectedIds: _permissionIds,
                onToggle: (id) {
                  setState(() {
                    if (!_permissionIds.remove(id)) _permissionIds.add(id);
                  });
                  _scheduleConflictCheck();
                },
              ),
              if (_conflictLoading) ...[
                const SizedBox(height: 8),
                const Row(
                  children: [
                    SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                    SizedBox(width: 8),
                    Text('正在检查职责分离冲突…', style: TextStyle(fontSize: 12)),
                  ],
                ),
              ] else if (_conflicts.isNotEmpty) ...[
                const SizedBox(height: 10),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: hasHard
                        ? const Color(0xfffee2e2)
                        : const Color(0xfffff7e6),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: hasHard
                          ? const Color(0xfffecaca)
                          : const Color(0xfffde68a),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        hasHard
                            ? '存在职责分离（SoD）严禁冲突：保存将被服务端拦截，需超级管理员说明原因后豁免'
                            : '存在软性（SOFT）职责分离冲突提示：',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: hasHard
                              ? const Color(0xffb91c1c)
                              : const Color(0xff92400e),
                        ),
                      ),
                      const SizedBox(height: 6),
                      for (final conflict in _conflicts)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 1),
                          child: Text(
                            '• ${conflict.permissionA} ↔ ${conflict.permissionB}'
                            '（${conflict.isHard ? 'HARD 严禁' : 'SOFT 提示'}）'
                            '${conflict.message.isNotEmpty ? '：${conflict.message}' : ''}',
                            style: TextStyle(
                              fontSize: 12,
                              height: 1.4,
                              color: conflict.isHard
                                  ? const Color(0xffb91c1c)
                                  : const Color(0xff92400e),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
              if (_isEdit) ...[
                const SizedBox(height: 14),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: context.cashier.warningBackground,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    '当前 version=${widget.role!.version}；保存时携带该版本号并提交所选 permissionIds。若期间被他人修改将返回 409 版本冲突。',
                    style: TextStyle(
                      fontSize: 12,
                      height: 1.5,
                      color: context.cashier.warning,
                    ),
                  ),
                ),
              ],
              if (_submitError != null) ...[
                const SizedBox(height: 12),
                Text(
                  '保存失败：$_submitError',
                  style: TextStyle(color: context.cashier.danger, fontSize: 13),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _submitting ? null : () => Navigator.of(context).pop(false),
          child: const Text('取消'),
        ),
        FilledButton(
          key: const Key('access-role-submit'),
          onPressed: _submitting ? null : _submit,
          style: FilledButton.styleFrom(
            backgroundColor: context.cashier.ink),
          child: Text(_isEdit ? '保存' : '创建'),
        ),
      ],
    );
  }
}

/// HARD 职责分离冲突二次确认：超级管理员说明合规原因（forceReason）。
class _ForceReasonDialog extends StatefulWidget {
  const _ForceReasonDialog();

  @override
  State<_ForceReasonDialog> createState() => _ForceReasonDialogState();
}

class _ForceReasonDialogState extends State<_ForceReasonDialog> {
  final _reasonController = TextEditingController();

  @override
  void dispose() {
    _reasonController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Row(
        children: [
          Icon(Icons.gavel, color: Color(0xffb91c1c), size: 24),
          SizedBox(width: 10),
          Text('职责分离冲突豁免'),
        ],
      ),
      content: SizedBox(
        width: 460,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '所选权限组合命中 HARD 级别职责分离（SoD）严禁冲突。'
              '仅超级管理员可填写合规原因后强制豁免，理由将写入审计记录。',
              style: TextStyle(fontSize: 13, height: 1.5),
            ),
            const SizedBox(height: 12),
            TextField(
              key: const Key('force-reason-input'),
              controller: _reasonController,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: '合规原因（必填）',
                hintText: '如：临时业务需要，财务轮岗期间由店长兼任',
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton(
          key: const Key('force-reason-confirm'),
          onPressed: () => Navigator.of(context).pop(_reasonController.text.trim()),
          child: const Text('确认豁免'),
        ),
      ],
    );
  }
}

// ============================================================
// 弹窗：权限解释（evaluate）
// ============================================================

class _EvaluateDialog extends StatefulWidget {
  const _EvaluateDialog({
    required this.repository,
    required this.permissionCodes,
  });

  final CashierSettingsRepository repository;
  final List<CashierPermissionCode> permissionCodes;

  @override
  State<_EvaluateDialog> createState() => _EvaluateDialogState();
}

class _EvaluateDialogState extends State<_EvaluateDialog> {
  final _userIdController = TextEditingController();
  final _shopIdController = TextEditingController();
  final _contextController = TextEditingController();
  String? _permission;
  CashierAccessEvaluation? _result;
  Object? _error;
  var _submitting = false;

  @override
  void initState() {
    super.initState();
    if (widget.permissionCodes.isNotEmpty) {
      _permission = widget.permissionCodes.first.permissionCode;
    }
  }

  @override
  void dispose() {
    _userIdController.dispose();
    _shopIdController.dispose();
    _contextController.dispose();
    super.dispose();
  }

  Future<void> _evaluate() async {
    final userId = int.tryParse(_userIdController.text.trim());
    if (userId == null || _permission == null) {
      setState(() => _error = '请输入有效的员工 ID 并选择权限码');
      return;
    }
    final shopId = int.tryParse(_shopIdController.text.trim());
    // 业务上下文（可选 JSON：amount 金额 / discountRate 折扣率 /
    // resourceType、resourceId 资源标识 / approvalToken 审批令牌）。
    Map<String, Object?>? context;
    final contextText = _contextController.text.trim();
    if (contextText.isNotEmpty) {
      try {
        final decoded = jsonDecode(contextText);
        if (decoded is Map) {
          context = decoded.cast<String, Object?>();
        } else {
          setState(() => _error = '业务上下文必须是 JSON 对象，如 {"amount": 60, "discountRate": 0.75}',
          );
          return;
        }
      } catch (_) {
        setState(() => _error = '业务上下文 JSON 格式不合法，请检查引号与逗号');
        return;
      }
    }
    setState(() {
      _submitting = true;
      _error = null;
      _result = null;
    });
    try {
      final evaluation = await widget.repository.evaluateAccess(
        userId: userId,
        shopId: shopId,
        permission: _permission!,
        context: context,
      );
      if (!mounted) return;
      setState(() => _result = evaluation);
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = error);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final allowed = _result?.isAllowed == true;
    final approvalRequired = _result?.requiresApproval == true;
    final verdictColor = allowed
        ? context.cashier.success
        : approvalRequired
            ? const Color(0xffd97706)
            : context.cashier.danger;
    final verdictBackground = allowed
        ? context.cashier.successBackground
        : approvalRequired
            ? const Color(0xfffffbeb)
            : context.cashier.dangerBackground;
    final verdictText = allowed
        ? '允许'
        : approvalRequired
            ? '放行，需审批'
            : '拒绝';
    return AlertDialog(
      title: const Row(
        children: [
          Icon(Icons.search, color: Color(0xff075985)),
          const SizedBox(width: 10),
          const Text('权限解释'),
        ],
      ),
      content: SizedBox(
        width: 540,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                key: const Key('access-evaluate-user-id'),
                controller: _userIdController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: '员工 ID（userId）',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                key: const Key('access-evaluate-shop-id'),
                controller: _shopIdController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: '门店 ID（可选，缺省用当前门店）',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                key: const Key('access-evaluate-permission'),
                initialValue: _permission,
                decoration: const InputDecoration(
                  labelText: '权限码',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                items: [
                  for (final code in widget.permissionCodes)
                    DropdownMenuItem(
                      value: code.permissionCode,
                      child: Text(
                        '${code.permissionCode}（${code.permissionName}）',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                ],
                onChanged: (value) => setState(() => _permission = value),
              ),
              const SizedBox(height: 12),
              const _DialogFieldLabel(
                label: '业务上下文（可选，JSON 对象）',
                trailing: '金额 / 折扣率 / 资源标识',
              ),
              const SizedBox(height: 6),
              TextField(
                key: const Key('access-evaluate-context'),
                controller: _contextController,
                maxLines: 3,
                decoration: const InputDecoration(
                  hintText:
                      '示例：{"amount": 60, "discountRate": 0.75, "resourceType": "ORDER", "resourceId": "20261006001"}',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
              const SizedBox(height: 16),
              Align(
                alignment: Alignment.centerRight,
                child: SettingsPrimaryButton(
                  key: const Key('access-evaluate-submit'),
                  label: _submitting ? '解析中…' : '解析权限',
                  onPressed: _submitting ? () {} : _evaluate,
                ),
              ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(
                  '解析失败：$_error',
                  style: TextStyle(color: context.cashier.danger, fontSize: 13),
                ),
              ],
              if (_result != null) ...[
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: verdictBackground,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        verdictText,
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: verdictColor,
                        ),
                      ),
                      const SizedBox(height: 6),
                      _EvalRow(label: '权限授予', value: _result!.permissionGranted ? '是' : '否',
                      ),
                      _EvalRow(label: '门店在范围内', value: _result!.shopInScope ? '是' : '否',
                      ),
                      if (_result!.policyPassed != null)
                        _EvalRow(label: '策略判定', value: _result!.policyPassed! ? '通过' : '未通过',
                        ),
                      if (_result!.approvalRequired != null)
                        _EvalRow(
                          label: '审批要求',
                          value: _result!.approvalRequired!
                              ? '需店长现场授权（approvalToken）'
                              : '无需审批',
                        ),
                      _EvalRow(
                        label: '命中角色',
                        value: _result!.matchedRoles.isEmpty
                            ? '无'
                            : _result!.matchedRoles.join('、'),
                      ),
                      if (_result!.matchedPolicies != null &&
                          _result!.matchedPolicies!.isNotEmpty)
                        _EvalRow(label: '命中策略', value: _result!.matchedPolicies!,
                        ),
                      if (_result!.reasonCode != null &&
                          _result!.reasonCode!.isNotEmpty)
                        _EvalRow(label: '原因码', value: _result!.reasonCode!),
                      if (_result!.priority != null)
                        _EvalRow(label: '优先级', value: '${_result!.priority}'),
                      if (_result!.rule != null && _result!.rule!.isNotEmpty)
                        _EvalRow(label: '规则', value: _result!.rule!),
                      if (_result!.explanation != null &&
                          _result!.explanation!.isNotEmpty)
                        _EvalRow(label: '说明', value: _result!.explanation!),
                      if (_result!.approval != null &&
                          _result!.approval!.isNotEmpty)
                        _EvalRow(label: '审批信息', value: _result!.approval!),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('关闭'),
        ),
      ],
    );
  }
}

class _EvalRow extends StatelessWidget {
  const _EvalRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 6),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 80,
          child: Text(
            label,
            style: TextStyle(fontSize: 12, color: context.cashier.inkMuted),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
          ),
        ),
      ],
    ),
  );
}

// ============================================================
// 弹窗：接口权限映射
// ============================================================

class _ApiPermissionEditDialog extends StatefulWidget {
  const _ApiPermissionEditDialog({
    required this.repository,
    required this.item,
    required this.permissionCodes,
  });

  final CashierSettingsRepository repository;
  final CashierApiPermission? item;
  final List<CashierPermissionCode> permissionCodes;

  @override
  State<_ApiPermissionEditDialog> createState() =>
      _ApiPermissionEditDialogState();
}

class _ApiPermissionEditDialogState extends State<_ApiPermissionEditDialog> {
  static const _methods = ['GET', 'POST', 'PUT', 'DELETE', '*'];

  late final TextEditingController _pathController;
  late final TextEditingController _remarkController;
  late String _method;
  String? _permissionCode;
  var _submitting = false;
  Object? _submitError;

  bool get _isEdit => widget.item != null;

  @override
  void initState() {
    super.initState();
    final item = widget.item;
    _pathController = TextEditingController(text: item?.pathPattern ?? '');
    _remarkController = TextEditingController(text: item?.remark ?? '');
    _method = item?.method ?? 'GET';
    _permissionCode = item?.permissionCode;
  }

  @override
  void dispose() {
    _pathController.dispose();
    _remarkController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final path = _pathController.text.trim();
    if (path.isEmpty || _permissionCode == null) {
      setState(() => _submitError = '请填写路径模式并选择权限码');
      return;
    }
    setState(() {
      _submitting = true;
      _submitError = null;
    });
    try {
      await widget.repository.saveApiPermission(
        id: _isEdit ? widget.item!.id : null,
        method: _method,
        pathPattern: path,
        permissionCode: _permissionCode!,
        remark: _remarkController.text.trim(),
      );
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _submitError = error;
        _submitting = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Row(
        children: [
          const Icon(Icons.add_link, color: Color(0xff075985)),
          const SizedBox(width: 10),
          Text(_isEdit ? '编辑接口映射' : '新增接口映射'),
        ],
      ),
      content: SizedBox(
        width: 560,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const _DialogFieldLabel(label: '请求方法（* 表示任意方法）'),
              const SizedBox(height: 6),
              DropdownButtonFormField<String>(
                key: const Key('access-api-method'),
                initialValue: _method,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                items: [
                  for (final m in _methods)
                    DropdownMenuItem(value: m, child: Text(m)),
                ],
                onChanged: (value) =>
                    setState(() => _method = value ?? _method),
              ),
              const SizedBox(height: 12),
              TextField(
                key: const Key('access-api-path'),
                controller: _pathController,
                decoration: const InputDecoration(
                  labelText: '路径模式 path_pattern（支持 {id} 占位，同一路径全局唯一）',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
              const SizedBox(height: 12),
              const _DialogFieldLabel(label: '权限码（须已存在于权限码管理）'),
              const SizedBox(height: 6),
              DropdownButtonFormField<String>(
                key: const Key('access-api-permission-code'),
                initialValue: _permissionCode,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                items: [
                  for (final code in widget.permissionCodes)
                    DropdownMenuItem(
                      value: code.permissionCode,
                      child: Text(
                        '${code.permissionCode}（${code.permissionName}）',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                ],
                onChanged: (value) =>
                    setState(() => _permissionCode = value),
              ),
              const SizedBox(height: 12),
              TextField(
                key: const Key('access-api-remark'),
                controller: _remarkController,
                decoration: const InputDecoration(
                  labelText: '备注',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
              const SizedBox(height: 14),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: context.cashier.warningBackground,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '保存后服务端自动 reload 内存映射并立即生效；变更同时写入安全审计日志。',
                  style: TextStyle(
                    fontSize: 12,
                    height: 1.5,
                    color: context.cashier.warning,
                  ),
                ),
              ),
              if (_submitError != null) ...[
                const SizedBox(height: 12),
                Text(
                  '保存失败：$_submitError',
                  style: TextStyle(color: context.cashier.danger, fontSize: 13),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _submitting ? null : () => Navigator.of(context).pop(false),
          child: const Text('取消'),
        ),
        FilledButton(
          key: const Key('access-api-submit'),
          onPressed: _submitting ? null : _submit,
          style: FilledButton.styleFrom(
            backgroundColor: context.cashier.ink),
          child: Text(_isEdit ? '保存' : '新增'),
        ),
      ],
    );
  }
}

// ============================================================
// 弹窗：权限码
// ============================================================

class _PermissionCodeEditDialog extends StatefulWidget {
  const _PermissionCodeEditDialog({
    required this.repository,
    required this.item,
  });

  final CashierSettingsRepository repository;
  final CashierPermissionCode? item;

  @override
  State<_PermissionCodeEditDialog> createState() =>
      _PermissionCodeEditDialogState();
}

class _PermissionCodeEditDialogState extends State<_PermissionCodeEditDialog> {
  late final TextEditingController _codeController;
  late final TextEditingController _nameController;
  late final TextEditingController _moduleController;
  late final TextEditingController _remarkController;
  late final TextEditingController _sortController;
  var _submitting = false;
  Object? _submitError;

  bool get _isEdit => widget.item != null;

  @override
  void initState() {
    super.initState();
    final item = widget.item;
    _codeController = TextEditingController(text: item?.permissionCode ?? '');
    _nameController = TextEditingController(text: item?.permissionName ?? '');
    _moduleController = TextEditingController(text: item?.module ?? '');
    _remarkController = TextEditingController(text: item?.remark ?? '');
    _sortController = TextEditingController(text: '${item?.sortOrder ?? 0}');
  }

  @override
  void dispose() {
    _codeController.dispose();
    _nameController.dispose();
    _moduleController.dispose();
    _remarkController.dispose();
    _sortController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final code = _codeController.text.trim();
    final name = _nameController.text.trim();
    if (code.isEmpty || name.isEmpty) {
      setState(() => _submitError = '请填写权限编码与权限名称');
      return;
    }
    setState(() {
      _submitting = true;
      _submitError = null;
    });
    try {
      await widget.repository.savePermissionCode(
        id: _isEdit ? widget.item!.id : null,
        permissionCode: code,
        permissionName: name,
        module: _moduleController.text.trim(),
        remark: _remarkController.text.trim(),
        sortOrder: int.tryParse(_sortController.text.trim()) ?? 0,
      );
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _submitError = error;
        _submitting = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Row(
        children: [
          const Icon(Icons.vpn_key_outlined, color: Color(0xff075985)),
          const SizedBox(width: 10),
          Text(_isEdit ? '编辑权限码' : '新增权限码'),
        ],
      ),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                key: const Key('access-permission-code-code'),
                controller: _codeController,
                readOnly: _isEdit,
                decoration: InputDecoration(
                  labelText: '权限编码（新增时必填，编辑不可改）',
                  border: const OutlineInputBorder(),
                  isDense: true,
                  filled: _isEdit,
                  fillColor: context.cashier.row,
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                key: const Key('access-permission-code-name'),
                controller: _nameController,
                decoration: const InputDecoration(
                  labelText: '权限名称',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                key: const Key('access-permission-code-module'),
                controller: _moduleController,
                decoration: const InputDecoration(
                  labelText: '模块 module（如 order / user / cashier）',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                key: const Key('access-permission-code-remark'),
                controller: _remarkController,
                decoration: const InputDecoration(
                  labelText: '备注',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                key: const Key('access-permission-code-sort'),
                controller: _sortController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: '排序 sort_order（数值小在前）',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
              if (_submitError != null) ...[
                const SizedBox(height: 12),
                Text(
                  '保存失败：$_submitError',
                  style: TextStyle(color: context.cashier.danger, fontSize: 13),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _submitting ? null : () => Navigator.of(context).pop(false),
          child: const Text('取消'),
        ),
        FilledButton(
          key: const Key('access-permission-code-submit'),
          onPressed: _submitting ? null : _submit,
          style: FilledButton.styleFrom(
            backgroundColor: context.cashier.ink),
          child: Text(_isEdit ? '保存' : '创建'),
        ),
      ],
    );
  }
}

// ============================================================
// 通用小组件
// ============================================================

class _AccessPageHeader extends StatelessWidget {
  const _AccessPageHeader({
    required this.title,
    required this.subtitle,
    this.actions = const [],
  });

  final String title;
  final String subtitle;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                subtitle,
                style: TextStyle(
                  fontSize: 13,
                  height: 1.5,
                  color: context.cashier.inkMuted,
                ),
              ),
            ],
          ),
        ),
        if (actions.isNotEmpty) ...[
          const SizedBox(width: 16),
          Wrap(spacing: 10, runSpacing: 8, children: actions),
        ],
      ],
    );
  }
}

class _ToolbarButton extends StatelessWidget {
  const _ToolbarButton({
    super.key,
    required this.icon,
    required this.label,
    required this.onPressed,
    this.primary = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onPressed;
  final bool primary;

  @override
  Widget build(BuildContext context) {
    final style = primary
        ? FilledButton.styleFrom(
            backgroundColor: context.cashier.ink,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          )
        : OutlinedButton.styleFrom(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          );
    final child = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 17),
        const SizedBox(width: 6),
        Text(label)],
    );
    return SizedBox(
      height: 48,
      child: primary
          ? FilledButton(
              onPressed: onPressed,
              style: style,
              child: child)
          : OutlinedButton(
              onPressed: onPressed,
              style: style,
              child: child),
    );
  }
}

class _StatsStrip extends StatelessWidget {
  const _StatsStrip({required this.items});

  final List<_StatItem> items;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        for (var i = 0; i < items.length; i++) ...[
          if (i > 0) const SizedBox(width: 12),
          Expanded(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              decoration: _surface(context),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    items[i].label,
                    style: TextStyle(fontSize: 14, color: context.cashier.inkMuted,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    items[i].value,
                    style: TextStyle(
                      fontSize: items[i].small ? 18 : 26,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _StatItem {
  const _StatItem({
    required this.label,
    required this.value,
    this.small = false,
  });

  final String label;
  final String value;
  final bool small;
}

class _TagRow extends StatelessWidget {
  const _TagRow({required this.label, required this.chips});

  final String label;
  final List<Widget> chips;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 76,
          child: Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              label,
              style: TextStyle(fontSize: 13, color: context.cashier.inkMuted),
            ),
          ),
        ),
        Expanded(
          child: Wrap(spacing: 6, runSpacing: 6, children: chips)),
      ],
    );
  }
}

class _AccessChip extends StatelessWidget {
  const _AccessChip({required this.text, this.accent = false, this.shop = false,
  });

  final String text;
  final bool accent;
  final bool shop;

  @override
  Widget build(BuildContext context) {
    final (background, foreground) = accent
        ? (context.cashier.selectedBackground, const Color(0xff075985))
        : shop
            ? (const Color(0xfff5f3ff), const Color(0xff5b21b6))
            : (context.cashier.row, context.cashier.ink);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        text,
        style: TextStyle(fontSize: 12, color: foreground)),
    );
  }
}

class _MethodChip extends StatelessWidget {
  const _MethodChip({required this.method});

  final String method;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
    decoration: BoxDecoration(
      color: context.cashier.selectedBackground,
      borderRadius: BorderRadius.circular(6),
    ),
    child: Text(
      method,
      style: const TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w700,
        color: Color(0xff075985),
      ),
    ),
  );
}

class _TableHeader extends StatelessWidget {
  const _TableHeader({required this.columns});

  final List<String> columns;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
    decoration: BoxDecoration(color: context.cashier.row),
    child: Row(
      children: [
        for (var i = 0; i < columns.length; i++)
          _TableCell(
            flex: i == 0 ? 1 : (i == 1 ? 4 : (i == 2 ? 3 : (i == 3 ? 3 : 2))),
            child: Text(
              columns[i],
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: context.cashier.inkMuted,
              ),
            ),
          ),
      ],
    ),
  );
}

class _TableCell extends StatelessWidget {
  const _TableCell({required this.child, this.flex = 1});

  final Widget child;
  final int flex;

  @override
  Widget build(BuildContext context) => Expanded(flex: flex, child: child);
}

class _PaginationBar extends StatelessWidget {
  const _PaginationBar({
    required this.page,
    required this.total,
    required this.pageSize,
    required this.onPrevious,
    required this.onNext,
  });

  final int page;
  final int total;
  final int pageSize;
  final VoidCallback? onPrevious;
  final VoidCallback? onNext;

  @override
  Widget build(BuildContext context) {
    final maxPage = (total / pageSize).ceil();
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        Text(
          '共 $total 条',
          style: TextStyle(fontSize: 13, color: context.cashier.inkMuted),
        ),
        const SizedBox(width: 10),
        _PageButton(icon: Icons.chevron_left, onPressed: onPrevious),
        const SizedBox(width: 8),
        Text('$page / $maxPage', style: const TextStyle(fontSize: 13)),
        const SizedBox(width: 8),
        _PageButton(icon: Icons.chevron_right, onPressed: onNext),
      ],
    );
  }
}

class _PageButton extends StatelessWidget {
  const _PageButton({required this.icon, required this.onPressed});

  final IconData icon;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 34,
    height: 34,
    child: OutlinedButton(
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        padding: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8)),
      ),
      child: Icon(icon, size: 18),
    ),
  );
}

class _DialogFieldLabel extends StatelessWidget {
  const _DialogFieldLabel({required this.label, this.trailing});

  final String label;
  final String? trailing;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Text(
        label,
        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
      ),
      const Spacer(),
      if (trailing != null)
        Text(
          trailing!,
          style: TextStyle(fontSize: 12, color: context.cashier.inkMuted),
        ),
    ],
  );
}

class _DialogField extends StatelessWidget {
  const _DialogField({
    super.key,
    required this.controller,
    required this.label,
    this.readOnly = false,
    this.number = false,
  });

  final TextEditingController controller;
  final String label;
  final bool readOnly;
  final bool number;

  @override
  Widget build(BuildContext context) => TextField(
    controller: controller,
    readOnly: readOnly,
    keyboardType: number ? TextInputType.number : null,
    decoration: InputDecoration(
      labelText: label,
      border: const OutlineInputBorder(),
      isDense: true,
      filled: readOnly,
      fillColor: context.cashier.row,
    ),
  );
}

class _OptionItem {
  const _OptionItem({
    required this.id,
    required this.title,
    this.subtitle});

  final int id;
  final String title;
  final String? subtitle;
}

class _OptionGrid extends StatelessWidget {
  const _OptionGrid({
    super.key,
    required this.items,
    required this.selectedIds,
    required this.onToggle,
  });

  final List<_OptionItem> items;
  final Set<int> selectedIds;
  final ValueChanged<int> onToggle;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 600 ? 2 : 1;
        final width = (constraints.maxWidth - 10 * (columns - 1)) / columns;
        return Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            for (final item in items)
              SizedBox(
                width: width,
                child: _OptionCard(
                  item: item,
                  selected: selectedIds.contains(item.id),
                  onTap: () => onToggle(item.id),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _OptionCard extends StatelessWidget {
  const _OptionCard({
    required this.item,
    required this.selected,
    required this.onTap,
  });

  final _OptionItem item;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final accent = const Color(0xff075985);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: selected ? context.cashier.selectedBackground : Colors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: selected ? accent : context.cashier.border),
        ),
        child: Row(
          children: [
            Icon(
              selected
                  ? Icons.check_box
                  : Icons.check_box_outline_blank,
              size: 18,
              color: selected ? accent : context.cashier.inkMuted,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.title,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (item.subtitle != null && item.subtitle!.isNotEmpty)
                    Text(
                      item.subtitle!,
                      style: TextStyle(
                        fontSize: 12,
                        color: context.cashier.inkMuted,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

BoxDecoration _surface(BuildContext context) => BoxDecoration(
  color: context.cashier.surface,
  border: Border.all(color: context.cashier.border),
  borderRadius: BorderRadius.circular(12),
);

String _fmtTime(DateTime? time) {
  if (time == null) return '';
  String two(int v) => v.toString().padLeft(2, '0');
  return '${time.year}-${two(time.month)}-${two(time.day)} '
      '${two(time.hour)}:${two(time.minute)}';
}

/// 审批记录人员展示：优先 姓名·工号；缺失时回退 #id（对齐 UI031 原型）。
String _personLabel(String? name, String? workNo, int? id) {
  final hasName = name != null && name.isNotEmpty;
  final hasNo = workNo != null && workNo.isNotEmpty;
  if (hasName && hasNo) return '$name·$workNo';
  if (hasName) return name;
  if (hasNo) return workNo;
  return id == null ? '—' : '#$id';
}

Future<void> _showActionError(
  BuildContext context,
  String title,
  Object error,
) {
  return showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: Text('$error'),
      actions: [
        FilledButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('我知道了'),
        ),
      ],
    ),
  );
}

// ============================================================
// 审批记录
// ============================================================

class _ApprovalsUnavailable extends StatelessWidget {
  const _ApprovalsUnavailable();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.approval_outlined,
              size: 42,
              color: context.cashier.inkMuted,
            ),
            const SizedBox(height: 12),
            Text(
              '审批记录需要客户端上下文支持，当前环境不可用。',
              style: TextStyle(color: context.cashier.inkMuted),
            ),
          ],
        ),
      ),
    );
  }
}

/// 审批记录：展示店长现场授权流水的状态流转（待使用/已签发/已核销/过期等）。
class _ApprovalsSection extends StatefulWidget {
  const _ApprovalsSection({super.key, required this.repository});

  final AccessApprovalRepository repository;

  @override
  State<_ApprovalsSection> createState() => _ApprovalsSectionState();
}

class _ApprovalsSectionState extends State<_ApprovalsSection> {
  static const _pageSize = 20;

  AccessApprovalPage? _page;
  bool _loading = false;
  String? _error;
  String? _status;
  int _currentPage = 1;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load({int? page}) async {
    final target = page ?? _currentPage;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final result = await widget.repository.listApprovals(
        page: target,
        pageSize: _pageSize,
        status: _status,
      );
      if (!mounted) return;
      setState(() {
        _page = result;
        _currentPage = result.page;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = '$error';
      });
    }
  }

  void _applyStatus(String? value) {
    if (_status == value) return;
    _status = value;
    _load(page: 1);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final page = _page;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              '审批流水',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: theme.colorScheme.onSurface,
              ),
            ),
            const SizedBox(width: 12),
            Text(
              '店长现场授权记录（POST /cashier/access/authorize 签发，敏感操作携带 approvalToken 核销）',
              style: TextStyle(
                fontSize: 12,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        Wrap(
          spacing: 8,
          children: [
            for (final option in const <(String?, String)>[
              (null, '全部状态'),
              (AccessApprovalStatus.pending, '待使用'),
              (AccessApprovalStatus.approved, '已签发'),
              (AccessApprovalStatus.consumed, '已核销'),
              (AccessApprovalStatus.expired, '已过期'),
              (AccessApprovalStatus.revoked, '已撤销'),
              (AccessApprovalStatus.rejected, '已拒绝'),
            ])
              FilterChip(
                label: Text(option.$2),
                selected: _status == option.$1,
                onSelected: (_) => _applyStatus(option.$1),
              ),
          ],
        ),
        const SizedBox(height: 14),
        Expanded(
          child: _buildBody(context)),
        const SizedBox(height: 12),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              page == null
                  ? ''
                  : '共 ${page.total} 条 · 第 ${page.page} 页',
              style: TextStyle(
                fontSize: 12,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            Row(
              children: [
                OutlinedButton(
                  onPressed: _loading || _currentPage <= 1
                      ? null
                      : () => _load(page: _currentPage - 1),
                  child: const Text('上一页'),
                ),
                const SizedBox(width: 8),
                OutlinedButton(
                  onPressed: _loading || page == null || !page.hasMore
                      ? null
                      : () => _load(page: _currentPage + 1),
                  child: const Text('下一页'),
                ),
              ],
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildBody(BuildContext context) {
    final theme = Theme.of(context);
    if (_loading) {
      return const Center(
        child: CircularProgressIndicator(strokeWidth: 2.5));
    }
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('加载失败：$_error', style: const TextStyle(fontSize: 13)),
            const SizedBox(height: 10),
            OutlinedButton(
              onPressed: _load,
              child: const Text('重试')),
          ],
        ),
      );
    }
    final records = _page?.items ?? const <AccessApprovalRecord>[];
    if (records.isEmpty) {
      return Center(
        child: Text(
          '暂无审批记录',
          style: TextStyle(
            fontSize: 13,
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      );
    }
    return ListView.separated(
      itemCount: records.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (context, index) => _ApprovalRecordCard(
        record: records[index],
        onTap: () => _openDetail(records[index]),
      ),
    );
  }

  Future<void> _openDetail(AccessApprovalRecord record) async {
    await showDialog<void>(
      context: context,
      builder: (context) => _ApprovalDetailDialog(
        repository: widget.repository,
        record: record),
    );
  }
}

/// 审批记录详情弹窗（GET /admin/access/approvals/{id}）。
class _ApprovalDetailDialog extends StatefulWidget {
  const _ApprovalDetailDialog({
    required this.repository,
    required this.record});

  final AccessApprovalRepository repository;
  final AccessApprovalRecord record;

  @override
  State<_ApprovalDetailDialog> createState() => _ApprovalDetailDialogState();
}

class _ApprovalDetailDialogState extends State<_ApprovalDetailDialog> {
  AccessApprovalRecord? _detail;
  Object? _error;
  var _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final detail = await widget.repository.loadApprovalDetail(widget.record.id,
      );
      if (!mounted) return;
      setState(() {
        _detail = detail ?? widget.record;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error;
        _loading = false;
        // 详情接口失败时回退展示列表行数据，保证可追溯性。
        _detail = widget.record;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final record = _detail ?? widget.record;
    final statusColor = switch (record.status) {
      AccessApprovalStatus.consumed => Colors.green,
      AccessApprovalStatus.approved => Colors.blue,
      AccessApprovalStatus.pending => Colors.orange,
      AccessApprovalStatus.expired => Colors.grey,
      AccessApprovalStatus.revoked || AccessApprovalStatus.rejected =>
        Colors.red,
      _ => Colors.grey,
    };

    Widget row(String label, String value) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 110,
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 12,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
              Expanded(
                child: Text(
                  value,
                  style: const TextStyle(fontSize: 12.5))),
            ],
          ),
        );

    return AlertDialog(
      title: Row(
        children: [
          const Icon(Icons.receipt_long_outlined,
              color: Color(0xff075985), size: 24,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              '审批详情 · ${record.approvalNo.isEmpty ? '#${record.id}' : record.approvalNo}',
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
      content: SizedBox(
        width: 520,
        child: _loading
            ? const Padding(
                padding: EdgeInsets.all(24),
                child: Center(child: CircularProgressIndicator(strokeWidth: 2.5),
                ),
              )
            : SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (_error != null) ...[
                      Text(
                        '详情加载失败（已展示列表数据）：$_error',
                        style: const TextStyle(fontSize: 12, color: Colors.orange,
                        ),
                      ),
                      const SizedBox(height: 8),
                    ],
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: statusColor.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text(
                            AccessApprovalStatus.label(record.status),
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: statusColor,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        if (record.authMethod != null)
                          Text(
                            AccessApprovalAuthMethod.label(record.authMethod),
                            style: TextStyle(
                              fontSize: 12,
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    row('审批编号', record.approvalNo.isEmpty ? '—' : record.approvalNo,
                    ),
                    row('权限码', record.permissionCode.isEmpty ? '—' : record.permissionCode,
                    ),
                    row('业务类型', record.bizType ?? '—'),
                    row('业务单号', record.bizId == null || record.bizId!.isEmpty ? '—' : record.bizId!,
                    ),
                    row('操作员工', _personLabel(record.operatorName, record.operatorWorkNo, record.operatorId,
                      ),
                    ),
                    row('授权店长', _personLabel(record.authorizerName, record.authorizerWorkNo, record.authorizerId,
                      ),
                    ),
                    row('门店', record.shopId == null ? '—' : '#${record.shopId}',
                    ),
                    row(
                      '金额',
                      record.amount == null
                          ? '—'
                          : '¥${record.amount!.toStringAsFixed(2)}',
                    ),
                    row(
                      '最大允许金额',
                      record.maxAmount == null
                          ? '—'
                          : '¥${record.maxAmount!.toStringAsFixed(2)}',
                    ),
                    row('授权原因', record.reason == null || record.reason!.isEmpty ? '—' : record.reason!,
                    ),
                    row(
                      '创建时间',
                      record.createdAt == null ? '—' : _fmtTime(record.createdAt!),
                    ),
                    row(
                      '过期时间',
                      record.expiresAt == null ? '—' : _fmtTime(record.expiresAt!),
                    ),
                    if (record.consumedAt != null)
                      row('核销时间', _fmtTime(record.consumedAt!)),
                  ],
                ),
              ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('关闭'),
        ),
      ],
    );
  }
}

class _ApprovalRecordCard extends StatelessWidget {
  const _ApprovalRecordCard({required this.record, this.onTap});

  final AccessApprovalRecord record;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final status = record.status;
    final statusLabel = AccessApprovalStatus.label(status);
    final statusColor = switch (status) {
      AccessApprovalStatus.consumed => Colors.green,
      AccessApprovalStatus.approved => Colors.blue,
      AccessApprovalStatus.pending => Colors.orange,
      AccessApprovalStatus.expired => Colors.grey,
      AccessApprovalStatus.revoked || AccessApprovalStatus.rejected =>
        Colors.red,
      _ => Colors.grey,
    };

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: theme.dividerColor),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 第一行：审批单号 + 状态徽标
            Row(
              children: [
                Expanded(
                  child: Text(
                    record.approvalNo.isEmpty
                        ? '审批 #${record.id}'
                        : record.approvalNo,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    statusLabel,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: statusColor,
                    ),
                  ),
                ),
              ],
            ),
            // 第二行：权限码 · 业务 · 单号
            const SizedBox(height: 6),
            Text(
              [
                if (record.permissionCode.isNotEmpty) record.permissionCode,
                if (record.bizType != null) '业务: ${record.bizType}',
                if (record.bizId != null && record.bizId!.isNotEmpty)
                  '单号: ${record.bizId}',
              ].join(' · '),
              style: TextStyle(
                fontSize: 12,
                color: theme.colorScheme.onSurfaceVariant,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            // 第三行：操作人 / 授权人（姓名 + 工号，对齐 UI031 原型 rec-people）
            if (record.operatorId != null || record.authorizerId != null) ...[
              const SizedBox(height: 8),
              Wrap(
                spacing: 18,
                runSpacing: 6,
                children: [
                  if (record.operatorId != null)
                    _RecordPersonField(
                      label: '操作人',
                      name: record.operatorName,
                      workNo: record.operatorWorkNo,
                      id: record.operatorId,
                    ),
                  if (record.authorizerId != null)
                    _RecordPersonField(
                      label: '授权人',
                      name: record.authorizerName,
                      workNo: record.authorizerWorkNo,
                      id: record.authorizerId,
                    ),
                ],
              ),
            ],
            // 第四行：时间 · 授权方式（等宽小灰字）
            if (record.createdAt != null || record.authMethod != null) ...[
              const SizedBox(height: 8),
              Text(
                [
                  if (record.createdAt != null) _fmtTime(record.createdAt!),
                  if (record.authMethod != null)
                    '授权方式 ${AccessApprovalAuthMethod.label(record.authMethod)}',
                ].join(' · '),
                style: TextStyle(
                  fontSize: 11.5,
                  color: theme.colorScheme.onSurfaceVariant,
                  fontFamily: 'Roboto',
                  letterSpacing: 0.3,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// 记录卡片人员字段：标签 + 姓名 + 工号（工号灰色等宽，对齐 UI031 原型）。
class _RecordPersonField extends StatelessWidget {
  const _RecordPersonField({
    required this.label,
    required this.name,
    required this.workNo,
    required this.id,
  });

  final String label;
  final String? name;
  final String? workNo;
  final int? id;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasName = name != null && name!.isNotEmpty;
    final hasNo = workNo != null && workNo!.isNotEmpty;
    final displayName =
        hasName ? name! : (id != null ? '#$id' : (hasNo ? workNo! : '—'));
    final displayNo = hasNo ? workNo! : '';
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 12.5,
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(width: 5),
        Text(
          displayName,
          style: const TextStyle(
            fontSize: 12.5,
            fontWeight: FontWeight.w600),
        ),
        if (displayNo.isNotEmpty) ...[
          const SizedBox(width: 4),
          Text(
            displayNo,
            style: TextStyle(
              fontSize: 11.5,
              color: theme.colorScheme.onSurfaceVariant,
              fontFamily: 'Roboto',
              letterSpacing: 0.3,
            ),
          ),
        ],
      ],
    );
  }
}
