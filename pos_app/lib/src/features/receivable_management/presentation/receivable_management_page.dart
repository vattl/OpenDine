import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../core/admin_api_client.dart';
import '../../cashier_shell/presentation/cashier_tokens.dart';
import '../../pos/presentation/pos_auth_dialog.dart';
import '../data/receivable_management_repository.dart';
import '../domain/receivable_account_model.dart';

class ReceivableManagementPage extends StatefulWidget {
  const ReceivableManagementPage({
    super.key,
    this.client,
    this.repository,
    this.permissions = const {},
    this.currentShopId,
    this.onBack,
    this.section,
  });

  final AdminApiClient? client;
  final ReceivableManagementRepository? repository;
  final Set<String> permissions;
  final int? currentShopId;
  final VoidCallback? onBack;

  /// Shared settings section; null retains the standalone workbench.
  final String? section;

  @override
  State<ReceivableManagementPage> createState() => _ReceivableManagementPageState();
}

class _ReceivableManagementPageState extends State<ReceivableManagementPage> {
  late ReceivableManagementRepository _repository;
  bool _loading = false;
  String? _errorMessage;
  List<ReceivableAccountModel> _accounts = [];
  ReceivableAgingSummary _aging = const ReceivableAgingSummary();
  List<ReceivableClaimModel> _claims = [];

  String _currentTab = 'ACCOUNTS'; // 'ACCOUNTS' | 'CLAIMS'
  int? _filterClaimAccountId;

  String _searchKeyword = '';
  String _selectedStatus = 'ALL';
  String _selectedCustomerType = 'ALL';
  String _selectedScopeType = 'ALL';

  String _claimSearchKeyword = '';
  String _selectedClaimStatus = 'ALL';

  bool get _hasViewPermission {
    return widget.permissions.contains('receivable:view') ||
        widget.permissions.contains('admin:manage') ||
        widget.permissions.contains('admin:super');
  }

  bool get _hasManagePermission {
    return widget.permissions.contains('receivable:manage') ||
        widget.permissions.contains('admin:manage') ||
        widget.permissions.contains('admin:super');
  }

  bool get _hasMerchantManagePermission {
    return widget.permissions.contains('receivable:merchant_manage') ||
        widget.permissions.contains('admin:super');
  }

  @override
  void initState() {
    super.initState();
    _currentTab = widget.section == 'claims' ? 'CLAIMS' : 'ACCOUNTS';
    if (widget.repository != null) {
      _repository = widget.repository!;
    } else if (widget.client != null) {
      _repository = ReceivableManagementRepository(widget.client!);
    }
    if (_hasViewPermission) {
      _loadData();
    }
  }

  Future<void> _loadData() async {
    setState(() {
      _loading = true;
      _errorMessage = null;
    });
    try {
      final accountsFuture = _repository.fetchAccounts(
        status: _selectedStatus == 'ALL' ? null : _selectedStatus,
        keyword: _searchKeyword.isEmpty ? null : _searchKeyword,
      );
      final agingFuture = _repository.fetchAging();
      final claimsFuture = _repository.fetchClaims(
        accountId: _filterClaimAccountId,
        status: _selectedClaimStatus == 'ALL' ? null : _selectedClaimStatus,
      );
      final accounts = await accountsFuture;
      final aging = await agingFuture;
      final claims = await claimsFuture;
      if (mounted) {
        setState(() {
          _accounts = accounts;
          _aging = aging;
          _claims = claims;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = e.toString();
          _loading = false;
        });
      }
    }
  }

  List<ReceivableAccountModel> get _filteredAccounts {
    return _accounts.where((account) {
      if (_selectedCustomerType != 'ALL' && account.customerType != _selectedCustomerType) {
        return false;
      }
      if (_selectedScopeType != 'ALL' && account.scopeType != _selectedScopeType) {
        return false;
      }
      return true;
    }).toList();
  }

  List<ReceivableClaimModel> get _filteredClaims {
    return _claims.where((claim) {
      if (_filterClaimAccountId != null && claim.accountId != _filterClaimAccountId) {
        return false;
      }
      if (_claimSearchKeyword.isNotEmpty) {
        final kw = _claimSearchKeyword.toLowerCase();
        final orderMatch = claim.orderNo.toLowerCase().contains(kw);
        final nameMatch = claim.customerName?.toLowerCase().contains(kw) ?? false;
        final noMatch = claim.claimNo.toLowerCase().contains(kw);
        if (!orderMatch && !nameMatch && !noMatch) {
          return false;
        }
      }
      return true;
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    if (!_hasViewPermission) {
      return _buildForbiddenBarrier();
    }

    final double totalOutstandingYuan = _accounts.fold(
      0.0,
      (sum, item) => sum + item.outstandingYuan,
    );
    final double totalCreditLimitYuan = _accounts.fold(
      0.0,
      (sum, item) => sum + item.creditLimitYuan,
    );
    final int activeCount = _accounts.where((a) => a.isActive).length;
    final int suspendedCount = _accounts.where((a) => a.isSuspended).length;

    return Scaffold(
      key: const Key('receivable-management-page'),
      backgroundColor: context.cashier.canvas,
      body: Column(
        children: [
          if (widget.section == null) _buildHeader(context),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _buildMetricsGrid(
                    context,
                    totalAccounts: _accounts.length,
                    activeCount: activeCount,
                    suspendedCount: suspendedCount,
                    totalOutstandingYuan: totalOutstandingYuan,
                    totalCreditLimitYuan: totalCreditLimitYuan,
                  ),
                  const SizedBox(height: 20),
                  if (widget.section == null) _buildTabBar(context),
                  const SizedBox(height: 16),
                  if (_errorMessage != null)
                    _buildErrorBanner(context)
                  else if (_loading)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 48),
                      child: Center(child: CircularProgressIndicator()),
                    )
                  else if (widget.section == 'aging') ...[
                    OutlinedButton.icon(
                      onPressed: _showAgingDialog,
                      icon: const Icon(Icons.pie_chart_outline),
                      label: const Text('查看账龄明细'),
                    ),
                  ] else if (widget.section == 'statement') ...[
                    const Text('选择授信账户查看流水对账'),
                    for (final account in _accounts)
                      ListTile(
                        title: Text(account.customerName),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => _showStatementDialog(account),
                      ),
                  ] else if (_currentTab == 'ACCOUNTS') ...[
                    _buildToolbar(context),
                    const SizedBox(height: 16),
                    _buildAccountTable(context, _filteredAccounts),
                  ] else ...[
                    _buildClaimsToolbar(context),
                    const SizedBox(height: 16),
                    _buildClaimsTable(context, _filteredClaims),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildForbiddenBarrier() {
    return Scaffold(
      key: const Key('receivable-forbidden-barrier'),
      backgroundColor: context.cashier.canvas,
      body: Center(
        child: Container(
          constraints: const BoxConstraints(maxWidth: 520),
          margin: const EdgeInsets.all(24),
          padding: const EdgeInsets.all(32),
          decoration: BoxDecoration(
            color: context.cashier.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: context.cashier.danger.withValues(alpha: 0.3),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.05),
                blurRadius: 16,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.shield_outlined, size: 64, color: context.cashier.danger,
              ),
              const SizedBox(height: 16),
              const Text(
                '403 无权访问挂账管理',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),
              Text(
                '您当前的账号缺少 receivable:view 权限码，无法查阅商业授信与应收账款数据。如需操作，请联系系统超级管理员进行授权。',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 14, color: context.cashier.inkMuted, height: 1.5,
                ),
              ),
              const SizedBox(height: 24),
              if (widget.onBack != null)
                OutlinedButton.icon(
                  onPressed: widget.onBack,
                  icon: const Icon(Icons.arrow_back),
                  label: const Text('返回设置中心'),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Container(
      height: 72,
      padding: const EdgeInsets.symmetric(horizontal: 24),
      decoration: BoxDecoration(
        color: context.cashier.surface,
        border: Border(bottom: BorderSide(color: context.cashier.border)),
      ),
      child: Row(
        children: [
          if (widget.onBack != null) ...[
            OutlinedButton.icon(
              onPressed: widget.onBack,
              style: OutlinedButton.styleFrom(
                side: BorderSide(color: context.cashier.border),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10,
                ),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8),
                ),
              ),
              icon: const Icon(Icons.arrow_back, size: 18),
              label: const Text('返回设置'),
            ),
            const SizedBox(width: 16),
          ],
          Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Text(
                    '挂账系统管理',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(width: 10),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xfffef3c7),
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(color: const Color(0xfffde68a)),
                    ),
                    child: const Text(
                      '授信 · 应收 · 资金闭环',
                      style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xffb45309),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 2),
              Text(
                '授信账户增删改查 · 客户信用额度控制 · 历史流水对账单',
                style: TextStyle(fontSize: 12, color: context.cashier.inkMuted),
              ),
            ],
          ),
          const Spacer(),
          IconButton(
            tooltip: '刷新',
            icon: const Icon(Icons.refresh_rounded),
            onPressed: _loading ? null : _loadData,
          ),
          const SizedBox(width: 8),
          FilledButton.icon(
            key: const Key('receivable-add-account-button'),
            onPressed: _hasManagePermission ? () => _showAccountFormDialog(null) : null,
            style: FilledButton.styleFrom(
              backgroundColor: context.cashier.selected,
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8),
              ),
            ),
            icon: const Icon(Icons.add, size: 18),
            label: const Text('新增挂账用户'),
          ),
        ],
      ),
    );
  }

  Widget _buildMetricsGrid(
    BuildContext context, {
    required int totalAccounts,
    required int activeCount,
    required int suspendedCount,
    required double totalOutstandingYuan,
    required double totalCreditLimitYuan,
  }) {
    final double ratio = totalCreditLimitYuan > 0
        ? (totalOutstandingYuan / totalCreditLimitYuan * 100).clamp(0.0, 100.0)
        : 0.0;

    return LayoutBuilder(
      builder: (context, constraints) {
        final cols = constraints.maxWidth >= 960 ? 4 : (constraints.maxWidth >= 600 ? 2 : 1);
        return Wrap(
          spacing: 16,
          runSpacing: 16,
          children: [
            _metricCard(
              context,
              width: (constraints.maxWidth - (cols - 1) * 16) / cols,
              title: '授信客户总数',
              value: '$totalAccounts',
              unit: '户',
              desc: '正常使用 $activeCount 户 · 暂停 $suspendedCount 户',
            ),
            _metricCard(
              context,
              width: (constraints.maxWidth - (cols - 1) * 16) / cols,
              title: '当前未清应收总额',
              value: '¥${totalOutstandingYuan.toStringAsFixed(2)}',
              desc: '授信总额 ¥${totalCreditLimitYuan.toStringAsFixed(2)} (占用 ${ratio.toStringAsFixed(1)}%)',
            ),
            _metricCard(
              context,
              width: (constraints.maxWidth - (cols - 1) * 16) / cols,
              title: '全店已授信额度',
              value: '¥${totalCreditLimitYuan.toStringAsFixed(2)}',
              desc: '可用额度 ¥${(totalCreditLimitYuan - totalOutstandingYuan).clamp(0.0, totalCreditLimitYuan).toStringAsFixed(2)}',
            ),
            InkWell(
              key: const Key('receivable-aging-metric-card'),
              onTap: _showAgingDialog,
              borderRadius: BorderRadius.circular(12),
              child: _metricCard(
                context,
                width: (constraints.maxWidth - (cols - 1) * 16) / cols,
                title: '逾期应收预警 (点击分析)',
                value: '¥${_aging.overdueYuan.toStringAsFixed(2)}',
                desc: '包含 1~90+ 天超账期未回款 · 点击查看5级账龄',
                valueColor: _aging.overdueFen > 0 ? context.cashier.danger : null,
                trailing: Icon(Icons.arrow_forward_ios_rounded, size: 14, color: context.cashier.inkMuted,
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _metricCard(
    BuildContext context, {
    required double width,
    required String title,
    required String value,
    String? unit,
    required String desc,
    Color? valueColor,
    Widget? trailing,
  }) {
    return Container(
      width: width,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: context.cashier.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: context.cashier.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                title,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: context.cashier.inkMuted,
                  letterSpacing: 0.5,
                ),
              ),
              if (trailing != null) trailing,
            ],
          ),
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                value,
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: valueColor ?? context.cashier.ink,
                ),
              ),
              if (unit != null) ...[
                const SizedBox(width: 4),
                Text(
                  unit,
                  style: TextStyle(fontSize: 13, color: context.cashier.inkMuted,
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 6),
          Text(
            desc,
            style: TextStyle(fontSize: 12, color: context.cashier.inkMuted),
          ),
        ],
      ),
    );
  }

  Widget _buildTabBar(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: context.cashier.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: context.cashier.border),
      ),
      padding: const EdgeInsets.all(4),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _tabButton(
            context,
            key: const Key('receivable-tab-accounts'),
            title: '授信客户账户 (${_accounts.length})',
            isSelected: _currentTab == 'ACCOUNTS',
            icon: Icons.account_balance_outlined,
            onTap: () {
              if (_currentTab != 'ACCOUNTS') {
                setState(() => _currentTab = 'ACCOUNTS');
              }
            },
          ),
          const SizedBox(width: 4),
          _tabButton(
            context,
            key: const Key('receivable-tab-claims'),
            title: '应收借据明细 (${_claims.length})',
            isSelected: _currentTab == 'CLAIMS',
            icon: Icons.receipt_long_outlined,
            onTap: () {
              if (_currentTab != 'CLAIMS') {
                setState(() => _currentTab = 'CLAIMS');
              }
            },
          ),
        ],
      ),
    );
  }

  Widget _tabButton(
    BuildContext context, {
    required Key key,
    required String title,
    required bool isSelected,
    required IconData icon,
    required VoidCallback onTap,
  }) {
    return InkWell(
      key: key,
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? context.cashier.selected : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 16,
              color: isSelected ? Colors.white : context.cashier.inkMuted,
            ),
            const SizedBox(width: 8),
            Text(
              title,
              style: TextStyle(
                fontSize: 13,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                color: isSelected ? Colors.white : context.cashier.ink,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildToolbar(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: context.cashier.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: context.cashier.border),
      ),
      child: Wrap(
        spacing: 14,
        runSpacing: 12,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          SizedBox(
            width: 260,
            height: 38,
            child: TextField(
              key: const Key('receivable-search-input'),
              decoration: InputDecoration(
                hintText: '搜索客户名称、联系人、电话、税号...',
                hintStyle: TextStyle(fontSize: 13, color: context.cashier.inkMuted,
                ),
                prefixIcon: const Icon(Icons.search, size: 18),
                contentPadding: const EdgeInsets.symmetric(horizontal: 10),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(color: context.cashier.border),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(color: context.cashier.border),
                ),
              ),
              onChanged: (val) {
                setState(() => _searchKeyword = val);
              },
              onSubmitted: (_) => _loadData(),
            ),
          ),
          DropdownButton<String>(
            key: const Key('receivable-status-select'),
            value: _selectedStatus,
            underline: const SizedBox.shrink(),
            items: const [
              DropdownMenuItem(value: 'ALL', child: Text('全部状态')),
              DropdownMenuItem(value: 'ACTIVE', child: Text('正常使用 (ACTIVE)')),
              DropdownMenuItem(value: 'SUSPENDED', child: Text('已暂停 (SUSPENDED)'),
              ),
              DropdownMenuItem(value: 'CLOSED', child: Text('已注销关闭 (CLOSED)')),
            ],
            onChanged: (val) {
              if (val != null) {
                setState(() => _selectedStatus = val);
                _loadData();
              }
            },
          ),
          DropdownButton<String>(
            value: _selectedCustomerType,
            underline: const SizedBox.shrink(),
            items: const [
              DropdownMenuItem(value: 'ALL', child: Text('全部客户类型')),
              DropdownMenuItem(value: 'COMPANY', child: Text('企业客户 (COMPANY)')),
              DropdownMenuItem(value: 'PERSONAL', child: Text('个人客户 (PERSONAL)'),
              ),
            ],
            onChanged: (val) {
              if (val != null) {
                setState(() => _selectedCustomerType = val);
              }
            },
          ),
          DropdownButton<String>(
            value: _selectedScopeType,
            underline: const SizedBox.shrink(),
            items: const [
              DropdownMenuItem(value: 'ALL', child: Text('全部范围')),
              DropdownMenuItem(value: 'SHOP', child: Text('本店专属 (SHOP)')),
              DropdownMenuItem(value: 'MERCHANT', child: Text('全商户跨店 (MERCHANT)'),
              ),
            ],
            onChanged: (val) {
              if (val != null) {
                setState(() => _selectedScopeType = val);
              }
            },
          ),
          Text(
            '共匹配 ${_filteredAccounts.length} 个账户',
            style: TextStyle(fontSize: 13, color: context.cashier.inkMuted),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorBanner(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: context.cashier.danger.withValues(alpha: 0.1),
        border: Border.all(color: context.cashier.danger.withValues(alpha: 0.3),
        ),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(Icons.error_outline, color: context.cashier.danger),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              '加载失败：$_errorMessage',
              style: TextStyle(color: context.cashier.danger, fontSize: 13),
            ),
          ),
          TextButton(onPressed: _loadData, child: const Text('重试')),
        ],
      ),
    );
  }

  Widget _buildAccountTable(BuildContext context, List<ReceivableAccountModel> accounts,
  ) {
    if (accounts.isEmpty) {
      return Container(
        padding: const EdgeInsets.symmetric(vertical: 48),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: context.cashier.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: context.cashier.border),
        ),
        child: Column(
          children: [
            Icon(Icons.folder_open_outlined, size: 48, color: context.cashier.inkMuted,
            ),
            const SizedBox(height: 12),
            Text(
              '暂无符合条件的授信客户账户',
              style: TextStyle(color: context.cashier.inkMuted, fontSize: 14),
            ),
          ],
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: context.cashier.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: context.cashier.border),
      ),
      child: ListView.separated(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: accounts.length,
        separatorBuilder: (_, __) => Divider(height: 1, color: context.cashier.border),
        itemBuilder: (context, index) {
          final account = accounts[index];
          return _buildAccountRow(context, account);
        },
      ),
    );
  }

  Widget _buildAccountRow(BuildContext context, ReceivableAccountModel account,
  ) {
    final double ratio = account.usedRatio;

    return Padding(
      key: Key('receivable-account-row-${account.id}'),
      padding: const EdgeInsets.all(16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // 客户基本信息
          Expanded(
            flex: 4,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        account.customerName,
                        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 8),
                    _badge(
                      label: account.isCompany ? '企业' : '个人',
                      color: account.isCompany ? context.cashier.selected : const Color(0xff7c3aed),
                      bg: account.isCompany
                          ? context.cashier.selected.withValues(alpha: 0.1)
                          : const Color(0xfff3e8ff),
                    ),
                    const SizedBox(width: 6),
                    _badge(
                      label: account.isMerchantScope ? '全商户跨店' : '本店专属',
                      color: account.isMerchantScope ? const Color(0xffb45309) : const Color(0xff475569),
                      bg: account.isMerchantScope ? const Color(0xfffef3c7) : const Color(0xfff1f5f9),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  '联系人: ${account.contactName ?? "-"} (${account.contactPhone ?? "-"})'
                  '${account.taxNo != null && account.taxNo!.isNotEmpty ? " · 税号: ${account.taxNo}" : ""}',
                  style: TextStyle(fontSize: 12, color: context.cashier.inkMuted,
                  ),
                ),
              ],
            ),
          ),

          // 额度与进度条
          Expanded(
            flex: 3,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        '¥${account.outstandingYuan.toStringAsFixed(2)}',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: account.outstandingFen > 0 ? context.cashier.selected : context.cashier.ink,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Flexible(
                      child: Text(
                        ' / ¥${account.creditLimitYuan.toStringAsFixed(2)}',
                        style: TextStyle(fontSize: 13, color: context.cashier.inkMuted,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Container(
                  width: 140,
                  height: 6,
                  decoration: BoxDecoration(
                    color: const Color(0xffe2e8f0),
                    borderRadius: BorderRadius.circular(3),
                  ),
                  child: FractionallySizedBox(
                    alignment: Alignment.centerLeft,
                    widthFactor: ratio,
                    child: Container(
                      decoration: BoxDecoration(
                        color: ratio >= 0.9
                            ? context.cashier.danger
                            : (ratio >= 0.7 ? const Color(0xffd97706) : context.cashier.selected),
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '可用 ¥${account.availableYuan.toStringAsFixed(2)} · 账期 ${account.paymentTermsDays} 天',
                  style: TextStyle(fontSize: 11, color: context.cashier.inkMuted,
                  ),
                ),
              ],
            ),
          ),

          // 状态
          SizedBox(
            width: 80,
            child: _statusBadge(account.status)),

          // 操作按钮组
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextButton(
                key: Key('receivable-account-claims-button-${account.id}'),
                onPressed: () {
                  setState(() {
                    _filterClaimAccountId = account.id;
                    _currentTab = 'CLAIMS';
                  });
                  _loadData();
                },
                child: const Text('查看借据'),
              ),
              TextButton(
                key: Key('receivable-account-statement-button-${account.id}'),
                onPressed: () => _showStatementDialog(account),
                child: const Text('对账单'),
              ),
              if (_hasManagePermission) ...[
                TextButton(
                  key: Key('receivable-account-edit-button-${account.id}'),
                  onPressed: account.isClosed ? null : () => _showAccountFormDialog(account),
                  child: const Text('编辑'),
                ),
                TextButton(
                  onPressed: account.isClosed
                      ? null
                      : () => _toggleStatus(account),
                  child: Text(account.isActive ? '暂停' : '启用'),
                ),
                TextButton(
                  key: Key('receivable-account-delete-button-${account.id}'),
                  style: TextButton.styleFrom(foregroundColor: context.cashier.danger,
                  ),
                  onPressed: () => _confirmDeleteOrCloseAccount(account),
                  child: const Text('删除'),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Widget _badge({required String label, required Color color, required Color bg,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        label,
        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: color,
        ),
      ),
    );
  }

  Widget _statusBadge(String status) {
    return switch (status) {
      'ACTIVE' => _badge(
          label: '正常使用',
          color: const Color(0xff16a34a),
          bg: const Color(0xffdcfce7),
        ),
      'SUSPENDED' => _badge(
          label: '已暂停',
          color: const Color(0xffd97706),
          bg: const Color(0xfffef3c7),
        ),
      'CLOSED' => _badge(
          label: '已注销',
          color: const Color(0xff64748b),
          bg: const Color(0xfff1f5f9),
        ),
      _ => Text(status),
    };
  }

  Future<void> _toggleStatus(ReceivableAccountModel account) async {
    final nextStatus = account.isActive ? 'SUSPENDED' : 'ACTIVE';
    try {
      await _repository.updateAccountStatus(account.id, nextStatus);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('账户【${account.customerName}】已切换为 ${nextStatus == "ACTIVE" ? "正常" : "暂停"}',
          ),
        ),
      );
      _loadData();
    } catch (e) {
      ScaffoldMessenger.of(context,
      ).showSnackBar(
        SnackBar(content: Text('操作失败: $e')));
    }
  }

  Future<void> _confirmDeleteOrCloseAccount(ReceivableAccountModel account,
  ) async {
    // 财务合规强规则：若存在未清余额，严格阻断
    if (account.outstandingFen > 0) {
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Row(
            children: [
              Icon(Icons.warning_amber_rounded, color: context.cashier.danger),
              const SizedBox(width: 8),
              const Text('无法删除挂账账户'),
            ],
          ),
          content: Text(
            '客户【${account.customerName}】当前仍有未清挂账欠款 ¥${account.outstandingYuan.toStringAsFixed(2)}。\n\n依据资金安全与财务审计合规准则，禁止删除或注销含有未清余额的授信账户。请先收取回款或核销坏账后再试。',
            style: const TextStyle(fontSize: 14, height: 1.5),
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('我知道了'),
            ),
          ],
        ),
      );
      return;
    }

    // 零未清余额账户，确认删除/注销
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('确认删除或注销账户？'),
        content: Text(
          '客户【${account.customerName}】当前无未清欠款。\n\n'
          '• 若该账户从未产生过交易流水，系统将执行【彻底物理删除】；\n'
          '• 若该账户曾发生过历史挂账并已结清，系统将执行【合规注销关闭】，保留历史对账流水。\n\n'
          '是否确定继续？',
          style: const TextStyle(fontSize: 14, height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: context.cashier.danger,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('确认删除/注销'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        final result = await _repository.deleteAccount(account.id);
        final wasDeleted = result['deleted'] == true;
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                wasDeleted
                    ? '账户【${account.customerName}】已彻底删除'
                    : '账户【${account.customerName}】已安全注销并归档',
              ),
            ),
          );
          _loadData();
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context,
          ).showSnackBar(
            SnackBar(content: Text('删除失败: $e')));
        }
      }
    }
  }

  void _showAccountFormDialog(ReceivableAccountModel? existing) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => ReceivableAccountFormDialog(
        existing: existing,
        canManageMerchantScope: _hasMerchantManagePermission,
        onSave: (form) async {
          if (existing == null) {
            await _repository.createAccount(form);
          } else {
            await _repository.updateAccount(existing.id, form);
          }
          if (mounted) {
            _loadData();
          }
        },
      ),
    );
  }

  void _showStatementDialog(ReceivableAccountModel account) {
    showDialog(
      context: context,
      builder: (ctx) => ReceivableStatementDialog(
        account: account,
        repository: _repository),
    );
  }

  Widget _buildClaimsToolbar(BuildContext context) {
    ReceivableAccountModel? filteredAccount;
    if (_filterClaimAccountId != null) {
      filteredAccount = _accounts.where((a) => a.id == _filterClaimAccountId).firstOrNull;
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: context.cashier.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: context.cashier.border),
      ),
      child: Wrap(
        spacing: 14,
        runSpacing: 12,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          if (filteredAccount != null) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: context.cashier.selected.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: context.cashier.selected.withValues(alpha: 0.3),
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.person, size: 14, color: context.cashier.selected),
                  const SizedBox(width: 6),
                  Text(
                    '筛选客户: ${filteredAccount.customerName}',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: context.cashier.selected,
                    ),
                  ),
                  const SizedBox(width: 4),
                  InkWell(
                    key: const Key('receivable-claims-clear-account-filter'),
                    onTap: () {
                      setState(() => _filterClaimAccountId = null);
                      _loadData();
                    },
                    child: Icon(Icons.close, size: 14, color: context.cashier.selected,
                    ),
                  ),
                ],
              ),
            ),
          ],
          SizedBox(
            width: 260,
            height: 38,
            child: TextField(
              key: const Key('receivable-claim-search-input'),
              decoration: InputDecoration(
                hintText: '搜索借据编号、订单号、客户名称...',
                hintStyle: TextStyle(fontSize: 13, color: context.cashier.inkMuted,
                ),
                prefixIcon: const Icon(Icons.search, size: 18),
                contentPadding: const EdgeInsets.symmetric(horizontal: 10),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(color: context.cashier.border),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(color: context.cashier.border),
                ),
              ),
              onChanged: (val) {
                setState(() => _claimSearchKeyword = val);
              },
            ),
          ),
          DropdownButton<String>(
            key: const Key('receivable-claim-status-select'),
            value: _selectedClaimStatus,
            underline: const SizedBox.shrink(),
            items: const [
              DropdownMenuItem(value: 'ALL', child: Text('全部借据状态')),
              DropdownMenuItem(value: 'OPEN', child: Text('待结清 (OPEN)')),
              DropdownMenuItem(value: 'PARTIAL', child: Text('部分已回款 (PARTIAL)'),
              ),
              DropdownMenuItem(value: 'SETTLED', child: Text('已结清 (SETTLED)')),
              DropdownMenuItem(value: 'OVERDUE', child: Text('已逾期 (OVERDUE)')),
              DropdownMenuItem(value: 'WRITTEN_OFF', child: Text('坏账已核销 (WRITTEN_OFF)'),
              ),
              DropdownMenuItem(value: 'REVERSED', child: Text('已冲正废弃 (REVERSED)'),
              ),
            ],
            onChanged: (val) {
              if (val != null) {
                setState(() => _selectedClaimStatus = val);
                _loadData();
              }
            },
          ),
          Text(
            '共匹配 ${_filteredClaims.length} 笔借据',
            style: TextStyle(fontSize: 13, color: context.cashier.inkMuted),
          ),
        ],
      ),
    );
  }

  Widget _buildClaimsTable(BuildContext context, List<ReceivableClaimModel> claims,
  ) {
    if (claims.isEmpty) {
      return Container(
        padding: const EdgeInsets.symmetric(vertical: 48),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: context.cashier.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: context.cashier.border),
        ),
        child: Column(
          children: [
            Icon(Icons.receipt_long_outlined, size: 48, color: context.cashier.inkMuted,
            ),
            const SizedBox(height: 12),
            Text(
              '暂无符合条件的应收借据明细',
              style: TextStyle(color: context.cashier.inkMuted, fontSize: 14),
            ),
          ],
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: context.cashier.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: context.cashier.border),
      ),
      child: ListView.separated(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: claims.length,
        separatorBuilder: (_, __) => Divider(height: 1, color: context.cashier.border),
        itemBuilder: (context, index) {
          final claim = claims[index];
          return _buildClaimRow(context, claim);
        },
      ),
    );
  }

  Widget _buildClaimRow(BuildContext context, ReceivableClaimModel claim) {
    return Padding(
      key: Key('receivable-claim-row-${claim.id}'),
      padding: const EdgeInsets.all(16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // 借据基本标识与订单
          Expanded(
            flex: 3,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      claim.claimNo,
                      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(width: 8),
                    _claimStatusBadge(claim.status),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  '关联订单: ${claim.orderNo.isEmpty ? "-" : claim.orderNo} · 客户: ${claim.customerName ?? "账户#${claim.accountId}"}',
                  style: TextStyle(fontSize: 12, color: context.cashier.inkMuted,
                  ),
                ),
                if (claim.notes != null && claim.notes!.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    '备注: ${claim.notes}',
                    style: TextStyle(fontSize: 11, color: context.cashier.inkMuted,
                    ),
                  ),
                ],
              ],
            ),
          ),

          // 金额明细
          Expanded(
            flex: 3,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      '未清: ¥${claim.uncollectedYuan.toStringAsFixed(2)}',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: claim.uncollectedFen > 0 ? context.cashier.selected : context.cashier.inkMuted,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '总额: ¥${claim.amountYuan.toStringAsFixed(2)}',
                      style: TextStyle(fontSize: 12, color: context.cashier.inkMuted,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  '已收: ¥${claim.collectedYuan.toStringAsFixed(2)}',
                  style: const TextStyle(fontSize: 12, color: Color(0xff16a34a),
                  ),
                ),
              ],
            ),
          ),

          // 日期与账期
          Expanded(
            flex: 2,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '发生: ${claim.createdAt != null && claim.createdAt!.length >= 10 ? claim.createdAt!.substring(0, 10) : (claim.createdAt ?? "-")}',
                  style: TextStyle(fontSize: 12, color: context.cashier.inkMuted,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '到期: ${claim.dueDate != null && claim.dueDate!.length >= 10 ? claim.dueDate!.substring(0, 10) : (claim.dueDate ?? "-")}',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: claim.isOverdue ? FontWeight.bold : FontWeight.normal,
                    color: claim.isOverdue ? context.cashier.danger : context.cashier.inkMuted,
                  ),
                ),
              ],
            ),
          ),

          // 操作按钮组
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              FilledButton.tonal(
                key: Key('receivable-claim-collect-button-${claim.id}'),
                onPressed: (claim.isCollectable && _hasManagePermission)
                    ? () => _showCollectDialog(claim)
                    : null,
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8,
                  ),
                  textStyle: const TextStyle(fontSize: 12),
                ),
                child: const Text('登记收款'),
              ),
              const SizedBox(width: 6),
              OutlinedButton(
                key: Key('receivable-claim-reverse-button-${claim.id}'),
                onPressed: (claim.canReverse && _hasManagePermission)
                    ? () => _showReverseDialog(claim)
                    : null,
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8,
                  ),
                  textStyle: const TextStyle(fontSize: 12),
                ),
                child: const Text('冲正'),
              ),
              const SizedBox(width: 6),
              OutlinedButton(
                key: Key('receivable-claim-writeoff-button-${claim.id}'),
                onPressed: (claim.canWriteOff && _hasManagePermission)
                    ? () => _showWriteOffDialog(claim)
                    : null,
                style: OutlinedButton.styleFrom(
                  foregroundColor: context.cashier.danger,
                  side: BorderSide(
                    color: (claim.canWriteOff && _hasManagePermission)
                        ? context.cashier.danger.withValues(alpha: 0.5)
                        : context.cashier.border,
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8,
                  ),
                  textStyle: const TextStyle(fontSize: 12),
                ),
                child: const Text('坏账核销'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _claimStatusBadge(String status) {
    return switch (status) {
      'OPEN' => _badge(
          label: '待结清',
          color: const Color(0xff0284c7),
          bg: const Color(0xffe0f2fe),
        ),
      'PARTIAL' => _badge(
          label: '部分已收',
          color: const Color(0xffd97706),
          bg: const Color(0xfffef3c7),
        ),
      'SETTLED' => _badge(
          label: '已全额结清',
          color: const Color(0xff16a34a),
          bg: const Color(0xffdcfce7),
        ),
      'OVERDUE' => _badge(
          label: '已逾期',
          color: const Color(0xffdc2626),
          bg: const Color(0xfffee2e2),
        ),
      'WRITTEN_OFF' => _badge(
          label: '坏账核销',
          color: const Color(0xff64748b),
          bg: const Color(0xfff1f5f9),
        ),
      'REVERSED' => _badge(
          label: '已冲正废弃',
          color: const Color(0xff64748b),
          bg: const Color(0xfff1f5f9),
        ),
      _ => Text(status),
    };
  }

  void _showAgingDialog() {
    showDialog(
      context: context,
      builder: (ctx) => ReceivableAgingBreakdownDialog(aging: _aging),
    );
  }

  void _showCollectDialog(ReceivableClaimModel claim) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => ReceivableCollectDialog(
        claim: claim,
        repository: _repository,
        onSuccess: () {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('借据【${claim.claimNo}】回款登记成功')),
            );
            _loadData();
          }
        },
      ),
    );
  }

  void _showWriteOffDialog(ReceivableClaimModel claim) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => ReceivableWriteOffDialog(
        claim: claim,
        repository: _repository,
        isSuperAdmin: widget.permissions.contains('admin:super'),
        onSuccess: () {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('借据【${claim.claimNo}】坏账核销完成')),
            );
            _loadData();
          }
        },
      ),
    );
  }

  void _showReverseDialog(ReceivableClaimModel claim) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => ReceivableReverseDialog(
        claim: claim,
        repository: _repository,
        isSuperAdmin: widget.permissions.contains('admin:super'),
        onSuccess: () {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('借据【${claim.claimNo}】冲正撤销成功')),
            );
            _loadData();
          }
        },
      ),
    );
  }
}

class ReceivableAccountFormDialog extends StatefulWidget {
  const ReceivableAccountFormDialog({
    super.key,
    this.existing,
    this.canManageMerchantScope = false,
    required this.onSave,
  });

  final ReceivableAccountModel? existing;
  final bool canManageMerchantScope;
  final Future<void> Function(ReceivableAccountFormData form) onSave;

  @override
  State<ReceivableAccountFormDialog> createState() => _ReceivableAccountFormDialogState();
}

class _ReceivableAccountFormDialogState extends State<ReceivableAccountFormDialog> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _nameController;
  late TextEditingController _contactNameController;
  late TextEditingController _contactPhoneController;
  late TextEditingController _taxNoController;
  late TextEditingController _creditLimitController;
  late TextEditingController _paymentTermsDaysController;
  late TextEditingController _notesController;

  late String _customerType;
  late String _scopeType;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final ex = widget.existing;
    _nameController = TextEditingController(text: ex?.customerName ?? '');
    _contactNameController = TextEditingController(text: ex?.contactName ?? '');
    _contactPhoneController = TextEditingController(text: ex?.contactPhone ?? '',
    );
    _taxNoController = TextEditingController(text: ex?.taxNo ?? '');
    _creditLimitController = TextEditingController(
      text: ex != null ? (ex.creditLimitFen / 100.0).toStringAsFixed(2) : '10000.00',
    );
    _paymentTermsDaysController = TextEditingController(
      text: (ex?.paymentTermsDays ?? 30).toString(),
    );
    _notesController = TextEditingController(text: ex?.notes ?? '');
    _customerType = ex?.customerType ?? 'COMPANY';
    _scopeType = ex?.scopeType ?? 'SHOP';
  }

  @override
  void dispose() {
    _nameController.dispose();
    _contactNameController.dispose();
    _contactPhoneController.dispose();
    _taxNoController.dispose();
    _creditLimitController.dispose();
    _paymentTermsDaysController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.existing != null;

    return Dialog(
      key: const Key('receivable-form-dialog'),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        width: 600,
        padding: const EdgeInsets.all(24),
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    isEdit ? '编辑挂账授信账户' : '新增挂账授信账户',
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: _saving ? null : () => Navigator.pop(context),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              if (_error != null)
                Container(
                  padding: const EdgeInsets.all(10),
                  margin: const EdgeInsets.only(bottom: 12),
                  decoration: BoxDecoration(
                    color: Colors.red.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(_error!, style: const TextStyle(color: Colors.red, fontSize: 13),
                  ),
                ),
              Flexible(
                child: SingleChildScrollView(
                  child: Column(
                    children: [
                      TextFormField(
                        controller: _nameController,
                        decoration: const InputDecoration(
                          labelText: '客户/单位名称 *',
                          hintText: '如：万达商管餐饮部、老费烧烤VIP李总',
                        ),
                        validator: (v) => v == null || v.trim().isEmpty ? '客户名称不能为空' : null,
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: DropdownButtonFormField<String>(
                              initialValue: _customerType,
                              decoration: const InputDecoration(labelText: '客户类型 *',
                              ),
                              items: const [
                                DropdownMenuItem(value: 'COMPANY', child: Text('企业客户 (COMPANY)'),
                                ),
                                DropdownMenuItem(value: 'PERSONAL', child: Text('个人客户 (PERSONAL)'),
                                ),
                              ],
                              onChanged: isEdit ? null : (v) => setState(() => _customerType = v!),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: DropdownButtonFormField<String>(
                              initialValue: _scopeType,
                              decoration: const InputDecoration(labelText: '适用范围 *',
                              ),
                              items: [
                                const DropdownMenuItem(value: 'SHOP', child: Text('本店专属 (SHOP)'),
                                ),
                                if (widget.canManageMerchantScope || _scopeType == 'MERCHANT')
                                  const DropdownMenuItem(value: 'MERCHANT', child: Text('全商户跨店 (MERCHANT)'),
                                  ),
                              ],
                              onChanged: isEdit ? null : (v) => setState(() => _scopeType = v!),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: TextFormField(
                              controller: _contactNameController,
                              decoration: const InputDecoration(labelText: '经办人姓名',
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: TextFormField(
                              controller: _contactPhoneController,
                              decoration: const InputDecoration(labelText: '联系电话',
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _taxNoController,
                        decoration: const InputDecoration(
                          labelText: '统一社会信用代码 / 税号',
                          hintText: '企业客户报销税号 (选填)',
                        ),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: TextFormField(
                              controller: _creditLimitController,
                              decoration: const InputDecoration(
                                labelText: '授信总额度 (元) *',
                                prefixText: '¥ ',
                              ),
                              keyboardType: const TextInputType.numberWithOptions(decimal: true,
                                  ),
                              validator: (v) {
                                if (v == null || v.trim().isEmpty) return '额度不能为空';
                                final val = double.tryParse(v.trim());
                                if (val == null || val < 0) return '请输入有效金额';
                                if (isEdit && val < widget.existing!.outstandingYuan) {
                                  return '授信额度不得低于当前未清欠款 (¥${widget.existing!.outstandingYuan.toStringAsFixed(2)})';
                                }
                                return null;
                              },
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: TextFormField(
                              controller: _paymentTermsDaysController,
                              decoration: const InputDecoration(
                                labelText: '约定账期 (天) *',
                                suffixText: '天',
                              ),
                              keyboardType: TextInputType.number,
                              validator: (v) {
                                if (v == null || v.trim().isEmpty) return '账期不能为空';
                                final val = int.tryParse(v.trim());
                                if (val == null || val < 0) return '请输入正整数天数';
                                return null;
                              },
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _notesController,
                        maxLines: 2,
                        decoration: const InputDecoration(
                          labelText: '备注说明',
                          hintText: '财务对账周期、特殊要求等',
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  OutlinedButton(
                    onPressed: _saving ? null : () => Navigator.pop(context),
                    child: const Text('取消'),
                  ),
                  const SizedBox(width: 12),
                  FilledButton(
                    onPressed: _saving ? null : _submit,
                    child: _saving
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white,
                            ),
                          )
                        : const Text('确认保存'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _saving = true;
      _error = null;
    });

    final limitYuan = double.parse(_creditLimitController.text.trim());
    final limitFen = (limitYuan * 100).round();
    final terms = int.parse(_paymentTermsDaysController.text.trim());

    final form = ReceivableAccountFormData(
      customerName: _nameController.text,
      customerType: _customerType,
      scopeType: _scopeType,
      contactName: _contactNameController.text,
      contactPhone: _contactPhoneController.text,
      taxNo: _taxNoController.text,
      creditLimitFen: limitFen,
      paymentTermsDays: terms,
      notes: _notesController.text,
    );

    try {
      await widget.onSave(form);
      if (mounted) {
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _saving = false;
        });
      }
    }
  }
}

class ReceivableStatementDialog extends StatefulWidget {
  const ReceivableStatementDialog({
    super.key,
    required this.account,
    required this.repository,
  });

  final ReceivableAccountModel account;
  final ReceivableManagementRepository repository;

  @override
  State<ReceivableStatementDialog> createState() => _ReceivableStatementDialogState();
}

class _ReceivableStatementDialogState extends State<ReceivableStatementDialog> {
  bool _loading = true;
  String? _error;
  List<ReceivableStatementItem> _items = [];

  @override
  void initState() {
    super.initState();
    _loadStatement();
  }

  Future<void> _loadStatement() async {
    try {
      final items = await widget.repository.fetchStatement(widget.account.id);
      if (mounted) {
        setState(() {
          _items = items;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _loading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      key: const Key('receivable-statement-dialog'),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        width: 700,
        height: 520,
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '客户对账单流水 · ${widget.account.customerName}',
                        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '当前未清挂账余额: ¥${widget.account.outstandingYuan.toStringAsFixed(2)} · 授信额度: ¥${widget.account.creditLimitYuan.toStringAsFixed(2)}',
                        style: TextStyle(fontSize: 13, color: context.cashier.inkMuted,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    OutlinedButton.icon(
                      key: const Key('receivable-statement-export-csv-btn'),
                      onPressed: _items.isEmpty ? null : _exportCsv,
                      icon: const Icon(Icons.download, size: 16),
                      label: const Text('导出CSV'),
                    ),
                    const SizedBox(width: 8),
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
              ],
            ),
            const Divider(height: 24),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _error != null
                      ? Center(child: Text('加载流水失败: $_error', style: const TextStyle(color: Colors.red),
                      ),
                    )
                      : _items.isEmpty
                          ? Center(
                              child: Text(
                                '暂无对账流水记录',
                                style: TextStyle(color: context.cashier.inkMuted, fontSize: 14,
                        ),
                              ),
                            )
                          : ListView.separated(
                              itemCount: _items.length,
                              separatorBuilder: (_, __) => const Divider(height: 1),
                              itemBuilder: (context, index) {
                                final item = _items[index];
                                return ListTile(
                                  leading: _entryTypeIcon(item),
                                  title: Row(
                                    children: [
                                      Text(
                                        item.entryTypeLabel,
                                        style: const TextStyle(fontWeight: FontWeight.bold,
                                ),
                                      ),
                                      const SizedBox(width: 8),
                                      if (item.orderNo != null)
                                        Text(
                                          '订单号: ${item.orderNo}',
                                          style: TextStyle(fontSize: 12, color: context.cashier.inkMuted,
                                  ),
                                        ),
                                    ],
                                  ),
                                  subtitle: Text(
                                    '${item.createdAt ?? "-"} ${item.note != null ? "· 备注: ${item.note}" : ""}',
                                    style: TextStyle(fontSize: 12, color: context.cashier.inkMuted,
                            ),
                                  ),
                                  trailing: Text(
                                    '${item.isCharge ? "+" : "-"}¥${item.amountYuan.toStringAsFixed(2)}',
                                    style: TextStyle(
                                      fontSize: 15,
                                      fontWeight: FontWeight.bold,
                                      color: item.isCharge
                                          ? const Color(0xffd97706)
                                          : (item.isCollection ? const Color(0xff16a34a) : context.cashier.ink),
                                    ),
                                  ),
                                );
                              },
                            ),
            ),
          ],
        ),
      ),
    );
  }

  void _exportCsv() {
    final buffer = StringBuffer();
    buffer.writeln('流水号,类型,订单号,金额(元),发生时间,备注');
    for (final item in _items) {
      buffer.writeln(
        '${item.id},${item.entryTypeLabel},${item.orderNo ?? ""},'
        '${item.amountYuan.toStringAsFixed(2)},${item.createdAt ?? ""},'
        '"${item.note?.replaceAll('"', '""') ?? ""}"',
      );
    }
    Clipboard.setData(ClipboardData(text: buffer.toString()));
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('对账单已成功导出 (CSV 内容已复制到剪贴板)')));
  }

  Widget _entryTypeIcon(ReceivableStatementItem item) {
    return switch (item.entryType) {
      'CHARGE' => Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: const Color(0xfffef3c7),
          borderRadius: BorderRadius.circular(8),
        ),
        child: const Icon(
          Icons.receipt_outlined,
          color: Color(0xffd97706),
          size: 20,
        ),
      ),
      'COLLECTION' => Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: const Color(0xffdcfce7),
          borderRadius: BorderRadius.circular(8),
        ),
        child: const Icon(
          Icons.price_check_outlined,
          color: Color(0xff16a34a),
          size: 20,
        ),
      ),
      'REVERSAL' => Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: const Color(0xffe0f2fe),
          borderRadius: BorderRadius.circular(8),
        ),
        child: const Icon(
          Icons.undo_outlined,
          color: Color(0xff0284c7),
          size: 20,
        ),
      ),
      'WRITEOFF' => Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: const Color(0xfffee2e2),
          borderRadius: BorderRadius.circular(8),
        ),
        child: const Icon(
          Icons.money_off_outlined,
          color: Color(0xffdc2626),
          size: 20,
        ),
      ),
      _ => const Icon(Icons.receipt),
    };
  }
}

/// 5级账龄深度分析弹窗
class ReceivableAgingBreakdownDialog extends StatelessWidget {
  const ReceivableAgingBreakdownDialog({super.key, required this.aging});

  final ReceivableAgingSummary aging;

  @override
  Widget build(BuildContext context) {
    final double total = aging.totalOutstandingYuan;
    return Dialog(
      key: const Key('receivable-aging-breakdown-dialog'),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        width: 620,
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.analytics_outlined,
                      color: context.cashier.selected,
                      size: 24,
                    ),
                    const SizedBox(width: 8),
                    const Text(
                      '5级应收账龄深度分析',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              '未清挂账总额: ¥${aging.totalOutstandingYuan.toStringAsFixed(2)} · 逾期总额: ¥${aging.overdueYuan.toStringAsFixed(2)}',
              style: TextStyle(fontSize: 13, color: context.cashier.inkMuted),
            ),
            const Divider(height: 24),
            _buildTierRow(
              context,
              tierName: '正常未到期 (Current)',
              amountYuan: aging.currentYuan,
              totalYuan: total,
              color: const Color(0xff16a34a),
            ),
            const SizedBox(height: 12),
            _buildTierRow(
              context,
              tierName: '逾期 1~30 天',
              amountYuan: aging.days1To30Yuan,
              totalYuan: total,
              color: const Color(0xffca8a04),
            ),
            const SizedBox(height: 12),
            _buildTierRow(
              context,
              tierName: '逾期 31~60 天',
              amountYuan: aging.days31To60Yuan,
              totalYuan: total,
              color: const Color(0xffea580c),
            ),
            const SizedBox(height: 12),
            _buildTierRow(
              context,
              tierName: '逾期 61~90 天',
              amountYuan: aging.days61To90Yuan,
              totalYuan: total,
              color: const Color(0xffdc2626),
            ),
            const SizedBox(height: 12),
            _buildTierRow(
              context,
              tierName: '逾期 90+ 天 (严重呆账)',
              amountYuan: aging.days90PlusYuan,
              totalYuan: total,
              color: const Color(0xff991b1b),
            ),
            const SizedBox(height: 24),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('关闭'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTierRow(
    BuildContext context, {
    required String tierName,
    required double amountYuan,
    required double totalYuan,
    required Color color,
  }) {
    final double ratio = totalYuan > 0
        ? (amountYuan / totalYuan).clamp(0.0, 1.0)
        : 0.0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              tierName,
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
            ),
            Text(
              '¥${amountYuan.toStringAsFixed(2)} (${(ratio * 100).toStringAsFixed(1)}%)',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Container(
          height: 8,
          decoration: BoxDecoration(
            color: const Color(0xffe2e8f0),
            borderRadius: BorderRadius.circular(4),
          ),
          child: FractionallySizedBox(
            alignment: Alignment.centerLeft,
            widthFactor: ratio,
            child: Container(
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(4),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// 借据直接登记收款弹窗
class ReceivableCollectDialog extends StatefulWidget {
  const ReceivableCollectDialog({
    super.key,
    required this.claim,
    required this.repository,
    required this.onSuccess,
  });

  final ReceivableClaimModel claim;
  final ReceivableManagementRepository repository;
  final VoidCallback onSuccess;

  @override
  State<ReceivableCollectDialog> createState() =>
      _ReceivableCollectDialogState();
}

class _ReceivableCollectDialogState extends State<ReceivableCollectDialog> {
  String? _requestId;
  String? _requestPayload;
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _amountController;
  late TextEditingController _noteController;
  String _channel = 'BANK_TRANSFER';
  bool _submitting = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _amountController = TextEditingController(
      text: widget.claim.uncollectedYuan.toStringAsFixed(2),
    );
    _noteController = TextEditingController();
  }

  @override
  void dispose() {
    _amountController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_submitting) return;
    if (!_formKey.currentState!.validate()) return;
    final amountYuan = double.tryParse(_amountController.text.trim()) ?? 0.0;
    final amountFen = (amountYuan * 100).round();
    if (amountFen <= 0 || amountFen > widget.claim.uncollectedFen) {
      setState(
        () => _error =
            '回款金额必须大于 0 且不超过未清金额 ¥${widget.claim.uncollectedYuan.toStringAsFixed(2)}',
      );
      return;
    }

    setState(() {
      _submitting = true;
      _error = null;
    });

    try {
      final payload = '$amountFen|$_channel|${_noteController.text.trim()}';
      if (_requestPayload != payload) {
        _requestPayload = payload;
        _requestId =
            'COL_${DateTime.now().microsecondsSinceEpoch}_${widget.claim.id}';
      }
      await widget.repository.collectClaim(
        claimId: widget.claim.id,
        amountFen: amountFen,
        channel: _channel,
        requestId: _requestId!,
        note: _noteController.text.trim().isEmpty
            ? null
            : _noteController.text.trim(),
      );
      if (mounted) {
        Navigator.pop(context);
        widget.onSuccess();
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _submitting = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      key: const Key('receivable-collect-dialog'),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        width: 500,
        padding: const EdgeInsets.all(24),
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.price_check_outlined,
                        color: context.cashier.selected,
                        size: 24,
                      ),
                      const SizedBox(width: 8),
                      const Text(
                        '登记挂账回款',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
              const Divider(height: 20),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: context.cashier.surface,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: context.cashier.border),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '借据编号: ${widget.claim.claimNo} · 关联订单: ${widget.claim.orderNo.isEmpty ? "-" : widget.claim.orderNo}',
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '客户名称: ${widget.claim.customerName ?? "-"}',
                      style: TextStyle(
                        fontSize: 12,
                        color: context.cashier.inkMuted,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '借据总额: ¥${widget.claim.amountYuan.toStringAsFixed(2)} · 已收: ¥${widget.claim.collectedYuan.toStringAsFixed(2)} · 未清欠款: ¥${widget.claim.uncollectedYuan.toStringAsFixed(2)}',
                      style: TextStyle(
                        fontSize: 12,
                        color: context.cashier.selected,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              TextFormField(
                key: const Key('receivable-collect-amount-input'),
                controller: _amountController,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: InputDecoration(
                  labelText: '本次回款金额 (元)',
                  prefixText: '¥ ',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                validator: (val) {
                  final parsed = double.tryParse(val?.trim() ?? '');
                  if (parsed == null || parsed <= 0) return '请输入合法的回款金额';
                  return null;
                },
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                key: const Key('receivable-collect-channel-select'),
                isExpanded: true,
                initialValue: _channel,
                decoration: InputDecoration(
                  labelText: '资金结算方式 / 渠道',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                items: const [
                  DropdownMenuItem(
                    value: 'BANK_TRANSFER',
                    child: Text('银行转账 (BANK_TRANSFER)'),
                  ),
                  DropdownMenuItem(
                    value: 'WECHAT',
                    child: Text('微信支付 (WECHAT)'),
                  ),
                  DropdownMenuItem(
                    value: 'ALIPAY',
                    child: Text('支付宝 (ALIPAY)'),
                  ),
                  DropdownMenuItem(value: 'CASH', child: Text('现金结算 (CASH)')),
                  DropdownMenuItem(value: 'OTHER', child: Text('其他方式 (OTHER)')),
                ],
                onChanged: (val) {
                  if (val != null) setState(() => _channel = val);
                },
              ),
              const SizedBox(height: 16),
              TextFormField(
                key: const Key('receivable-collect-note-input'),
                controller: _noteController,
                decoration: InputDecoration(
                  labelText: '回款备注 (如银行流水号、转账人姓名)',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(
                  _error!,
                  style: TextStyle(color: context.cashier.danger, fontSize: 13),
                ),
              ],
              const SizedBox(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  OutlinedButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('取消'),
                  ),
                  const SizedBox(width: 12),
                  FilledButton(
                    key: const Key('receivable-collect-submit-btn'),
                    onPressed: _submitting ? null : _submit,
                    child: _submitting
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Text('确认登记回款'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 借据坏账核销弹窗
class ReceivableWriteOffDialog extends StatefulWidget {
  const ReceivableWriteOffDialog({
    super.key,
    required this.claim,
    required this.repository,
    required this.isSuperAdmin,
    required this.onSuccess,
  });

  final ReceivableClaimModel claim;
  final ReceivableManagementRepository repository;
  final bool isSuperAdmin;
  final VoidCallback onSuccess;

  @override
  State<ReceivableWriteOffDialog> createState() =>
      _ReceivableWriteOffDialogState();
}

class _ReceivableWriteOffDialogState extends State<ReceivableWriteOffDialog> {
  final _reasonController = TextEditingController();
  bool _submitting = false;
  String? _error;

  @override
  void dispose() {
    _reasonController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final reason = _reasonController.text.trim();
    if (reason.isEmpty) {
      setState(() => _error = '请详细填写坏账核销的原因');
      return;
    }

    if (!widget.isSuperAdmin) {
      final authResult = await showPosAuthDialog(
        context,
        title: '坏账核销经理授权',
        reason:
            '借据编号: ${widget.claim.claimNo} 核销呆账 ¥${widget.claim.uncollectedYuan.toStringAsFixed(2)}',
        onVerify: (account, password) async {
          await widget.repository.verifyPassword(
            username: account,
            password: password,
          );
        },
      );
      if (authResult == null) {
        return;
      }
    }

    setState(() {
      _submitting = true;
      _error = null;
    });

    try {
      final reqId =
          'WO_${DateTime.now().millisecondsSinceEpoch}_${widget.claim.id}';
      await widget.repository.writeOffClaim(
        claimId: widget.claim.id,
        reason: reason,
        requestId: reqId,
      );
      if (mounted) {
        Navigator.pop(context);
        widget.onSuccess();
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _submitting = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      key: const Key('receivable-writeoff-dialog'),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        width: 500,
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.money_off_outlined,
                      color: context.cashier.danger,
                      size: 24,
                    ),
                    const SizedBox(width: 8),
                    const Text(
                      '呆账坏账核销',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
            const Divider(height: 20),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: context.cashier.danger.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: context.cashier.danger.withValues(alpha: 0.2),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.warning_amber_rounded,
                        size: 16,
                        color: context.cashier.danger,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        '财务严正警告: 坏账核销不可逆',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                          color: context.cashier.danger,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '核销借据【${widget.claim.claimNo}】将永久确认该笔挂账欠款 ¥${widget.claim.uncollectedYuan.toStringAsFixed(2)} 为无法收回的商业呆账，该操作将记录财务审计日志。',
                    style: TextStyle(
                      fontSize: 12,
                      color: context.cashier.inkMuted,
                      height: 1.4,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              key: const Key('receivable-writeoff-reason-input'),
              controller: _reasonController,
              maxLines: 3,
              decoration: InputDecoration(
                labelText: '坏账核销原因 (如企业破产清算、长期失联诉讼终结)',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(
                _error!,
                style: TextStyle(color: context.cashier.danger, fontSize: 13),
              ),
            ],
            const SizedBox(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                OutlinedButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('取消'),
                ),
                const SizedBox(width: 12),
                FilledButton(
                  key: const Key('receivable-writeoff-submit-btn'),
                  style: FilledButton.styleFrom(
                    backgroundColor: context.cashier.danger,
                  ),
                  onPressed: _submitting ? null : _submit,
                  child: _submitting
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Text('确认核销坏账'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// 借据冲正撤销弹窗
class ReceivableReverseDialog extends StatefulWidget {
  const ReceivableReverseDialog({
    super.key,
    required this.claim,
    required this.repository,
    required this.isSuperAdmin,
    required this.onSuccess,
  });

  final ReceivableClaimModel claim;
  final ReceivableManagementRepository repository;
  final bool isSuperAdmin;
  final VoidCallback onSuccess;

  @override
  State<ReceivableReverseDialog> createState() =>
      _ReceivableReverseDialogState();
}

class _ReceivableReverseDialogState extends State<ReceivableReverseDialog> {
  final _reasonController = TextEditingController();
  bool _submitting = false;
  String? _error;

  @override
  void dispose() {
    _reasonController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final reason = _reasonController.text.trim();
    if (reason.isEmpty) {
      setState(() => _error = '请填写冲正原因');
      return;
    }

    if (!widget.isSuperAdmin) {
      final authResult = await showPosAuthDialog(
        context,
        title: '挂账冲正经理授权',
        reason:
            '借据编号: ${widget.claim.claimNo} 冲正金额 ¥${widget.claim.amountYuan.toStringAsFixed(2)}',
        onVerify: (account, password) async {
          await widget.repository.verifyPassword(
            username: account,
            password: password,
          );
        },
      );
      if (authResult == null) {
        return;
      }
    }

    setState(() {
      _submitting = true;
      _error = null;
    });

    try {
      final reqId =
          'REV_${DateTime.now().millisecondsSinceEpoch}_${widget.claim.id}';
      await widget.repository.reverseClaim(
        claimId: widget.claim.id,
        reason: reason,
        requestId: reqId,
      );
      if (mounted) {
        Navigator.pop(context);
        widget.onSuccess();
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _submitting = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      key: const Key('receivable-reverse-dialog'),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        width: 500,
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Row(
                  children: [
                    Icon(
                      Icons.undo_outlined,
                      color: Color(0xff0284c7),
                      size: 24,
                    ),
                    SizedBox(width: 8),
                    Text(
                      '挂账借据冲正撤销',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
            const Divider(height: 20),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xffe0f2fe),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xffbae6fd)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(
                    children: [
                      Icon(
                        Icons.info_outline,
                        size: 16,
                        color: Color(0xff0284c7),
                      ),
                      SizedBox(width: 6),
                      Text(
                        '冲正撤销说明',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                          color: Color(0xff0284c7),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '冲正借据【${widget.claim.claimNo}】将撤销金额 ¥${widget.claim.amountYuan.toStringAsFixed(2)} 的未清账款，并联动原订单撤销挂账结算。仅未发生回款的借据支持冲正。',
                    style: TextStyle(
                      fontSize: 12,
                      color: context.cashier.inkMuted,
                      height: 1.4,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              key: const Key('receivable-reverse-reason-input'),
              controller: _reasonController,
              decoration: InputDecoration(
                labelText: '冲正原因 (如收银员误挂账、转其他方式付款)',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(
                _error!,
                style: TextStyle(color: context.cashier.danger, fontSize: 13),
              ),
            ],
            const SizedBox(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                OutlinedButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('取消'),
                ),
                const SizedBox(width: 12),
                FilledButton(
                  key: const Key('receivable-reverse-submit-btn'),
                  onPressed: _submitting ? null : _submit,
                  child: _submitting
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Text('确认冲正撤销'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
