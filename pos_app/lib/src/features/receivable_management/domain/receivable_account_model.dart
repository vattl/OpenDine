import 'package:flutter/foundation.dart';

@immutable
class ReceivableAccountModel {
  const ReceivableAccountModel({
    required this.id,
    required this.accountNo,
    required this.scopeType,
    this.shopId,
    required this.customerType,
    required this.customerName,
    this.contactName,
    this.contactPhone,
    this.taxNo,
    required this.creditLimitFen,
    required this.outstandingFen,
    required this.paymentTermsDays,
    required this.status,
    this.notes,
    this.createdAt,
    this.updatedAt,
    this.closedAt,
  });

  final int id;
  final String accountNo;
  final String scopeType; // 'SHOP' | 'MERCHANT'
  final int? shopId;
  final String customerType; // 'COMPANY' | 'PERSONAL'
  final String customerName;
  final String? contactName;
  final String? contactPhone;
  final String? taxNo;
  final int creditLimitFen;
  final int outstandingFen;
  final int paymentTermsDays;
  final String status; // 'ACTIVE' | 'SUSPENDED' | 'CLOSED'
  final String? notes;
  final String? createdAt;
  final String? updatedAt;
  final String? closedAt;

  double get creditLimitYuan => creditLimitFen / 100.0;
  double get outstandingYuan => outstandingFen / 100.0;
  int get availableFen => (creditLimitFen - outstandingFen).clamp(0, creditLimitFen);
  double get availableYuan => availableFen / 100.0;
  double get usedRatio =>
      creditLimitFen > 0 ? (outstandingFen / creditLimitFen).clamp(0.0, 1.0) : 0.0;

  bool get isActive => status == 'ACTIVE';
  bool get isSuspended => status == 'SUSPENDED';
  bool get isClosed => status == 'CLOSED';
  bool get isCompany => customerType == 'COMPANY';
  bool get isMerchantScope => scopeType == 'MERCHANT';

  factory ReceivableAccountModel.fromJson(Map<String, dynamic> json) {
    return ReceivableAccountModel(
      id: (json['id'] as num?)?.toInt() ?? 0,
      accountNo: json['accountNo']?.toString() ?? json['account_no']?.toString() ?? '',
      scopeType: json['scopeType']?.toString() ?? json['scope_type']?.toString() ?? 'SHOP',
      shopId: (json['shopId'] as num?)?.toInt() ?? (json['shop_id'] as num?)?.toInt(),
      customerType: json['customerType']?.toString() ?? json['customer_type']?.toString() ?? 'COMPANY',
      customerName: json['customerName']?.toString() ?? json['customer_name']?.toString() ?? '',
      contactName: json['contactName']?.toString() ?? json['contact_name']?.toString(),
      contactPhone: json['contactPhone']?.toString() ?? json['contact_phone']?.toString(),
      taxNo: json['taxNo']?.toString() ?? json['tax_no']?.toString(),
      creditLimitFen: (json['creditLimitFen'] as num?)?.toInt() ?? (json['credit_limit_fen'] as num?)?.toInt() ?? 0,
      outstandingFen: (json['outstandingFen'] as num?)?.toInt() ?? (json['outstanding_fen'] as num?)?.toInt() ?? 0,
      paymentTermsDays: (json['paymentTermsDays'] as num?)?.toInt() ?? (json['payment_terms_days'] as num?)?.toInt() ?? 30,
      status: json['status']?.toString() ?? 'ACTIVE',
      notes: json['notes']?.toString(),
      createdAt: json['createdAt']?.toString() ?? json['created_at']?.toString(),
      updatedAt: json['updatedAt']?.toString() ?? json['updated_at']?.toString(),
      closedAt: json['closedAt']?.toString() ?? json['closed_at']?.toString(),
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'accountNo': accountNo,
    'scopeType': scopeType,
    'shopId': shopId,
    'customerType': customerType,
    'customerName': customerName,
    'contactName': contactName,
    'contactPhone': contactPhone,
    'taxNo': taxNo,
    'creditLimitFen': creditLimitFen,
    'outstandingFen': outstandingFen,
    'paymentTermsDays': paymentTermsDays,
    'status': status,
    'notes': notes,
  };
}

class ReceivableAccountFormData {
  const ReceivableAccountFormData({
    required this.customerName,
    this.customerType = 'COMPANY',
    this.scopeType = 'SHOP',
    this.contactName = '',
    this.contactPhone = '',
    this.taxNo = '',
    required this.creditLimitFen,
    this.paymentTermsDays = 30,
    this.notes = '',
  });

  final String customerName;
  final String customerType;
  final String scopeType;
  final String contactName;
  final String contactPhone;
  final String taxNo;
  final int creditLimitFen;
  final int paymentTermsDays;
  final String notes;

  Map<String, dynamic> toJson() => {
    'customerName': customerName.trim(),
    'customerType': customerType,
    'scopeType': scopeType,
    'contactName': contactName.trim(),
    'contactPhone': contactPhone.trim(),
    'taxNo': taxNo.trim(),
    'creditLimitFen': creditLimitFen,
    'paymentTermsDays': paymentTermsDays,
    'notes': notes.trim(),
  };
}

@immutable
class ReceivableStatementItem {
  const ReceivableStatementItem({
    required this.id,
    required this.entryType,
    required this.amountFen,
    this.channel,
    this.orderNo,
    this.operatorId,
    this.note,
    this.createdAt,
  });

  final int id;
  final String entryType; // 'CHARGE' | 'COLLECTION' | 'REVERSAL' | 'WRITEOFF'
  final int amountFen;
  final String? channel;
  final String? orderNo;
  final int? operatorId;
  final String? note;
  final String? createdAt;

  double get amountYuan => amountFen.abs() / 100.0;
  bool get isCharge => entryType == 'CHARGE';
  bool get isCollection => entryType == 'COLLECTION';
  bool get isReversal => entryType == 'REVERSAL';
  bool get isWriteoff => entryType == 'WRITEOFF';

  String get entryTypeLabel => switch (entryType) {
    'CHARGE' => '挂账增加',
    'COLLECTION' => '回款冲减',
    'REVERSAL' => '应收撤销',
    'WRITEOFF' => '坏账核销',
    _ => entryType,
  };

  factory ReceivableStatementItem.fromJson(Map<String, dynamic> json) {
    return ReceivableStatementItem(
      id: (json['id'] as num?)?.toInt() ?? 0,
      entryType: json['entryType']?.toString() ?? json['entry_type']?.toString() ?? 'CHARGE',
      amountFen: (json['amountFen'] as num?)?.toInt() ?? (json['amount_fen'] as num?)?.toInt() ?? 0,
      channel: json['channel']?.toString(),
      orderNo: json['orderNo']?.toString() ?? json['order_no']?.toString(),
      operatorId: (json['operatorId'] as num?)?.toInt() ?? (json['operator_id'] as num?)?.toInt(),
      note: json['note']?.toString(),
      createdAt: json['createdAt']?.toString() ?? json['created_at']?.toString(),
    );
  }
}

@immutable
class ReceivableAgingSummary {
  const ReceivableAgingSummary({
    this.currentFen = 0,
    this.days1To30Fen = 0,
    this.days31To60Fen = 0,
    this.days61To90Fen = 0,
    this.days90PlusFen = 0,
    this.totalOutstandingFen = 0,
  });

  final int currentFen;
  final int days1To30Fen;
  final int days31To60Fen;
  final int days61To90Fen;
  final int days90PlusFen;
  final int totalOutstandingFen;

  int get overdueFen =>
      days1To30Fen + days31To60Fen + days61To90Fen + days90PlusFen;
  double get overdueYuan => overdueFen / 100.0;
  double get totalOutstandingYuan => totalOutstandingFen / 100.0;
  double get currentYuan => currentFen / 100.0;
  double get days1To30Yuan => days1To30Fen / 100.0;
  double get days31To60Yuan => days31To60Fen / 100.0;
  double get days61To90Yuan => days61To90Fen / 100.0;
  double get days90PlusYuan => days90PlusFen / 100.0;

  factory ReceivableAgingSummary.fromJson(Map<String, dynamic> json) {
    return ReceivableAgingSummary(
      currentFen: (json['current_fen'] as num?)?.toInt() ?? (json['currentFen'] as num?)?.toInt() ?? 0,
      days1To30Fen: (json['days_1_30_fen'] as num?)?.toInt() ?? (json['days1To30Fen'] as num?)?.toInt() ?? 0,
      days31To60Fen: (json['days_31_60_fen'] as num?)?.toInt() ?? (json['days31To60Fen'] as num?)?.toInt() ?? 0,
      days61To90Fen: (json['days_61_90_fen'] as num?)?.toInt() ?? (json['days61To90Fen'] as num?)?.toInt() ?? 0,
      days90PlusFen: (json['days_90_plus_fen'] as num?)?.toInt() ?? (json['days90PlusFen'] as num?)?.toInt() ?? 0,
      totalOutstandingFen: (json['total_outstanding_fen'] as num?)?.toInt() ?? (json['totalOutstandingFen'] as num?)?.toInt() ?? 0,
    );
  }
}

@immutable
class ReceivableClaimModel {
  const ReceivableClaimModel({
    required this.id,
    required this.claimNo,
    required this.orderNo,
    required this.accountId,
    this.customerName,
    required this.originalAmountFen,
    required this.outstandingFen,
    required this.status,
    this.dueDate,
    this.overdueDays = 0,
    this.settledAt,
    this.note,
    this.createdAt,
    this.updatedAt,
  });

  final int id;
  final String claimNo;
  final String orderNo;
  final int accountId;
  final String? customerName;
  final int originalAmountFen;
  final int outstandingFen;
  final String status;
  final String? dueDate;
  final int overdueDays;
  final String? settledAt;
  final String? note;
  final String? createdAt;
  final String? updatedAt;

  double get originalAmountYuan => originalAmountFen / 100.0;
  double get outstandingYuan => outstandingFen / 100.0;
  double get collectedYuan => (originalAmountFen - outstandingFen).clamp(0, originalAmountFen) / 100.0;

  int get amountFen => originalAmountFen;
  double get amountYuan => originalAmountYuan;
  int get uncollectedFen => outstandingFen;
  double get uncollectedYuan => outstandingYuan;
  String? get notes => note;

  bool get isOpen => status == 'OPEN';
  bool get isPartial => status == 'PARTIAL';
  bool get isSettled => status == 'SETTLED';
  bool get isOverdue => status == 'OVERDUE' || overdueDays > 0;
  bool get isWrittenOff => status == 'WRITTEN_OFF';
  bool get isReversed => status == 'REVERSED';

  bool get isCollectable => (isOpen || isPartial || isOverdue) && outstandingFen > 0;
  bool get canReverse => isOpen && outstandingFen == originalAmountFen;
  bool get canWriteOff => isCollectable;

  String get statusLabel => switch (status) {
    'OPEN' => '未结清',
    'PARTIAL' => '部分回款',
    'SETTLED' => '已结清',
    'OVERDUE' => '已逾期',
    'WRITTEN_OFF' => '已核销坏账',
    'REVERSED' => '已撤销冲正',
    _ => status,
  };

  factory ReceivableClaimModel.fromJson(Map<String, dynamic> json) {
    return ReceivableClaimModel(
      id: (json['id'] as num?)?.toInt() ?? 0,
      claimNo: json['claimNo']?.toString() ?? json['claim_no']?.toString() ?? '',
      orderNo: json['orderNo']?.toString() ?? json['order_no']?.toString() ?? '',
      accountId: (json['accountId'] as num?)?.toInt() ?? (json['account_id'] as num?)?.toInt() ?? 0,
      customerName: json['customerName']?.toString() ?? json['customer_name']?.toString(),
      originalAmountFen: (json['originalAmountFen'] as num?)?.toInt() ?? (json['original_amount_fen'] as num?)?.toInt() ?? 0,
      outstandingFen: (json['outstandingFen'] as num?)?.toInt() ?? (json['outstanding_fen'] as num?)?.toInt() ?? 0,
      status: json['status']?.toString() ?? 'OPEN',
      dueDate: json['dueDate']?.toString() ?? json['due_date']?.toString(),
      overdueDays: (json['overdueDays'] as num?)?.toInt() ?? (json['overdue_days'] as num?)?.toInt() ?? 0,
      settledAt: json['settledAt']?.toString() ?? json['settled_at']?.toString(),
      note: json['note']?.toString(),
      createdAt: json['createdAt']?.toString() ?? json['created_at']?.toString(),
      updatedAt: json['updatedAt']?.toString() ?? json['updated_at']?.toString(),
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'claimNo': claimNo,
    'orderNo': orderNo,
    'accountId': accountId,
    'customerName': customerName,
    'originalAmountFen': originalAmountFen,
    'outstandingFen': outstandingFen,
    'status': status,
    'dueDate': dueDate,
    'overdueDays': overdueDays,
    'settledAt': settledAt,
    'note': note,
    'createdAt': createdAt,
    'updatedAt': updatedAt,
  };
}
