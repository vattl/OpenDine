/// 票据预览场景枚举 (与后端 OpenAPI PrintScenario 规范 100% 对齐)
enum ReceiptTemplateScenario {
  kitchenTicket(
    code: 'KITCHEN',
    label: '后厨菜品制作分单',
    shortLabel: '后厨分单',
    description: '后厨制作口出菜分单，大字高亮桌号与制作备注',
  ),
  fullOrder(
    code: 'FULL_ORDER',
    label: '前台整单点单小票',
    shortLabel: '前台整单',
    description: '开台就餐全单汇总，包含全单品项、打包费与人数',
  ),
  preCheckout(
    code: 'PRE_CHECKOUT',
    label: '顾客消费预结单',
    shortLabel: '预结单',
    description: '结账前供顾客核对消费品项，带非结账凭证防伪提示',
  ),
  standardReceipt(
    code: 'CHECKOUT',
    label: '前台结账小票',
    shortLabel: '结账单',
    description: '顾客结算完成后的正式消费明细与支付凭单',
  ),
  expedite(
    code: 'EXPEDITE',
    label: '催菜/划单/传菜单',
    shortLabel: '传菜单',
    description: '出餐划单口、催单与传菜凭证，带划单方框',
  ),
  takeout(
    code: 'TAKEOUT',
    label: '外卖配送接单小票',
    shortLabel: '外卖小票',
    description: '美团/饿了么/自营外卖骑手取餐联与顾客配送联',
  ),
  packing(
    code: 'PACKING',
    label: '打包/自提核餐单',
    shortLabel: '打包单',
    description: '打包与到店自提订单的独立核餐凭条，突出取餐码、餐品和备注',
  ),
  shift(
    code: 'SHIFT',
    label: '收银交接班报表',
    shortLabel: '交接班单',
    description: '收银员当班结账汇总、备用金与各渠道收款报表',
  ),
  refund(
    code: 'REFUND',
    label: '订单退款单据凭条',
    shortLabel: '退款单',
    description: '订单退款凭证与财务核对审核单据',
  ),
  itemLabel(
    code: 'LABEL',
    label: '商品标签/杯贴',
    shortLabel: '标签杯贴',
    description: '商品外包装贴纸/奶茶杯贴/烧烤餐盒标',
  ),
  cutterTest(
    code: 'TEST',
    label: '自检与切刀测试小票',
    shortLabel: '测试小票',
    description: '用于检测打印机行距、走纸步进与切刀切纸动作',
  ),
  custom(
    code: 'ORDER',
    label: '通用点餐订单',
    shortLabel: '点餐单',
    description: '开单点菜凭据与通用点餐消费明细',
  );

  const ReceiptTemplateScenario({
    required this.code,
    required this.label,
    required this.shortLabel,
    required this.description,
  });

  final String code;
  final String label;
  final String shortLabel;
  final String description;

  static ReceiptTemplateScenario fromCode(String code) {
    final upper = code.toUpperCase();
    for (final s in values) {
      if (s.code.toUpperCase() == upper) return s;
    }
    return switch (upper) {
      'CHECKOUT' || 'STANDARD_RECEIPT' => standardReceipt,
      'KITCHEN' || 'KITCHEN_TICKET' => kitchenTicket,
      'FULL_ORDER' => fullOrder,
      'ORDER' => custom,
      'PRE_CHECKOUT' || 'PRECHECKOUT' => preCheckout,
      'EXPEDITE' || 'SERVE' || 'KDS_SERVE' => expedite,
      'TAKEOUT' || 'DELIVERY' => takeout,
      'PACKING' || 'PACKING_SLIP' || 'PICKUP' => packing,
      'SHIFT' => shift,
      'REFUND' => refund,
      'LABEL' => itemLabel,
      'CUTTER_TEST' || 'TEST' => cutterTest,
      'CUSTOM' => custom,
      _ => standardReceipt,
    };
  }
}

/// 打印小票 AST 节点类型 (由后端 /admin/printing/preview 接口返回)
enum PrintElementType {
  header,
  text,
  divider,
  tableHeader,
  tableRow,
  keyValue,
  qrcode,
  barcode,
  cut,
  logo,
  cashDrawer,
  audio,
  unknown;

  static PrintElementType fromString(String? type) {
    return switch (type?.toUpperCase()) {
      'HEADER' => header,
      'TEXT' => text,
      'DIVIDER' => divider,
      'TABLE_HEADER' => tableHeader,
      'TABLE_ROW' => tableRow,
      'KEY_VALUE' => keyValue,
      'QRCODE' => qrcode,
      'BARCODE' => barcode,
      'CUT' => cut,
      'LOGO' => logo,
      'CASH_DRAWER' => cashDrawer,
      'AUDIO' => audio,
      _ => unknown,
    };
  }
}

/// 打印对齐方式
enum PrintElementAlign {
  left,
  center,
  right;

  static PrintElementAlign fromString(String? align) {
    return switch (align?.toUpperCase()) {
      'CENTER' => center,
      'RIGHT' => right,
      _ => left,
    };
  }
}

/// 打印字号
enum PrintElementSize {
  normal,
  double,
  large;

  static PrintElementSize fromString(String? size) {
    return switch (size?.toUpperCase()) {
      'DOUBLE' => double,
      'LARGE' => large,
      _ => normal,
    };
  }
}

/// 打印小票 AST 元素 (与后端 PrintPreviewElement 契约对齐)
class PrintElement {
  const PrintElement({
    required this.type,
    this.text,
    this.align = PrintElementAlign.left,
    this.bold = false,
    this.size = PrintElementSize.normal,
    this.key,
    this.value,
    this.columns = const [],
    this.meta = const {},
  });

  final PrintElementType type;
  final String? text;
  final PrintElementAlign align;
  final bool bold;
  final PrintElementSize size;
  final String? key;
  final String? value;
  final List<String> columns;
  final Map<String, Object?> meta;

  factory PrintElement.fromJson(Map<String, Object?> json) {
    return PrintElement(
      type: PrintElementType.fromString(json['type'] as String?),
      text: json['text'] as String?,
      align: PrintElementAlign.fromString(json['align'] as String?),
      bold: json['bold'] == true,
      size: PrintElementSize.fromString(json['size'] as String?),
      key: json['key'] as String?,
      value: json['value'] as String?,
      columns:
          (json['columns'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          const [],
      meta: (json['meta'] as Map<String, Object?>?) ?? const {},
    );
  }
}

/// 单张小票对象 (与后端 TicketPreviewItem 契约对齐)
class PrintTicket {
  const PrintTicket({
    required this.ticketIndex,
    required this.title,
    required this.rawContent,
    required this.plainText,
    this.elements = const [],
    this.ruleId,
    this.deviceId,
    this.deviceName,
    this.templateId,
    this.templateCode,
  });

  final int ticketIndex;
  final String title;
  final String rawContent;
  final String plainText;
  final List<PrintElement> elements;

  /// 精确预览的实际调度来源；普通样例预览中可能为空。
  final int? ruleId;
  final int? deviceId;
  final String? deviceName;
  final int? templateId;
  final String? templateCode;

  factory PrintTicket.fromJson(Map<String, Object?> json) {
    return PrintTicket(
      ticketIndex: (json['ticketIndex'] as num?)?.toInt() ?? 0,
      title: json['title'] as String? ?? '小票',
      rawContent: json['rawContent'] as String? ?? '',
      plainText: json['plainText'] as String? ?? '',
      elements:
          (json['elements'] as List<dynamic>?)
              ?.whereType<Map<String, Object?>>()
              .map(PrintElement.fromJson)
              .toList() ??
          const [],
      ruleId: (json['ruleId'] as num?)?.toInt(),
      deviceId: (json['deviceId'] as num?)?.toInt(),
      deviceName: json['deviceName'] as String?,
      templateId: (json['templateId'] as num?)?.toInt(),
      templateCode: json['templateCode'] as String?,
    );
  }
}

/// 后端 POST/GET /admin/printing/preview 业务数据聚合对象
class PrintPreviewResult {
  const PrintPreviewResult({
    required this.scenario,
    required this.scenarioName,
    required this.paperSize,
    required this.paperWidthMm,
    required this.paperWidthChars,
    required this.shopName,
    required this.totalTickets,
    required this.tickets,
    this.rawCombinedContent = '',
    this.renderedAt,
    this.bindingWarnings = const [],
    this.capabilityWarnings = const [],
  });

  final String scenario;
  final String scenarioName;
  final String paperSize;
  final int paperWidthMm;
  final int paperWidthChars;
  final String shopName;
  final int totalTickets;
  final List<PrintTicket> tickets;
  final String rawCombinedContent;
  final String? renderedAt;

  /// 显式绑定在真实上下文中缺失时，后端隐藏该行并返回本字段。
  final List<String> bindingWarnings;

  /// 目标打印机能力不足、降级或忽略控制指令时的提示。
  final List<String> capabilityWarnings;

  bool get is80mm =>
      paperSize.toLowerCase().contains('80') ||
      paperWidthMm == 80 ||
      paperWidthChars >= 40;

  String get allPlainText => tickets.map((t) => t.plainText).join('\n\n');

  factory PrintPreviewResult.fromJson(Map<String, Object?> json) {
    return PrintPreviewResult(
      scenario: json['scenario'] as String? ?? 'ORDER',
      scenarioName: json['scenarioName'] as String? ?? '小票预览',
      paperSize: json['paperSize'] as String? ?? '58mm',
      paperWidthMm: (json['paperWidthMm'] as num?)?.toInt() ?? 58,
      paperWidthChars: (json['paperWidthChars'] as num?)?.toInt() ?? 32,
      shopName: json['shopName'] as String? ?? '',
      totalTickets:
          (json['totalTickets'] as num?)?.toInt() ??
          (json['tickets'] as List?)?.length ??
          1,
      tickets:
          (json['tickets'] as List<dynamic>?)
              ?.whereType<Map<String, Object?>>()
              .map(PrintTicket.fromJson)
              .toList() ??
          const [],
      rawCombinedContent: json['rawCombinedContent'] as String? ?? '',
      renderedAt: json['renderedAt'] as String?,
      bindingWarnings:
          (json['bindingWarnings'] as List?)
              ?.map((item) => item.toString())
              .toSet()
              .toList() ??
          const [],
      capabilityWarnings:
          (json['capabilityWarnings'] as List?)
              ?.map((item) => item.toString())
              .toSet()
              .toList() ??
          const [],
    );
  }
}
