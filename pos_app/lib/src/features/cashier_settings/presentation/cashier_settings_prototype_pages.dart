import 'package:flutter/material.dart';

import '../data/cashier_settings_repository.dart';
import '../domain/cashier_settings.dart';
import 'cashier_settings_shared.dart';
import '../../cashier_shell/presentation/cashier_tokens.dart';

/// Repository-backed read-only section. It never displays example rows or
/// promises write operations that the endpoint does not provide.
class SettingsReadOnlySection extends SettingsPrototypePage {
  const SettingsReadOnlySection({
    super.key,
    required super.repository,
    required super.destination,
    required super.section,
  }) : super(readOnly: true);
}

class SettingsPrototypePage extends StatefulWidget {
  const SettingsPrototypePage({
    super.key,
    required this.repository,
    required this.destination,
    required this.section,
    this.readOnly = false,
  });

  final CashierSettingsRepository repository;
  final SettingsDestination destination;
  final SettingsSectionSpec section;
  final bool readOnly;

  @override
  State<SettingsPrototypePage> createState() => _SettingsPrototypePageState();
}

class _SettingsPrototypePageState extends State<SettingsPrototypePage> {
  late Future<CashierSettingsSectionData> _sectionData;
  var _page = 1;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant SettingsPrototypePage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.destination != widget.destination ||
        oldWidget.section.id != widget.section.id ||
        oldWidget.repository != widget.repository) {
      _page = 1;
      _load();
    }
  }

  void _load() {
    _sectionData = widget.repository.loadSettingsSection(
      module: widget.destination.name,
      section: widget.section.id,
      page: _page,
    );
  }

  void _reload() => setState(_load);

  void _goToPage(int page) => setState(() {
    _page = page;
    _load();
  });

  @override
  Widget build(BuildContext context) {
    final content = _contentFor(widget.destination, widget.section.id);
    return ListView(
      key: PageStorageKey('${widget.destination.name}-${widget.section.id}'),
      padding: const EdgeInsets.all(20),
      children: [
        FutureBuilder<CashierSettingsSectionData>(
          future: _sectionData,
          builder: (context, snapshot) => _PrototypeHeader(
            content: content,
            source: _sourceLabel(snapshot.data?.source),
            loading: snapshot.connectionState == ConnectionState.waiting,
            onRefresh: _reload,
          ),
        ),
        const SizedBox(height: 16),
        if (!widget.readOnly && content.facts.isNotEmpty)
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [for (final fact in content.facts) _FactCard(fact: fact)],
          ),
        if (!widget.readOnly && content.facts.isNotEmpty) const SizedBox(height: 16),
        FutureBuilder<CashierSettingsSectionData>(
          future: _sectionData,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const _ProductionLoading();
            }
            if (snapshot.hasError) {
              return _ProductionError(error: snapshot.error, onRetry: _reload);
            }
            final data = snapshot.data!;
            return _ProductionTable(
              data: data,
              onPrevious: data.page > 1 ? () => _goToPage(data.page - 1) : null,
              onNext: data.page * data.pageSize < data.total
                  ? () => _goToPage(data.page + 1)
                  : null,
            );
          },
        ),
        const SizedBox(height: 16),
        if (!widget.readOnly) _StatePanel(states: content.states),
      ],
    );
  }
}

class SettingsPolicyBanner extends StatelessWidget {
  const SettingsPolicyBanner({super.key, required this.destination});

  final SettingsDestination destination;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final content = _contentFor(destination, destination.sections.first.id);
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
      decoration: BoxDecoration(
        color: isDark ? context.cashier.subtle : const Color(0xfff8fafc),
        border: Border.all(color: isDark ? context.cashier.border : const Color(0xffdfe4ea),
        ),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          const Icon(Icons.info_outline, color: Color(0xff2563eb)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  content.description,
                  style: const TextStyle(fontSize: 15, height: 1.35),
                ),
                if (content.facts.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(
                    content.facts.join(' · '),
                    style: TextStyle(
                      color: context.cashier.inkMuted,
                      fontSize: 13,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 12),
          const _SourceBadge(label: '当前门店'),
        ],
      ),
    );
  }
}

class _PrototypeHeader extends StatelessWidget {
  const _PrototypeHeader({
    required this.content,
    required this.source,
    required this.loading,
    required this.onRefresh,
  });

  final _PrototypeContent content;
  final String source;
  final bool loading;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(20),
    decoration: _surfaceDecoration(context),
    child: LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 640;
        final titleAndDesc = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Flexible(
                  child: Text(
                    content.title,
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                _SourceBadge(label: source),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              content.description,
              style: TextStyle(
                color: context.cashier.inkMuted,
                fontSize: 15,
                height: 1.45,
              ),
            ),
          ],
        );

        final buttons = Wrap(
          spacing: 10,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            OutlinedButton.icon(
              key: const Key('settings-refresh'),
              onPressed: loading ? null : onRefresh,
              icon: const Icon(Icons.refresh, size: 18),
              label: const Text('刷新'),
            ),
          ],
        );

        if (compact) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              titleAndDesc,
              const SizedBox(height: 14),
              buttons],
          );
        }

        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: titleAndDesc),
            const SizedBox(width: 16),
            buttons,
          ],
        );
      },
    ),
  );
}

class _FactCard extends StatelessWidget {
  const _FactCard({required this.fact});

  final String fact;

  @override
  Widget build(BuildContext context) => Container(
    constraints: const BoxConstraints(minWidth: 210),
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    decoration: _surfaceDecoration(context),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(
          Icons.check_circle_outline,
          size: 20,
          color: Color(0xff15803d),
        ),
        const SizedBox(width: 8),
        Text(fact, style: const TextStyle(fontWeight: FontWeight.w600)),
      ],
    ),
  );
}

class _ProductionTable extends StatelessWidget {
  const _ProductionTable({
    required this.data,
    required this.onPrevious,
    required this.onNext,
  });

  final CashierSettingsSectionData data;
  final VoidCallback? onPrevious;
  final VoidCallback? onNext;

  @override
  Widget build(BuildContext context) {
    final rows = _displayRows(data);
    return Container(
      decoration: _surfaceDecoration(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 16, 18, 12),
            child: Row(
              children: [
                const Expanded(
                  child: Text(
                    '生产数据',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                  ),
                ),
                Text(
                  '共 ${data.total} 条',
                  style: TextStyle(color: context.cashier.inkMuted),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          if (rows.isEmpty)
            const _ProductionEmpty()
          else
            for (var index = 0; index < rows.length; index++) ...[
              ListTile(
                minTileHeight: 62,
                leading: Container(
                  width: 34,
                  height: 34,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: Theme.of(context).brightness == Brightness.dark
                        ? context.cashier.subtle
                        : const Color(0xfff1f3f5),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text('${index + 1}'),
                ),
                title: Text(
                  rows[index].$1,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                subtitle: Text(rows[index].$2),
              ),
              if (index != rows.length - 1)
                const Divider(height: 1, indent: 70),
            ],
          if (data.total > data.pageSize) ...[
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Text('第 ${data.page} 页'),
                  const SizedBox(width: 12),
                  IconButton(
                    key: const Key('settings-page-previous'),
                    tooltip: '上一页',
                    onPressed: onPrevious,
                    icon: const Icon(Icons.chevron_left),
                  ),
                  IconButton(
                    key: const Key('settings-page-next'),
                    tooltip: '下一页',
                    onPressed: onNext,
                    icon: const Icon(Icons.chevron_right),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _ProductionLoading extends StatelessWidget {
  const _ProductionLoading();

  @override
  Widget build(BuildContext context) => Container(
    height: 180,
    alignment: Alignment.center,
    decoration: _surfaceDecoration(context),
    child: const CircularProgressIndicator(),
  );
}

class _ProductionError extends StatelessWidget {
  const _ProductionError({required this.error, required this.onRetry});

  final Object? error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(24),
    decoration: _surfaceDecoration(context),
    child: Column(
      children: [
        const Icon(Icons.cloud_off_outlined, size: 36),
        const SizedBox(height: 10),
        Text('生产数据加载失败：$error', textAlign: TextAlign.center),
        const SizedBox(height: 12),
        FilledButton(onPressed: onRetry, child: const Text('重试')),
      ],
    ),
  );
}

class _ProductionEmpty extends StatelessWidget {
  const _ProductionEmpty();

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.all(32),
    child: Column(
      children: [
        Icon(
          Icons.inbox_outlined,
          size: 38,
          color: context.cashier.inkMuted),
        SizedBox(height: 10),
        Text('暂无数据', style: TextStyle(color: context.cashier.inkMuted)),
      ],
    ),
  );
}

class _StatePanel extends StatelessWidget {
  const _StatePanel({required this.states});

  final List<String> states;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(18),
    decoration: _surfaceDecoration(context),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          '边界与反馈状态',
          style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final state in states)
              Chip(
                avatar: const Icon(Icons.circle_outlined, size: 16),
                label: Text(state),
                backgroundColor: Colors.white,
                side: const BorderSide(color: Color(0xffdfe4ea)),
              ),
          ],
        ),
      ],
    ),
  );
}

class _SourceBadge extends StatelessWidget {
  const _SourceBadge({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
    decoration: BoxDecoration(
      color: const Color(0xffeef4ff),
      borderRadius: BorderRadius.circular(999),
    ),
    child: Text(
      label,
      style: const TextStyle(
        color: Color(0xff1d4ed8),
        fontSize: 12,
        fontWeight: FontWeight.w700,
      ),
    ),
  );
}

String _sourceLabel(String? source) => switch (source?.toUpperCase()) {
  'HEADQUARTERS' => '继承总店',
  'SHOP' => '门店覆盖',
  'SYSTEM' => '系统配置',
  _ => '当前门店',
};

List<(String, String)> _displayRows(CashierSettingsSectionData data) {
  if (data.items.isNotEmpty) {
    return data.items.map(_displayItem).toList(growable: false);
  }
  final rows = <(String, String)>[];
  final basic = data.raw['basic'];
  if (basic is Map) {
    final values = basic.cast<Object?, Object?>();
    final title = _firstText(values, const ['name', 'shopName', 'code']);
    final summary = _safeSummary(values);
    if (title.isNotEmpty || summary.isNotEmpty) {
      rows.add((title.isEmpty ? '门店基础资料' : title, summary));
    }
  }
  for (final entry in data.raw.entries) {
    if (_metadataKeys.contains(entry.key) || entry.key == 'basic') continue;
    if (_sensitiveKey(entry.key)) continue;
    final value = _displayValue(entry.value);
    if (value.isNotEmpty) rows.add((_fieldLabel(entry.key), value));
  }
  return rows;
}

(String, String) _displayItem(Map<String, Object?> item) {
  final title = _firstText(item, const [
    'name',
    'title',
    'roleName',
    'userName',
    'deviceName',
    'materialName',
    'orderNo',
    'code',
    'id',
  ]);
  return (title.isEmpty ? '未命名记录' : title, _safeSummary(item));
}

String _safeSummary(Map<Object?, Object?> values) {
  const titleKeys = {
    'name',
    'title',
    'roleName',
    'userName',
    'deviceName',
    'materialName',
    'orderNo',
    'code',
    'id',
  };
  final parts = <String>[];
  for (final entry in values.entries) {
    final key = '${entry.key}';
    if (titleKeys.contains(key) ||
        _metadataKeys.contains(key) ||
        _sensitiveKey(key)) {
      continue;
    }
    final value = _displayValue(entry.value);
    if (value.isEmpty) continue;
    parts.add('${_fieldLabel(key)}：$value');
    if (parts.length == 4) break;
  }
  return parts.isEmpty ? '暂无更多信息' : parts.join(' · ');
}

String _firstText(Map<Object?, Object?> values, List<String> keys) {
  for (final key in keys) {
    final value = values[key];
    if (value != null && '$value'.trim().isNotEmpty) return '$value'.trim();
  }
  return '';
}

String _displayValue(Object? value) {
  if (value == null) return '';
  if (value is bool) return value ? '是' : '否';
  if (value is Iterable) {
    return value.map(_displayValue).where((part) => part.isNotEmpty).join('、');
  }
  if (value is Map) return '';
  final text = '$value'.trim();
  return text.length > 80 ? '${text.substring(0, 80)}…' : text;
}

String _fieldLabel(String key) =>
    const {
      'status': '状态',
      'enabled': '启用',
      'source': '来源',
      'transport': '连接方式',
      'businessHours': '营业时段',
      'businessDays': '营业日',
      'updatedAt': '更新时间',
      'updatedBy': '更新人',
      'address': '地址',
      'phone': '门店电话',
    }[key] ??
    key;

bool _sensitiveKey(String key) {
  final normalized = key.toLowerCase();
  return const [
    'secret',
    'password',
    'token',
    'certificate',
    'privatekey',
    'apikey',
    'merchantno',
    'settlement',
  ].any(normalized.contains);
}

const _metadataKeys = {
  'items',
  'list',
  'records',
  'rows',
  'total',
  'page',
  'pageSize',
  'page_size',
  'version',
  'module',
};

BoxDecoration _surfaceDecoration(BuildContext context) {
  final isDark = Theme.of(context).brightness == Brightness.dark;
  return BoxDecoration(
    color: context.cashier.surface,
    border: Border.all(color: isDark ? context.cashier.border : const Color(0xffe2e6ea),
    ),
    borderRadius: BorderRadius.circular(12),
  );
}

class _PrototypeContent {
  const _PrototypeContent({
    required this.title,
    required this.description,
    required this.facts,
    required this.rows,
    this.action,
  });

  final String title;
  final String description;
  final List<String> facts;
  final List<(String, String)> rows;
  final String? action;
  final List<String> states = const ['加载中', '空状态', '校验失败', '保存失败', '权限不足'];
}

_PrototypeContent _contentFor(SettingsDestination destination, String id) {
  final key = '${destination.name}:$id';
  return switch (key) {
    'store:profile' => const _PrototypeContent(
      title: '门店基础资料',
      description: '当前门店配置默认继承总店，门店覆盖时记录差异和版本。',
      facts: ['继承总店', '保存需校验'],
      rows: [('基础资料', '名称、编码、电话、地址与地图定位')],
    ),
    'store:business-day' => const _PrototypeContent(
      title: '营业日',
      description: '各门店可独立配置营业日切换时间，所有报表按此口径统计。',
      facts: ['门店独立配置', '报表统一口径'],
      rows: [('切换时间', '当前 04:00；修改后影响下一营业日'), ('影响预览', '日报、交班、库存和结算日期')],
      action: '修改切换时间',
    ),
    'store:inheritance' => const _PrototypeContent(
      title: '继承设置',
      description: '查看总店配置与门店差异，可创建覆盖或恢复继承。',
      facts: ['差异可追溯', '恢复需确认'],
      rows: [('基础资料', '门店覆盖 4 项'), ('营业规则', '继承总店')],
    ),
    'printer:devices' => const _PrototypeContent(
      title: '打印机',
      description: '统一打印系统将业务标准文档转换为品牌协议，并通过对应通道发送。',
      facts: ['LAN', 'USB', '蓝牙', '云打印', '标准打印文档 → 品牌适配器 → 传输通道'],
      rows: [
        ('前台小票机', 'LAN · 收银端直接执行 · 在线'),
        ('后厨标签机', 'USB · Windows 端 · 在线'),
        ('移动打印机', '蓝牙 · Android 端 · 待连接'),
        ('云打印机', '云打印 · 服务端执行 · 在线'),
      ],
      action: '新增打印机',
    ),
    'printer:rules' => const _PrototypeContent(
      title: '打印规则',
      description: '按业务场景绑定打印机、模板、份数与触发条件。',
      facts: ['标准场景映射', '无远程重启'],
      rows: [('堂食结账', '前台小票机 · 结账后 1 份'), ('厨房制作', '后厨标签机 · 下单后按档口')],
      action: '新增规则',
    ),
    'printer:templates' => const _PrototypeContent(
      title: '票据模板',
      description: '预览标准票据字段，不与具体打印品牌耦合。',
      facts: ['版本化模板', '多品牌复用'],
      rows: [('结账小票', '门店信息、菜品、优惠、支付'), ('传菜单', '桌台、菜品、备注、出餐数量')],
      action: '复制模板',
    ),
    'printer:test' => const _PrototypeContent(
      title: '打印测试',
      description: '选择设备和模板执行真实打印，并反馈端侧或云端结果。',
      facts: ['真实设备测试', '失败原因可诊断'],
      rows: [('选择设备', '仅显示当前终端可执行的设备'), ('测试结果', '等待执行、成功或失败')],
      action: '开始测试',
    ),
    'printer:jobs' => const _PrototypeContent(
      title: '任务记录',
      description: '查询打印任务、执行端、耗时和错误，不提供远程重启。',
      facts: ['任务可追踪', '禁止远程重启'],
      rows: [('今日任务', '128 成功 · 2 失败'), ('失败任务', '可查看错误并按能力重试')],
    ),
    'payment:channels' => const _PrototypeContent(
      title: '支付渠道',
      description: '门店管理员只管理渠道可用性与终端范围；敏感支付配置由超级管理员在安全后台维护。',
      facts: ['停用前展示影响', '真实扣款，完成后自动退款'],
      rows: [('微信支付', '收银台与扫码盒子可用'), ('支付宝', '收银台可用'), ('现金', '线下收款')],
    ),
    'payment:impact' => const _PrototypeContent(
      title: '停用影响',
      description: '停用前检查未完成交易并明确受影响的收款入口。',
      facts: ['未完成交易时阻止停用', '操作写入审计'],
      rows: [('收银台扫码', '影响微信与支付宝主扫'), ('待入账订单', '必须处理完毕后停用')],
    ),
    'payment:test' => const _PrototypeContent(
      title: '支付测试',
      description: '测试交易执行真实扣款，并在扣款成功后自动退款。',
      facts: ['真实扣款，完成后自动退款', '退款处理中可追踪'],
      rows: [('扣款阶段', '扫码支付并确认到账'), ('退款阶段', '自动原路退款并展示结果')],
      action: '发起测试交易',
    ),
    'notification:rules' => const _PrototypeContent(
      title: '通知规则',
      description: '查看当前门店的通知规则。',
      facts: ['只读查询'],
      rows: [('新订单', '声音 + 弹窗 · 全时段'), ('库存预警', '弹窗 · 店长')],
    ),
    'notification:receivers' => const _PrototypeContent(
      title: '接收人',
      description: '选择门店角色或具体员工，联系方式按权限脱敏。',
      facts: ['联系方式脱敏'],
      rows: [('门店管理员', '2 人'), ('值班店长', '按排班动态匹配')],
    ),
    'notification:deliveries' => const _PrototypeContent(
      title: '发送记录',
      description: '查看发送状态、失败原因和重试次数。',
      facts: ['失败可诊断'],
      rows: [('新订单提醒', '成功 · 16:20'), ('库存预警', '失败 · 设备离线')],
    ),
    'marketing:campaigns' => const _PrototypeContent(
      title: '首单活动',
      description: '首期四种活动复用现有优惠券与会员规则引擎。',
      facts: ['首单立减', '首单折扣', '首单满赠', '首单返券'],
      rows: [('新人立减 10 元', '进行中 · 当前门店'), ('首单 9 折', '待生效 · 09-01 00:00')],
      action: '新增首单活动',
    ),
    'marketing:eligibility' => const _PrototypeContent(
      title: '资格与互斥',
      description: '服务端返回资格结论及命中规则，前端不自行推导。',
      facts: ['按当前门店计算首单资格', '取消或全额退款后恢复资格', '会员折扣与普通优惠券不可叠加'],
      rows: [('资格判定', '按客户与当前门店订单历史判定'), ('冲突解释', '展示不可叠加的会员或优惠券规则')],
    ),
    'marketing:redemptions' => const _PrototypeContent(
      title: '核销记录',
      description: '追踪首单优惠使用、取消、退款与资格恢复。',
      facts: ['恢复原因留痕'],
      rows: [
        ('ORD20260828001', '立减 10 元 · 已核销'),
        ('ORD20260827019', '全额退款 · 资格已恢复'),
      ],
    ),
    'employee:employees' => const _PrototypeContent(
      title: '员工',
      description: '管理员工状态、所属门店和角色，敏感操作需确认。',
      facts: ['一人多店', '一人多角色'],
      rows: [('张店长', '2 家门店 · 店长/库存审核员'), ('李收银', '1 家门店 · 收银员')],
      action: '新增员工',
    ),
    'employee:roles' => const _PrototypeContent(
      title: '角色',
      description: '角色包含优先级与权限集合，被引用角色不可直接删除。',
      facts: ['高优先级覆盖低优先级', '同优先级拒绝优先'],
      rows: [('店长', '优先级 80 · 12 人'), ('收银员', '优先级 40 · 26 人')],
      action: '新增角色',
    ),
    'employee:matrix' => const _PrototypeContent(
      title: '权限矩阵',
      description: '以模块和操作呈现允许/拒绝，并显示最终决策来源。',
      facts: ['拒绝优先', '可解释决策'],
      rows: [('订单退款', '店长允许 · 风控角色拒绝 → 最终拒绝'), ('日志导出', '仅超级管理员允许')],
    ),
    'employee:shops' => const _PrototypeContent(
      title: '多店授权',
      description: '按经营主体和门店范围授予员工角色。',
      facts: ['一人多店'],
      rows: [('张店长', '西湖店：店长；滨江店：值班经理')],
    ),
    'employee:changes' => const _PrototypeContent(
      title: '变更记录',
      description: '记录角色、门店范围和权限变更前后值。',
      facts: ['敏感操作审计'],
      rows: [('张店长', '新增滨江店值班经理 · 15:20')],
    ),
    'inventory:materials' => const _PrototypeContent(
      title: '原料',
      description: '管理原料、单位、库存上下限、保质期和可替代属性。',
      facts: ['多仓库存', '库存预警'],
      rows: [('鸡胸肉', '冷藏仓 · 12.5kg'), ('生菜', '前置仓 · 3.2kg')],
      action: '新增原料',
    ),
    'inventory:bom' => const _PrototypeContent(
      title: 'BOM配方',
      description: '菜品配方支持替代原料、损耗率与版本化生效。',
      facts: ['替代原料', '多版本定时生效'],
      rows: [('香煎鸡胸', 'v3 待 09-01 生效 · 2 个替代原料'), ('牛肉饭', 'v2 当前有效')],
      action: '新建 BOM 版本',
    ),
    'inventory:purchase' => const _PrototypeContent(
      title: '采购',
      description: '采购申请、审核、到货与入库形成完整状态链。',
      facts: ['默认启用审核'],
      rows: [('PO20260828001', '待审核 · ¥1,280'), ('PO20260827008', '待收货 · 3 项')],
      action: '新建采购单',
    ),
    'inventory:suppliers' => const _PrototypeContent(
      title: '供应商',
      description: '维护供应主体、联系人和供货范围，结算字段按权限过滤。',
      facts: ['敏感字段按权限'],
      rows: [('鲜达食材', '蔬菜 · 正常'), ('牧场直供', '肉类 · 正常')],
      action: '新增供应商',
    ),
    'inventory:warehouses' => const _PrototypeContent(
      title: '仓库',
      description: '同一经营主体下管理多仓库及门店归属。',
      facts: ['多仓库', '经营主体隔离'],
      rows: [('西湖冷藏仓', '西湖店 · 326 个批次'), ('中央仓', '总部 · 1,208 个批次')],
      action: '新增仓库',
    ),
    'inventory:transfers' => const _PrototypeContent(
      title: '调拨',
      description: '调拨覆盖出库、在途和入库，只允许同一经营主体内流转。',
      facts: ['仅限同一经营主体', '全流程留痕'],
      rows: [
        ('TR20260828002', '中央仓 → 西湖店 · 在途'),
        ('TR20260827011', '西湖店 → 滨江店 · 已入库'),
      ],
      action: '新建调拨单',
    ),
    'inventory:batches' => const _PrototypeContent(
      title: '批次',
      description: '按生产日期、到期日和可用量管理，系统默认推荐最早到期批次。',
      facts: ['默认 FEFO 出库', '人工覆盖需原因'],
      rows: [
        ('鸡胸肉 B240821', '2026-08-30 到期 · 6.5kg'),
        ('鸡胸肉 B240823', '2026-09-02 到期 · 6kg'),
      ],
    ),
    'inventory:ledger' => const _PrototypeContent(
      title: '库存预警',
      description: '查看原料余量与预警阈值，及时补充库存。',
      facts: ['库存预警'],
      rows: [('鸡胸肉 -2kg', '厨房领用 · 16:10'), ('生菜 +5kg', '采购入库 · 15:42')],
    ),
    'report:catalog' => const _PrototypeContent(
      title: '报表目录',
      description: '日报、周报、月报、菜品、收银员和门店利润统一按营业日统计。',
      facts: ['营业日口径'],
      rows: [('经营日报', '昨日营业日 · 已更新'), ('菜品排行', '本周营业日')],
    ),
    'report:business-day' => const _PrototypeContent(
      title: '营业日设置',
      description: '展示当前门店切换时间、统计范围和数据截止时间。',
      facts: ['门店独立配置', '返回数据截止时间'],
      rows: [('当前营业日', '2026-08-28 · 04:00 至次日 03:59')],
    ),
    'report:exports' => const _PrototypeContent(
      title: '订阅导出',
      description: '大报表使用异步任务生成，下载地址短期有效。',
      facts: ['异步导出'],
      rows: [('日报订阅', '每日 06:00 · 店长'), ('导出任务 #892', '生成中 · 42%')],
      action: '新增订阅',
    ),
    'kds:mode' => const _PrototypeContent(
      title: 'KDS 模式配置',
      description: '配置门店出餐工作模式：仅飞鹅打印、仅后厨厨显或打印+厨显并行。',
      facts: ['print_only', 'kds_only', 'both', '划单按 serve_print_enabled 打印'],
      rows: [
        ('当前模式', 'both（厨显 + 飞鹅打印并行）'),
        ('待配菜流程', '已开启 · 局域网实时同步'),
        ('传菜打印', '划单完成自动触发传菜单打印'),
      ],
      action: '修改模式配置',
    ),
    'kds:stations' => const _PrototypeContent(
      title: '档口分屏',
      description: '管理后厨档口屏配置（screen_tag），支持一键初始化五屏标准档口。',
      facts: ['五屏初始化', 'screen_tag 路由'],
      rows: [
        ('烧烤档', 'screen_tag: bbq · 排序 1'),
        ('热菜档', 'screen_tag: hot · 排序 2'),
        ('冷菜/凉菜档', 'screen_tag: cold · 排序 3'),
        ('酒水/传菜档', 'screen_tag: bar · 排序 4'),
      ],
      action: '一键初始化五屏',
    ),
    'kds:binding' => const _PrototypeContent(
      title: '菜品分类绑屏',
      description: '将商品分类或特定菜品路由绑定至对应的后厨档口屏。',
      facts: ['分类路由', '单品优先'],
      rows: [
        ('烧烤类', '绑定至 烧烤档 (bbq)'),
        ('凉菜/小吃', '绑定至 冷菜档 (cold)'),
        ('酒水饮料', '绑定至 酒水档 (bar)'),
      ],
      action: '新增绑屏规则',
    ),
    'kds:devices' => const _PrototypeContent(
      title: '厨显设备绑定',
      description: '局域网内的后厨平板终端绑定至指定档口，并颁发鉴权令牌。',
      facts: ['配对码绑定', '颁发 device_token', '检查设备可用性'],
      rows: [
        ('KDS-TABLET-01', '后厨 1 号屏 · 烧烤档 · 在线'),
        ('KDS-TABLET-02', '前厅传菜屏 · 传菜档 · 在线'),
      ],
      action: '生成配对码',
    ),
    'kds:diagnostics' => const _PrototypeContent(
      title: 'KDS 运行诊断',
      description: '查看局域网主收银权威节点状态、WebSocket 连接数、事件投递队列与日志。',
      facts: ['局域网权威', '事件复制', '死信队列与排查'],
      rows: [
        ('局域网服务', '正常运行 · 端口 17026'),
        ('在线设备', '2 台厨显设备已连接'),
        ('同步队列', '0 待同步 · 0 失败'),
      ],
      action: '刷新诊断',
    ),
    _ => _PrototypeContent(
      title: sectionFallback(destination, id),
      description: '该子页面已纳入原型和接口开发任务。',
      facts: const ['当前门店'],
      rows: const [('配置项', '等待后端接口联调')],
    ),
  };
}

String sectionFallback(SettingsDestination destination, String id) =>
    destination.sections.firstWhere((section) => section.id == id).label;
