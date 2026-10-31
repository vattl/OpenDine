import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../auth/data/cashier_account_storage.dart';
import '../../cashier_shell/presentation/cashier_components.dart';
import '../../cashier_shell/presentation/cashier_section_visibility.dart';
import '../data/cashier_shift_repository.dart';
import '../domain/cashier_shift.dart';
import '../../cashier_shell/presentation/cashier_tokens.dart';
import 'cashier_shift_workbench.dart';

class CashierShiftPage extends StatefulWidget {
  const CashierShiftPage({
    super.key,
    required this.repository,
    required this.canViewReport,
    required this.canSettleDaily,
    this.shopId,
    this.currentAccount,
    this.onShiftStatusChanged,
    this.now,
  });

  final CashierShiftRepository repository;
  final bool canViewReport;
  final bool canSettleDaily;
  final int? shopId;
  final String? currentAccount;
  final ValueChanged<bool>? onShiftStatusChanged;
  final DateTime Function()? now;

  @override
  State<CashierShiftPage> createState() => _CashierShiftPageState();
}

class _CashierShiftPageState extends State<CashierShiftPage>
    with CashierSectionVisibilityMixin {
  CashierShift? shift;
  CashierTodayReport? report;
  CashierShiftWorkbenchData? workbench;
  CashierHandoverResult? handoverResult;
  CashierDailySummary? dailySummary;
  DailyPrecheckResult? dailyPrecheck;
  String? error;
  String? reportError;
  String? workbenchError;
  String? dailyError;
  bool loading = true;
  bool reportLoading = false;
  bool operationInFlight = false;
  bool dailyLoading = false;
  String? _dailySettleBusinessDay;
  String? _dailySettleIdempotencyKey;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant CashierShiftPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.shopId != widget.shopId ||
        oldWidget.canViewReport != widget.canViewReport ||
        oldWidget.canSettleDaily != widget.canSettleDaily ||
        oldWidget.repository != widget.repository) {
      _load();
    }
  }

  /// 侧边栏切回可见 / 可见轮询：静默刷新当班与报表；
  /// 开班/交班操作进行中跳过本轮，失败保留旧数据。
  @override
  Future<void> refreshSectionSilently() async {
    if (operationInFlight) return;
    await _load(silent: true);
  }

  Future<void> _load({bool silent = false}) async {
    if (mounted && !silent) {
      setState(() {
        loading = true;
        error = null;
        reportError = null;
        workbenchError = null;
      });
    }
    try {
      final current = await widget.repository.loadCurrentShift();
      if (mounted) setState(() => shift = current);
    } catch (exception) {
      if (mounted && !silent) setState(() => error = '$exception');
    }
    try {
      final nextWorkbench = await widget.repository.loadWorkbench(
        shopId: widget.shopId,
      );
      if (mounted) setState(() => workbench = nextWorkbench);
    } catch (exception) {
      if (mounted && !silent) setState(() => workbenchError = '$exception');
    }
    if (widget.canViewReport) {
      await _loadReport(silent: silent);
    } else if (mounted) {
      setState(() {
        report = null;
        reportError = null;
        reportLoading = false;
      });
    }
    if (widget.canSettleDaily) {
      await _loadDaily(silent: silent);
    } else if (mounted) {
      setState(() => dailySummary = null);
    }
    if (mounted && !silent) setState(() => loading = false);
  }

  Future<void> _loadReport({bool silent = false}) async {
    if (!widget.canViewReport) {
      if (mounted) {
        setState(() {
          report = null;
          reportError = null;
          reportLoading = false;
        });
      }
      return;
    }
    if (mounted && !silent) {
      setState(() {
        reportLoading = true;
        reportError = null;
      });
    }
    try {
      final today = await widget.repository.loadTodayReport(
        shopId: widget.shopId,
      );
      if (mounted) {
        setState(() {
          report = today;
          reportError = null;
          reportLoading = false;
        });
      }
    } catch (exception) {
      if (mounted) {
        setState(() {
          reportError = '$exception';
          reportLoading = false;
        });
      }
    }
  }

  /// 遵循 OpenAPI 时间窗口统一标准（D031 / BUG042）：日结接口 stat_date 可选。
  /// 未选择特定历史日期时传 null，由后端自动按当前活动营业班次的完整 24 小时周期（以门店 settle_time 为准）聚合；
  /// 若今日简报已返回服务端权威结算日则使用之。
  String? _settlementDate() => report?.settlementDate;

  Future<void> _loadDaily({
    bool silent = false,
    String? targetBusinessDay,
  }) async {
    if (!widget.canSettleDaily) return;
    if (mounted && !silent) {
      setState(() {
        dailyLoading = true;
        dailyError = null;
      });
    }
    final statDate = targetBusinessDay ?? _settlementDate();
    try {
      final results = await Future.wait<Object>([
        widget.repository.loadDailySummary(
          statDate: statDate,
          shopId: widget.shopId,
        ),
        widget.repository.loadDailyChannels(
          statDate: statDate,
          shopId: widget.shopId,
        ),
      ]);
      final summary = results[0] as CashierDailySummary;
      final channels = results[1] as Map<String, double>;
      if (mounted) {
        setState(() {
          dailySummary = CashierDailySummary(
            statDate: summary.statDate,
            totalAmount: summary.totalAmount,
            discountAmount: summary.discountAmount,
            refundAmount: summary.refundAmount,
            settled: summary.settled,
            settledAt: summary.settledAt,
            channels: channels,
          );
          dailyLoading = false;
        });
      }
    } catch (exception) {
      if (mounted && !silent) {
        setState(() {
          dailyLoading = false;
          dailyError = '$exception';
        });
      }
    }
  }

  Future<String> _resolveAccount() async {
    final direct = widget.currentAccount?.trim();
    if (direct != null && direct.isNotEmpty) {
      return direct;
    }
    final accounts = await CashierAccountStorage().getSavedAccounts();
    if (accounts.isNotEmpty && accounts.first.isNotEmpty) {
      return accounts.first;
    }
    return 'admin';
  }

  Future<void> _settleDaily({
    String? targetBusinessDay,
    BuildContext? hostContext,
    DailyPrecheckResult? hostPrecheck,
  }) async {
    final effectiveContext = hostContext ?? context;
    if (operationInFlight || dailyLoading) return;
    final statDate = targetBusinessDay ?? dailySummary?.statDate;
    if (statDate == null || statDate.isEmpty) {
      if (effectiveContext.mounted) {
        ScaffoldMessenger.of(
          effectiveContext,
        ).showSnackBar(const SnackBar(content: Text('未找到有效的待结营业日')));
      }
      return;
    }

    if (_dailySettleBusinessDay != statDate ||
        _dailySettleIdempotencyKey == null) {
      _dailySettleBusinessDay = statDate;
      _dailySettleIdempotencyKey = _financialOperationKey('daily-close');
    }

    // 1. 日结预检门禁 (POS-SDC-301)
    setState(() {
      operationInFlight = true;
      dailyError = null;
    });
    DailyPrecheckResult? precheck = hostPrecheck;
    try {
      precheck = await widget.repository.precheckDaily(
        statDate: statDate,
        shopId: widget.shopId,
      );
    } catch (e) {
      if (!mounted) return;
      final isSeqError =
          e.toString().contains('DAILY_CLOSE_OUT_OF_SEQUENCE') ||
          e.toString().contains('409');
      final errorText = isSeqError ? '日结时序冲突：存在更早的未结营业日，请先结更早日期。' : '日结预检失败：$e';
      setState(() {
        operationInFlight = false;
        dailyError = errorText;
      });
      if (effectiveContext.mounted) {
        ScaffoldMessenger.of(effectiveContext).showSnackBar(
          SnackBar(
            content: Text(errorText),
            backgroundColor: Theme.of(effectiveContext).colorScheme.error,
          ),
        );
      }
      if (isSeqError) {
        await _loadDaily();
      }
      return;
    } finally {
      if (mounted) setState(() => operationInFlight = false);
    }

    if (!mounted || !effectiveContext.mounted) return;

    if (precheck.isAlreadySettled) {
      ScaffoldMessenger.of(
        effectiveContext,
      ).showSnackBar(SnackBar(content: Text('营业日 $statDate 已完成日结，已为您打开 Z 报表')));
      await _viewZReport(statDate: statDate, hostContext: effectiveContext);
      return;
    }

    // 2. 若存在阻断项，弹出阻断明细对话框，阻止日结
    if (precheck.blockers.isNotEmpty) {
      await showDialog<void>(
        context: effectiveContext,
        barrierDismissible: false,
        builder: (dialogCtx) => _DailyPrecheckBlockersDialog(
          precheck: precheck!,
          onVoidStaleTakeout: () async {
            final result = await widget.repository.voidStaleTakeoutOrders(
              statDate: statDate,
              shopId: widget.shopId,
            );
            if (effectiveContext.mounted) {
              ScaffoldMessenger.of(effectiveContext).showSnackBar(
                SnackBar(
                  content: Text(
                    '已作废 ${result.voidedCount} 笔超时打包单（释放 ¥${result.voidedAmount.toStringAsFixed(2)}），正在重新预检...',
                  ),
                ),
              );
            }
            // 自动重新触发预检以更新阻断状态
            _settleDaily(
              targetBusinessDay: statDate,
              hostContext: effectiveContext,
            );
          },
        ),
      );
      return;
    }

    if (!precheck.canSettle ||
        precheck.precheckToken == null ||
        precheck.precheckToken!.isEmpty) {
      final msg = '日结预检未签发有效凭据，请重新预检后再试。';
      setState(() {
        dailyError = msg;
      });
      if (effectiveContext.mounted) {
        ScaffoldMessenger.of(effectiveContext).showSnackBar(
          SnackBar(
            content: Text(msg),
            backgroundColor: Theme.of(effectiveContext).colorScheme.error,
          ),
        );
      }
      return;
    }

    // 3. 预检通过，弹出二次认证确认框
    final account = await _resolveAccount();
    if (!mounted || !effectiveContext.mounted) return;

    final effectiveSummary =
        (dailySummary != null && dailySummary!.statDate == statDate)
        ? dailySummary!
        : CashierDailySummary(
            statDate: statDate,
            totalAmount: (precheck.preview['net_sales_fen'] is num)
                ? (precheck.preview['net_sales_fen'] as num) / 100.0
                : (precheck.preview['gross_sales_fen'] is num)
                ? (precheck.preview['gross_sales_fen'] as num) / 100.0
                : 0.0,
            refundAmount: (precheck.preview['refund_amount_fen'] is num)
                ? (precheck.preview['refund_amount_fen'] as num) / 100.0
                : 0.0,
            discountAmount: (precheck.preview['discount_amount_fen'] is num)
                ? (precheck.preview['discount_amount_fen'] as num) / 100.0
                : 0.0,
            settled: false,
          );

    final confirmedPassword = await showDialog<String>(
      context: effectiveContext,
      barrierDismissible: false,
      builder: (dialogContext) => _SettleAuthConfirmDialog(
        summary: effectiveSummary,
        account: account,
        repository: widget.repository,
        activeShift: shift,
        precheck: precheck,
      ),
    );
    if (confirmedPassword == null || !mounted) return;
    setState(() {
      operationInFlight = true;
      dailyError = null;
    });
    try {
      final res = await widget.repository.settleDaily(
        statDate: statDate,
        shopId: widget.shopId,
        precheckToken: precheck.precheckToken,
        password: confirmedPassword,
        force: true,
        idempotencyKey: _dailySettleIdempotencyKey,
      );
      _dailySettleBusinessDay = null;
      _dailySettleIdempotencyKey = null;
      if (!mounted) return;
      await _loadDaily();
      if (!mounted) return;
      setState(() => operationInFlight = false);
      if (effectiveContext.mounted) {
        ScaffoldMessenger.of(effectiveContext).showSnackBar(
          SnackBar(
            content: Text('营业日 ${res.statDate} 日结成功！'),
            backgroundColor: Colors.green.shade700,
          ),
        );
      }
      // 日结成功后自动弹出商用 Z 报表
      await _viewZReport(statDate: res.statDate, hostContext: effectiveContext);
    } catch (exception) {
      if (!mounted) return;
      final isSeqError =
          exception.toString().contains('DAILY_CLOSE_OUT_OF_SEQUENCE') ||
          exception.toString().contains('409');
      final errorMsg = isSeqError
          ? '日结时序冲突：存在更早的未结营业日，正在自动刷新至最早待结日...'
          : '日结失败：$exception';
      setState(() {
        operationInFlight = false;
        dailyError = errorMsg;
      });
      if (effectiveContext.mounted) {
        ScaffoldMessenger.of(effectiveContext).showSnackBar(
          SnackBar(
            content: Text(errorMsg),
            backgroundColor: Theme.of(effectiveContext).colorScheme.error,
          ),
        );
      }
      if (isSeqError) {
        await _loadDaily();
      }
    } finally {
      if (mounted) setState(() => operationInFlight = false);
    }
  }

  Future<void> _viewZReport({
    String? statDate,
    BuildContext? hostContext,
  }) async {
    final effectiveContext = hostContext ?? context;
    final targetDate = statDate ?? dailySummary?.statDate;
    if (targetDate == null || targetDate.isEmpty) return;
    setState(() => operationInFlight = true);
    try {
      final report = await widget.repository.loadZReport(
        statDate: targetDate,
        shopId: widget.shopId,
      );
      if (!mounted) return;
      setState(() => operationInFlight = false);
      if (!effectiveContext.mounted) return;
      await Navigator.of(effectiveContext).push<void>(
        MaterialPageRoute(
          builder: (routeContext) => CashierZReportPage(
            report: report,
            onPrint: () async {
              final shiftId = shift?.id ?? handoverResult?.sessionId ?? 0;
              if (shiftId > 0) {
                try {
                  await widget.repository.reprintShiftTicket(shiftId);
                  if (routeContext.mounted) {
                    ScaffoldMessenger.of(routeContext).showSnackBar(
                      const SnackBar(content: Text('已重新发送 Z 报表打印任务至收银打印机')),
                    );
                  }
                } catch (err) {
                  if (routeContext.mounted) {
                    ScaffoldMessenger.of(
                      routeContext,
                    ).showSnackBar(SnackBar(content: Text('Z 报表打印失败: $err')));
                  }
                }
              } else {
                ScaffoldMessenger.of(routeContext).showSnackBar(
                  const SnackBar(content: Text('已重新发送 Z 报表打印任务至收银打印机')),
                );
              }
            },
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        operationInFlight = false;
        dailyError = '获取Z报表失败：$e';
      });
    }
  }

  Future<void> _openCashDialog({required bool starting}) async {
    if (operationInFlight) return;
    final activeShift = starting ? null : shift;
    final idempotencyKey = _financialOperationKey(
      starting ? 'shift-open' : 'shift-close',
    );
    final handoverEndTime = starting ? null : (widget.now ?? DateTime.now)();
    final account = await _resolveAccount();
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => _ShiftCashDialog(
        starting: starting,
        shift: activeShift,
        handoverEndTime: handoverEndTime,
        account: account,
        repository: widget.repository,
        onSubmit:
            (value, {varianceReasonCode, varianceNote, approvedBy}) async {
              setState(() => operationInFlight = true);
              try {
                if (starting) {
                  final next = await widget.repository.startShift(
                    startCash: value,
                    shopId: widget.shopId,
                    idempotencyKey: idempotencyKey,
                  );
                  if (mounted) {
                    setState(() {
                      shift = next;
                      handoverResult = null;
                      error = null;
                    });
                    widget.onShiftStatusChanged?.call(true);
                  }
                } else {
                  final result = await widget.repository.handover(
                    endCash: value,
                    countedCash: value,
                    varianceReasonCode: varianceReasonCode,
                    varianceNote: varianceNote,
                    approvedBy: approvedBy,
                    shopId: widget.shopId,
                    idempotencyKey: idempotencyKey,
                  );
                  if (mounted) {
                    setState(() {
                      shift = null;
                      handoverResult = result;
                      error = null;
                    });
                    widget.onShiftStatusChanged?.call(false);
                  }
                }
              } finally {
                if (mounted) setState(() => operationInFlight = false);
              }
            },
      ),
    );
  }

  Future<void> _openCashMovementDialog() async {
    if (operationInFlight || shift == null) return;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => _CashMovementDialog(
        repository: widget.repository,
        shopId: widget.shopId,
        onSuccess: () {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('钱箱现金变动已记录入不可变流水')));
        },
      ),
    );
  }

  Future<void> _viewShiftReport(int sessionId) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (routeContext) => CashierShiftDetailPage(
          sessionId: sessionId,
          repository: widget.repository,
          shopId: widget.shopId,
        ),
      ),
    );
  }

  Future<void> _viewShiftHistory() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (routeContext) => CashierShiftHistoryPage(
          repository: widget.repository,
          shopId: widget.shopId,
        ),
      ),
    );
  }

  Future<void> _viewCashEvents(int sessionId) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (routeContext) => CashierCashEventsPage(
          sessionId: sessionId,
          repository: widget.repository,
          shopId: widget.shopId,
        ),
      ),
    );
  }

  Future<void> _viewZReportHistory() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (routeContext) => CashierZReportHistoryListPage(
          repository: widget.repository,
          shopId: widget.shopId,
          onOpenReport: (businessDay) =>
              _viewZReport(statDate: businessDay, hostContext: routeContext),
          onOpenDailyClose: (businessDay) =>
              _openDailyClose(targetBusinessDay: businessDay),
        ),
      ),
    );
  }

  Future<void> _openDailyClose({String? targetBusinessDay}) async {
    final summary = dailySummary;
    if (summary == null && targetBusinessDay == null) return;
    final effectiveSummary =
        summary ??
        CashierDailySummary(
          statDate: targetBusinessDay ?? '',
          totalAmount: 0,
          discountAmount: 0,
          refundAmount: 0,
          settled: false,
        );
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (routeContext) => CashierDailyClosePage(
          repository: widget.repository,
          summary: effectiveSummary,
          shopId: widget.shopId,
          targetBusinessDay: targetBusinessDay,
          onSettle: ({targetBusinessDay, precheck, context}) => _settleDaily(
            targetBusinessDay: targetBusinessDay,
            hostContext: context ?? routeContext,
            hostPrecheck: precheck,
          ),
        ),
      ),
    );
  }

  Future<void> _reprintTicket(CashierHandoverResult result) async {
    final shiftId =
        result.sessionId ?? result.drawerSessionId ?? shift?.id ?? 0;
    if (shiftId <= 0) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('缺少有效班次ID，无法打印交班小票')));
      return;
    }
    try {
      await widget.repository.reprintShiftTicket(shiftId);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '交班小票已派发打印（班次 #$shiftId，订单 ${result.orderCount} 笔，金额 ¥${formatCashierMoney(result.totalAmount)}）',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('交班小票打印失败: $e'),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (loading && shift == null && error == null) {
      return const CashierStateView(
        state: CashierViewState.loading,
        title: '正在读取班次',
        message: '请稍候',
      );
    }
    if (error != null && shift == null) {
      return CashierStateView(
        state: CashierViewState.error,
        title: '班次加载失败',
        message: error!,
        actionLabel: '重试',
        onAction: _load,
      );
    }
    return CashierShiftWorkbench(
      shift: shift,
      workbench: workbench,
      report: report,
      reportLoading: reportLoading,
      reportError: reportError,
      onRetryReport: () => _loadReport(),
      fallbackChannels: dailySummary?.channels,
      dailySummary: dailySummary,
      dailyPrecheck: dailyPrecheck,
      handoverResult: handoverResult,
      canViewReport: widget.canViewReport,
      canSettleDaily: widget.canSettleDaily,
      busy: operationInFlight || dailyLoading,
      onRefresh: _load,
      onStart: () => _openCashDialog(starting: true),
      onHandover: () => _openCashDialog(starting: false),
      onCashMovement: shift == null ? null : _openCashMovementDialog,
      onOpenShiftDetail:
          handoverResult?.sessionId != null ||
              handoverResult?.drawerSessionId != null
          ? () => _viewShiftReport(
              handoverResult!.sessionId ?? handoverResult!.drawerSessionId!,
            )
          : null,
      onOpenShiftHistory: _viewShiftHistory,
      onOpenPreviousCashEvents: workbench?.previousShift == null
          ? null
          : () => _viewCashEvents(workbench!.previousShift!.sessionId),
      onOpenDailyClose: dailySummary == null ? null : _openDailyClose,
      onOpenZReport: dailySummary?.settled == true
          ? () => _viewZReport()
          : null,
      onOpenZReportHistory: widget.canSettleDaily ? _viewZReportHistory : null,
      onReprintHandover: handoverResult == null
          ? null
          : () => _reprintTicket(handoverResult!),
      now: (widget.now ?? DateTime.now)(),
    );
  }
}

typedef ShiftCashSubmitCallback =
    Future<void> Function(
      double value, {
      String? varianceReasonCode,
      String? varianceNote,
      int? approvedBy,
    });

class _ShiftCashDialog extends StatefulWidget {
  const _ShiftCashDialog({
    required this.starting,
    required this.shift,
    required this.handoverEndTime,
    required this.onSubmit,
    this.account,
    this.repository,
  });

  final bool starting;
  final CashierShift? shift;
  final DateTime? handoverEndTime;
  final ShiftCashSubmitCallback onSubmit;
  final String? account;
  final CashierShiftRepository? repository;

  @override
  State<_ShiftCashDialog> createState() => _ShiftCashDialogState();
}

class _ShiftCashDialogState extends State<_ShiftCashDialog> {
  final controller = TextEditingController();
  double? countedCash;
  String? inputError;
  bool busy = false;
  bool showDenominations = false;
  int handoverStep = 1;
  final Map<double, int> denominationCounts = {
    100.0: 0,
    50.0: 0,
    20.0: 0,
    10.0: 0,
    5.0: 0,
    1.0: 0,
    0.5: 0,
    0.1: 0,
  };

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  void _updateDenomination(double denom, int delta) {
    final current = denominationCounts[denom] ?? 0;
    final next = (current + delta).clamp(0, 9999);
    setState(() {
      denominationCounts[denom] = next;
      final sum = denominationCounts.entries.fold<double>(
        0.0,
        (prev, e) => prev + e.key * e.value,
      );
      if (sum > 0) {
        controller.text = sum.toStringAsFixed(2);
        countedCash = sum;
      }
    });
  }

  Future<void> submit({
    String? varianceReasonCode,
    String? varianceNote,
    int? approvedBy,
  }) async {
    if (busy) return;
    final value = double.tryParse(controller.text.trim());
    if (value == null || !value.isFinite || value < 0) {
      setState(() => inputError = '请输入有效的非负金额');
      return;
    }
    setState(() {
      busy = true;
      inputError = null;
    });
    try {
      await widget.onSubmit(
        value,
        varianceReasonCode: varianceReasonCode,
        varianceNote: varianceNote,
        approvedBy: approvedBy,
      );
      if (mounted) Navigator.of(context).pop();
    } catch (exception) {
      if (!mounted) return;
      final errorMsg = '$exception';
      if (!widget.starting &&
          (errorMsg.contains('长短款') ||
              errorMsg.contains('审批') ||
              errorMsg.contains('超过50元')) &&
          widget.repository != null &&
          varianceReasonCode == null) {
        setState(() => busy = false);
        final approval = await showDialog<Map<String, Object?>>(
          context: context,
          barrierDismissible: false,
          builder: (dialogCtx) => _ManagerVarianceApprovalDialog(
            countedCash: value,
            account: widget.account ?? 'admin',
            repository: widget.repository!,
          ),
        );
        if (approval != null && mounted) {
          await submit(
            varianceReasonCode: approval['reasonCode']?.toString(),
            varianceNote: approval['note']?.toString(),
            approvedBy: approval['approvedBy'] as int? ?? 1,
          );
        }
      } else {
        setState(() {
          busy = false;
          inputError = errorMsg;
        });
      }
    }
  }

  void _advanceOrSubmit() {
    if (widget.starting || handoverStep == 2) {
      submit();
      return;
    }
    final value = double.tryParse(controller.text.trim());
    if (value == null || !value.isFinite || value < 0) {
      setState(() => inputError = '请输入有效的非负金额');
      return;
    }
    setState(() {
      countedCash = value;
      inputError = null;
      handoverStep = 2;
    });
  }

  @override
  Widget build(BuildContext context) {
    final activeShift = widget.shift;
    return CashierDialogFrame(
      title: widget.starting ? '确认开班' : '盲盘交班',
      subtitle: widget.starting
          ? '核对责任终端与钱箱后，录入本班备用金。'
          : '系统不会显示应有现金。请按钱箱内实物独立清点。',
      compact: true,
      width: widget.starting ? 620 : 780,
      height: widget.starting ? 500 : (showDenominations ? 720 : 570),
      busy: busy,
      onClose: busy ? null : () => Navigator.of(context).pop(),
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (!widget.starting) ...[
              _BlindCountStepper(step: handoverStep),
              const SizedBox(height: 18),
            ],
            Text(
              widget.starting
                  ? '请核对备用金，开班后将开始记录本班次。'
                  : '请清点钱箱内所有现金并输入盘点总额。根据财务风控规范，交班采用盲盘机制，系统不显示系统应有现金。',
              style: const TextStyle(fontSize: 16),
            ),
            if (activeShift != null) ...[
              const SizedBox(height: 16),
              Wrap(
                spacing: 24,
                runSpacing: 12,
                children: [
                  _ConfirmationMetric(
                    label: '订单数',
                    value: '${activeShift.orderCount} 笔',
                  ),
                  _ConfirmationMetric(
                    label: '盘点现金',
                    value: countedCash == null
                        ? '--'
                        : '¥ ${formatCashierMoney(countedCash)}',
                  ),
                  _ConfirmationMetric(
                    label: '班次开始',
                    value: _time(activeShift.startTime),
                  ),
                  _ConfirmationMetric(
                    label: '班次截至',
                    value: _time(widget.handoverEndTime),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    key: const Key('shift-cash-input'),
                    controller: controller,
                    autofocus: true,
                    enabled: !busy,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(
                        RegExp(r'^\d*\.?\d{0,2}'),
                      ),
                    ],
                    onChanged: (text) {
                      setState(() {
                        countedCash = double.tryParse(text.trim());
                        handoverStep = 1;
                      });
                    },
                    onSubmitted: (_) => submit(),
                    decoration: InputDecoration(
                      labelText: widget.starting ? '开班备用金' : '盲盘实点现金',
                      prefixText: '¥ ',
                      errorText: inputError,
                      border: const OutlineInputBorder(),
                    ),
                  ),
                ),
                if (!widget.starting) ...[
                  const SizedBox(width: 12),
                  OutlinedButton.icon(
                    key: const Key('toggle-denominations-button'),
                    icon: Icon(
                      showDenominations
                          ? Icons.keyboard_arrow_up
                          : Icons.calculate_outlined,
                    ),
                    label: Text(showDenominations ? '收起点钞' : '面额点钞助手'),
                    onPressed: () =>
                        setState(() => showDenominations = !showDenominations),
                  ),
                ],
              ],
            ),
            if (!widget.starting && showDenominations) ...[
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: context.cashier.surface,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: context.cashier.border),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      '面额快捷点钞（张/枚数）：',
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 12,
                      runSpacing: 8,
                      children: denominationCounts.entries.map((entry) {
                        final denom = entry.key;
                        final count = entry.value;
                        final label = denom >= 1
                            ? '${denom.toInt()}元'
                            : '${(denom * 10).toInt()}角';
                        return Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: context.cashier.row,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                '$label: ',
                                style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              IconButton(
                                icon: const Icon(
                                  Icons.remove_circle_outline,
                                  size: 16,
                                ),
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints(),
                                onPressed: count > 0
                                    ? () => _updateDenomination(denom, -1)
                                    : null,
                              ),
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                ),
                                child: Text(
                                  '$count',
                                  style: const TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                              IconButton(
                                icon: const Icon(
                                  Icons.add_circle_outline,
                                  size: 16,
                                ),
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints(),
                                onPressed: () => _updateDenomination(denom, 1),
                              ),
                              const SizedBox(width: 4),
                              Text(
                                '¥${formatCashierMoney(denom * count)}',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: context.cashier.inkMuted,
                                ),
                              ),
                            ],
                          ),
                        );
                      }).toList(),
                    ),
                  ],
                ),
              ),
            ],
            if (!widget.starting && handoverStep == 2) ...[
              const SizedBox(height: 16),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(13),
                decoration: BoxDecoration(
                  color: context.cashier.warningBackground,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '请复核实点金额 ¥ ${formatCashierMoney(countedCash)}。提交后服务端才会计算差额；超过 ¥50.00 时必须由店长授权。',
                  style: TextStyle(
                    color: context.cashier.warning,
                    fontSize: 13,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        CashierActionButton(
          label: !widget.starting && handoverStep == 2 ? '返回重新点钞' : '取消',
          variant: CashierActionButtonVariant.secondary,
          onPressed: busy
              ? null
              : () {
                  if (!widget.starting && handoverStep == 2) {
                    setState(() => handoverStep = 1);
                  } else {
                    Navigator.of(context).pop();
                  }
                },
          minimumWidth: 120,
        ),
        CashierActionButton(
          key: const Key('shift-cash-submit-button'),
          label: widget.starting
              ? '确认开班'
              : handoverStep == 1
              ? '下一步：复核金额'
              : '确认提交交班',
          variant: widget.starting
              ? CashierActionButtonVariant.success
              : CashierActionButtonVariant.primary,
          onPressed: busy ? null : _advanceOrSubmit,
          busy: busy,
        ),
      ],
    );
  }
}

class _BlindCountStepper extends StatelessWidget {
  const _BlindCountStepper({required this.step});
  final int step;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      _BlindStep(index: 1, label: '清点现金', active: step >= 1),
      Expanded(child: Divider(color: context.cashier.border)),
      _BlindStep(index: 2, label: '复核提交', active: step >= 2),
      Expanded(child: Divider(color: context.cashier.border)),
      const _BlindStep(index: 3, label: '交班结果', active: false),
    ],
  );
}

class _BlindStep extends StatelessWidget {
  const _BlindStep({
    required this.index,
    required this.label,
    required this.active,
  });
  final int index;
  final String label;
  final bool active;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(
        width: 26,
        height: 26,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: active ? context.cashier.selected : context.cashier.subtle,
          shape: BoxShape.circle,
        ),
        child: Text(
          '$index',
          style: TextStyle(
            color: active ? Colors.white : context.cashier.inkMuted,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      const SizedBox(width: 7),
      Text(
        label,
        style: TextStyle(
          color: active ? context.cashier.selected : context.cashier.inkMuted,
          fontWeight: FontWeight.w700,
        ),
      ),
    ],
  );
}

class _ConfirmationMetric extends StatelessWidget {
  const _ConfirmationMetric({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 190,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: TextStyle(color: context.cashier.inkMuted)),
        const SizedBox(height: 6),
        Text(
          value,
          style: TextStyle(
            color: context.cashier.ink,
            fontSize: 20,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    ),
  );
}

class _ManagerVarianceApprovalDialog extends StatefulWidget {
  const _ManagerVarianceApprovalDialog({
    required this.countedCash,
    required this.account,
    required this.repository,
  });

  final double countedCash;
  final String account;
  final CashierShiftRepository repository;

  @override
  State<_ManagerVarianceApprovalDialog> createState() =>
      _ManagerVarianceApprovalDialogState();
}

class _ManagerVarianceApprovalDialogState
    extends State<_ManagerVarianceApprovalDialog> {
  String selectedReason = 'SHORTAGE';
  final noteController = TextEditingController();
  final passwordController = TextEditingController();
  late final accountController = TextEditingController(text: widget.account);
  bool verifying = false;
  String? verifyError;

  @override
  void dispose() {
    noteController.dispose();
    passwordController.dispose();
    accountController.dispose();
    super.dispose();
  }

  Future<void> _handleAuthorize() async {
    final note = noteController.text.trim();
    if (note.isEmpty) {
      setState(() => verifyError = '请填写长短款具体差异说明');
      return;
    }
    final account = accountController.text.trim();
    if (account.isEmpty) {
      setState(() => verifyError = '请输入审批员工号或管理员账号');
      return;
    }
    final password = passwordController.text.trim();
    if (password.isEmpty) {
      setState(() => verifyError = '请输入店长/管理账号密码进行授权');
      return;
    }
    setState(() {
      verifying = true;
      verifyError = null;
    });
    try {
      await widget.repository.verifyPassword(
        username: account,
        password: password,
      );
      if (!mounted) return;
      Navigator.of(
        context,
      ).pop({'reasonCode': selectedReason, 'note': note, 'approvedBy': 1});
    } catch (e) {
      if (!mounted) return;
      String message = e.toString();
      if (message.startsWith('Exception: ')) {
        message = message.substring('Exception: '.length);
      }
      setState(() {
        verifying = false;
        verifyError =
            message.contains('密码') ||
                message.contains('账号') ||
                message.contains('工号')
            ? message
            : '授权失败：$message';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return CashierDialogFrame(
      title: '店长长短款差异授权审批',
      subtitle: '授权不会修改原始点钞记录，审批信息将永久关联本次交班。',
      compact: true,
      width: 620,
      height: 590,
      onClose: verifying ? null : () => Navigator.of(context).pop(),
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: context.cashier.warning.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: context.cashier.warning.withValues(alpha: 0.3),
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.warning_amber_rounded,
                    color: context.cashier.warning,
                    size: 24,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      '实盘现金为 ¥${formatCashierMoney(widget.countedCash)}。系统检测到长短款差异超过50元限额，根据财务规定必须店长审批并登记原因。',
                      style: TextStyle(
                        fontSize: 13,
                        color: context.cashier.ink,
                        height: 1.4,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              '差异原因分类：',
              style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
            ),
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
              key: const Key('variance-reason-dropdown'),
              initialValue: selectedReason,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                isDense: true,
              ),
              items: const [
                DropdownMenuItem(
                  value: 'SHORTAGE',
                  child: Text('SHORTAGE - 钱箱短款（少钱）'),
                ),
                DropdownMenuItem(
                  value: 'OVERAGE',
                  child: Text('OVERAGE - 钱箱长款（多钱）'),
                ),
                DropdownMenuItem(
                  value: 'SYSTEM_CALC',
                  child: Text('SYSTEM_CALC - 系统计费/退款差异'),
                ),
                DropdownMenuItem(value: 'OTHER', child: Text('OTHER - 其他特殊原因')),
              ],
              onChanged: (val) {
                if (val != null) setState(() => selectedReason = val);
              },
            ),
            const SizedBox(height: 14),
            const Text(
              '具体原因说明：',
              style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
            ),
            const SizedBox(height: 8),
            TextField(
              key: const Key('variance-note-input'),
              controller: noteController,
              decoration: const InputDecoration(
                hintText: '请输入长短款具体发生原因（必填）',
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
            const SizedBox(height: 14),
            const Text(
              '审批人身份与密码授权：',
              style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
            ),
            const SizedBox(height: 8),
            TextField(
              key: const Key('variance-manager-account-input'),
              controller: accountController,
              enabled: !verifying,
              decoration: const InputDecoration(
                labelText: '审批人员工号 / 管理员账号',
                hintText: '请输入审批员工号 (如 EMP1001) 或管理员账号',
                prefixIcon: Icon(Icons.person_outline, size: 18),
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              key: const Key('variance-manager-password-input'),
              controller: passwordController,
              enabled: !verifying,
              obscureText: true,
              decoration: InputDecoration(
                labelText: '审批人授权密码',
                hintText: '请输入审批人密码',
                prefixIcon: const Icon(Icons.lock_outline, size: 18),
                border: const OutlineInputBorder(),
                isDense: true,
                errorText: verifyError,
              ),
              onSubmitted: (_) => _handleAuthorize(),
            ),
          ],
        ),
      ),
      actions: [
        CashierActionButton(
          label: '取消',
          variant: CashierActionButtonVariant.secondary,
          onPressed: verifying ? null : () => Navigator.of(context).pop(),
        ),
        CashierActionButton(
          key: const Key('variance-approve-button'),
          label: verifying ? '验证中...' : '授权并交班',
          variant: CashierActionButtonVariant.primary,
          busy: verifying,
          onPressed: verifying ? null : _handleAuthorize,
        ),
      ],
    );
  }
}

class _CashMovementDialog extends StatefulWidget {
  const _CashMovementDialog({
    required this.repository,
    this.shopId,
    required this.onSuccess,
  });

  final CashierShiftRepository repository;
  final int? shopId;
  final VoidCallback onSuccess;

  @override
  State<_CashMovementDialog> createState() => _CashMovementDialogState();
}

class _CashMovementDialogState extends State<_CashMovementDialog> {
  String movementType = 'CASH_IN';
  final amountController = TextEditingController();
  final remarkController = TextEditingController();
  bool submitting = false;
  String? error;
  late final String idempotencyKey = _financialOperationKey('cash-movement');

  @override
  void dispose() {
    amountController.dispose();
    remarkController.dispose();
    super.dispose();
  }

  Future<void> _handleSubmit() async {
    final amount = double.tryParse(amountController.text.trim());
    if (amount == null || amount <= 0) {
      setState(() => error = '请输入有效的正数金额');
      return;
    }
    setState(() {
      submitting = true;
      error = null;
    });
    try {
      await widget.repository.recordCashMovement(
        movementType: movementType,
        amount: amount,
        remark: remarkController.text.trim(),
        shopId: widget.shopId,
        idempotencyKey: idempotencyKey,
      );
      if (!mounted) return;
      Navigator.of(context).pop();
      widget.onSuccess();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        submitting = false;
        error = '操作失败：$e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return CashierDialogFrame(
      title: '记录钱箱现金动作',
      subtitle: '所有人工动作都会写入不可变流水并关联当前班次。',
      compact: true,
      width: 620,
      height: 580,
      onClose: submitting ? null : () => Navigator.of(context).pop(),
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '所有人工钱箱变动均会记入不可变现金台账，请按实际操作记录。',
              style: TextStyle(fontSize: 13),
            ),
            const SizedBox(height: 16),
            const Text(
              '变动类型：',
              style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
            ),
            const SizedBox(height: 8),
            Row(
              key: const Key('cash-movement-type-dropdown'),
              children: [
                for (final choice in const [
                  ('CASH_IN', '零钱加钞', '增加现金'),
                  ('CASH_OUT', '现金支出', '减少现金'),
                  ('CASH_DROP', '大钞投库', '减少现金'),
                ]) ...[
                  Expanded(
                    child: _CashMovementChoice(
                      code: choice.$1,
                      label: choice.$2,
                      detail: choice.$3,
                      selected: movementType == choice.$1,
                      onTap: submitting
                          ? null
                          : () => setState(() => movementType = choice.$1),
                    ),
                  ),
                  if (choice.$1 != 'CASH_DROP') const SizedBox(width: 9),
                ],
              ],
            ),
            const SizedBox(height: 16),
            const Text(
              '变动金额：',
              style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
            ),
            const SizedBox(height: 8),
            TextField(
              key: const Key('cash-movement-amount-input'),
              controller: amountController,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: const InputDecoration(
                prefixText: '¥ ',
                hintText: '0.00',
                border: OutlineInputBorder(),
                isDense: true,
              ),
              minLines: 3,
              maxLines: 3,
            ),
            const SizedBox(height: 14),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: context.cashier.selectedBackground,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                '提交后不可编辑，只能通过后续调整事件纠错。',
                style: TextStyle(fontSize: 13, color: context.cashier.selected),
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              '操作说明/原因备注：',
              style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
            ),
            const SizedBox(height: 8),
            TextField(
              key: const Key('cash-movement-remark-input'),
              controller: remarkController,
              decoration: const InputDecoration(
                hintText: '例如：找零零钱兑换、购办公用品、投库百元大钞',
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
            if (error != null) ...[
              const SizedBox(height: 10),
              Text(
                error!,
                style: TextStyle(color: context.cashier.danger, fontSize: 12),
              ),
            ],
          ],
        ),
      ),
      actions: [
        CashierActionButton(
          label: '取消',
          variant: CashierActionButtonVariant.secondary,
          onPressed: submitting ? null : () => Navigator.of(context).pop(),
        ),
        CashierActionButton(
          key: const Key('cash-movement-confirm-button'),
          label: submitting ? '提交中...' : '确认记录',
          variant: CashierActionButtonVariant.primary,
          busy: submitting,
          onPressed: submitting ? null : _handleSubmit,
        ),
      ],
    );
  }
}

class _CashMovementChoice extends StatelessWidget {
  const _CashMovementChoice({
    required this.code,
    required this.label,
    required this.detail,
    required this.selected,
    required this.onTap,
  });
  final String code;
  final String label;
  final String detail;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Material(
    color: selected
        ? context.cashier.selectedBackground
        : context.cashier.surface,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(10),
      side: BorderSide(
        color: selected ? context.cashier.selected : context.cashier.border,
        width: selected ? 2 : 1,
      ),
    ),
    child: InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(11),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: const TextStyle(fontWeight: FontWeight.w800)),
            const SizedBox(height: 3),
            Text(
              '$code · $detail',
              style: TextStyle(fontSize: 11, color: context.cashier.inkMuted),
            ),
          ],
        ),
      ),
    ),
  );
}

class _SettleMetric extends StatelessWidget {
  const _SettleMetric({
    required this.label,
    required this.value,
    this.emphasized = false,
  });

  final String label;
  final String value;
  final bool emphasized;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: context.cashier.row,
      borderRadius: BorderRadius.circular(14),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(fontSize: 13, color: context.cashier.inkMuted),
        ),
        const SizedBox(height: 8),
        Text(
          value,
          style: TextStyle(
            fontSize: emphasized ? 24 : 22,
            fontWeight: FontWeight.w700,
            color: context.cashier.ink,
          ),
        ),
      ],
    ),
  );
}

class _SettleAuthConfirmDialog extends StatefulWidget {
  const _SettleAuthConfirmDialog({
    required this.summary,
    required this.account,
    required this.repository,
    this.activeShift,
    this.precheck,
  });

  final CashierDailySummary summary;
  final String account;
  final CashierShiftRepository repository;
  final CashierShift? activeShift;
  final DailyPrecheckResult? precheck;

  @override
  State<_SettleAuthConfirmDialog> createState() =>
      _SettleAuthConfirmDialogState();
}

class _SettleAuthConfirmDialogState extends State<_SettleAuthConfirmDialog> {
  final _passwordController = TextEditingController();
  bool _obscurePassword = true;
  bool _verifying = false;
  String? _verifyError;

  @override
  void dispose() {
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _handleConfirm() async {
    final password = _passwordController.text.trim();
    if (password.isEmpty) {
      setState(() => _verifyError = '请输入管理员密码');
      return;
    }
    setState(() {
      _verifying = true;
      _verifyError = null;
    });
    try {
      await widget.repository.verifyPassword(
        username: widget.account,
        password: password,
      );
      if (!mounted) return;
      Navigator.of(context).pop(password);
    } catch (e) {
      if (!mounted) return;
      String message = e.toString();
      if (message.startsWith('Exception: ')) {
        message = message.substring('Exception: '.length);
      }
      setState(() {
        _verifying = false;
        _verifyError =
            message.contains('密码') ||
                message.contains('账号') ||
                message.contains('工号')
            ? message
            : '验证失败：$message';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final hasActiveShift = widget.activeShift != null;
    final hasWarnings = widget.precheck?.warnings.isNotEmpty == true;
    const dialogHeight = 450.0;

    return CashierDialogFrame(
      width: 520,
      height: dialogHeight,
      title: '营业日日结关账执行确认',
      subtitle: '营业日 ${_dateLabel(widget.summary.statDate)} · 预检通过后需管理员二次认证。',
      compact: true,
      onClose: _verifying ? null : () => Navigator.pop(context, null),
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (hasActiveShift) ...[
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: context.cashier.warningBackground,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: context.cashier.warning.withValues(alpha: 0.3),
                  ),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.warning_amber_rounded,
                      color: context.cashier.warning,
                      size: 22,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        '日结不可逆警告：当前有正在当班的收银员（班次 #${widget.activeShift!.id}，备用金 ¥${formatCashierMoney(widget.activeShift!.startCash)}）。建议先完成交班；关账后将生成不可变 Z 报表。',
                        style: TextStyle(
                          fontSize: 13,
                          color: context.cashier.warning,
                          fontWeight: FontWeight.w600,
                          height: 1.4,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
            ] else if (hasWarnings) ...[
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: context.cashier.warningBackground,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: context.cashier.warning.withValues(alpha: 0.3),
                  ),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.info_outline,
                      color: context.cashier.warning,
                      size: 22,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        '预检提示：${widget.precheck!.warnings.map((w) => w.message).join("；")}。输入店长密码后将授权强制关账。',
                        style: TextStyle(
                          fontSize: 13,
                          color: context.cashier.warning,
                          fontWeight: FontWeight.w600,
                          height: 1.4,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
            ] else ...[
              Text(
                '日结预检已通过。系统将按结算日窗口原子汇总并固化锁定营业数据，生成不可变商用快照与 Z 报表。',
                style: TextStyle(
                  fontSize: 13,
                  height: 1.5,
                  color: context.cashier.inkMuted,
                ),
              ),
              const SizedBox(height: 14),
            ],
            Row(
              children: [
                Expanded(
                  child: _SettleMetric(
                    label: '全日已结订单数',
                    value: '${_precheckInt(widget.precheck, 'order_count')} 笔',
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _SettleMetric(
                    label: '全日全渠道净营收',
                    value:
                        '¥ ${formatCashierMoney(_precheckMoney(widget.precheck, 'net_sales_fen', fallback: widget.summary.totalAmount))}',
                    emphasized: true,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _SettleMetric(
                    label: '累计现金实收',
                    value:
                        '¥ ${formatCashierMoney(_precheckCash(widget.precheck))}',
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: context.cashier.surface,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: context.cashier.border),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.admin_panel_settings_outlined, size: 18),
                      const SizedBox(width: 6),
                      const Text(
                        '管理二次验证',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const Spacer(),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: context.cashier.selectedBackground,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          '当前账号: ${widget.account}',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: context.cashier.selected,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    key: const Key('cashier-daily-settle-password-input'),
                    controller: _passwordController,
                    obscureText: _obscurePassword,
                    autofocus: true,
                    textInputAction: TextInputAction.done,
                    onSubmitted: (_) => _handleConfirm(),
                    decoration: InputDecoration(
                      isDense: true,
                      hintText: '请输入当前管理账号密码以确认日结',
                      hintStyle: TextStyle(
                        fontSize: 13,
                        color: context.cashier.inkMuted,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide(color: context.cashier.border),
                      ),
                      prefixIcon: const Icon(Icons.lock_outline, size: 18),
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
                  if (_verifyError != null) ...[
                    const SizedBox(height: 6),
                    Text(
                      _verifyError!,
                      key: const Key('cashier-daily-settle-error-text'),
                      style: TextStyle(
                        fontSize: 12,
                        color: context.cashier.danger,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
      actions: [
        CashierActionButton(
          label: '取消',
          variant: CashierActionButtonVariant.secondary,
          onPressed: _verifying ? null : () => Navigator.pop(context, null),
        ),
        CashierActionButton(
          key: const Key('cashier-daily-settle-confirm-button'),
          label: _verifying ? '验证中...' : '确认关账并生成 Z 报表',
          variant: CashierActionButtonVariant.primary,
          onPressed: _verifying ? null : _handleConfirm,
        ),
      ],
    );
  }
}

/// 日结预检阻断明细对话框 (POS-SDC-301, v1.2.289 / WI-014)
class _DailyPrecheckBlockersDialog extends StatefulWidget {
  const _DailyPrecheckBlockersDialog({
    required this.precheck,
    this.onVoidStaleTakeout,
  });

  final DailyPrecheckResult precheck;
  final Future<void> Function()? onVoidStaleTakeout;

  @override
  State<_DailyPrecheckBlockersDialog> createState() =>
      _DailyPrecheckBlockersDialogState();
}

class _DailyPrecheckBlockersDialogState
    extends State<_DailyPrecheckBlockersDialog> {
  bool _operating = false;

  Future<void> _handleVoidStaleTakeout(
    VoidableStalePackTakeoutSummary summary,
  ) async {
    if (widget.onVoidStaleTakeout == null || _operating) return;

    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => CashierDialogFrame(
        title: '作废超时打包外卖订单',
        subtitle: '作废处理将清理跑单阻断并释放资源',
        compact: true,
        width: 480,
        height: 380,
        onClose: () => Navigator.of(ctx).pop(false),
        body: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xfffff7ed),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xfffed7aa)),
              ),
              child: const Row(
                children: [
                  Icon(
                    Icons.warning_amber_rounded,
                    color: Color(0xffea580c),
                    size: 22,
                  ),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '系统将自动回退菜品库存、作废后厨KDS工单、取消配送单并释放收款意向，操作已接入特权审计。堂食订单不受任何影响。',
                      style: TextStyle(
                        fontSize: 12.5,
                        color: Color(0xff9a3412),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: const Color(0xfff8fafc),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xffe2e8f0)),
              ),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        '作废单数',
                        style: TextStyle(
                          color: Color(0xff64748b),
                          fontSize: 13,
                        ),
                      ),
                      Text(
                        '${summary.count} 笔 (超时 ${summary.thresholdMinutes} 分钟)',
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        '涉及金额',
                        style: TextStyle(
                          color: Color(0xff64748b),
                          fontSize: 13,
                        ),
                      ),
                      Text(
                        '¥ ${summary.amount.toStringAsFixed(2)}',
                        style: const TextStyle(
                          color: Color(0xffdc2626),
                          fontWeight: FontWeight.w800,
                          fontSize: 15,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          CashierActionButton(
            label: '取消',
            variant: CashierActionButtonVariant.secondary,
            onPressed: () => Navigator.of(ctx).pop(false),
          ),
          CashierActionButton(
            label: '确认全部作废',
            variant: CashierActionButtonVariant.danger,
            onPressed: () => Navigator.of(ctx).pop(true),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    setState(() => _operating = true);
    try {
      await widget.onVoidStaleTakeout!();
      if (!mounted) return;
      Navigator.of(context).pop();
    } finally {
      if (mounted) setState(() => _operating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final precheck = widget.precheck;
    return CashierDialogFrame(
      title: '日结预检未通过',
      subtitle: '以下 ${precheck.blockers.length} 项阻断处理完成前不能创建关账快照。',
      compact: true,
      width: 660,
      height: 520,
      onClose: () => Navigator.of(context).pop(),
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: context.cashier.dangerBackground,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: context.cashier.danger.withValues(alpha: 0.3),
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.error_outline,
                    color: context.cashier.danger,
                    size: 24,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      '日结前检测到存在未完成业务项。为保证财务账目准确与交易可追溯，系统已阻断关账流程：',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: context.cashier.danger,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            for (final b in precheck.blockers)
              Container(
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: context.cashier.surface,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: context.cashier.border),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(6),
                          decoration: BoxDecoration(
                            color: context.cashier.dangerBackground,
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            Icons.close_rounded,
                            color: context.cashier.danger,
                            size: 16,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Text(
                                    _blockerTitle(b.code),
                                    style: const TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  CashierStatusBadge(
                                    label: b.code,
                                    variant: CashierStatusBadgeVariant.danger,
                                  ),
                                ],
                              ),
                              const SizedBox(height: 6),
                              Text(
                                b.message,
                                style: TextStyle(
                                  fontSize: 13,
                                  color: context.cashier.inkMuted,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    if (b.voidablePackTakeout case final summary?
                        when summary.count > 0) ...[
                      const SizedBox(height: 10),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: const Color(0xfffffbeb),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: const Color(0xfffde68a)),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Row(
                                  children: [
                                    const Icon(
                                      Icons.takeout_dining_rounded,
                                      color: Color(0xffb45309),
                                      size: 18,
                                    ),
                                    const SizedBox(width: 6),
                                    Text(
                                      '超时未支付打包/外卖单 (${summary.count}笔)',
                                      style: const TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w800,
                                        color: Color(0xff92400e),
                                      ),
                                    ),
                                  ],
                                ),
                                Text(
                                  '合计 ¥ ${summary.amount.toStringAsFixed(2)}',
                                  style: const TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w800,
                                    color: Color(0xffb91c1c),
                                  ),
                                ),
                              ],
                            ),
                            if (summary.orders.isNotEmpty) ...[
                              const SizedBox(height: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 6,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(6),
                                  border: Border.all(
                                    color: const Color(0xfffef3c7),
                                  ),
                                ),
                                child: Column(
                                  children: [
                                    for (final order in summary.orders)
                                      Padding(
                                        padding: const EdgeInsets.symmetric(
                                          vertical: 3,
                                        ),
                                        child: Row(
                                          mainAxisAlignment:
                                              MainAxisAlignment.spaceBetween,
                                          children: [
                                            Text(
                                              '${order.orderNo} (${order.dineInOrTakeOut})',
                                              style: const TextStyle(
                                                fontSize: 12,
                                                fontWeight: FontWeight.w600,
                                                color: Color(0xff1e293b),
                                              ),
                                            ),
                                            Text(
                                              '超 ${order.ageMinutes} 分钟 · ¥${order.settAmount.toStringAsFixed(2)}',
                                              style: const TextStyle(
                                                fontSize: 12,
                                                color: Color(0xff64748b),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                            ],
                            if (widget.onVoidStaleTakeout != null) ...[
                              const SizedBox(height: 10),
                              SizedBox(
                                width: double.infinity,
                                height: 38,
                                child: FilledButton.icon(
                                  key: const Key(
                                    'precheck-void-stale-takeout-button',
                                  ),
                                  onPressed: _operating
                                      ? null
                                      : () => _handleVoidStaleTakeout(summary),
                                  icon: _operating
                                      ? const SizedBox.square(
                                          dimension: 14,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                            color: Colors.white,
                                          ),
                                        )
                                      : const Icon(
                                          Icons.delete_sweep_outlined,
                                          size: 18,
                                        ),
                                  label: Text(
                                    _operating
                                        ? '正在作废并释放资源...'
                                        : '一键全部作废这 ${summary.count} 笔打包单 (回退库存/取消工单)',
                                    style: const TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  style: FilledButton.styleFrom(
                                    backgroundColor: const Color(0xffd97706),
                                    foregroundColor: Colors.white,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
          ],
        ),
      ),
      actions: [
        CashierActionButton(
          label: '我知道了',
          variant: CashierActionButtonVariant.primary,
          onPressed: () => Navigator.of(context).pop(),
        ),
      ],
    );
  }

  String _blockerTitle(String code) => switch (code) {
    'OPEN_DRAWER_SESSIONS' => '未关箱交班',
    'OPEN_ORDERS' => '未结账订单',
    'PENDING_PAYMENTS' => '待确认支付',
    'UNAPPROVED_CASH_VARIANCES' => '差额未审批',
    _ => '阻断项',
  };
}

String _time(DateTime? value) {
  if (value == null) return '--';
  return '${_two(value.month)}-${_two(value.day)} ${_two(value.hour)}:${_two(value.minute)}';
}

String _two(int number) => number.toString().padLeft(2, '0');

String _dateLabel(String statDate) {
  final parts = statDate.split('-');
  if (parts.length != 3) return statDate;
  return '${parts[1]}-${parts[2]}';
}

String _financialOperationKey(String scope) =>
    '$scope-${DateTime.now().microsecondsSinceEpoch}-${identityHashCode(Object())}';

double _precheckMoney(
  DailyPrecheckResult? precheck,
  String fenKey, {
  required double fallback,
}) {
  final raw = precheck?.preview[fenKey];
  return raw == null ? fallback : safeFen(raw);
}

int _precheckInt(DailyPrecheckResult? precheck, String key) {
  final raw = precheck?.preview[key];
  if (raw is num) return raw.toInt();
  return int.tryParse('$raw') ?? 0;
}

double _precheckCash(DailyPrecheckResult? precheck) {
  final rawChannels = precheck?.preview['channels'];
  if (rawChannels is List) {
    for (final raw in rawChannels.whereType<Map>()) {
      if ('${raw['code']}'.toLowerCase() == 'cash') {
        final fen = raw['net_amount_fen'];
        if (fen != null) return safeFen(fen);
      }
    }
  }
  return precheck?.channels['cash'] ?? 0;
}
