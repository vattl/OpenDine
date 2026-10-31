class OrderQuery {
  const OrderQuery({
    this.pageNum = 1,
    this.pageSize = 20,
    this.status,
    this.keyword = '',
  });

  final int pageNum;
  final int pageSize;
  final String? status;
  final String keyword;

  OrderQuery copyWith({
    int? pageNum,
    int? pageSize,
    Object? status = _sentinel,
    String? keyword,
  }) {
    return OrderQuery(
      pageNum: pageNum ?? this.pageNum,
      pageSize: pageSize ?? this.pageSize,
      status: identical(status, _sentinel) ? this.status : status as String?,
      keyword: keyword ?? this.keyword,
    );
  }

  Map<String, Object?> toRequestBody() {
    final offset = (pageNum - 1) * pageSize;
    final normalizedStatus = status?.trim() ?? '';
    return {
      'pageNum': pageNum,
      'pageSize': pageSize > 100 ? 100 : pageSize,
      'start': offset < 0 ? 0 : offset,
      'transac_status': normalizedStatus,
      'query': normalizedStatus.isEmpty ? keyword.trim() : normalizedStatus,
      'keyword': keyword.trim(),
    };
  }
}

const Object _sentinel = Object();
