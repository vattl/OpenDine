import 'package:flutter/material.dart';

import '../../../core/admin_api_client.dart';
import '../../../core/api_contract.dart';
import '../../../core/app_state.dart';
import '../../../core/shop_summary.dart';

/// 员工模型（对齐 /admin/administrator/list 返回结构）
class EmployeeItem {
  const EmployeeItem({
    required this.id,
    required this.userName,
    required this.workNo,
    required this.realName,
    required this.jobTitle,
    required this.displayName,
    required this.roleIds,
    required this.roles,
    required this.scope,
    required this.shopIds,
    required this.shops,
  });

  final int id;
  final String userName;
  final String workNo;
  final String realName;
  final String jobTitle;
  final String displayName;
  final List<int> roleIds;
  final List<Map<String, Object?>> roles;
  final String scope;
  final List<int> shopIds;
  final List<ShopSummary> shops;

  factory EmployeeItem.fromJson(Map<String, Object?> json) {
    final rawRoles = json['roles'] as List? ?? const [];
    final rolesList = rawRoles.whereType<Map>().map((r) => r.cast<String, Object?>()).toList();
    final rawRoleIds = json['roleIds'] as List? ?? const [];
    final roleIdsList = rawRoleIds.whereType<num>().map((n) => n.toInt()).toList();

    final rawShops = json['shops'] as List? ?? const [];
    final shopsList = rawShops.whereType<Map>().map((s) {
      final id = (s['id'] as num?)?.toInt() ?? 0;
      final code = (s['code'] ?? s['shopCode'] ?? '').toString();
      final name = (s['name'] ?? s['shopName'] ?? '').toString();
      return ShopSummary(id: id, code: code, name: name);
    }).toList();
    final rawShopIds = json['shopIds'] as List? ?? const [];
    final shopIdsList = rawShopIds.whereType<num>().map((n) => n.toInt()).toList();

    final workNo = (json['workNo'] ?? json['work_no'] ?? '').toString().trim();
    final realName = (json['realName'] ?? json['real_name'] ?? '').toString().trim();
    final jobTitle = (json['jobTitle'] ?? json['job_title'] ?? '').toString().trim();
    final userName = (json['userName'] ?? json['username'] ?? '').toString().trim();
    final displayName = (json['displayName'] ?? json['name'] ?? (realName.isNotEmpty ? realName : userName)).toString().trim();

    return EmployeeItem(
      id: (json['id'] as num?)?.toInt() ?? 0,
      userName: userName,
      workNo: workNo,
      realName: realName,
      jobTitle: jobTitle,
      displayName: displayName.isNotEmpty ? displayName : (userName.isNotEmpty ? userName : '员工 #$json["id"]'),
      roleIds: roleIdsList,
      roles: rolesList,
      scope: (json['scope'] ?? 'SHOP').toString(),
      shopIds: shopIdsList,
      shops: shopsList,
    );
  }
}

/// 角色选项
class EmployeeRoleOption {
  const EmployeeRoleOption({
    required this.id,
    required this.roleCode,
    required this.roleName,
  });

  final int id;
  final String roleCode;
  final String roleName;

  factory EmployeeRoleOption.fromJson(Map<String, Object?> json) {
    return EmployeeRoleOption(
      id: (json['id'] as num?)?.toInt() ?? 0,
      roleCode: (json['role_code'] ?? json['roleCode'] ?? '').toString(),
      roleName: (json['role_name'] ?? json['roleName'] ?? '').toString(),
    );
  }
}

/// 员工管理视图 (Employee Management View)
/// 契约见《员工工号与真实姓名管理体系前端接入与UI改造规范》§4.3
class EmployeeListView extends StatefulWidget {
  const EmployeeListView({
    super.key,
    required this.appState,
    required this.client,
  });

  final AppState appState;
  final AdminApiClient client;

  @override
  State<EmployeeListView> createState() => _EmployeeListViewState();
}

class _EmployeeListViewState extends State<EmployeeListView> {
  final _searchController = TextEditingController();
  var _selectedShopId = ''; // '' 表示全部门店

  var _loading = true;
  String? _errorMessage;

  var _allEmployees = <EmployeeItem>[];
  var _allRoles = <EmployeeRoleOption>[];
  var _allShops = <ShopSummary>[];

  // 分页状态
  var _page = 1;
  final _pageSize = 10;

  @override
  void initState() {
    super.initState();
    _fetchData();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _fetchData() async {
    setState(() {
      _loading = true;
      _errorMessage = null;
    });

    try {
      final res = await widget.client.get(adminAdministratorListEndpoint);
      final data = res is Map ? res.cast<String, Object?>() : <String, Object?>{};
      final rawList = data['list'] as List? ?? const [];
      final employees = rawList
          .whereType<Map>()
          .map((m) => EmployeeItem.fromJson(m.cast<String, Object?>()))
          .toList();

      final rawRoles = data['allRoles'] as List? ?? const [];
      final roles = rawRoles
          .whereType<Map>()
          .map((m) => EmployeeRoleOption.fromJson(m.cast<String, Object?>()))
          .toList();

      // 从 appState 或接口收集所有门店
      final shopsMap = <int, ShopSummary>{};
      for (final s in widget.appState.shops) {
        shopsMap[s.id] = s;
      }
      for (final emp in employees) {
        for (final s in emp.shops) {
          shopsMap[s.id] = s;
        }
      }

      if (!mounted) return;
      setState(() {
        _allEmployees = employees;
        _allRoles = roles;
        _allShops = shopsMap.values.toList()..sort((a, b) => a.id.compareTo(b.id));
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _errorMessage = '加载员工列表失败：$e';
      });
    }
  }

  List<EmployeeItem> get _filteredEmployees {
    final keyword = _searchController.text.trim().toLowerCase();
    final filterShopId = int.tryParse(_selectedShopId);

    return _allEmployees.where((emp) {
      if (filterShopId != null && filterShopId > 0) {
        if (!emp.shopIds.contains(filterShopId) && emp.scope != 'HQ') {
          return false;
        }
      }
      if (keyword.isNotEmpty) {
        final matchWorkNo = emp.workNo.toLowerCase().contains(keyword);
        final matchRealName = emp.realName.toLowerCase().contains(keyword);
        final matchJobTitle = emp.jobTitle.toLowerCase().contains(keyword);
        final matchUserName = emp.userName.toLowerCase().contains(keyword);
        final matchDisplayName = emp.displayName.toLowerCase().contains(keyword);
        if (!matchWorkNo && !matchRealName && !matchJobTitle && !matchUserName && !matchDisplayName) {
          return false;
        }
      }
      return true;
    }).toList();
  }

  void _resetFilter() {
    _searchController.clear();
    setState(() {
      _selectedShopId = '';
      _page = 1;
    });
  }

  void _openCreateOrEditDialog({EmployeeItem? employee}) {
    showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => _EmployeeFormDialog(
        client: widget.client,
        appState: widget.appState,
        allRoles: _allRoles,
        allShops: _allShops,
        employee: employee,
      ),
    ).then((saved) {
      if (saved == true) {
        _fetchData();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(employee == null ? '员工创建成功' : '员工信息已保存'),
            backgroundColor: const Color(0xff22863a),
          ),
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filteredEmployees;
    final totalCount = filtered.length;
    final maxPage = ((totalCount - 1) ~/ _pageSize) + 1;
    final safePage = _page > maxPage ? maxPage : _page;
    final startIndex = (safePage - 1) * _pageSize;
    final endIndex = (startIndex + _pageSize).clamp(0, totalCount);
    final pageItems = filtered.sublist(startIndex.clamp(0, totalCount), endIndex);

    return Scaffold(
      backgroundColor: const Color(0xfff5f6f7),
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 面包屑 & 标题
            _buildHeader(context),
            const SizedBox(height: 16),
            // 搜索过滤栏
            _buildFilterBar(context),
            const SizedBox(height: 16),
            // 表格主体
            Expanded(
              child: _buildTableCard(context, pageItems, totalCount),
            ),
            const SizedBox(height: 12),
            // 分页栏
            _buildPagination(context, totalCount, safePage, maxPage),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '首页 / 系统管理 / 员工管理',
              style: TextStyle(fontSize: 12, color: Color(0xff848484)),
            ),
            SizedBox(height: 4),
            Text(
              '员工管理与责任人档案',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Color(0xff2d2d2f)),
            ),
          ],
        ),
        ElevatedButton.icon(
          key: const Key('btn-create-employee'),
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xffed3d08),
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            elevation: 0,
          ),
          onPressed: () => _openCreateOrEditDialog(),
          icon: const Icon(Icons.add, size: 18),
          label: const Text('新建员工账号', style: TextStyle(fontWeight: FontWeight.bold)),
        ),
      ],
    );
  }

  Widget _buildFilterBar(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xffe1e4e8)),
      ),
      child: Row(
        children: [
          Expanded(
            flex: 3,
            child: SizedBox(
              height: 40,
              child: TextField(
                key: const Key('employee-search-input'),
                controller: _searchController,
                decoration: InputDecoration(
                  hintText: '搜索：工号 / 姓名 / 岗位 / 账号...',
                  hintStyle: const TextStyle(fontSize: 13, color: Color(0xff848484)),
                  prefixIcon: const Icon(Icons.search, size: 18, color: Color(0xff848484)),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12),
                  filled: true,
                  fillColor: const Color(0xfffafbfc),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(6),
                    borderSide: const BorderSide(color: Color(0xffd1d5da)),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(6),
                    borderSide: const BorderSide(color: Color(0xffe1e4e8)),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(6),
                    borderSide: const BorderSide(color: Color(0xffed3d08)),
                  ),
                ),
                onSubmitted: (_) => setState(() => _page = 1),
              ),
            ),
          ),
          const SizedBox(width: 12),
          if (_allShops.isNotEmpty) ...[
            Container(
              height: 40,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                color: const Color(0xfffafbfc),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: const Color(0xffe1e4e8)),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  value: _selectedShopId,
                  style: const TextStyle(fontSize: 13, color: Color(0xff2d2d2f)),
                  onChanged: (val) {
                    setState(() {
                      _selectedShopId = val ?? '';
                      _page = 1;
                    });
                  },
                  items: [
                    const DropdownMenuItem(value: '', child: Text('全部所属门店')),
                    ..._allShops.map((s) => DropdownMenuItem(
                          value: '${s.id}',
                          child: Text('${s.name} (#${s.id})'),
                        )),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 12),
          ],
          ElevatedButton(
            key: const Key('btn-employee-search'),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xff2d2d2f),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
              elevation: 0,
            ),
            onPressed: () => setState(() => _page = 1),
            child: const Text('查询'),
          ),
          const SizedBox(width: 8),
          OutlinedButton(
            key: const Key('btn-employee-reset'),
            style: OutlinedButton.styleFrom(
              foregroundColor: const Color(0xff2d2d2f),
              side: const BorderSide(color: Color(0xffd1d5da)),
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
            ),
            onPressed: _resetFilter,
            child: const Text('重置'),
          ),
          const Spacer(),
          IconButton(
            tooltip: '刷新',
            icon: const Icon(Icons.refresh, color: Color(0xff848484)),
            onPressed: _fetchData,
          ),
        ],
      ),
    );
  }

  Widget _buildTableCard(BuildContext context, List<EmployeeItem> items, int totalCount) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator(color: Color(0xffed3d08)));
    }
    if (_errorMessage != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 48, color: Color(0xffd73a49)),
            const SizedBox(height: 12),
            Text(_errorMessage!, style: const TextStyle(color: Color(0xffd73a49))),
            const SizedBox(height: 12),
            ElevatedButton(onPressed: _fetchData, child: const Text('重试')),
          ],
        ),
      );
    }
    if (items.isEmpty) {
      return Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: const Color(0xffe1e4e8)),
        ),
        alignment: Alignment.center,
        child: const Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.people_outline, size: 48, color: Color(0xffc5cad0)),
            SizedBox(height: 12),
            Text('未找到符合条件的员工记录', style: TextStyle(color: Color(0xff848484), fontSize: 14)),
          ],
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xffe1e4e8)),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: SingleChildScrollView(
          child: DataTable(
            headingRowColor: WidgetStateProperty.all(const Color(0xfff6f8fa)),
            horizontalMargin: 20,
            columnSpacing: 24,
            columns: const [
              DataColumn(label: Text('工号', style: TextStyle(fontWeight: FontWeight.bold))),
              DataColumn(label: Text('员工姓名', style: TextStyle(fontWeight: FontWeight.bold))),
              DataColumn(label: Text('岗位/职务', style: TextStyle(fontWeight: FontWeight.bold))),
              DataColumn(label: Text('登录用户名', style: TextStyle(fontWeight: FontWeight.bold))),
              DataColumn(label: Text('绑定角色', style: TextStyle(fontWeight: FontWeight.bold))),
              DataColumn(label: Text('所属门店', style: TextStyle(fontWeight: FontWeight.bold))),
              DataColumn(label: Text('状态', style: TextStyle(fontWeight: FontWeight.bold))),
              DataColumn(label: Text('操作', style: TextStyle(fontWeight: FontWeight.bold))),
            ],
            rows: items.map((emp) => _buildRow(context, emp)).toList(),
          ),
        ),
      ),
    );
  }

  DataRow _buildRow(BuildContext context, EmployeeItem emp) {
    return DataRow(
      key: ValueKey('employee-row-${emp.id}'),
      cells: [
        // 工号
        DataCell(
          Text(
            emp.workNo.isNotEmpty ? emp.workNo : '--',
            style: TextStyle(
              fontWeight: FontWeight.w600,
              color: emp.workNo.isNotEmpty ? const Color(0xff2d2d2f) : const Color(0xff848484),
              fontFamily: 'monospace',
            ),
          ),
        ),
        // 姓名（加粗）
        DataCell(
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircleAvatar(
                radius: 12,
                backgroundColor: const Color(0xfffff1ed),
                child: Text(
                  emp.realName.isNotEmpty ? emp.realName[0] : (emp.userName.isNotEmpty ? emp.userName[0].toUpperCase() : '?'),
                  style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xffed3d08)),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                emp.realName.isNotEmpty ? emp.realName : emp.displayName,
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Color(0xff2d2d2f)),
              ),
            ],
          ),
        ),
        // 岗位 Badge
        DataCell(
          emp.jobTitle.isNotEmpty
              ? Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: const Color(0xfffff1ed),
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: const Color(0xffffdcd3)),
                  ),
                  child: Text(
                    emp.jobTitle,
                    style: const TextStyle(
                      fontSize: 12,
                      color: Color(0xffed3d08),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                )
              : const Text('--', style: TextStyle(color: Color(0xff848484))),
        ),
        // 用户名
        DataCell(Text(emp.userName, style: const TextStyle(color: Color(0xff586069)))),
        // 绑定角色
        DataCell(
          Wrap(
            spacing: 4,
            runSpacing: 4,
            children: emp.roles.map((r) {
              final name = (r['role_name'] ?? r['roleName'] ?? r['role_code'] ?? '').toString();
              return Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: const Color(0xfff1f8ff),
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: const Color(0xffc8e1ff)),
                ),
                child: Text(name, style: const TextStyle(fontSize: 11, color: Color(0xff0366d6))),
              );
            }).toList(),
          ),
        ),
        // 所属门店
        DataCell(
          emp.scope == 'HQ'
              ? Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: const Color(0xfff3e5f5),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: const Text('全部门店(HQ)', style: TextStyle(fontSize: 11, color: Color(0xff7b1fa2), fontWeight: FontWeight.w600)),
                )
              : Text(
                  emp.shops.isNotEmpty
                      ? emp.shops.map((s) => s.name).join(', ')
                      : (emp.shopIds.isNotEmpty ? '已分配 ${emp.shopIds.length} 门店' : '未分配'),
                  style: const TextStyle(fontSize: 12, color: Color(0xff586069)),
                ),
        ),
        // 状态
        DataCell(
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: const Color(0xffe6ffed),
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: const Color(0xffacf2bd)),
            ),
            child: const Text('正常', style: TextStyle(fontSize: 11, color: Color(0xff22863a), fontWeight: FontWeight.w600)),
          ),
        ),
        // 操作
        DataCell(
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextButton(
                key: Key('btn-edit-employee-${emp.id}'),
                style: TextButton.styleFrom(
                  foregroundColor: const Color(0xffed3d08),
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                onPressed: () => _openCreateOrEditDialog(employee: emp),
                child: const Text('编辑', style: TextStyle(fontWeight: FontWeight.bold)),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildPagination(BuildContext context, int totalCount, int currentPage, int maxPage) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          '共 $totalCount 条记录 · 每页 $_pageSize 条',
          style: const TextStyle(fontSize: 13, color: Color(0xff586069)),
        ),
        Row(
          children: [
            IconButton(
              icon: const Icon(Icons.chevron_left),
              onPressed: currentPage > 1 ? () => setState(() => _page = currentPage - 1) : null,
            ),
            Text(
              ' $currentPage / $maxPage ',
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
            ),
            IconButton(
              icon: const Icon(Icons.chevron_right),
              onPressed: currentPage < maxPage ? () => setState(() => _page = currentPage + 1) : null,
            ),
          ],
        ),
      ],
    );
  }
}

/// 员工新增与编辑对话框
class _EmployeeFormDialog extends StatefulWidget {
  const _EmployeeFormDialog({
    required this.client,
    required this.appState,
    required this.allRoles,
    required this.allShops,
    this.employee,
  });

  final AdminApiClient client;
  final AppState appState;
  final List<EmployeeRoleOption> allRoles;
  final List<ShopSummary> allShops;
  final EmployeeItem? employee;

  @override
  State<_EmployeeFormDialog> createState() => _EmployeeFormDialogState();
}

class _EmployeeFormDialogState extends State<_EmployeeFormDialog> {
  final _formKey = GlobalKey<FormState>();

  late final TextEditingController _workNoController;
  late final TextEditingController _realNameController;
  late final TextEditingController _jobTitleController;
  late final TextEditingController _userNameController;
  late final TextEditingController _passwordController;

  late Set<int> _selectedRoleIds;
  late Set<int> _selectedShopIds;

  bool _obscurePassword = true;
  bool _submitting = false;
  String? _dialogError;

  final _commonJobTitles = ['店长', '副店长', '领班', '收银员', '服务员', '后厨主管'];

  @override
  void initState() {
    super.initState();
    final emp = widget.employee;
    _workNoController = TextEditingController(text: emp?.workNo ?? '');
    _realNameController = TextEditingController(text: emp?.realName ?? '');
    _jobTitleController = TextEditingController(text: emp?.jobTitle ?? '');
    _userNameController = TextEditingController(text: emp?.userName ?? '');
    _passwordController = TextEditingController();

    _selectedRoleIds = Set.from(emp?.roleIds ?? []);
    _selectedShopIds = Set.from(emp?.shopIds ?? []);

    // 新增时若没有选中门店且当前登录有门店，默认选中当前门店
    if (emp == null && _selectedShopIds.isEmpty && widget.appState.currentShopId != null) {
      _selectedShopIds.add(widget.appState.currentShopId!);
    }
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

  bool get _isEdit => widget.employee != null;

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    if (_selectedRoleIds.isEmpty) {
      setState(() => _dialogError = '请至少勾选分配一个权限角色');
      return;
    }

    setState(() {
      _submitting = true;
      _dialogError = null;
    });

    final workNo = _workNoController.text.trim();
    final realName = _realNameController.text.trim();
    final jobTitle = _jobTitleController.text.trim();
    final userName = _userNameController.text.trim();
    final password = _passwordController.text.trim();

    try {
      if (_isEdit) {
        final id = widget.employee!.id;
        // 1. 更新基本信息
        final body = <String, Object?>{
          'workNo': workNo,
          'realName': realName,
          'jobTitle': jobTitle,
        };
        if (password.isNotEmpty) {
          body['password'] = password;
        }
        await widget.client.put(
          adminAdministratorUpdateEndpoint.withPathParams({'id': '$id'}),
          body: body,
        );

        // 2. 更新角色分配
        await widget.client.put(
          adminAdministratorRolesEndpoint.withPathParams({'id': '$id'}),
          body: {'roleIds': _selectedRoleIds.toList()},
        );

        // 3. 更新门店分配 (仅在非 HQ 时调用)
        if (widget.employee!.scope != 'HQ') {
          await widget.client.put(
            adminAdministratorShopsEndpoint.withPathParams({'id': '$id'}),
            body: {
              'shopIds': _selectedShopIds.toList(),
              'regionIds': <int>[],
            },
          );
        }
      } else {
        // 创建新员工账号
        await widget.client.post(
          adminAdministratorCreateEndpoint,
          body: {
            'workNo': workNo,
            'realName': realName,
            'jobTitle': jobTitle,
            'userName': userName,
            'password': password,
            'roleIds': _selectedRoleIds.toList(),
            'shopIds': _selectedShopIds.toList(),
          },
        );
      }

      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _dialogError = e.toString().replaceFirst(RegExp(r'^Exception:\s*'), '');
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 580, maxHeight: 720),
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 头部
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      _isEdit ? '编辑员工信息' : '新建员工档案',
                      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xff2d2d2f)),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close, size: 20),
                      onPressed: () => Navigator.of(context).pop(false),
                    ),
                  ],
                ),
                const Divider(height: 24),
                // 错误提示条
                if (_dialogError != null) ...[
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: const Color(0xffffeef0),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: const Color(0xfffdaeb7)),
                    ),
                    child: Text(
                      _dialogError!,
                      style: const TextStyle(color: Color(0xffcb2431), fontSize: 13),
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
                // 表单主体
                Expanded(
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // 员工工号
                        _buildFieldLabel('员工工号', required: true),
                        TextFormField(
                          key: const Key('input-work-no'),
                          controller: _workNoController,
                          decoration: _inputDecoration(hint: '如 EMP1001'),
                          validator: (val) {
                            final v = val?.trim() ?? '';
                            if (v.isEmpty) return '员工工号为必填项';
                            if (!RegExp(r'^[a-zA-Z0-9_\-]+$').hasMatch(v)) {
                              return '工号仅支持字母、数字、下划线及连字符';
                            }
                            if (v.length < 2 || v.length > 20) {
                              return '工号长度需在 2~20 位之间';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 4),
                        const Text(
                          '(i) 工号为系统唯一标识，用于日常快速登录与操作审计',
                          style: TextStyle(fontSize: 11, color: Color(0xff848484)),
                        ),
                        const SizedBox(height: 16),

                        // 真实姓名
                        _buildFieldLabel('真实姓名', required: true),
                        TextFormField(
                          key: const Key('input-real-name'),
                          controller: _realNameController,
                          decoration: _inputDecoration(hint: '如 张晓明'),
                          validator: (val) {
                            final v = val?.trim() ?? '';
                            if (v.isEmpty) return '真实姓名为必填项';
                            if (v.length < 2 || v.length > 20) {
                              return '姓名长度需在 2~20 个字符之间';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 4),
                        const Text(
                          '(i) 必填，后续所有点单、交班、日结单据将打印此姓名',
                          style: TextStyle(fontSize: 11, color: Color(0xff848484)),
                        ),
                        const SizedBox(height: 16),

                        // 岗位称谓
                        _buildFieldLabel('岗位称谓'),
                        Row(
                          children: [
                            Expanded(
                              child: TextFormField(
                                key: const Key('input-job-title'),
                                controller: _jobTitleController,
                                decoration: _inputDecoration(hint: '选择或输入岗位，如 店长、收银员'),
                              ),
                            ),
                            const SizedBox(width: 8),
                            PopupMenuButton<String>(
                              icon: const Icon(Icons.arrow_drop_down_circle_outlined, color: Color(0xffed3d08)),
                              tooltip: '选择常用岗位',
                              onSelected: (val) {
                                setState(() {
                                  _jobTitleController.text = val;
                                });
                              },
                              itemBuilder: (ctx) => _commonJobTitles
                                  .map((title) => PopupMenuItem(value: title, child: Text(title)))
                                  .toList(),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),

                        // 登录系统名 (新增时必填，编辑时只读)
                        _buildFieldLabel('登录账号 (系统名)', required: !_isEdit),
                        TextFormField(
                          key: const Key('input-user-name'),
                          controller: _userNameController,
                          enabled: !_isEdit,
                          decoration: _inputDecoration(hint: '如 zhangxm (英文字母开头)'),
                          validator: (val) {
                            if (_isEdit) return null;
                            final v = val?.trim() ?? '';
                            if (v.isEmpty) return '登录账号为必填项';
                            if (v.length < 3 || v.length > 30) return '账号长度在 3~30 位之间';
                            return null;
                          },
                        ),
                        const SizedBox(height: 16),

                        // 密码
                        _buildFieldLabel(_isEdit ? '重置密码 (留空则不修改)' : '初始密码', required: !_isEdit),
                        TextFormField(
                          key: const Key('input-password'),
                          controller: _passwordController,
                          obscureText: _obscurePassword,
                          decoration: _inputDecoration(
                            hint: _isEdit ? '留空表示保持现有密码不变' : '请输入初始登录密码',
                            suffixIcon: IconButton(
                              icon: Icon(_obscurePassword ? Icons.visibility_off : Icons.visibility, size: 18),
                              onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                            ),
                          ),
                          validator: (val) {
                            if (!_isEdit && (val == null || val.trim().isEmpty)) {
                              return '初始密码为必填项';
                            }
                            if (val != null && val.isNotEmpty && val.length < 6) {
                              return '密码长度不能少于 6 位';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 20),

                        // 角色权限分配
                        _buildFieldLabel('权限角色分配', required: true),
                        const SizedBox(height: 6),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: widget.allRoles.map((role) {
                            final checked = _selectedRoleIds.contains(role.id);
                            return FilterChip(
                              label: Text('${role.roleName} (${role.roleCode})'),
                              selected: checked,
                              selectedColor: const Color(0xfffff1ed),
                              checkmarkColor: const Color(0xffed3d08),
                              labelStyle: TextStyle(
                                color: checked ? const Color(0xffed3d08) : const Color(0xff2d2d2f),
                                fontWeight: checked ? FontWeight.bold : FontWeight.normal,
                                fontSize: 12,
                              ),
                              onSelected: (val) {
                                setState(() {
                                  if (val) {
                                    _selectedRoleIds.add(role.id);
                                  } else {
                                    _selectedRoleIds.remove(role.id);
                                  }
                                });
                              },
                            );
                          }).toList(),
                        ),
                        const SizedBox(height: 20),

                        // 所属门店授权
                        if (widget.employee?.scope != 'HQ') ...[
                          _buildFieldLabel('所属门店授权'),
                          const SizedBox(height: 6),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: widget.allShops.map((shop) {
                              final checked = _selectedShopIds.contains(shop.id);
                              return FilterChip(
                                label: Text(shop.name),
                                selected: checked,
                                selectedColor: const Color(0xffe6ffed),
                                checkmarkColor: const Color(0xff22863a),
                                labelStyle: TextStyle(
                                  color: checked ? const Color(0xff22863a) : const Color(0xff2d2d2f),
                                  fontWeight: checked ? FontWeight.bold : FontWeight.normal,
                                  fontSize: 12,
                                ),
                                onSelected: (val) {
                                  setState(() {
                                    if (val) {
                                      _selectedShopIds.add(shop.id);
                                    } else {
                                      _selectedShopIds.remove(shop.id);
                                    }
                                  });
                                },
                              );
                            }).toList(),
                          ),
                          const SizedBox(height: 8),
                        ],
                      ],
                    ),
                  ),
                ),
                const Divider(height: 24),
                // 底部操作按钮
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: const Color(0xff2d2d2f),
                        side: const BorderSide(color: Color(0xffd1d5da)),
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                      ),
                      onPressed: _submitting ? null : () => Navigator.of(context).pop(false),
                      child: const Text('取消'),
                    ),
                    const SizedBox(width: 12),
                    ElevatedButton(
                      key: const Key('btn-submit-employee-form'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xffed3d08),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                        elevation: 0,
                      ),
                      onPressed: _submitting ? null : _submit,
                      child: _submitting
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                            )
                          : const Text('确认保存', style: TextStyle(fontWeight: FontWeight.bold)),
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

  Widget _buildFieldLabel(String label, {bool required = false}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6.0),
      child: RichText(
        text: TextSpan(
          text: label,
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xff2d2d2f)),
          children: [
            if (required)
              const TextSpan(
                text: ' *',
                style: TextStyle(color: Color(0xffd73a49), fontWeight: FontWeight.bold),
              ),
          ],
        ),
      ),
    );
  }

  InputDecoration _inputDecoration({required String hint, Widget? suffixIcon}) {
    return InputDecoration(
      hintText: hint,
      hintStyle: const TextStyle(fontSize: 13, color: Color(0xff848484)),
      suffixIcon: suffixIcon,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      filled: true,
      fillColor: const Color(0xfffafbfc),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(6),
        borderSide: const BorderSide(color: Color(0xffd1d5da)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(6),
        borderSide: const BorderSide(color: Color(0xffe1e4e8)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(6),
        borderSide: const BorderSide(color: Color(0xffed3d08)),
      ),
    );
  }
}
