class OrderQuery {
  const OrderQuery({
    this.pageNum = 1,
    this.pageSize = 20,
    this.status,
    this.keyword = '',
    this.startTime,
    this.endTime,
  });

  final int pageNum;
  final int pageSize;

  /// 交易状态：''/null=全部，'unsettled'=未结账，'success'=已结账。
  final String? status;

  /// 搜索关键词（单号/桌号等）。注意：当前后端 /admin/order/list 仅支持
  /// transac_status 过滤，未实现关键词模糊搜索；透传保留以兼容未来后端能力。
  final String keyword;

  /// 自定义时间窗口（yyyy-MM-dd HH:mm:ss）。不传时后端默认「昨天00:00～当前」，
  /// 会导致更早的历史订单查不到——分页列表场景应显式传入较宽的开始时间。
  final String? startTime;

  /// 自定义时间窗口（yyyy-MM-dd HH:mm:ss）。
  final String? endTime;

  OrderQuery copyWith({
    int? pageNum,
    int? pageSize,
    Object? status = _sentinel,
    String? keyword,
    Object? startTime = _sentinel,
    Object? endTime = _sentinel,
  }) {
    return OrderQuery(
      pageNum: pageNum ?? this.pageNum,
      pageSize: pageSize ?? this.pageSize,
      status: identical(status, _sentinel) ? this.status : status as String?,
      keyword: keyword ?? this.keyword,
      startTime:
          identical(startTime, _sentinel) ? this.startTime : startTime as String?,
      endTime: identical(endTime, _sentinel) ? this.endTime : endTime as String?,
    );
  }

  Map<String, Object?> toRequestBody() {
    final offset = (pageNum - 1) * pageSize;
    final normalizedStatus = status?.trim() ?? '';
    return {
      'pageNum': pageNum,
      'pageSize': pageSize > 100 ? 100 : pageSize,
      'start': offset < 0 ? 0 : offset,
      // 后端 PageBean 用 query 作为 transac_status 过滤；status 语义独立，
      // 不应把搜索关键词混入 query（否则关键词会被当成状态过滤，查不到任何单）。
      'transac_status': normalizedStatus,
      'query': normalizedStatus,
      'keyword': keyword.trim(),
      if (startTime != null && startTime!.trim().isNotEmpty)
        'startTime': startTime!.trim(),
      if (endTime != null && endTime!.trim().isNotEmpty) 'endTime': endTime!.trim(),
    };
  }
}

const Object _sentinel = Object();
