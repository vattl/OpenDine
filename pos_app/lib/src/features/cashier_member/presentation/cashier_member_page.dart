import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/admin_api_client.dart';
import '../../../core/cashier_operation_audit.dart';
import '../../auth/data/access_approval_repository.dart';
import '../../cashier_shell/presentation/cashier_approval_dialog.dart';
import '../../cashier_shell/presentation/cashier_components.dart';
import '../../cashier_shell/presentation/cashier_section_visibility.dart';
import '../../pos/presentation/pos_notice_dialog.dart';
import '../data/cashier_member_repository.dart';
import '../domain/cashier_member.dart';
import '../../cashier_settings/presentation/cashier_settings_shared.dart';
import '../../cashier_shell/presentation/cashier_tokens.dart';
import 'member_consumption_order_detail_dialog.dart';

/// 会员主界面（图1：统计卡 + 搜索 + 工具栏 + 会员表格）与会员详情页（图2）。
///
/// 数据全部来自真实接口：
/// - 统计卡：GET /admin/member/stats（v1.2.231）
/// - 列表 / 搜索：POST /admin/order/getUserInfo
/// - 详情：GET /admin/member/profile、GET /admin/member/consumption、
///   GET /admin/member/recharge/list
/// - 一键发券：GET /admin/coupon/list + POST /admin/coupon/batch-send
///
/// 等级口径：0=普通会员 / 1=白银会员 / 2=黄金会员 / 3=铂金会员（前端展示约定，
/// 后端仅存整数等级）。积分/余额变动为派生列，口径见详情页表头脚注。
class CashierMemberPage extends StatefulWidget {
  const CashierMemberPage({
    super.key,
    required this.repository,
    this.approvalRepository,
    this.permissions = const {},
    this.canRecharge = false,
    this.canBindOrder = false,
    this.currentOrderId,
    this.currentOrderNo,
    this.currentTableNumber,
    this.currentOrderStatus,
    this.currentAccount,
    this.isSuperAdmin = false,
  });

  final CashierMemberRepository repository;
  final AccessApprovalRepository? approvalRepository;

  /// 当前登录角色权限码集合，控制「一键发券」等按钮显隐。
  final Set<String> permissions;

  final bool canRecharge;
  final bool canBindOrder;
  final int? currentOrderId;
  final String? currentOrderNo;
  final String? currentTableNumber;
  final String? currentOrderStatus;
  final String? currentAccount;
  final bool isSuperAdmin;

  @override
  State<CashierMemberPage> createState() => _CashierMemberPageState();
}

enum _MemberView { list, detail, rechargeLogs }

class _CashierMemberPageState extends State<CashierMemberPage>
    with CashierSectionVisibilityMixin {
  final _queryController = TextEditingController();

  // 列表视图
  List<CashierMemberRow> _rows = const [];
  int _total = 0;
  int _page = 1;
  static const _pageSize = 20;
  bool _listLoading = false;
  int _requestSeq = 0;
  String? _listError;
  CashierMemberStats _stats = const CashierMemberStats();
  bool _statsLoading = true;
  bool _statsFailed = false;

  // 详情视图
  _MemberView _view = _MemberView.list;
  String? _detailPhone;
  final Set<String> _unmaskedMemberPhones = <String>{};
  CashierMemberProfile? _profile;
  List<MemberConsumptionRecord> _consumption = const [];
  List<MemberRechargeRecord> _recharges = const [];
  bool _detailLoading = false;
  String? _detailError;

  // UI061: 选中的会员画像与近期消费历史
  CashierMemberRow? _selectedMember;
  List<MemberConsumptionRecord> _personaConsumption = const [];
  bool _personaLoading = false;

  // 充值记录视图（单查用户 / 按时间查全部）
  final _logPhoneController = TextEditingController();
  DateTime? _logStart;
  DateTime? _logEnd;
  List<RechargeLogRow> _logRows = const [];
  int _logTotal = 0;
  int _logPage = 1;
  static const _logPageSize = 20;
  bool _logLoading = false;
  bool _logLoaded = false;
  String? _logError;
  int _logRequestSeq = 0;

  @override
  void initState() {
    super.initState();
    _loadList();
    _loadStats();
  }

  @override
  Duration get sectionPollInterval => const Duration(seconds: 15);

  /// 侧边栏切回可见 / 可见轮询：列表视图刷新列表与统计；详情视图刷新档案与记录。
  /// 静默失败保留旧数据，不清除输入或错误提示。
  @override
  Future<void> refreshSectionSilently() async {
    if (_view == _MemberView.detail) {
      final phone = _detailPhone;
      if (phone == null || _detailLoading || _profile == null) return;
      try {
        final results = await Future.wait<Object>([
          widget.repository.loadProfile(phone),
          widget.repository.loadConsumption(phone),
          widget.repository.loadRecharges(phone),
        ]);
        if (!mounted) return;
        setState(() {
          _profile = results[0] as CashierMemberProfile;
          _consumption = results[1] as List<MemberConsumptionRecord>;
          _recharges = results[2] as List<MemberRechargeRecord>;
        });
      } catch (_) {
        // 静默失败：保留当前画面，下轮再试。
      }
      return;
    }
    if (_listLoading) return;
    try {
      await Future.wait([_loadList(silent: true), _loadStats(silent: true)]);
    } catch (_) {
      // 静默失败：保留当前画面，下轮再试。
    }
  }

  @override
  void dispose() {
    _queryController.dispose();
    _logPhoneController.dispose();
    super.dispose();
  }

  Future<void> _loadList({bool silent = false}) async {
    // 抢占式加载：每次调用领取新序号，过期响应按序号丢弃，杜绝快速翻页/静默刷新竞态。
    final seq = ++_requestSeq;
    if (!silent) {
      setState(() {
        _listLoading = true;
        _listError = null;
      });
    }
    try {
      final result = await widget.repository.loadMembers(
        page: _page,
        pageSize: _pageSize,
        query: _queryController.text.trim(),
      );
      if (!mounted || seq != _requestSeq) return;
      setState(() {
        _rows = result.rows;
        _total = result.total;
        _listLoading = false;
        final maxPages = result.total == 0
            ? 1
            : ((result.total + _pageSize - 1) ~/ _pageSize);
        if (_page > maxPages) _page = maxPages;
      });
    } catch (error) {
      if (!mounted || seq != _requestSeq) return;
      setState(() {
        _listLoading = false;
        _listError = _message(error);
      });
    }
  }

  Future<void> _loadStats({bool silent = false}) async {
    if (!silent) {
      setState(() {
        _statsLoading = true;
        _statsFailed = false;
      });
    }
    try {
      final stats = await widget.repository.loadStats();
      if (!mounted) return;
      setState(() {
        _stats = stats;
        _statsLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _statsLoading = false;
        _statsFailed = true;
      });
    }
  }

  Future<void> _search() async {
    setState(() => _page = 1);
    await _loadList();
  }

  Future<void> _goToPage(int page) async {
    if (_listLoading) return;
    setState(() => _page = page);
    await _loadList();
  }

  bool get _hasUnsettledOrder =>
      widget.currentOrderId != null &&
      widget.currentOrderNo?.isNotEmpty == true &&
      widget.currentTableNumber?.isNotEmpty == true &&
      widget.currentOrderStatus?.toLowerCase() == 'unsettled';

  Future<void> _openDetail(CashierMemberRow row) async {
    setState(() {
      _view = _MemberView.detail;
      _detailPhone = row.phone;
    });
    await _loadDetail(row.phone);
  }

  void _backToList() {
    if (_detailPhone != null) {
      _unmaskedMemberPhones.remove(_detailPhone);
    }
    setState(() {
      _view = _MemberView.list;
      _detailPhone = null;
      _profile = null;
      _consumption = const [];
      _recharges = const [];
      _detailError = null;
    });
    _loadList(silent: true);
    _loadStats(silent: true);
  }

  Future<void> _selectMember(CashierMemberRow row) async {
    setState(() {
      _selectedMember = row;
      _personaLoading = true;
      _personaConsumption = const [];
    });
    try {
      final consumption = await widget.repository.loadConsumption(row.phone);
      if (!mounted || _selectedMember?.phone != row.phone) return;
      setState(() {
        _personaConsumption = consumption;
        _personaLoading = false;
      });
    } catch (_) {
      if (!mounted || _selectedMember?.phone != row.phone) return;
      setState(() {
        _personaLoading = false;
      });
    }
  }

  Future<void> _rechargeMemberRow(CashierMemberRow row) async {
    final success = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => _RechargeByPhoneDialog(
        repository: widget.repository,
        initialPhone: row.phone,
      ),
    );
    if (success == true) {
      _loadList(silent: true);
      _loadStats(silent: true);
      if (_selectedMember?.phone == row.phone) {
        _selectMember(row);
      }
    }
  }

  Future<void> _openConsumptionDetailDialog(MemberConsumptionRecord record) async {
    await showDialog<void>(
      context: context,
      builder: (context) => MemberConsumptionOrderDetailDialog(
        record: record,
        repository: widget.repository,
      ),
    );
  }

  Future<void> _togglePhoneMask(
    String phone,
    String memberName,
    int memberId,
  ) async {
    final cleanPhone = phone.trim();
    if (cleanPhone.isEmpty) return;

    if (_unmaskedMemberPhones.contains(cleanPhone)) {
      setState(() {
        _unmaskedMemberPhones.remove(cleanPhone);
      });
      return;
    }

    final canViewPrivacy =
        widget.permissions.contains('user:view') ||
        widget.permissions.contains('admin:manage') ||
        widget.isSuperAdmin;

    if (canViewPrivacy) {
      setState(() {
        _unmaskedMemberPhones.add(cleanPhone);
      });
      CashierOperationAuditStore.instance.record(
        CashierOperationAuditDraft(
          module: 'member',
          action: 'view_privacy_phone',
          result: 'success',
          actorName: widget.currentAccount,
          targetType: 'member',
          targetId: cleanPhone,
          detail: {
            'member_id': memberId,
            'member_name': memberName,
            'member_phone': cleanPhone,
            'direct_permission': true,
          },
        ),
      );
      return;
    }

    // 无直接权限，弹出店长现场审批弹窗
    if (widget.approvalRepository == null) {
      await showPosNotice(
        context,
        title: '提示',
        message: '未配置审批服务，无法申请查看权限',
        tone: PosNoticeTone.warning,
      );
      return;
    }

    final grant = await showCashierApprovalDialog(
      context,
      request: CashierApprovalRequest(
        title: '查看会员隐私信息审批',
        permission: 'user:view',
        permissionLabel: '查看会员完整手机号',
        bizType: 'VIEW_PRIVACY',
        bizId: cleanPhone,
        hint: '需店长或具备 user:view 权限的主管现场授权',
      ),
      repository: widget.approvalRepository!,
      currentAccount: widget.currentAccount,
    );

    if (!mounted) return;

    if (grant != null) {
      setState(() {
        _unmaskedMemberPhones.add(cleanPhone);
      });
      CashierOperationAuditStore.instance.record(
        CashierOperationAuditDraft(
          module: 'member',
          action: 'view_privacy_phone',
          result: 'success',
          actorName: widget.currentAccount,
          targetType: 'member',
          targetId: cleanPhone,
          detail: {
            'member_id': memberId,
            'member_name': memberName,
            'member_phone': cleanPhone,
            'authorized_by': grant.authorizerName,
            'approval_no': grant.approvalNo,
            'direct_permission': false,
          },
        ),
      );
    } else {
      CashierOperationAuditStore.instance.record(
        CashierOperationAuditDraft(
          module: 'member',
          action: 'view_privacy_phone',
          result: 'blocked',
          actorName: widget.currentAccount,
          targetType: 'member',
          targetId: cleanPhone,
          errorMsg: '未获得查看权限',
        ),
      );
      await showPosNotice(
        context,
        title: '提示',
        message: '未获得查看权限，已保持脱敏隐藏',
        tone: PosNoticeTone.info,
      );
    }
  }

  Future<void> _copyPhone(
    String phone,
    String memberName,
    int memberId,
  ) async {
    final cleanPhone = phone.trim();
    if (cleanPhone.isEmpty) return;

    final isAlreadyUnmasked = _unmaskedMemberPhones.contains(cleanPhone);
    final canViewPrivacy =
        widget.permissions.contains('user:view') ||
        widget.permissions.contains('admin:manage') ||
        widget.isSuperAdmin;

    if (isAlreadyUnmasked || canViewPrivacy) {
      if (!isAlreadyUnmasked) {
        setState(() {
          _unmaskedMemberPhones.add(cleanPhone);
        });
      }
      Clipboard.setData(ClipboardData(text: cleanPhone));
      CashierOperationAuditStore.instance.record(
        CashierOperationAuditDraft(
          module: 'member',
          action: 'copy_privacy_phone',
          result: 'success',
          actorName: widget.currentAccount,
          targetType: 'member',
          targetId: cleanPhone,
          detail: {
            'member_id': memberId,
            'member_name': memberName,
            'member_phone': cleanPhone,
            'direct_permission': true,
          },
        ),
      );
      if (!mounted) return;
      showSettingsSaved(context, '手机号已复制到剪贴板');
      return;
    }

    // 脱敏态且无直接权限，调起审批
    if (widget.approvalRepository == null) {
      await showPosNotice(
        context,
        title: '提示',
        message: '未配置审批服务，无法申请复制权限',
        tone: PosNoticeTone.warning,
      );
      return;
    }

    final grant = await showCashierApprovalDialog(
      context,
      request: CashierApprovalRequest(
        title: '复制会员隐私信息审批',
        permission: 'user:view',
        permissionLabel: '复制会员完整手机号',
        bizType: 'VIEW_PRIVACY',
        bizId: cleanPhone,
        hint: '需店长或具备 user:view 权限的主管现场授权',
      ),
      repository: widget.approvalRepository!,
      currentAccount: widget.currentAccount,
    );

    if (!mounted) return;

    if (grant != null) {
      setState(() {
        _unmaskedMemberPhones.add(cleanPhone);
      });
      Clipboard.setData(ClipboardData(text: cleanPhone));
      CashierOperationAuditStore.instance.record(
        CashierOperationAuditDraft(
          module: 'member',
          action: 'copy_privacy_phone',
          result: 'success',
          actorName: widget.currentAccount,
          targetType: 'member',
          targetId: cleanPhone,
          detail: {
            'member_id': memberId,
            'member_name': memberName,
            'member_phone': cleanPhone,
            'authorized_by': grant.authorizerName,
            'approval_no': grant.approvalNo,
            'direct_permission': false,
          },
        ),
      );
      if (!mounted) return;
      showSettingsSaved(context, '授权通过，手机号已复制到剪贴板');
    } else {
      CashierOperationAuditStore.instance.record(
        CashierOperationAuditDraft(
          module: 'member',
          action: 'copy_privacy_phone',
          result: 'blocked',
          actorName: widget.currentAccount,
          targetType: 'member',
          targetId: cleanPhone,
          errorMsg: '未获得复制权限',
        ),
      );
      await showPosNotice(
        context,
        title: '提示',
        message: '未获得查看权限，无法复制完整手机号',
        tone: PosNoticeTone.info,
      );
    }
  }

  Future<void> _loadDetail(String phone) async {
    setState(() {
      _detailLoading = true;
      _detailError = null;
      _profile = null;
      _consumption = const [];
      _recharges = const [];
    });
    try {
      final results = await Future.wait<Object>([
        widget.repository.loadProfile(phone),
        widget.repository.loadConsumption(phone),
        widget.repository.loadRecharges(phone),
      ]);
      if (!mounted) return;
      setState(() {
        _profile = results[0] as CashierMemberProfile;
        _consumption = results[1] as List<MemberConsumptionRecord>;
        _recharges = results[2] as List<MemberRechargeRecord>;
        _detailLoading = false;
      });
    } on MemberNotFoundException {
      if (!mounted) return;
      setState(() {
        _detailLoading = false;
        _detailError = '未找到该手机号对应的会员';
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _detailLoading = false;
        _detailError = _message(error);
      });
    }
  }

  Future<void> _bind() async {
    final profile = _profile;
    if (profile == null || !_hasUnsettledOrder) return;
    final success = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => _BindOrderDialog(
        repository: widget.repository,
        member: profile.member,
        orderId: widget.currentOrderId!,
        orderNo: widget.currentOrderNo!,
        tableNumber: widget.currentTableNumber!,
      ),
    );
    if (success == true) await _loadDetail(profile.member.phone);
  }

  Future<void> _recharge() async {
    final profile = _profile;
    if (profile == null) return;
    final success = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => _RechargeDialog(
        repository: widget.repository,
        member: profile.member,
      ),
    );
    if (success == true) {
      await _loadDetail(profile.member.phone);
      _loadList(silent: true);
      _loadStats(silent: true);
    }
  }

  Future<void> _rechargeByPhone() async {
    final success = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) =>
          _RechargeByPhoneDialog(repository: widget.repository),
    );
    if (success == true) {
      _loadList(silent: true);
      _loadStats(silent: true);
    }
  }

  Future<void> _batchSendCoupon() async {
    await showDialog<void>(
      context: context,
      builder: (context) => _CouponSendDialog(repository: widget.repository),
    );
  }

  Future<void> _createMember() async {
    await showDialog<void>(
      context: context,
      builder: (context) => const _CreateMemberDialog(),
    );
  }

  void _openRechargeLogs() {
    setState(() {
      _view = _MemberView.rechargeLogs;
      _logPage = 1;
    });
    _loadRechargeLogs();
  }

  void _backFromLogs() {
    setState(() => _view = _MemberView.list);
    _loadList(silent: true);
    _loadStats(silent: true);
  }

  String? _formatLogDate(DateTime? d) {
    if (d == null) return null;
    final y = d.year.toString().padLeft(4, '0');
    final m = d.month.toString().padLeft(2, '0');
    final day = d.day.toString().padLeft(2, '0');
    return '$y-$m-$day 00:00:00';
  }

  String? _formatLogEnd(DateTime? d) {
    if (d == null) return null;
    final y = d.year.toString().padLeft(4, '0');
    final m = d.month.toString().padLeft(2, '0');
    final day = d.day.toString().padLeft(2, '0');
    return '$y-$m-$day 23:59:59';
  }

  Future<void> _loadRechargeLogs({bool silent = false}) async {
    final seq = ++_logRequestSeq;
    if (!silent) {
      setState(() {
        _logLoading = true;
        _logError = null;
      });
    }
    try {
      final result = await widget.repository.loadRechargeLogs(
        page: _logPage,
        pageSize: _logPageSize,
        phone: _logPhoneController.text.trim(),
        startTime: _formatLogDate(_logStart) ?? '',
        endTime: _formatLogEnd(_logEnd) ?? '',
      );
      if (!mounted || seq != _logRequestSeq) return;
      setState(() {
        _logRows = result.rows;
        _logTotal = result.total;
        _logLoading = false;
        _logLoaded = true;
        final maxPages = result.total == 0
            ? 1
            : ((result.total + _logPageSize - 1) ~/ _logPageSize);
        if (_logPage > maxPages) _logPage = maxPages;
      });
    } catch (error) {
      if (!mounted || seq != _logRequestSeq) return;
      setState(() {
        _logLoading = false;
        _logError = _message(error);
      });
    }
  }

  Future<void> _searchRechargeLogs() async {
    setState(() => _logPage = 1);
    await _loadRechargeLogs();
  }

  Future<void> _goLogPage(int page) async {
    if (_logLoading) return;
    setState(() => _logPage = page);
    await _loadRechargeLogs();
  }

  Future<void> _pickLogDate({required bool isStart}) async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: (isStart ? _logStart : _logEnd) ?? now,
      firstDate: DateTime(2020, 1, 1),
      lastDate: now,
    );
    if (picked == null || !mounted) return;
    setState(() {
      if (isStart) {
        _logStart = picked;
      } else {
        _logEnd = picked;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: context.cashier.canvas,
      child: switch (_view) {
        _MemberView.detail => _detailView(),
        _MemberView.rechargeLogs => _rechargeLogsView(),
        _MemberView.list => _listView(),
      },
    );
  }

  // ---------- 图1 会员主界面 (UI061 左右双栏极简工业风) ----------

  Widget _listView() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isTwoColumn = constraints.maxWidth >= 900;
        return Padding(
          padding: const EdgeInsets.all(10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _statsRow(constraints.maxWidth),
              const SizedBox(height: 10),
              Expanded(
                child: isTwoColumn
                    ? Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Expanded(
                            flex: 6,
                            child: _buildMemberLeftPane(),
                          ),
                          const SizedBox(width: 10),
                          SizedBox(
                            width: 460,
                            child: _buildMemberPersonaPane(),
                          ),
                        ],
                      )
                    : _buildMemberLeftPane(),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _statsRow(double maxWidth) {
    final cards = [
      _statCard(
        key: const Key('member-stats-count'),
        label: '会员总数',
        value: _statsText(_count(_stats.memberCount)),
      ),
      _statCard(
        key: const Key('member-stats-month-new'),
        label: '今日新增',
        value: _statsText(_count(_stats.todayNewCount)),
      ),
      _statCard(
        key: const Key('member-stats-month-recharge'),
        label: '储值总额',
        value: _statsText(_money(_stats.totalBalance)),
      ),
      _statCard(
        key: const Key('member-stats-month-points'),
        label: '积分发放',
        value: _statsText(_count(_stats.totalPoints)),
      ),
    ];
    if (maxWidth >= 900) {
      return Row(
        children: [
          for (var i = 0; i < cards.length; i++) ...[
            if (i > 0) const SizedBox(width: 10),
            Expanded(child: cards[i]),
          ],
        ],
      );
    }
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: [
        for (final card in cards) SizedBox(width: (maxWidth - 10) / 2, child: card),
      ],
    );
  }

  String _statsText(String value) =>
      _statsLoading || _statsFailed ? '—' : value;

  Widget _statCard({
    required Key key,
    required String label,
    required String value,
  }) {
    return Container(
      key: key,
      height: 104,
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
      decoration: BoxDecoration(
        color: context.cashier.surface,
        border: Border.all(color: context.cashier.border),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: context.cashier.inkSecondary,
            ),
          ),
          const SizedBox(height: 6),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              value,
              style: TextStyle(
                fontSize: 34,
                fontWeight: FontWeight.w900,
                fontFamily: 'monospace',
                color: context.cashier.ink,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMemberLeftPane() {
    return Container(
      decoration: BoxDecoration(
        color: context.cashier.surface,
        border: Border.all(color: context.cashier.border),
        borderRadius: BorderRadius.circular(8),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _toolbar(),
          Expanded(child: _memberTable()),
          _paginationBar(),
        ],
      ),
    );
  }

  Widget _toolbar() {
    final searchField = ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 300),
      child: SizedBox(
        height: 50,
        child: TextField(
          key: const Key('member-search-input'),
          controller: _queryController,
          enabled: !_listLoading,
          onSubmitted: (_) => _search(),
          style: TextStyle(fontSize: 16, color: context.cashier.ink),
          decoration: InputDecoration(
            hintText: '输入手机号/会员姓名/卡号检索...',
            hintStyle: TextStyle(fontSize: 15, color: context.cashier.inkMuted),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide(color: context.cashier.border),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide(color: context.cashier.border),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide(color: context.cashier.selected),
            ),
            filled: true,
            fillColor: context.cashier.subtle,
            isDense: true,
            contentPadding: const EdgeInsets.symmetric(vertical: 12, horizontal: 14),
          ),
        ),
      ),
    );
    final searchButton = SizedBox(
      height: 50,
      child: ElevatedButton(
        key: const Key('member-search-button'),
        style: ElevatedButton.styleFrom(
          backgroundColor: context.cashier.surface,
          foregroundColor: context.cashier.ink,
          elevation: 0,
          side: BorderSide(color: context.cashier.border),
          padding: const EdgeInsets.symmetric(horizontal: 18),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
        onPressed: (_listLoading && _rows.isEmpty) ? null : _search,
        child: const Text('搜索', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
      ),
    );
    final couponButton = widget.permissions.contains('coupon:manage')
        ? SizedBox(
            height: 50,
            child: OutlinedButton(
              key: const Key('member-batch-coupon-button'),
              style: OutlinedButton.styleFrom(
                foregroundColor: context.cashier.ink,
                side: BorderSide(color: context.cashier.border),
                padding: const EdgeInsets.symmetric(horizontal: 16),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              onPressed: _batchSendCoupon,
              child: const Text('一键发券', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
            ),
          )
        : null;
    final rechargeButton = widget.canRecharge
        ? SizedBox(
            height: 50,
            child: OutlinedButton(
              key: const Key('member-recharge-button'),
              style: OutlinedButton.styleFrom(
                foregroundColor: context.cashier.ink,
                side: BorderSide(color: context.cashier.border),
                padding: const EdgeInsets.symmetric(horizontal: 16),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              onPressed: _rechargeByPhone,
              child: const Text('储值', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
            ),
          )
        : null;
    final logsButton = SizedBox(
      height: 50,
      child: OutlinedButton(
        key: const Key('member-recharge-logs-button'),
        style: OutlinedButton.styleFrom(
          foregroundColor: context.cashier.ink,
          side: BorderSide(color: context.cashier.border),
          padding: const EdgeInsets.symmetric(horizontal: 16),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
        onPressed: _openRechargeLogs,
        child: const Text('充值记录', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
      ),
    );
    final createButton = SizedBox(
      height: 50,
      child: ElevatedButton(
        key: const Key('member-create-button'),
        style: ElevatedButton.styleFrom(
          backgroundColor: context.cashier.btnPrimaryBg,
          foregroundColor: context.cashier.btnPrimaryInk,
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 20),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
        onPressed: _createMember,
        child: const Text('+快速注册新会员', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
      ),
    );
    return Container(
      height: 70,
      padding: const EdgeInsets.symmetric(horizontal: 18),
      decoration: BoxDecoration(
        color: context.cashier.surface,
        border: Border(bottom: BorderSide(color: context.cashier.border)),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          if (constraints.maxWidth >= 960) {
            return Row(
              children: [
                searchField,
                const SizedBox(width: 8),
                searchButton,
                const Spacer(),
                logsButton,
                if (couponButton != null) ...[
                  const SizedBox(width: 8),
                  couponButton,
                ],
                if (rechargeButton != null) ...[
                  const SizedBox(width: 8),
                  rechargeButton,
                ],
                const SizedBox(width: 8),
                createButton,
              ],
            );
          }
          return SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                searchField,
                const SizedBox(width: 8),
                searchButton,
                const SizedBox(width: 8),
                logsButton,
                if (couponButton != null) ...[
                  const SizedBox(width: 8),
                  couponButton,
                ],
                if (rechargeButton != null) ...[
                  const SizedBox(width: 8),
                  rechargeButton,
                ],
                const SizedBox(width: 8),
                createButton,
              ],
            ),
          );
        },
      ),
    );
  }

  static const _headerLabels = ['姓名', '手机号', '等级', '储值余额', '积分', '操作'];
  static const _headerFlex = [12, 11, 9, 9, 7, 7];

  Widget _memberTable() {
    if (_listLoading && _rows.isEmpty) {
      return const CashierStateView(
        state: CashierViewState.loading,
        title: '正在加载会员',
        message: '请稍候',
      );
    }
    if (_listError != null && _rows.isEmpty) {
      return CashierStateView(
        state: CashierViewState.error,
        title: _listError!,
        message: '请重试',
        actionLabel: '重试',
        onAction: _loadList,
      );
    }
    if (_rows.isEmpty) {
      return const CashierStateView(
        state: CashierViewState.empty,
        title: '暂无会员',
        message: '换个关键词搜索，或点击「+新增会员」',
      );
    }
    return Column(
      children: [
        _tableHeader(),
        Expanded(
          child: ListView.builder(
            itemCount: _rows.length,
            itemBuilder: (context, index) =>
                _memberRow(_rows[index], index),
          ),
        ),
        if (_listLoading)
          const LinearProgressIndicator(minHeight: 2),
      ],
    );
  }

  Widget _tableHeader() {
    return Container(
      height: 60,
      padding: const EdgeInsets.symmetric(horizontal: 20),
      decoration: BoxDecoration(
        color: context.cashier.subtle,
        border: Border(bottom: BorderSide(color: context.cashier.border)),
      ),
      child: Row(
        children: [
          for (var i = 0; i < _headerLabels.length; i++)
            Expanded(
              flex: _headerFlex[i],
              child: Text(
                _headerLabels[i],
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: context.cashier.inkSecondary,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _memberRow(CashierMemberRow row, int index) {
    final isSelected = _selectedMember?.id == row.id;
    return InkWell(
      key: Key('member-row-' + row.id.toString()),
      onTap: () => _selectMember(row),
      hoverColor: context.cashier.row,
      child: Container(
        height: 84,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        decoration: BoxDecoration(
          color: isSelected
              ? context.cashier.selectedBackground
              : Colors.transparent,
          border: Border(
            bottom: BorderSide(color: context.cashier.border),
            left: isSelected
                ? BorderSide(color: context.cashier.selected, width: 5)
                : BorderSide.none,
          ),
        ),
        child: Row(
          children: [
            Expanded(
              flex: 12,
              child: InkWell(
                onTap: () => _openDetail(row),
                borderRadius: BorderRadius.circular(6),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      row.name.trim().isEmpty ? '未命名会员' : row.name,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: context.cashier.ink,
                      ),
                    ),
                  ),
                ),
              ),
            ),
            Expanded(
              flex: 11,
              child: Text(
                maskedPhone(row.phone),
                style: TextStyle(
                  fontSize: 17,
                  fontFamily: 'monospace',
                  color: context.cashier.inkMuted,
                ),
              ),
            ),
            Expanded(
              flex: 9,
              child: Align(
                alignment: Alignment.centerLeft,
                child: _LevelBadge(level: row.level),
              ),
            ),
            Expanded(
              flex: 9,
              child: Text(
                _money(row.balance),
                style: TextStyle(
                  fontSize: 18,
                  fontFamily: 'monospace',
                  fontWeight: FontWeight.w800,
                  color: context.cashier.ink,
                ),
              ),
            ),
            Expanded(
              flex: 7,
              child: Text(
                _count(row.points),
                style: TextStyle(
                  fontSize: 17,
                  fontFamily: 'monospace',
                  color: context.cashier.inkMuted,
                ),
              ),
            ),
            Expanded(
              flex: 7,
              child: Align(
                alignment: Alignment.centerRight,
                child: OutlinedButton(
                  key: Key('member-row-detail-' + row.id.toString()),
                  onPressed: () => _openDetail(row),
                  style: OutlinedButton.styleFrom(
                    side: BorderSide(color: context.cashier.border),
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    minimumSize: const Size(66, 46),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  child: Text(
                    '详情',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: context.cashier.ink,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  int get _totalPages =>
      _total == 0 ? 1 : ((_total + _pageSize - 1) ~/ _pageSize);

  Widget _paginationBar() {
    return Container(
      height: 68,
      padding: const EdgeInsets.symmetric(horizontal: 20),
      decoration: BoxDecoration(
        color: context.cashier.surface,
        border: Border(top: BorderSide(color: context.cashier.border)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          Text(
            '\u5171 ' + _total.toString() + ' \u4f4d\u4f1a\u5458 \u00b7 \u7b2c ' + _page.toString() + '/' + _totalPages.toString() + ' \u9875',
            style: TextStyle(
              fontSize: 16,
              color: context.cashier.inkMuted,
            ),
          ),
          const SizedBox(width: 20),
          OutlinedButton(
            key: const Key('member-prev-page'),
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 18),
              minimumSize: const Size(92, 48),
              side: BorderSide(color: context.cashier.border),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            onPressed: _page > 1 && !_listLoading
                ? () => _goToPage(_page - 1)
                : null,
            child: const Text('上一页', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
          ),
          const SizedBox(width: 12),
          OutlinedButton(
            key: const Key('member-next-page'),
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 18),
              minimumSize: const Size(92, 48),
              side: BorderSide(color: context.cashier.border),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            onPressed: _page < _totalPages && !_listLoading
                ? () => _goToPage(_page + 1)
                : null,
            child: const Text('下一页', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }

  Widget _buildMemberPersonaPane() {
    if (_selectedMember == null) {
      return Container(
        decoration: BoxDecoration(
          color: context.cashier.surface,
          border: Border.all(color: context.cashier.border),
          borderRadius: BorderRadius.circular(8),
        ),
        padding: const EdgeInsets.all(28),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.person_outline, size: 64, color: context.cashier.inkMuted),
              const SizedBox(height: 16),
              Text(
                '请从左侧选择会员查看画像与操作',
                style: TextStyle(fontSize: 18, color: context.cashier.inkMuted),
              ),
            ],
          ),
        ),
      );
    }

    final m = _selectedMember!;
    final cleanPhone = m.phone.trim();
    final isUnmasked = _unmaskedMemberPhones.contains(cleanPhone);

    return Container(
      decoration: BoxDecoration(
        color: context.cashier.surface,
        border: Border.all(color: context.cashier.border),
        borderRadius: BorderRadius.circular(8),
      ),
      padding: const EdgeInsets.all(22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 1. Header: Name + Badge
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  m.name,
                  style: TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.w900,
                    color: context.cashier.ink,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              _LevelBadge(level: m.level),
            ],
          ),
          const SizedBox(height: 8),

          // 2. Phone row with unmask & copy
          Row(
            children: [
              Text(
                '手机: ' + (isUnmasked ? cleanPhone : maskedPhone(cleanPhone)),
                style: TextStyle(
                  fontSize: 16,
                  fontFamily: 'monospace',
                  color: context.cashier.inkMuted,
                ),
              ),
              const Spacer(),
              if (cleanPhone.isNotEmpty) ...[
                InkWell(
                  onTap: () => _togglePhoneMask(cleanPhone, m.name, m.id),
                  borderRadius: BorderRadius.circular(4),
                  child: Padding(
                    padding: const EdgeInsets.all(10),
                    child: Icon(
                      isUnmasked
                          ? Icons.visibility_outlined
                          : Icons.visibility_off_outlined,
                      size: 24,
                      color: isUnmasked
                          ? const Color(0xFF38BDF8)
                          : context.cashier.inkMuted,
                    ),
                  ),
                ),
                const SizedBox(width: 4),
                InkWell(
                  onTap: () => _copyPhone(cleanPhone, m.name, m.id),
                  borderRadius: BorderRadius.circular(4),
                  child: Padding(
                    padding: const EdgeInsets.all(10),
                    child: Icon(
                      Icons.copy_rounded,
                      size: 24,
                      color: context.cashier.inkMuted,
                    ),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 14),

          // 3. Balance & Points summary box
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: context.cashier.subtle,
              border: Border.all(color: context.cashier.border),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '储值可用余额',
                      style: TextStyle(
                        fontSize: 16,
                        color: context.cashier.inkSecondary,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      _money(m.balance),
                      style: TextStyle(
                        fontSize: 34,
                        fontWeight: FontWeight.w900,
                        fontFamily: 'monospace',
                        color: context.cashier.ink,
                      ),
                    ),
                  ],
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      '当前积分',
                      style: TextStyle(
                        fontSize: 16,
                        color: context.cashier.inkSecondary,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      _count(m.points),
                      style: TextStyle(
                        fontSize: 34,
                        fontWeight: FontWeight.w900,
                        fontFamily: 'monospace',
                        color: context.cashier.ink,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),

          // 4. Quick Action Buttons
          Row(
            children: [
              Expanded(
                child: SizedBox(
                  height: 50,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: context.cashier.btnPrimaryBg,
                      foregroundColor: context.cashier.btnPrimaryInk,
                      elevation: 0,
                      padding: EdgeInsets.zero,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    onPressed: () => _rechargeMemberRow(m),
                    child: const Text(
                      '充值赠金',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: SizedBox(
                  height: 50,
                  child: OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: context.cashier.ink,
                      side: BorderSide(color: context.cashier.border),
                      padding: EdgeInsets.zero,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    onPressed: _batchSendCoupon,
                    child: const Text(
                      '一键发券',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                height: 50,
                child: OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: context.cashier.ink,
                    side: BorderSide(color: context.cashier.border),
                    padding: const EdgeInsets.symmetric(horizontal: 18),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  onPressed: () => _openDetail(m),
                  child: const Text(
                    '详情',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // 5. Recent consumption history
          Text(
            '近期消费历史',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w800,
              color: context.cashier.inkSecondary,
            ),
          ),
          const SizedBox(height: 10),
          Expanded(
            child: _personaLoading
                ? Center(
                    child: CircularProgressIndicator(
                      color: context.cashier.selected,
                      strokeWidth: 2,
                    ),
                  )
                : _personaConsumption.isEmpty
                    ? Container(
                        alignment: Alignment.center,
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: context.cashier.subtle,
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: context.cashier.border),
                        ),
                        child: Text(
                          '暂无近期消费记录',
                          style: TextStyle(
                            fontSize: 14,
                            color: context.cashier.inkMuted,
                          ),
                        ),
                      )
                    : ListView.separated(
                        itemCount: _personaConsumption.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 8),
                        itemBuilder: (context, index) {
                          final record = _personaConsumption[index];
                          final pts = (record.amount / 10).floor();
                          return InkWell(
                            onTap: () => _openConsumptionDetailDialog(record),
                            borderRadius: BorderRadius.circular(6),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 14,
                              ),
                              decoration: BoxDecoration(
                                color: context.cashier.subtle,
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(color: context.cashier.border),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    '\u2022 ' + (record.paidAt.length >= 10 ? record.paidAt.substring(0, 10) : record.paidAt) + ' \u00b7 \u6d88\u8d39 \u00a5' + record.amount.toStringAsFixed(2),
                                    style: TextStyle(
                                      fontSize: 15,
                                      color: context.cashier.inkMuted,
                                      fontFamily: 'monospace',
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    '\u79ef\u5206 +' + pts.toString() + ' \u00b7 ' + (record.paymentMethod.isNotEmpty ? record.paymentMethod : '\u672a\u77e5'),
                                    style: const TextStyle(
                                      fontSize: 14,
                                      color: Color(0xFF22C55E),
                                      fontWeight: FontWeight.w600,
                                    ),
                                  )
                                ],
                              ),
                            ),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }

  // ---------- 充值记录查询视图 ----------

  Widget _rechargeLogsView() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _logsHeader(),
        const SizedBox(height: 12),
        _logsFilter(),
        const SizedBox(height: 12),
        Expanded(child: _logsTable()),
        const SizedBox(height: 8),
        _logsPagination(),
      ],
    );
  }

  Widget _logsHeader() {
    return Row(
      children: [
        OutlinedButton(
          key: const Key('recharge-logs-back-button'),
          onPressed: _backFromLogs,
          child: const Text('← 返回'),
        ),
        const SizedBox(width: 16),
        const Text(
          '充值记录',
          style: TextStyle(fontSize: 28, fontWeight: FontWeight.w700),
        ),
        const SizedBox(width: 12),
        Text(
          '输入手机号单查某会员；留空并选择时间范围可查全部充值',
          style: TextStyle(fontSize: 14, color: context.cashier.inkMuted),
        ),
      ],
    );
  }

  Widget _logsFilter() {
    Widget dateChip(String label, DateTime? value, VoidCallback onTap) {
      final text = value == null ? '未选择' : _date('${value.year.toString().padLeft(4, '0')}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}');
      return OutlinedButton.icon(
        onPressed: _logLoading ? null : onTap,
        icon: const Icon(Icons.calendar_today, size: 16),
        label: Text('$label：$text'),
      );
    }

    return CashierCard(
      padding: const EdgeInsets.all(16),
      child: Wrap(
        spacing: 12,
        runSpacing: 12,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          SizedBox(
            width: 220,
            height: 48,
            child: TextField(
              key: const Key('recharge-logs-phone-input'),
              controller: _logPhoneController,
              enabled: !_logLoading,
              keyboardType: TextInputType.phone,
              maxLength: 11,
              onSubmitted: (_) => _searchRechargeLogs(),
              decoration: const InputDecoration(
                hintText: '会员手机号（可空）',
                counterText: '',
                border: OutlineInputBorder(),
                isDense: true,
                contentPadding: EdgeInsets.symmetric(vertical: 12, horizontal: 12),
              ),
            ),
          ),
          dateChip('开始', _logStart, () => _pickLogDate(isStart: true)),
          dateChip('结束', _logEnd, () => _pickLogDate(isStart: false)),
          CashierActionButton(
            key: const Key('recharge-logs-search-button'),
            label: '查询',
            onPressed: _searchRechargeLogs,
            busy: _logLoading && !_logLoaded,
            minimumWidth: 120,
            height: 48,
          ),
          TextButton(
            onPressed: _logLoading
                ? null
                : () {
                    setState(() {
                      _logPhoneController.clear();
                      _logStart = null;
                      _logEnd = null;
                      _logPage = 1;
                    });
                    _loadRechargeLogs();
                  },
            child: const Text('重置'),
          ),
        ],
      ),
    );
  }

  static const _logHeaderLabels = [
    '时间',
    '会员',
    '手机号',
    '充值本金',
    '赠送金额',
    '到账合计',
    '渠道',
  ];
  static const _logHeaderFlex = [13, 10, 11, 9, 9, 9, 8];

  Widget _logsTable() {
    if (_logLoading && !_logLoaded) {
      return const CashierCard(
        child: CashierStateView(
          state: CashierViewState.loading,
          title: '正在加载充值记录',
          message: '请稍候',
        ),
      );
    }
    if (_logError != null && !_logLoaded) {
      return CashierCard(
        child: CashierStateView(
          state: CashierViewState.error,
          title: _logError!,
          message: '请重试',
          actionLabel: '重试',
          onAction: _loadRechargeLogs,
        ),
      );
    }
    if (!_logLoaded || _logRows.isEmpty) {
      return const CashierCard(
        child: CashierStateView(
          state: CashierViewState.empty,
          title: '暂无充值记录',
          message: '输入手机号或选择时间范围后点击「查询」',
        ),
      );
    }
    return CashierCard(
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          _logTableHeader(),
          const Divider(height: 1),
          Expanded(
            child: ListView.separated(
              itemCount: _logRows.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (context, index) => _logRow(_logRows[index], index),
            ),
          ),
          if (_logLoading) const LinearProgressIndicator(minHeight: 2),
        ],
      ),
    );
  }

  Widget _logTableHeader() {
    return Container(
      height: 48,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      color: context.cashier.row,
      child: Row(
        children: [
          for (var i = 0; i < _logHeaderLabels.length; i++)
            Expanded(
              flex: _logHeaderFlex[i],
              child: Text(
                _logHeaderLabels[i],
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: context.cashier.inkMuted,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _logRow(RechargeLogRow row, int index) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      color: index.isEven ? context.cashier.row : Colors.transparent,
      child: Row(
        children: [
          Expanded(
            flex: _logHeaderFlex[0],
            child: Text(
              row.payTime,
              style: const TextStyle(fontSize: 14),
            ),
          ),
          Expanded(
            flex: _logHeaderFlex[1],
            child: Text(
              row.name.isEmpty ? '—' : row.name,
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Expanded(
            flex: _logHeaderFlex[2],
            child: Text(
              row.phone.isEmpty ? '—' : maskedPhone(row.phone),
              style: const TextStyle(fontSize: 14),
            ),
          ),
          Expanded(
            flex: _logHeaderFlex[3],
            child: Text(_money(row.rechargeAmount), style: const TextStyle(fontSize: 14)),
          ),
          Expanded(
            flex: _logHeaderFlex[4],
            child: Text(_money(row.giftAmount), style: const TextStyle(fontSize: 14)),
          ),
          Expanded(
            flex: _logHeaderFlex[5],
            child: Text(
              _money(row.totalAmount),
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
            ),
          ),
          Expanded(
            flex: _logHeaderFlex[6],
            child: Text(_channelLabel(row.channel), style: const TextStyle(fontSize: 14)),
          ),
        ],
      ),
    );
  }

  String _channelLabel(String channel) {
    switch (channel) {
      case 'wechat':
        return '微信支付';
      case 'admin':
        return '后台充值';
      default:
        return channel.isEmpty ? '—' : channel;
    }
  }

  int get _logTotalPages =>
      _logTotal == 0 ? 1 : ((_logTotal + _logPageSize - 1) ~/ _logPageSize);

  Widget _logsPagination() {
    if (!_logLoaded) return const SizedBox.shrink();
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        Text(
          '共 $_logTotal 条充值记录 · 第 $_logPage/$_logTotalPages 页',
          style: TextStyle(fontSize: 14, color: context.cashier.inkMuted),
        ),
        const SizedBox(width: 12),
        OutlinedButton(
          key: const Key('recharge-logs-prev'),
          onPressed: _logPage > 1 && !_logLoading
              ? () => _goLogPage(_logPage - 1)
              : null,
          child: const Text('上一页'),
        ),
        const SizedBox(width: 8),
        OutlinedButton(
          key: const Key('recharge-logs-next'),
          onPressed: _logPage < _logTotalPages && !_logLoading
              ? () => _goLogPage(_logPage + 1)
              : null,
          child: const Text('下一页'),
        ),
      ],
    );
  }

  // ---------- 图2 会员详情页 ----------

  Widget _detailView() {
    final Widget body;
    if (_detailLoading && _profile == null) {
      body = const CashierCard(
        child: CashierStateView(
          state: CashierViewState.loading,
          title: '正在加载会员详情',
          message: '请稍候',
        ),
      );
    } else if (_detailError != null && _profile == null) {
      body = CashierCard(
        child: CashierStateView(
          state: CashierViewState.error,
          title: _detailError!,
          message: '请重试',
          actionLabel: '重试',
          onAction: () => _loadDetail(_detailPhone ?? ''),
        ),
      );
    } else {
      final profile = _profile;
      body = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 4),
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (profile != null) ...[
                    _profileBanner(profile),
                    const SizedBox(height: 12),
                    _metricRow(profile),
                    const SizedBox(height: 16),
                    _memberStatsCard(profile),
                  ],
                  const SizedBox(height: 16),
                  _consumptionCard(),
                  const SizedBox(height: 16),
                  _rechargeCard(),
                ],
              ),
            ),
          ),
        ],
      );
    }
    // 顶部栏（含返回按钮）在加载/失败/正常三种状态始终渲染，避免服务器
    // 处理失败或长时间无响应时页面卡住且无法返回列表。
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _detailHeader(_profile),
        const SizedBox(height: 12),
        Expanded(child: body),
      ],
    );
  }

  Widget _detailHeader(CashierMemberProfile? profile) {
    final member = profile?.member;
    return Row(
      children: [
        OutlinedButton(
          key: const Key('member-back-button'),
          onPressed: _backToList,
          child: const Text('← 返回'),
        ),
        const SizedBox(width: 16),
        const Text(
          '会员详情',
          style: TextStyle(fontSize: 28, fontWeight: FontWeight.w700),
        ),
        const SizedBox(width: 16),
        if (member != null)
          Text(
            '会员编号 VIP-${member.id}',
            key: const Key('member-detail-code'),
            style: TextStyle(
              fontSize: 15,
              color: context.cashier.inkMuted,
            ),
          ),
        const Spacer(),
        if (widget.canBindOrder &&
            _hasUnsettledOrder &&
            member != null &&
            member.hasOpenid) ...[
          CashierActionButton(
            label: '绑定当前订单',
            onPressed: _bind,
            minimumWidth: 180,
            height: 48,
          ),
          const SizedBox(width: 12),
        ],
        if (widget.canRecharge && member != null && member.hasOpenid) ...[
          CashierActionButton(
            label: '储值',
            onPressed: _recharge,
            minimumWidth: 120,
            height: 48,
          ),
        ],
      ],
    );
  }

  /// 档案横幅：头像 + 姓名/等级徽章 + 手机号 + 绑定状态（详情页主身份区）
  Widget _profileBanner(CashierMemberProfile profile) {
    final member = profile.member;
    return CashierCard(
      key: const Key('member-info-card'),
      padding: const EdgeInsets.all(24),
      child: Row(
        children: [
          _AvatarBadge(name: member.name, size: 72, fontSize: 28),
          const SizedBox(width: 20),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        member.name,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 26,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    _LevelBadge(level: member.level),
                  ],
                ),
                const SizedBox(height: 6),
                Builder(
                  builder: (context) {
                    final cleanPhone = member.phone.trim();
                    final isUnmasked =
                        _unmaskedMemberPhones.contains(cleanPhone);
                    return Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          isUnmasked ? cleanPhone : maskedPhone(cleanPhone),
                          key: const Key('member-detail-phone-text'),
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight:
                                isUnmasked ? FontWeight.w700 : FontWeight.w500,
                            letterSpacing: 0.5,
                            color: isUnmasked
                                ? const Color(0xFF38BDF8)
                                : context.cashier.inkMuted,
                          ),
                        ),
                        if (cleanPhone.isNotEmpty) ...[
                          const SizedBox(width: 6),
                          Tooltip(
                            message: isUnmasked
                                ? '隐藏完整手机号'
                                : '查看完整手机号 (需权限)',
                            child: InkWell(
                              key: const Key(
                                'member-detail-toggle-phone-mask-btn',
                              ),
                              borderRadius: BorderRadius.circular(6),
                              onTap: () => _togglePhoneMask(
                                cleanPhone,
                                member.name,
                                member.id,
                              ),
                              child: Padding(
                                padding: const EdgeInsets.all(8),
                                child: Icon(
                                  isUnmasked
                                      ? Icons.visibility_outlined
                                      : Icons.visibility_off_outlined,
                                  size: 18,
                                  color: isUnmasked
                                      ? const Color(0xFF38BDF8)
                                      : context.cashier.inkMuted,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 4),
                          Tooltip(
                            message: '复制手机号',
                            child: InkWell(
                              key: const Key('member-detail-copy-phone-btn'),
                              borderRadius: BorderRadius.circular(6),
                              onTap: () => _copyPhone(
                                cleanPhone,
                                member.name,
                                member.id,
                              ),
                              child: Padding(
                                padding: const EdgeInsets.all(8),
                                child: Icon(
                                  Icons.copy_rounded,
                                  size: 18,
                                  color: isUnmasked
                                      ? const Color(0xFF38BDF8)
                                      : context.cashier.inkMuted,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ],
                    );
                  },
                ),
                if (!member.hasOpenid) ...[
                  const SizedBox(height: 12),
                  const CashierStatusBadge(
                    label: '该会员尚未完成账户绑定',
                    variant: CashierStatusBadgeVariant.warning,
                  ),
                ],
              ],
            ),
          ),
          if (member.hasOpenid)
            const CashierStatusBadge(
              label: '已绑定账户',
              variant: CashierStatusBadgeVariant.success,
            ),
        ],
      ),
    );
  }

  /// 详情指标行：储值余额 / 可用积分 / 等级权益（≥1100 并排，窄屏纵向）
  Widget _metricRow(CashierMemberProfile profile) {
    final member = profile.member;
    final cards = [
      _metricCard(
        key: const Key('member-level-card'),
        label: '储值余额',
        value: _money(member.balance),
        note: '可用余额',
      ),
      _metricCard(
        key: const Key('member-points-card'),
        label: '可用积分',
        value: '${_count(member.points)}分',
        note: '本月新增 —',
      ),
      _metricCard(
        label: '等级权益',
        value: memberLevelLabel(member.level),
        note: '折扣 —',
      ),
    ];
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth >= 1100) {
          return Row(
            children: [
              for (var i = 0; i < cards.length; i++) ...[
                if (i > 0) const SizedBox(width: 12),
                Expanded(child: cards[i]),
              ],
            ],
          );
        }
        return Column(
          children: [
            for (var i = 0; i < cards.length; i++) ...[
              if (i > 0) const SizedBox(height: 12),
              cards[i],
            ],
          ],
        );
      },
    );
  }

  Widget _metricCard({
    Key? key,
    required String label,
    required String value,
    required String note,
  }) {
    return CashierCard(
      key: key,
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 14,
              color: context.cashier.inkMuted,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            value,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 4),
          Text(
            note,
            style: TextStyle(
              fontSize: 13,
              color: context.cashier.inkMuted,
            ),
          ),
        ],
      ),
    );
  }

  Widget _memberStatsCard(CashierMemberProfile profile) {
    // D023 统计字段：后端画像接口后期补齐，null 时展示占位 '—'
    final consume = profile.consumeAmount;
    final lastTime = profile.lastConsumeTime;
    final invites = profile.inviteRegisteredCount;
    final coupons = profile.availableCouponCount;
    return CashierCard(
      key: const Key('member-stats-card'),
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '消费统计',
            style: TextStyle(fontSize: 16, color: context.cashier.inkMuted),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _statItem(
                  '累计消费',
                  consume == null ? '—' : _money(consume),
                  icon: Icons.account_balance_wallet_outlined,
                ),
              ),
              Expanded(
                child: _statItem(
                  '最近消费',
                  lastTime == null ? '—' : _date(lastTime),
                  icon: Icons.schedule_rounded,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _statItem(
                  '邀请注册',
                  invites == null ? '—' : _count(invites),
                  icon: Icons.group_add_outlined,
                ),
              ),
              Expanded(
                child: _statItem(
                  '可用券',
                  coupons == null ? '—' : _count(coupons),
                  icon: Icons.confirmation_number_outlined,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _statItem(
    String label,
    String value, {
    required IconData icon,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: context.cashier.canvas,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: context.cashier.selectedBackground,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, size: 18, color: context.cashier.selected),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 12,
                    color: context.cashier.inkMuted,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _consumptionCard() {
    return CashierCard(
      key: const Key('member-consumption-card'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '消费记录',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 4),
          Text(
            '积分变动按实付金额 1:1 反积分（四舍五入）；余额变动仅在储值/余额支付时扣减，其余显示 —',
            style: TextStyle(fontSize: 13, color: context.cashier.inkMuted),
          ),
          const SizedBox(height: 12),
          const _RecordTableHeader(
            columns: ['时间', '金额', '支付方式', '积分变动', '余额变动'],
            flexes: [11, 8, 8, 7, 9],
          ),
          const Divider(height: 1),
          if (_consumption.isEmpty)
            const Padding(
              padding: EdgeInsets.all(24),
              child: Center(child: Text('暂无消费记录')),
            )
          else
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 340),
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: _consumption.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (context, index) {
                  final item = _consumption[index];
                  return _RecordRow(
                    cells: [
                      _date(item.paidAt),
                      _money(item.amount),
                      item.paymentMethod.isEmpty ? '—' : item.paymentMethod,
                      item.amount > 0 ? '+${item.amount.round()}' : '—',
                      _isBalancePayment(item.paymentMethod)
                          ? '-${_money(item.amount)}'
                          : '—',
                    ],
                  );
                },
              ),
            ),
        ],
      ),
    );
  }

  Widget _rechargeCard() {
    final member = _profile?.member;
    return CashierCard(
      key: const Key('member-recharge-card'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '充值记录',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 4),
          Text(
            '当前余额为会员最新余额，仅首行展示',
            style: TextStyle(fontSize: 13, color: context.cashier.inkMuted),
          ),
          const SizedBox(height: 12),
          const _RecordTableHeader(
            columns: ['时间', '充值金额', '到账金额', '当前余额'],
            flexes: [11, 8, 8, 8],
          ),
          const Divider(height: 1),
          if (_recharges.isEmpty)
            const Padding(
              padding: EdgeInsets.all(24),
              child: Center(child: Text('暂无充值记录')),
            )
          else
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 340),
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: _recharges.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (context, index) {
                  final item = _recharges[index];
                  return _RecordRow(
                    cells: [
                      _date(item.createdAt),
                      _money(item.principalAmount),
                      _money(item.totalAmount),
                      index == 0 && member != null
                          ? _money(member.balance)
                          : '—',
                    ],
                  );
                },
              ),
            ),
        ],
      ),
    );
  }

  bool _isBalancePayment(String method) {
    final text = method.toLowerCase();
    return method.contains('余额') ||
        method.contains('储值') ||
        text.contains('balance') ||
        method.contains('会员卡');
  }
}

/// 头像圆标：取姓名首字符，深蓝底白字。
class _AvatarBadge extends StatelessWidget {
  const _AvatarBadge({required this.name, this.size = 34, this.fontSize = 14});

  final String name;
  final double size;
  final double fontSize;

  @override
  Widget build(BuildContext context) {
    final initial = name.trim().isEmpty ? '?' : name.trim().characters.first;
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: context.cashier.selected,
        shape: BoxShape.circle,
      ),
      child: Text(
        initial,
        style: TextStyle(
          color: Colors.white,
          fontSize: fontSize,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

/// 等级徽章：0=普通(灰) 1=白银(蓝) 2=黄金(金) 3=铂金(绿)，未知为「—」。
class _LevelBadge extends StatelessWidget {
  const _LevelBadge({required this.level});

  final int? level;

  @override
  Widget build(BuildContext context) {
    final (Color bg, Color border, Color fg, String label) = switch (level) {
      0 => (
          context.cashier.subtle,
          context.cashier.border,
          context.cashier.inkMuted,
          '普通会员'
        ),
      1 => (
          const Color(0x1a3b82f6),
          const Color(0x4d3b82f6),
          const Color(0xff60a5fa),
          '白银会员'
        ),
      2 => (
          const Color(0x1af59e0b),
          const Color(0x4df59e0b),
          const Color(0xfffbbf24),
          '黄金会员'
        ),
      3 => (
          const Color(0x1a10b981),
          const Color(0x4d10b981),
          const Color(0xff34d399),
          '铂金会员'
        ),
      _ => (
          context.cashier.subtle,
          context.cashier.border,
          context.cashier.inkMuted,
          '—'
        ),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: border, width: 1),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w700,
          color: fg,
          height: 1.1,
        ),
      ),
    );
  }
}

class _RecordTableHeader extends StatelessWidget {
  const _RecordTableHeader({required this.columns, required this.flexes});

  final List<String> columns;
  final List<int> flexes;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 48,
      color: context.cashier.row,
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Row(
        children: [
          for (var i = 0; i < columns.length; i++)
            Expanded(
              flex: flexes[i],
              child: Text(
                columns[i],
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: context.cashier.inkMuted,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _RecordRow extends StatelessWidget {
  const _RecordRow({required this.cells});

  final List<String> cells;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 10),
      child: Row(
        children: [
          for (var i = 0; i < cells.length; i++)
            Expanded(
              flex: _recordFlex(i, cells.length),
              child: Text(
                cells[i],
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 14),
              ),
            ),
        ],
      ),
    );
  }

  int _recordFlex(int index, int length) {
    const tableFlex = [
      [11, 8, 8, 7, 9],
      [11, 8, 8, 8],
    ];
    if (length >= tableFlex[0].length) return tableFlex[0][index];
    return tableFlex[1][index];
  }
}

class _BindOrderDialog extends StatefulWidget {
  const _BindOrderDialog({
    required this.repository,
    required this.member,
    required this.orderId,
    required this.orderNo,
    required this.tableNumber,
  });
  final CashierMemberRepository repository;
  final CashierMember member;
  final int orderId;
  final String orderNo;
  final String tableNumber;

  @override
  State<_BindOrderDialog> createState() => _BindOrderDialogState();
}

class _BindOrderDialogState extends State<_BindOrderDialog> {
  bool _busy = false;
  String? _error;

  Future<void> _submit() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.repository.bindOrder(
        orderId: widget.orderId,
        phone: widget.member.phone,
      );
      if (mounted) Navigator.pop(context, true);
    } catch (error) {
      if (mounted)
        setState(() {
          _busy = false;
          _error = _message(error);
        });
    }
  }

  @override
  Widget build(BuildContext context) => CashierDialogFrame(
    title: '确认绑定当前订单',
    height: 480,
    busy: _busy,
    onClose: () => Navigator.pop(context, false),
    body: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _DetailRow('会员姓名', widget.member.name),
        _DetailRow('手机号', widget.member.phone),
        _DetailRow('订单号', widget.orderNo),
        _DetailRow('桌号', widget.tableNumber),
        const _DetailRow('订单状态', '未结账'),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Text(
              _error!,
              style: TextStyle(color: context.cashier.danger),
            ),
          ),
      ],
    ),
    actions: [
      CashierActionButton(
        label: '取消',
        onPressed: _busy ? null : () => Navigator.pop(context, false),
        variant: CashierActionButtonVariant.secondary,
        minimumWidth: 120,
        height: 56,
      ),
      CashierActionButton(
        label: '确认绑定',
        onPressed: _submit,
        busy: _busy,
        minimumWidth: 150,
        height: 56,
      ),
    ],
  );
}

class _RechargeDialog extends StatefulWidget {
  const _RechargeDialog({required this.repository, required this.member});
  final CashierMemberRepository repository;
  final CashierMember member;

  @override
  State<_RechargeDialog> createState() => _RechargeDialogState();
}

class _RechargeDialogState extends State<_RechargeDialog> {
  final _amount = TextEditingController();
  final _gift = TextEditingController(text: '0');
  bool _busy = false;
  bool _success = false;
  String? _error;
  double? _newBalance;

  double get _principal => double.tryParse(_amount.text) ?? 0;
  double get _giftAmount => double.tryParse(_gift.text) ?? 0;
  bool get _valid => _principal >= 50 && _giftAmount >= 0;

  @override
  void dispose() {
    _amount.dispose();
    _gift.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy || !_valid) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final result = await widget.repository.recharge(
        phone: widget.member.phone,
        amount: _principal,
        giftAmount: _giftAmount,
      );
      if (!mounted) return;
      setState(() {
        _busy = false;
        _success = true;
        _newBalance = result.newBalance;
      });
    } catch (error) {
      if (mounted)
        setState(() {
          _busy = false;
          _error = _message(error);
        });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_success) {
      return CashierDialogFrame(
        title: '充值成功',
        width: 820,
        height: 650,
      body: Column(
  

          children: [
            Icon(
              Icons.check_circle,
              size: 88,
              color: context.cashier.success,
            ),
            const SizedBox(height: 20),
            _DetailRow('充值本金', _money(_principal)),
            _DetailRow('赠送金额', _money(_giftAmount)),
            _DetailRow('到账合计', _money(_principal + _giftAmount)),
            if (_newBalance != null) _DetailRow('最新余额', _money(_newBalance!)),
          ],
        ),
        actions: [
          CashierActionButton(
            label: '完成',
            onPressed: () => Navigator.pop(context, true),
          ),
        ],
      );
    }
    return CashierDialogFrame(
      title: '会员充值',
      width: 820,
      height: 650,
      busy: _busy,
      onClose: () => Navigator.pop(context, false),
      body: Column(


        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            '${widget.member.name}  ${widget.member.phone}',
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
          ),
          Text(
            '当前余额 ${_money(widget.member.balance)}',
            style: TextStyle(
              fontSize: 18,
              color: context.cashier.inkMuted,
            ),
          ),
          const SizedBox(height: 20),
          TextField(
            key: const Key('member-recharge-amount'),
            controller: _amount,
            enabled: !_busy,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              labelText: '充值本金',
              errorText: _amount.text.isNotEmpty && _principal < 50
                  ? '充值本金不得低于 ¥50.00'
                  : null,
              border: const OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 12,
            children: [
              for (final value in const [50, 100, 200, 500])
                ActionChip(
                  label: Text('¥$value'),
                  onPressed: _busy
                      ? null
                      : () {
                          _amount.text = '$value';
                          setState(() {});
                        },
                ),
            ],
          ),
          const SizedBox(height: 16),
          TextField(
            key: const Key('member-recharge-gift'),
            controller: _gift,
            enabled: !_busy,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              labelText: '赠送金额',
              errorText: _giftAmount < 0 ? '赠送金额不得小于 0' : null,
              border: const OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 20),
          _DetailRow('本金', _money(_principal)),
          _DetailRow('赠送', _money(_giftAmount)),
          _DetailRow('到账合计', _money(_principal + _giftAmount)),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(
                _error!,
                style: TextStyle(color: context.cashier.danger),
              ),
            ),
        ],
      ),
      actions: [
        CashierActionButton(
          label: '取消',
          onPressed: _busy ? null : () => Navigator.pop(context, false),
          variant: CashierActionButtonVariant.secondary,
          minimumWidth: 120,
          height: 56,
        ),
        CashierActionButton(
          label: '确认充值',
          onPressed: _valid ? _submit : null,
          busy: _busy,
          minimumWidth: 150,
          height: 56,
        ),
      ],
    );
  }
}

/// 工具栏「储值」弹窗：先按手机号解析会员（真实画像），再充值。
class _RechargeByPhoneDialog extends StatefulWidget {
  const _RechargeByPhoneDialog({required this.repository, this.initialPhone});

  final CashierMemberRepository repository;
  final String? initialPhone;

  @override
  State<_RechargeByPhoneDialog> createState() => _RechargeByPhoneDialogState();
}

class _RechargeByPhoneDialogState extends State<_RechargeByPhoneDialog> {
  final _phone = TextEditingController();
  final _amount = TextEditingController();
  final _gift = TextEditingController(text: '0');
  bool _busy = false;
  bool _loadingMember = false;
  String? _phoneError;
  String? _error;
  bool _success = false;
  double? _newBalance;
  CashierMemberProfile? _profile;

  @override
  void initState() {
    super.initState();
    if (widget.initialPhone != null && widget.initialPhone!.isNotEmpty) {
      _phone.text = widget.initialPhone!;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _resolveMember();
      });
    }
  }

  double get _principal => double.tryParse(_amount.text) ?? 0;
  double get _giftAmount => double.tryParse(_gift.text) ?? 0;
  bool get _valid => _profile != null && _principal >= 50 && _giftAmount >= 0;

  @override
  void dispose() {
    _phone.dispose();
    _amount.dispose();
    _gift.dispose();
    super.dispose();
  }

  Future<void> _resolveMember() async {
    final phone = _phone.text.trim();
    if (!RegExp(r'^1\d{10}$').hasMatch(phone)) {
      setState(() => _phoneError = '请输入 11 位有效手机号');
      return;
    }
    setState(() {
      _loadingMember = true;
      _phoneError = null;
      _error = null;
    });
    try {
      final profile = await widget.repository.loadProfile(phone);
      if (!mounted) return;
      setState(() {
        _profile = profile;
        _loadingMember = false;
      });
    } on MemberNotFoundException {
      if (!mounted) return;
      setState(() {
        _profile = null;
        _loadingMember = false;
        _phoneError = '未找到该手机号对应的会员';
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _profile = null;
        _loadingMember = false;
        _error = _message(error);
      });
    }
  }

  Future<void> _submit() async {
    final profile = _profile;
    if (_busy || !_valid || profile == null) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final result = await widget.repository.recharge(
        phone: profile.member.phone,
        amount: _principal,
        giftAmount: _giftAmount,
      );
      if (!mounted) return;
      setState(() {
        _busy = false;
        _success = true;
        _newBalance = result.newBalance;
      });
    } catch (error) {
      if (mounted)
        setState(() {
          _busy = false;
          _error = _message(error);
        });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_success) {
      final member = _profile!.member;
      return CashierDialogFrame(
        title: '充值成功',
        width: 820,
        height: 650,
      body: Column(
  

          children: [
            Icon(
              Icons.check_circle,
              size: 88,
              color: context.cashier.success,
            ),
            const SizedBox(height: 20),
            _DetailRow('会员', '${member.name}  ${member.phone}'),
            _DetailRow('充值本金', _money(_principal)),
            _DetailRow('赠送金额', _money(_giftAmount)),
            _DetailRow('到账合计', _money(_principal + _giftAmount)),
            if (_newBalance != null) _DetailRow('最新余额', _money(_newBalance!)),
          ],
        ),
        actions: [
          CashierActionButton(
            label: '完成',
            onPressed: () => Navigator.pop(context, true),
          ),
        ],
      );
    }
    return CashierDialogFrame(
      title: '会员储值',
      width: 820,
      height: 680,
      busy: _busy,
      onClose: () => Navigator.pop(context, false),
      body: Column(


        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            key: const Key('recharge-phone-input'),
            controller: _phone,
            enabled: !_busy && !_loadingMember,
            keyboardType: TextInputType.phone,
            maxLength: 11,
            onSubmitted: (_) => _resolveMember(),
            decoration: InputDecoration(
              labelText: '会员手机号',
              hintText: '输入手机号查询会员',
              counterText: '',
              errorText: _phoneError,
              suffixIcon: _loadingMember
                  ? const Padding(
                      padding: EdgeInsets.all(12),
                      child: SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    )


                  : IconButton(
                      icon: const Icon(Icons.search),
                      onPressed: _resolveMember,
                      key: const Key('recharge-phone-resolve'),
                    ),
              border: const OutlineInputBorder(),
            ),
          ),
          if (_profile != null) ...[
            const SizedBox(height: 12),
            Text(
              '${_profile!.member.name}  ${maskedPhone(_profile!.member.phone)}',
              style: const TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w700,
              ),
            ),
            Text(
              '当前余额 ${_money(_profile!.member.balance)}',
              style: TextStyle(
                fontSize: 18,
                color: context.cashier.inkMuted,
              ),
            ),
          ],
          const SizedBox(height: 20),
          TextField(
            key: const Key('recharge-amount-input'),
            controller: _amount,
            enabled: !_busy && _profile != null,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              labelText: '充值本金',
              errorText: _amount.text.isNotEmpty && _principal < 50
                  ? '充值本金不得低于 ¥50.00'
                  : null,
              border: const OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 12,
            children: [
              for (final value in const [50, 100, 200, 500])
                ActionChip(
                  label: Text('¥$value'),
                  onPressed: _busy || _profile == null
                      ? null
                      : () {
                          _amount.text = '$value';
                          setState(() {});
                        },
                ),
            ],
          ),
          const SizedBox(height: 16),
          TextField(
            key: const Key('recharge-gift-input'),
            controller: _gift,
            enabled: !_busy && _profile != null,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              labelText: '赠送金额',
              errorText: _giftAmount < 0 ? '赠送金额不得小于 0' : null,
              border: const OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 20),
          _DetailRow('本金', _money(_principal)),
          _DetailRow('赠送', _money(_giftAmount)),
          _DetailRow('到账合计', _money(_principal + _giftAmount)),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(
                _error!,
                style: TextStyle(color: context.cashier.danger),
              ),
            ),
        ],
      ),
      actions: [
        CashierActionButton(
          label: '取消',
          onPressed: _busy ? null : () => Navigator.pop(context, false),
          variant: CashierActionButtonVariant.secondary,
          minimumWidth: 120,
          height: 56,
        ),
        CashierActionButton(
          label: '确认充值',
          onPressed: _valid ? _submit : null,
          busy: _busy,
          minimumWidth: 150,
          height: 56,
        ),
      ],
    );
  }
}

/// 一键发券弹窗：选券（真实券模板）→ 批量发放。
class _CouponSendDialog extends StatefulWidget {
  const _CouponSendDialog({required this.repository});

  final CashierMemberRepository repository;

  @override
  State<_CouponSendDialog> createState() => _CouponSendDialogState();
}

class _CouponSendDialogState extends State<_CouponSendDialog> {
  List<CashierCoupon> _coupons = const [];
  bool _loading = true;
  bool _busy = false;
  bool _done = false;
  String? _loadError;
  String? _error;
  int _granted = 0;
  int? _selectedId;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _loadError = null;
    });
    try {
      final coupons = await widget.repository.loadCoupons();
      final usable = coupons.where((c) => c.isUsable).toList(growable: false);
      if (!mounted) return;
      setState(() {
        _coupons = usable;
        _loading = false;
        if (_selectedId == null && usable.isNotEmpty) {
          _selectedId = usable.first.id;
        }
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _loadError = _message(error);
      });
    }
  }

  Future<void> _send() async {
    final id = _selectedId;
    if (id == null || _busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final granted = await widget.repository.batchSendCoupon(couponId: id);
      if (!mounted) return;
      setState(() {
        _busy = false;
        _done = true;
        _granted = granted;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = _message(error);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_done) {
      return CashierDialogFrame(
        title: '发券完成',
        width: 640,
        height: 460,
        body: Column(
  

          children: [
            Icon(
              Icons.check_circle,
              size: 88,
              color: context.cashier.success,
            ),
            const SizedBox(height: 20),
            Text(
              '成功发放 $_granted 张',
              style: const TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '已发放至符合条件的会员账户',
              style: TextStyle(
                fontSize: 18,
                color: context.cashier.inkMuted,
              ),
            ),
          ],
        ),
        actions: [
          CashierActionButton(
            label: '完成',
            onPressed: () => Navigator.pop(context),
          ),
        ],
      );
    }
    return CashierDialogFrame(
      title: '一键发券',
      width: 720,
      height: 620,
      busy: _busy,
      onClose: () => Navigator.pop(context),
      body: _body(),
      actions: [
        CashierActionButton(
          label: '取消',
          onPressed: _busy ? null : () => Navigator.pop(context),
          variant: CashierActionButtonVariant.secondary,
          minimumWidth: 120,
          height: 56,
        ),
        CashierActionButton(
          label: '确认发放',
          onPressed: _selectedId != null && !_busy ? _send : null,
          busy: _busy,
          minimumWidth: 150,
          height: 56,
        ),
      ],
    );
  }

  Widget _body() {
    if (_loading) {
      return const CashierStateView(
        state: CashierViewState.loading,
        title: '正在加载优惠券',
        message: '请稍候',
      );
    }
    if (_loadError != null) {
      return CashierStateView(
        state: CashierViewState.error,
        title: _loadError!,
        message: '请重试',
        actionLabel: '重试',
        onAction: _load,
      );
    }
    if (_coupons.isEmpty) {
      return const CashierStateView(
        state: CashierViewState.empty,
        title: '暂无可发放的优惠券',
        message: '请先在运营后台创建并启用优惠券',
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          '选择要发放的优惠券（发给已绑定手机号的会员）',
          style: TextStyle(fontSize: 18, color: context.cashier.inkMuted),
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: 320,
          child: ListView.builder(
            key: const Key('coupon-send-list'),
            itemCount: _coupons.length,
            itemBuilder: (context, index) {
              final coupon = _coupons[index];
              return InkWell(
                key: Key('coupon-send-select-${coupon.id}'),
                onTap: _busy
                    ? null
                    : () => setState(() => _selectedId = coupon.id),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 10),
                  child: Row(
                    children: [
                      Icon(
                        _selectedId == coupon.id
                            ? Icons.radio_button_checked
                            : Icons.radio_button_unchecked,
                        color: _selectedId == coupon.id
                            ? context.cashier.focus
                            : context.cashier.inkMuted,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              coupon.name,
                              style: const TextStyle(fontWeight: FontWeight.w700),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              '${coupon.summary} · 有效至 ${coupon.endTime == null || coupon.endTime!.isEmpty ? '长期' : _date(coupon.endTime)}',
                              style: TextStyle(fontSize: 14, color: context.cashier.inkMuted),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              );

            },
          ),
        ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Text(
              _error!,
              style: TextStyle(color: context.cashier.danger),
            ),
          ),
      ],
    );
  }
}

/// 新增会员：后端（openapi.yaml）暂无新增会员接口，仅提示，不使用假数据。
class _CreateMemberDialog extends StatelessWidget {
  const _CreateMemberDialog();

  @override
  Widget build(BuildContext context) {
    return CashierDialogFrame(
      title: '新增会员',
      width: 640,
      height: 420,
      body: Column(


        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline, size: 48, color: context.cashier.warning),
          const SizedBox(height: 16),
          const Text(
            '当前后端接口（openapi.yaml）暂未提供「新增会员」能力。',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 12),
          Text(
            '会员由小程序注册生成。如需后台开通该功能，请先在服务端补充新增会员接口后接入。',
            style: TextStyle(fontSize: 18, color: context.cashier.inkMuted),
          ),
        ],
      ),
      actions: [
        CashierActionButton(
          label: '知道了',
          onPressed: () => Navigator.pop(context),
        ),
      ],
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow(this.label, this.value);
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 8),
    child: Row(
      children: [
        SizedBox(
          width: 140,
          child: Text(
            label,
            style: TextStyle(
              color: context.cashier.inkMuted,
              fontSize: 18,
            ),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
          ),
        ),
      ],
    ),
  );
}

String _message(Object error) {
  if (error is ApiException) return error.message;
  if (error is MemberNotFoundException) return error.message;
  return error.toString().replaceFirst(RegExp(r'^Exception: '), '');
}

String _money(num value) {
  final parts = value.toStringAsFixed(2).split('.');
  final grouped = parts.first.replaceAllMapped(
    RegExp(r'\B(?=(\d{3})+(?!\d))'),
    (_) => ',',
  );
  return '¥$grouped.${parts.last}';
}

String _count(num value) {
  final text = value.toStringAsFixed(0);
  return text.replaceAllMapped(
    RegExp(r'\B(?=(\d{3})+(?!\d))'),
    (_) => ',',
  );
}

String _date(String? value) {
  if (value == null || value.isEmpty) return '—';
  return value.length >= 10 ? value.substring(0, 10) : value;
}
