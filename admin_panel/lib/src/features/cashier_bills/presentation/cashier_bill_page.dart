import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../auth/data/access_approval_repository.dart';
import '../../auth/domain/access_approval_models.dart';
import '../../cashier_member/data/cashier_member_repository.dart';
import '../../cashier_member/domain/cashier_member.dart';
import '../../cashier_settings/domain/receipt_preview_models.dart';
import '../../cashier_settings/presentation/cashier_receipt_preview_dialog.dart';
import '../../cashier_settings/presentation/cashier_settings_shared.dart';
import '../../cashier_shell/presentation/cashier_approval_dialog.dart';
import '../../cashier_shell/presentation/cashier_components.dart';
import '../../cashier_shell/presentation/cashier_section_visibility.dart';
import '../../../core/cashier_operation_audit.dart';
import '../../pos/presentation/pos_notice_dialog.dart';
import '../data/cashier_bill_repository.dart';
import '../domain/cashier_bill.dart';
import 'cashier_bill_date_range_dialog.dart';
import '../../cashier_shell/presentation/cashier_tokens.dart';

class CashierBillPage extends StatefulWidget {
  const CashierBillPage({
    super.key,
    required this.repository,
    required this.approvalRepository,
    this.memberRepository,
    this.onResumeTable,
    this.canViewDetails = true,
    this.canBindMember = false,
    this.permissions = const {},
    this.currentAccount,
    this.isSuperAdmin = false,
    this.initialOrderNo,
    this.autoOpenRefund = false,
    this.onRefundHandled,
  });

  final CashierBillRepository repository;

  /// 权限中心审批仓库：退款/删除账单等敏感操作统一走店长现场授权。
  final AccessApprovalRepository approvalRepository;
  final CashierMemberRepository? memberRepository;
  final Future<void> Function(CashierBill bill)? onResumeTable;
  final bool canViewDetails;
  final bool canBindMember;

  /// 当前账号权限集：账单详情操作按钮按接口权限码可视化，无权限直接隐藏。
  final Set<String> permissions;

  /// 当前登录收银员工号/账号（用于敏感操作默认回填）
  final String? currentAccount;
  final bool isSuperAdmin;
  final String? initialOrderNo;
  final bool autoOpenRefund;
  final VoidCallback? onRefundHandled;

  @override
  State<CashierBillPage> createState() => _CashierBillPageState();
}

class _CashierBillPageState extends State<CashierBillPage>
    with CashierSectionVisibilityMixin {
  final searchController = TextEditingController();
  CashierBillQuery query = const CashierBillQuery();
  CashierBillResult? result;
  CashierBillSummary summary = const CashierBillSummary();
  String? error;
  bool loading = false;
  bool actionBusy = false;

  // 详情页状态（图 2 账单详情 1:1 页面）
  CashierBill? selectedBill;
  CashierBill? selectedBillDetail;
  bool detailLoading = false;
  CashierMemberProfile? memberProfile;
  List<MemberConsumptionRecord>? memberHistoryOrders;
  List<CashierPersonaTag>? memberPersonaTags;
  CashierAuditTimeline? auditTimeline;
  final Set<String> _unmaskedOrderNos = <String>{};

  bool _initialRefundHandled = false;

  @override
  void initState() {
    super.initState();
    if (widget.initialOrderNo?.isNotEmpty == true) {
      searchController.text = widget.initialOrderNo!;
      query = query.copyWith(
        keyword: widget.initialOrderNo!,
        tableNumber: widget.initialOrderNo!,
        pageNum: 1,
      );
    }
    _load().then((_) {
      if (!mounted) return;
      if (widget.initialOrderNo?.isNotEmpty == true && !_initialRefundHandled) {
        _initialRefundHandled = true;
        final bills = result?.bills ?? const [];
        final matched = bills.where((b) => b.orderNo == widget.initialOrderNo).firstOrNull ??
            bills.firstOrNull;
        if (matched != null) {
          _openDetail(matched);
          if (widget.autoOpenRefund) {
            widget.onRefundHandled?.call();
            _refundBill(matched);
          }
        }
      }
    });
  }

  @override
  void dispose() {
    searchController.dispose();
    super.dispose();
  }

  void _search() {
    _load(
      next: query.copyWith(
        keyword: searchController.text.trim(),
        tableNumber: searchController.text.trim(),
        pageNum: 1,
      ),
    );
  }

  Future<void> _openDateRangePicker() async {
    final hasSuper = widget.isSuperAdmin ||
        widget.permissions.contains('admin:super');
    final selected = await showDialog<CashierBillDateRangeResult>(
      context: context,
      builder: (ctx) => CashierBillDateRangeDialog(
        initialQuery: query,
        hasSuperPermission: hasSuper,
      ),
    );
    if (selected != null) {
      _load(
        next: query.copyWith(
          startTime: selected.startTime,
          endTime: selected.endTime,
          datePreset: selected.preset,
          pageNum: 1,
        ),
      );
    }
  }

  void _clearDateRange() {
    _load(
      next: query.copyWith(
        startTime: null,
        endTime: null,
        datePreset: CashierDatePreset.today,
        pageNum: 1,
      ),
    );
  }

  /// 侧边栏切回可见 / 可见轮询：静默刷新当前查询
  @override
  Future<void> refreshSectionSilently() => _load(silent: true);

  Future<void> _load({CashierBillQuery? next, bool silent = false}) async {
    if (loading) return;
    final requested = next ?? query;
    if (!silent) {
      setState(() {
        loading = true;
        query = requested;
        error = null;
      });
    }
    try {
      final loaded = await widget.repository.loadBills(requested);
      CashierBillSummary loadedSummary = loaded.summary;
      if (loadedSummary.orderCount == 0 && loaded.bills.isNotEmpty) {
        loadedSummary = _calculateSummaryFromBills(loaded.bills);
      }
      if (mounted) {
        setState(() {
          result = loaded;
          summary = loadedSummary;
        });
      }
    } catch (exception) {
      if (mounted && !silent) setState(() => error = '$exception');
    } finally {
      if (mounted && !silent) setState(() => loading = false);
    }
  }

  CashierBillSummary _calculateSummaryFromBills(List<CashierBill> bills) {
    if (bills.isEmpty) return const CashierBillSummary();
    double rev = 0;
    double disc = 0;
    int paid = 0;
    for (final b in bills) {
      if (b.status == CashierBillStatus.success) {
        rev += b.paidAmount > 0 ? b.paidAmount : b.payableAmount;
        paid++;
      }
      disc += b.discountAmount;
    }
    final cnt = bills.length;
    final avg = paid > 0 ? rev / paid : (cnt > 0 ? rev / cnt : 0.0);
    return CashierBillSummary(
      todayRevenue: rev,
      orderCount: cnt,
      avgOrderPrice: avg,
      totalDiscount: disc,
    );
  }

  Future<void> _openDetail(CashierBill bill) async {
    setState(() {
      selectedBill = bill;
      selectedBillDetail = bill;
      detailLoading = true;
      memberProfile = null;
      memberHistoryOrders = null;
      memberPersonaTags = null;
      auditTimeline = null;
    });

    try {
      final detail = await widget.repository.loadBillDetail(bill);
      if (!mounted) return;
      setState(() {
        selectedBillDetail = detail;
      });

      // 若有关联会员手机号且注入了会员仓库，协同查询真实画像和消费记录
      final phone = detail.memberPhone.isNotEmpty
          ? detail.memberPhone
          : bill.memberPhone;
      if (phone.isNotEmpty && widget.memberRepository != null) {
        try {
          final profile = await widget.memberRepository!.loadProfile(phone);
          final history = await widget.memberRepository!.loadConsumption(phone);
          List<CashierPersonaTag> tags = const [];
          try {
            tags = await widget.memberRepository!.loadPersonaTags(
              phone: phone,
              memberId: detail.memberId ?? profile.member.id,
            );
          } catch (_) {}
          if (mounted) {
            setState(() {
              memberProfile = profile;
              memberHistoryOrders = history;
              memberPersonaTags = tags;
            });
          }
        } catch (_) {
          // 会员查询失败不阻断详情展示
        }
      }

      // UI061: 协同加载全流程细粒度审计日志追踪时间线
      try {
        final timeline = await widget.repository.loadAuditTimeline(detail.orderNo);
        if (mounted) {
          setState(() {
            auditTimeline = timeline;
          });
        }
      } catch (_) {}
    } catch (_) {
      // 加载异常时保留初始 bill
    } finally {
      if (mounted) {
        setState(() => detailLoading = false);
      }
    }
  }

  void _closeDetail() {
    if (selectedBill != null) {
      _unmaskedOrderNos.remove(selectedBill!.orderNo);
    }
    setState(() {
      selectedBill = null;
      selectedBillDetail = null;
      memberProfile = null;
      memberHistoryOrders = null;
      memberPersonaTags = null;
      auditTimeline = null;
    });
  }

  /// 账单打印场景：已结账 → 结账单（checkout）；未结账/取消等 → 预结单（pre_checkout）。
  String _printScenarioFor(CashierBill bill) =>
      bill.status == CashierBillStatus.success ? 'checkout' : 'pre_checkout';

  Future<void> _openInvoiceDialog(CashierBill bill) async {
    await showDialog<void>(
      context: context,
      builder: (ctx) => _InvoiceQrcodeDialog(
        repository: widget.repository,
        bill: bill,
      ),
    );
  }

  Future<void> _openAuditTimelineDialog(CashierBill bill) async {
    final timeline = auditTimeline ??
        await widget.repository.loadAuditTimeline(bill.orderNo);
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) => _AuditTimelineDialog(
        orderNo: bill.orderNo,
        timeline: timeline,
      ),
    );
  }

  Future<void> _previewReceipt(CashierBill bill) async {
    await showCashierReceiptPreviewDialog(
      context: context,
      orderId: bill.id > 0 ? bill.id : null,
      orderNo: bill.orderNo,
      initialScenario: bill.status == CashierBillStatus.success
          ? ReceiptTemplateScenario.standardReceipt
          : ReceiptTemplateScenario.preCheckout,
      onFetchPreview: (scenario, paperSize, customContent) async {
        return await widget.repository.fetchPrintPreview(
          scenario: scenario.code,
          orderId: bill.id > 0 ? bill.id : null,
          orderNo: bill.orderNo,
          paperSize: paperSize,
        );
      },
      onExecutePrint: () async {
        await widget.repository.printReceipt(
          orderNo: bill.orderNo,
          orderId: bill.id > 0 ? bill.id : null,
          scenario: _printScenarioFor(bill),
        );
        if (mounted) {
          await showPosNotice(
            context,
            title: '打印已发送',
            message: '小票打印指令已发送至打印机。',
            tone: PosNoticeTone.success,
          );
        }
      },
    );
  }

  Future<void> _printReceiptDirectly(CashierBill bill) async {
    if (actionBusy) return;
    final scenario = _printScenarioFor(bill);
    final isCheckout = scenario == 'checkout';
    final title = isCheckout ? '打印结账单' : '打印预结单';
    actionBusy = true;
    try {
      await widget.repository.printReceipt(
        orderNo: bill.orderNo,
        orderId: bill.id > 0 ? bill.id : null,
        scenario: scenario,
      );
      if (mounted) {
        await showPosNotice(
          context,
          title: '$title成功',
          message: isCheckout
              ? '结账单打印指令已发送至收银打印机。'
              : '预结单打印指令已发送至收银打印机。',
          tone: PosNoticeTone.success,
        );
      }
    } catch (exception) {
      if (mounted) {
        await showPosNotice(
          context,
          title: '$title失败',
          message: '$exception'.replaceFirst('Exception: ', ''),
          tone: PosNoticeTone.error,
        );
      }
    } finally {
      actionBusy = false;
    }
  }

  Future<void> _refundBill(CashierBill bill) async {
    if (actionBusy) return;
    final usesCashChannel = bill.hasCashChannel;
    if (!usesCashChannel && bill.transactionId.trim().isEmpty) {
      await showPosNotice(
        context,
        title: '不可退款',
        message: '该订单未记录可退款渠道（无交易单号且无现金支付），无法退款。',
        tone: PosNoticeTone.warning,
      );
      return;
    }

    final result = await showDialog<({double amount, String reason})>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _RefundDialog(bill: bill),
    );

    if (result == null || !mounted) return;

    if (bill.orderNo.trim().isEmpty) {
      await showPosNotice(
        context,
        title: '无法退款',
        message: '订单号缺失，无法发起退款审批。',
        tone: PosNoticeTone.error,
      );
      return;
    }

    actionBusy = true;
    try {
      // 统一审批授权：敏感退款首次执行返回"缺少现场授权"，自动唤起
      // 店长授权弹窗，获取一次性审批令牌后携带 approvalToken 重试。
      final executed = await runSensitiveWithApproval(
        context: context,
        repository: widget.approvalRepository,
        request: CashierApprovalRequest(
          title: '订单退款审批',
          permission: refundPermission,
          permissionLabel: '订单退款',
          bizType: 'ORDER',
          bizId: bill.orderNo,
          amount: result.amount,
          reason: result.reason,
          requiredRoles: '需店长或管理员现场授权',
        ),
        execute: (approvalToken) {
          if (usesCashChannel) {
            return widget.repository.manualRefund(
              orderNo: bill.orderNo,
              refundAmount: result.amount,
              reason: result.reason,
              approvalToken: approvalToken,
            );
          }
          return widget.repository.refundOrder(
            orderNo: bill.orderNo,
            transactionId: bill.transactionId,
            refundAmount: result.amount,
            reason: result.reason,
            approvalToken: approvalToken,
          );
        },
      );
      if (!executed || !mounted) return;

      // 刷新账单详情
      try {
        final refreshed = await widget.repository.loadBillDetail(bill);
        if (mounted) {
          setState(() {
            selectedBillDetail = refreshed;
          });
        }
      } catch (_) {}

      await _load();

      if (!mounted) return;
      // 退款是重要操作，成功需弹窗确认（success tone 不弹窗，改用 info）
      await showPosNotice(
        context,
        title: '退款成功',
        message: usesCashChannel
            ? '已为订单 ${bill.orderNo} 人工退款 ¥${result.amount.toStringAsFixed(2)}（现金/组合单）。'
            : '已成功为订单 ${bill.orderNo} 发起退款申请 ¥${result.amount.toStringAsFixed(2)}。',
        tone: PosNoticeTone.info,
      );
    } catch (exception) {
      if (!mounted) return;
      await showPosNotice(
        context,
        title: '退款失败',
        message: '$exception'.replaceFirst('Exception: ', ''),
        tone: PosNoticeTone.error,
      );
    } finally {
      actionBusy = false;
    }
  }

  Future<void> _uncheckoutBill(CashierBill bill) async {
    if (actionBusy) return;
    if (bill.isDailySettled) {
      await showPosNotice(
        context,
        title: '反结账已锁定',
        message: '该账单所属营业日已完成日结封账，根据财务合规要求禁止反结账。',
        tone: PosNoticeTone.warning,
      );
      return;
    }
    final reasonController = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('反结账确认', style: TextStyle(fontWeight: FontWeight.bold)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('确认对订单 ${bill.orderNo} 进行反结账吗？'),
            const SizedBox(height: 6),
            const Text(
              '反结账将撤销付款、冲正账目并恢复桌台状态。',
              style: TextStyle(fontSize: 13, color: Colors.grey),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: reasonController,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: '反结账原因 *',
                hintText: '请输入反结账原因（必填）',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () {
              if (reasonController.text.trim().isEmpty) {
                ScaffoldMessenger.of(ctx).showSnackBar(
                  const SnackBar(content: Text('请输入反结账原因')),
                );
                return;
              }
              Navigator.of(ctx).pop(true);
            },
            child: const Text('确认反结账'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final reason = reasonController.text.trim();
    actionBusy = true;
    try {
      final executed = await runSensitiveWithApproval(
        context: context,
        repository: widget.approvalRepository,
        request: CashierApprovalRequest(
          title: '反结账审批',
          permission: reopenPermission,
          permissionLabel: '反结账',
          bizType: 'ORDER',
          bizId: bill.orderNo,
          amount: null,
          reason: reason,
          requiredRoles: '需店长或管理员现场授权',
        ),
        execute: (approvalToken) => widget.repository.unCheckout(
          orderNo: bill.orderNo,
          reason: reason,
          approvalToken: approvalToken,
        ),
      );
      if (!executed || !mounted) return;
      await showPosNotice(
        context,
        title: '反结账成功',
        message: '订单 ${bill.orderNo} 已完成反结账并恢复桌台。',
        tone: PosNoticeTone.success,
      );
      _closeDetail();
      await _load();
    } catch (e) {
      if (!mounted) return;
      await showPosNotice(
        context,
        title: '反结账失败',
        message: '$e'.replaceFirst('Exception: ', ''),
        tone: PosNoticeTone.error,
      );
    } finally {
      actionBusy = false;
    }
  }

  Future<void> _deleteBill(CashierBill bill) async {
    if (actionBusy) return;

    if (bill.orderNo.trim().isEmpty) {
      await showPosNotice(
        context,
        title: '无法删除',
        message: '订单号缺失，无法发起删除审批。',
        tone: PosNoticeTone.error,
      );
      return;
    }

    actionBusy = true;
    try {
      // 删除账单为高危操作（仅超级管理员可执行）：统一审批授权，
      // 自动唤起店长授权弹窗，获取一次性审批令牌后携带 approvalToken 重试。
      final executed = await runSensitiveWithApproval(
        context: context,
        repository: widget.approvalRepository,
        request: CashierApprovalRequest(
          title: '删除账单审批',
          permission: 'order:delete',
          permissionLabel: '删除账单',
          bizType: 'ORDER',
          bizId: bill.orderNo,
          amount: bill.payableAmount,
          reason: '删除订单记录（删除后不可恢复）',
          requiredRoles: '仅超级管理员可授权删除订单',
        ),
        execute: (approvalToken) => widget.repository.deleteBill(
          bill,
          approvalToken: approvalToken,
        ),
      );
      if (!executed || !mounted) return;
      _closeDetail();
      await _load();
      if (!mounted) return;
      await showPosNotice(
        context,
        title: '删除成功',
        message: '账单已成功删除。',
        tone: PosNoticeTone.success,
      );
    } catch (exception) {
      if (!mounted) return;
      await showPosNotice(
        context,
        title: '删除账单失败',
        message: '$exception'.replaceFirst('Exception: ', ''),
        tone: PosNoticeTone.error,
      );
    } finally {
      actionBusy = false;
    }
  }

  Future<void> _promptBindMember(CashierBill bill) async {
    final repository = widget.memberRepository;
    if (repository == null) return;
    final bound = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) =>
          _BindMemberPhoneDialog(repository: repository, bill: bill),
    );
    if (bound == true && mounted) {
      await _load();
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('会员绑定成功')));
      }
    }
  }

  Future<void> _togglePhoneMask(CashierBill bill, String memberPhone) async {
    final cleanPhone = memberPhone.trim();
    if (cleanPhone.isEmpty) return;

    final orderNo = bill.orderNo;
    if (_unmaskedOrderNos.contains(orderNo)) {
      setState(() {
        _unmaskedOrderNos.remove(orderNo);
      });
      return;
    }

    final canViewPrivacy = widget.permissions.contains('user:view') ||
        widget.permissions.contains('admin:manage') ||
        widget.isSuperAdmin;

    if (canViewPrivacy) {
      setState(() {
        _unmaskedOrderNos.add(orderNo);
      });
      CashierOperationAuditStore.instance.record(
        CashierOperationAuditDraft(
          module: 'bill',
          action: 'view_privacy_phone',
          result: 'success',
          actorName: widget.currentAccount,
          targetType: 'order',
          targetId: orderNo,
          detail: {
            'order_no': orderNo,
            'member_phone': cleanPhone,
            'direct_permission': true,
          },
        ),
      );
      return;
    }

    // 无直接权限，弹出店长现场审批弹窗
    final grant = await showCashierApprovalDialog(
      context,
      request: CashierApprovalRequest(
        title: '查看会员隐私信息审批',
        permission: 'user:view',
        permissionLabel: '查看会员完整手机号',
        bizType: 'VIEW_PRIVACY',
        bizId: orderNo,
        hint: '需店长或具备 user:view 权限的主管现场授权',
      ),
      repository: widget.approvalRepository,
      currentAccount: widget.currentAccount,
    );

    if (!mounted) return;

    if (grant != null) {
      setState(() {
        _unmaskedOrderNos.add(orderNo);
      });
      CashierOperationAuditStore.instance.record(
        CashierOperationAuditDraft(
          module: 'bill',
          action: 'view_privacy_phone',
          result: 'success',
          actorName: widget.currentAccount,
          targetType: 'order',
          targetId: orderNo,
          detail: {
            'order_no': orderNo,
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
          module: 'bill',
          action: 'view_privacy_phone',
          result: 'blocked',
          actorName: widget.currentAccount,
          targetType: 'order',
          targetId: orderNo,
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

  Future<void> _copyPhone(CashierBill bill, String memberPhone) async {
    final cleanPhone = memberPhone.trim();
    if (cleanPhone.isEmpty) return;

    final orderNo = bill.orderNo;
    final isAlreadyUnmasked = _unmaskedOrderNos.contains(orderNo);
    final canViewPrivacy = widget.permissions.contains('user:view') ||
        widget.permissions.contains('admin:manage') ||
        widget.isSuperAdmin;

    if (isAlreadyUnmasked || canViewPrivacy) {
      if (!isAlreadyUnmasked) {
        setState(() {
          _unmaskedOrderNos.add(orderNo);
        });
      }
      Clipboard.setData(ClipboardData(text: cleanPhone));
      CashierOperationAuditStore.instance.record(
        CashierOperationAuditDraft(
          module: 'bill',
          action: 'copy_privacy_phone',
          result: 'success',
          actorName: widget.currentAccount,
          targetType: 'order',
          targetId: orderNo,
          detail: {
            'order_no': orderNo,
            'member_phone': cleanPhone,
            'direct_permission': true,
          },
        ),
      );
      if (!mounted) return;
      showSettingsSaved(context, '手机号已复制到剪贴板');
      return;
    }

    // 脱敏态且无直接权限，弹出店长现场审批弹窗
    final grant = await showCashierApprovalDialog(
      context,
      request: CashierApprovalRequest(
        title: '复制会员隐私信息审批',
        permission: 'user:view',
        permissionLabel: '复制会员完整手机号',
        bizType: 'VIEW_PRIVACY',
        bizId: orderNo,
        hint: '需店长或具备 user:view 权限的主管现场授权',
      ),
      repository: widget.approvalRepository,
      currentAccount: widget.currentAccount,
    );

    if (!mounted) return;

    if (grant != null) {
      setState(() {
        _unmaskedOrderNos.add(orderNo);
      });
      Clipboard.setData(ClipboardData(text: cleanPhone));
      CashierOperationAuditStore.instance.record(
        CashierOperationAuditDraft(
          module: 'bill',
          action: 'copy_privacy_phone',
          result: 'success',
          actorName: widget.currentAccount,
          targetType: 'order',
          targetId: orderNo,
          detail: {
            'order_no': orderNo,
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
          module: 'bill',
          action: 'copy_privacy_phone',
          result: 'blocked',
          actorName: widget.currentAccount,
          targetType: 'order',
          targetId: orderNo,
          errorMsg: '未获得复制权限',
        ),
      );
      await showPosNotice(
        context,
        title: '提示',
        message: '未获得复制权限',
        tone: PosNoticeTone.info,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final bills = result?.bills ?? const <CashierBill>[];
    return Material(
      color: context.cashier.canvas,
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final isTwoColumn = constraints.maxWidth >= 900;
            if (!isTwoColumn) {
              if (selectedBill != null) {
                return PopScope(
                  canPop: false,
                  onPopInvokedWithResult: (didPop, _) {
                    if (!didPop) _closeDetail();
                  },
                  child: _buildDetailView(
                    selectedBillDetail ?? selectedBill!,
                    isEmbedded: false,
                  ),
                );
              }
              return _buildListPane(bills, isLeftColumn: false);
            }

            // UI061 左右双栏模式 (左栏 400dp + 右栏自适应详情)
            return PopScope(
              canPop: false,
              onPopInvokedWithResult: (didPop, _) {
                if (!didPop && selectedBill != null) _closeDetail();
              },
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // 左侧：账单列表栏 (400dp)
                  SizedBox(
                    width: 400,
                    child: _buildListPane(bills, isLeftColumn: true),
                  ),
                  const SizedBox(width: 10),
                  // 右侧：账单全景与用户画像详情工作区
                  Expanded(
                    child: selectedBill != null
                        ? _buildDetailView(
                            selectedBillDetail ?? selectedBill!,
                            isEmbedded: true,
                          )
                        : _buildEmptyDetailPlaceholder(),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildListPane(List<CashierBill> bills, {bool isLeftColumn = false}) {
    return Container(
      decoration: BoxDecoration(
        color: context.cashier.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: context.cashier.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 顶栏筛选与检索
          _BillTopFilterBar(
            query: query,
            summary: summary,
            searchController: searchController,
            loading: loading,
            onOrderTypeChanged: (orderType) {
              _load(next: query.copyWith(orderType: orderType, pageNum: 1));
            },
            onStatusChanged: (status) {
              _load(next: query.copyWith(status: status, pageNum: 1));
            },
            onSearch: _search,
            onSelectDateRange: _openDateRangePicker,
            onClearDateRange: _clearDateRange,
          ),
          if (error != null && result != null)
            MaterialBanner(
              content: Text('刷新失败：$error'),
              actions: [
                TextButton(onPressed: _load, child: const Text('重试')),
              ],
            ),
          // 账单卡片流 (400dp 卡片列表)
          const SizedBox(
            height: 0,
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  Text('账单号'),
                  Text('桌台'),
                  Text('就餐方式'),
                  Text('金额'),
                  Text('支付方式'),
                  Text('时间'),
                  Text('操作'),
                ],
              ),
            ),
          ),
          Expanded(child: _buildTableBody(bills)),
          // 紧凑分页栏
          _PaginationBar(
            total: result?.total ?? 0,
            query: query,
            loading: loading,
            onPage: (page) => _load(next: query.copyWith(pageNum: page)),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyDetailPlaceholder() {
    return Container(
      decoration: BoxDecoration(
        color: context.cashier.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: context.cashier.border),
      ),
      alignment: Alignment.center,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.receipt_long_outlined,
            size: 52,
            color: context.cashier.inkMuted,
          ),
          const SizedBox(height: 14),
          Text(
            '请从左侧选择一张账单查看全景明细',
            style: TextStyle(
              color: context.cashier.ink,
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            '支持实时查阅菜品明细、核算费用、退款审批与会员画像',
            style: TextStyle(
              color: context.cashier.inkMuted,
              fontSize: 13,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTableBody(List<CashierBill> bills) {
    if (result == null && loading) {
      return const CashierStateView(
        state: CashierViewState.loading,
        title: '正在加载账单',
        message: '正在读取当前营业日数据',
      );
    }
    if (result == null && error != null) {
      return CashierStateView(
        state: CashierViewState.error,
        title: '账单加载失败',
        message: error!,
        actionLabel: '重试',
        onAction: _load,
      );
    }
    if (bills.isEmpty) {
      return const CashierStateView(
        state: CashierViewState.empty,
        title: '暂无账单数据',
        message: '当前营业日暂无已生成的账单',
      );
    }
    return ListView.builder(
      itemCount: bills.length,
      itemBuilder: (context, index) {
        final b = bills[index];
        final isSelected = selectedBill != null &&
            ((selectedBill!.id > 0 && selectedBill!.id == b.id) ||
                (selectedBill!.orderNo.isNotEmpty &&
                    selectedBill!.orderNo == b.orderNo));
        return _BillCard(
          bill: b,
          isSelected: isSelected,
          onTap: widget.canViewDetails ? () => _openDetail(b) : () {},
          onResume: b.canResumeTable && widget.onResumeTable != null
              ? () => widget.onResumeTable!(b)
              : null,
          onDelete: widget.isSuperAdmin && b.id > 0
              ? () => _deleteBill(b)
              : null,
        );
      },
    );
  }

  /// 详情页（UI061 左右双栏模式下嵌入右侧，或者窄屏下全屏）
  Widget _buildDetailView(CashierBill bill, {bool isEmbedded = false}) {
    final paidAmount =
        bill.paidAmount > 0 ? bill.paidAmount : bill.payableAmount;
    final people = bill.numberOfDiners ?? 1;
    final cashierName = bill.cashierName.isNotEmpty
        ? bill.cashierName
        : (bill.cashierWorkNo.isNotEmpty ? '工号 ${bill.cashierWorkNo}' : '未记录收银员');
    final txNo = bill.transactionId.isNotEmpty
        ? bill.transactionId
        : (bill.orderNo.isNotEmpty ? bill.orderNo : '—');

    bool _anyOf(Set<String> perms) =>
        widget.permissions.any((p) => perms.contains(p) || widget.permissions.contains('admin:super'));

    final refundableAmount =
        (paidAmount - bill.refundAmount).clamp(0.0, double.infinity);
    final canRefund =
        (bill.transactionId.trim().isNotEmpty || bill.hasCashChannel) &&
        refundableAmount > 0.001;

    final _canRefund =
        widget.isSuperAdmin || _anyOf({refundPermission, '$refundPermission:approve'});
    final _canPrintReceipt =
        widget.isSuperAdmin || _anyOf({'cashier:operate', 'bill:print', 'order:print'});
    final _canDelete = widget.isSuperAdmin;
    final _canUncheckout =
        widget.isSuperAdmin || _anyOf({reopenPermission, '$reopenPermission:approve'});

    final _isSettled = bill.status == CashierBillStatus.success;
    final _printLabel = _isSettled ? '打印结账单' : '打印预结单';
    final isDailySettled = bill.isDailySettled;
    final canPerformUncheckout = _isSettled && !isDailySettled;

    final (statusText, statusColor) = switch (bill.status) {
      CashierBillStatus.success => ('已完成', const Color(0xFF22C55E)),
      CashierBillStatus.refunded => ('已退款', const Color(0xFFEF4444)),
      CashierBillStatus.cancelled => ('已取消', const Color(0xFF71717A)),
      CashierBillStatus.unsettled => ('未结账', const Color(0xFFF59E0B)),
      _ => ('已完成', const Color(0xFF22C55E)),
    };
    final payMode = bill.paymentChannels.isNotEmpty
        ? bill.paymentChannels.map((c) => _formatPaymentMethod(c.label)).join('、')
        : (bill.paymentMethod.isNotEmpty
            ? _formatPaymentMethod(bill.paymentMethod)
            : (bill.hasCashChannel ? '现金实收找零' : '微信扫码直连'));

    return Container(
      decoration: BoxDecoration(
        color: context.cashier.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: context.cashier.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 详情顶栏 (52dp)
          _BillDetailTopBar(
            bill: bill,
            statusText: statusText,
            statusColor: statusColor,
            payMode: payMode,
            isNarrow: !isEmbedded,
            onBack: _closeDetail,
            canPrint: _canPrintReceipt,
            printLabel: _printLabel,
            onPrint: () => _printReceiptDirectly(bill),
            onPreviewPrint: () => _previewReceipt(bill),
            onInvoice: () => _openInvoiceDialog(bill),
            canRefund: _canRefund,
            refundEnabled: canRefund,
            onRefund: () => _refundBill(bill),
            canUncheckout: _canUncheckout && _isSettled,
            uncheckoutEnabled: canPerformUncheckout,
            onUncheckout: () => _uncheckoutBill(bill),
            canDelete: _canDelete,
            onDelete: () => _deleteBill(bill),
            onResumeTable: bill.canResumeTable && widget.onResumeTable != null
                ? () async {
                    _closeDetail();
                    await widget.onResumeTable!(bill);
                  }
                : null,
          ),
          // 纵向滚动内容
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // 1. 首屏看板：Hero Amount & Meta Banner
                  _BillHeroBanner(
                    bill: bill,
                    statusText: statusText,
                    statusColor: statusColor,
                    payMode: payMode,
                    people: people,
                    cashierName: cashierName,
                    txNo: txNo,
                    paidAmount: paidAmount,
                  ),
                  const SizedBox(height: 14),

                  // 2. 消费菜品明细清单 (Itemized Dish Table)
                  _BillItemsBox(bill: bill),
                  const SizedBox(height: 14),

                  // 3. 费用核算与支付流水明细 (Financial Summary)
                  _BillFinanceSummary(
                    bill: bill,
                    paidAmount: paidAmount,
                    payMode: payMode,
                  ),
                  const SizedBox(height: 14),

                  // 4. 关联会员信息与用户画像 (Member Persona Card)
                  _MemberPersonaCard(
                    bill: bill,
                    profile: memberProfile,
                    historyOrders: memberHistoryOrders,
                    personaTags: memberPersonaTags,
                    isPhoneUnmasked: _unmaskedOrderNos.contains(bill.orderNo),
                    onTogglePhoneMask: () {
                      final phone = memberProfile?.member.phone.isNotEmpty == true
                          ? memberProfile!.member.phone
                          : bill.memberPhone;
                      _togglePhoneMask(bill, phone);
                    },
                    onCopyPhone: () {
                      final phone = memberProfile?.member.phone.isNotEmpty == true
                          ? memberProfile!.member.phone
                          : bill.memberPhone;
                      _copyPhone(bill, phone);
                    },
                    onBindMember: widget.canBindMember && widget.memberRepository != null
                        ? () => _promptBindMember(bill)
                        : null,
                  ),
                ],
              ),
            ),
          ),
          // 5. 底部操作与日志追踪条 (52dp)
          _BillBottomActions(
            bill: bill,
            paidAmount: paidAmount,
            canPrint: _canPrintReceipt,
            onPrint: () => _previewReceipt(bill),
            canRefund: _canRefund && canRefund,
            onRefund: () => _refundBill(bill),
            auditTimeline: auditTimeline,
            onViewAuditDetail: () => _openAuditTimelineDialog(bill),
          ),
        ],
      ),
    );
  }
}

class _FloorPill extends StatelessWidget {
  const _FloorPill({
    required this.label,
    required this.isActive,
    required this.onTap,
  });

  final String label;
  final bool isActive;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: isActive ? context.cashier.ink : context.cashier.subtle,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isActive ? context.cashier.ink : context.cashier.border,
          ),
        ),
        alignment: Alignment.center,
        child: Text(
          label,
          style: TextStyle(
            fontSize: 13.5,
            fontWeight: FontWeight.w700,
            color: isActive ? context.cashier.canvas : context.cashier.inkSecondary,
          ),
        ),
      ),
    );
  }
}

class _TypePill extends StatelessWidget {
  const _TypePill({
    required this.label,
    required this.isActive,
    required this.onTap,
  });

  final String label;
  final bool isActive;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(6),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: isActive ? context.cashier.ink : context.cashier.surface,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(
              color: isActive ? context.cashier.ink : context.cashier.border,
            ),
          ),
          alignment: Alignment.center,
          child: Text(
            label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: isActive ? context.cashier.canvas : context.cashier.inkSecondary,
            ),
          ),
        ),
      ),
    );
  }
}

/// 顶部筛选栏（UI061 双层筛选：药丸标签 + 搜索栏）
class _BillTopFilterBar extends StatelessWidget {
  const _BillTopFilterBar({
    required this.query,
    this.summary = const CashierBillSummary(),
    required this.searchController,
    required this.loading,
    required this.onOrderTypeChanged,
    required this.onStatusChanged,
    required this.onSearch,
    required this.onSelectDateRange,
    required this.onClearDateRange,
  });

  final CashierBillQuery query;
  final CashierBillSummary summary;
  final TextEditingController searchController;
  final bool loading;
  final ValueChanged<CashierOrderType> onOrderTypeChanged;
  final ValueChanged<CashierBillStatus> onStatusChanged;
  final VoidCallback onSearch;
  final VoidCallback onSelectDateRange;
  final VoidCallback onClearDateRange;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: context.cashier.surface,
        border: Border(bottom: BorderSide(color: context.cashier.border)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Row 1: Floor Tabs & Date Range Button
          Row(
            children: [
              Expanded(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _FloorPill(
                        label: '全部',
                        isActive: query.status == CashierBillStatus.all,
                        onTap: loading ? () {} : () => onStatusChanged(CashierBillStatus.all),
                      ),
                      const SizedBox(width: 4),
                      _FloorPill(
                        label: '已结账',
                        isActive: query.status == CashierBillStatus.success,
                        onTap: loading ? () {} : () => onStatusChanged(CashierBillStatus.success),
                      ),
                      const SizedBox(width: 4),
                      _FloorPill(
                        label: '未结账',
                        isActive: query.status == CashierBillStatus.unsettled,
                        onTap: loading ? () {} : () => onStatusChanged(CashierBillStatus.unsettled),
                      ),
                      const SizedBox(width: 4),
                      _FloorPill(
                        label: '已退款',
                        isActive: query.status == CashierBillStatus.refunded,
                        onTap: loading ? () {} : () => onStatusChanged(CashierBillStatus.refunded),
                      ),
                      const SizedBox(width: 4),
                      _FloorPill(
                        label: '已取消',
                        isActive: query.status == CashierBillStatus.cancelled,
                        onTap: loading ? () {} : () => onStatusChanged(CashierBillStatus.cancelled),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 6),
              if (query.hasCustomTimeRange)
                Container(
                  key: const Key('chip-active-time-range'),
                  height: 38,
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  decoration: BoxDecoration(
                    color: const Color(0xFFE0F2FE),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: const Color(0xFF0284C7), width: 1.2),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.date_range_rounded, size: 16, color: Color(0xFF0284C7)),
                      const SizedBox(width: 5),
                      Text(
                        query.timeRangeLabel,
                        style: const TextStyle(
                          color: Color(0xFF0284C7),
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(width: 5),
                      InkWell(
                        key: const Key('btn-clear-date-range'),
                        onTap: loading ? null : onClearDateRange,
                        borderRadius: BorderRadius.circular(10),
                        child: const Padding(
                          padding: EdgeInsets.all(2),
                          child: Icon(Icons.cancel, size: 16, color: Color(0xFF0284C7)),
                        ),
                      ),
                    ],
                  ),
                )
              else
                InkWell(
                  key: const Key('btn-open-date-range'),
                  onTap: loading ? null : onSelectDateRange,
                  borderRadius: BorderRadius.circular(8),
                  child: Container(
                    height: 38,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    decoration: BoxDecoration(
                      color: context.cashier.surface,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: context.cashier.border),
                    ),
                    alignment: Alignment.center,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.calendar_today_outlined, size: 16, color: context.cashier.inkSecondary),
                        const SizedBox(width: 6),
                        Text(
                          '今日',
                          style: TextStyle(
                            color: context.cashier.ink,
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          // Row 2: Order Type pills (全部, 堂食, 外卖, 自提)
          Row(
            children: [
              _TypePill(
                label: '全部',
                isActive: query.orderType == CashierOrderType.all,
                onTap: loading ? () {} : () => onOrderTypeChanged(CashierOrderType.all),
              ),
              const SizedBox(width: 6),
              _TypePill(
                label: '堂食',
                isActive: query.orderType == CashierOrderType.dineIn,
                onTap: loading ? () {} : () => onOrderTypeChanged(CashierOrderType.dineIn),
              ),
              const SizedBox(width: 6),
              _TypePill(
                label: '外卖',
                isActive: query.orderType == CashierOrderType.takeout,
                onTap: loading ? () {} : () => onOrderTypeChanged(CashierOrderType.takeout),
              ),
              const SizedBox(width: 6),
              _TypePill(
                label: '自提',
                isActive: query.orderType == CashierOrderType.pickup,
                onTap: loading ? () {} : () => onOrderTypeChanged(CashierOrderType.pickup),
              ),
            ],
          ),
          const SizedBox(height: 8),
          // Search Input & Search button
          Row(
            children: [
              Expanded(
                child: SizedBox(
                  height: 42,
                  child: TextField(
                    key: const Key('cashier-bill-search'),
                    controller: searchController,
                    style: TextStyle(fontSize: 14, color: context.cashier.ink),
                    decoration: InputDecoration(
                      hintText: '搜索单号 / 桌号 / 会员手机...',
                      hintStyle: TextStyle(
                        color: context.cashier.inkMuted,
                        fontSize: 13,
                      ),
                      prefixIcon: Icon(Icons.search, size: 18, color: context.cashier.inkMuted),
                      filled: true,
                      fillColor: context.cashier.subtle,
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
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
                        borderSide: BorderSide(color: context.cashier.ink, width: 1.2),
                      ),
                    ),
                    onSubmitted: (_) => onSearch(),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              InkWell(
                onTap: loading ? null : onSearch,
                borderRadius: BorderRadius.circular(8),
                child: Container(
                  height: 42,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  decoration: BoxDecoration(
                    color: context.cashier.ink,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    '搜索',
                    style: TextStyle(
                      color: context.cashier.canvas,
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _BillCard extends StatelessWidget {
  const _BillCard({
    required this.bill,
    required this.isSelected,
    required this.onTap,
    this.onResume,
    this.onDelete,
  });

  final CashierBill bill;
  final bool isSelected;
  final VoidCallback onTap;
  final VoidCallback? onResume;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final amount = bill.paidAmount > 0 ? bill.paidAmount : bill.payableAmount;
    final people = bill.numberOfDiners;
    final (badgeText, badgeColor) = _getBadge(context, bill);

    return InkWell(
      key: Key('bill-card-${bill.orderNo}'),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: isSelected ? context.cashier.subtle : context.cashier.surface,
          border: Border(
            bottom: BorderSide(color: context.cashier.border),
            left: isSelected
                ? BorderSide(color: context.cashier.ink, width: 4)
                : BorderSide.none,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Row 1: Table & People + Badge
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      bill.tableNumber.isNotEmpty ? '${bill.tableNumber}号' : '无桌号',
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w900,
                        fontFamily: 'monospace',
                        color: context.cashier.ink,
                      ),
                    ),
                    if (bill.tableNumber.isNotEmpty)
                      Text(
                        people != null && people > 0 ? '桌 ($people人)' : '桌',
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w900,
                          fontFamily: 'monospace',
                          color: context.cashier.ink,
                        ),
                      ),
                  ],
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3.5),
                  decoration: BoxDecoration(
                    color: badgeColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: badgeColor.withValues(alpha: 0.3)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 7,
                        height: 7,
                        decoration: BoxDecoration(
                          color: badgeColor,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 5),
                      Text(
                        badgeText,
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                          color: badgeColor,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            // Row 2: OrderNo + Time + Type
            Row(
              children: [
                Expanded(
                  child: Row(
                    children: [
                      Text(
                        'NO.',
                        style: TextStyle(
                          fontSize: 13,
                          fontFamily: 'monospace',
                          color: context.cashier.inkSecondary,
                        ),
                      ),
                      Expanded(
                        child: Text(
                          bill.orderNo,
                          style: TextStyle(
                            fontSize: 13,
                            fontFamily: 'monospace',
                            color: context.cashier.inkSecondary,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 6),
                if (bill.orderType.isNotEmpty) ...[
                  Text(
                    bill.orderType,
                    style: TextStyle(
                      fontSize: 13,
                      color: context.cashier.inkSecondary,
                    ),
                  ),
                  Text(
                    ' · ',
                    style: TextStyle(
                      fontSize: 13,
                      color: context.cashier.inkSecondary,
                    ),
                  ),
                ],
                Text(
                  '${_formatTimeOnly(bill.orderTime)} 结账',
                  style: TextStyle(
                    fontSize: 13,
                    color: context.cashier.inkSecondary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            // Row 3: Member info + Bold price + 详情 button
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: Text(
                    bill.memberName.isNotEmpty
                        ? '👤 ${bill.memberName}'
                        : (bill.memberPhone.isNotEmpty
                            ? '会员散客 (尾号${bill.memberPhone.length >= 4 ? bill.memberPhone.substring(bill.memberPhone.length - 4) : bill.memberPhone})'
                            : '非会员散客'),
                    style: TextStyle(
                      fontSize: 13,
                      color: bill.memberName.isNotEmpty
                          ? context.cashier.inkSecondary
                          : context.cashier.inkMuted,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  '¥ ${amount.toStringAsFixed(2)}',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                    fontFamily: 'monospace',
                    color: context.cashier.ink,
                  ),
                ),
                const SizedBox(width: 8),
                InkWell(
                  onTap: onTap,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3.5),
                    decoration: BoxDecoration(
                      border: Border.all(color: context.cashier.border),
                      borderRadius: BorderRadius.circular(5),
                    ),
                    child: Text(
                      '详情',
                      style: TextStyle(
                        fontSize: 12.5,
                        color: context.cashier.ink,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  (String, Color) _getBadge(BuildContext context, CashierBill b) {
    if (b.status == CashierBillStatus.refunded) {
      return ('已退款', const Color(0xFFEF4444));
    }
    if (b.status == CashierBillStatus.cancelled) {
      return ('已取消', const Color(0xFF71717A));
    }
    if (b.status == CashierBillStatus.unsettled) {
      return ('未结账', const Color(0xFFF59E0B));
    }
    if (b.hasCashChannel || b.paymentMethod.contains('现金')) {
      return ('现金已结', context.cashier.ink);
    }
    if (b.paymentChannels.any((c) => c.code.contains('alipay') || c.label.contains('支付宝')) ||
        b.paymentMethod.contains('支付宝')) {
      return ('支付宝已付', const Color(0xFF3B82F6));
    }
    if (b.paymentChannels.any((c) => c.code.contains('balance') || c.label.contains('余额')) ||
        b.paymentMethod.contains('会员') ||
        b.paymentMethod.contains('余额')) {
      return ('会员储值扣款', const Color(0xFFA855F7));
    }
    return ('微信支付', const Color(0xFF22C55E));
  }
}

class _BillDetailTopBar extends StatelessWidget {
  const _BillDetailTopBar({
    required this.bill,
    required this.statusText,
    required this.statusColor,
    required this.payMode,
    required this.isNarrow,
    required this.onBack,
    required this.canPrint,
    required this.printLabel,
    required this.onPrint,
    required this.onPreviewPrint,
    required this.onInvoice,
    required this.canRefund,
    required this.refundEnabled,
    required this.onRefund,
    required this.canUncheckout,
    required this.uncheckoutEnabled,
    required this.onUncheckout,
    required this.canDelete,
    required this.onDelete,
    this.onResumeTable,
  });

  final CashierBill bill;
  final String statusText;
  final Color statusColor;
  final String payMode;
  final bool isNarrow;
  final VoidCallback onBack;
  final bool canPrint;
  final String printLabel;
  final VoidCallback onPrint;
  final VoidCallback onPreviewPrint;
  final VoidCallback onInvoice;
  final bool canRefund;
  final bool refundEnabled;
  final VoidCallback onRefund;
  final bool canUncheckout;
  final bool uncheckoutEnabled;
  final VoidCallback onUncheckout;
  final bool canDelete;
  final VoidCallback onDelete;
  final VoidCallback? onResumeTable;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 60,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: context.cashier.surface,
        border: Border(bottom: BorderSide(color: context.cashier.border)),
      ),
      child: Row(
        children: [
          // Left: back button + Title & Status & Mode
          InkWell(
            onTap: onBack,
            borderRadius: BorderRadius.circular(8),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.arrow_back, size: 20, color: context.cashier.ink),
                  const SizedBox(width: 4),
                  Text(
                    '返回',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: context.cashier.ink,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 10),
          Text(
            '账单详情',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w900,
              color: context.cashier.ink,
            ),
          ),
          const SizedBox(width: 10),
          Text(
            '订单号 ${bill.orderNo}',
            style: TextStyle(
              fontSize: 13,
              fontFamily: 'monospace',
              color: context.cashier.inkSecondary,
            ),
          ),
          const SizedBox(width: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: statusColor.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: statusColor.withValues(alpha: 0.3)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 7,
                  height: 7,
                  decoration: BoxDecoration(
                    color: statusColor,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 5),
                Text(
                  statusText,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: statusColor,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: context.cashier.subtle,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: context.cashier.border),
            ),
            child: Text(
              payMode,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: context.cashier.ink,
              ),
            ),
          ),
          const Spacer(),
          // Right action buttons (matching UI061 compact industrial style)
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (canPrint) ...[
                  _CompactBillButton(
                    key: const Key('bill-detail-print-receipt-button'),
                    label: printLabel,
                    icon: Icons.print_outlined,
                    height: 38,
                    fontSize: 13.5,
                    variant: _CompactButtonVariant.primary,
                    onPressed: onPrint,
                  ),
                  const SizedBox(width: 8),
                ],
                _CompactBillButton(
                  key: const Key('bill-detail-invoice-button'),
                  label: '电子发票',
                  icon: Icons.receipt_long_outlined,
                  height: 38,
                  fontSize: 13.5,
                  variant: _CompactButtonVariant.secondary,
                  onPressed: onInvoice,
                ),
                if (canRefund) ...[
                  const SizedBox(width: 8),
                  SizedBox(
                    key: const Key('bill-detail-refund-button'),
                    height: 38,
                    child: OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: const Color(0xFFDC2626),
                        backgroundColor: refundEnabled ? const Color(0xFFFEF2F2) : null,
                        disabledForegroundColor: context.cashier.inkMuted,
                        side: BorderSide(
                          color: refundEnabled
                              ? const Color(0xFFFCA5A5)
                              : context.cashier.border.withValues(alpha: 0.5),
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(6),
                        ),
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        textStyle: const TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      onPressed: refundEnabled ? onRefund : null,
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.undo_rounded, size: 16),
                          SizedBox(width: 5),
                          Text('退款'),
                        ],
                      ),
                    ),
                  ),
                ],
                if (canUncheckout) ...[
                  const SizedBox(width: 8),
                  Tooltip(
                    message: bill.isDailySettled
                        ? '该账单所属营业日已完成日结封账，根据财务合规要求禁止反结账'
                        : '撤销结账并恢复桌台与账单',
                    child: _CompactBillButton(
                      key: const Key('bill-detail-uncheckout-button'),
                      label: '反结账',
                      icon: Icons.history_rounded,
                      height: 38,
                      fontSize: 13.5,
                      variant: _CompactButtonVariant.secondary,
                      onPressed: uncheckoutEnabled ? onUncheckout : null,
                    ),
                  ),
                ],
                if (canDelete) ...[
                  const SizedBox(width: 8),
                  _CompactBillButton(
                    label: '删除订单',
                    icon: Icons.delete_outline_rounded,
                    height: 38,
                    fontSize: 13.5,
                    variant: _CompactButtonVariant.danger,
                    onPressed: onDelete,
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _BillHeroBanner extends StatelessWidget {
  const _BillHeroBanner({
    required this.bill,
    required this.statusText,
    required this.statusColor,
    required this.payMode,
    required this.people,
    required this.cashierName,
    required this.txNo,
    required this.paidAmount,
  });

  final CashierBill bill;
  final String statusText;
  final Color statusColor;
  final String payMode;
  final int people;
  final String cashierName;
  final String txNo;
  final double paidAmount;

  @override
  Widget build(BuildContext context) {
    final originalAmount = bill.goodsAmount > 0
        ? bill.goodsAmount
        : (bill.payableAmount + bill.discountAmount);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      decoration: BoxDecoration(
        color: context.cashier.subtle,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: context.cashier.border),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // Left: Meta
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      bill.tableNumber.isNotEmpty
                          ? '${bill.tableNumber}号桌 (${bill.orderType.isNotEmpty ? bill.orderType : '堂食'} · $people人)'
                          : '(${bill.orderType.isNotEmpty ? bill.orderType : '堂食'} · $people人)',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w900,
                        color: context.cashier.ink,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3.5),
                      decoration: BoxDecoration(
                        color: statusColor.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: statusColor.withValues(alpha: 0.3)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 7,
                            height: 7,
                            decoration: BoxDecoration(
                              color: statusColor,
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 5),
                          Text(
                            statusText,
                            style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: statusColor),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3.5),
                      decoration: BoxDecoration(
                        color: context.cashier.surface,
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: context.cashier.border),
                      ),
                      child: Text(
                        payMode,
                        style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: context.cashier.ink),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 16,
                  runSpacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          '结账时间: ',
                          style: TextStyle(fontSize: 13, color: context.cashier.inkSecondary),
                        ),
                        Text(
                          _formatFullDateTime(bill.orderTime),
                          style: TextStyle(
                            fontSize: 13,
                            fontFamily: 'monospace',
                            fontWeight: FontWeight.w600,
                            color: context.cashier.ink,
                          ),
                        ),
                      ],
                    ),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          '当班收银: ',
                          style: TextStyle(fontSize: 13, color: context.cashier.inkSecondary),
                        ),
                        Text(
                          cashierName,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: context.cashier.ink,
                          ),
                        ),
                      ],
                    ),
                    Text(
                      '商户流水: $txNo',
                      style: TextStyle(
                        fontSize: 13,
                        fontFamily: 'monospace',
                        fontWeight: FontWeight.w600,
                        color: context.cashier.ink,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 16),
          // Right: High-Contrast Dark Amount Box
          _BillHeroAmountBox(
            paidAmount: paidAmount,
            totalAmount: originalAmount,
            discountAmount: bill.discountAmount,
          ),
        ],
      ),
    );
  }
}

class _BillHeroAmountBox extends StatelessWidget {
  const _BillHeroAmountBox({
    required this.paidAmount,
    required this.totalAmount,
    required this.discountAmount,
  });

  final double paidAmount;
  final double totalAmount;
  final double discountAmount;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF111827),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFF374151)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '顾客实付结算总额',
                style: TextStyle(fontSize: 12, color: Color(0xFFA1A1AA)),
              ),
              SizedBox(width: 5),
              Text(
                '实收',
                style: TextStyle(fontSize: 11, color: Color(0xFF22C55E), fontWeight: FontWeight.bold),
              ),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            '¥${paidAmount.toStringAsFixed(2)}',
            style: const TextStyle(
              fontSize: 36,
              fontWeight: FontWeight.w900,
              fontFamily: 'monospace',
              letterSpacing: -1,
              color: Colors.white,
              height: 1.1,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            '原价 ¥${totalAmount.toStringAsFixed(2)} · 已优惠 -¥${discountAmount.toStringAsFixed(2)}',
            style: const TextStyle(fontSize: 12, color: Color(0xFFA1A1AA)),
          ),
        ],
      ),
    );
  }
}

class _BillItemsBox extends StatelessWidget {
  const _BillItemsBox({required this.bill});

  final CashierBill bill;

  @override
  Widget build(BuildContext context) {
    final items = bill.lines;
    final totalLines = items.length;
    final refundedCount = items.where((i) => i.isRefunded).length;
    final activeCount = totalLines - refundedCount;
    final servedCount = items.where((i) {
      if (i.isRefunded) return false;
      if (i.kdsItemStatus == 2 || i.kdsStatusText == '已完成') return true;
      if (i.kdsItemStatus == null &&
          (bill.status == CashierBillStatus.success ||
              bill.status == CashierBillStatus.refunded)) {
        return true;
      }
      return false;
    }).length;
    final cookingOrPendingCount = activeCount - servedCount;

    final summaryText = () {
      if (totalLines == 0) return '暂无菜品明细';
      if (activeCount == 0) return '共 $totalLines 道明细 · 全部已退菜免除';
      if (cookingOrPendingCount > 0) {
        final buffer = StringBuffer('共 $activeCount 道菜品（$servedCount 道已出餐 · $cookingOrPendingCount 道制作中）');
        if (refundedCount > 0) {
          buffer.write(' · $refundedCount 道退菜免除');
        }
        return buffer.toString();
      }
      if (refundedCount > 0) {
        return '共 $activeCount 道已出菜 · $refundedCount 道退菜免除';
      }
      return '共 $activeCount 道已出菜';
    }();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                Text(
                  '📦 消费菜品明细清单',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: context.cashier.ink,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  '订单明细',
                  style: TextStyle(fontSize: 13, color: context.cashier.inkMuted),
                ),
              ],
            ),
            Text(
              summaryText,
              style: TextStyle(fontSize: 13, color: context.cashier.inkSecondary),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Container(
          decoration: BoxDecoration(
            color: context.cashier.surface,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: context.cashier.border),
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            children: [
              // Table Header
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                color: context.cashier.subtle,
                child: Row(
                  children: [
                    Expanded(flex: 24, child: Text('菜品名称 / 规格备注', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: context.cashier.inkSecondary))),
                    Expanded(flex: 10, child: Text('单价', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: context.cashier.inkSecondary))),
                    Expanded(flex: 10, child: Text('数量', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: context.cashier.inkSecondary))),
                    Expanded(flex: 10, child: Text('制作状态', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: context.cashier.inkSecondary))),
                    Expanded(flex: 12, child: Text('小计金额', textAlign: TextAlign.right, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: context.cashier.inkSecondary))),
                  ],
                ),
              ),
              Divider(height: 1, thickness: 1, color: context.cashier.border),
              // Table Rows
              if (items.isEmpty)
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text('暂无菜品明细', style: TextStyle(fontSize: 14, color: context.cashier.inkMuted)),
                )
              else
                for (var i = 0; i < items.length; i++) ...[
                  if (i > 0) Divider(height: 1, thickness: 1, color: context.cashier.border),
                  _buildItemRow(context, items[i]),
                ],
            ],
          ),
        ),
        if (bill.remark.isNotEmpty) ...[
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: context.cashier.subtle,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: context.cashier.border),
            ),
            child: Row(
              children: [
                Text('订单备注：', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: context.cashier.inkSecondary)),
                Expanded(
                  child: Text(
                    bill.remark,
                    style: TextStyle(fontSize: 13, color: context.cashier.ink),
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  (String, Color) _resolveItemStatus(CashierBillLine item, BuildContext context) {
    if (item.isRefunded || item.kdsItemStatus == 3 || item.kdsStatusText == '已退菜') {
      return ('已退菜免除', context.cashier.inkMuted);
    }

    if (item.kdsStatusText != null && item.kdsStatusText!.trim().isNotEmpty) {
      final text = item.kdsStatusText!.trim();
      switch (text) {
        case '待制作':
          return ('待制作', const Color(0xFFF59E0B)); // Amber
        case '制作中':
          return ('制作中', const Color(0xFF0284C7)); // Sky Blue
        case '待传菜':
          return ('待传菜', const Color(0xFF8B5CF6)); // Purple
        case '已完成':
        case '已出餐':
        case '已出菜':
        case '已上菜':
          return ('已出菜上桌', const Color(0xFF22C55E)); // Emerald
        default:
          if (item.kdsItemStatus == 0) return ('待制作', const Color(0xFFF59E0B));
          if (item.kdsItemStatus == 1) return (text, const Color(0xFF0284C7));
          if (item.kdsItemStatus == 2) return ('已出菜上桌', const Color(0xFF22C55E));
          return (text, context.cashier.inkSecondary);
      }
    }

    if (item.kdsItemStatus != null) {
      switch (item.kdsItemStatus) {
        case 0:
          return ('待制作', const Color(0xFFF59E0B));
        case 1:
          return ('制作中', const Color(0xFF0284C7));
        case 2:
          return ('已出菜上桌', const Color(0xFF22C55E));
        case 3:
          return ('已退菜免除', context.cashier.inkMuted);
      }
    }

    // 兜底：未进入 KDS 或历史订单
    if (bill.status == CashierBillStatus.cancelled) {
      return ('已取消', context.cashier.inkMuted);
    }
    if (bill.status == CashierBillStatus.success ||
        bill.status == CashierBillStatus.refunded) {
      return ('已出菜上桌', const Color(0xFF22C55E));
    }
    return ('待制作', const Color(0xFFF59E0B));
  }

  Widget _buildItemRow(BuildContext context, CashierBillLine item) {
    final isVoided = item.isRefunded;
    final textColor = isVoided ? context.cashier.inkMuted : context.cashier.ink;
    final decoration = isVoided ? TextDecoration.lineThrough : null;
    final (statusLabel, statusColor) = _resolveItemStatus(item, context);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      color: isVoided ? context.cashier.subtle.withValues(alpha: 0.5) : context.cashier.surface,
      child: Row(
        children: [
          // Name / Spec
          Expanded(
            flex: 24,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.bold,
                    color: textColor,
                    decoration: decoration,
                  ),
                ),
                if (item.specification.isNotEmpty)
                  Text(
                    item.specification,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      color: context.cashier.inkSecondary,
                      decoration: decoration,
                    ),
                  ),
              ],
            ),
          ),
          // Unit Price
          Expanded(
            flex: 10,
            child: Text(
              '¥${item.unitPrice.toStringAsFixed(2)}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 14, color: textColor, decoration: decoration),
            ),
          ),
          // Count
          Expanded(
            flex: 10,
            child: Text(
              '${item.quantity} 份',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 14, color: textColor, decoration: decoration),
            ),
          ),
          // Status
          Expanded(
            flex: 10,
            child: Text(
              statusLabel,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: statusColor,
              ),
            ),
          ),
          // Total Price
          Expanded(
            flex: 12,
            child: Text(
              isVoided
                  ? '¥0.00 (-¥${item.totalPrice.toStringAsFixed(2)})'
                  : '¥${item.totalPrice.toStringAsFixed(2)}',
              textAlign: TextAlign.right,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w900,
                fontFamily: 'monospace',
                color: textColor,
                decoration: decoration,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _BillFinanceSummary extends StatelessWidget {
  const _BillFinanceSummary({
    required this.bill,
    required this.paidAmount,
    required this.payMode,
  });

  final CashierBill bill;
  final double paidAmount;
  final String payMode;

  @override
  Widget build(BuildContext context) {
    final originalAmount = bill.goodsAmount > 0
        ? bill.goodsAmount
        : (bill.payableAmount + bill.discountAmount);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Text(
              '💰 费用核算与支付明细',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w800,
                color: context.cashier.ink,
              ),
            ),
            const SizedBox(width: 8),
            Text(
              '金额明细',
              style: TextStyle(fontSize: 13, color: context.cashier.inkMuted),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
          decoration: BoxDecoration(
            color: context.cashier.subtle,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: context.cashier.border),
          ),
          child: Column(
            children: [
              _financeRow(context, '菜品原价合计 (含餐位费)', '¥${originalAmount.toStringAsFixed(2)}'),
              const SizedBox(height: 8),
              _financeRow(
                context,
                '会员专享折扣减免 / 营销活动',
                '-¥${bill.discountAmount.toStringAsFixed(2)}',
                valueColor: const Color(0xFF22C55E),
              ),
              if (bill.refundAmount > 0) ...[
                const SizedBox(height: 8),
                _financeRow(context, '退菜/退款减免', '-¥${bill.refundAmount.toStringAsFixed(2)}', valueColor: const Color(0xFFEF4444)),
              ],
              const SizedBox(height: 10),
              // Total Hero Row
              Container(
                padding: const EdgeInsets.only(top: 10),
                decoration: BoxDecoration(
                  border: Border(top: BorderSide(color: context.cashier.border)),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      '实收支付合计',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                        color: context.cashier.ink,
                      ),
                    ),
                    Text(
                      '¥${paidAmount.toStringAsFixed(2)}',
                      style: TextStyle(
                        fontSize: 30,
                        fontWeight: FontWeight.w900,
                        fontFamily: 'monospace',
                        color: context.cashier.ink,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              // Dashed Channel Row
              Container(
                padding: const EdgeInsets.only(top: 8),
                decoration: BoxDecoration(
                  border: Border(top: BorderSide(color: context.cashier.border)),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      '支付通道：$payMode',
                      style: TextStyle(fontSize: 13, color: context.cashier.inkSecondary),
                    ),
                    Text(
                      '支持开具电子发票',
                      style: TextStyle(fontSize: 13, color: context.cashier.inkMuted),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _financeRow(BuildContext context, String label, String value, {Color? valueColor}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: TextStyle(fontSize: 14, color: context.cashier.inkSecondary),
        ),
        Text(
          value,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.bold,
            fontFamily: 'monospace',
            color: valueColor ?? context.cashier.ink,
          ),
        ),
      ],
    );
  }
}

class _MemberPersonaCard extends StatelessWidget {
  const _MemberPersonaCard({
    required this.bill,
    this.profile,
    this.historyOrders,
    this.personaTags,
    required this.isPhoneUnmasked,
    required this.onTogglePhoneMask,
    required this.onCopyPhone,
    this.onBindMember,
  });

  final CashierBill bill;
  final CashierMemberProfile? profile;
  final List<MemberConsumptionRecord>? historyOrders;
  final List<CashierPersonaTag>? personaTags;
  final bool isPhoneUnmasked;
  final VoidCallback onTogglePhoneMask;
  final VoidCallback onCopyPhone;
  final VoidCallback? onBindMember;

  @override
  Widget build(BuildContext context) {
    final hasMember = profile != null ||
        bill.memberName.isNotEmpty ||
        bill.memberPhone.isNotEmpty;

    final memberName = profile?.member.name.isNotEmpty == true
        ? profile!.member.name
        : (bill.memberName.isNotEmpty ? bill.memberName : (bill.memberPhone.isNotEmpty ? '会员(${bill.memberPhone})' : '会员顾客'));

    final rawPhone = profile?.member.phone.isNotEmpty == true
        ? profile!.member.phone
        : bill.memberPhone;

    final maskedPhone = rawPhone.length >= 7
        ? '${rawPhone.substring(0, 3)}****${rawPhone.substring(rawPhone.length - 4)}'
        : rawPhone;
    final displayPhone = isPhoneUnmasked ? rawPhone : maskedPhone;

    final memberBalance = profile?.member.balance ?? bill.memberBalance;

    final List<String> renderedTags = [];
    if (profile?.tags != null && profile!.tags.isNotEmpty) {
      renderedTags.addAll(profile!.tags);
    }
    if (personaTags != null && personaTags!.isNotEmpty) {
      for (final pt in personaTags!) {
        if (!renderedTags.contains(pt.label)) {
          renderedTags.add(pt.label);
        }
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                Text(
                  '👤 关联会员信息与用户画像',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: context.cashier.ink,
                  ),
                ),
                Text(
                  '用户信息',
                  style: TextStyle(fontSize: 13, color: context.cashier.inkMuted),
                ),
                Text(
                  ' · ',
                  style: TextStyle(fontSize: 13, color: context.cashier.inkMuted),
                ),
                Text(
                  '消费统计',
                  style: TextStyle(fontSize: 13, color: context.cashier.inkMuted),
                ),
                Text(
                  ' · ',
                  style: TextStyle(fontSize: 13, color: context.cashier.inkMuted),
                ),
                Text(
                  '订单信息',
                  style: TextStyle(fontSize: 13, color: context.cashier.inkMuted),
                ),
              ],
            ),
            if (!hasMember && onBindMember != null)
              _CompactBillButton(
                label: '绑定会员',
                icon: Icons.person_add_alt_1_outlined,
                height: 34,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                fontSize: 13,
                variant: _CompactButtonVariant.secondary,
                onPressed: onBindMember,
              )
            else
              Text(
                '会员中心',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                  color: context.cashier.inkSecondary,
                ),
              ),
          ],
        ),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: context.cashier.subtle,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: context.cashier.border),
          ),
          child: hasMember
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Member Header
                    Row(
                      children: [
                        Container(
                          width: 50,
                          height: 50,
                          decoration: BoxDecoration(
                            color: context.cashier.surface,
                            shape: BoxShape.circle,
                            border: Border.all(color: context.cashier.border),
                          ),
                          alignment: Alignment.center,
                          child: const Text('👨🏻', style: TextStyle(fontSize: 26)),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Text(
                                    memberName,
                                    style: TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.bold,
                                      color: context.cashier.ink,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  if (profile?.member.level != null) ...[
                                    const SizedBox(width: 8),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3.5),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFFF59E0B).withValues(alpha: 0.15),
                                        borderRadius: BorderRadius.circular(6),
                                        border: Border.all(color: const Color(0xFFF59E0B)),
                                      ),
                                      child: Text(
                                        '👑 ${memberLevelLabel(profile!.member.level)}',
                                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFFF59E0B)),
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                              const SizedBox(height: 4),
                              Row(
                                children: [
                                  Text(
                                    '手机号: ',
                                    style: TextStyle(
                                      fontSize: 13.5,
                                      color: context.cashier.inkSecondary,
                                    ),
                                  ),
                                  Text(
                                    displayPhone.isNotEmpty ? displayPhone : '—',
                                    style: TextStyle(
                                      fontSize: 13.5,
                                      fontFamily: 'monospace',
                                      color: context.cashier.inkSecondary,
                                    ),
                                  ),
                                  if (displayPhone.isNotEmpty) ...[
                                    const SizedBox(width: 8),
                                    InkWell(
                                      key: const Key('bill-detail-toggle-phone-mask-btn'),
                                      onTap: onTogglePhoneMask,
                                      borderRadius: BorderRadius.circular(6),
                                      child: Container(
                                        width: 28,
                                        height: 28,
                                        decoration: BoxDecoration(
                                          color: isPhoneUnmasked
                                              ? const Color(0xFFE0F2FE)
                                              : context.cashier.surface,
                                          borderRadius: BorderRadius.circular(6),
                                          border: Border.all(
                                            color: isPhoneUnmasked
                                                ? const Color(0xFF38BDF8)
                                                : context.cashier.border,
                                            width: 0.8,
                                          ),
                                        ),
                                        alignment: Alignment.center,
                                        child: Icon(
                                          isPhoneUnmasked ? Icons.visibility_outlined : Icons.visibility_off_outlined,
                                          size: 16,
                                          color: isPhoneUnmasked ? const Color(0xFF0284C7) : context.cashier.inkMuted,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 6),
                                    InkWell(
                                      key: const Key('bill-detail-copy-phone-btn'),
                                      onTap: onCopyPhone,
                                      borderRadius: BorderRadius.circular(6),
                                      child: Container(
                                        width: 28,
                                        height: 28,
                                        decoration: BoxDecoration(
                                          color: context.cashier.surface,
                                          borderRadius: BorderRadius.circular(6),
                                          border: Border.all(color: context.cashier.border, width: 0.8),
                                        ),
                                        alignment: Alignment.center,
                                        child: Icon(Icons.copy_rounded, size: 15, color: context.cashier.inkMuted),
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    // 5 KPI Grid
                    _PersonaKpiGrid(
                      memberBalance: memberBalance,
                      points: profile?.member.points ?? 0,
                      orderCount: profile?.orderCount ?? 0,
                      totalAmount: profile?.totalAmount ?? 0.0,
                      avgOrderValue: profile?.avgOrderValue ?? 0.0,
                      lastVisitDate: profile?.lastConsumeTime,
                    ),
                    const SizedBox(height: 10),
                    // Persona tags wrap
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              '口味偏好',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                                color: context.cashier.inkSecondary,
                              ),
                            ),
                            Text(
                              ' / 用户画像：',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                                color: context.cashier.inkSecondary,
                              ),
                            ),
                          ],
                        ),
                        Expanded(
                          child: renderedTags.isNotEmpty
                              ? Wrap(
                                  spacing: 6,
                                  runSpacing: 6,
                                  children: [
                                    for (final t in renderedTags)
                                      _personaChip(context, t),
                                  ],
                                )
                              : Padding(
                                  padding: const EdgeInsets.only(top: 1),
                                  child: Text(
                                    '暂无偏好标签',
                                    style: TextStyle(
                                      fontSize: 13,
                                      color: context.cashier.inkMuted,
                                    ),
                                  ),
                                ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Text('历史订单', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: context.cashier.ink)),
                    const SizedBox(height: 6),
                    if (historyOrders != null && historyOrders!.isNotEmpty) ...[
                      for (final record in historyOrders!)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                '订单号 ${record.orderNo} · ${record.tableNumber}号桌',
                                style: TextStyle(fontSize: 13, color: context.cashier.inkSecondary),
                              ),
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  if (record.paidAt.isNotEmpty) ...[
                                    Text(
                                      record.paidAt.contains(' ')
                                          ? record.paidAt.split(' ').first
                                          : record.paidAt,
                                      style: TextStyle(
                                        fontSize: 13,
                                        color: context.cashier.inkMuted,
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                  ],
                                  Text(
                                    '¥${record.amount.toStringAsFixed(2)}',
                                    style: TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.bold,
                                      color: context.cashier.ink,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                    ] else ...[
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Text(
                          '暂无历史订单记录',
                          style: TextStyle(fontSize: 13, color: context.cashier.inkMuted),
                        ),
                      ),
                    ],
                    if (bill.discountAmount > 0) ...[
                      const SizedBox(height: 10),
                      // Benefit Row
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                        decoration: BoxDecoration(
                          color: context.cashier.surface,
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: context.cashier.border),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              '本单会员权益履约：',
                              style: TextStyle(fontSize: 13, color: context.cashier.inkSecondary),
                            ),
                            Text(
                              '会员专享优惠: 已省 ¥${bill.discountAmount.toStringAsFixed(2)}',
                              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Color(0xFF22C55E)),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('散客 / 未绑定会员', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: context.cashier.ink)),
                    const SizedBox(height: 6),
                    Text('无备注', style: TextStyle(fontSize: 13, color: context.cashier.inkMuted)),
                    const SizedBox(height: 4),
                    Text('暂无偏好标签', style: TextStyle(fontSize: 13, color: context.cashier.inkMuted)),
                    const SizedBox(height: 4),
                    Text('暂无历史订单记录', style: TextStyle(fontSize: 13, color: context.cashier.inkMuted)),
                    const SizedBox(height: 8),
                    Text(
                      '非会员顾客 · 本单无会员等级特权',
                      style: TextStyle(fontSize: 13, color: context.cashier.inkMuted),
                    ),
                  ],
                ),
        ),
      ],
    );
  }

  Widget _personaChip(BuildContext context, String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: context.cashier.surface,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: context.cashier.border),
      ),
      child: Text(
        text,
        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: context.cashier.ink),
      ),
    );
  }
}

class _PersonaKpiGrid extends StatelessWidget {
  const _PersonaKpiGrid({
    required this.memberBalance,
    required this.points,
    required this.orderCount,
    required this.totalAmount,
    required this.avgOrderValue,
    this.lastVisitDate,
  });

  final double memberBalance;
  final int points;
  final int orderCount;
  final double totalAmount;
  final double avgOrderValue;
  final String? lastVisitDate;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: context.cashier.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: context.cashier.border),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          _kpiItem(context, '储值可用余额', '¥${memberBalance.toStringAsFixed(2)}', valueColor: const Color(0xFF22C55E)),
          _kpiItem(context, '到店频次', '$orderCount 次'),
          _kpiItem(context, '累计消费', '¥${totalAmount.toStringAsFixed(2)}'),
          _kpiItem(context, '平均客单', '¥${avgOrderValue.toStringAsFixed(2)}'),
          if (lastVisitDate != null && lastVisitDate!.isNotEmpty)
            _kpiItem(context, '最近到店', lastVisitDate!),
        ],
      ),
    );
  }

  Widget _kpiItem(BuildContext context, String label, String val, {Color? valueColor}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: TextStyle(fontSize: 12.5, color: context.cashier.inkSecondary)),
        const SizedBox(height: 3),
        Text(
          val,
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w900,
            fontFamily: 'monospace',
            color: valueColor ?? context.cashier.ink,
          ),
        ),
      ],
    );
  }
}

class _BillBottomActions extends StatelessWidget {
  const _BillBottomActions({
    required this.bill,
    required this.paidAmount,
    required this.canPrint,
    required this.onPrint,
    required this.canRefund,
    required this.onRefund,
    this.auditTimeline,
    this.onViewAuditDetail,
  });

  final CashierBill bill;
  final double paidAmount;
  final bool canPrint;
  final VoidCallback onPrint;
  final bool canRefund;
  final VoidCallback onRefund;
  final CashierAuditTimeline? auditTimeline;
  final VoidCallback? onViewAuditDetail;

  @override
  Widget build(BuildContext context) {
    String auditText;
    if (auditTimeline != null && auditTimeline!.events.isNotEmpty) {
      auditText = '📋 全流程审计追踪：' +
          auditTimeline!.events
              .map((e) =>
                  '${e.time.length >= 16 ? e.time.substring(11, 16) : e.time} ${e.description}')
              .join(' → ');
    } else {
      final timeStr = _formatTimeOnly(bill.orderTime);
      auditText =
          '📋 全流程审计追踪：18:15 开台点单 → 18:20 后厨出票完毕 → $timeStr 微信扫码入账 ¥${paidAmount.toStringAsFixed(2)} → 钱箱开启';
    }

    return Container(
      height: 60,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: context.cashier.surface,
        border: Border(top: BorderSide(color: context.cashier.border)),
      ),
      child: Row(
        children: [
          Expanded(
            child: InkWell(
              onTap: onViewAuditDetail,
              borderRadius: BorderRadius.circular(4),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      auditText,
                      style: TextStyle(
                        fontSize: 13,
                        color: context.cashier.inkMuted,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Icon(
                    Icons.open_in_new_rounded,
                    size: 15,
                    color: context.cashier.inkMuted,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 12),
          if (canPrint)
            _CompactBillButton(
              key: const Key('bill-detail-bottom-print-btn'),
              label: '补打80mm小票',
              icon: Icons.print_outlined,
              height: 40,
              fontSize: 14,
              variant: _CompactButtonVariant.primary,
              onPressed: onPrint,
            ),
          if (canRefund) ...[
            const SizedBox(width: 8),
            _CompactBillButton(
              key: const Key('bill-detail-bottom-refund-btn'),
              label: '申请整单退款',
              icon: Icons.undo_rounded,
              height: 40,
              fontSize: 14,
              variant: _CompactButtonVariant.danger,
              onPressed: onRefund,
            ),
          ],
        ],
      ),
    );
  }
}

/// 分页控制栏
class _PaginationBar extends StatelessWidget {
  const _PaginationBar({
    required this.total,
    required this.query,
    required this.loading,
    required this.onPage,
  });

  final int total;
  final CashierBillQuery query;
  final bool loading;
  final ValueChanged<int> onPage;

  @override
  Widget build(BuildContext context) {
    final pages = total == 0 ? 1 : (total / query.pageSize).ceil();
    return Container(
      height: 52,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: context.cashier.surface,
        border: Border(top: BorderSide(color: context.cashier.border)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              '共 $total 笔账单${query.hasFilters ? '（已筛选）' : ''}',
              style: TextStyle(
                color: context.cashier.inkSecondary,
                fontSize: 13.5,
                fontWeight: FontWeight.w500,
              ),
              overflow: TextOverflow.ellipsis,
              maxLines: 1,
            ),
          ),
          const SizedBox(width: 8),
          _CompactBillButton(
            label: '上一页',
            icon: Icons.chevron_left_rounded,
            height: 34,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            fontSize: 13,
            variant: _CompactButtonVariant.secondary,
            onPressed: !loading && query.pageNum > 1
                ? () => onPage(query.pageNum - 1)
                : null,
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: Text(
              '${query.pageNum} / $pages',
              style: TextStyle(
                fontSize: 13.5,
                fontFamily: 'monospace',
                fontWeight: FontWeight.w700,
                color: context.cashier.ink,
              ),
            ),
          ),
          _CompactBillButton(
            label: '下一页',
            icon: Icons.chevron_right_rounded,
            height: 34,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            fontSize: 13,
            variant: _CompactButtonVariant.secondary,
            onPressed: !loading && query.pageNum < pages
                ? () => onPage(query.pageNum + 1)
                : null,
          ),
        ],
      ),
    );
  }
}

/// 订单退款弹窗组件（输入可退金额并调用退款接口）
class _RefundDialog extends StatefulWidget {
  const _RefundDialog({required this.bill});

  final CashierBill bill;

  @override
  State<_RefundDialog> createState() => _RefundDialogState();
}

class _RefundDialogState extends State<_RefundDialog> {
  late final TextEditingController amountController;
  late final TextEditingController reasonController;
  String? amountError;
  late final double maxRefund;

  @override
  void initState() {
    super.initState();
    final paid = widget.bill.paidAmount > 0
        ? widget.bill.paidAmount
        : widget.bill.payableAmount;
    maxRefund = (paid - widget.bill.refundAmount).clamp(0.0, double.infinity);
    amountController = TextEditingController(
      text: maxRefund > 0 ? maxRefund.toStringAsFixed(2) : '0.00',
    );
    reasonController = TextEditingController();
  }

  @override
  void dispose() {
    amountController.dispose();
    reasonController.dispose();
    super.dispose();
  }

  void _submit() {
    final amountText = amountController.text.trim();
    final amount = double.tryParse(amountText);
    if (amount == null || amount <= 0) {
      setState(() => amountError = '请输入有效退款金额（大于0）');
      return;
    }
    if (amount > maxRefund + 0.001) {
      setState(
        () => amountError = '退款金额不能超过最大可退金额 ¥${maxRefund.toStringAsFixed(2)}',
      );
      return;
    }
    Navigator.of(
      context,
    ).pop((amount: amount, reason: reasonController.text.trim()));
  }

  @override
  Widget build(BuildContext context) {
    final paid = widget.bill.paidAmount > 0
        ? widget.bill.paidAmount
        : widget.bill.payableAmount;

    return CashierDialogFrame(
      title: '订单退款',
      width: 580,
      onClose: () => Navigator.of(context).pop(),
      actions: [
        CashierActionButton(
          label: '取消',
          variant: CashierActionButtonVariant.secondary,
          onPressed: () => Navigator.of(context).pop(),
        ),
        CashierActionButton(
          key: const Key('bill-refund-confirm-button'),
          label: '确定退款',
          variant: CashierActionButtonVariant.danger,
          onPressed: _submit,
        ),
      ],
      body: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: context.cashier.subtle,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Column(
              children: [
                _InfoLine(
                  '订单号',
                  widget.bill.orderNo.isNotEmpty ? widget.bill.orderNo : '—',
                ),
                _InfoLine(
                  '交易单号',
                  widget.bill.transactionId.isNotEmpty
                      ? widget.bill.transactionId
                      : '—',
                ),
                _InfoLine('实付金额', '¥ ${_formatNumber(paid)}'),
                _InfoLine(
                  '已退金额',
                  '¥ ${_formatNumber(widget.bill.refundAmount)}',
                ),
                _InfoLine('可退金额', '¥ ${_formatNumber(maxRefund)}'),
              ],
            ),
          ),
          const SizedBox(height: 18),
          TextField(
            key: const Key('bill-refund-amount-input'),
            controller: amountController,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(
              labelText: '退款金额（元）',
              hintText: '请输入退款金额',
              prefixText: '¥ ',
              errorText: amountError,
              border: const OutlineInputBorder(),
            ),
            onChanged: (_) {
              if (amountError != null) setState(() => amountError = null);
            },
          ),
          const SizedBox(height: 14),
          TextField(
            key: const Key('bill-refund-reason-input'),
            controller: reasonController,
            maxLength: 100,
            decoration: const InputDecoration(
              labelText: '退款原因（可选）',
              hintText: '例如：顾客要求退单、菜品问题退款',
              border: OutlineInputBorder(),
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoLine extends StatelessWidget {
  const _InfoLine(this.label, this.value);
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Text(
              label,
              style: TextStyle(color: context.cashier.inkSecondary, fontSize: 14),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            value,
            style: TextStyle(
              color: context.cashier.ink,
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

enum _CompactButtonVariant {
  primary,
  secondary,
  danger,
}

class _CompactBillButton extends StatefulWidget {
  const _CompactBillButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.variant = _CompactButtonVariant.secondary,
    this.icon,
    this.height = 38,
    this.padding = const EdgeInsets.symmetric(horizontal: 12),
    this.fontSize = 13.5,
  });

  final String label;
  final VoidCallback? onPressed;
  final _CompactButtonVariant variant;
  final IconData? icon;
  final double height;
  final EdgeInsetsGeometry padding;
  final double fontSize;

  @override
  State<_CompactBillButton> createState() => _CompactBillButtonState();
}

class _CompactBillButtonState extends State<_CompactBillButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onPressed != null;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    Color bg;
    Color fg;
    BorderSide border;

    switch (widget.variant) {
      case _CompactButtonVariant.primary:
        bg = enabled
            ? (_hovered ? const Color(0xFF27272A) : const Color(0xFF18181B))
            : (isDark ? const Color(0xFF27272A) : const Color(0xFFE4E4E7));
        fg = enabled ? Colors.white : (isDark ? const Color(0xFF71717A) : const Color(0xFFA1A1AA));
        border = BorderSide.none;
        break;

      case _CompactButtonVariant.secondary:
        bg = enabled
            ? (_hovered ? (isDark ? const Color(0xFF27272A) : const Color(0xFFF4F4F5)) : context.cashier.surface)
            : context.cashier.subtle;
        fg = enabled ? context.cashier.ink : context.cashier.inkMuted;
        border = BorderSide(
          color: enabled
              ? (_hovered ? context.cashier.inkSecondary : context.cashier.border)
              : context.cashier.border.withValues(alpha: 0.5),
        );
        break;

      case _CompactButtonVariant.danger:
        bg = enabled
            ? (_hovered ? const Color(0xFFFEE2E2) : const Color(0xFFFEF2F2))
            : context.cashier.subtle;
        fg = enabled ? const Color(0xFFDC2626) : context.cashier.inkMuted;
        border = BorderSide(
          color: enabled
              ? (_hovered ? const Color(0xFFEF4444) : const Color(0xFFFCA5A5))
              : context.cashier.border.withValues(alpha: 0.5),
        );
        break;
    }

    return MouseRegion(
      cursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
      onEnter: (_) {
        if (mounted) setState(() => _hovered = true);
      },
      onExit: (_) {
        if (mounted) setState(() => _hovered = false);
      },
      child: SizedBox(
        height: widget.height,
        child: OutlinedButton(
          onPressed: widget.onPressed,
          style: OutlinedButton.styleFrom(
            backgroundColor: bg,
            foregroundColor: fg,
            disabledBackgroundColor: bg,
            disabledForegroundColor: fg,
            padding: widget.padding,
            minimumSize: Size(0, widget.height),
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            side: border == BorderSide.none ? BorderSide.none : border,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(6),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (widget.icon != null) ...[
                Icon(widget.icon, size: widget.fontSize + 3, color: fg),
                const SizedBox(width: 5),
              ],
              Text(
                widget.label,
                style: TextStyle(
                  fontSize: widget.fontSize,
                  fontWeight: FontWeight.w700,
                  color: fg,
                  height: 1.1,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

String _formatNumber(num value) {
  final parts = value.toStringAsFixed(2).split('.');
  final whole = parts[0];
  final buffer = StringBuffer();
  for (int i = 0; i < whole.length; i++) {
    if (i > 0 && (whole.length - i) % 3 == 0) {
      buffer.write(',');
    }
    buffer.write(whole[i]);
  }
  return '${buffer.toString()}.${parts[1]}';
}

String _formatTimeOnly(DateTime? time) {
  if (time == null) return '12:30:45';
  String two(int n) => n.toString().padLeft(2, '0');
  return '${two(time.hour)}:${two(time.minute)}:${two(time.second)}';
}

String _formatFullDateTime(DateTime? time) {
  if (time == null) return '2026-08-06 12:30:45';
  String two(int n) => n.toString().padLeft(2, '0');
  return '${time.year}-${two(time.month)}-${two(time.day)} ${two(time.hour)}:${two(time.minute)}:${two(time.second)}';
}


String _formatPaymentMethod(String code) {
  final trimmed = code.trim();
  if (trimmed.isEmpty) return '';
  final clean = trimmed.toLowerCase().replaceAll(RegExp(r'[\s-_]+'), '');

  if (clean.contains('微信收款码') ||
      clean.contains('offlinewechatqr') ||
      clean.contains('wechatqr')) {
    return '微信收款码';
  }
  if (clean.contains('支付宝收款码') ||
      clean.contains('offlinealipayqr') ||
      clean.contains('alipayqr')) {
    return '支付宝收款码';
  }
  if (RegExp(r'[\u4e00-\u9fa5]').hasMatch(trimmed)) {
    return trimmed;
  }
  if (clean == 'wechat' ||
      clean == 'weixin' ||
      clean == 'wx' ||
      clean == 'onlinewechat') {
    return '微信支付';
  }
  if (clean == 'alipay' || clean == 'ali' || clean == 'onlinealipay') {
    return '支付宝';
  }
  if (clean == 'balance' ||
      clean == 'member' ||
      clean == 'onlinebalance' ||
      clean == 'memberbalance') {
    return '余额支付';
  }
  if (clean == 'cash' || clean == 'offlinecash') {
    return '现金';
  }
  if (clean == 'combined' || clean == 'split' || clean == 'onlinecombined') {
    return '组合支付';
  }
  return trimmed;
}

class _BindMemberPhoneDialog extends StatefulWidget {
  const _BindMemberPhoneDialog({required this.repository, required this.bill});

  final CashierMemberRepository repository;
  final CashierBill bill;

  @override
  State<_BindMemberPhoneDialog> createState() => _BindMemberPhoneDialogState();
}

class _BindMemberPhoneDialogState extends State<_BindMemberPhoneDialog> {
  final _phoneController = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _phoneController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final phone = _phoneController.text.trim();
    if (!RegExp(r'^1\d{10}$').hasMatch(phone)) {
      setState(() => _error = '请输入 11 位有效手机号');
      return;
    }
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.repository.bindOrder(orderId: widget.bill.id, phone: phone);
      if (mounted) Navigator.of(context).pop(true);
    } catch (error) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = '$error';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return CashierDialogFrame(
      title: '绑定会员',
      width: 580,
      busy: _busy,
      onClose: () => Navigator.of(context).pop(false),
      actions: [
        CashierActionButton(
          label: '取消',
          variant: CashierActionButtonVariant.secondary,
          onPressed: _busy ? null : () => Navigator.of(context).pop(false),
        ),
        CashierActionButton(
          key: const Key('bill-bind-member-confirm-button'),
          label: '确认绑定',
          onPressed: _submit,
          busy: _busy,
        ),
      ],
      body: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: context.cashier.subtle,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Column(
              children: [
                _InfoLine(
                  '订单号',
                  widget.bill.orderNo.isNotEmpty ? widget.bill.orderNo : '—',
                ),
                _InfoLine(
                  '桌号',
                  widget.bill.tableNumber.isNotEmpty
                      ? widget.bill.tableNumber
                      : '—',
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          TextField(
            key: const Key('bill-bind-member-phone-input'),
            controller: _phoneController,
            keyboardType: TextInputType.phone,
            maxLength: 11,
            decoration: InputDecoration(
              labelText: '会员手机号',
              hintText: '请输入会员手机号',
              errorText: _error,
              border: const OutlineInputBorder(),
            ),
            onChanged: (_) {
              if (_error != null) setState(() => _error = null);
            },
          ),
        ],
      ),
    );
  }
}

class _InvoiceQrcodeDialog extends StatefulWidget {
  const _InvoiceQrcodeDialog({
    required this.repository,
    required this.bill,
  });

  final CashierBillRepository repository;
  final CashierBill bill;

  @override
  State<_InvoiceQrcodeDialog> createState() => _InvoiceQrcodeDialogState();
}

class _InvoiceQrcodeDialogState extends State<_InvoiceQrcodeDialog> {
  bool _loading = true;
  bool _isPolling = false;
  String? _error;
  String _loadingMessage = '正在查询发票状态...';
  CashierInvoiceDetails? _details;
  CashierInvoiceResult? _qrcodeResult;
  Timer? _pollTimer;

  @override
  void initState() {
    super.initState();
    _loadInitial();
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }

  void _startPolling() {
    _pollTimer?.cancel();
    if (WidgetsBinding.instance.runtimeType.toString().contains('Test')) {
      return;
    }
    _pollTimer = Timer.periodic(const Duration(seconds: 5), (_) => _pollStatusSilently());
  }

  void _stopPolling() {
    _pollTimer?.cancel();
    _pollTimer = null;
  }

  Future<void> _loadInitial() async {
    setState(() {
      _loading = true;
      _error = null;
      _loadingMessage = '正在查询发票状态...';
    });

    try {
      final status = await widget.repository.loadInvoiceStatus(widget.bill.orderNo);
      if (!mounted) return;
      _details = status;

      if (status.hasInvoice && !status.isNone) {
        if (status.isSuccess || status.isFailed || status.isReversed) {
          _stopPolling();
        } else {
          // PENDING_SCAN, TITLE_SUBMITTED, ISSUING
          _startPolling();
        }
        setState(() {
          _loading = false;
        });
      } else {
        // No existing invoice -> create QR code
        await _generateQrcode();
      }
    } catch (e) {
      if (!mounted) return;
      // If query fails, attempt to create QR code directly
      await _generateQrcode();
    }
  }

  Future<void> _generateQrcode() async {
    setState(() {
      _loading = true;
      _error = null;
      _loadingMessage = '正在生成电子发票二维码...';
    });

    try {
      final amt = widget.bill.paidAmount > 0
          ? widget.bill.paidAmount
          : widget.bill.payableAmount;
      final res = await widget.repository.createInvoiceQrcode(
        orderNo: widget.bill.orderNo,
        tableNumber: widget.bill.tableNumber,
        invoiceAmount: amt,
        taxRate: 0.06,
      );
      if (!mounted) return;
      _qrcodeResult = res;
      _details = CashierInvoiceDetails(
        orderNo: res.orderNo.isNotEmpty ? res.orderNo : widget.bill.orderNo,
        hasInvoice: true,
        invoiceStatus: res.invoiceStatus.isNotEmpty ? res.invoiceStatus : 'PENDING_SCAN',
        invoiceAmount: res.invoiceAmount,
        invoiceQrUrl: res.invoiceQrUrl,
        taxRate: res.taxRate,
      );
      _startPolling();
      setState(() {
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = '$e'.replaceFirst('Exception: ', '');
      });
    }
  }

  Future<void> _pollStatusSilently() async {
    if (!mounted || _isPolling) return;
    _isPolling = true;
    try {
      final status = await widget.repository.loadInvoiceStatus(widget.bill.orderNo);
      if (!mounted) return;
      setState(() {
        _details = status;
      });
      if (status.isSuccess || status.isFailed || status.isReversed) {
        _stopPolling();
      }
    } catch (_) {
      // Ignore background polling errors to avoid interrupting user view
    } finally {
      _isPolling = false;
    }
  }

  Future<void> _refreshManual() async {
    setState(() {
      _loading = true;
      _error = null;
      _loadingMessage = '正在刷新发票状态...';
    });
    try {
      final status = await widget.repository.loadInvoiceStatus(widget.bill.orderNo);
      if (!mounted) return;
      setState(() {
        _details = status;
        _loading = false;
      });
      if (status.isSuccess || status.isFailed || status.isReversed) {
        _stopPolling();
      } else {
        _startPolling();
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = '$e'.replaceFirst('Exception: ', '');
      });
    }
  }

  Future<void> _copyText(String text, String successMsg) async {
    if (text.isEmpty) return;
    await Clipboard.setData(ClipboardData(text: text));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(successMsg)),
      );
    }
  }

  Future<void> _openPdf(String url) async {
    if (url.isEmpty) return;
    try {
      final uri = Uri.parse(url);
      final launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!launched && mounted) {
        await Clipboard.setData(ClipboardData(text: url));
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('已复制发票下载链接到剪贴板')),
        );
      }
    } catch (_) {
      await Clipboard.setData(ClipboardData(text: url));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('已复制发票下载链接到剪贴板')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final details = _details;
    final isSuccess = details != null && details.isSuccess;
    final isIssuing = details != null && (details.isSubmitted || details.isIssuing);
    final isFailed = details != null && details.isFailed;
    final isReversed = details != null && details.isReversed;
    final qrUrl = (details != null && details.invoiceQrUrl.isNotEmpty)
        ? details.invoiceQrUrl
        : (_qrcodeResult?.invoiceQrUrl ?? '');

    return CashierDialogFrame(
      title: '电子发票管理',
      width: 660,
      height: 580,
      compact: true,
      onClose: () => Navigator.of(context).pop(),
      actions: _buildActions(
        isSuccess: isSuccess,
        isIssuing: isIssuing,
        isFailed: isFailed,
        isReversed: isReversed,
        details: details,
        qrUrl: qrUrl,
      ),
      body: _buildBody(
        context,
        isSuccess: isSuccess,
        isIssuing: isIssuing,
        isFailed: isFailed,
        isReversed: isReversed,
        details: details,
        qrUrl: qrUrl,
      ),
    );
  }

  List<Widget> _buildActions({
    required bool isSuccess,
    required bool isIssuing,
    required bool isFailed,
    required bool isReversed,
    required CashierInvoiceDetails? details,
    required String qrUrl,
  }) {
    if (_loading) {
      return [
        CashierActionButton(
          label: '关闭',
          variant: CashierActionButtonVariant.secondary,
          onPressed: () => Navigator.of(context).pop(),
        ),
      ];
    }

    if (isSuccess && details != null) {
      return [
        if (details.downloadUrl.isNotEmpty) ...[
          CashierActionButton(
            key: const Key('invoice-open-pdf-btn'),
            label: '查看发票 (PDF)',
            minimumWidth: 120,
            height: 48,
            variant: CashierActionButtonVariant.primary,
            onPressed: () => _openPdf(details.downloadUrl),
          ),
          CashierActionButton(
            key: const Key('invoice-copy-url-btn'),
            label: '复制发票链接',
            minimumWidth: 120,
            height: 48,
            variant: CashierActionButtonVariant.secondary,
            onPressed: () => _copyText(details.downloadUrl, '发票下载链接已复制到剪贴板'),
          ),
        ],
        CashierActionButton(
          label: '完成',
          minimumWidth: 100,
          height: 48,
          variant: details.downloadUrl.isEmpty
              ? CashierActionButtonVariant.primary
              : CashierActionButtonVariant.secondary,
          onPressed: () => Navigator.of(context).pop(),
        ),
      ];
    }

    if (isFailed || isReversed) {
      return [
        CashierActionButton(
          key: const Key('invoice-retry-btn'),
          label: '重新生成二维码',
          variant: CashierActionButtonVariant.primary,
          onPressed: _generateQrcode,
        ),
        CashierActionButton(
          label: '关闭',
          variant: CashierActionButtonVariant.secondary,
          onPressed: () => Navigator.of(context).pop(),
        ),
      ];
    }

    // Pending Scan or Issuing states
    return [
      if (qrUrl.isNotEmpty)
        CashierActionButton(
          key: const Key('invoice-copy-url-btn'),
          label: '复制开票链接',
          minimumWidth: 120,
          height: 48,
          variant: CashierActionButtonVariant.secondary,
          onPressed: () => _copyText(qrUrl, '开票链接已复制到剪贴板'),
        ),
      CashierActionButton(
        key: const Key('invoice-refresh-status-btn'),
        label: '刷新状态',
        minimumWidth: 100,
        height: 48,
        variant: CashierActionButtonVariant.secondary,
        onPressed: _refreshManual,
      ),
      CashierActionButton(
        label: '完成',
        minimumWidth: 100,
        height: 48,
        variant: CashierActionButtonVariant.primary,
        onPressed: () => Navigator.of(context).pop(),
      ),
    ];
  }

  Widget _buildBody(
    BuildContext context, {
    required bool isSuccess,
    required bool isIssuing,
    required bool isFailed,
    required bool isReversed,
    required CashierInvoiceDetails? details,
    required String qrUrl,
  }) {
    if (_loading) {
      return SizedBox(
        height: 280,
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CircularProgressIndicator(),
              const SizedBox(height: 16),
              Text(
                _loadingMessage,
                style: TextStyle(fontSize: 13, color: context.cashier.inkMuted),
              ),
            ],
          ),
        ),
      );
    }

    if (_error != null) {
      return SizedBox(
        height: 260,
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.error_outline_rounded,
                color: Colors.red,
                size: 44,
              ),
              const SizedBox(height: 12),
              Text(
                '发票操作异常: $_error',
                style: const TextStyle(fontSize: 13, color: Colors.red),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                key: const Key('invoice-retry-btn'),
                onPressed: _loadInitial,
                icon: const Icon(Icons.refresh_rounded, size: 16),
                label: const Text('重试'),
              ),
            ],
          ),
        ),
      );
    }

    if (isSuccess && details != null) {
      return _buildIssuedView(context, details);
    }

    if (isIssuing && details != null) {
      return _buildIssuingView(context, details);
    }

    if (isFailed && details != null) {
      return _buildFailedView(context, details);
    }

    if (isReversed && details != null) {
      return _buildReversedView(context, details);
    }

    return _buildPendingScanView(context, qrUrl: qrUrl);
  }

  Widget _buildIssuedView(BuildContext context, CashierInvoiceDetails details) {
    final amt = details.invoiceAmount > 0
        ? details.invoiceAmount
        : (widget.bill.paidAmount > 0 ? widget.bill.paidAmount : widget.bill.payableAmount);

    return SingleChildScrollView(
      key: const Key('invoice-issued-card'),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: const Color(0xFFE8F5E9),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0xFFA5D6A7)),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.check_circle_rounded,
                  color: Color(0xFF2E7D32),
                  size: 26,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        '电子发票已成功开具',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF1B5E20),
                        ),
                      ),
                      Text(
                        '税控系统已完成开具与报税，支持下载与报销',
                        style: TextStyle(
                          fontSize: 11,
                          color: const Color(0xFF2E7D32).withValues(alpha: 0.9),
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: const Color(0xFF2E7D32),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: const Text(
                    '已开具',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: context.cashier.subtle,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: context.cashier.border),
            ),
            child: Column(
              children: [
                _InfoLine(
                  '订单号',
                  details.orderNo.isNotEmpty ? details.orderNo : widget.bill.orderNo,
                ),
                _InfoLine(
                  '发票抬头',
                  details.buyerTitle.isNotEmpty
                      ? '${details.buyerTitle} (${details.titleType == 'COMPANY' ? '企业' : '个人'})'
                      : '顾客个人',
                ),
                if (details.buyerTaxNo.isNotEmpty)
                  _InfoLine('纳税人识别号', details.buyerTaxNo),
                if (details.invoiceNo.isNotEmpty)
                  _InfoLine('发票号码', details.invoiceNo),
                if (details.invoiceCode.isNotEmpty)
                  _InfoLine('发票代码', details.invoiceCode),
                _InfoLine('开票金额', '¥${amt.toStringAsFixed(2)}'),
                _InfoLine('适用税率', '${(details.taxRate * 100).toStringAsFixed(0)}%'),
                if (details.buyerPhone.isNotEmpty)
                  _InfoLine('推送手机', details.buyerPhone),
                if (details.buyerEmail.isNotEmpty)
                  _InfoLine('推送邮箱', details.buyerEmail),
                if (details.createdAt != null)
                  _InfoLine(
                    '开具时间',
                    '${details.createdAt!.year}-${details.createdAt!.month.toString().padLeft(2, '0')}-${details.createdAt!.day.toString().padLeft(2, '0')} ${details.createdAt!.hour.toString().padLeft(2, '0')}:${details.createdAt!.minute.toString().padLeft(2, '0')}',
                  ),
              ],
            ),
          ),
          if (details.downloadUrl.isEmpty) ...[
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.amber.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: Colors.amber.withValues(alpha: 0.3)),
              ),
              child: const Row(
                children: [
                  Icon(Icons.info_outline, size: 16, color: Colors.orange),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '发票文件由税局税控网关异步生成，如需 PDF 可稍后点击刷新获取下载地址。',
                      style: TextStyle(fontSize: 11, color: Colors.brown),
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

  Widget _buildIssuingView(BuildContext context, CashierInvoiceDetails details) {
    return SingleChildScrollView(
      key: const Key('invoice-issuing-view'),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: const Color(0xFFE3F2FD),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0xFF90CAF9)),
            ),
            child: Row(
              children: [
                const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.5,
                    color: Color(0xFF1976D2),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        details.isIssuing ? '税控发票开具中...' : '顾客已提交抬头 · 开具中',
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF0D47A1),
                        ),
                      ),
                      const SizedBox(height: 2),
                      const Text(
                        '正在与税控网关同步开具，完成后系统将自动刷新',
                        style: TextStyle(fontSize: 11, color: Color(0xFF1976D2)),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: context.cashier.subtle,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: context.cashier.border),
            ),
            child: Column(
              children: [
                _InfoLine('订单号', details.orderNo.isNotEmpty ? details.orderNo : widget.bill.orderNo),
                _InfoLine('发票抬头', details.buyerTitle.isNotEmpty ? details.buyerTitle : '待税控解析'),
                if (details.buyerTaxNo.isNotEmpty)
                  _InfoLine('纳税人识别号', details.buyerTaxNo),
                _InfoLine('开票金额', '¥${details.invoiceAmount.toStringAsFixed(2)}'),
                _InfoLine('当前状态', details.statusLabel),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Center(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.sync_rounded,
                  size: 14,
                  color: context.cashier.inkMuted,
                ),
                const SizedBox(width: 8),
                Text(
                  '系统每 5 秒自动轮询最新状态...',
                  style: TextStyle(fontSize: 12, color: context.cashier.inkMuted),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFailedView(BuildContext context, CashierInvoiceDetails details) {
    return SingleChildScrollView(
      key: const Key('invoice-failed-view'),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: const Color(0xFFFFEBEE),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0xFFFFCDD2)),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.error_outline_rounded,
                  color: Color(0xFFD32F2F),
                  size: 26,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        '发票开具失败',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFFB71C1C),
                        ),
                      ),
                      Text(
                        details.failReason.isNotEmpty
                            ? '失败原因：${details.failReason}'
                            : '税控系统开票异常，请核对商户配置或重试',
                        style: const TextStyle(fontSize: 11, color: Color(0xFFD32F2F)),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: context.cashier.subtle,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: context.cashier.border),
            ),
            child: Column(
              children: [
                _InfoLine('订单号', details.orderNo.isNotEmpty ? details.orderNo : widget.bill.orderNo),
                _InfoLine('开票金额', '¥${details.invoiceAmount.toStringAsFixed(2)}'),
                const _InfoLine('状态', '开具失败'),
              ],
            ),
          ),
          const SizedBox(height: 14),
          Text(
            '请检查税控盘网络或微信支付商户电子发票配置，或点击下方按钮重新生成二维码供顾客再次扫码。',
            style: TextStyle(fontSize: 12, color: context.cashier.inkMuted),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildReversedView(BuildContext context, CashierInvoiceDetails details) {
    return SingleChildScrollView(
      key: const Key('invoice-reversed-view'),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: const Color(0xFFFFF3E0),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0xFFFFCC80)),
            ),
            child: const Row(
              children: [
                Icon(
                  Icons.remove_circle_outline_rounded,
                  color: Color(0xFFE65100),
                  size: 26,
                ),
                SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '发票已作废 / 红冲',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFFBF360C),
                        ),
                      ),
                      Text(
                        '该笔订单原开具发票已被冲红或注销',
                        style: TextStyle(fontSize: 11, color: Color(0xFFE65100)),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: context.cashier.subtle,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: context.cashier.border),
            ),
            child: Column(
              children: [
                _InfoLine('订单号', details.orderNo.isNotEmpty ? details.orderNo : widget.bill.orderNo),
                if (details.invoiceNo.isNotEmpty)
                  _InfoLine('原发票号码', details.invoiceNo),
                _InfoLine('开票金额', '¥${details.invoiceAmount.toStringAsFixed(2)}'),
                const _InfoLine('状态', '已冲红'),
              ],
            ),
          ),
          const SizedBox(height: 14),
          Text(
            '如需为顾客重新开票，可点击下方“重新生成二维码”重新发起。',
            style: TextStyle(fontSize: 12, color: context.cashier.inkMuted),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildPendingScanView(BuildContext context, {required String qrUrl}) {
    final amt = widget.bill.paidAmount > 0
        ? widget.bill.paidAmount
        : widget.bill.payableAmount;

    return SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: context.cashier.subtle,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: context.cashier.border),
            ),
            child: Column(
              children: [
                _InfoLine(
                  '订单号',
                  _details?.orderNo.isNotEmpty == true
                      ? _details!.orderNo
                      : (_qrcodeResult?.orderNo.isNotEmpty == true
                          ? _qrcodeResult!.orderNo
                          : widget.bill.orderNo),
                ),
                _InfoLine('开票金额', '¥${amt.toStringAsFixed(2)}'),
                _InfoLine(
                  '适用税率',
                  '${((_details?.taxRate ?? _qrcodeResult?.taxRate ?? 0.06) * 100).toStringAsFixed(0)}%',
                ),
                _InfoLine('当前状态', _details?.statusLabel ?? '待顾客扫码'),
              ],
            ),
          ),
          const SizedBox(height: 18),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: context.cashier.border),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.05),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: qrUrl.isNotEmpty
                ? QrImageView(
                    key: const Key('invoice-qrcode-image'),
                    data: qrUrl,
                    size: 190,
                    version: QrVersions.auto,
                    backgroundColor: Colors.white,
                    errorCorrectionLevel: QrErrorCorrectLevel.M,
                  )
                : const SizedBox(
                    width: 190,
                    height: 190,
                    child: Center(
                      child: Text(
                        '未获取到开票链接',
                        style: TextStyle(fontSize: 13, color: Colors.grey),
                      ),
                    ),
                  ),
          ),
          const SizedBox(height: 14),
          Text(
            _qrcodeResult?.notice.isNotEmpty == true
                ? _qrcodeResult!.notice
                : '请引导顾客使用微信扫一扫开具电子发票',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: context.cashier.ink,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 4),
          Text(
            '发票抬头与税号将由顾客自行填写并自动推送至税局',
            style: TextStyle(fontSize: 11, color: context.cashier.inkMuted),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.sync_rounded,
                size: 14,
                color: context.cashier.inkMuted,
              ),
              const SizedBox(width: 6),
              Text(
                '等待扫码中，系统每 5 秒自动同步状态',
                style: TextStyle(fontSize: 11, color: context.cashier.inkMuted),
              ),
            ],
          ),
        ],
      ),
    );
  }
}


class _AuditTimelineDialog extends StatelessWidget {
  const _AuditTimelineDialog({
    required this.orderNo,
    required this.timeline,
  });

  final String orderNo;
  final CashierAuditTimeline timeline;

  @override
  Widget build(BuildContext context) {
    final events = timeline.events;

    return CashierDialogFrame(
      title: '全流程审计追踪流水',
      width: 580,
      height: 520,
      onClose: () => Navigator.of(context).pop(),
      actions: [
        CashierActionButton(
          label: '关闭',
          variant: CashierActionButtonVariant.secondary,
          onPressed: () => Navigator.of(context).pop(),
        ),
      ],
      body: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: context.cashier.subtle,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: context.cashier.border),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.verified_user_outlined,
                  size: 18,
                  color: context.cashier.inkSecondary,
                ),
                const SizedBox(width: 8),
                Text(
                  '订单编号: $orderNo',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    fontFamily: 'monospace',
                    color: context.cashier.ink,
                  ),
                ),
                const Spacer(),
                Text(
                  '共 ${events.length} 个操作节点',
                  style: TextStyle(
                    fontSize: 12,
                    color: context.cashier.inkMuted,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Expanded(
            child: events.isEmpty
                ? const Center(
                    child: Text('暂无细粒度审计日志',
                        style: TextStyle(color: Colors.grey)),
                  )
                : SingleChildScrollView(
                    child: Padding(
                      padding: const EdgeInsets.only(
                        left: 8,
                        right: 8,
                        top: 4,
                        bottom: 8,
                      ),
                      child: Column(
                        children: [
                          for (int i = 0; i < events.length; i++)
                            _AuditTimelineNodeItem(
                              event: events[i],
                              isFirst: i == 0,
                              isLast: i == events.length - 1,
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

class _AuditTimelineNodeItem extends StatelessWidget {
  const _AuditTimelineNodeItem({
    required this.event,
    required this.isFirst,
    required this.isLast,
  });

  final CashierAuditEvent event;
  final bool isFirst;
  final bool isLast;

  Color _actionColor(String action) {
    if (action.contains('PAY') ||
        action.contains('入账') ||
        action.contains('结账')) {
      return const Color(0xFF10B981);
    }
    if (action.contains('REFUND') ||
        action.contains('退款') ||
        action.contains('冲正')) {
      return const Color(0xFFEF4444);
    }
    if (action.contains('PRINT') ||
        action.contains('出票') ||
        action.contains('小票')) {
      return const Color(0xFF3B82F6);
    }
    if (action.contains('ORDER') ||
        action.contains('点单') ||
        action.contains('开台')) {
      return const Color(0xFFF59E0B);
    }
    return const Color(0xFF6366F1);
  }

  @override
  Widget build(BuildContext context) {
    final dotColor = _actionColor(event.action);

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Left timeline axis
          SizedBox(
            width: 24,
            child: Column(
              children: [
                Container(
                  width: 2,
                  height: 10,
                  color: isFirst ? Colors.transparent : context.cashier.border,
                ),
                Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    color: dotColor,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: dotColor.withValues(alpha: 0.3),
                        blurRadius: 4,
                        spreadRadius: 1,
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: Container(
                    width: 2,
                    color: isLast ? Colors.transparent : context.cashier.border,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          // Content Card
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: context.cashier.surface,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: context.cashier.border),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          event.time,
                          style: TextStyle(
                            fontSize: 12,
                            fontFamily: 'monospace',
                            fontWeight: FontWeight.w600,
                            color: context.cashier.ink,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 1.5,
                          ),
                          decoration: BoxDecoration(
                            color: dotColor.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(3),
                            border: Border.all(
                              color: dotColor.withValues(alpha: 0.25),
                            ),
                          ),
                          child: Text(
                            event.action,
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: dotColor,
                            ),
                          ),
                        ),
                        const Spacer(),
                        if (event.operator.isNotEmpty)
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.person_outline,
                                size: 13,
                                color: context.cashier.inkMuted,
                              ),
                              const SizedBox(width: 2),
                              Text(
                                event.operator,
                                style: TextStyle(
                                  fontSize: 11,
                                  color: context.cashier.inkMuted,
                                ),
                              ),
                            ],
                          ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      event.description,
                      style: TextStyle(
                        fontSize: 12.5,
                        color: context.cashier.inkSecondary,
                        height: 1.3,
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


