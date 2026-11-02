import 'dart:async';

import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../../core/admin_api_client.dart';
import '../../../core/terminal_device_service.dart';
import '../../auth/data/access_approval_repository.dart';
import '../../auth/domain/access_approval_models.dart';
import '../../pos/presentation/pos_notice_dialog.dart';
import 'cashier_components.dart';

/// 收银端敏感操作/超限操作的统一审批授权请求描述。
/// 由业务调用方描述"要做什么、涉及什么、为什么需要审批"，
/// 审批弹窗据此展示给现场授权人（店长/管理员）。
class CashierApprovalRequest {
  const CashierApprovalRequest({
    required this.title,
    required this.permission,
    required this.permissionLabel,
    this.bizType,
    this.bizId,
    this.amount,
    this.currentAmount,
    this.allowedAmount,
    this.reason,
    this.requiredRoles,
    this.hint,
    this.terminalId,
  });

  /// 弹窗标题（如 "退菜审批"、"改价审批"）。
  final String title;

  /// 目标权限码（如 order:operate:refund），决定授权人需要持有的权限。
  final String permission;

  /// 权限中文名（如 "退菜 / 人工退款"）。
  final String permissionLabel;

  /// 业务类型（ORDER / REFUND / DISCOUNT 等，透传给审批记录）。
  final String? bizType;

  /// 业务对象标识（订单号/账单号等）。
  final String? bizId;

  /// 本次操作涉及金额（元）。
  final double? amount;

  /// 策略超限信息：当前累计金额（元）。
  final double? currentAmount;

  /// 策略超限信息：允许的最大金额（元）。
  final double? allowedAmount;

  /// 操作原因（由收银员/系统填写）。
  final String? reason;

  /// 授权人要求（如 "需店长或管理员授权"）。
  final String? requiredRoles;

  /// 触发提示（如后端返回的 APPROVAL_REQUIRED 原文）。
  final String? hint;

  /// 收银终端编号（透传服务端 binding v2 严格绑定校验）。
  final String? terminalId;

  /// 展示用：是否存在策略超限信息。
  bool get hasLimitInfo =>
      currentAmount != null || allowedAmount != null;
}

/// 打开统一"店长现场授权"审批弹窗。
///
/// 支持三种授权方式：
/// - 账号密码 / PIN 码：店长在收银台输入凭据，服务端验证后签发审批 Token；
/// - 扫码审批（方案A）：收银端出码，店长手机扫码无密审批，彻底避免在收银台输入密码。
///
/// 返回签发成功的 [CashierApprovalGrant]（含一次性 approvalToken）；
/// 用户取消返回 null；凭证错误等失败由弹窗内联提示，不抛异常。
Future<CashierApprovalGrant?> showCashierApprovalDialog(
  BuildContext context, {
  required CashierApprovalRequest request,
  required AccessApprovalRepository repository,
  String? currentAccount,
  String? terminalId,
}) {
  return showDialog<CashierApprovalGrant>(
    context: context,
    barrierDismissible: false,
    builder: (context) => _CashierApprovalDialog(
      request: request,
      repository: repository,
      currentAccount: currentAccount,
      terminalId: terminalId,
    ),
  );
}

/// 敏感操作统一执行器（WI-062 交互状态机）：
///
/// 1. 若配置了事前评估（[preEvaluate] = true 或传入 [userId]），执行 POST /admin/access/evaluate：
///    - outcome == ALLOW → 直接提交动作；
///    - outcome == REQUIRE_APPROVAL → 打开现场授权/扫码授权弹窗，获得 approvalToken 后重试；取消/超时则终止；
///    - outcome == DENY → 提示 reasonCode / explanation，硬拒绝，不调起弹窗且不自动重试。
/// 2. 直连执行（ALLOW 或未开启事前评估时）：
///    - 命中 APPROVAL_REQUIRED（40320）或现场授权缺失 → 调起现场授权弹窗，带 token 重试；
///    - 令牌失效（ACCESS_APPROVAL_INVALID / 40321）→ 清除本地令牌，允许重新授权一次，禁止无限循环；
///    - 硬拒绝（ACCESS_EXPLICIT_DENY / ACCESS_PERMISSION_DENIED）→ 提示并硬停止；
///    - 接口权限未配置（403 系统部署异常）→ 提示接口路径与 traceId，硬停止不降级。
///
/// 返回 true 表示敏感操作已成功执行；false 表示用户取消或拒绝执行。
Future<bool> runSensitiveWithApproval({
  required BuildContext context,
  required CashierApprovalRequest request,
  required AccessApprovalRepository repository,
  required Future<void> Function(String? approvalToken) execute,
  int? userId,
  int? shopId,
  bool preEvaluate = false,
  Map<String, Object?>? evaluationContext,
}) async {
  final effectiveTerminalId = request.terminalId ??
      repository.client.terminalId ??
      TerminalDeviceService.instance.currentTerminalId;

  // 1. 若开启事前评估（preEvaluate=true 或显式传入 userId）且有有效 userId
  if (userId != null && userId > 0) {
    final effectiveUserId = userId;
    final effectiveShopId = shopId ?? repository.client.shopId;
      final evalContext = <String, Object?>{
        if (request.amount != null && request.amount! > 0)
          'amount': request.amount,
        if (request.bizType != null && request.bizType!.isNotEmpty)
          'resourceType': request.bizType,
        if (request.bizId != null && request.bizId!.isNotEmpty)
          'resourceId': request.bizId,
        if (effectiveTerminalId != null && effectiveTerminalId.isNotEmpty)
          'terminalId': effectiveTerminalId,
        ...?evaluationContext,
      };

      try {
        final decision = await repository.evaluate(
          userId: effectiveUserId,
          shopId: effectiveShopId,
          permission: request.permission,
          context: evalContext,
        );

        if (decision.isDenied) {
          if (!context.mounted) return false;
          final reason = decision.explanation?.trim().isNotEmpty == true
              ? decision.explanation!.trim()
              : (decision.reasonCode?.trim().isNotEmpty == true
                  ? '操作被拒绝 (${decision.reasonCode})'
                  : '无权限执行该敏感操作');
          await showPosNotice(
            context,
            title: '权限不足',
            message: reason,
            tone: PosNoticeTone.error,
          );
          return false;
        }

        if (decision.requiresApproval) {
          // 决策引擎三态：REQUIRE_APPROVAL → 打开现场授权/扫码授权
          final effectiveRequest = CashierApprovalRequest(
            title: request.title,
            permission: request.permission,
            permissionLabel: request.permissionLabel,
            bizType: request.bizType,
            bizId: request.bizId,
            amount: request.amount,
            currentAmount: request.currentAmount,
            allowedAmount: request.allowedAmount,
            reason: request.reason,
            requiredRoles: request.requiredRoles,
            hint: decision.explanation ?? request.hint,
            terminalId: effectiveTerminalId,
          );
          final grant = await showCashierApprovalDialog(
            context,
            request: effectiveRequest,
            repository: repository,
            terminalId: effectiveTerminalId,
          );
          if (grant == null) return false; // 用户取消授权，不提交
          return await _guardedExecute(
            context: context,
            request: effectiveRequest,
            repository: repository,
            approvalToken: grant.approvalToken,
            execute: execute,
            effectiveTerminalId: effectiveTerminalId,
          );
        }
        // outcome == ALLOW: 继续向下直接执行
      } on ApiException catch (e) {
        if (e.isPermissionMappingMissing) {
          if (!context.mounted) rethrow;
          final traceInfo = e.traceId != null && e.traceId!.isNotEmpty
              ? ' (traceId: ${e.traceId})'
              : '';
          final pathInfo = e.endpointPath != null && e.endpointPath!.isNotEmpty
              ? ' [${e.endpointPath}]'
              : '';
          await showPosNotice(
            context,
            title: '系统权限配置异常',
            message: '服务端接口权限未配置，已被安全策略拦截。$pathInfo$traceInfo',
            tone: PosNoticeTone.error,
          );
          return false;
        }
        if (e.isDeny) {
          if (!context.mounted) rethrow;
          await showPosNotice(
            context,
            title: '权限不足',
            message: e.message,
            tone: PosNoticeTone.error,
          );
          return false;
        }
      }
    }

  // 2. 直连执行（ALLOW 或未开启事前评估时默认直连，命中拦截时按需调起授权）
  return await _guardedExecute(
    context: context,
    request: request,
    repository: repository,
    approvalToken: null,
    execute: execute,
    effectiveTerminalId: effectiveTerminalId,
  );
}

Future<bool> _guardedExecute({
  required BuildContext context,
  required CashierApprovalRequest request,
  required AccessApprovalRepository repository,
  required String? approvalToken,
  required Future<void> Function(String? approvalToken) execute,
  required String? effectiveTerminalId,
}) async {
  try {
    await execute(approvalToken);
    return true;
  } on ApiException catch (error) {
    if (error.isPermissionMappingMissing) {
      if (!context.mounted) rethrow;
      final traceInfo = error.traceId != null && error.traceId!.isNotEmpty
          ? ' (traceId: ${error.traceId})'
          : '';
      final pathInfo =
          error.endpointPath != null && error.endpointPath!.isNotEmpty
              ? ' [${error.endpointPath}]'
              : '';
      await showPosNotice(
        context,
        title: '系统权限配置异常',
        message: '服务端接口权限未配置，已被安全策略拦截。$pathInfo$traceInfo',
        tone: PosNoticeTone.error,
      );
      return false;
    }
    // 权威判定：服务端显式阻断 / 拒绝（outcome == DENY），禁止自动调起授权或自动重试
    if (error.isDeny) {
      if (!context.mounted) rethrow;
      await showPosNotice(
        context,
        title: '操作被拒绝',
        message: error.message,
        tone: PosNoticeTone.error,
      );
      return false;
    }
    // 乐观并发版本冲突（HTTP 409 / ORDER_VERSION_CONFLICT，WI-064）：
    // 订单已被其他终端修改，停止重试，禁止自动调起授权或自动重放旧动作
    if (error.isOrderVersionConflict) {
      if (!context.mounted) rethrow;
      await showPosNotice(
        context,
        title: '订单版本冲突',
        message: '订单已被其他终端修改，请确认后重试',
        tone: PosNoticeTone.warning,
      );
      return false;
    }
    // 首次直接提交无 token 时若触发 REQUIRE_APPROVAL / APPROVAL_REQUIRED / 缺少现场授权
    if (approvalToken == null &&
        (error.isRequireApproval ||
            error.isApprovalRequired ||
            error.isSensitiveAuthMissing ||
            error.isApprovalInvalid)) {
      final hint = (error.isRequireApproval || error.isApprovalRequired)
          ? error.message
          : null;
      final targetPermission = error.approvalPermission ?? request.permission;
      final effectiveRequest = CashierApprovalRequest(
        title: request.title,
        permission: targetPermission,
        permissionLabel: request.permissionLabel,
        bizType: request.bizType,
        bizId: request.bizId,
        amount: request.amount,
        currentAmount: request.currentAmount,
        allowedAmount: request.allowedAmount,
        reason: request.reason,
        requiredRoles: request.requiredRoles,
        hint: hint ?? request.hint,
        terminalId: effectiveTerminalId,
      );
      final grant = await showCashierApprovalDialog(
        context,
        request: effectiveRequest,
        repository: repository,
        terminalId: effectiveTerminalId,
      );
      if (grant == null) return false;
      return await _guardedExecute(
        context: context,
        request: effectiveRequest,
        repository: repository,
        approvalToken: grant.approvalToken,
        execute: execute,
        effectiveTerminalId: effectiveTerminalId,
      );
    }
    // 已携带 token 提交但令牌失效（40321 / ACCESS_APPROVAL_INVALID）：
    // 清除本地 token，允许用户重新发起审批一次，禁止无限循环。
    if (approvalToken != null && error.isApprovalInvalid) {
      if (!context.mounted) rethrow;
      final targetPermission = error.approvalPermission ?? request.permission;
      final secondGrant = await showCashierApprovalDialog(
        context,
        request: CashierApprovalRequest(
          title: request.title,
          permission: targetPermission,
          permissionLabel: request.permissionLabel,
          bizType: request.bizType,
          bizId: request.bizId,
          amount: request.amount,
          currentAmount: request.currentAmount,
          allowedAmount: request.allowedAmount,
          reason: request.reason,
          requiredRoles: request.requiredRoles,
          hint: '授权令牌已失效或已被使用，请重新授权后再试',
          terminalId: effectiveTerminalId,
        ),
        repository: repository,
        terminalId: effectiveTerminalId,
      );
      if (secondGrant == null) return false;
      // 第二次尝试执行，若再次报 invalid 则不再弹窗重试，直接抛出！
      await execute(secondGrant.approvalToken);
      return true;
    }
    rethrow;
  }
}

/// 授权方式。
enum _ApprovalMode {
  /// 账号 + 密码。
  password,

  /// 6 位 PIN 码。
  pin,

  /// 方案A：收银端出码，店长手机扫码无密审批。
  qr,
}

class _CashierApprovalDialog extends StatefulWidget {
  const _CashierApprovalDialog({
    required this.request,
    required this.repository,
    this.currentAccount,
    this.terminalId,
  });

  final CashierApprovalRequest request;
  final AccessApprovalRepository repository;
  final String? currentAccount;
  final String? terminalId;

  @override
  State<_CashierApprovalDialog> createState() => _CashierApprovalDialogState();
}

class _CashierApprovalDialogState extends State<_CashierApprovalDialog> {
  final _accountController = TextEditingController();
  final _credentialController = TextEditingController();
  _ApprovalMode _mode = _ApprovalMode.password;
  bool _busy = false;
  String? _errorText;

  /// ---- 最近授权账号快捷选择（本门店历史成功授权人） ----
  List<RecentAuthor>? _recentAuthors;

  /// ---- 限流退避状态 ----
  int _rateLimitSeconds = 0;
  Timer? _rateLimitTimer;

  /// ---- 扫码审批（方案A）状态 ----
  CashierQrApprovalRequest? _qrRequest;
  Timer? _countdownTimer;
  Timer? _pollTimer;
  bool _polling = false;
  String? _qrError;
  int _secondsLeft = 0;

  /// 扫码结果标记：null=等待中；'REJECTED'=已驳回；'EXPIRED'=已过期。
  String? _qrResult;

  /// 当前收银终端编号（用于授权和出码请求透传）。
  String? get _terminalId {
    final tId = widget.terminalId ??
        widget.request.terminalId ??
        widget.repository.client.terminalId ??
        TerminalDeviceService.instance.currentTerminalId;
    if (tId != null && tId.trim().isNotEmpty) {
      return tId.trim();
    }
    return null;
  }

  /// 异步解析收银终端编号：优先读取同步已绑定的终端编号；
  /// 若暂时未初始化，自动触发 TerminalDeviceService 预热获取或生成。
  Future<String?> _resolveTerminalId() async {
    final current = _terminalId;
    if (current != null && current.isNotEmpty) {
      return current;
    }
    try {
      final asyncInited =
          await TerminalDeviceService.instance.getOrInitializeTerminalId();
      if (asyncInited != null && asyncInited.trim().isNotEmpty) {
        return asyncInited.trim();
      }
    } catch (_) {}
    return null;
  }

  bool get _isRateLimited => _rateLimitSeconds > 0;

  @override
  void initState() {
    super.initState();
    final account = widget.currentAccount;
    if (account != null && account.isNotEmpty) {
      _accountController.text = account;
    }
    // 若同步终端标识为空，静默预热一次，避免出码时时延
    if (_terminalId == null) {
      unawaited(TerminalDeviceService.instance.getOrInitializeTerminalId().then((_) {
        if (mounted) setState(() {});
      }));
    }
    // 静默加载最近授权账号：失败时隐藏快捷区，不阻塞授权主流程。
    unawaited(_loadRecentAuthors());
  }

  Future<void> _loadRecentAuthors() async {
    try {
      final authors = await widget.repository.loadRecentAuthors(limit: 10);
      if (!mounted) return;
      setState(() {
        _recentAuthors = authors;
      });
    } catch (_) {
      // 快捷选择为增强能力：任何失败均静默降级为纯手输。
    }
  }

  @override
  void dispose() {
    _stopQrTimers();
    _stopRateLimitTimer();
    // 弹层短命，controller 交由 GC 回收，避免退出动画期间崩溃。
    _accountController.dispose();
    _credentialController.dispose();
    super.dispose();
  }

  void _stopRateLimitTimer() {
    _rateLimitTimer?.cancel();
    _rateLimitTimer = null;
  }

  void _applyRateLimit(int seconds, {String? scope}) {
    _stopRateLimitTimer();
    final effectiveSeconds = seconds <= 0 ? 1 : seconds;
    setState(() {
      _rateLimitSeconds = effectiveSeconds;
    });
    _rateLimitTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      if (_rateLimitSeconds <= 1) {
        timer.cancel();
        setState(() {
          _rateLimitSeconds = 0;
        });
      } else {
        setState(() {
          _rateLimitSeconds--;
        });
      }
    });
  }

  /// ---- 密码 / PIN 授权路径 ----

  Future<void> _submit() async {
    if (_isRateLimited) return;
    final termId = await _resolveTerminalId();
    if (termId == null || termId.isEmpty) {
      setState(() {
        _errorText = '当前收银机尚未初始化终端标识，无法发起绑定授权，请重新登录收银端';
      });
      return;
    }
    final account = _accountController.text.trim();
    final credential = _credentialController.text;
    if (account.isEmpty || credential.isEmpty) {
      setState(() {
        _errorText = '请填写授权员工账号与${_mode == _ApprovalMode.pin ? 'PIN 码' : '密码'}';
      });
      return;
    }
    setState(() {
      _busy = true;
      _errorText = null;
    });
    final request = widget.request;
    try {
      final grant = await widget.repository.authorize(
        permission: request.permission,
        bizType: request.bizType,
        bizId: request.bizId,
        amount: request.amount,
        reason: request.reason,
        authorizerAccount: account,
        credential: credential,
        authMethod: _mode == _ApprovalMode.pin ? 'PIN' : 'PASSWORD',
        requestId:
            'approval-${DateTime.now().millisecondsSinceEpoch}',
        terminalId: termId,
      );
      if (!mounted) return;
      Navigator.of(context).pop(grant);
    } on ApiException catch (error) {
      if (!mounted) return;
      if (error.isRateLimited) {
        _applyRateLimit(
          error.retryAfterSeconds ?? 3,
          scope: error.rateLimitScope,
        );
      }
      setState(() {
        _busy = false;
        _errorText = _friendlyError(error);
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _errorText = '授权失败：$error';
      });
    }
  }

  String _friendlyError(ApiException error) {
    if (error.isRateLimited) {
      final waitSec = _rateLimitSeconds > 0
          ? _rateLimitSeconds
          : (error.retryAfterSeconds ?? 3);
      if (error.rateLimitScope == 'CREDENTIAL_FAILURE') {
        return '密码或PIN码错误次数过多，请在 $waitSec 秒后再试';
      }
      return '操作过于频繁，请在 $waitSec 秒后再试';
    }
    if (error.isAccountDisabled) return '授权员工账号已停用或已离职，无法授权';
    if (error.isAccountLocked) return '授权员工账号已锁定，请联系管理员';
    if (error.isShopOutOfScope) return '授权员工无当前门店的授权范围';
    if (error.code == 401) return '授权凭证错误，请重新输入';
    if (error.code == 403) return error.message;
    return error.message;
  }

  /// ---- 扫码审批（方案A）路径 ----

  /// 发起出码申请并开始轮询。
  Future<void> _createQr() async {
    if (_isRateLimited) return;
    final termId = await _resolveTerminalId();
    if (termId == null || termId.isEmpty) {
      setState(() {
        _qrError = '当前收银机尚未初始化终端标识，无法发起扫码审批，请重新登录收银端';
      });
      return;
    }
    final request = widget.request;
    setState(() {
      _busy = true;
      _qrError = null;
      _qrResult = null;
    });
    try {
      final qrRequest = await widget.repository.createQrApproval(
        permission: request.permission,
        bizType: request.bizType,
        bizId: request.bizId,
        amount: request.amount,
        reason: request.reason,
        requestId: 'qr-approval-${DateTime.now().millisecondsSinceEpoch}',
        terminalId: termId,
      );
      if (!mounted) return;
      _stopQrTimers();
      setState(() {
        _busy = false;
        _qrRequest = qrRequest;
        _secondsLeft = qrRequest.expireSeconds;
      });
      _startQrTimers();
    } on ApiException catch (error) {
      if (!mounted) return;
      if (error.isRateLimited) {
        _applyRateLimit(
          error.retryAfterSeconds ?? 3,
          scope: error.rateLimitScope,
        );
      }
      setState(() {
        _busy = false;
        _qrError = _friendlyQrError(error);
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _qrError = '出码失败：$error';
      });
    }
  }

  /// 重新生成二维码（驳回/过期后）。
  void _recreateQr() {
    if (_isRateLimited) return;
    _stopQrTimers();
    setState(() {
      _qrRequest = null;
      _qrError = null;
      _qrResult = null;
      _secondsLeft = 0;
    });
    _createQr();
  }

  void _startQrTimers() {
    _stopQrTimers();
    // 倒计时：每秒刷新剩余秒数。
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      final request = _qrRequest;
      if (request == null || !mounted) return;
      final deadline = request.expiresAt;
      final left = deadline == null
          ? _secondsLeft - 1
          : deadline.difference(DateTime.now()).inSeconds;
      if (left <= 0) {
        _stopQrTimers();
        if (mounted) {
          setState(() {
            _secondsLeft = 0;
            _qrResult = 'EXPIRED';
            _qrError = '二维码已过期，请重新生成';
          });
        }
        return;
      }
      if (mounted) setState(() => _secondsLeft = left);
    });
    // 轮询：每 2 秒查询一次审批状态。
    _pollTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      unawaited(_pollQrStatus());
    });
    // 立即先查一次，减少店长已快速审批时的等待。
    unawaited(_pollQrStatus());
  }

  void _stopQrTimers() {
    _countdownTimer?.cancel();
    _countdownTimer = null;
    _pollTimer?.cancel();
    _pollTimer = null;
  }

  Future<void> _pollQrStatus() async {
    final request = _qrRequest;
    if (request == null || _polling || _qrResult != null || !mounted) {
      return;
    }
    _polling = true;
    try {
      final status = await widget.repository.pollQrApprovalStatus(
        request.approvalCode,
      );
      if (!mounted) return;
      if (status.isApproved) {
        final token = status.approvalToken;
        if (token == null || token.isEmpty) {
          // 令牌尚未落缓存（极端竞态），下一轮再取。
          return;
        }
        _stopQrTimers();
        final grant = _grantFromQrStatus(status);
        Navigator.of(context).pop(grant);
        return;
      }
      if (status.isRejected) {
        _stopQrTimers();
        if (mounted) {
          setState(() {
            _qrResult = 'REJECTED';
            _qrError = status.reason == null || status.reason!.trim().isEmpty
                ? '店长已驳回本次审批'
                : '店长已驳回：${status.reason}';
          });
        }
        return;
      }
      if (status.isExpired) {
        _stopQrTimers();
        if (mounted) {
          setState(() {
            _qrResult = 'EXPIRED';
            _qrError = '二维码已过期，请重新生成';
          });
        }
        return;
      }
      // PENDING：继续等待。
    } on ApiException catch (error) {
      // 轮询瞬时失败不中断：提示后下一轮继续，直到过期或成功。
      if (mounted && _qrResult == null) {
        setState(() => _qrError = _friendlyQrError(error));
      }
    } catch (error) {
      if (mounted && _qrResult == null) {
        setState(() => _qrError = '查询审批状态失败：$error');
      }
    } finally {
      _polling = false;
    }
  }

  /// 由轮询结果组装与现场授权一致的 [CashierApprovalGrant]。
  CashierApprovalGrant _grantFromQrStatus(CashierQrApprovalStatus status) {
    return CashierApprovalGrant(
      approvalNo: status.approvalCode,
      approvalToken: status.approvalToken ?? '',
      permission: widget.request.permission,
      operatorId: 0,
      authorizerId: status.authorizerId ?? 0,
      authorizerName: status.authorizerName ?? '',
      shopId: 0,
      expiresAt: status.expiresAt,
      expireSeconds: _qrRequest?.expireSeconds ?? 120,
    );
  }

  String _friendlyQrError(ApiException error) {
    if (error.isAccountDisabled) return '账号状态异常，无法发起审批';
    if (error.isShopOutOfScope) return '当前门店无审批权限';
    if (error.code == 403) return error.message;
    return error.message;
  }

  /// 切换授权方式：离开扫码模式时停止轮询并清空二维码状态。
  void _switchMode(_ApprovalMode mode) {
    if (mode == _mode) return;
    if (_mode == _ApprovalMode.qr) {
      _stopQrTimers();
    }
    setState(() {
      _mode = mode;
      _errorText = null;
      _qrError = null;
      _qrResult = null;
      _credentialController.clear();
    });
  }

  /// ---- UI ----

  @override
  Widget build(BuildContext context) {
    final request = widget.request;
    final qrMode = _mode == _ApprovalMode.qr;
    final hasRecent =
        _recentAuthors != null && _recentAuthors!.isNotEmpty;

    // 原型规格（UI034）：宽 460；密码/PIN 模式 470 一屏；有最近账号快捷区时
    // 自适应加高；扫码模式内容多保持较高高度。
    final dialogHeight = qrMode ? 660.0 : (hasRecent ? 560.0 : 470.0);

    return CashierDialogFrame(
      key: const Key('cashier-approval-dialog'),
      title: request.title,
      subtitle: request.hint ??
          (qrMode
              ? '收银端出码，请店长手机扫码完成无密审批'
              : '请店长或管理员现场授权后继续'),
      onClose: _busy ? null : () => Navigator.of(context).pop(),
      busy: _busy,
      width: 460,
      height: dialogHeight,
      compact: false,
      // UI034 原型保真：17 标题 / 12 副标题 / 紧凑 header·body·footer / 12 圆角。
      titleFontSize: 17,
      subtitleFontSize: 12,
      headerHeight: 66,
      bodyPadding: const EdgeInsets.fromLTRB(22, 14, 22, 6),
      footerHeight: 62,
      dialogRadius: 12,
      // 原型为纯白底（#FFFFFF）。
      dialogBackgroundColor: Colors.white,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _ApprovalInfoCard(request: request),
          const SizedBox(height: 11),
          const Text(
            '授权方式',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: Color(0xFF334155),
            ),
          ),
          const SizedBox(height: 6),
          _ApprovalSegmented(
            value: _mode,
            enabled: !_busy,
            onChanged: (mode) {
              if (mode != _mode) _switchMode(mode);
            },
          ),
          const SizedBox(height: 9),
          if (qrMode)
            _buildQrBody(context)
          else ...[
            if (_recentAuthors != null && _recentAuthors!.isNotEmpty) ...[
              _buildRecentAuthors(context),
              const SizedBox(height: 10),
            ],
            TextField(
              key: const Key('approval-account'),
              controller: _accountController,
              enabled: !_busy,
              autofocus: true,
              style: const TextStyle(fontSize: 13, color: Color(0xFF334155)),
              decoration: const InputDecoration(
                labelText: '授权员工账号',
                hintText: '店长工号或用户名',
                floatingLabelBehavior: FloatingLabelBehavior.never,
                labelStyle: TextStyle(fontSize: 11, color: Color(0xFF6B7280)),
                hintStyle: TextStyle(fontSize: 13, color: Color(0xFF9CA3AF)),
                isDense: true,
                contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                prefixIcon: Icon(Icons.badge_outlined, size: 16, color: Color(0xFF9CA3AF)),
                prefixIconConstraints: BoxConstraints(minWidth: 32),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.all(Radius.circular(8)),
                  borderSide: BorderSide(color: Color(0xFFCBD5E1)),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.all(Radius.circular(8)),
                  borderSide: BorderSide(color: Color(0xFFCBD5E1)),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.all(Radius.circular(8)),
                  borderSide: BorderSide(color: Color(0xFF3B82F6), width: 1.5),
                ),
              ),
            ),
            const SizedBox(height: 9),
            TextField(
              key: const Key('approval-credential'),
              controller: _credentialController,
              enabled: !_busy,
              obscureText: true,
              onSubmitted: (_) => _submit(),
              style: const TextStyle(fontSize: 13, color: Color(0xFF334155)),
              decoration: InputDecoration(
                labelText: _mode == _ApprovalMode.pin ? 'PIN 码' : '密码',
                hintText: _mode == _ApprovalMode.pin
                    ? '请输入店长 PIN 码'
                    : '请输入店长密码',
                floatingLabelBehavior: FloatingLabelBehavior.never,
                labelStyle: const TextStyle(fontSize: 11, color: Color(0xFF6B7280)),
                hintStyle: const TextStyle(fontSize: 13, color: Color(0xFF9CA3AF)),
                isDense: true,
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                prefixIcon: const Icon(Icons.lock_outline,
                    size: 16, color: Color(0xFF9CA3AF)),
                prefixIconConstraints: const BoxConstraints(minWidth: 32),
                border: const OutlineInputBorder(
                  borderRadius: BorderRadius.all(Radius.circular(8)),
                  borderSide: BorderSide(color: Color(0xFFCBD5E1)),
                ),
                enabledBorder: const OutlineInputBorder(
                  borderRadius: BorderRadius.all(Radius.circular(8)),
                  borderSide: BorderSide(color: Color(0xFFCBD5E1)),
                ),
                focusedBorder: const OutlineInputBorder(
                  borderRadius: BorderRadius.all(Radius.circular(8)),
                  borderSide: BorderSide(color: Color(0xFF3B82F6), width: 1.5),
                ),
              ),
            ),
            if (_errorText != null) ...[
              const SizedBox(height: 10),
              _InlineErrorBanner(text: _errorText!),
            ],
          ],
        ],
      ),
      actions: qrMode ? _buildQrActions() : _buildCredentialActions(),
    );
  }

  List<Widget> _buildCredentialActions() {
    final submitDisabled = _busy || _isRateLimited;
    final submitText = _isRateLimited ? '请等待 ($_rateLimitSeconds s)' : '授权并继续';
    return [
      OutlinedButton(
        key: const Key('approval-cancel'),
        onPressed: _busy ? null : () => Navigator.of(context).pop(),
        style: OutlinedButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
          side: const BorderSide(color: Color(0xFFCBD5E1)),
          foregroundColor: const Color(0xFF475569),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
        ),
        child: const Text('取消'),
      ),
      FilledButton(
        key: const Key('approval-submit'),
        onPressed: submitDisabled ? null : _submit,
        style: FilledButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
          backgroundColor: const Color(0xFF3B82F6),
          foregroundColor: Colors.white,
          disabledBackgroundColor: const Color(0xFF93C5FD),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
        ),
        child: Text(submitText),
      ),
    ];
  }

  /// 最近授权账号快捷选择区（对齐 UI031 原型：chip 点击填入账号，仍需输密码/PIN）。
  Widget _buildRecentAuthors(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final authors = _recentAuthors!.take(5).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '最近授权账号',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: scheme.onSurface,
          ),
        ),
        const SizedBox(height: 6),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final author in authors)
              _RecentAuthorChip(
                author: author,
                selected: _accountController.text ==
                    (author.authorizerWorkNo ?? ''),
                onTap: () {
                  if (_busy) return;
                  setState(() {
                    _accountController.text = author.authorizerWorkNo ?? '';
                    _errorText = null;
                  });
                },
              ),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          '点击快捷填入账号，仍需输入${_mode == _ApprovalMode.pin ? 'PIN 码' : '密码'}',
          style: TextStyle(
            fontSize: 12,
            color: scheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          '来自本门店最近 10 次成功授权，按时间倒序去重',
          style: TextStyle(
            fontSize: 11.5,
            color: scheme.onSurfaceVariant.withValues(alpha: 0.8),
          ),
        ),
      ],
    );
  }

  List<Widget> _buildQrActions() {
    final qrRequest = _qrRequest;
    final waiting = qrRequest != null && _qrResult == null;
    final createDisabled = _busy || _isRateLimited;
    final qrButtonText = _isRateLimited
        ? '请等待 ($_rateLimitSeconds s)'
        : (qrRequest == null ? '生成审批二维码' : '重新生成二维码');
    return [
      OutlinedButton(
        key: const Key('approval-cancel'),
        onPressed: _busy ? null : () => Navigator.of(context).pop(),
        style: OutlinedButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
          side: const BorderSide(color: Color(0xFFCBD5E1)),
          foregroundColor: const Color(0xFF475569),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
        ),
        child: const Text('取消'),
      ),
      if (!waiting)
        FilledButton(
          key: const Key('approval-qr-create'),
          onPressed: createDisabled
              ? null
              : (qrRequest == null ? _createQr : _recreateQr),
          style: FilledButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
            backgroundColor: const Color(0xFF3B82F6),
            foregroundColor: Colors.white,
            disabledBackgroundColor: const Color(0xFF93C5FD),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
          ),
          child: Text(qrButtonText),
        ),
    ];
  }

  Widget _buildQrBody(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final qrRequest = _qrRequest;
    final waiting = qrRequest != null && _qrResult == null;

    if (qrRequest == null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: scheme.surfaceContainerHighest.withValues(alpha: 0.45),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: scheme.outlineVariant),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.qr_code_2, size: 26, color: scheme.primary),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '扫码无密审批',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: scheme.onSurface,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        '生成动态二维码后，请店长使用手机「门店助手」扫码，'
                        '在手机上确认或驳回本次操作。全程无需在收银台输入密码，'
                        '避免密码被偷看或被监控记录。',
                        style: TextStyle(
                          fontSize: 13,
                          height: 1.5,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          if (_qrError != null) ...[
            const SizedBox(height: 14),
            _InlineErrorBanner(text: _qrError!),
          ],
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        // 二维码卡片
        Container(
          width: 300,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: scheme.outlineVariant),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.06),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            children: [
              QrImageView(
                key: const Key('approval-qr-image'),
                data: qrRequest.qrPayload,
                version: QrVersions.auto,
                size: 240,
                backgroundColor: Colors.white,
                errorCorrectionLevel: QrErrorCorrectLevel.M,
              ),
              const SizedBox(height: 10),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    waiting ? Icons.timer_outlined : Icons.timer_off_outlined,
                    size: 16,
                    color: _secondsLeft <= 30
                        ? scheme.error
                        : scheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    waiting
                        ? '二维码 $_secondsLeft 秒后失效'
                        : '二维码已失效',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: _secondsLeft <= 30
                          ? scheme.error
                          : scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        // 等待 / 结果状态
        if (waiting) ...[
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const SizedBox.square(
                dimension: 14,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              const SizedBox(width: 10),
              Text(
                '等待店长手机扫码审批…',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: scheme.primary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            '审批通过后本窗口将自动继续',
            style: TextStyle(
              fontSize: 12,
              color: scheme.onSurfaceVariant,
            ),
          ),
        ],
        if (_qrError != null) ...[
          const SizedBox(height: 12),
          _InlineErrorBanner(text: _qrError!),
        ],
        const SizedBox(height: 12),
        // 兜底：授权码文本
        SelectableText(
          '授权码：${qrRequest.approvalCode}',
          style: TextStyle(
            fontSize: 12,
            color: scheme.onSurfaceVariant,
            fontFamily: 'Roboto',
            letterSpacing: 0.5,
          ),
        ),
      ],
    );
  }
}

/// 内联错误/提示条。
class _InlineErrorBanner extends StatelessWidget {
  const _InlineErrorBanner({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: scheme.errorContainer,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Icon(Icons.error_outline, size: 18, color: scheme.error),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                fontSize: 13,
                color: scheme.onErrorContainer,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// UI034 原型三格分段控件：等宽均分、圆角 8、选中蓝底白字（#3B82F6）。
class _ApprovalSegmented extends StatelessWidget {
  const _ApprovalSegmented({
    required this.value,
    required this.enabled,
    required this.onChanged,
  });

  final _ApprovalMode value;
  final bool enabled;
  final ValueChanged<_ApprovalMode> onChanged;

  static const _labels = <_ApprovalMode, String>{
    _ApprovalMode.password: '账号密码',
    _ApprovalMode.pin: 'PIN 码',
    _ApprovalMode.qr: '扫码审批',
  };

  @override
  Widget build(BuildContext context) {
    final modes = _ApprovalMode.values;
    return Row(
      children: [
        for (final mode in modes) ...[
          if (mode != modes.first) const SizedBox(width: 6),
          Expanded(
            child: InkWell(
              key: Key('approval-mode-${mode.name}'),
              borderRadius: BorderRadius.circular(8),
              onTap: enabled ? () => onChanged(mode) : null,
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 7),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color:
                      mode == value ? const Color(0xFF3B82F6) : Colors.white,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: mode == value
                        ? const Color(0xFF3B82F6)
                        : const Color(0xFFCBD5E1),
                  ),
                ),
                child: Text(
                  _labels[mode]!,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight:
                        mode == value ? FontWeight.w600 : FontWeight.w500,
                    color: mode == value
                        ? Colors.white
                        : const Color(0xFF475569),
                  ),
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

/// 审批信息卡片：向现场授权人展示操作对象、金额、超限原因与授权人要求。
class _ApprovalInfoCard extends StatelessWidget {
  const _ApprovalInfoCard({required this.request});

  final CashierApprovalRequest request;

  @override
  Widget build(BuildContext context) {
    // 简约化：隐藏后端英文权限码，仅展示中文授权内容与关键业务信息。
    final rows = <(String, String)>[
      ('授权内容', request.permissionLabel),
      if (request.bizId != null && request.bizId!.isNotEmpty)
        ('业务单号', request.bizId!),
      if (request.amount != null) ('涉及金额', '¥${request.amount!.toStringAsFixed(2)}'),
      if (request.hasLimitInfo)
        (
          '额度说明',
          '当前 ${_amountText(request.currentAmount)} / 允许 ${_amountText(request.allowedAmount)}',
        ),
    ];

    // UI034 原型样式：浅灰信息卡 #F1F5F9、圆角 10、紧凑 padding；
    // 行 label 左 / value 右两端对齐，金额红色加粗。
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(12, 9, 12, 9),
      decoration: BoxDecoration(
        color: const Color(0xFFF1F5F9),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final (label, value) in rows)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: const TextStyle(
                      fontSize: 12.5,
                      color: Color(0xFF64748B),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Flexible(
                    child: Text(
                      value,
                      textAlign: TextAlign.right,
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: label == '涉及金额'
                            ? FontWeight.w700
                            : FontWeight.w600,
                        color: label == '涉及金额'
                            ? const Color(0xFFDC2626)
                            : const Color(0xFF1E293B),
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

  String _amountText(double? value) =>
      value == null ? '不限' : '¥${value.toStringAsFixed(2)}';
}

/// 最近授权账号快捷选择 chip（对齐 UI031 原型：姓名 + 工号）。
class _RecentAuthorChip extends StatelessWidget {
  const _RecentAuthorChip({
    required this.author,
    required this.selected,
    required this.onTap,
  });

  final RecentAuthor author;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: selected
              ? scheme.primaryContainer.withValues(alpha: 0.55)
              : scheme.surface,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: selected ? scheme.primary : scheme.outlineVariant,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.person_outline,
              size: 14,
              color: selected ? scheme.primary : scheme.onSurfaceVariant,
            ),
            const SizedBox(width: 5),
            Text(
              author.authorizerName != null && author.authorizerName!.isNotEmpty
                  ? author.authorizerName!
                  : '店长',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: scheme.onSurface,
              ),
            ),
            const SizedBox(width: 4),
            Text(
              author.authorizerWorkNo != null &&
                      author.authorizerWorkNo!.isNotEmpty
                  ? author.authorizerWorkNo!
                  : (author.authorizerId != null
                      ? '#${author.authorizerId}'
                      : ''),
              style: TextStyle(
                fontSize: 12,
                color: scheme.onSurfaceVariant,
                fontFamily: 'Roboto',
                letterSpacing: 0.3,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
