import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../../core/admin_api_client.dart';
import '../data/cashier_settings_repository.dart';
import '../data/marketing_repository.dart';
import '../data/real_marketing_repository.dart';
import '../domain/marketing_models.dart';
import 'cashier_settings_prototype_pages.dart';
import 'cashier_settings_shared.dart';
import 'cashier_marketing_redemptions_section.dart';
import '../../cashier_shell/presentation/cashier_tokens.dart';

/// 营销设置页（M-G 营销配置）。
/// campaigns（首单活动）/ eligibility（资格评估）/ invite-reward（首单返利）/
/// invite-poster（邀请海报）/ ninefold（夜间九折）分区提供配置闭环，
/// 其余分区沿用原型占位页；无接口客户端时回退原型页。
class CashierSettingsMarketingPage extends StatelessWidget {
  const CashierSettingsMarketingPage({
    super.key,
    required this.repository,
    required this.client,
    required this.section,
    this.permissions = const {},
    this.onDirtyChanged,
  });

  final CashierSettingsRepository repository;
  final AdminApiClient? client;
  final SettingsSectionSpec section;
  final Set<String> permissions;
  final ValueChanged<bool>? onDirtyChanged;

  bool get _canWrite =>
      permissions.contains('admin:manage') ||
      permissions.contains('order:config') ||
      permissions.contains('marketing:firstorder:manage');

  @override
  Widget build(BuildContext context) {
    final apiClient = client;
    if (apiClient == null) {
      return SettingsPrototypePage(
        repository: repository,
        destination: SettingsDestination.marketing,
        section: section,
      );
    }
    final marketing = RealMarketingRepository(apiClient);
    switch (section.id) {
      case 'redemptions':
        return CashierMarketingRedemptionsSection(repository: marketing);
      case 'campaigns':
        return _CampaignsSection(repository: marketing);
      case 'banners':
        return _BannersSection(
          repository: marketing,
          // 轮播图写权限为 banner:manage（营销配置权限不可代写）。
          canWrite: _canWrite || permissions.contains('banner:manage'),
        );
      case 'eligibility':
        return _EligibilitySection(repository: marketing);
      case 'invite-reward':
        return _InviteRewardSection(repository: marketing,
          onDirtyChanged: onDirtyChanged,
        );
      case 'invite-poster':
        return _InvitePosterSection(repository: marketing,
          onDirtyChanged: onDirtyChanged,
        );
      case 'ninefold':
        return _NinefoldSection(
          repository: marketing,
          canWrite: _canWrite,
          onDirtyChanged: onDirtyChanged,
        );
      default:
        return SettingsPrototypePage(
          repository: repository,
          destination: SettingsDestination.marketing,
          section: section,
        );
    }
  }
}

const _campaignStatusMeta = <String, (StatusBadgeType, String)>{
  'DRAFT': (StatusBadgeType.warning, '草稿'),
  'ACTIVE': (StatusBadgeType.success, '启用'),
  'PAUSED': (StatusBadgeType.neutral, '已停用'),
  'EXPIRED': (StatusBadgeType.info, '已过期'),
};

const _campaignTypeLabels = <String, String>{
  'DISCOUNT': '满减',
  'GIFT': '赠品',
  'FREEBIE': '免费',
};

/// 首单活动状态筛选（null = 全部），顺序对齐 UI030 原型。
const _campaignFilters = <String?, String>{
  null: '全部',
  'ACTIVE': '启用',
  'DRAFT': '草稿',
  'PAUSED': '已停用',
};

/// 数据表格统一表头（UI030-v1 锁定，营销页私有副本）。
Widget _tableHeader(BuildContext context, String label) => Padding(
  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
  child: Text(
    label,
    style: TextStyle(
      fontSize: 12,
      fontWeight: FontWeight.w600,
      color: context.cashier.inkMuted,
    ),
  ),
);

/// 表单抽屉分组标题（对齐 UI030 原型「基本信息 / 规则 / 有效期与频次」）。
Widget _groupTitle(BuildContext context, String label) => Padding(
  padding: const EdgeInsets.fromLTRB(0, 4, 0, 8),
  child: Text(
    label,
    style: TextStyle(
      fontSize: 12,
      fontWeight: FontWeight.w700,
      color: context.cashier.inkMuted,
      letterSpacing: 0.5,
    ),
  ),
);

/// 右侧滑出抽屉容器（UI030-v1 锁定：宽 520、220ms 滑入、barrier 可点关闭）。
Future<T?> showMarketingDrawer<T>({
  required BuildContext context,
  required String title,
  required Widget child,
}) {
  return showGeneralDialog<T>(
    context: context,
    barrierDismissible: true,
    barrierLabel: '关闭',
    barrierColor: const Color(0x590f172a),
    transitionDuration: const Duration(milliseconds: 220),
    pageBuilder: (context, _, __) => Align(
      alignment: Alignment.centerRight,
      child: Material(
        color: context.cashier.surface,
        borderRadius: const BorderRadius.horizontal(
          left: Radius.circular(12)),
        clipBehavior: Clip.antiAlias,
        child: SizedBox(
          width: 520,
          height: double.infinity,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 12, 16),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        title,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.close),
                      tooltip: '关闭',
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(20),
                  child: child,
                ),
              ),
            ],
          ),
        ),
      ),
    ),
    transitionBuilder: (context, animation, secondary, child) =>
        SlideTransition(
          position: Tween(begin: const Offset(1, 0), end: Offset.zero,
          ).animate(
            CurvedAnimation(parent: animation, curve: Curves.easeOut)),
          child: child,
        ),
  );
}

/// 首单活动新增/编辑表单抽屉（表单字段 Key 与既有测试兼容）。
Future<MarketingCampaign?> showCampaignFormDrawer(
  BuildContext context,
  MarketingCampaign? initial,
) {
  return showGeneralDialog<MarketingCampaign>(
    context: context,
    barrierDismissible: true,
    barrierLabel: '关闭',
    barrierColor: const Color(0x590f172a),
    transitionDuration: const Duration(milliseconds: 220),
    pageBuilder: (context, _, __) => Align(
      alignment: Alignment.centerRight,
      child: Material(
        color: context.cashier.surface,
        borderRadius: const BorderRadius.horizontal(
          left: Radius.circular(12)),
        clipBehavior: Clip.antiAlias,
        child: SizedBox(
          width: 520,
          height: double.infinity,
          child: _CampaignFormDrawer(initial: initial),
        ),
      ),
    ),
    transitionBuilder: (context, animation, secondary, child) =>
        SlideTransition(
          position: Tween(begin: const Offset(1, 0), end: Offset.zero,
          ).animate(
            CurvedAnimation(parent: animation, curve: Curves.easeOut)),
          child: child,
        ),
  );
}

class _CampaignsSection extends StatefulWidget {
  const _CampaignsSection({required this.repository});

  final MarketingRepository repository;

  @override
  State<_CampaignsSection> createState() => _CampaignsSectionState();
}

class _CampaignsSectionState extends State<_CampaignsSection> {
  late Future<List<MarketingCampaign>> _future;
  String? _campaignStatusFilter;

  @override
  void initState() {
    super.initState();
    _future = widget.repository.loadCampaigns();
  }

  void _reload() => setState(() {
        _future = widget.repository.loadCampaigns();
      });

  Future<void> _showDetail(MarketingCampaign campaign) async {
    late MarketingCampaign resolved;
    try {
      resolved = await widget.repository.loadCampaignDetail(campaign.id);
    } catch (_) {
      resolved = campaign;
    }
    if (!mounted) return;
    await showMarketingDrawer<void>(
      context: context,
      title: '活动详情：${resolved.name}',
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _detailRow('类型', _campaignTypeLabels[resolved.campaignType] ??
              resolved.campaignType,
          ),
          _detailRow('状态', resolved.status),
          _detailRow('门槛金额', '¥${resolved.thresholdAmount.toStringAsFixed(2)}'),
          _detailRow('优惠值', resolved.discountValue.toStringAsFixed(2)),
          _detailRow('优惠说明', resolved.discountDesc ?? '-'),
          _detailRow('开始时间', resolved.startTime ?? '-'),
          _detailRow('结束时间', resolved.endTime ?? '-'),
          _detailRow('核销/恢复', '${resolved.redemptions} / ${resolved.restorations}',
          ),
          if (resolved.version != null)
            _detailRow('版本', '${resolved.version}'),
        ],
      ),
    );
  }

  Widget _detailRow(String label, String value) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 3),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 90,
          child: Text(
            label,
            style: TextStyle(color: context.cashier.inkMuted)),
        ),
        Expanded(child: Text(value)),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<MarketingCampaign>>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return SettingsErrorState(
            message: '加载首单活动失败：${snapshot.error}',
            onRetry: _reload,
          );
        }
        if (!snapshot.hasData) {
          return const SettingsSkeletonLoader(rows: 3);
        }
        final campaigns = snapshot.data!;
        final filtered = _campaignStatusFilter == null
            ? campaigns
            : campaigns
                .where((c) => c.status == _campaignStatusFilter)
                .toList();
        return SettingsPagePadding(
          child: SettingsPanel(
            title: '首单活动',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          for (final entry in _campaignFilters.entries)
                            ChoiceChip(
                              label: Text(entry.value),
                              selected: _campaignStatusFilter == entry.key,
                              onSelected: (_) => setState(() {
                                _campaignStatusFilter = entry.key;
                              }),
                            ),
                        ],
                      ),
                    ),
                    TextButton.icon(
                      key: const Key('marketing-campaign-create'),
                      onPressed: () => _openForm(null),
                      icon: const Icon(Icons.add_circle_outline, size: 18),
                      label: const Text('新增活动'),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                if (filtered.isEmpty)
                  const SettingsEmptyState(
                    title: '暂无首单活动',
                    description: '首单活动按门店配置，同一时间窗仅一个活动生效。',
                  )
                else
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Table(
                      columnWidths: const {
                        0: FixedColumnWidth(190),
                        1: FixedColumnWidth(80),
                        2: FixedColumnWidth(90),
                        3: FixedColumnWidth(100),
                        4: FixedColumnWidth(180),
                        5: FixedColumnWidth(110),
                        6: FixedColumnWidth(90),
                        7: FixedColumnWidth(230),
                      },
                      defaultVerticalAlignment:
                          TableCellVerticalAlignment.middle,
                      children: [
                        TableRow(
                          decoration: const BoxDecoration(
                            color: Color(0xfffafafa),
                          ),
                          children: [
                            _tableHeader(context, '活动名称'),
                            _tableHeader(context, '类型'),
                            _tableHeader(context, '门槛'),
                            _tableHeader(context, '折扣'),
                            _tableHeader(context, '有效期'),
                            _tableHeader(context, '核销 / 恢复'),
                            _tableHeader(context, '状态'),
                            _tableHeader(context, '操作'),
                          ],
                        ),
                        for (final campaign in filtered)
                          _campaignTableRow(context, campaign),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  TableRow _campaignTableRow(
    BuildContext context,
    MarketingCampaign campaign) {
    final (badgeType, badgeLabel) =
        _campaignStatusMeta[campaign.status] ??
            (StatusBadgeType.neutral, campaign.status);
    Widget cell(Widget child) => Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: child,
    );
    final typeLabel =
        _campaignTypeLabels[campaign.campaignType] ??
            campaign.campaignType;
    final canPause = campaign.status == 'ACTIVE' ||
        campaign.status == 'DRAFT';
    return TableRow(
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: Color(0xfff1f1f1))),
      ),
      children: [
        cell(Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              campaign.name,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              '#${campaign.id} · ${campaign.discountDesc ?? typeLabel}',
              style: TextStyle(
                fontSize: 12,
                color: context.cashier.inkMuted),
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
        ),
        cell(Text(typeLabel)),
        cell(Text(
          '¥${campaign.thresholdAmount.toStringAsFixed(2)}',
          textAlign: TextAlign.right,
        ),
        ),
        cell(Text(
          campaign.discountDesc?.isNotEmpty == true
              ? campaign.discountDesc!
              : '减 ¥${campaign.discountValue.toStringAsFixed(0)}',
        ),
        ),
        cell(Text(
          '${campaign.startTime != null && campaign.startTime!.length >= 10 ? campaign.startTime!.substring(0, 10) : '-'}'
          ' ~ '
          '${campaign.endTime != null && campaign.endTime!.length >= 10 ? campaign.endTime!.substring(0, 10) : '-'}',
          style: TextStyle(fontSize: 12, color: context.cashier.inkMuted),
        ),
        ),
        cell(Text(
          '${campaign.redemptions} / ${campaign.restorations}',
          textAlign: TextAlign.right,
        ),
        ),
        cell(FittedBox(
          fit: BoxFit.scaleDown,
          child: SettingsStatusBadge(label: badgeLabel, type: badgeType),
        ),
        ),
        cell(Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextButton.icon(
                  key: Key('marketing-campaign-detail-${campaign.id}'),
                  onPressed: () => _showDetail(campaign),
                  icon: const Icon(Icons.info_outline, size: 15),
                  label: const Text('详情'),
                ),
                TextButton.icon(
                  key: Key('marketing-campaign-edit-${campaign.id}'),
                  onPressed: () => _openForm(campaign),
                  icon: const Icon(Icons.edit_outlined, size: 15),
                  label: const Text('编辑'),
                ),
              ],
            ),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (canPause)
                  TextButton.icon(
                    key: Key('marketing-campaign-pause-${campaign.id}'),
                    onPressed: () => _pauseCampaign(campaign),
                    icon: Icon(
                      Icons.pause_circle_outline,
                      size: 15,
                      color: context.cashier.warning,
                    ),
                    label: Text(
                      '停用',
                      style: TextStyle(color: context.cashier.warning),
                    ),
                  )
                else
                  TextButton.icon(
                    key: Key('marketing-campaign-resume-${campaign.id}'),
                    onPressed: () => _resumeCampaign(campaign),
                    icon: Icon(
                      Icons.play_circle_outline,
                      size: 15,
                      color: context.cashier.success,
                    ),
                    label: Text(
                      '恢复',
                      style: TextStyle(color: context.cashier.success),
                    ),
                  ),
              ],
            ),
          ],
        ),
        ),
      ],
    );
  }

  Future<void> _openForm(MarketingCampaign? existing) async {
    if (existing != null) {
      try {
        existing = await widget.repository.loadCampaignDetail(existing.id);
      } catch (_) {}
    }
    if (!mounted) return;
    final saved = await showCampaignFormDrawer(context, existing);
    if (saved == null || !mounted) return;
    try {
      if (existing == null) {
        await widget.repository.createCampaign(saved);
        showSettingsSaved(context, '首单活动已创建');
      } else {
        await widget.repository.updateCampaign(saved);
        showSettingsSaved(context, '首单活动已更新');
      }
      _reload();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context,
      ).showSnackBar(
        SnackBar(content: Text('保存失败：$error')));
    }
  }

  Future<void> _pauseCampaign(MarketingCampaign campaign) async {
    MarketingCampaign detail;
    try {
      detail = await widget.repository.loadCampaignDetail(campaign.id);
    } catch (_) {
      detail = campaign;
    }
    final confirmed = await showSettingsConfirmDialog(
      context: context,
      title: '停用首单活动',
      message:
          '停用「${detail.name}」？活动将暂停发放（无删除端点，活动通过状态管理）。',
      destructive: true,
      confirmLabel: '停用',
    );
    if (confirmed != true || !mounted) return;
    try {
      await widget.repository.updateCampaign(
        MarketingCampaign(
          id: detail.id,
          name: detail.name,
          campaignType: detail.campaignType,
          status: 'PAUSED',
          thresholdAmount: detail.thresholdAmount,
          discountValue: detail.discountValue,
          discountDesc: detail.discountDesc,
          startTime: detail.startTime,
          endTime: detail.endTime,
          version: detail.version,
        ),
      );
      if (!mounted) return;
      showSettingsSaved(context, '活动已停用');
      _reload();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context,
      ).showSnackBar(
        SnackBar(content: Text('停用失败：$error')));
    }
  }

  Future<void> _resumeCampaign(MarketingCampaign campaign) async {
    MarketingCampaign detail;
    try {
      detail = await widget.repository.loadCampaignDetail(campaign.id);
    } catch (_) {
      detail = campaign;
    }
    final confirmed = await showSettingsConfirmDialog(
      context: context,
      title: '恢复首单活动',
      message: '恢复「${detail.name}」？恢复后按原规则继续生效。',
      destructive: false,
      confirmLabel: '恢复',
    );
    if (confirmed != true || !mounted) return;
    try {
      await widget.repository.updateCampaign(
        MarketingCampaign(
          id: detail.id,
          name: detail.name,
          campaignType: detail.campaignType,
          status: 'ACTIVE',
          thresholdAmount: detail.thresholdAmount,
          discountValue: detail.discountValue,
          discountDesc: detail.discountDesc,
          startTime: detail.startTime,
          endTime: detail.endTime,
          version: detail.version,
        ),
      );
      if (!mounted) return;
      showSettingsSaved(context, '活动已恢复');
      _reload();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context,
      ).showSnackBar(
        SnackBar(content: Text('恢复失败：$error')));
    }
  }
}

/// 新增/编辑首单活动共用表单（抽屉形态，右侧滑出）。
class _CampaignFormDrawer extends StatefulWidget {
  const _CampaignFormDrawer({this.initial});

  final MarketingCampaign? initial;

  @override
  State<_CampaignFormDrawer> createState() => _CampaignFormDrawerState();
}

class _CampaignFormDrawerState extends State<_CampaignFormDrawer> {
  late final TextEditingController _name;
  late final TextEditingController _threshold;
  late final TextEditingController _discount;
  late final TextEditingController _discountDesc;
  late final TextEditingController _startTime;
  late final TextEditingController _endTime;
  String _campaignType;
  String _status;
  String? _error;

  _CampaignFormDrawerState()
    : _campaignType = 'DISCOUNT',
      _status = 'DRAFT';

  @override
  void initState() {
    super.initState();
    final initial = widget.initial;
    _name = TextEditingController(text: initial?.name ?? '');
    _threshold = TextEditingController(
      text: initial == null ? '' : initial.thresholdAmount.toStringAsFixed(2),
    );
    _discount = TextEditingController(
      text: initial == null ? '' : initial.discountValue.toStringAsFixed(2),
    );
    _discountDesc = TextEditingController(text: initial?.discountDesc ?? '');
    _startTime = TextEditingController(text: initial?.startTime ?? '');
    _endTime = TextEditingController(text: initial?.endTime ?? '');
    if (initial != null) {
      _campaignType = initial.campaignType;
      _status = initial.status;
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _threshold.dispose();
    _discount.dispose();
    _discountDesc.dispose();
    _startTime.dispose();
    _endTime.dispose();
    super.dispose();
  }

  void _submit() {
    final name = _name.text.trim();
    if (name.isEmpty) {
      setState(() => _error = '请填写活动名称');
      return;
    }
    if (_startTime.text.trim().isEmpty || _endTime.text.trim().isEmpty) {
      setState(() => _error = '请填写开始与结束时间（yyyy-MM-dd HH:mm:ss）');
      return;
    }
    final initial = widget.initial;
    final campaign = MarketingCampaign(
      id: initial?.id ?? 0,
      name: name,
      campaignType: _campaignType,
      status: _status,
      thresholdAmount: double.tryParse(_threshold.text.trim()) ?? 0,
      discountValue: double.tryParse(_discount.text.trim()) ?? 0,
      discountDesc: _discountDesc.text.trim().isEmpty
          ? null
          : _discountDesc.text.trim(),
      startTime: _startTime.text.trim(),
      endTime: _endTime.text.trim(),
      version: initial?.version,
    );
    Navigator.of(context).pop(campaign);
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.initial != null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 12, 16),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  isEdit ? '编辑首单活动' : '新增首单活动',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              IconButton(
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(Icons.close),
                tooltip: '关闭',
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _groupTitle(context, '基本信息'),
                TextField(
                  key: const Key('marketing-campaign-form-name'),
                  controller: _name,
                  decoration: const InputDecoration(
                    labelText: '名称 *',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
                const SizedBox(height: 10),
                _groupTitle(context, '规则'),
                DropdownButtonFormField<String>(
                  key: const Key('marketing-campaign-form-type'),
                  initialValue: _campaignType,
                  decoration: const InputDecoration(
                    labelText: '类型',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  items: const [
                    DropdownMenuItem(value: 'DISCOUNT', child: Text('满减（DISCOUNT）'),
                    ),
                    DropdownMenuItem(value: 'GIFT', child: Text('赠品（GIFT）')),
                    DropdownMenuItem(value: 'FREEBIE', child: Text('免费（FREEBIE）'),
                    ),
                  ],
                  onChanged: (value) =>
                      setState(() => _campaignType = value ?? 'DISCOUNT'),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        key: const Key('marketing-campaign-form-threshold'),
                        controller: _threshold,
                        decoration: const InputDecoration(
                          labelText: '门槛金额（元）',
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: TextField(
                        key: const Key('marketing-campaign-form-discount'),
                        controller: _discount,
                        decoration: const InputDecoration(
                          labelText: '优惠值',
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                TextField(
                  key: const Key('marketing-campaign-form-desc'),
                  controller: _discountDesc,
                  decoration: const InputDecoration(
                    labelText: '优惠说明',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
                const SizedBox(height: 10),
                _groupTitle(context, '有效期与状态'),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        key: const Key('marketing-campaign-form-start'),
                        controller: _startTime,
                        decoration: const InputDecoration(
                          labelText: '开始时间 *',
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: TextField(
                        key: const Key('marketing-campaign-form-end'),
                        controller: _endTime,
                        decoration: const InputDecoration(
                          labelText: '结束时间 *',
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                DropdownButtonFormField<String>(
                  key: const Key('marketing-campaign-form-status'),
                  initialValue: _status,
                  decoration: const InputDecoration(
                    labelText: '状态',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  items: [
                    for (final entry in _campaignStatusMeta.entries)
                      if (entry.key != 'EXPIRED')
                        DropdownMenuItem(
                          value: entry.key,
                          child: Text(entry.value.$2),
                        ),
                  ],
                  onChanged: (value) =>
                      setState(() => _status = value ?? 'DRAFT'),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: context.cashier.dangerBackground,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      _error!,
                      style: TextStyle(color: context.cashier.danger),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
        const Divider(height: 1),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('取消'),
              ),
              TextButton(
                key: const Key('marketing-campaign-form-submit'),
                onPressed: _submit,
                child: Text(isEdit ? '保存' : '创建'),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _EligibilitySection extends StatefulWidget {
  const _EligibilitySection({required this.repository});

  final MarketingRepository repository;

  @override
  State<_EligibilitySection> createState() => _EligibilitySectionState();
}

class _EligibilitySectionState extends State<_EligibilitySection> {
  final _customerId = TextEditingController();
  final _orderAmount = TextEditingController();
  var _busy = false;
  MarketingEligibilityResult? _result;
  String? _error;

  @override
  void dispose() {
    _customerId.dispose();
    _orderAmount.dispose();
    super.dispose();
  }

  Future<void> _evaluate() async {
    final customerId = _customerId.text.trim();
    if (customerId.isEmpty) {
      setState(() => _error = '请输入客户标识（openid 或会员手机号）');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
      _result = null;
    });
    try {
      final result = await widget.repository.evaluateEligibility(
        customerId: customerId,
        orderAmount: double.tryParse(_orderAmount.text.trim()),
      );
      if (!mounted) return;
      setState(() {
        _busy = false;
        _result = result;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = '$error';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return SettingsPagePadding(
      child: SettingsPanel(
        title: '首单资格评估',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              '输入客户标识与订单金额试算首单资格：店内生效活动、无已核销记录、无历史已完成订单且金额达门槛。',
              style: TextStyle(fontSize: 13, color: Color(0xff667085)),
            ),
            const SizedBox(height: 16),
            SettingsField(
              label: '客户标识（openid / 手机号）',
              value: _customerId.text,
              onChanged: (value) => _customerId.text = value,
            ),
            const SizedBox(height: 12),
            SettingsField(
              label: '订单金额（元，可空）',
              value: _orderAmount.text,
              onChanged: (value) => _orderAmount.text = value,
            ),
            const SizedBox(height: 16),
            SettingsPrimaryButton(
              key: const Key('marketing-eligibility-evaluate'),
              label: '开始评估',
              loading: _busy,
              onPressed: _evaluate,
            ),
            if (_error != null) ...[
              const SizedBox(height: 14),
              Text(
                _error!,
                style: TextStyle(color: context.cashier.danger)),
            ],
            if (_result != null) ...[
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: _result!.eligible
                      ? context.cashier.successBackground
                      : context.cashier.warningBackground,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        SettingsStatusBadge(
                          label: _result!.eligible ? '符合首单资格' : '不符合首单资格',
                          type: _result!.eligible
                              ? StatusBadgeType.success
                              : StatusBadgeType.warning,
                        ),
                      ],
                    ),
                    if (_result!.reason != null &&
                        _result!.reason!.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Text('原因：${_result!.reason}'),
                    ],
                    if (_result!.conflicts.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Text('互斥项：${_result!.conflicts.join('、')}'),
                    ],
                    if (_result!.campaignName != null &&
                        _result!.campaignName!.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Text('命中活动：${_result!.campaignName}'),
                    ],
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _InviteRewardSection extends StatefulWidget {
  const _InviteRewardSection({required this.repository, this.onDirtyChanged});

  final MarketingRepository repository;
  final ValueChanged<bool>? onDirtyChanged;

  @override
  State<_InviteRewardSection> createState() => _InviteRewardSectionState();
}

class _InviteRewardSectionState extends State<_InviteRewardSection> {
  MarketingInviteReward? _value;
  var _enabled = false;
  final _percent = TextEditingController();
  var _busy = false;
  var _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final value = await widget.repository.loadInviteReward();
      if (!mounted) return;
      setState(() {
        _value = value;
        _enabled = value.enabled;
        _percent.text = value.rewardPercent.toStringAsFixed(1);
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = error);
    }
  }

  Future<void> _save() async {
    final percent = double.tryParse(_percent.text.trim());
    if (percent == null || percent < 0 || percent > 100) {
      setState(() => _error = '返利比例需为 0～100 的数字');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final saved = await widget.repository.saveInviteReward(
        enabled: _enabled,
        rewardPercent: percent,
      );
      if (!mounted) return;
      setState(() {
        _busy = false;
        _value = saved;
      });
      showSettingsSaved(context, '首单返利规则已保存');
      widget.onDirtyChanged?.call(false);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = error;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return SettingsPagePadding(
      child: SettingsPanel(
        title: '邀请首单返利',
        child: _error != null && _value == null
            ? SettingsErrorState(message: '加载失败：$_error', onRetry: _load)
            : _value == null
            ? const SettingsSkeletonLoader(rows: 2)
            : Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SwitchListTile(
                    key: const Key('marketing-invite-reward-enabled'),
                    contentPadding: EdgeInsets.zero,
                    title: const Text('启用首单余额返利'),
                    subtitle: const Text(
                      '关闭后不再发放邀请首单返利',
                      style: TextStyle(fontSize: 12),
                    ),
                    value: _enabled,
                    onChanged: _busy
                        ? null
                        : (value) {
                            setState(() => _enabled = value);
                            widget.onDirtyChanged?.call(true);
                          },
                  ),
                  const SizedBox(height: 12),
                  SettingsField(
                    label: '返利比例（%，按实付金额）',
                    value: _percent.text,
                    onChanged: (value) {
                      _percent.text = value;
                      widget.onDirtyChanged?.call(true);
                    },
                  ),
                  const SizedBox(height: 16),
                  SettingsPrimaryButton(
                    key: const Key('marketing-invite-reward-save'),
                    label: '保存',
                    loading: _busy,
                    onPressed: _save,
                  ),
                ],
              ),
      ),
    );
  }
}

class _InvitePosterSection extends StatefulWidget {
  const _InvitePosterSection({required this.repository, this.onDirtyChanged});

  final MarketingRepository repository;
  final ValueChanged<bool>? onDirtyChanged;

  @override
  State<_InvitePosterSection> createState() => _InvitePosterSectionState();
}

class _InvitePosterSectionState extends State<_InvitePosterSection> {
  final _backgroundPath = TextEditingController();
  final _qrX = TextEditingController();
  final _qrY = TextEditingController();
  final _qrSize = TextEditingController();
  var _busy = false;
  var _error;
  var _loaded = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final poster = await widget.repository.loadInvitePoster();
      if (!mounted) return;
      setState(() {
        _backgroundPath.text = poster.backgroundPath;
        _qrX.text = '${poster.qrX}';
        _qrY.text = '${poster.qrY}';
        _qrSize.text = '${poster.qrSize}';
        _loaded = true;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = error);
    }
  }

  Future<void> _save() async {
    final qrX = int.tryParse(_qrX.text.trim());
    final qrY = int.tryParse(_qrY.text.trim());
    final qrSize = int.tryParse(_qrSize.text.trim());
    if (qrX == null || qrY == null || qrSize == null) {
      setState(() => _error = '二维码坐标与尺寸需为整数');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.repository.saveInvitePoster(
        backgroundPath: _backgroundPath.text.trim(),
        qrX: qrX,
        qrY: qrY,
        qrSize: qrSize,
      );
      if (!mounted) return;
      setState(() => _busy = false);
      showSettingsSaved(context, '邀请海报配置已保存');
      widget.onDirtyChanged?.call(false);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = error;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return SettingsPagePadding(
      child: SettingsPanel(
        title: '邀请海报',
        child: !_loaded && _error == null
            ? const SettingsSkeletonLoader(rows: 2)
            : _error != null && !_loaded
            ? SettingsErrorState(message: '加载失败：$_error', onRetry: _load)
            : Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SettingsField(
                    label: '背景图路径（本地绝对路径或 URL）',
                    value: _backgroundPath.text,
                    onChanged: (value) {
                      _backgroundPath.text = value;
                      widget.onDirtyChanged?.call(true);
                    },
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: SettingsField(
                          label: '二维码 X',
                          value: _qrX.text,
                          onChanged: (value) {
                            _qrX.text = value;
                            widget.onDirtyChanged?.call(true);
                          },
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: SettingsField(
                          label: '二维码 Y',
                          value: _qrY.text,
                          onChanged: (value) {
                            _qrY.text = value;
                            widget.onDirtyChanged?.call(true);
                          },
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: SettingsField(
                          label: '二维码尺寸',
                          value: _qrSize.text,
                          onChanged: (value) {
                            _qrSize.text = value;
                            widget.onDirtyChanged?.call(true);
                          },
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  SettingsPrimaryButton(
                    key: const Key('marketing-invite-poster-save'),
                    label: '保存',
                    loading: _busy,
                    onPressed: _save,
                  ),
                ],
              ),
      ),
    );
  }
}

class _NinefoldSection extends StatefulWidget {
  const _NinefoldSection({required this.repository, required this.canWrite,
    this.onDirtyChanged,
  });

  final MarketingRepository repository;
  final bool canWrite;
  final ValueChanged<bool>? onDirtyChanged;

  @override
  State<_NinefoldSection> createState() => _NinefoldSectionState();
}

class _NinefoldSectionState extends State<_NinefoldSection> {
  MarketingNinefoldConfig? _value;
  var _enabled = false;
  final _payRate = TextEditingController();
  final _minBaseYuan = TextEditingController();
  final _timeStart = TextEditingController();
  final _timeEnd = TextEditingController();
  final _zoneId = TextEditingController();
  final _diningTypes = <String>{};
  var _busy = false;
  var _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final value = await widget.repository.loadNinefold();
      if (!mounted) return;
      setState(() {
        _value = value;
        _enabled = value.enabled;
        _payRate.text = value.payRate.toStringAsFixed(2);
        _minBaseYuan.text = value.minBaseYuan.toStringAsFixed(2);
        _timeStart.text = value.timeStart;
        _timeEnd.text = value.timeEnd;
        _zoneId.text = value.zoneId;
        _diningTypes
          ..clear()
          ..addAll(value.eligibleDiningTypes);
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = error);
    }
  }

  Future<void> _save() async {
    final payRate = double.tryParse(_payRate.text.trim());
    final minBaseYuan = double.tryParse(_minBaseYuan.text.trim());
    if (payRate == null || minBaseYuan == null) {
      setState(() => _error = '支付倍率与门槛金额需为数字');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.repository.saveNinefold(
        MarketingNinefoldConfig(
          enabled: _enabled,
          payRate: payRate,
          minBaseYuan: minBaseYuan,
          timeStart: _timeStart.text.trim(),
          timeEnd: _timeEnd.text.trim(),
          zoneId: _zoneId.text.trim(),
          eligibleDiningTypes: _diningTypes.toList()..sort(),
        ),
      );
      if (!mounted) return;
      setState(() => _busy = false);
      showSettingsSaved(context, '夜间九折配置已保存');
      widget.onDirtyChanged?.call(false);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = error;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return SettingsPagePadding(
      child: SettingsPanel(
        title: '夜间九折',
        child: _error != null && _value == null
            ? SettingsErrorState(message: '加载失败：$_error', onRetry: _load)
            : _value == null
            ? const SettingsSkeletonLoader(rows: 2)
            : Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SwitchListTile(
                    key: const Key('marketing-ninefold-enabled'),
                    contentPadding: EdgeInsets.zero,
                    title: const Text('启用夜间九折'),
                    subtitle: Text(
                      _value!.hasOwnConfig
                          ? '本店独立配置'
                          : _value!.inheritsGlobal
                          ? '继承全店默认配置'
                          : '独立配置',
                      style: const TextStyle(fontSize: 12),
                    ),
                    value: _enabled,
                    onChanged: widget.canWrite && !_busy
                        ? (value) {
                            setState(() => _enabled = value);
                            widget.onDirtyChanged?.call(true);
                          }
                        : null,
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: SettingsField(
                          label: '支付倍率（如 0.9）',
                          value: _payRate.text,
                          onChanged: (value) {
                            _payRate.text = value;
                            widget.onDirtyChanged?.call(true);
                          },
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: SettingsField(
                          label: '门槛金额（元）',
                          value: _minBaseYuan.text,
                          onChanged: (value) {
                            _minBaseYuan.text = value;
                            widget.onDirtyChanged?.call(true);
                          },
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: SettingsField(
                          label: '开始时间（如 00:30）',
                          value: _timeStart.text,
                          onChanged: (value) {
                            _timeStart.text = value;
                            widget.onDirtyChanged?.call(true);
                          },
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: SettingsField(
                          label: '结束时间（如 03:00）',
                          value: _timeEnd.text,
                          onChanged: (value) {
                            _timeEnd.text = value;
                            widget.onDirtyChanged?.call(true);
                          },
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  SettingsField(
                    label: '时区（如 Asia/Shanghai）',
                    value: _zoneId.text,
                    onChanged: (value) {
                      _zoneId.text = value;
                      widget.onDirtyChanged?.call(true);
                    },
                  ),
                  const SizedBox(height: 12),
                  Text(
                    '适用就餐方式',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: context.cashier.inkSecondary,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 8,
                    children: [
                      for (final type in const ['堂食', '打包', '外卖'])
                        FilterChip(
                          key: Key('marketing-ninefold-type-$type'),
                          label: Text(type),
                          selected: _diningTypes.contains(type),
                          onSelected: widget.canWrite && !_busy
                              ? (selected) => setState(() {
                                  widget.onDirtyChanged?.call(true);
                                  if (selected) {
                                      _diningTypes.add(type);
                                    } else {
                                      _diningTypes.remove(type);
                                    }
                                  })
                              : null,
                        ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  SettingsPrimaryButton(
                    key: const Key('marketing-ninefold-save'),
                    label: '保存',
                    loading: _busy,
                    onPressed: widget.canWrite ? _save : null,
                  ),
                  if (!widget.canWrite)
                    const Padding(
                      padding: EdgeInsets.only(top: 10),
                      child: Text(
                        '当前账号无支付/营销配置写权限，仅可查看。',
                        style: TextStyle(fontSize: 12, color: Color(0xff667085),
                        ),
                      ),
                    ),
                ],
              ),
      ),
    );
  }
}

/// 轮播图分区（列表/新增/删除；openapi 无更新端点，改动经删除重建）。
class _BannersSection extends StatefulWidget {
  const _BannersSection({
    required this.repository,
    required this.canWrite});

  final MarketingRepository repository;
  final bool canWrite;

  @override
  State<_BannersSection> createState() => _BannersSectionState();
}

class _BannersSectionState extends State<_BannersSection> {
  late Future<List<MarketingBanner>> _future;
  String _tab = 'banners';

  @override
  void initState() {
    super.initState();
    _future = widget.repository.listBanners();
  }

  void _reload() => setState(() {
        _future = widget.repository.listBanners();
      });

  Future<void> _openForm({MarketingBanner? initial}) async {
    final saved = await showBannerFormDrawer(
      context,
      widget.repository,
      initial: initial,
    );
    if (saved == null || !mounted) return;
    try {
      if (initial == null) {
        await widget.repository.addBanner(saved);
        if (!mounted) return;
        showSettingsSaved(context, '轮播图已新增');
      } else {
        await widget.repository.updateBanner(saved);
        if (!mounted) return;
        showSettingsSaved(context, '轮播图已更新');
      }
      _reload();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context,
      ).showSnackBar(
        SnackBar(content: Text('保存失败：$error')));
    }
  }

  Future<void> _deleteBanner(MarketingBanner banner) async {
    final confirmed = await showSettingsConfirmDialog(
      context: context,
      title: '删除轮播图',
      message: '删除 #${banner.id}（${banner.image ?? '无图片'}）？删除后不可恢复。',
      destructive: true,
      confirmLabel: '删除',
    );
    if (confirmed != true || !mounted) return;
    try {
      await widget.repository.deleteBanner(id: banner.id);
      if (!mounted) return;
      showSettingsSaved(context, '轮播图已删除');
      _reload();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context,
      ).showSnackBar(
        SnackBar(content: Text('删除失败：$error')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return SettingsPagePadding(
      child: SettingsPanel(
        title: '轮播图',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: SegmentedButton<String>(
                key: const Key('marketing-banner-tabs'),
                segments: const [
                  ButtonSegment(
                    value: 'banners',
                    label: Text('轮播图'),
                    icon: Icon(Icons.view_carousel_outlined, size: 16),
                  ),
                  ButtonSegment(
                    value: 'popups',
                    label: Text('弹窗广告'),
                    icon: Icon(Icons.campaign_outlined, size: 16),
                  ),
                ],
                selected: {_tab},
                onSelectionChanged: (selection) {
                  setState(() => _tab = selection.first);
                },
              ),
            ),
            const SizedBox(height: 12),
            if (_tab == 'banners') _buildBanners(context) else _PopupsTab(repository: widget.repository, canWrite: widget.canWrite,
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildBanners(BuildContext context) {
    return FutureBuilder<List<MarketingBanner>>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return SettingsErrorState(
            message: '加载轮播图失败：${snapshot.error}',
            onRetry: _reload,
          );
        }
        if (!snapshot.hasData) {
          return const SettingsSkeletonLoader(rows: 3);
        }
        final banners = snapshot.data!;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                key: const Key('marketing-banner-create'),
                onPressed: widget.canWrite ? _openForm : null,
                icon: const Icon(Icons.add_circle_outline, size: 18),
                label: const Text('新增轮播图'),
              ),
            ),
            const SizedBox(height: 10),
            if (banners.isEmpty)
              const SettingsEmptyState(
                title: '暂无轮播图',
                description: '新增首页/底部轮播图用于小程序展示；'
                    'openapi 无更新端点，改动经删除重建。',
              )
            else
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Table(
                  columnWidths: const {
                    0: FixedColumnWidth(110),
                    1: FixedColumnWidth(230),
                    2: FixedColumnWidth(90),
                    3: FixedColumnWidth(240),
                    4: FixedColumnWidth(90),
                    5: FixedColumnWidth(210),
                  },
                  defaultVerticalAlignment:
                      TableCellVerticalAlignment.middle,
                  children: [
                    TableRow(
                      decoration: const BoxDecoration(
                        color: Color(0xfffafafa)),
                      children: [
                        _tableHeader(context, '预览'),
                        _tableHeader(context, '图片信息'),
                        _tableHeader(context, '类型'),
                        _tableHeader(context, '跳转'),
                        _tableHeader(context, '状态'),
                        _tableHeader(context, '操作'),
                      ],
                    ),
                    for (final banner in banners)
                      _bannerTableRow(context, banner),
                  ],
                ),
              ),
            if (!widget.canWrite)
              const Padding(
                padding: EdgeInsets.only(top: 10),
                child: Text(
                  '当前账号无轮播图管理权限（banner:manage），仅可查看。',
                  style: TextStyle(fontSize: 12, color: Color(0xff667085)),
                ),
              ),
          ],
        );
      },
    );
  }

  Widget _bannerThumb(MarketingBanner banner) {
    final image = banner.image;
    if (image == null || image.trim().isEmpty) {
      return Container(
        width: 84,
        height: 48,
        decoration: BoxDecoration(
          color: const Color(0xfff2f4f7),
          borderRadius: BorderRadius.circular(6),
        ),
        child: const Icon(
          Icons.image_outlined,
          size: 22,
          color: Color(0xff98a2b3),
        ),
      );
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(6),
      child: Image.network(
        image,
        width: 84,
        height: 48,
        fit: BoxFit.cover,
        errorBuilder: (context, error, stack) => Container(
          width: 84,
          height: 48,
          decoration: BoxDecoration(
            color: const Color(0xfff2f4f7),
            borderRadius: BorderRadius.circular(6),
          ),
          child: const Icon(
            Icons.broken_image_outlined,
            size: 22,
            color: Color(0xff98a2b3),
          ),
        ),
      ),
    );
  }

  TableRow _bannerTableRow(BuildContext context, MarketingBanner banner) {
    final enabled = banner.status == 1;
    Widget cell(Widget child) => Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: child,
    );
    return TableRow(
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: Color(0xfff1f1f1))),
      ),
      children: [
        cell(_bannerThumb(banner)),
        cell(Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              banner.image ?? '未设置图片',
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 2),
            Text(
              '#${banner.id}',
              style: TextStyle(
                fontSize: 12,
                color: context.cashier.inkMuted),
            ),
          ],
        ),
        ),
        cell(Text(banner.type == 'bottom' ? '底部' : '首页')),
        cell(Text(
          banner.url == null || banner.url!.isEmpty
              ? '无跳转链接'
              : banner.url!,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(fontSize: 12, color: context.cashier.inkMuted),
        ),
        ),
        cell(FittedBox(
          fit: BoxFit.scaleDown,
          child: SettingsStatusBadge(
            label: enabled ? '启用' : '禁用',
            type: enabled
                ? StatusBadgeType.success
                : StatusBadgeType.neutral,
          ),
        ),
        ),
        cell(Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextButton.icon(
                  key: Key('marketing-banner-toggle-${banner.id}'),
                  onPressed: widget.canWrite
                      ? () => _toggleBanner(banner)
                      : null,
                  icon: Icon(
                    enabled ? Icons.pause_circle_outline : Icons.play_circle_outline,
                    size: 15,
                    color: enabled ? context.cashier.warning : context.cashier.success,
                  ),
                  label: Text(
                    enabled ? '禁用' : '启用',
                    style: TextStyle(
                      color: enabled
                          ? context.cashier.warning
                          : context.cashier.success,
                    ),
                  ),
                ),
                TextButton.icon(
                  key: Key('marketing-banner-edit-${banner.id}'),
                  onPressed: widget.canWrite
                      ? () => _openForm(initial: banner)
                      : null,
                  icon: Icon(
                    Icons.edit_outlined,
                    size: 15,
                    color: context.cashier.inkSecondary,
                  ),
                  label: Text(
                    '编辑',
                    style: TextStyle(color: context.cashier.inkSecondary),
                  ),
                ),
              ],
            ),
            TextButton.icon(
              key: Key('marketing-banner-delete-${banner.id}'),
              onPressed: widget.canWrite
                  ? () => _deleteBanner(banner)
                  : null,
              icon: Icon(
                Icons.delete_outline,
                size: 15,
                color: context.cashier.danger,
              ),
              label: Text(
                '删除',
                style: TextStyle(color: context.cashier.danger),
              ),
            ),
          ],
        ),
        ),
      ],
    );
  }

  Future<void> _toggleBanner(MarketingBanner banner) async {
    final enabled = banner.status == 1;
    final confirmed = await showSettingsConfirmDialog(
      context: context,
      title: enabled ? '禁用轮播图' : '启用轮播图',
      message: enabled
          ? '禁用 #${banner.id}？禁用后小程序首页不再展示该轮播图。'
          : '启用 #${banner.id}？启用后小程序首页展示该轮播图。',
      destructive: enabled,
      confirmLabel: enabled ? '禁用' : '启用',
    );
    if (confirmed != true || !mounted) return;
    try {
      await widget.repository.updateBanner(
        MarketingBanner(
          id: banner.id,
          image: banner.image,
          url: banner.url,
          status: enabled ? 0 : 1,
          type: banner.type,
        ),
      );
      if (!mounted) return;
      showSettingsSaved(context, enabled ? '轮播图已禁用' : '轮播图已启用');
      _reload();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context,
      ).showSnackBar(
        SnackBar(content: Text('状态更新失败：$error')));
    }
  }
}

/// 新增轮播图表单抽屉（字段 Key 与既有测试兼容）。
Future<MarketingBanner?> showBannerFormDrawer(
  BuildContext context,
  MarketingRepository repository, {
  MarketingBanner? initial,
}) {
  return showGeneralDialog<MarketingBanner>(
    context: context,
    barrierDismissible: true,
    barrierLabel: '关闭',
    barrierColor: const Color(0x590f172a),
    transitionDuration: const Duration(milliseconds: 220),
    pageBuilder: (context, _, __) => Align(
      alignment: Alignment.centerRight,
      child: Material(
        color: context.cashier.surface,
        borderRadius: const BorderRadius.horizontal(
          left: Radius.circular(12)),
        clipBehavior: Clip.antiAlias,
        child: SizedBox(
          width: 520,
          height: double.infinity,
          child: _BannerFormDrawer(repository: repository, initial: initial),
        ),
      ),
    ),
    transitionBuilder: (context, animation, secondary, child) =>
        SlideTransition(
          position: Tween(begin: const Offset(1, 0), end: Offset.zero,
          ).animate(
            CurvedAnimation(parent: animation, curve: Curves.easeOut)),
          child: child,
        ),
  );
}

/// 新增/编辑弹窗广告表单抽屉（字段 Key 与既有测试兼容）。
Future<MarketingPopup?> showPopupFormDrawer(
  BuildContext context,
  MarketingRepository repository,
  MarketingPopup? initial,
) {
  return showGeneralDialog<MarketingPopup>(
    context: context,
    barrierDismissible: true,
    barrierLabel: '关闭',
    barrierColor: const Color(0x590f172a),
    transitionDuration: const Duration(milliseconds: 220),
    pageBuilder: (context, _, __) => Align(
      alignment: Alignment.centerRight,
      child: Material(
        color: context.cashier.surface,
        borderRadius: const BorderRadius.horizontal(
          left: Radius.circular(12)),
        clipBehavior: Clip.antiAlias,
        child: SizedBox(
          width: 520,
          height: double.infinity,
          child: _PopupFormDrawer(repository: repository, initial: initial),
        ),
      ),
    ),
    transitionBuilder: (context, animation, secondary, child) =>
        SlideTransition(
          position: Tween(begin: const Offset(1, 0), end: Offset.zero,
          ).animate(
            CurvedAnimation(parent: animation, curve: Curves.easeOut)),
          child: child,
        ),
  );
}

/// 新增/编辑轮播图表单（抽屉形态，右侧滑出）。
class _BannerFormDrawer extends StatefulWidget {
  const _BannerFormDrawer({required this.repository, this.initial});

  final MarketingRepository repository;
  final MarketingBanner? initial;

  @override
  State<_BannerFormDrawer> createState() => _BannerFormDrawerState();
}

class _BannerFormDrawerState extends State<_BannerFormDrawer> {
  final _image = TextEditingController();
  final _url = TextEditingController();
  bool _enabled = true;
  String _type = 'home';
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    final initial = widget.initial;
    if (initial != null) {
      _image.text = initial.image ?? '';
      _url.text = initial.url ?? '';
      _type = initial.type;
      _enabled = initial.status == 1;
    }
  }

  @override
  void dispose() {
    _image.dispose();
    _url.dispose();
    super.dispose();
  }

  Future<void> _uploadImage() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.image,
        withData: true,
      );
      if (result == null || result.files.isEmpty || !mounted) return;
      final file = result.files.single;
      final bytes = file.bytes;
      if (bytes == null || bytes.isEmpty) {
        if (!mounted) return;
        ScaffoldMessenger.of(context,
        ).showSnackBar(
          const SnackBar(content: Text('无法读取所选图片，请重试')));
        return;
      }
      if (_busy) return;
      setState(() => _busy = true);
      final path = await widget.repository.uploadBannerImage(
        bytes: bytes,
        filename: file.name,
      );
      if (!mounted) return;
      setState(() {
        _busy = false;
        _image.text = path;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.of(context,
      ).showSnackBar(
        SnackBar(content: Text('图片上传失败：$error')));
    }
  }

  void _submit() {
    final image = _image.text.trim();
    if (image.isEmpty) {
      ScaffoldMessenger.of(context,
      ).showSnackBar(
        const SnackBar(content: Text('图片地址不能为空')));
      return;
    }
    if (_busy) return;
    setState(() => _busy = true);
    Navigator.of(context).pop(
      MarketingBanner(
        id: widget.initial?.id ?? 0,
        image: image,
        url: _url.text.trim().isEmpty ? null : _url.text.trim(),
        status: _enabled ? 1 : 0,
        type: _type,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 12, 16),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  widget.initial == null ? '新增轮播图' : '编辑轮播图',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              IconButton(
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(Icons.close),
                tooltip: '关闭',
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SettingsField(
                  label: '图片地址（必填，支持 http/https 或上传回填）',
                  value: _image.text,
                  onChanged: (value) => _image.text = value,
                ),
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    key: const Key('marketing-banner-upload'),
                    onPressed: _busy ? null : _uploadImage,
                    icon: const Icon(Icons.upload_file_outlined, size: 18),
                    label: Text(_busy ? '上传中…' : '上传图片'),
                  ),
                ),
                const SizedBox(height: 12),
                SettingsField(
                  label: '跳转链接（可选，http/https）',
                  value: _url.text,
                  onChanged: (value) => _url.text = value,
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  key: const Key('marketing-banner-type'),
                  initialValue: _type,
                  decoration: const InputDecoration(
                    labelText: '展示位置',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  items: const [
                    DropdownMenuItem(value: 'home', child: Text('首页')),
                    DropdownMenuItem(value: 'bottom', child: Text('底部')),
                  ],
                  onChanged: _busy
                      ? null
                      : (value) {
                          if (value != null) {
                            setState(() => _type = value);
                          }
                        },
                ),
                const SizedBox(height: 12),
                SwitchListTile(
                  key: const Key('marketing-banner-enabled'),
                  contentPadding: EdgeInsets.zero,
                  title: const Text('启用'),
                  value: _enabled,
                  onChanged: _busy
                      ? null
                      : (value) => setState(() => _enabled = value),
                ),
              ],
            ),
          ),
        ),
        const Divider(height: 1),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('取消'),
              ),
              TextButton(
                key: const Key('marketing-banner-submit'),
                onPressed: _submit,
                child: Text(widget.initial == null ? '新增' : '保存'),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

const _popupTypeLabels = <String, String>{
  'home_top': '首页顶部',
  'home_bottom': '首页底部',
  'page_banner': '页面横幅',
  'page_hor': '横向横幅',
  'page_activity': '活动页',
};

const _popupTargetLabels = <String, String>{
  'new': '新客',
  'member': '会员',
  'all': '全部用户',
};

/// 弹窗广告 Tab（banner:manage 权限体系，服务端 /activity/* 端点）。
class _PopupsTab extends StatefulWidget {
  const _PopupsTab({
    required this.repository,
    required this.canWrite});

  final MarketingRepository repository;
  final bool canWrite;

  @override
  State<_PopupsTab> createState() => _PopupsTabState();
}

class _PopupsTabState extends State<_PopupsTab> {
  late Future<List<MarketingPopup>> _future;

  @override
  void initState() {
    super.initState();
    _future = widget.repository.listPopups();
  }

  void _reload() => setState(() {
        _future = widget.repository.listPopups();
      });

  Future<void> _openForm(MarketingPopup? existing) async {
    final saved = await showPopupFormDrawer(
      context,
      widget.repository,
      existing,
    );
    if (saved == null || !mounted) return;
    try {
      if (existing == null) {
        await widget.repository.addPopup(saved);
        if (!mounted) return;
        showSettingsSaved(context, '弹窗广告已新增');
      } else {
        await widget.repository.updatePopup(saved);
        if (!mounted) return;
        showSettingsSaved(context, '弹窗广告已更新');
      }
      _reload();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context,
      ).showSnackBar(
        SnackBar(content: Text('保存失败：$error')));
    }
  }

  Future<void> _deletePopup(MarketingPopup popup) async {
    final confirmed = await showSettingsConfirmDialog(
      context: context,
      title: '删除弹窗广告',
      message: '删除「${popup.name ?? '未命名'}」（#${popup.id}）？'
          '删除后不可恢复。',
      destructive: true,
      confirmLabel: '删除',
    );
    if (confirmed != true || !mounted) return;
    try {
      await widget.repository.deletePopup(id: popup.id!);
      if (!mounted) return;
      showSettingsSaved(context, '弹窗广告已删除');
      _reload();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context,
      ).showSnackBar(
        SnackBar(content: Text('删除失败：$error')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<MarketingPopup>>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return SettingsErrorState(
            message: '加载弹窗广告失败：${snapshot.error}',
            onRetry: _reload,
          );
        }
        if (!snapshot.hasData) {
          return const SettingsSkeletonLoader(rows: 3);
        }
        final popups = snapshot.data!;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                key: const Key('marketing-popup-create'),
                onPressed: widget.canWrite ? () => _openForm(null) : null,
                icon: const Icon(Icons.add_circle_outline, size: 18),
                label: const Text('新增弹窗'),
              ),
            ),
            const SizedBox(height: 10),
            if (popups.isEmpty)
              const SettingsEmptyState(
                title: '暂无弹窗广告',
                description: '弹窗广告按门店展示，可设置目标用户与投放时段。',
              )
            else
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Table(
                  columnWidths: const {
                    0: FixedColumnWidth(180),
                    1: FixedColumnWidth(220),
                    2: FixedColumnWidth(110),
                    3: FixedColumnWidth(110),
                    4: FixedColumnWidth(90),
                    5: FixedColumnWidth(240),
                    6: FixedColumnWidth(190),
                  },
                  defaultVerticalAlignment:
                      TableCellVerticalAlignment.middle,
                  children: [
                    TableRow(
                      decoration: const BoxDecoration(
                        color: Color(0xfffafafa)),
                      children: [
                        _tableHeader(context, '名称'),
                        _tableHeader(context, '图片'),
                        _tableHeader(context, '投放位置'),
                        _tableHeader(context, '目标用户'),
                        _tableHeader(context, '状态'),
                        _tableHeader(context, '有效期'),
                        _tableHeader(context, '操作'),
                      ],
                    ),
                    for (final popup in popups)
                      _popupTableRow(context, popup),
                  ],
                ),
              ),
            if (!widget.canWrite)
              const Padding(
                padding: EdgeInsets.only(top: 10),
                child: Text(
                  '当前账号无弹窗广告管理权限（banner:manage），仅可查看。',
                  style: TextStyle(fontSize: 12, color: Color(0xff667085)),
                ),
              ),
          ],
        );
      },
    );
  }

  Widget _popupThumb(MarketingPopup popup) {
    final image = popup.popupImage ?? popup.imageUrl;
    if (image == null || image.trim().isEmpty) {
      return Container(
        width: 84,
        height: 48,
        decoration: BoxDecoration(
          color: const Color(0xfff2f4f7),
          borderRadius: BorderRadius.circular(6),
        ),
        child: const Icon(
          Icons.image_outlined,
          size: 22,
          color: Color(0xff98a2b3),
        ),
      );
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(6),
      child: Image.network(
        image,
        width: 84,
        height: 48,
        fit: BoxFit.cover,
        errorBuilder: (context, error, stack) => Container(
          width: 84,
          height: 48,
          decoration: BoxDecoration(
            color: const Color(0xfff2f4f7),
            borderRadius: BorderRadius.circular(6),
          ),
          child: const Icon(
            Icons.broken_image_outlined,
            size: 22,
            color: Color(0xff98a2b3),
          ),
        ),
      ),
    );
  }

  TableRow _popupTableRow(BuildContext context, MarketingPopup popup) {
    final enabled = popup.isEnabled == 1;
    final typeLabel =
        _popupTypeLabels[popup.type] ?? (popup.type ?? '未设置位置');
    Widget cell(Widget child) => Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: child,
    );
    return TableRow(
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: Color(0xfff1f1f1))),
      ),
      children: [
        cell(Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              popup.name ?? '未命名弹窗',
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              '#${popup.id}',
              style: TextStyle(
                fontSize: 12,
                color: context.cashier.inkMuted),
            ),
          ],
        ),
        ),
        cell(_popupThumb(popup)),
        cell(Text(typeLabel)),
        cell(Text(
          _popupTargetLabels[popup.targetUser] ??
              (popup.targetUser ?? '全部'),
        ),
        ),
        cell(FittedBox(
          fit: BoxFit.scaleDown,
          child: SettingsStatusBadge(
            label: enabled ? '启用' : '禁用',
            type: enabled
                ? StatusBadgeType.success
                : StatusBadgeType.neutral,
          ),
        ),
        ),
        cell(Text(
          '${popup.startTime ?? '-'} ~ ${popup.endTime ?? '-'}\n'
          '每日上限 ${popup.maxShowCount ?? 0} 次 · 门店 '
          '${popup.applyShopIds == null || popup.applyShopIds!.trim().isEmpty ? '全部' : popup.applyShopIds}',
          style: TextStyle(
            fontSize: 12,
            color: context.cashier.inkMuted,
            height: 1.4,
          ),
        ),
        ),
        cell(Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextButton.icon(
              key: Key('marketing-popup-edit-${popup.id}'),
              onPressed: widget.canWrite
                  ? () async {
                      MarketingPopup detail;
                      try {
                        detail = await widget.repository
                            .loadPopupDetail(id: popup.id!,
                          );
                      } catch (_) {
                        detail = popup;
                      }
                      if (!mounted) return;
                      await _openForm(detail);
                    }
                  : null,
              icon: const Icon(Icons.edit_outlined, size: 15),
              label: const Text('编辑'),
            ),
            TextButton.icon(
              key: Key('marketing-popup-delete-${popup.id}'),
              onPressed:
                  widget.canWrite ? () => _deletePopup(popup) : null,
              icon: Icon(
                Icons.delete_outline,
                size: 15,
                color: context.cashier.danger,
              ),
              label: Text(
                '删除',
                style: TextStyle(color: context.cashier.danger),
              ),
            ),
          ],
        ),
        ),
      ],
    );
  }
}

/// 新增/编辑弹窗广告共用表单（抽屉形态，右侧滑出）。
class _PopupFormDrawer extends StatefulWidget {
  const _PopupFormDrawer({
    required this.repository,
    this.initial});

  final MarketingRepository repository;
  final MarketingPopup? initial;

  @override
  State<_PopupFormDrawer> createState() => _PopupFormDrawerState();
}

class _PopupFormDrawerState extends State<_PopupFormDrawer> {
  late final TextEditingController _name;
  late final TextEditingController _image;
  late final TextEditingController _url;
  late final TextEditingController _startTime;
  late final TextEditingController _endTime;
  late final TextEditingController _maxShowCount;
  late final TextEditingController _sorting;
  late final TextEditingController _shopIds;
  late String _targetUser;
  late String _type;
  late bool _enabled;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    final initial = widget.initial;
    _name = TextEditingController(text: initial?.name ?? '');
    _image = TextEditingController(text: initial?.popupImage ?? '');
    _url = TextEditingController(text: initial?.imageUrl ?? '');
    _startTime = TextEditingController(text: initial?.startTime ?? '');
    _endTime = TextEditingController(text: initial?.endTime ?? '');
    _maxShowCount = TextEditingController(
      text: initial?.maxShowCount == null ? '0' : '${initial!.maxShowCount}',
    );
    _sorting = TextEditingController(
      text: initial?.sorting == null ? '0' : '${initial!.sorting}',
    );
    _shopIds = TextEditingController(
      text: _shopIdsText(initial?.applyShopIds));
    _targetUser = initial?.targetUser ?? 'all';
    _type = initial?.type ?? 'page_banner';
    _enabled = initial == null || initial.isEnabled == 1;
  }

  static String _shopIdsText(String? jsonList) {
    if (jsonList == null || jsonList.trim().isEmpty) return '';
    final cleaned = jsonList.replaceAll('[', '').replaceAll(']', '');
    return cleaned.trim();
  }

  @override
  void dispose() {
    _name.dispose();
    _image.dispose();
    _url.dispose();
    _startTime.dispose();
    _endTime.dispose();
    _maxShowCount.dispose();
    _sorting.dispose();
    _shopIds.dispose();
    super.dispose();
  }

  Future<void> _uploadImage() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.image,
        withData: true,
      );
      if (result == null || result.files.isEmpty || !mounted) return;
      final file = result.files.single;
      final bytes = file.bytes;
      if (bytes == null || bytes.isEmpty) {
        if (!mounted) return;
        ScaffoldMessenger.of(context,
        ).showSnackBar(
          const SnackBar(content: Text('无法读取所选图片，请重试')));
        return;
      }
      if (_busy) return;
      setState(() => _busy = true);
      final path = await widget.repository.uploadBannerImage(
        bytes: bytes,
        filename: file.name,
      );
      if (!mounted) return;
      setState(() {
        _busy = false;
        _image.text = path;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.of(context,
      ).showSnackBar(
        SnackBar(content: Text('图片上传失败：$error')));
    }
  }

  void _submit() {
    final name = _name.text.trim();
    final image = _image.text.trim();
    final startTime = _startTime.text.trim();
    final endTime = _endTime.text.trim();
    if (name.isEmpty || image.isEmpty) {
      ScaffoldMessenger.of(context,
      ).showSnackBar(
        const SnackBar(content: Text('弹窗名称与图片不能为空')));
      return;
    }
    if (startTime.isEmpty || endTime.isEmpty) {
      ScaffoldMessenger.of(context,
      ).showSnackBar(
        const SnackBar(content: Text('开始/结束时间不能为空')));
      return;
    }
    if (_busy) return;
    final shopIdsRaw = _shopIds.text.trim();
    final applyShopIds = shopIdsRaw.isEmpty
        ? null
        : '[${shopIdsRaw.split(RegExp(r'[,，\s]+')).where((s) => s.isNotEmpty).join(',')}]';
    setState(() => _busy = true);
    Navigator.of(context).pop(
      MarketingPopup(
        id: widget.initial?.id,
        name: name,
        popupImage: image,
        imageUrl: _url.text.trim().isEmpty ? null : _url.text.trim(),
        targetUser: _targetUser,
        startTime: startTime,
        endTime: endTime,
        isEnabled: _enabled ? 1 : 0,
        maxShowCount: int.tryParse(_maxShowCount.text.trim()) ?? 0,
        sorting: int.tryParse(_sorting.text.trim()) ?? 0,
        type: _type,
        applyShopIds: applyShopIds,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.initial != null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 12, 16),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  isEdit ? '编辑弹窗广告' : '新增弹窗广告',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              IconButton(
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(Icons.close),
                tooltip: '关闭',
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
              _groupTitle(context, '基本信息'),
              SettingsField(
                label: '弹窗名称（必填）',
                value: _name.text,
                onChanged: (value) => _name.text = value,
              ),
              const SizedBox(height: 12),
              SettingsField(
                label: '弹窗图片（必填，上传回填或手填地址）',
                value: _image.text,
                onChanged: (value) => _image.text = value,
              ),
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  key: const Key('marketing-popup-upload'),
                  onPressed: _busy ? null : _uploadImage,
                  icon: const Icon(Icons.upload_file_outlined, size: 18),
                  label: Text(_busy ? '上传中…' : '上传图片'),
                ),
              ),
              const SizedBox(height: 12),
              SettingsField(
                label: '点击跳转链接（可选，http/https）',
                value: _url.text,
                onChanged: (value) => _url.text = value,
              ),
              const SizedBox(height: 12),
              _groupTitle(context, '有效期与频次'),
              Row(
                children: [
                  Expanded(
                    child: SettingsField(
                      label: '开始时间（yyyy-MM-dd HH:mm:ss）',
                      value: _startTime.text,
                      onChanged: (value) => _startTime.text = value,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: SettingsField(
                      label: '结束时间（yyyy-MM-dd HH:mm:ss）',
                      value: _endTime.text,
                      onChanged: (value) => _endTime.text = value,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      key: const Key('marketing-popup-target'),
                      initialValue: _targetUser,
                      decoration: const InputDecoration(
                        labelText: '目标用户',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      items: const [
                        DropdownMenuItem(value: 'new', child: Text('新客')),
                        DropdownMenuItem(value: 'member', child: Text('会员')),
                        DropdownMenuItem(value: 'all', child: Text('全部用户')),
                      ],
                      onChanged: _busy
                          ? null
                          : (value) {
                              if (value != null) {
                                setState(() => _targetUser = value);
                              }
                            },
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      key: const Key('marketing-popup-type'),
                      initialValue: _type,
                      decoration: const InputDecoration(
                        labelText: '投放位置',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      items: [
                        for (final entry in _popupTypeLabels.entries)
                          DropdownMenuItem(
                            value: entry.key,
                            child: Text(entry.value),
                          ),
                      ],
                      onChanged: _busy
                          ? null
                          : (value) {
                              if (value != null) {
                                setState(() => _type = value);
                              }
                            },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: SettingsField(
                      label: '单日最大展示次数（0=不限）',
                      value: _maxShowCount.text,
                      onChanged: (value) => _maxShowCount.text = value,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: SettingsField(
                      label: '排序值（小者优先）',
                      value: _sorting.text,
                      onChanged: (value) => _sorting.text = value,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              SettingsField(
                label: '适用门店 ID（逗号分隔，留空=全部门店）',
                value: _shopIds.text,
                onChanged: (value) => _shopIds.text = value,
              ),
              const SizedBox(height: 12),
              SwitchListTile(
                key: const Key('marketing-popup-enabled'),
                contentPadding: EdgeInsets.zero,
                title: const Text('启用'),
                value: _enabled,
                onChanged: _busy
                    ? null
                    : (value) => setState(() => _enabled = value),
              ),
              ],
            ),
          ),
        ),
        const Divider(height: 1),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('取消'),
              ),
              TextButton(
                key: const Key('marketing-popup-submit'),
                onPressed: _submit,
                child: Text(isEdit ? '保存' : '新增'),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
