import 'dart:convert';

class PrintingTemplateMeta {
  const PrintingTemplateMeta({
    this.scenarios = const [],
    this.parametersByScenario = const {},
  });

  final List<PrintingTemplateScenarioMeta> scenarios;
  final Map<String, List<PrintingTemplateParameterMeta>> parametersByScenario;

  factory PrintingTemplateMeta.fromJson(Map<String, Object?> json) {
    final scenarios = <PrintingTemplateScenarioMeta>[];
    final rawScenarios = json['scenarios'];
    if (rawScenarios is List) {
      for (final raw in rawScenarios.whereType<Map>()) {
        scenarios.add(
          PrintingTemplateScenarioMeta.fromJson(raw.cast<String, Object?>()),
        );
      }
    }

    final parameters = <String, List<PrintingTemplateParameterMeta>>{};
    final rawParameters = json['parametersByScenario'];
    if (rawParameters is Map) {
      for (final entry in rawParameters.entries) {
        final values = entry.value;
        if (values is! List) continue;
        parameters['${entry.key}'.toUpperCase()] = values
            .whereType<Map>()
            .map(
              (raw) => PrintingTemplateParameterMeta.fromJson(
                raw.cast<String, Object?>(),
              ),
            )
            .toList(growable: false);
      }
    }

    return PrintingTemplateMeta(
      scenarios: scenarios,
      parametersByScenario: parameters,
    );
  }

  List<PrintingTemplateParameterMeta> parametersFor(String scenario) =>
      parametersByScenario[scenario.toUpperCase()] ?? const [];
}

class PrintingTemplateScenarioMeta {
  const PrintingTemplateScenarioMeta({
    required this.code,
    required this.name,
    this.description = '',
    this.paperSizes = const [],
    this.allowedBlocks = const [],
  });

  final String code;
  final String name;
  final String description;
  final List<String> paperSizes;
  final List<String> allowedBlocks;

  String get ruleCode => code.toLowerCase();

  factory PrintingTemplateScenarioMeta.fromJson(Map<String, Object?> json) =>
      PrintingTemplateScenarioMeta(
        code: '${json['code'] ?? ''}'.toUpperCase(),
        name: '${json['name'] ?? json['label'] ?? json['code'] ?? ''}',
        description: '${json['description'] ?? ''}',
        paperSizes: _stringList(json['paperSizes'] ?? json['paper_sizes']),
        allowedBlocks: _stringList(
          json['allowedBlocks'] ?? json['allowed_blocks'],
        ),
      );
}

class PrintingTemplateParameterMeta {
  const PrintingTemplateParameterMeta({
    required this.name,
    required this.tag,
    this.description = '',
    this.type = '',
    this.example = '',
  });

  final String name;
  final String tag;
  final String description;
  final String type;
  final String example;

  factory PrintingTemplateParameterMeta.fromJson(Map<String, Object?> json) =>
      PrintingTemplateParameterMeta(
        name: '${json['name'] ?? ''}',
        tag: '${json['tag'] ?? ''}',
        description: '${json['description'] ?? ''}',
        type: '${json['type'] ?? ''}',
        example: '${json['example'] ?? ''}',
      );
}

List<String> _stringList(Object? value) => value is List
    ? value.map((item) => '$item').toList(growable: false)
    : const [];

/// 小票排版模板实体，对应后端 t_printing_template
class PrintingTemplate {
  const PrintingTemplate({
    required this.id,
    required this.shopId,
    required this.templateCode,
    required this.templateName,
    required this.scenario,
    this.paperSize = '58mm',
    this.isSystem = false,
    this.isDefault = false,
    this.templateJson,
    this.templateDsl,
    this.version = 1,
    this.createdAt,
    this.updatedAt,
  });

  final int id;
  final int shopId;
  final String templateCode;
  final String templateName;
  final String scenario;
  final String paperSize;
  final bool isSystem;
  final bool isDefault;
  final String? templateJson;
  final PrintTemplateDsl? templateDsl;
  final int version;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  factory PrintingTemplate.fromJson(Map<String, Object?> json) {
    final rawId = json['id'];
    final id = rawId is num
        ? rawId.toInt()
        : (int.tryParse(rawId?.toString() ?? '') ?? 0);
    final rawShopId = json['shopId'] ?? json['shop_id'];
    final shopId = rawShopId is num
        ? rawShopId.toInt()
        : (int.tryParse(rawShopId?.toString() ?? '') ?? 0);
    final templateCode =
        json['templateCode']?.toString() ??
        json['template_code']?.toString() ??
        '';
    final templateName =
        json['templateName']?.toString() ??
        json['template_name']?.toString() ??
        '未命名模板';
    final scenario = json['scenario']?.toString() ?? 'ORDER';
    final paperSize =
        json['paperSize']?.toString() ??
        json['paper_size']?.toString() ??
        '58mm';
    final isSystem =
        json['isSystem'] == true ||
        json['is_system'] == true ||
        json['isSystem'] == 1 ||
        json['is_system'] == 1 ||
        '${json['isSystem'] ?? json['is_system']}'.toLowerCase() == 'true';
    final isDefault =
        json['isDefault'] == true ||
        json['is_default'] == true ||
        json['isDefault'] == 1 ||
        json['is_default'] == 1 ||
        '${json['isDefault'] ?? json['is_default']}'.toLowerCase() == 'true';
    final templateJson =
        json['templateJson']?.toString() ?? json['template_json']?.toString();

    PrintTemplateDsl? templateDsl;
    if (json['templateDsl'] is Map) {
      templateDsl = PrintTemplateDsl.fromJson(
        (json['templateDsl'] as Map).cast<String, Object?>(),
      );
    } else if (templateJson != null && templateJson.trim().isNotEmpty) {
      try {
        final decoded = jsonDecode(templateJson);
        if (decoded is Map) {
          templateDsl = PrintTemplateDsl.fromJson(
            decoded.cast<String, Object?>(),
          );
        }
      } catch (_) {}
    }

    final rawVersion = json['version'];
    final version = rawVersion is num
        ? rawVersion.toInt()
        : (int.tryParse(rawVersion?.toString() ?? '') ?? 1);

    DateTime? parseDate(Object? v) {
      if (v == null) return null;
      if (v is DateTime) return v;
      final s = v.toString().trim();
      if (s.isEmpty) return null;
      return DateTime.tryParse(s) ?? DateTime.tryParse(s.replaceAll(' ', 'T'));
    }

    return PrintingTemplate(
      id: id,
      shopId: shopId,
      templateCode: templateCode,
      templateName: templateName,
      scenario: scenario,
      paperSize: paperSize,
      isSystem: isSystem,
      isDefault: isDefault,
      templateJson: templateJson,
      templateDsl: templateDsl,
      version: version,
      createdAt: parseDate(json['createdAt'] ?? json['created_at']),
      updatedAt: parseDate(json['updatedAt'] ?? json['updated_at']),
    );
  }

  Map<String, Object?> toJson() {
    return {
      'id': id,
      'shopId': shopId,
      'templateCode': templateCode,
      'templateName': templateName,
      'scenario': scenario,
      'paperSize': paperSize,
      'isSystem': isSystem,
      'isDefault': isDefault,
      if (templateJson != null) 'templateJson': templateJson,
      if (templateDsl != null) 'templateDsl': templateDsl!.toJson(),
      'version': version,
      if (createdAt != null) 'createdAt': createdAt!.toIso8601String(),
      if (updatedAt != null) 'updatedAt': updatedAt!.toIso8601String(),
    };
  }

  PrintingTemplate copyWith({
    int? id,
    int? shopId,
    String? templateCode,
    String? templateName,
    String? scenario,
    String? paperSize,
    bool? isSystem,
    bool? isDefault,
    String? templateJson,
    PrintTemplateDsl? templateDsl,
    int? version,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return PrintingTemplate(
      id: id ?? this.id,
      shopId: shopId ?? this.shopId,
      templateCode: templateCode ?? this.templateCode,
      templateName: templateName ?? this.templateName,
      scenario: scenario ?? this.scenario,
      paperSize: paperSize ?? this.paperSize,
      isSystem: isSystem ?? this.isSystem,
      isDefault: isDefault ?? this.isDefault,
      templateJson: templateJson ?? this.templateJson,
      templateDsl: templateDsl ?? this.templateDsl,
      version: version ?? this.version,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}

/// 打印模板 DSL 协议根模型
class PrintTemplateDsl {
  const PrintTemplateDsl({
    this.mode = 'BLOCK',
    this.rawTemplate,
    this.paperSize = '58mm',
    this.scenario = 'ORDER',
    this.autoCut = true,
    this.beeper = true,
    this.audio = 'NONE',
    this.feedLines = 2,
    this.blocks = const [],
  });

  /// 模板模式：BLOCK（可视化区块模式） / TEXT（纯文本模板模式）
  final String mode;

  /// 纯文本排版模板内容
  final String? rawTemplate;

  final String paperSize;
  final String scenario;
  final bool autoCut;
  final bool beeper;
  final String audio;
  final int feedLines;
  final List<TemplateBlock> blocks;

  factory PrintTemplateDsl.fromJson(Map<String, Object?> json) {
    final rawBlocks = json['blocks'];
    final blocks = <TemplateBlock>[];
    if (rawBlocks is List) {
      for (final b in rawBlocks) {
        if (b is Map) {
          blocks.add(TemplateBlock.fromJson(b.cast<String, Object?>()));
        }
      }
    }

    return PrintTemplateDsl(
      mode: json['mode']?.toString() ?? 'BLOCK',
      rawTemplate: json['rawTemplate']?.toString(),
      paperSize: json['paperSize']?.toString() ?? '58mm',
      scenario: json['scenario']?.toString() ?? 'ORDER',
      autoCut: json['autoCut'] != false,
      beeper: json['beeper'] != false,
      audio: json['audio']?.toString() ?? 'NONE',
      feedLines: (json['feedLines'] as num?)?.toInt() ?? 2,
      blocks: blocks,
    );
  }

  Map<String, Object?> toJson() {
    return {
      'mode': mode,
      if (rawTemplate != null) 'rawTemplate': rawTemplate,
      'paperSize': paperSize,
      'scenario': scenario,
      'autoCut': autoCut,
      'beeper': beeper,
      'audio': audio,
      'feedLines': feedLines,
      'blocks': blocks.map((b) => b.toJson()).toList(),
    };
  }

  PrintTemplateDsl copyWith({
    String? mode,
    String? rawTemplate,
    String? paperSize,
    String? scenario,
    bool? autoCut,
    bool? beeper,
    String? audio,
    int? feedLines,
    List<TemplateBlock>? blocks,
  }) {
    return PrintTemplateDsl(
      mode: mode ?? this.mode,
      rawTemplate: rawTemplate ?? this.rawTemplate,
      paperSize: paperSize ?? this.paperSize,
      scenario: scenario ?? this.scenario,
      autoCut: autoCut ?? this.autoCut,
      beeper: beeper ?? this.beeper,
      audio: audio ?? this.audio,
      feedLines: feedLines ?? this.feedLines,
      blocks: blocks ?? this.blocks,
    );
  }

  /// 获取纯文本模板的默认预设
  static String defaultTextTemplateForScenario(String scenario) {
    final upper = scenario.toUpperCase();
    if (upper == 'KITCHEN' || upper == 'EXPEDITE') {
      return '''           后厨制作单 {加菜}
             {桌号}号桌
--------------------------------
名称                    数量
--------------------------------
{菜品}                {数量}
--------------------------------
备注：{备注}
--------------------------------
下单时间：{下单时间}
''';
    }
    if (upper == 'SHIFT') {
      return '''           {门店名称}
         收银交接班报表
--------------------------------
班次ID：{shiftId}
收银员：{cashier}
开班时间：{startTime}
交班时间：{endTime}
--------------------------------
开班备用金：{startCash}元
完成总单数：{orderCount}单
实收总金额：{totalAmount}元
--------------------------------
【收款渠道汇总】
微信支付：{wechatAmount}元
支付宝支付：{alipayAmount}元
现金收取：{cashAmount}元
退款总额：{totalRefund}元
--------------------------------
打印时间：{printTime}
交班收银员签字：___________
''';
    }
    if (upper == 'REFUND') {
      return '''           {门店名称}
          订单退款凭条
--------------------------------
原订单号：{orderNo}
桌台号：{tableNo}
原单金额：{originalAmount}元
退款金额：{refundAmount}元
--------------------------------
退款原因：{refundReason}
退款渠道：{refundChannel}
操作人员：{operator}
退款时间：{refundTime}
--------------------------------
退款款项已原路退回，请注意查收
''';
    }
    if (upper == 'LABEL') {
      return '''{goodsName}
规格：{spec} {spicy}
数量：{quantity}   单价：{price}元
--------------------------------
桌号：{tableNo}
单号：{orderNo}
时间：{time}
''';
    }
    if (upper == 'TAKEOUT') {
      return '''          【{外卖平台}】
           外卖配送单
--------------------------------
单号：{订单号}
期望送达：{配送时间}
--------------------------------
收货人：{收件人}
电话：{收件人电话}
地址：{配送地址}
--------------------------------
名称               单价   数量   金额
--------------------------------
{菜品}    {单价}     {数量}  {金额}
--------------------------------
餐盒打包费：{打包费}元
配送服务费：{配送费}元
实付合计：{实付}元
支付方式：{支付方式}
--------------------------------
备注：{备注}
--------------------------------
下单时间：{下单时间}
''';
    }
    if (upper == 'PACKING') {
      return '''           打包单
          取餐码：{取餐码}
--------------------------------
订单号：{订单号}
用餐方式：{用餐方式}
下单时间：{下单时间}
--------------------------------
名称                    数量
--------------------------------
{菜品}                {数量}
--------------------------------
备注：{备注}
--------------------------------
请核对餐品与数量后封装
''';
    }
    if (upper == 'PRE_CHECKOUT') {
      return '''           {门店名称}
             {桌号}号桌
        消费预结单(非结账凭证)
名称               单价   数量   金额
--------------------------------
{菜品}    {单价}     {数量}  {金额}
--------------------------------
商品原价：{原价}元
优惠减免：-{优惠}元
应收总额：{实付}元
--------------------------------
桌台号：{桌号}
就餐人数：{人数}位
开单时间：{下单时间}
--------------------------------
* 本单仅供消费核对，请前往收银台结账 *
''';
    }
    if (upper == 'FULL_ORDER') {
      return '''           {门店名称}
             {桌号}号桌
          前台整单点菜单
名称               单价   数量   金额
--------------------------------
{菜品}    {单价}     {数量}  {金额}
--------------------------------
备注：{备注}
--------------------------------
商品总计：{原价}元
餐盒打包费：{打包费}元
优惠减免：-{优惠}元
实付应收：{实付}元
支付方式：{支付方式}
--------------------------------
下单门店：{门店名称}
桌台号：{桌号}
就餐人数：{人数}位
下单时间：{下单时间}
''';
    }
    if (upper == 'TEST') {
      return '''================================
         打印机自检测试单
================================
设备名称：{设备名称}
通信协议：{通信协议}
纸张规格：{纸张规格}
测试时间：{当前时间}
--------------------------------
1x 标准测试菜品A   ¥10.00
2x 标准测试菜品B   ¥28.00
--------------------------------
合计金额：¥38.00
--------------------------------
** 打印模块联调测试，非真实单据 **
''';
    }

    return '''           {门店名称}
             {桌号}号桌
            结账单
名称               单价   数量   金额
--------------------------------
{菜品}    {单价}     {数量}  {金额}
--------------------------------
备注：{备注}
--------------------------------
商品原价：{原价}元
打包费：{打包费}元
优惠减免：-{优惠}元
实付合计：{实付}元
支付方式：{支付方式}

下单门店：{门店名称}
桌台号：{桌号}
用餐方式：{用餐方式}
下单时间：{下单时间}
结账时间：{结账时间}

-----------感谢惠顾-----------

          {二维码}
        有任何问题可扫码反馈
''';
  }

  /// 为特定场景生成默认的区块 DSL
  static PrintTemplateDsl defaultForScenario(
    String scenario, {
    String paperSize = '58mm',
  }) {
    final upper = scenario.toUpperCase();
    if (upper == 'KITCHEN' || upper == 'EXPEDITE') {
      return PrintTemplateDsl(
        paperSize: paperSize,
        scenario: upper,
        autoCut: true,
        beeper: true,
        feedLines: 2,
        blocks: [
          const TemplateBlock(
            id: 'block_header',
            type: 'HEADER',
            name: '单据抬头',
            enabled: true,
            config: {
              'titleType': 'CUSTOM',
              'customTitle': '后厨制作单',
              'align': 'CENTER',
              'size': 'DOUBLE',
              'bold': true,
            },
          ),
          const TemplateBlock(
            id: 'block_order_info',
            type: 'ORDER_INFO',
            name: '订单基本信息',
            enabled: true,
            config: {
              'showTableNo': true,
              'tableNoSize': 'DOUBLE',
              'showDineInType': true,
              'showOrderNo': true,
              'showOrderTime': true,
            },
          ),
          const TemplateBlock(
            id: 'block_divider_1',
            type: 'DIVIDER',
            name: '分割线',
            enabled: true,
            config: {
              'char': '-',
              'length': 32,
              'text': '--------------------------------',
            },
          ),
          const TemplateBlock(
            id: 'block_items',
            type: 'DISH_ITEMS',
            name: '制作菜品列表',
            enabled: true,
            config: {
              'showTableHead': true,
              'showUnitPrice': false,
              'showQuantity': true,
              'showTotalPrice': false,
            },
          ),
          const TemplateBlock(
            id: 'block_divider_2',
            type: 'DIVIDER',
            name: '分割线',
            enabled: true,
            config: {
              'char': '-',
              'length': 32,
              'text': '--------------------------------',
            },
          ),
          const TemplateBlock(
            id: 'block_remark',
            type: 'REMARK',
            name: '整单备注',
            enabled: true,
            config: {'bold': true, 'size': 'LARGE'},
          ),
          const TemplateBlock(
            id: 'block_footer',
            type: 'FOOTER',
            name: '页脚标语',
            enabled: true,
            config: {'thankText': '制作出餐', 'showQrCode': false},
          ),
        ],
      );
    }

    if (upper == 'SHIFT') {
      return PrintTemplateDsl(
        paperSize: paperSize,
        scenario: upper,
        autoCut: true,
        beeper: true,
        feedLines: 2,
        blocks: [
          const TemplateBlock(
            id: 'block_header',
            type: 'HEADER',
            name: '报表抬头',
            enabled: true,
            config: {
              'titleType': 'SHOP_NAME',
              'subTitle': '收银交接班报表',
              'align': 'CENTER',
              'size': 'DOUBLE',
              'bold': true,
            },
          ),
          const TemplateBlock(
            id: 'block_divider_1',
            type: 'DIVIDER',
            name: '分割线',
            enabled: true,
            config: {
              'char': '-',
              'length': 32,
              'text': '--------------------------------',
            },
          ),
          const TemplateBlock(
            id: 'block_shift_info',
            type: 'CUSTOM_TEXT',
            name: '交班基础信息',
            enabled: true,
            config: {
              'content':
                  '班次流水：{shiftId}\n收银员：{cashier}\n开班时间：{startTime}\n交班时间：{endTime}',
              'align': 'LEFT',
              'size': 'NORMAL',
              'bold': false,
            },
          ),
          const TemplateBlock(
            id: 'block_divider_2',
            type: 'DIVIDER',
            name: '分割线',
            enabled: true,
            config: {
              'char': '-',
              'length': 32,
              'text': '--------------------------------',
            },
          ),
          const TemplateBlock(
            id: 'block_shift_stats',
            type: 'CUSTOM_TEXT',
            name: '营业与收款汇总',
            enabled: true,
            config: {
              'content':
                  '开班备用金：{startCash}元\n完成总单数：{orderCount}单\n实收营业额：{totalAmount}元\n\n【渠道收款明细】\n微信收款：{wechatAmount}元\n支付宝收款：{alipayAmount}元\n现金收款：{cashAmount}元\n退款总额：{totalRefund}元',
              'align': 'LEFT',
              'size': 'NORMAL',
              'bold': false,
            },
          ),
          const TemplateBlock(
            id: 'block_divider_3',
            type: 'DIVIDER',
            name: '分割线',
            enabled: true,
            config: {
              'char': '-',
              'length': 32,
              'text': '--------------------------------',
            },
          ),
          const TemplateBlock(
            id: 'block_footer',
            type: 'FOOTER',
            name: '签名与时间',
            enabled: true,
            config: {
              'thankText': '打印时间：{printTime}\n交班人签字：___________',
              'showQrCode': false,
            },
          ),
        ],
      );
    }

    if (upper == 'REFUND') {
      return PrintTemplateDsl(
        paperSize: paperSize,
        scenario: upper,
        autoCut: true,
        beeper: true,
        feedLines: 2,
        blocks: [
          const TemplateBlock(
            id: 'block_header',
            type: 'HEADER',
            name: '单据抬头',
            enabled: true,
            config: {
              'titleType': 'SHOP_NAME',
              'subTitle': '订单退款单据凭条',
              'align': 'CENTER',
              'size': 'DOUBLE',
              'bold': true,
            },
          ),
          const TemplateBlock(
            id: 'block_divider_1',
            type: 'DIVIDER',
            name: '分割线',
            enabled: true,
            config: {
              'char': '-',
              'length': 32,
              'text': '--------------------------------',
            },
          ),
          const TemplateBlock(
            id: 'block_refund_info',
            type: 'CUSTOM_TEXT',
            name: '退款明细',
            enabled: true,
            config: {
              'content':
                  '原订单号：{orderNo}\n桌台号：{tableNo}\n原单金额：{originalAmount}元\n退款金额：{refundAmount}元\n退款原因：{refundReason}\n退款渠道：{refundChannel}\n操作人员：{operator}\n退款时间：{refundTime}',
              'align': 'LEFT',
              'size': 'NORMAL',
              'bold': false,
            },
          ),
          const TemplateBlock(
            id: 'block_divider_2',
            type: 'DIVIDER',
            name: '分割线',
            enabled: true,
            config: {
              'char': '-',
              'length': 32,
              'text': '--------------------------------',
            },
          ),
          const TemplateBlock(
            id: 'block_footer',
            type: 'FOOTER',
            name: '提示',
            enabled: true,
            config: {'thankText': '退款款项已原路退回，请注意查收', 'showQrCode': false},
          ),
        ],
      );
    }

    if (upper == 'LABEL') {
      return PrintTemplateDsl(
        paperSize: paperSize,
        scenario: upper,
        autoCut: true,
        beeper: false,
        feedLines: 1,
        blocks: [
          const TemplateBlock(
            id: 'block_label_main',
            type: 'CUSTOM_TEXT',
            name: '标签商品信息',
            enabled: true,
            config: {
              'content':
                  '{goodsName}\n规格：{spec} {spicy}\n数量：{quantity}   单价：{price}元\n桌号：{tableNo}\n单号：{orderNo}\n时间：{time}',
              'align': 'LEFT',
              'size': 'NORMAL',
              'bold': true,
            },
          ),
        ],
      );
    }

    if (upper == 'TAKEOUT') {
      return PrintTemplateDsl(
        paperSize: paperSize,
        scenario: upper,
        autoCut: true,
        beeper: true,
        feedLines: 2,
        blocks: [
          const TemplateBlock(
            id: 'block_header',
            type: 'HEADER',
            name: '外卖抬头',
            enabled: true,
            config: {
              'titleType': 'CUSTOM',
              'customTitle': '【外卖配送单】',
              'align': 'CENTER',
              'size': 'DOUBLE',
              'bold': true,
            },
          ),
          const TemplateBlock(
            id: 'block_delivery_info',
            type: 'DELIVERY_INFO',
            name: '配送与顾客信息',
            enabled: true,
            config: {
              'showReceiverName': true,
              'showReceiverPhone': true,
              'showDeliveryAddress': true,
              'showExpectedTime': true,
            },
          ),
          const TemplateBlock(
            id: 'block_divider_1',
            type: 'DIVIDER',
            name: '分割线',
            enabled: true,
            config: {
              'char': '-',
              'length': 32,
              'text': '--------------------------------',
            },
          ),
          const TemplateBlock(
            id: 'block_items',
            type: 'DISH_ITEMS',
            name: '外卖菜品明细',
            enabled: true,
            config: {
              'showTableHead': true,
              'showUnitPrice': true,
              'showQuantity': true,
              'showTotalPrice': true,
            },
          ),
          const TemplateBlock(
            id: 'block_divider_2',
            type: 'DIVIDER',
            name: '分割线',
            enabled: true,
            config: {
              'char': '-',
              'length': 32,
              'text': '--------------------------------',
            },
          ),
          const TemplateBlock(
            id: 'block_payment',
            type: 'PAYMENT_SUMMARY',
            name: '结算汇总',
            enabled: true,
            config: {
              'showOriginalAmount': true,
              'showDiscountAmount': true,
              'showActualAmount': true,
              'actualAmountSize': 'DOUBLE',
              'actualAmountBold': true,
              'showPayChannel': true,
            },
          ),
          const TemplateBlock(
            id: 'block_remark',
            type: 'REMARK',
            name: '顾客备注',
            enabled: true,
            config: {'bold': true, 'size': 'LARGE'},
          ),
          const TemplateBlock(
            id: 'block_divider_3',
            type: 'DIVIDER',
            name: '分割线',
            enabled: true,
            config: {
              'char': '-',
              'length': 32,
              'text': '--------------------------------',
            },
          ),
          const TemplateBlock(
            id: 'block_footer',
            type: 'FOOTER',
            name: '页脚',
            enabled: true,
            config: {'thankText': '祝您就餐愉快', 'showQrCode': false},
          ),
        ],
      );
    }

    if (upper == 'PACKING') {
      return PrintTemplateDsl(
        paperSize: paperSize,
        scenario: upper,
        autoCut: true,
        beeper: true,
        feedLines: 2,
        blocks: [
          const TemplateBlock(
            id: 'block_header',
            type: 'HEADER',
            name: '打包单抬头',
            enabled: true,
            config: {
              'titleType': 'CUSTOM',
              'customTitle': '打包单',
              'align': 'CENTER',
              'size': 'DOUBLE',
              'bold': true,
            },
          ),
          const TemplateBlock(
            id: 'block_pickup_code',
            type: 'CUSTOM_TEXT',
            name: '取餐码',
            enabled: true,
            config: {
              'content': '取餐码：{取餐码}',
              'align': 'CENTER',
              'size': 'DOUBLE',
              'bold': true,
            },
          ),
          const TemplateBlock(
            id: 'block_order_info',
            type: 'ORDER_INFO',
            name: '订单信息',
            enabled: true,
            config: {
              'showDineInType': true,
              'showOrderNo': true,
              'showOrderTime': true,
            },
          ),
          const TemplateBlock(
            id: 'block_items',
            type: 'DISH_ITEMS',
            name: '打包餐品明细',
            enabled: true,
            config: {
              'showTableHead': false,
              'showUnitPrice': false,
              'showQuantity': true,
              'showTotalPrice': false,
            },
          ),
          const TemplateBlock(
            id: 'block_remark',
            type: 'REMARK',
            name: '打包备注',
            enabled: true,
            config: {'bold': true, 'size': 'DOUBLE'},
          ),
          const TemplateBlock(
            id: 'block_footer',
            type: 'FOOTER',
            name: '核餐提示',
            enabled: true,
            config: {'thankText': '请核对餐品与数量后封装', 'showQrCode': false},
          ),
        ],
      );
    }

    // 默认 ORDER / FULL_ORDER / CHECKOUT / PRE_CHECKOUT
    return PrintTemplateDsl(
      paperSize: paperSize,
      scenario: upper,
      autoCut: true,
      beeper: true,
      feedLines: 2,
      blocks: [
        const TemplateBlock(
          id: 'block_header',
          type: 'HEADER',
          name: '门店抬头',
          enabled: true,
          config: {
            'titleType': 'SHOP_NAME',
            'align': 'CENTER',
            'size': 'DOUBLE',
            'bold': true,
          },
        ),
        const TemplateBlock(
          id: 'block_order_info',
          type: 'ORDER_INFO',
          name: '桌台与订单信息',
          enabled: true,
          config: {
            'showTableNo': true,
            'tableNoSize': 'DOUBLE',
            'showDineInType': true,
            'showOrderNo': true,
            'showOrderTime': true,
          },
        ),
        const TemplateBlock(
          id: 'block_divider_1',
          type: 'DIVIDER',
          name: '分割线',
          enabled: true,
          config: {
            'char': '-',
            'length': 32,
            'text': '--------------------------------',
          },
        ),
        const TemplateBlock(
          id: 'block_items',
          type: 'DISH_ITEMS',
          name: '菜品明细',
          enabled: true,
          config: {
            'showTableHead': true,
            'showUnitPrice': true,
            'showQuantity': true,
            'showTotalPrice': true,
          },
        ),
        const TemplateBlock(
          id: 'block_divider_2',
          type: 'DIVIDER',
          name: '分割线',
          enabled: true,
          config: {
            'char': '-',
            'length': 32,
            'text': '--------------------------------',
          },
        ),
        const TemplateBlock(
          id: 'block_payment',
          type: 'PAYMENT_SUMMARY',
          name: '结算与支付汇总',
          enabled: true,
          config: {
            'showOriginalAmount': true,
            'showDiscountAmount': true,
            'showActualAmount': true,
            'actualAmountSize': 'DOUBLE',
            'actualAmountBold': true,
            'showPayChannel': true,
          },
        ),
        const TemplateBlock(
          id: 'block_member',
          type: 'MEMBER_INFO',
          name: '会员信息',
          enabled: true,
          config: {'enabled': true},
        ),
        const TemplateBlock(
          id: 'block_remark',
          type: 'REMARK',
          name: '顾客备注',
          enabled: true,
          config: {'bold': true, 'size': 'NORMAL'},
        ),
        const TemplateBlock(
          id: 'block_divider_3',
          type: 'DIVIDER',
          name: '分割线',
          enabled: true,
          config: {
            'char': '-',
            'length': 32,
            'text': '--------------------------------',
          },
        ),
        const TemplateBlock(
          id: 'block_footer',
          type: 'FOOTER',
          name: '页脚与二维码',
          enabled: true,
          config: {
            'thankText': '感谢惠顾 欢迎再次光临',
            'showQrCode': true,
            'qrCodeUrl': 'https://u.wechat.com/EF9MZwaAbHhL79QCtBgAVAA?s=2',
            'qrCodeNote': '有任何问题可扫码反馈',
          },
        ),
      ],
    );
  }
}

/// 模板中的单个区块组件定义
class TemplateBlock {
  const TemplateBlock({
    required this.id,
    required this.type,
    required this.name,
    this.enabled = true,
    this.config = const {},
  });

  final String id;
  final String type;
  final String name;
  final bool enabled;
  final Map<String, Object?> config;

  factory TemplateBlock.fromJson(Map<String, Object?> json) {
    return TemplateBlock(
      id:
          json['id']?.toString() ??
          'block_${DateTime.now().millisecondsSinceEpoch}',
      type: json['type']?.toString() ?? 'CUSTOM_TEXT',
      name: json['name']?.toString() ?? '自定义区块',
      enabled: json['enabled'] != false,
      config: json['config'] is Map
          ? (json['config'] as Map).cast<String, Object?>()
          : const {},
    );
  }

  Map<String, Object?> toJson() {
    return {
      'id': id,
      'type': type,
      'name': name,
      'enabled': enabled,
      'config': config,
    };
  }

  TemplateBlock copyWith({
    String? id,
    String? type,
    String? name,
    bool? enabled,
    Map<String, Object?>? config,
  }) {
    return TemplateBlock(
      id: id ?? this.id,
      type: type ?? this.type,
      name: name ?? this.name,
      enabled: enabled ?? this.enabled,
      config: config ?? this.config,
    );
  }
}
