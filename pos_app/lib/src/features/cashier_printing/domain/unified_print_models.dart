/// 统一出票与补打调度领域模型 (契约对应 POST /cashier/print/dispatch 与 POST /admin/printing/dispatch)
class UnifiedPrintScenario {
  const UnifiedPrintScenario._();

  /// 后厨制作单 / 厨房小票 (默认档口分联分发)
  static const String kitchen = 'kitchen';

  /// 结账收据 / 消费小票
  static const String checkout = 'checkout';

  /// 预结单 / 账单对账单
  static const String preCheckout = 'pre_checkout';

  /// 客看全单 / 总单
  static const String fullOrder = 'full_order';

  /// 打包出餐单
  static const String packing = 'packing';

  /// 外卖联
  static const String takeout = 'takeout';

  /// 催菜单 / 加菜单
  static const String expedite = 'expedite';

  /// 退款退单小票
  static const String refund = 'refund';

  /// 收银交接班报表小票
  static const String shift = 'shift';

  /// 杯贴 / 菜品不干胶标签
  static const String label = 'label';

  /// 打印机测试页
  static const String test = 'test';
}

/// 统一出票与补打请求体
class UnifiedPrintRequest {
  const UnifiedPrintRequest({
    this.orderNo,
    this.orderId,
    this.scenario,
    this.isReprint = true,
    this.cidList = const [],
    this.deviceId,
    this.templateId,
    this.copies,
    this.reason,
    this.shiftId,
    this.customContent,
    this.idempotencyKey,
  });

  /// 业务订单号（补打订单场景最简入参）
  final String? orderNo;

  /// 订单主键 ID
  final int? orderId;

  /// 场景枚举（kitchen, checkout, shift 等）
  final String? scenario;

  /// 是否为补打（默认 true，自动追加【补打】水印并记录存根）
  final bool isReprint;

  /// 勾选的菜品明细 ID 列表（t_order_detail.id），用于局部补打
  final List<int> cidList;

  /// 强制定向打印设备 ID（传值时将绕过规则引擎直接派发）
  final int? deviceId;

  /// 强制指定模板 ID
  final int? templateId;

  /// 强制指定打印联数
  final int? copies;

  /// 补打原因说明（如"顾客催单"、"后厨丢单"）
  final String? reason;

  /// 班次 ID（交接班出票场景）
  final int? shiftId;

  /// 自定义原始文本内容
  final String? customContent;

  /// 客户端防重复幂等 Key
  final String? idempotencyKey;

  Map<String, dynamic> toJson() {
    final map = <String, dynamic>{
      'is_reprint': isReprint,
      'isReprint': isReprint,
    };
    if (orderNo != null && orderNo!.trim().isNotEmpty) {
      final val = orderNo!.trim();
      map['order_no'] = val;
      map['orderNo'] = val;
    }
    if (orderId != null && orderId! > 0) {
      map['order_id'] = orderId;
      map['orderId'] = orderId;
    }
    if (scenario != null && scenario!.trim().isNotEmpty) {
      map['scenario'] = scenario!.trim();
    }
    if (cidList.isNotEmpty) {
      map['cid_list'] = cidList;
      map['cidList'] = cidList;
    }
    if (deviceId != null && deviceId! > 0) {
      map['device_id'] = deviceId;
      map['deviceId'] = deviceId;
    }
    if (templateId != null && templateId! > 0) {
      map['template_id'] = templateId;
      map['templateId'] = templateId;
    }
    if (copies != null && copies! > 0) {
      map['copies'] = copies;
    }
    if (reason != null && reason!.trim().isNotEmpty) {
      map['reason'] = reason!.trim();
    }
    if (shiftId != null && shiftId! > 0) {
      map['shift_id'] = shiftId;
      map['shiftId'] = shiftId;
    }
    if (customContent != null && customContent!.trim().isNotEmpty) {
      final val = customContent!.trim();
      map['custom_content'] = val;
      map['customContent'] = val;
    }
    if (idempotencyKey != null && idempotencyKey!.trim().isNotEmpty) {
      final val = idempotencyKey!.trim();
      map['idempotency_key'] = val;
      map['idempotencyKey'] = val;
    }
    return map;
  }
}

/// 单项设备出票任务结果
class PrintJobItem {
  const PrintJobItem({
    required this.jobId,
    required this.deviceId,
    required this.deviceName,
    required this.status,
    required this.copies,
    this.errorMessage,
  });

  final int jobId;
  final int deviceId;
  final String deviceName;
  final String status;
  final int copies;
  final String? errorMessage;

  bool get isSuccess => status.toUpperCase() == 'SUCCESS';
  bool get hasError => !isSuccess;

  factory PrintJobItem.fromJson(Map<String, dynamic> json) {
    return PrintJobItem(
      jobId: _int(json['job_id'] ?? json['jobId'] ?? json['id']),
      deviceId: _int(json['device_id'] ?? json['deviceId']),
      deviceName: _str(json['device_name'] ?? json['deviceName']),
      status: _str(json['status'] ?? 'SUCCESS'),
      copies: _int(json['copies'] ?? 1),
      errorMessage: json['error_message']?.toString() ?? json['errorMessage']?.toString(),
    );
  }
}

/// 统一出票响应结果聚合
class UnifiedPrintResult {
  const UnifiedPrintResult({
    required this.totalJobs,
    required this.dispatchedCount,
    required this.failedCount,
    required this.summary,
    required this.jobs,
  });

  final int totalJobs;
  final int dispatchedCount;
  final int failedCount;
  final String summary;
  final List<PrintJobItem> jobs;

  /// 全部任务派发成功且至少有一台设备接收
  bool get isSuccess => failedCount == 0 && (dispatchedCount > 0 || totalJobs == 0);

  /// 存在失败任务
  bool get hasFailures => failedCount > 0;

  /// 首个失败任务的错误信息
  String? get firstErrorMessage {
    for (final job in jobs) {
      if (job.hasError && job.errorMessage != null && job.errorMessage!.isNotEmpty) {
        return '${job.deviceName}: ${job.errorMessage}';
      }
    }
    return null;
  }

  factory UnifiedPrintResult.fromJson(Map<String, dynamic> json) {
    final rawJobs = json['jobs'];
    final parsedJobs = <PrintJobItem>[];
    if (rawJobs is List) {
      for (final item in rawJobs) {
        if (item is Map<String, dynamic>) {
          parsedJobs.add(PrintJobItem.fromJson(item));
        } else if (item is Map) {
          parsedJobs.add(PrintJobItem.fromJson(item.cast<String, dynamic>()));
        }
      }
    }

    final totalJobs = _int(json['total_jobs'] ?? json['totalJobs'] ?? parsedJobs.length);
    final dispatched = _int(json['dispatched_count'] ?? json['dispatchedCount'] ?? parsedJobs.where((j) => j.isSuccess).length);
    final failed = _int(json['failed_count'] ?? json['failedCount'] ?? parsedJobs.where((j) => j.hasError).length);
    final summary = _str(json['summary'] ?? json['msg'] ?? (failed == 0 ? '出票指令已下发' : '部分打印任务派发失败'));

    return UnifiedPrintResult(
      totalJobs: totalJobs,
      dispatchedCount: dispatched,
      failedCount: failed,
      summary: summary,
      jobs: parsedJobs,
    );
  }
}

int _int(Object? value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  if (value is String) return int.tryParse(value) ?? 0;
  return 0;
}

String _str(Object? value) {
  if (value == null) return '';
  return value.toString();
}
