import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../auth/data/access_approval_repository.dart';
import '../../auth/domain/access_approval_models.dart';
import '../../cashier_member/data/cashier_member_repository.dart';
import '../../cashier_member/presentation/member_consumption_dialog.dart';
import '../../cashier_shell/presentation/cashier_approval_dialog.dart';
import '../../cashier_shell/presentation/cashier_tokens.dart';
import '../../../core/crash_log.dart';
import '../../tables/domain/dining_table.dart';
import '../data/pending_external_checkout_store.dart';
import '../data/pending_order_submission_store.dart';
import '../data/pos_repository.dart';
import '../domain/pos_models.dart';
import 'occupied_table_view.dart';
import 'order_checkout_dialog.dart';
import 'order_discount_dialog.dart';
import 'pos_hang_order_dialog.dart';
import 'pos_notice_dialog.dart';
import 'pos_update_diners_dialog.dart';
import 'pos_ordering_view.dart';
import 'pos_raw_print_result_dialog.dart';
import 'refund_dish_dialog.dart';
import 'wechat_micropay_checkout_dialog.dart';
import 'wechat_native_checkout_dialog.dart';
import 'receivable_charge_dialog.dart';
import '../../../core/admin_api_client.dart';
import '../../cashier_shift/data/cashier_shift_repository.dart';
import '../../tables/data/table_repository.dart';
import 'pos_dining_mode_dialog.dart';

class TableOrderPage extends StatefulWidget {
  const TableOrderPage({
    super.key,
    required this.table,
    required this.repository,
    required this.approvalRepository,
    this.tableRepository,
    this.onCompleted,
    this.pickupOrder = false,
    this.initiallyOpened = false,
    this.memberRepository,
    this.shiftRepository,
    this.pendingExternalCheckoutStore,
    this.pendingOrderSubmissionStore,
    this.initialWorkspace,
    this.checkoutOnly = false,
    this.fulfillmentTitle,
    this.currentAccount,
    this.onLogout,
    this.onBack,
  });

  final DiningTable table;
  final PosRepository repository;
  final TableRepository? tableRepository;

  /// 权限中心审批仓库：敏感操作统一走店长现场授权（签发一次性审批令牌）。
  final AccessApprovalRepository approvalRepository;
  final VoidCallback? onCompleted;
  final bool pickupOrder;
  final bool initiallyOpened;
  final CashierMemberRepository? memberRepository;
  final CashierShiftRepository? shiftRepository;
  final PendingExternalCheckoutStore? pendingExternalCheckoutStore;
  final PendingOrderSubmissionStore? pendingOrderSubmissionStore;
  final PosWorkspace? initialWorkspace;
  final bool checkoutOnly;
  final String? fulfillmentTitle;
  final String? currentAccount;
  final VoidCallback? onLogout;
  final VoidCallback? onBack;

  @override
  State<TableOrderPage> createState() => _TableOrderPageState();
}

class _TableOrderPageState extends State<TableOrderPage> {
  static const _collectionSessionRandomBound = 0x100000000;

  static String _newCollectionSessionId() =>
      '${DateTime.now().microsecondsSinceEpoch}-${math.Random.secure().nextInt(_collectionSessionRandomBound)}';

  static String _newSubmissionRequestId() =>
      'cashier-order-${DateTime.now().microsecondsSinceEpoch}-${math.Random.secure().nextInt(_collectionSessionRandomBound)}';

  static String _newAddDishesRequestId() =>
      'cashier-add-dishes-${DateTime.now().microsecondsSinceEpoch}-${math.Random.secure().nextInt(_collectionSessionRandomBound)}';

  final horizontalController = ScrollController();
  final verticalController = ScrollController();
  PosWorkspace? workspace;
  Object? error;
  bool loading = true;
  bool submitting = false;
  bool addingDishes = false;
  PosOrder? addingDishesTargetOrder;
  bool tableOpened = false;
  bool openingPromptScheduled = false;
  String? pendingExternalOrderNo;
  PosCheckoutSettlement? pendingCombinedSettlement;
  String? pendingOfflineChannel;
  Set<String> pendingConfirmedChannels = const <String>{};
  bool pendingCombinedReady = false;
  bool orderAmountsFresh = true;
  bool allowingPagePop = false;
  bool pagePopInProgress = false;
  bool _isDrawerOpen = true;
  String collectionSessionId = _newCollectionSessionId();
  late final PendingExternalCheckoutStore pendingCheckoutStore;
  late final PendingOrderSubmissionStore pendingSubmissionStore;
  int _orderingSessionIndex = 0;

  @override
  void initState() {
    super.initState();
    tableOpened =
        widget.pickupOrder ||
        widget.initiallyOpened ||
        widget.table.isOccupied ||
        widget.table.number.trim().isEmpty;
    pendingCheckoutStore =
        widget.pendingExternalCheckoutStore ??
        createPendingExternalCheckoutStore();
    pendingSubmissionStore =
        widget.pendingOrderSubmissionStore ??
        createPendingOrderSubmissionStore();
    final initialWorkspace = widget.initialWorkspace;
    if (initialWorkspace == null) {
      _initialize();
    } else {
      workspace = initialWorkspace;
      loading = false;
      tableOpened = true;
      unawaited(_restorePendingCheckout(initialWorkspace));
    }
    unawaited(_checkDrawerState());
  }

  Future<void> _checkDrawerState() async {
    final shiftRepo = widget.shiftRepository;
    if (shiftRepo == null) return;
    try {
      final shift = await shiftRepo.loadCurrentShift();
      if (mounted) {
        setState(() {
          _isDrawerOpen = shift != null && shift.isOpen;
        });
      }
    } catch (_) {}
  }

  Future<bool> _promptStartShift() async {
    final controller = TextEditingController(text: '0.00');
    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text(
          '录入初始备用金并开班',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '请输入当前钱箱的初始备用金金额（元）：',
              style: TextStyle(fontSize: 14, color: Color(0xff475569)),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              autofocus: true,
              decoration: const InputDecoration(
                prefixText: '¥ ',
                border: OutlineInputBorder(),
                hintText: '0.00',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('取消'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xff2563eb),
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('确定开班'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return false;
    final amount = double.tryParse(controller.text.trim()) ?? 0.0;
    try {
      if (widget.shiftRepository != null) {
        await widget.shiftRepository!.startShift(startCash: amount);
      }
      if (mounted) {
        setState(() => _isDrawerOpen = true);
        await showPosNotice(
          context,
          title: '开班成功',
          message:
              '钱箱开班已完成，初始备用金 ¥${amount.toStringAsFixed(2)} 已录入。现在可以进行现金结账。',
          tone: PosNoticeTone.success,
        );
      }
      return true;
    } catch (e) {
      if (mounted) {
        await showPosNotice(
          context,
          title: '开班失败',
          message: '$e',
          tone: PosNoticeTone.error,
        );
      }
      return false;
    }
  }

  Future<bool> _showDrawerUnopenedDialog() async {
    final startShiftNow = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: const Color(0xfffef3c7),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(
                Icons.lock_clock_outlined,
                color: Color(0xffd97706),
                size: 24,
              ),
            ),
            const SizedBox(width: 12),
            const Text(
              '钱箱未开班',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
            ),
          ],
        ),
        content: const Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '现金结算拦截 (Code: 4002)',
              style: TextStyle(
                fontSize: 12,
                color: Color(0xffd97706),
                fontWeight: FontWeight.w600,
              ),
            ),
            SizedBox(height: 8),
            Text(
              '开启了班次钱箱管理的门店，必须先开班录入初始备用金，才能进行现金收款。',
              style: TextStyle(fontSize: 14, color: Color(0xff475569)),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('取消', style: TextStyle(color: Color(0xff64748b))),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xff2563eb),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('立即开班'),
          ),
        ],
      ),
    );
    if (startShiftNow != true || !mounted) return false;
    return _promptStartShift();
  }

  Future<void> _restorePendingCheckout(PosWorkspace initialWorkspace) async {
    final orderNo = initialWorkspace.currentOrder?.orderNo;
    if (orderNo == null) return;
    final pending = await pendingCheckoutStore.read(orderNo);
    if (!mounted || pending == null) return;
    setState(() {
      pendingExternalOrderNo = pending.orderNo;
      pendingCombinedSettlement = pending.combinedSettlement;
      pendingOfflineChannel = pending.offlineChannel;
      pendingConfirmedChannels = pending.confirmedChannels;
      pendingCombinedReady = pending.readyForSubmission;
      if (pending.collectionSessionId.isNotEmpty) {
        collectionSessionId = pending.collectionSessionId;
      }
    });
  }

  Future<void> _initialize() async {
    await _load();
  }

  @override
  void dispose() {
    horizontalController.dispose();
    verticalController.dispose();
    super.dispose();
  }

  Future<void> _load({bool forceOrder = false}) async {
    var shouldRequestOpening = false;
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final value = await widget.repository.loadWorkspace(
        forceOrder
            ? widget.table.copyWith(status: TableStatus.pending)
            : widget.table,
      );
      final orderNo = value.currentOrder?.orderNo;
      final pending = orderNo == null
          ? null
          : await pendingCheckoutStore.read(orderNo);
      if (mounted) {
        setState(() {
          // 下单成功后的强制重载：仅当云端确实返回了订单时才覆盖本地刚构造的
          // 临时明细，避免拉取失败/未返回时明细页被顶回下单页。
          if (!forceOrder || value.currentOrder != null) {
            workspace = value;
          }
          pendingExternalOrderNo = pending?.orderNo;
          pendingCombinedSettlement = pending?.combinedSettlement;
          pendingOfflineChannel = pending?.offlineChannel;
          pendingConfirmedChannels =
              pending?.confirmedChannels ?? const <String>{};
          pendingCombinedReady = pending?.readyForSubmission ?? false;
          if (pending != null && pending.collectionSessionId.isNotEmpty) {
            collectionSessionId = pending.collectionSessionId;
          }
          orderAmountsFresh = true;
          if (widget.pickupOrder ||
              value.table.isOccupied ||
              value.currentOrder != null ||
              widget.table.number.trim().isEmpty) {
            tableOpened = true;
          }
        });
        shouldRequestOpening =
            !widget.pickupOrder &&
            !tableOpened &&
            widget.table.number.trim().isNotEmpty &&
            value.currentOrder == null &&
            !openingPromptScheduled;
      }
    } catch (exception, stackTrace) {
      CrashLog.instance.write('ERROR', '点餐工作台加载异常: $exception', stackTrace);
      if (mounted) setState(() => error = exception);
    } finally {
      if (mounted) setState(() => loading = false);
    }
    if (mounted && shouldRequestOpening) {
      openingPromptScheduled = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _confirmAndOpenTable();
      });
    }
  }

  Future<void> _showMemberHistory() async {
    final repository = widget.memberRepository;
    final phone = workspace?.currentOrder?.memberPhone.trim() ?? '';
    if (repository == null || phone.isEmpty || !mounted) return;
    await showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (_) =>
          MemberConsumptionDialog(phone: phone, repository: repository),
    );
  }

  Future<void> _confirmAndOpenTable() async {
    final confirmed = await showPosNotice(
      context,
      title: '是否开台',
      message: '确认开启 ${widget.table.number}号桌并进入点菜界面？',
      tone: PosNoticeTone.info,
      primaryLabel: '开台',
      secondaryLabel: '取消',
    );
    if (!mounted) return;
    if (!confirmed) {
      if (Navigator.of(context).canPop()) Navigator.of(context).pop();
      return;
    }
    setState(() => submitting = true);
    try {
      await widget.repository.openTable(widget.table.number);
      if (!mounted) return;
      setState(() => tableOpened = true);
    } catch (exception, stackTrace) {
      CrashLog.instance.write('ERROR', '开台异常: $exception', stackTrace);
      if (!mounted) return;
      await showPosNotice(
        context,
        title: '开台失败',
        message: '$exception',
        tone: PosNoticeTone.error,
      );
      openingPromptScheduled = false;
    } finally {
      if (mounted) setState(() => submitting = false);
    }
  }

  Future<void> _submit({
    required int diners,
    required String remark,
    required List<PosCartLine> lines,
  }) async {
    if (submitting) return;
    if (lines.isEmpty) {
      await showPosNotice(
        context,
        title: '未选择菜品',
        message: '购物车为空，请先选择菜品再提交。',
        tone: PosNoticeTone.warning,
      );
      return;
    }
    if (widget.table.number.trim().isEmpty && !widget.pickupOrder) {
      await _handleNoTableSubmission(
        diners: diners,
        remark: remark,
        lines: lines,
      );
      return;
    }
    if (!tableOpened) {
      await showPosNotice(
        context,
        title: '尚未开台',
        message: '请先完成开台，再提交菜品。',
        tone: PosNoticeTone.warning,
      );
      return;
    }
    setState(() => submitting = true);
    CrashLog.instance.recordBreadcrumb(
      category: 'order',
      message:
          '开始下单: 桌台=${widget.table.number}, 人数=$diners, 菜品数=${lines.length}',
      data: {
        'table': widget.table.number,
        'diners': diners,
        'lines_count': lines.length,
        'pickup': widget.pickupOrder,
      },
    );
    try {
      final fingerprint = jsonEncode({
        'pickup': widget.pickupOrder,
        'table_number': widget.table.number,
        'diners': diners,
        'remark': remark,
        'lines': lines.map((line) => line.requestBody()).toList(),
      });
      final submissionScope = widget.pickupOrder
          ? 'pickup'
          : 'table-${widget.table.number}';
      final requestId = await pendingSubmissionStore.resolve(
        scope: submissionScope,
        fingerprint: fingerprint,
        generate: _newSubmissionRequestId,
      );
      PosSubmissionResult result;
      if (widget.pickupOrder) {
        final repository = widget.repository;
        if (repository is! PosPickupOrderRepository) {
          throw UnsupportedError('当前收银接口不支持自提打包下单');
        }
        result = await (repository as PosPickupOrderRepository)
            .submitPickupOrder(
              remark: remark,
              lines: lines,
              clientRequestId: requestId,
            );
      } else {
        result = await widget.repository.submitOrder(
          tableNumber: widget.table.number,
          diners: diners,
          remark: remark,
          lines: lines,
          clientRequestId: requestId,
        );
      }
      await pendingSubmissionStore.clear(submissionScope);
      if (!mounted) return;
      if (widget.pickupOrder) {
        final current = workspace!;
        final total = lines.fold<double>(0, (sum, line) => sum + line.total);
        final packagingFee = total <= 0 ? 0 : (total / 100).ceilToDouble();
        setState(() {
          workspace = PosWorkspace(
            table: const DiningTable(
              number: '打包',
              status: TableStatus.pending,
              people: 1,
            ),
            categories: current.categories,
            dishes: current.dishes,
            paymentMethods: current.paymentMethods,
            currentOrder: PosOrder(
              id: result.id,
              orderNo: result.orderNo,
              tableNumber: '打包',
              diners: 1,
              total: total + packagingFee,
              grossAmount: total + packagingFee,
              createdAt: DateTime.now(),
              lines: [
                if (result.hasFormalOrderDetails)
                  for (final detail in result.orderDetails)
                    PosOrderLine(
                      id: detail.detailId,
                      name: detail.name,
                      quantity: detail.quantity,
                      total:
                          (detail.raw['total_price'] as num?)?.toDouble() ??
                          0.0,
                      unit: detail.unit,
                      specification: '${detail.raw['specification'] ?? ''}',
                      refunded: false,
                      kdsStatusText: result.cloudAcceptanceStatus.isNotEmpty
                          ? result.cloudAcceptanceStatus
                          : (detail.remainingQuantity > 0 ? '待确认' : ''),
                    )
                else
                  for (var index = 0; index < lines.length; index++)
                    PosOrderLine(
                      id: -(index + 1),
                      name: lines[index].dish.name,
                      quantity: lines[index].quantity,
                      total: lines[index].total,
                      unit: lines[index].dish.unit,
                      specification: lines[index].specification,
                      refunded: false,
                      kdsStatusText: result.cloudAcceptanceStatus.isNotEmpty
                          ? result.cloudAcceptanceStatus
                          : '待确认',
                    ),
              ],
            ),
          );
        });
        return;
      }
      widget.onCompleted?.call();
      final current = workspace!;
      final total = lines.fold<double>(0, (sum, line) => sum + line.total);
      setState(() {
        workspace = PosWorkspace(
          table: current.table,
          categories: current.categories,
          dishes: current.dishes,
          paymentMethods: current.paymentMethods,
          currentOrder: PosOrder(
            id: result.id,
            orderNo: result.orderNo,
            tableNumber: widget.table.number,
            diners: diners,
            total: total,
            grossAmount: total,
            createdAt: DateTime.now(),
            lines: [
              for (var index = 0; index < lines.length; index++)
                PosOrderLine(
                  id: -(index + 1),
                  name: lines[index].dish.name,
                  quantity: lines[index].quantity,
                  total: lines[index].total,
                  unit: lines[index].dish.unit,
                  specification: lines[index].specification,
                  refunded: false,
                ),
            ],
          ),
        );
      });
      // 立即展示本地明细后，再强制重载云端真实订单（真实明细 ID、金额、
      // 规格、会员信息），保证退菜/改价/加菜等按 detailId 的操作可用。
      await _load(forceOrder: true);
    } on LocalKdsPersistenceException catch (exception) {
      await pendingSubmissionStore.clear(
        widget.pickupOrder ? 'pickup' : 'table-${widget.table.number}',
      );
      if (mounted) {
        await showPosNotice(
          context,
          title: '订单成功，KDS 推送失败',
          message: '$exception',
          tone: PosNoticeTone.warning,
        );
      }
    } catch (exception, stackTrace) {
      CrashLog.instance.write('ERROR', '下单异常: $exception', stackTrace);
      if (mounted) {
        await showPosNotice(
          context,
          title: '下单失败',
          message: '$exception',
          tone: PosNoticeTone.error,
        );
      }
    } finally {
      if (mounted) setState(() => submitting = false);
    }
  }

  Future<void> _handleNoTableSubmission({
    required int diners,
    required String remark,
    required List<PosCartLine> lines,
  }) async {
    final mode = await showPosDiningModeDialog(context);
    if (mode == null || !mounted) return;

    if (mode == PosDiningMode.takeout) {
      await _submitDirectPickupOrder(remark: remark, lines: lines);
      return;
    }

    if (mode == PosDiningMode.dineIn) {
      await _showTableSelectionAndSubmit(
        diners: diners,
        remark: remark,
        lines: lines,
      );
    }
  }

  Future<void> _submitDirectPickupOrder({
    required String remark,
    required List<PosCartLine> lines,
  }) async {
    final repository = widget.repository;
    if (repository is! PosPickupOrderRepository) {
      await showPosNotice(
        context,
        title: '不支持打包自提',
        message: '当前收银服务接口不支持自提打包下单',
        tone: PosNoticeTone.error,
      );
      return;
    }
    final pickupRepository = repository as PosPickupOrderRepository;
    setState(() => submitting = true);
    try {
      final fingerprint = jsonEncode({
        'pickup': true,
        'table_number': '打包',
        'diners': 1,
        'remark': remark,
        'lines': lines.map((line) => line.requestBody()).toList(),
      });
      final requestId = await pendingSubmissionStore.resolve(
        scope: 'pickup',
        fingerprint: fingerprint,
        generate: _newSubmissionRequestId,
      );
      final result = await pickupRepository.submitPickupOrder(
        remark: remark,
        lines: lines,
        clientRequestId: requestId,
      );
      await pendingSubmissionStore.clear('pickup');
      if (!mounted) return;

      widget.onCompleted?.call();
      final current = workspace!;
      final total = lines.fold<double>(0, (sum, line) => sum + line.total);
      final packagingFee = total <= 0 ? 0 : (total / 100).ceilToDouble();
      setState(() {
        workspace = PosWorkspace(
          table: const DiningTable(
            number: '打包',
            status: TableStatus.pending,
            people: 1,
          ),
          categories: current.categories,
          dishes: current.dishes,
          paymentMethods: current.paymentMethods,
          currentOrder: PosOrder(
            id: result.id,
            orderNo: result.orderNo,
            tableNumber: '打包',
            diners: 1,
            total: total + packagingFee,
            grossAmount: total + packagingFee,
            createdAt: DateTime.now(),
            lines: [
              if (result.hasFormalOrderDetails)
                for (final detail in result.orderDetails)
                  PosOrderLine(
                    id: detail.detailId,
                    name: detail.name,
                    quantity: detail.quantity,
                    total:
                        (detail.raw['total_price'] as num?)?.toDouble() ?? 0.0,
                    unit: detail.unit,
                    specification: '${detail.raw['specification'] ?? ''}',
                    refunded: false,
                    kdsStatusText: result.cloudAcceptanceStatus.isNotEmpty
                        ? result.cloudAcceptanceStatus
                        : (detail.remainingQuantity > 0 ? '待确认' : ''),
                  )
              else
                for (var index = 0; index < lines.length; index++)
                  PosOrderLine(
                    id: -(index + 1),
                    name: lines[index].dish.name,
                    quantity: lines[index].quantity,
                    total: lines[index].total,
                    unit: lines[index].dish.unit,
                    specification: lines[index].specification,
                    refunded: false,
                    kdsStatusText: result.cloudAcceptanceStatus.isNotEmpty
                        ? result.cloudAcceptanceStatus
                        : '待确认',
                  ),
            ],
          ),
        );
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('打包自提下单成功！订单号：${result.orderNo}'),
          duration: const Duration(seconds: 2),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (e) {
      if (mounted) {
        await showPosNotice(
          context,
          title: '打包下单失败',
          message: '$e',
          tone: PosNoticeTone.error,
        );
      }
    } finally {
      if (mounted) setState(() => submitting = false);
    }
  }

  Future<void> _showTableSelectionAndSubmit({
    required int diners,
    required String remark,
    required List<PosCartLine> lines,
  }) async {
    final selectedTable = await showPosTableSelectionGridDialog(
      context,
      repository: widget.tableRepository,
    );
    if (selectedTable == null || !mounted) return;

    setState(() => submitting = true);
    try {
      if (!selectedTable.isOccupied) {
        await widget.repository.openTable(selectedTable.number);
      }
      final dinersToUse = diners > 0
          ? diners
          : (selectedTable.people > 0 ? selectedTable.people : 2);
      final fingerprint = jsonEncode({
        'pickup': false,
        'table_number': selectedTable.number,
        'diners': dinersToUse,
        'remark': remark,
        'lines': lines.map((line) => line.requestBody()).toList(),
      });
      final requestId = await pendingSubmissionStore.resolve(
        scope: 'table-${selectedTable.number}',
        fingerprint: fingerprint,
        generate: _newSubmissionRequestId,
      );
      final result = await widget.repository.submitOrder(
        tableNumber: selectedTable.number,
        diners: dinersToUse,
        remark: remark,
        lines: lines,
        clientRequestId: requestId,
      );
      await pendingSubmissionStore.clear('table-${selectedTable.number}');
      if (!mounted) return;

      widget.onCompleted?.call();
      final current = workspace!;
      final total = lines.fold<double>(0, (sum, line) => sum + line.total);
      final targetTable = selectedTable.copyWith(
        status: TableStatus.pending,
        people: dinersToUse,
      );
      setState(() {
        workspace = PosWorkspace(
          table: targetTable,
          categories: current.categories,
          dishes: current.dishes,
          paymentMethods: current.paymentMethods,
          currentOrder: PosOrder(
            id: result.id,
            orderNo: result.orderNo,
            tableNumber: selectedTable.number,
            diners: dinersToUse,
            total: total,
            grossAmount: total,
            createdAt: DateTime.now(),
            lines: [
              for (var index = 0; index < lines.length; index++)
                PosOrderLine(
                  id: -(index + 1),
                  name: lines[index].dish.name,
                  quantity: lines[index].quantity,
                  total: lines[index].total,
                  unit: lines[index].dish.unit,
                  specification: lines[index].specification,
                  refunded: false,
                ),
            ],
          ),
        );
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('已开台并成功下单至 ${selectedTable.number}号桌！'),
          duration: const Duration(seconds: 2),
          behavior: SnackBarBehavior.floating,
        ),
      );
      await _load(forceOrder: true);
    } catch (e) {
      if (mounted) {
        await showPosNotice(
          context,
          title: '开台下单失败',
          message: '$e',
          tone: PosNoticeTone.error,
        );
      }
    } finally {
      if (mounted) setState(() => submitting = false);
    }
  }

  Future<void> _submitAddedDishes({
    required int diners,
    required String remark,
    required List<PosCartLine> lines,
  }) async {
    final order = addingDishesTargetOrder ?? workspace?.currentOrder;
    if (order == null || submitting) return;
    setState(() => submitting = true);
    CrashLog.instance.recordBreadcrumb(
      category: 'order',
      message:
          '开始加菜: 订单=${order.orderNo}, 桌台=${widget.table.number}, 加菜品类数=${lines.length}',
      data: {
        'order_no': order.orderNo,
        'table': widget.table.number,
        'lines_count': lines.length,
      },
    );
    try {
      final fingerprint = jsonEncode({
        'order_no': order.orderNo,
        'table_number': widget.table.number,
        'lines': lines.map((line) => line.requestBody()).toList(),
      });
      final scope = 'add-dishes-${order.orderNo}';
      final requestId = await pendingSubmissionStore.resolve(
        scope: scope,
        fingerprint: fingerprint,
        generate: _newAddDishesRequestId,
      );
      final newRevision = await widget.repository.addDishes(
        orderNo: order.orderNo,
        tableNumber: widget.table.number,
        lines: lines,
        clientRequestId: requestId,
        expectedVersion: order.revision,
      );
      if (newRevision != null) {
        _updateCurrentOrderRevision(newRevision);
      }
      await pendingSubmissionStore.clear(scope);
      if (!mounted) return;
      addingDishes = false;
      addingDishesTargetOrder = null;
      try {
        await _load(forceOrder: true);
      } catch (loadError, loadStack) {
        CrashLog.instance.write('ERROR', '加菜后刷新订单状态异常: $loadError', loadStack);
        if (mounted) {
          await showPosNotice(
            context,
            title: '订单刷新提示',
            message: '加菜已提交成功，但未能即时刷新最新订单状态：$loadError。请手动点击刷新或重试。',
            tone: PosNoticeTone.warning,
          );
        }
      }
    } catch (exception, stackTrace) {
      CrashLog.instance.write('ERROR', '加菜异常: $exception', stackTrace);
      if (mounted) {
        if (exception is ApiException && exception.isOrderVersionConflict) {
          addingDishes = false;
          addingDishesTargetOrder = null;
          try {
            await _load(forceOrder: true);
          } catch (_) {}
          if (mounted) {
            await showPosNotice(
              context,
              title: '订单版本冲突',
              message: '订单已被其他终端修改，请确认后重试',
              tone: PosNoticeTone.warning,
            );
          }
          return;
        }
        await showPosNotice(
          context,
          title: '加菜失败',
          message: '$exception',
          tone: PosNoticeTone.error,
        );
      }
    } finally {
      if (mounted) setState(() => submitting = false);
    }
  }

  void _updateCurrentOrderRevision(int newRevision) {
    final currentWorkspace = workspace;
    final currentOrder = currentWorkspace?.currentOrder;
    if (currentWorkspace == null || currentOrder == null) return;
    final updatedOrder = currentOrder.copyWith(revision: newRevision);
    final updatedTableOrders = currentWorkspace.tableOrders.map((o) {
      if (o.orderNo == updatedOrder.orderNo) {
        return o.copyWith(revision: newRevision);
      }
      return o;
    }).toList();
    setState(() {
      workspace = currentWorkspace.copyWith(
        currentOrder: updatedOrder,
        tableOrders: updatedTableOrders,
      );
    });
  }

  Future<bool> _confirm({
    required String title,
    required String message,
    String primaryLabel = '确认',
    PosNoticeTone tone = PosNoticeTone.warning,
  }) async {
    return showPosNotice(
      context,
      title: title,
      message: message,
      tone: tone,
      primaryLabel: primaryLabel,
      secondaryLabel: '取消',
    );
  }

  Future<String?> _targetTable(String title) async {
    var targetTable = '';
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: TextField(
          autofocus: true,
          onChanged: (value) => targetTable = value,
          decoration: const InputDecoration(
            labelText: '目标台号',
            hintText: '请输入空闲桌台号',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, targetTable.trim()),
            child: const Text('确认'),
          ),
        ],
      ),
    );
    final normalizedTarget = result?.trim() ?? '';
    return normalizedTarget.isEmpty ? null : normalizedTarget;
  }

  Future<bool> _runAction({
    required Future<void> Function() action,
    bool closeAfterSuccess = false,
    bool reloadAfterSuccess = true,
    FutureOr<void> Function()? onSuccess,
    String? failureMessage,
  }) async {
    if (submitting) return false;
    setState(() => submitting = true);
    try {
      await action();
      if (!mounted) return true;
      await onSuccess?.call();
      if (closeAfterSuccess) {
        widget.onCompleted?.call();
        if (widget.table.number.trim().isEmpty) {
          _resetToInitialOrderingView();
        } else if (Navigator.of(context).canPop()) {
          Navigator.of(context).pop(true);
        } else if (widget.onBack != null) {
          widget.onBack!();
        }
      } else if (reloadAfterSuccess) {
        // 强制重载云端订单：普通 _load 对空桌不请求订单详情，会把
        // 桌台明细顶回点餐页；forceOrder 拿不到订单时保留当前明细。
        await _load(forceOrder: true);
      }
      return true;
    } catch (exception, stackTrace) {
      CrashLog.instance.write('ERROR', '操作执行异常: $exception', stackTrace);
      if (mounted) {
        final errText = '$exception';
        final isCode4002 =
            (exception is ApiException && exception.code == 4002) ||
            errText.contains('4002') ||
            errText.contains('钱箱未开班');
        if (isCode4002) {
          final opened = await _showDrawerUnopenedDialog();
          if (opened && mounted) {
            unawaited(_checkDrawerState());
          }
          return false;
        }

        final isCode40935 =
            (exception is ApiException && exception.code == 40935) ||
            errText.contains('40935');
        if (isCode40935) {
          await showPosNotice(
            context,
            title: '微信支付进行中',
            message: '顾客正处于微信扫码界面，请先点击【取消微信支付】并确认顾客未付款，再进行手工结账。',
            tone: PosNoticeTone.warning,
          );
          return false;
        }

        if (errText.contains('并台') && errText.contains('统一结账')) {
          final doTableCheckout = await _confirm(
            title: '并台结账提示',
            message: '该桌存在并台订单，不支持单笔结账。是否使用【整桌统一结账】？',
            primaryLabel: '整桌结账',
          );
          if (doTableCheckout && mounted) {
            unawaited(_tableCheckout('cash'));
            return false;
          }
        }
        if (errText.contains('意向') ||
            errText.contains('冲突') ||
            errText.contains('扫码款') ||
            errText.contains('重复扣款') ||
            errText.contains('锁定')) {
          final doForceCheckout = await _confirm(
            title: '结算拦截提示',
            message: '$errText\n\n检测到支付意向或状态冲突。若已在吧台确认款项或需主管核销，是否进行【主管强制结账】？',
            primaryLabel: '主管强制结账',
          );
          if (doForceCheckout && mounted) {
            unawaited(_forceCheckout());
            return false;
          }
        }
        await showPosNotice(
          context,
          title: '操作失败',
          message: failureMessage == null
              ? '$exception'
              : '$failureMessage\n\n失败原因：$exception',
          tone: PosNoticeTone.error,
        );
      }
      return false;
    } finally {
      if (mounted) setState(() => submitting = false);
    }
  }

  Future<void> _clearTable() async {
    final tableNumber = (workspace?.table.number ?? widget.table.number).trim();
    if (tableNumber.isEmpty) {
      _showUnavailable('桌号缺失，无法清台，请刷新桌台列表后重试');
      return;
    }
    final confirmed = await _confirm(title: '清台提示', message: '确定要清台吗？');
    if (!confirmed) return;
    await _runAction(
      action: () => widget.repository.clearTable(tableNumber),
      closeAfterSuccess: true,
    );
  }

  /// 挂单：把未结订单挂起（POST /cashier/order/hang），桌台释放；
  /// 挂起的订单可从挂单池找回继续操作。
  Future<void> _hangOrder() async {
    final orderNo = (workspace?.currentOrder?.orderNo ?? '').trim();
    if (orderNo.isEmpty) {
      await _showUnavailable('订单号缺失，无法挂单，请刷新桌台后重试');
      return;
    }
    final reason = await showPosHangOrderDialog(
      context,
      tableNumber: widget.table.number,
      orderNo: orderNo,
    );
    if (reason == null) return;
    try {
      await widget.repository.hangOrder(orderNo: orderNo, reason: reason);
      if (mounted) {
        widget.onCompleted?.call();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('挂单成功，订单已移入挂单池'),
            behavior: SnackBarBehavior.floating,
            duration: Duration(seconds: 2),
          ),
        );
        if (Navigator.of(context).canPop()) {
          Navigator.of(context).pop(true);
        }
      }
    } catch (e) {
      if (mounted) {
        final errText = '$e'.replaceFirst('Exception: ', '');
        final msg = errText.contains('已结账') || errText.contains('已取消')
            ? '已结账或已取消的订单不可挂单'
            : (errText.contains('400')
                  ? '当前订单状态不允许挂单：$errText'
                  : '挂单失败，桌台保持当前状态，请重试');
        await showPosNotice(
          context,
          title: '挂单失败',
          message: msg,
          tone: PosNoticeTone.error,
        );
      }
    }
  }

  Future<void> _mergeTable() async {
    final target = await _targetTable('并台');
    if (target == null) return;
    await _runAction(
      action: () => widget.repository.mergeTables(
        sourceTableNumber: widget.table.number,
        targetTableNumber: target,
      ),
      closeAfterSuccess: true,
    );
  }

  Future<void> _transferTable([PosOrder? targetOrder]) async {
    final order = targetOrder ?? workspace?.currentOrder;
    if (order == null) return;
    final target = await _targetTable('换台');
    if (target == null) return;
    await _runAction(
      action: () => widget.repository.transferTable(
        orderNo: order.orderNo,
        targetTableNumber: target,
      ),
      closeAfterSuccess: true,
    );
  }

  Future<void> _refundDish(PosOrderLine line) async {
    final order = workspace?.findOrderByLine(line) ?? workspace?.currentOrder;
    if (order == null) return;
    final result = await showDialog<RefundDishResult>(
      context: context,
      barrierDismissible: false,
      builder: (_) => RefundDishDialog(line: line),
    );
    if (result == null || !mounted) return;

    // 统一审批授权：首次执行返回"缺少现场授权"，自动唤起店长授权弹窗，
    // 获取一次性审批令牌后携带 approvalToken 重试原请求。
    int? nextRevision;
    final executed = await runSensitiveWithApproval(
      context: context,
      repository: widget.approvalRepository,
      request: CashierApprovalRequest(
        title: '退菜审批',
        permission: refundPermission,
        permissionLabel: '退菜 / 人工退款',
        bizType: 'ORDER',
        bizId: order.orderNo,
        amount: null,
        reason: result.reason,
        requiredRoles: '需店长或管理员现场授权',
      ),
      execute: (approvalToken) async {
        nextRevision = await widget.repository.refundDish(
          orderNo: order.orderNo,
          detailId: line.id,
          quantity: result.quantity,
          stockAction: result.stockAction,
          reason: result.reason,
          approvalToken: approvalToken,
          expectedVersion: order.revision,
        );
      },
    );
    if (!executed || !mounted) {
      await _refreshWorkspaceSilently();
      return;
    }

    if (nextRevision != null) {
      _updateCurrentOrderRevision(nextRevision!);
    }
    orderAmountsFresh = false;
    _applyRefundLocally(line.id, result.quantity, orderNo: order.orderNo);
    if (!await _refreshWorkspaceSilently()) {
      await _showUnavailable('退菜已成功，但最新金额同步失败。重新获取金额前已暂停结账，请检查网络后重试。');
    }
  }

  Future<bool> _refreshWorkspaceSilently() async {
    try {
      final shouldBeOccupied =
          tableOpened ||
          workspace?.currentOrder != null ||
          widget.table.isOccupied;
      final targetTable = shouldBeOccupied
          ? (workspace?.table ?? widget.table).copyWith(
              status: TableStatus.pending,
            )
          : (workspace?.table ?? widget.table);
      final value = await widget.repository.loadWorkspace(targetTable);
      if (!mounted) return false;
      setState(() {
        workspace = value;
        orderAmountsFresh = true;
      });
      return true;
    } catch (_) {
      return false;
    }
  }

  void _applyRefundLocally(int lineId, int refundQuantity, {String? orderNo}) {
    final currentWorkspace = workspace;
    final currentOrder = currentWorkspace?.currentOrder;
    if (currentWorkspace == null || currentOrder == null) return;

    List<PosOrderLine> updateLines(
      List<PosOrderLine> lines,
      String fallbackOrderNo,
    ) {
      return [
        for (final currentLine in lines)
          if (currentLine.id == lineId)
            if (refundQuantity >= currentLine.quantity)
              currentLine.copyWith(
                refunded: true,
                orderNo: currentLine.orderNo.isNotEmpty
                    ? currentLine.orderNo
                    : fallbackOrderNo,
                kdsStatusText: '待确认',
              )
            else
              currentLine.copyWith(
                quantity: currentLine.quantity - refundQuantity,
                total:
                    currentLine.unitPrice *
                    (currentLine.quantity - refundQuantity),
                refunded: false,
                orderNo: currentLine.orderNo.isNotEmpty
                    ? currentLine.orderNo
                    : fallbackOrderNo,
                kdsStatusText: '待确认',
              )
          else
            currentLine,
      ];
    }

    PosOrder updateOrder(PosOrder target) {
      final hasLine = target.lines.any((l) => l.id == lineId);
      if (!hasLine) return target;
      final newLines = updateLines(target.lines, target.orderNo);
      final activeTotal = newLines
          .where((l) => !l.isRefunded)
          .fold<double>(0, (sum, l) => sum + l.total);
      final activeGross = newLines.fold<double>(0, (sum, l) => sum + l.total);
      return target.copyWith(
        lines: newLines,
        total: activeTotal,
        grossAmount: activeGross,
      );
    }

    final updatedCurrentOrder = updateOrder(currentOrder);
    final updatedTableOrders = currentWorkspace.tableOrders
        .map(updateOrder)
        .toList();
    setState(() {
      workspace = currentWorkspace.copyWith(
        currentOrder: updatedCurrentOrder,
        tableOrders: updatedTableOrders,
      );
    });
  }

  Future<void> _giftDish(PosOrderLine line) async {
    final order = workspace?.findOrderByLine(line) ?? workspace?.currentOrder;
    if (order == null) return;

    final confirmed = await showPosNotice(
      context,
      title: '确认赠送',
      message: '确定要将【${line.name}】设为赠菜（单价改为 ¥0.00）吗？',
      primaryLabel: '确认赠送',
      secondaryLabel: '取消',
      tone: PosNoticeTone.warning,
    );
    if (!confirmed || !mounted) return;

    int? nextRevision;
    final executed = await runSensitiveWithApproval(
      context: context,
      repository: widget.approvalRepository,
      request: CashierApprovalRequest(
        title: '赠菜审批',
        permission: changePricePermission,
        permissionLabel: '改价 / 赠菜',
        bizType: 'ORDER',
        bizId: order.orderNo,
        amount: 0.0,
        reason: '将【${line.name}】本行金额调整为 ¥0.00 赠送给顾客',
        requiredRoles: '需店长或管理员现场授权',
      ),
      execute: (approvalToken) async {
        nextRevision = await widget.repository.giftDish(
          orderNo: order.orderNo,
          detailId: line.id,
          approvalToken: approvalToken,
          expectedVersion: order.revision,
        );
      },
    );
    if (!executed || !mounted) {
      await _refreshWorkspaceSilently();
      return;
    }
    if (nextRevision != null) {
      _updateCurrentOrderRevision(nextRevision!);
    }
    await _load(forceOrder: true);
  }

  Future<void> _discountOrder([PosOrder? targetOrder]) async {
    final order = targetOrder ?? workspace?.currentOrder;
    if (order == null) return;
    final result = await showDialog<OrderDiscountResult>(
      context: context,
      barrierDismissible: false,
      barrierColor: const Color(0x66000000),
      builder: (_) => OrderDiscountDialog(order: order),
    );
    if (result == null || !mounted) return;

    int? nextRevision;
    final executed = await runSensitiveWithApproval(
      context: context,
      repository: widget.approvalRepository,
      request: CashierApprovalRequest(
        title: '整单优惠审批',
        permission: discountPermission,
        permissionLabel: '整单优惠 / 折扣',
        bizType: 'ORDER',
        bizId: order.orderNo,
        amount: result.discountAmount,
        reason: result.reason,
        requiredRoles: '需店长或管理员现场授权',
      ),
      execute: (approvalToken) async {
        nextRevision = await widget.repository.discountOrder(
          orderNo: order.orderNo,
          discountAmount: result.discountAmount,
          reason: result.reason,
          approvalToken: approvalToken,
          expectedVersion: order.revision,
        );
      },
    );
    if (!executed || !mounted) {
      await _refreshWorkspaceSilently();
      return;
    }
    if (nextRevision != null) {
      _updateCurrentOrderRevision(nextRevision!);
    }
    await _load(forceOrder: true);
  }

  Future<void> _updateOrderDiners([PosOrder? targetOrder]) async {
    final order = targetOrder ?? workspace?.currentOrder;
    if (order == null || order.orderNo.trim().isEmpty) {
      await _showUnavailable('订单号缺失，无法修改就餐人数');
      return;
    }
    final tableNumber = (workspace?.table.number ?? widget.table.number).trim();
    final newDiners = await showPosUpdateDinersDialog(
      context,
      tableNumber: tableNumber,
      orderNo: order.orderNo,
      currentDiners: order.diners,
    );
    if (newDiners == null || !mounted) return;
    if (newDiners == order.diners) {
      return;
    }

    setState(() => submitting = true);
    try {
      await widget.repository.updateDiners(
        orderNo: order.orderNo,
        diners: newDiners,
      );
      if (!mounted) return;
      await _load(forceOrder: true);
      if (!mounted) return;
      await showPosNotice(
        context,
        title: '修改就餐人数成功',
        message: '桌台 $tableNumber 用餐人数已更新为 $newDiners 人（原 ${order.diners} 人）。',
        tone: PosNoticeTone.success,
      );
    } catch (exception, stackTrace) {
      CrashLog.instance.write('ERROR', '修改就餐人数失败: $exception', stackTrace);
      if (!mounted) return;
      final rawError = exception.toString().replaceFirst('Exception: ', '');
      await showPosNotice(
        context,
        title: '修改就餐人数失败',
        message: rawError,
        tone: PosNoticeTone.error,
      );
    } finally {
      if (mounted) setState(() => submitting = false);
    }
  }

  Future<void> _showUnavailable(String message) {
    return showPosNotice(
      context,
      title: '暂不可用',
      message: message,
      tone: PosNoticeTone.warning,
    );
  }

  Future<void> _checkout(String paymentMethod) async {
    if (workspace != null && workspace!.isMergedTable) {
      await _tableCheckout(paymentMethod);
      return;
    }
    var order = workspace?.currentOrder;
    if (order == null) return;
    if (!orderAmountsFresh) {
      if (!await _refreshWorkspaceSilently()) {
        await _showUnavailable('订单金额尚未同步，暂不能结账，请检查网络后重试');
        return;
      }
      order = workspace?.currentOrder;
      if (order == null) return;
    }
    final checkoutOrder = order;
    if (PosPaymentChannelKind.normalize(paymentMethod) ==
        PosPaymentChannelKind.combined) {
      await _combinedCheckout(checkoutOrder);
      return;
    }
    if (PosPaymentChannelKind.normalize(paymentMethod) ==
            PosPaymentChannelKind.wechatMicropay &&
        widget.repository is PosWechatMicropayCheckoutRepository) {
      await _wechatMicropayCheckout(checkoutOrder);
      return;
    }
    if (PosPaymentChannelKind.normalize(paymentMethod) ==
            PosPaymentChannelKind.wechatNative &&
        widget.repository is PosWechatNativeCheckoutRepository) {
      await _wechatNativeCheckout(checkoutOrder);
      return;
    }
    if (PosPaymentChannelKind.normalize(paymentMethod) ==
            PosPaymentChannelKind.receivable &&
        widget.repository is PosReceivableRepository) {
      await _receivableCheckout(checkoutOrder);
      return;
    }
    if (_isCashPayment(paymentMethod) &&
        widget.repository is PosCashCheckoutRepository) {
      await _cashCheckout(checkoutOrder);
      return;
    }
    final collectionChannel = _collectionChannel(paymentMethod);
    if (collectionChannel != null &&
        widget.repository is PosOfflineCollectionRepository) {
      await _offlineCollectionCheckout(
        checkoutOrder,
        channel: collectionChannel,
      );
      return;
    }
    final labels = {
      for (final method
          in workspace?.paymentMethods ?? const <PosPaymentMethod>[])
        method.code: method.name,
    };
    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      barrierColor: const Color(0x66000000),
      builder: (_) => StandardCheckoutDialog(
        methodLabel: labels[paymentMethod] ?? paymentMethod,
        amount: checkoutOrder.total,
      ),
    );
    if (confirmed != true) return;
    await _runAction(
      action: () => widget.repository.checkout(
        orderNo: checkoutOrder.orderNo,
        paymentMethod: paymentMethod,
      ),
      closeAfterSuccess: true,
    );
  }

  Future<void> _wechatNativeCheckout(PosOrder order) async {
    final repository = widget.repository as PosWechatNativeCheckoutRepository;
    final result = await showDialog<WechatNativeDialogResult>(
      context: context,
      barrierDismissible: false,
      barrierColor: const Color(0x66000000),
      builder: (_) => WechatNativeCheckoutDialog(
        order: order,
        createOrder: () =>
            repository.createWechatNativeOrder(orderNo: order.orderNo),
        queryOrder: () =>
            repository.queryWechatNativeOrder(orderNo: order.orderNo),
        closeOrder: () =>
            repository.closeWechatNativeOrder(orderNo: order.orderNo),
      ),
    );

    if (result == WechatNativeDialogResult.success) {
      await _clearPendingExternalCheckout();
      await _refreshWorkspaceSilently();
      if (mounted) {
        await showDialog<void>(
          context: context,
          barrierDismissible: false,
          barrierColor: const Color(0x66000000),
          builder: (_) => PaymentSuccessDialog(
            amount: order.total,
            orderNo: order.orderNo,
            channelLabel: '微信支付',
          ),
        );
        widget.onCompleted?.call();
      }
    }
  }

  Future<void> _receivableCheckout(PosOrder order) async {
    final repo = widget.repository as PosReceivableRepository;
    final claim = await showDialog<PosReceivableClaim>(
      context: context,
      barrierDismissible: false,
      barrierColor: const Color(0x66000000),
      builder: (_) => ReceivableChargeDialog(
        order: order,
        tableNumber: widget.table.number,
        loadAccounts: repo.loadEligibleAccounts,
        chargeReceivable: ({required accountId, required requestId, note}) =>
            repo.chargeReceivable(
              orderNo: order.orderNo,
              accountId: accountId,
              requestId: requestId,
              note: note,
            ),
      ),
    );

    if (claim != null) {
      await _clearPendingExternalCheckout();
      await _refreshWorkspaceSilently();
      if (mounted) {
        await showDialog<void>(
          context: context,
          barrierDismissible: false,
          barrierColor: const Color(0x66000000),
          builder: (_) => PaymentSuccessDialog(
            amount: order.total,
            orderNo: order.orderNo,
            channelLabel:
                '客户挂账 (${claim.customerName.isNotEmpty ? claim.customerName : claim.claimNo})',
          ),
        );
        widget.onCompleted?.call();
      }
    }
  }

  Future<void> _wechatMicropayCheckout(PosOrder order) async {
    final repository = widget.repository as PosWechatMicropayCheckoutRepository;
    final result = await showDialog<WechatMicropayDialogResult>(
      context: context,
      barrierDismissible: false,
      barrierColor: const Color(0x66000000),
      builder: (_) => WechatMicropayCheckoutDialog(
        order: order,
        payMicropay: (authCode) => repository.payWechatMicropay(
          orderNo: order.orderNo,
          authCode: authCode,
        ),
        queryOrder: () =>
            repository.queryWechatMicropayOrder(orderNo: order.orderNo),
        reverseOrder: () =>
            repository.reverseWechatMicropayOrder(orderNo: order.orderNo),
      ),
    );

    if (result == WechatMicropayDialogResult.success) {
      await _clearPendingExternalCheckout();
      await _refreshWorkspaceSilently();
      if (mounted) {
        await showDialog<void>(
          context: context,
          barrierDismissible: false,
          barrierColor: const Color(0x66000000),
          builder: (_) => PaymentSuccessDialog(
            amount: order.total,
            orderNo: order.orderNo,
            channelLabel: '微信付款码',
          ),
        );
        widget.onCompleted?.call();
      }
    }
  }

  Future<void> _tableCheckout(String paymentMethod) async {
    final currentWorkspace = workspace;
    if (currentWorkspace == null) return;
    if (!orderAmountsFresh) {
      if (!await _refreshWorkspaceSilently()) {
        await _showUnavailable('订单金额尚未同步，暂不能结账，请检查网络后重试');
        return;
      }
    }
    final totalPayable =
        workspace?.tableTotalPayable ?? currentWorkspace.tableTotalPayable;
    final tableNumber = (workspace?.table.number ?? widget.table.number).trim();

    final normalizedKind = PosPaymentChannelKind.normalize(paymentMethod);
    if (normalizedKind == PosPaymentChannelKind.wechatMicropay) {
      await _showUnavailable('并台整桌暂不支持微信付款码结账，请使用现金或其它支付方式结账');
      return;
    }
    if (normalizedKind == PosPaymentChannelKind.wechatNative) {
      await _showUnavailable('并台整桌暂不支持微信动态扫码结账，请使用现金或其它支付方式结账');
      return;
    }

    if (_isCashPayment(paymentMethod) &&
        widget.repository is PosCashCheckoutRepository) {
      if (!_isDrawerOpen) {
        final opened = await _showDrawerUnopenedDialog();
        if (!opened) return;
      }
      final settlement = await showDialog<PosCashSettlement>(
        context: context,
        barrierDismissible: false,
        barrierColor: const Color(0x66000000),
        builder: (_) => _CashCheckoutDialog(orderTotal: totalPayable),
      );
      if (settlement == null) return;
      await _runAction(
        action: () => widget.repository.checkoutTable(
          tableNumber: tableNumber,
          paymentMethod: 'cash',
          cashAmount: settlement.cashReceived,
        ),
        closeAfterSuccess: true,
      );
      return;
    }

    final labels = {
      for (final method
          in workspace?.paymentMethods ?? const <PosPaymentMethod>[])
        method.code: method.name,
    };
    final methodLabel = labels[paymentMethod] ?? paymentMethod;
    final count = workspace?.tableOrders.length ?? 1;
    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      barrierColor: const Color(0x66000000),
      builder: (_) => StandardCheckoutDialog(
        methodLabel: count > 1 ? '$methodLabel (并台整桌结账)' : methodLabel,
        amount: totalPayable,
      ),
    );
    if (confirmed != true) return;
    await _runAction(
      action: () => widget.repository.checkoutTable(
        tableNumber: tableNumber,
        paymentMethod: paymentMethod,
      ),
      closeAfterSuccess: true,
    );
  }

  Future<void> _forceCheckout([PosOrder? targetOrder]) async {
    final currentWorkspace = workspace;
    if (currentWorkspace == null) return;
    if (!orderAmountsFresh) {
      if (!await _refreshWorkspaceSilently()) {
        await _showUnavailable('订单金额尚未同步，暂不能结账，请检查网络后重试');
        return;
      }
    }
    final order = targetOrder ?? workspace?.currentOrder;
    if (order == null) return;

    if (currentWorkspace.isMergedTable) {
      await _tableForceCheckout();
      return;
    }

    final result = await showDialog<ForceCheckoutResult>(
      context: context,
      barrierDismissible: false,
      barrierColor: const Color(0x66000000),
      builder: (_) => CashierForceCheckoutDialog(
        orderNo: order.orderNo,
        amount: order.total,
        paymentMethods: currentWorkspace.paymentMethods,
        title: '${widget.table.number}号 强制结账',
      ),
    );
    if (result == null || !mounted) return;

    final executed = await runSensitiveWithApproval(
      context: context,
      repository: widget.approvalRepository,
      request: CashierApprovalRequest(
        title: '强制结账审批',
        permission: 'admin:manage',
        permissionLabel: '主管强制结账',
        bizType: 'FORCE_CHECKOUT',
        bizId: order.orderNo,
        amount: order.total,
        reason: result.reason,
        requiredRoles: '需店长或管理员现场授权',
      ),
      execute: (approvalToken) => widget.repository.checkout(
        orderNo: order.orderNo,
        paymentMethod: result.paymentMethod,
        force: true,
        approvalToken: approvalToken,
      ),
    );
    if (!executed || !mounted) return;

    widget.onCompleted?.call();
    if (Navigator.of(context).canPop()) Navigator.of(context).pop(true);
  }

  Future<void> _tableForceCheckout() async {
    final currentWorkspace = workspace;
    if (currentWorkspace == null) return;
    final totalPayable = currentWorkspace.tableTotalPayable;
    final tableNumber = (workspace?.table.number ?? widget.table.number).trim();

    final result = await showDialog<ForceCheckoutResult>(
      context: context,
      barrierDismissible: false,
      barrierColor: const Color(0x66000000),
      builder: (_) => CashierForceCheckoutDialog(
        orderNo: '并台整桌 (${currentWorkspace.tableOrders.length}单)',
        amount: totalPayable,
        paymentMethods: currentWorkspace.paymentMethods,
        title: '$tableNumber号 整桌强制结账',
      ),
    );
    if (result == null || !mounted) return;

    final executed = await runSensitiveWithApproval(
      context: context,
      repository: widget.approvalRepository,
      request: CashierApprovalRequest(
        title: '整桌强制结账审批',
        permission: 'admin:manage',
        permissionLabel: '主管整桌强制结账',
        bizType: 'FORCE_CHECKOUT',
        bizId: tableNumber,
        amount: totalPayable,
        reason: result.reason,
        requiredRoles: '需店长或管理员现场授权',
      ),
      execute: (approvalToken) => widget.repository.checkoutTable(
        tableNumber: tableNumber,
        paymentMethod: result.paymentMethod,
        force: true,
        approvalToken: approvalToken,
      ),
    );
    if (!executed || !mounted) return;

    widget.onCompleted?.call();
    if (Navigator.of(context).canPop()) Navigator.of(context).pop(true);
  }

  Future<void> _combinedCheckout(PosOrder order) async {
    if (widget.repository is! PosCombinedCheckoutRepository) {
      await _showUnavailable('当前收银端暂不支持组合支付');
      return;
    }
    if (!await _canStartExternalCheckout(order.orderNo)) return;
    if (pendingExternalOrderNo == order.orderNo &&
        pendingCombinedSettlement != null &&
        pendingCombinedReady) {
      final retry = await _confirm(
        title: '待入账支付',
        message: '该订单已有人工确认到账的组合支付，是否直接重试入账？请勿再次生成收款码或重复收款。',
      );
      if (!retry) return;
      final succeeded = await _submitCombinedSettlement(
        order,
        pendingCombinedSettlement!,
      );
      if (succeeded) await _clearPendingExternalCheckout();
      return;
    }
    if (!await _reconcilePendingCollectionConfirmations(order)) return;
    final result = await showDialog<CombinedCheckoutDialogResult>(
      context: context,
      barrierDismissible: false,
      barrierColor: const Color(0x66000000),
      builder: (_) => CombinedCheckoutDialog(
        order: order,
        paymentMethods: workspace?.paymentMethods ?? const <PosPaymentMethod>[],
        confirmCollection: _confirmCombinedCollection,
        initialSettlement: pendingCombinedSettlement,
        initiallyConfirmedChannels: pendingConfirmedChannels,
        onCollectionConfirmed: (settlement, confirmedChannels) async {
          pendingExternalOrderNo = order.orderNo;
          pendingCombinedSettlement = settlement;
          pendingOfflineChannel = null;
          pendingConfirmedChannels = confirmedChannels;
          pendingCombinedReady = false;
          await pendingCheckoutStore.write(
            PendingExternalCheckout(
              orderNo: order.orderNo,
              combinedSettlement: settlement,
              confirmedChannels: confirmedChannels,
              collectionSessionId: collectionSessionId,
            ),
          );
        },
      ),
    );
    if (result == null || !mounted) return;
    final settlement = PosCheckoutSettlement(
      wechatMinor: result.wechatMinor,
      alipayMinor: result.alipayMinor,
      balanceMinor: result.balanceMinor,
      cashMinor: result.cashMinor,
      cashTenderMinor: result.cashTenderMinor,
      changeAmountMinor: result.changeAmountMinor,
      changeChannel: result.changeChannel,
    );
    final totalMinor = (order.total * 100).round();
    if (!settlement.isBalanced(totalMinor) ||
        settlement.positiveChannelCount < 2) {
      await _showUnavailable('组合支付金额发生变化，请重新核对');
      return;
    }
    if (settlement.wechatMinor > 0 || settlement.alipayMinor > 0) {
      pendingExternalOrderNo = order.orderNo;
      pendingCombinedSettlement = settlement;
      pendingOfflineChannel = null;
      pendingConfirmedChannels = {
        if (settlement.wechatMinor > 0) 'wechat',
        if (settlement.alipayMinor > 0) 'alipay',
      };
      pendingCombinedReady = true;
      await pendingCheckoutStore.write(
        PendingExternalCheckout(
          orderNo: order.orderNo,
          combinedSettlement: settlement,
          confirmedChannels: pendingConfirmedChannels,
          readyForSubmission: true,
          collectionSessionId: collectionSessionId,
        ),
      );
    }
    final succeeded = await _submitCombinedSettlement(order, settlement);
    if (succeeded) await _clearPendingExternalCheckout();
  }

  Future<bool> _submitCombinedSettlement(
    PosOrder order,
    PosCheckoutSettlement settlement,
  ) {
    return _runAction(
      action: () =>
          (widget.repository as PosCombinedCheckoutRepository).checkoutCombined(
            orderNo: order.orderNo,
            settlement: settlement,
            memberOpenid: order.memberOpenid,
            memberPhone: order.memberPhone,
            collectionSessionId: collectionSessionId,
          ),
      closeAfterSuccess: true,
      failureMessage: '已确认的扫码款仍保留为待入账状态，请勿重复收款。重新进入组合支付可直接重试原分摊。',
    );
  }

  Future<bool> _confirmCombinedCollection(
    String channel,
    int amountMinor,
    PosCheckoutSettlement draftSettlement,
  ) async {
    if (widget.repository is! PosOfflineCollectionRepository) {
      await _showUnavailable('当前收银端无法生成收款码');
      return false;
    }
    final repository = widget.repository as PosOfflineCollectionRepository;
    final orderNo = workspace?.currentOrder?.orderNo;
    if (orderNo == null) return false;
    Future<PosOfflineCollectionQr>? qrLoad;
    final result = await showDialog<OfflineCollectionDialogResult>(
      context: context,
      barrierDismissible: false,
      barrierColor: const Color(0x66000000),
      builder: (_) => OfflineCollectionCheckoutDialog(
        amount: amountMinor / 100,
        channel: channel,
        channelLabel: channel == 'alipay' ? '支付宝' : '微信',
        checkSettled: () => repository.checkOrderSettled(orderNo),
        loadQr: () => qrLoad ??= _createCombinedCollectionQr(
          repository: repository,
          channel: channel,
          orderNo: orderNo,
          amountMinor: amountMinor,
          draftSettlement: draftSettlement,
        ),
      ),
    );
    if (result == null) {
      await _cancelUnconfirmedCollection(
        repository: repository,
        channel: channel,
        orderNo: orderNo,
        qrLoad: qrLoad,
      );
      return false;
    }
    pendingConfirmedChannels = {...pendingConfirmedChannels, channel};
    await pendingCheckoutStore.write(
      PendingExternalCheckout(
        orderNo: orderNo,
        combinedSettlement: draftSettlement,
        confirmedChannels: pendingConfirmedChannels,
        collectionSessionId: collectionSessionId,
      ),
    );
    if (result == OfflineCollectionDialogResult.manualConfirm) {
      await repository.confirmOfflineCollection(
        channel: channel,
        orderNo: orderNo,
        sessionId: collectionSessionId,
        amountMinor: amountMinor,
      );
    } else if (result == OfflineCollectionDialogResult.autoSettled && mounted) {
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        barrierColor: const Color(0x66000000),
        builder: (_) => PaymentSuccessDialog(
          amount: amountMinor / 100,
          orderNo: orderNo,
          channelLabel: channel == 'alipay' ? '支付宝' : '微信',
        ),
      );
    }
    return true;
  }

  double _resolvePayableAmount(PosOrder order) {
    var totalYuan = order.total;
    if (totalYuan <= 0 && order.lines.isNotEmpty) {
      final activeSum = order.lines
          .where((l) => !l.refunded)
          .fold<double>(0.0, (sum, l) => sum + l.total);
      if (activeSum > 0) {
        final net = activeSum - order.discountAmount - order.wipeZeroAmount;
        totalYuan = net > 0 ? net : 0.0;
      }
    }
    if (totalYuan <= 0 && (workspace?.tableTotalPayable ?? 0) > 0) {
      totalYuan = workspace!.tableTotalPayable;
    }
    return totalYuan > 0 ? totalYuan : 0.0;
  }

  Future<void> _offlineCollectionCheckout(
    PosOrder order, {
    required String channel,
  }) async {
    final payableAmount = _resolvePayableAmount(order);
    if (payableAmount <= 0) {
      await _showUnavailable('订单待收金额为 ¥0.00，无需扫码收款，请使用免单或现金完成结账');
      return;
    }
    final repository = widget.repository as PosOfflineCollectionRepository;
    if (!await _canStartExternalCheckout(
      order.orderNo,
      requestedOfflineChannel: channel,
    )) {
      return;
    }
    if (pendingExternalOrderNo == order.orderNo &&
        pendingOfflineChannel == channel &&
        pendingCombinedReady) {
      final retry = await _confirm(
        title: '待入账支付',
        message:
            '该订单已有人工确认到账的${channel == 'alipay' ? '支付宝' : '微信'}扫码款，是否直接重试入账？请勿重复收款。',
      );
      if (!retry) return;
      final succeeded = await _submitOfflineCollection(order, channel);
      if (succeeded) {
        await _clearPendingExternalCheckout();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('到账金额 ¥${payableAmount.toStringAsFixed(2)}'),
              backgroundColor: const Color(0xff15803d),
              duration: const Duration(seconds: 3),
            ),
          );
        }
      }
      return;
    }
    if (!await _reconcilePendingCollectionConfirmations(order)) return;
    Future<PosOfflineCollectionQr>? qrLoad;
    final result = await showDialog<OfflineCollectionDialogResult>(
      context: context,
      barrierDismissible: false,
      barrierColor: const Color(0x66000000),
      builder: (_) => OfflineCollectionCheckoutDialog(
        amount: payableAmount,
        channel: channel,
        channelLabel: channel == 'alipay' ? '支付宝' : '微信',
        checkSettled: () => repository.checkOrderSettled(order.orderNo),
        loadQr: () => qrLoad ??= _createStandaloneCollectionQr(
          repository: repository,
          channel: channel,
          order: order,
        ),
      ),
    );
    if (result == null) {
      await _cancelUnconfirmedCollection(
        repository: repository,
        channel: channel,
        orderNo: order.orderNo,
        qrLoad: qrLoad,
      );
      return;
    }
    if (!mounted) return;
    if (result == OfflineCollectionDialogResult.autoSettled) {
      await _clearPendingExternalCheckout();
      await _refreshWorkspaceSilently();
      if (mounted) {
        await showDialog<void>(
          context: context,
          barrierDismissible: false,
          barrierColor: const Color(0x66000000),
          builder: (_) => PaymentSuccessDialog(
            amount: order.total,
            orderNo: order.orderNo,
            channelLabel: channel == 'alipay' ? '支付宝' : '微信',
          ),
        );
        widget.onCompleted?.call();
      }
      return;
    }
    pendingExternalOrderNo = order.orderNo;
    pendingOfflineChannel = channel;
    pendingCombinedSettlement = null;
    pendingConfirmedChannels = {channel};
    await pendingCheckoutStore.write(
      PendingExternalCheckout(
        orderNo: order.orderNo,
        offlineChannel: channel,
        confirmedChannels: {channel},
        collectionSessionId: collectionSessionId,
      ),
    );
    try {
      await repository.confirmOfflineCollection(
        channel: channel,
        orderNo: order.orderNo,
        sessionId: collectionSessionId,
        amountMinor: (order.total * 100).round(),
      );
    } catch (exception) {
      if (mounted) {
        await _showUnavailable(
          '已保留人工确认到账记录，但服务端确认失败：$exception。请勿重复收款，重新进入该支付方式将自动重试确认。',
        );
      }
      return;
    }
    pendingCombinedReady = true;
    await pendingCheckoutStore.write(
      PendingExternalCheckout(
        orderNo: order.orderNo,
        offlineChannel: channel,
        confirmedChannels: {channel},
        readyForSubmission: true,
        collectionSessionId: collectionSessionId,
      ),
    );
    final succeeded = await _submitOfflineCollection(order, channel);
    if (succeeded) {
      await _clearPendingExternalCheckout();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('到账金额 ¥${order.total.toStringAsFixed(2)}'),
            backgroundColor: const Color(0xff15803d),
            duration: const Duration(seconds: 3),
          ),
        );
      }
    }
  }

  Future<PosOfflineCollectionQr> _createStandaloneCollectionQr({
    required PosOfflineCollectionRepository repository,
    required String channel,
    required PosOrder order,
  }) async {
    final payableAmount = _resolvePayableAmount(order);
    if (payableAmount <= 0) {
      throw const ApiException('订单待收金额为 ¥0.00，无法生成收款码');
    }
    final qr = await repository.createOfflineCollectionQr(
      channel: channel,
      orderNo: order.orderNo,
      sessionId: collectionSessionId,
      amountMinor: (payableAmount * 100).round(),
    );
    if (mounted) {
      setState(() {
        pendingExternalOrderNo = order.orderNo;
        pendingOfflineChannel = channel;
        pendingCombinedSettlement = null;
        pendingConfirmedChannels = const <String>{};
        pendingCombinedReady = false;
      });
    }
    await pendingCheckoutStore.write(
      PendingExternalCheckout(
        orderNo: order.orderNo,
        offlineChannel: channel,
        collectionSessionId: collectionSessionId,
      ),
    );
    return qr;
  }

  Future<PosOfflineCollectionQr> _createCombinedCollectionQr({
    required PosOfflineCollectionRepository repository,
    required String channel,
    required String orderNo,
    required int amountMinor,
    required PosCheckoutSettlement draftSettlement,
  }) async {
    if (amountMinor <= 0) {
      throw const ApiException('待收金额须大于0，无法生成收款码');
    }
    final qr = await repository.createOfflineCollectionQr(
      channel: channel,
      orderNo: orderNo,
      sessionId: collectionSessionId,
      amountMinor: amountMinor,
    );
    if (mounted) {
      setState(() {
        pendingExternalOrderNo = orderNo;
        pendingCombinedSettlement = draftSettlement;
        pendingOfflineChannel = null;
        pendingCombinedReady = false;
      });
    }
    await pendingCheckoutStore.write(
      PendingExternalCheckout(
        orderNo: orderNo,
        combinedSettlement: draftSettlement,
        confirmedChannels: pendingConfirmedChannels,
        collectionSessionId: collectionSessionId,
      ),
    );
    return qr;
  }

  Future<void> _cancelUnconfirmedCollection({
    required PosOfflineCollectionRepository repository,
    required String channel,
    required String orderNo,
    required Future<PosOfflineCollectionQr>? qrLoad,
  }) async {
    try {
      await qrLoad;
    } catch (_) {
      // A failed QR request has no usable lease to release.
    }
    try {
      await repository.cancelOfflineCollection(
        channel: channel,
        orderNo: orderNo,
        sessionId: collectionSessionId,
      );
      if (pendingConfirmedChannels.isEmpty) {
        await _clearPendingExternalCheckout();
      }
    } catch (exception) {
      if (mounted) {
        await _showUnavailable('支付会话释放失败：$exception。请重试关闭或等待占用自动过期。');
      }
    }
  }

  Future<bool> _releasePendingCollectionSession() async {
    final orderNo = pendingExternalOrderNo;
    if (orderNo == null) return true;
    if (widget.repository is! PosOfflineCollectionRepository) {
      await _showUnavailable('当前收银端无法释放支付会话，请稍后重试');
      return false;
    }
    final channels = <String>{};
    final offlineChannel = pendingOfflineChannel;
    if (offlineChannel != null &&
        !pendingConfirmedChannels.contains(offlineChannel)) {
      channels.add(offlineChannel);
    }
    final combined = pendingCombinedSettlement;
    if (combined != null) {
      if (combined.wechatMinor > 0 &&
          !pendingConfirmedChannels.contains('wechat')) {
        channels.add('wechat');
      }
      if (combined.alipayMinor > 0 &&
          !pendingConfirmedChannels.contains('alipay')) {
        channels.add('alipay');
      }
    }
    if (channels.isEmpty) return true;
    final repository = widget.repository as PosOfflineCollectionRepository;
    try {
      for (final channel in channels) {
        await repository.cancelOfflineCollection(
          channel: channel,
          orderNo: orderNo,
          sessionId: collectionSessionId,
        );
      }
      if (pendingConfirmedChannels.isEmpty) {
        await _clearPendingExternalCheckout();
      }
      return true;
    } catch (exception) {
      if (mounted) {
        await _showUnavailable('支付会话释放失败：$exception。为避免持续占用，请重试当前操作。');
      }
      return false;
    }
  }

  void _resetToInitialOrderingView() {
    setState(() {
      _orderingSessionIndex++;
      tableOpened = true;
      addingDishes = false;
      addingDishesTargetOrder = null;
      pendingExternalOrderNo = null;
      pendingCombinedSettlement = null;
      pendingOfflineChannel = null;
      pendingConfirmedChannels = const <String>{};
      pendingCombinedReady = false;
      collectionSessionId = _newCollectionSessionId();
      if (workspace != null) {
        workspace = PosWorkspace(
          table: const DiningTable(
            number: '',
            status: TableStatus.empty,
            people: 0,
          ),
          categories: workspace!.categories,
          dishes: workspace!.dishes,
          paymentMethods: workspace!.paymentMethods,
          currentOrder: null,
          paymentConfigurationAvailable:
              workspace!.paymentConfigurationAvailable,
        );
      }
    });
  }

  Future<void> _leavePage() async {
    if (pagePopInProgress) return;
    if (pendingExternalOrderNo != null) {
      pagePopInProgress = true;
      final released = await _releasePendingCollectionSession();
      if (!mounted) return;
      if (!released) {
        pagePopInProgress = false;
        return;
      }
      pagePopInProgress = false;
    }

    // 若最初是从无台号点餐（侧栏点餐入口）进入，且当前已经下单进入了订单明细：
    // 点击返回应当返回到最初的无台号点菜页面（清空订单状态，重新开始点菜），而不是跳出到桌台大盘！
    if (widget.table.number.trim().isEmpty && workspace?.currentOrder != null) {
      _resetToInitialOrderingView();
      return;
    }

    if (widget.onBack != null) {
      widget.onBack!();
      return;
    }

    if (mounted) {
      final popped = await Navigator.maybePop(context);
      if (!popped && mounted && Navigator.of(context).canPop()) {
        Navigator.of(context).pop();
      }
    }
  }

  Future<bool> _submitOfflineCollection(PosOrder order, String channel) {
    return _runAction(
      action: () => widget.repository.checkout(
        orderNo: order.orderNo,
        paymentMethod: channel == 'alipay'
            ? PosPaymentChannelKind.alipay.canonicalCode
            : PosPaymentChannelKind.wechat.canonicalCode,
        collectionSessionId: collectionSessionId,
      ),
      closeAfterSuccess: true,
      failureMessage: '扫码款已人工确认到账并保留为待入账状态，请勿重复收款。重新进入该支付渠道可直接重试入账。',
    );
  }

  Future<bool> _canStartExternalCheckout(
    String orderNo, {
    String? requestedOfflineChannel,
  }) async {
    final persisted = await pendingCheckoutStore.read(orderNo);
    if (persisted != null) {
      if (persisted.collectionSessionId.isNotEmpty &&
          persisted.collectionSessionId != collectionSessionId &&
          !persisted.readyForSubmission) {
        await _showUnavailable('该订单正在其他收银窗口生成或确认收款码，请勿重复收款。');
        return false;
      }
      pendingExternalOrderNo = persisted.orderNo;
      pendingCombinedSettlement = persisted.combinedSettlement;
      pendingOfflineChannel = persisted.offlineChannel;
      pendingConfirmedChannels = persisted.confirmedChannels;
      pendingCombinedReady = persisted.readyForSubmission;
    }
    final pendingOrderNo = pendingExternalOrderNo;
    if (pendingOrderNo == null) return true;
    if (pendingOrderNo == orderNo) {
      final sameFlow = requestedOfflineChannel == null
          ? pendingCombinedSettlement != null
          : pendingOfflineChannel == requestedOfflineChannel;
      if (sameFlow) return true;
      if (pendingConfirmedChannels.isNotEmpty || pendingCombinedReady) {
        final doForce = await _confirm(
          title: '已确认到账拦截',
          message:
              '该订单已有扫码款确认到账，通常不能直接切换支付渠道。'
              '若原渠道款项核对有误或需管理人员特殊核销，是否调起【主管强制结账】？',
          primaryLabel: '主管强制结账',
        );
        if (doForce && mounted) {
          unawaited(_forceCheckout());
        }
        return false;
      }
      final originalLabel = pendingCombinedSettlement != null
          ? '组合支付'
          : _offlineChannelLabel(pendingOfflineChannel);
      final nextLabel = requestedOfflineChannel == null
          ? '组合支付'
          : _offlineChannelLabel(requestedOfflineChannel);
      final changeConfirmed = await showPosNotice(
        context,
        title: '变更支付渠道',
        message:
            '该订单当前保留“$originalLabel”的待入账记录。变更为“$nextLabel”会清除原记录并重新发起收款。\n请先确认原渠道未实际收款，或已完成退款，避免重复收款。',
        tone: PosNoticeTone.warning,
        primaryLabel: '确认变更',
        secondaryLabel: '取消',
      );
      if (!changeConfirmed || !mounted) return false;
      if (!await _releasePendingCollectionSession()) return false;
      await _clearPendingExternalCheckout();
      collectionSessionId = _newCollectionSessionId();
      return true;
    }
    await _showUnavailable(
      '订单 $pendingOrderNo 存在已确认到账但尚未入账的扫码款，请先回到该订单完成入账，当前订单暂不可再次收款。',
    );
    return false;
  }

  String _offlineChannelLabel(String? channel) => switch (channel) {
    'alipay' => '支付宝',
    'wechat' => '微信支付',
    _ => '原支付渠道',
  };

  Future<bool> _reconcilePendingCollectionConfirmations(PosOrder order) async {
    if (pendingConfirmedChannels.isEmpty ||
        widget.repository is! PosOfflineCollectionRepository) {
      return true;
    }
    final repository = widget.repository as PosOfflineCollectionRepository;
    try {
      for (final channel in pendingConfirmedChannels) {
        final amountMinor = pendingCombinedSettlement == null
            ? (order.total * 100).round()
            : channel == 'alipay'
            ? pendingCombinedSettlement!.alipayMinor
            : pendingCombinedSettlement!.wechatMinor;
        if (amountMinor <= 0) continue;
        await repository.confirmOfflineCollection(
          channel: channel,
          orderNo: order.orderNo,
          sessionId: collectionSessionId,
          amountMinor: amountMinor,
        );
      }
      return true;
    } catch (exception) {
      if (mounted) {
        await _showUnavailable(
          '已确认到账的扫码款尚未完成服务端核销：$exception。请勿重复出码或改用其他支付方式。',
        );
      }
      return false;
    }
  }

  Future<void> _clearPendingExternalCheckout() async {
    final orderNo = pendingExternalOrderNo;
    void clearState() {
      pendingExternalOrderNo = null;
      pendingCombinedSettlement = null;
      pendingOfflineChannel = null;
      pendingConfirmedChannels = const <String>{};
      pendingCombinedReady = false;
    }

    if (mounted) {
      setState(clearState);
    } else {
      clearState();
    }
    if (orderNo != null) {
      await pendingCheckoutStore.clear(orderNo);
    }
  }

  Future<void> _balanceCheckout() async {
    if (workspace != null && workspace!.isMergedTable) {
      await _showUnavailable('当前桌台存在并台订单，不支持单笔余额结账，请使用整桌统一结账');
      return;
    }
    final order = workspace?.currentOrder;
    if (order == null) return;
    if (widget.repository is! PosBalanceCheckoutRepository) {
      await _showUnavailable('当前收银端暂不支持储值划扣');
      return;
    }
    if (!order.hasRegisteredMember || order.memberOpenid.trim().isEmpty) {
      await _showUnavailable('该订单未绑定有效会员，请先绑定会员手机号');
      return;
    }
    if (order.discountAmount > 0 || order.wipeZeroAmount > 0) {
      await _showUnavailable('当前订单已使用优惠，请保留优惠并改用其他支付渠道');
      return;
    }
    if (order.memberBalance == null) {
      await _showUnavailable('会员余额加载失败，请刷新订单后重试');
      return;
    }
    final chargeAmount = order.grossAmount > 0
        ? order.grossAmount
        : order.total + order.discountAmount + order.wipeZeroAmount;
    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      barrierColor: const Color(0x66000000),
      builder: (_) =>
          BalanceCheckoutDialog(order: order, chargeAmount: chargeAmount),
    );
    if (confirmed != true || !mounted) return;
    await _runAction(
      action: () =>
          (widget.repository as PosBalanceCheckoutRepository).checkoutByBalance(
            orderNo: order.orderNo,
            openid: order.memberOpenid,
            memberPhone: order.memberPhone,
          ),
      closeAfterSuccess: true,
    );
  }

  Future<void> _printFrontTicket([PosOrder? targetOrder]) async {
    if (submitting) return;
    final order = targetOrder ?? workspace?.currentOrder;
    if (order == null || order.id <= 0) {
      await _showUnavailable('订单主键缺失，无法打印前台小票');
      return;
    }
    if (widget.repository is! PosReceiptPrintRepository &&
        widget.repository is! PosOrderPrintRepository) {
      await _showUnavailable('当前收银端暂不支持打印前台小票');
      return;
    }
    final shouldPreviewResult = await showCheckoutPrintPreviewChoice(context);
    if (!mounted) return;
    await _executeFrontTicketPrint(
      order: order,
      shouldPreviewResult: shouldPreviewResult,
    );
  }

  Future<void> _executeFrontTicketPrint({
    required PosOrder order,
    required bool shouldPreviewResult,
  }) async {
    if (widget.repository is! PosReceiptPrintRepository &&
        widget.repository is! PosOrderPrintRepository) {
      await _showUnavailable('当前收银端暂不支持打印前台小票');
      return;
    }
    setState(() => submitting = true);
    try {
      final result = widget.repository is PosReceiptPrintRepository
          ? await (widget.repository as PosReceiptPrintRepository)
                .printReceiptTicket(
                  type: PosReceiptPrintType.front,
                  orderId: order.id,
                  orderNo: order.orderNo,
                )
          : await (widget.repository as PosOrderPrintRepository)
                .printFrontTicket(orderId: order.id, orderNo: order.orderNo);
      if (!mounted) return;
      if (shouldPreviewResult) {
        await showPosRawPrintResultDialog(context, result: result);
        return;
      }
      await showPosNotice(
        context,
        title: result.printSuccess ? '打印成功' : '打印未完成',
        message: result.printSuccess
            ? '前台小票已发送至门店打印机。'
            : '小票内容已生成，但打印机未完成打印，请检查设备后重试。',
        tone: result.printSuccess
            ? PosNoticeTone.success
            : PosNoticeTone.warning,
      );
    } catch (exception, stackTrace) {
      CrashLog.instance.write('ERROR', '打印前台小票异常: $exception', stackTrace);
      if (!mounted) return;
      await showPosNotice(
        context,
        title: '打印失败',
        message: '$exception',
        tone: PosNoticeTone.error,
      );
    } finally {
      if (mounted) setState(() => submitting = false);
    }
  }

  Future<void> _reprintKitchenTicket([PosOrder? targetOrder]) async {
    if (submitting) return;
    final order = targetOrder ?? workspace?.currentOrder;
    if (order == null || order.orderNo.trim().isEmpty) {
      await _showUnavailable('订单号缺失，无法补打厨房小票');
      return;
    }
    if (widget.repository is! PosReceiptPrintRepository &&
        widget.repository is! PosKitchenPrintRepository) {
      await _showUnavailable('当前收银端暂不支持补打厨房小票');
      return;
    }
    setState(() => submitting = true);
    try {
      if (widget.repository is PosReceiptPrintRepository) {
        await (widget.repository as PosReceiptPrintRepository)
            .printReceiptTicket(
              type: PosReceiptPrintType.kitchen,
              orderId: order.id,
              orderNo: order.orderNo,
            );
      } else {
        await (widget.repository as PosKitchenPrintRepository)
            .reprintKitchenTicket(orderNo: order.orderNo);
      }
      if (!mounted) return;
      await showPosNotice(
        context,
        title: '厨房小票补打成功',
        message: '补打指令已发送至厨房打印机。',
        tone: PosNoticeTone.success,
      );
    } catch (exception, stackTrace) {
      CrashLog.instance.write('ERROR', '补打厨房小票异常: $exception', stackTrace);
      if (!mounted) return;
      await showPosNotice(
        context,
        title: '厨房小票补打失败',
        message: '$exception'.replaceFirst('Exception: ', ''),
        tone: PosNoticeTone.error,
      );
    } finally {
      if (mounted) setState(() => submitting = false);
    }
  }

  Future<void> _printReceiptTicket(
    PosReceiptPrintType type, [
    PosOrder? targetOrder,
  ]) async {
    if (type == PosReceiptPrintType.front) {
      await _printFrontTicket(targetOrder);
      return;
    }
    if (type == PosReceiptPrintType.kitchen) {
      await _reprintKitchenTicket(targetOrder);
      return;
    }
    if (submitting) return;
    final order = targetOrder ?? workspace?.currentOrder;
    if (order == null || (order.id <= 0 && order.orderNo.trim().isEmpty)) {
      await _showUnavailable('订单信息缺失，无法打印小票');
      return;
    }
    if (widget.repository is! PosReceiptPrintRepository) {
      await _showUnavailable('当前收银端暂不支持该小票类型');
      return;
    }
    setState(() => submitting = true);
    try {
      final result = await (widget.repository as PosReceiptPrintRepository)
          .printReceiptTicket(
            type: type,
            orderId: order.id,
            orderNo: order.orderNo,
          );
      if (!mounted) return;
      final label = type == PosReceiptPrintType.preCheckout ? '预结单' : '结账单';
      await showPosNotice(
        context,
        title: result.printSuccess ? '打印成功' : '打印未完成',
        message: result.printSuccess
            ? '$label已发送至门店打印机。'
            : '$label内容已生成，但打印机未完成打印，请检查设备后重试。',
        tone: result.printSuccess
            ? PosNoticeTone.success
            : PosNoticeTone.warning,
      );
    } catch (exception, stackTrace) {
      CrashLog.instance.write('ERROR', '打印小票异常: $exception', stackTrace);
      if (!mounted) return;
      await showPosNotice(
        context,
        title: '打印失败',
        message: '$exception'.replaceFirst('Exception: ', ''),
        tone: PosNoticeTone.error,
      );
    } finally {
      if (mounted) setState(() => submitting = false);
    }
  }

  Future<void> _cashCheckout(PosOrder order) async {
    if (!_isDrawerOpen) {
      final opened = await _showDrawerUnopenedDialog();
      if (!opened) return;
    }
    final settlement = await showDialog<PosCashSettlement>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _CashCheckoutDialog(orderTotal: order.total),
    );
    if (settlement == null || !mounted) return;
    await _runAction(
      action: () =>
          (widget.repository as PosCashCheckoutRepository).checkoutCash(
            orderNo: order.orderNo,
            paymentMethod: 'cash',
            settlement: settlement,
          ),
      closeAfterSuccess: true,
    );
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: allowingPagePop || pendingExternalOrderNo == null,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) unawaited(_leavePage());
      },
      child: Scaffold(
        backgroundColor: context.cashier.canvas,
        body: Stack(
          children: [
            LayoutBuilder(
              builder: (context, constraints) {
                final width = constraints.maxWidth < 1280
                    ? 1280.0
                    : constraints.maxWidth;
                final height = constraints.maxHeight < 720
                    ? 720.0
                    : constraints.maxHeight;
                return Scrollbar(
                  controller: verticalController,
                  thumbVisibility: constraints.maxHeight < 720,
                  child: SingleChildScrollView(
                    controller: verticalController,
                    child: Scrollbar(
                      controller: horizontalController,
                      thumbVisibility: constraints.maxWidth < 1280,
                      child: SingleChildScrollView(
                        controller: horizontalController,
                        scrollDirection: Axis.horizontal,
                        child: SizedBox(
                          width: width,
                          height: height,
                          child: Padding(
                            padding: workspace?.currentOrder != null && !addingDishes
                                ? const EdgeInsets.fromLTRB(20, 14, 19, 16)
                                : const EdgeInsets.all(10),
                            child: _body(),
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
            if (error != null || loading)
              Positioned(
                top: 20,
                left: 20,
                child: FilledButton.tonalIcon(
                  key: const Key('pos-top-back-button'),
                  onPressed: _leavePage,
                  icon: const Icon(Icons.arrow_back),
                  label: const Text('返回桌台'),
                  style: FilledButton.styleFrom(
                    elevation: 2,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _handleLogout() async {
    if (widget.onLogout == null) return;
    if (mounted && Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
    }
    widget.onLogout!();
  }

  Widget _body() {
    if (loading) {
      return Center(
        child: Container(
          key: const Key('pos-workspace-loading'),
          width: 520,
          padding: const EdgeInsets.symmetric(horizontal: 48, vertical: 42),
          decoration: BoxDecoration(
            color: context.cashier.surface,
            borderRadius: BorderRadius.circular(28),
            border: Border.all(color: context.cashier.border),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CircularProgressIndicator(),
              const SizedBox(height: 24),
              Text(
                '正在加载点餐数据...',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w700,
                  color: context.cashier.ink,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                '正在同步菜品、库存和桌台状态',
                style: TextStyle(fontSize: 18, color: context.cashier.inkMuted),
              ),
              const SizedBox(height: 24),
              OutlinedButton.icon(
                key: const Key('pos-loading-back-button'),
                onPressed: _leavePage,
                icon: const Icon(Icons.arrow_back, size: 18),
                label: const Text('返回桌台', style: TextStyle(fontSize: 16)),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size(160, 44),
                  foregroundColor: context.cashier.ink,
                  side: BorderSide(color: context.cashier.border),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }
    if (error != null) {
      final rawError = error?.toString() ?? '未知错误';
      final cleanError = rawError.replaceFirst('Exception: ', '');
      final isPermissionDenied =
          cleanError.contains('无权限') ||
          cleanError.contains('403') ||
          cleanError.contains('dish:manage') ||
          cleanError.contains('Forbidden') ||
          cleanError.contains('未授权');

      return Center(
        child: Container(
          key: const Key('pos-workspace-error'),
          width: 580,
          padding: const EdgeInsets.fromLTRB(40, 36, 40, 32),
          decoration: BoxDecoration(
            color: context.cashier.surface,
            borderRadius: BorderRadius.circular(28),
            border: Border.all(
              color: isPermissionDenied
                  ? const Color(0xfff59e0b).withValues(alpha: 0.4)
                  : context.cashier.border,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.05),
                blurRadius: 20,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  color: isPermissionDenied
                      ? const Color(0xfffef3c7)
                      : const Color(0xfffee2e2),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  isPermissionDenied
                      ? Icons.lock_person_outlined
                      : Icons.error_outline_rounded,
                  size: 40,
                  color: isPermissionDenied
                      ? const Color(0xffd97706)
                      : const Color(0xffdc2626),
                ),
              ),
              const SizedBox(height: 20),
              Text(
                isPermissionDenied ? '点餐工作台权限不足' : '点餐工作台加载失败',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w700,
                  color: context.cashier.ink,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                isPermissionDenied
                    ? '当前账号缺少菜品管理/点单权限（dish:manage）。\n请切换具备权限的账号登录，或联系管理员分配权限。'
                    : '网络连接异常或服务数据同步失败，请检查网络后重试。',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 16,
                  height: 1.5,
                  color: context.cashier.inkMuted,
                ),
              ),
              if (widget.currentAccount != null &&
                  widget.currentAccount!.trim().isNotEmpty) ...[
                const SizedBox(height: 14),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: context.cashier.canvas,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: context.cashier.border),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.account_circle_outlined,
                        size: 16,
                        color: context.cashier.inkMuted,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        '当前登录账号：${widget.currentAccount}',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                          color: context.cashier.ink,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 14),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: context.cashier.canvas,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  cleanError,
                  textAlign: TextAlign.center,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13,
                    fontFamily: 'monospace',
                    color: isPermissionDenied
                        ? const Color(0xffb45309)
                        : const Color(0xffb91c1c),
                  ),
                ),
              ),
              const SizedBox(height: 28),
              Row(
                children: [
                  Expanded(
                    child: SizedBox(
                      height: 48,
                      child: OutlinedButton.icon(
                        key: const Key('pos-error-back-button'),
                        onPressed: _leavePage,
                        icon: const Icon(Icons.arrow_back, size: 18),
                        label: const Text(
                          '返回桌台',
                          style: TextStyle(fontSize: 16),
                        ),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: context.cashier.ink,
                          side: BorderSide(color: context.cashier.border),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: SizedBox(
                      height: 48,
                      child: FilledButton.icon(
                        key: const Key('pos-error-reload-button'),
                        onPressed: _load,
                        icon: const Icon(Icons.refresh, size: 18),
                        label: const Text(
                          '重新加载',
                          style: TextStyle(fontSize: 16),
                        ),
                        style: FilledButton.styleFrom(
                          backgroundColor: context.cashier.ink,
                          foregroundColor:
                              Theme.of(context).brightness == Brightness.dark
                              ? Colors.black
                              : Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                    ),
                  ),
                  if (widget.onLogout != null) ...[
                    const SizedBox(width: 12),
                    Expanded(
                      child: SizedBox(
                        height: 48,
                        child: OutlinedButton.icon(
                          key: const Key('pos-error-logout-button'),
                          onPressed: _handleLogout,
                          icon: const Icon(Icons.logout, size: 18),
                          label: const Text(
                            '退出登录',
                            style: TextStyle(fontSize: 16),
                          ),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: const Color(0xffdc2626),
                            side: const BorderSide(color: Color(0xfffca5a5)),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      );
    }
    final data = workspace!;
    if (!tableOpened) {
      return _UnopenedTableView(
        tableNumber: widget.table.number,
        busy: submitting,
        onBack: _leavePage,
        onRetry: _confirmAndOpenTable,
      );
    }
    if (data.currentOrder != null && !addingDishes) {
      return OccupiedTableView(
        workspace: data,
        busy: submitting,
        isDrawerOpen: _isDrawerOpen,
        onBack: _leavePage,
        onAddDishes: ([order]) => setState(() {
          addingDishesTargetOrder = order;
          addingDishes = true;
        }),
        onMerge: _mergeTable,
        onTransfer: ([order]) => unawaited(_transferTable(order)),
        onClear: _clearTable,
        onRefund: _refundDish,
        onGift: _giftDish,
        onDiscount: ([order]) => unawaited(_discountOrder(order)),
        onForceCheckout: ([order]) => unawaited(_forceCheckout(order)),
        onPrintReceipt: (type, [order]) =>
            unawaited(_printReceiptTicket(type, order)),
        onUpdateDiners: _updateOrderDiners,
        onHang: () => unawaited(_hangOrder()),
        paymentMethods: data.paymentMethods,
        onCheckout: _checkout,
        onBalanceCheckout: _balanceCheckout,
        pickupOrder: widget.pickupOrder,
        checkoutOnly: widget.checkoutOnly,
        fulfillmentTitle: widget.fulfillmentTitle,
        onViewMemberHistory:
            data.currentOrder!.hasRegisteredMember &&
                widget.memberRepository != null
            ? _showMemberHistory
            : null,
      );
    }
    if (data.currentOrder == null &&
        data.table.status == TableStatus.settled &&
        !widget.pickupOrder) {
      // 已结账未清台且云端未返回订单时禁止渲染空点单（否则退出会弹未点餐自动清台确认，
      // 造成收款自动到账 / 退菜后误以为台号无账单），改为已结账占位页，可返回或清台。
      return _SettledEmptyTableView(
        tableNumber: widget.table.number,
        busy: submitting,
        onBack: _leavePage,
        onClear: _clearTable,
      );
    }
    return PosOrderingView(
      key: ValueKey('pos-ordering-view-$_orderingSessionIndex'),
      workspace: data,
      tableNumber: workspace?.table.number ?? widget.table.number,
      submitting: submitting,
      addingDishes: addingDishes,
      packingOrder: widget.pickupOrder,
      onBack: addingDishes
          ? () => setState(() {
              addingDishes = false;
              addingDishesTargetOrder = null;
            })
          : _leavePage,
      onEmptyBack: null, // 退菜赠菜后空购物车直接返回，不触发自动清台（清台失败会报未结账无法清台）
      onSubmit: addingDishes ? _submitAddedDishes : _submit,
    );
  }
}

String? _collectionChannel(String paymentMethod) {
  return switch (PosPaymentChannelKind.normalize(paymentMethod)) {
    PosPaymentChannelKind.wechat => 'wechat',
    PosPaymentChannelKind.alipay => 'alipay',
    _ => null,
  };
}

bool _isCashPayment(String paymentMethod) =>
    PosPaymentChannelKind.normalize(paymentMethod) ==
    PosPaymentChannelKind.cash;

class _SettledEmptyTableView extends StatelessWidget {
  const _SettledEmptyTableView({
    required this.tableNumber,
    required this.busy,
    required this.onBack,
    required this.onClear,
  });

  final String tableNumber;
  final bool busy;
  final VoidCallback onBack;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        key: const Key('pos-settled-empty-table'),
        width: 560,
        padding: const EdgeInsets.fromLTRB(48, 42, 48, 40),
        decoration: BoxDecoration(
          color: context.cashier.surface,
          borderRadius: BorderRadius.circular(28),
          border: Border.all(color: context.cashier.border),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.receipt_long_outlined,
              size: 70,
              color: context.cashier.ink,
            ),
            const SizedBox(height: 20),
            Text(
              '$tableNumber号桌已结账',
              style: TextStyle(
                fontSize: 32,
                fontWeight: FontWeight.w700,
                color: context.cashier.ink,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              '账单已结清，可在账单页查看记录；清台后恢复空闲状态。',
              style: TextStyle(fontSize: 20, color: context.cashier.inkMuted),
            ),
            const SizedBox(height: 32),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: busy ? null : onBack,
                    child: const Text('返回'),
                  ),
                ),
                const SizedBox(width: 18),
                Expanded(
                  child: FilledButton(
                    key: const Key('pos-settled-clear'),
                    onPressed: busy ? null : onClear,
                    style: FilledButton.styleFrom(
                      backgroundColor: context.cashier.ink,
                      foregroundColor:
                          Theme.of(context).brightness == Brightness.dark
                          ? Colors.black
                          : Colors.white,
                    ),
                    child: const Text('清台'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _UnopenedTableView extends StatelessWidget {
  const _UnopenedTableView({
    required this.tableNumber,
    required this.busy,
    required this.onBack,
    required this.onRetry,
  });

  final String tableNumber;
  final bool busy;
  final VoidCallback onBack;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        key: const Key('pos-unopened-table'),
        width: 520,
        padding: const EdgeInsets.fromLTRB(48, 42, 48, 40),
        decoration: BoxDecoration(
          color: context.cashier.surface,
          borderRadius: BorderRadius.circular(28),
          border: Border.all(color: context.cashier.border),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.table_restaurant_outlined,
              size: 70,
              color: context.cashier.ink,
            ),
            const SizedBox(height: 20),
            Text(
              '$tableNumber号桌尚未开台',
              style: TextStyle(
                fontSize: 32,
                fontWeight: FontWeight.w700,
                color: context.cashier.ink,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              '完成开台后才能点菜和提交订单',
              style: TextStyle(fontSize: 20, color: context.cashier.inkMuted),
            ),
            const SizedBox(height: 32),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: busy ? null : onBack,
                    child: const Text('返回'),
                  ),
                ),
                const SizedBox(width: 18),
                Expanded(
                  child: FilledButton(
                    key: const Key('pos-open-retry'),
                    onPressed: busy ? null : onRetry,
                    style: FilledButton.styleFrom(
                      backgroundColor: context.cashier.ink,
                      foregroundColor:
                          Theme.of(context).brightness == Brightness.dark
                          ? Colors.black
                          : Colors.white,
                    ),
                    child: const Text('重新开台'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _CashCheckoutDialog extends StatefulWidget {
  const _CashCheckoutDialog({required this.orderTotal});

  final double orderTotal;

  @override
  State<_CashCheckoutDialog> createState() => _CashCheckoutDialogState();
}

class _CashCheckoutDialogState extends State<_CashCheckoutDialog> {
  final TextEditingController _tenderController = TextEditingController();
  PosChangeChannel _channel = PosChangeChannel.cash;
  String? _inputError;

  int get _tenderMinor =>
      ((double.tryParse(_tenderController.text.trim()) ?? 0) * 100).round();
  int get _receivedMinor => (widget.orderTotal * 100).round();
  int get _changeMinor => (_tenderMinor - _receivedMinor).clamp(0, 1 << 62);

  @override
  void dispose() {
    _tenderController.dispose();
    super.dispose();
  }

  void _confirm() {
    if (_tenderMinor < _receivedMinor) {
      setState(() => _inputError = '付现金额不能小于应收金额');
      return;
    }
    Navigator.of(context).pop(
      PosCashSettlement.fromMinorUnits(
        cashReceivedMinor: _receivedMinor,
        cashTenderMinor: _tenderMinor,
        changeChannel: _channel,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final changeMinor = _changeMinor;
    return Dialog(
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.transparent,
      insetPadding: const EdgeInsets.all(24),
      elevation: 24,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
      child: SizedBox(
        key: const Key('cash-checkout-dialog'),
        width: 680,
        height: 650,
        child: Column(
          children: [
            SizedBox(
              height: 78,
              child: ColoredBox(
                color: const Color(0xff2d2d2d),
                child: Stack(
                  children: [
                    const Center(
                      child: Text(
                        '现金结账',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 31,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 2,
                        ),
                      ),
                    ),
                    Positioned(
                      right: 14,
                      top: 13,
                      child: IconButton(
                        onPressed: () => Navigator.of(context).pop(),
                        icon: const Icon(
                          Icons.close,
                          color: Colors.white,
                          size: 34,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(38, 26, 38, 18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text(
                      '本单应收',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Color(0xff777777), fontSize: 18),
                    ),
                    Text(
                      '¥${widget.orderTotal.toStringAsFixed(2)}',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Color(0xffe65353),
                        fontSize: 46,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 18),
                    TextField(
                      key: const Key('cash-tender-field'),
                      controller: _tenderController,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      onChanged: (_) => setState(() => _inputError = null),
                      decoration: InputDecoration(
                        labelText: '客人付现',
                        prefixText: '¥ ',
                        errorText: _inputError,
                        filled: true,
                        fillColor: Colors.white,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(
                            color: Color(0xff238af2),
                            width: 1.8,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        for (final amount in [
                          (label: '全额', value: widget.orderTotal),
                          (label: '¥50', value: 50.0),
                          (label: '¥100', value: 100.0),
                          (label: '¥200', value: 200.0),
                        ]) ...[
                          Expanded(
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 4,
                              ),
                              child: OutlinedButton(
                                key: Key('quick-cash-${amount.label}'),
                                style: OutlinedButton.styleFrom(
                                  minimumSize: const Size(0, 48),
                                  foregroundColor: const Color(0xff0369a1),
                                  side: const BorderSide(
                                    color: Color(0xffbae6fd),
                                  ),
                                  backgroundColor: const Color(0xfff0f9ff),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                ),
                                onPressed: () {
                                  setState(() {
                                    _tenderController.text = amount.value
                                        .toStringAsFixed(2);
                                    _inputError = null;
                                  });
                                },
                                child: Text(
                                  amount.label,
                                  style: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 14),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 22,
                        vertical: 14,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xfff5f5f5),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text('找零金额', style: TextStyle(fontSize: 19)),
                          Text(
                            '¥${(changeMinor / 100).toStringAsFixed(2)}',
                            style: const TextStyle(
                              color: Color(0xffe65353),
                              fontSize: 26,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (changeMinor > 0) ...[
                      const SizedBox(height: 16),
                      const Text(
                        '找零渠道',
                        style: TextStyle(
                          fontSize: 19,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 10),
                      SegmentedButton<PosChangeChannel>(
                        segments: [
                          for (final value in PosChangeChannel.values)
                            ButtonSegment(
                              value: value,
                              label: Text(
                                value.label,
                                key: Key(
                                  'cash-change-channel-${value.apiValue}',
                                ),
                              ),
                            ),
                        ],
                        selected: {_channel},
                        style: ButtonStyle(
                          minimumSize: const WidgetStatePropertyAll(
                            Size(0, 52),
                          ),
                          backgroundColor:
                              WidgetStateProperty.resolveWith<Color?>(
                                (states) =>
                                    states.contains(WidgetState.selected)
                                    ? const Color(0xffdcecff)
                                    : Colors.white,
                              ),
                          foregroundColor:
                              WidgetStateProperty.resolveWith<Color?>(
                                (states) =>
                                    states.contains(WidgetState.selected)
                                    ? const Color(0xff238af2)
                                    : const Color(0xff2d2d2d),
                              ),
                          side: WidgetStateProperty.resolveWith<BorderSide?>(
                            (states) => BorderSide(
                              color: states.contains(WidgetState.selected)
                                  ? const Color(0xff238af2)
                                  : const Color(0xffd0d0d0),
                            ),
                          ),
                        ),
                        onSelectionChanged: (value) =>
                            setState(() => _channel = value.first),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            Container(
              padding: const EdgeInsets.fromLTRB(38, 14, 38, 22),
              decoration: const BoxDecoration(
                border: Border(top: BorderSide(color: Color(0xffe2e2e2))),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: SizedBox(
                      height: 62,
                      child: OutlinedButton(
                        onPressed: () => Navigator.of(context).pop(),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: const Color(0xff2d2d2d),
                          side: const BorderSide(color: Color(0xff888888)),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: const Text('取消', style: TextStyle(fontSize: 25)),
                      ),
                    ),
                  ),
                  const SizedBox(width: 18),
                  Expanded(
                    child: SizedBox(
                      height: 62,
                      child: FilledButton(
                        key: const Key('cash-checkout-confirm'),
                        onPressed: _confirm,
                        style: FilledButton.styleFrom(
                          backgroundColor: const Color(0xff2d2d2d),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: const Text(
                          '确认收款',
                          style: TextStyle(
                            fontSize: 25,
                            fontWeight: FontWeight.w700,
                          ),
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
