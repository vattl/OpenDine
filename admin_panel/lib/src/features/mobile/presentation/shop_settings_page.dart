import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/app_config.dart';
import '../data/api_providers.dart';
import '../design/mobile_colors.dart';
import '../design/mobile_metrics.dart';
import '../design/mobile_typography.dart';
import '../../version_upgrade/data/app_version_service.dart';
import '../../version_upgrade/presentation/version_upgrade_dialog.dart';

/// 门店设置（原型文档 §四.12）。
///
/// 原型阶段：分组卡片列表；打印/接单开关为本地可交互状态，
/// 其余编辑项为占位交互，待后端配置接口定稿后接通。
class ShopSettingsPage extends ConsumerStatefulWidget {
  const ShopSettingsPage({super.key});

  @override
  ConsumerState<ShopSettingsPage> createState() => _ShopSettingsPageState();
}

class _ShopSettingsPageState extends ConsumerState<ShopSettingsPage> {
  bool _kdsPrint = true;
  bool _receiptPrint = true;
  bool _autoAccept = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('门店设置')),
      body: ListView(
        padding: MobileMetrics.pagePadding.copyWith(
          top: MobileMetrics.spaceLg,
          bottom: MobileMetrics.spaceLg,
        ),
        children: [
          const _GroupTitle('门店信息'),
          Card(
            child: Column(
              children: [
                _NavRow(
                  icon: Icons.store_outlined,
                  label: '门店名称',
                  value: '老肥家烧烤·建设路店',
                  onTap: () => _todo(context),
                ),
                _NavRow(
                  icon: Icons.schedule_outlined,
                  label: '营业时间',
                  value: '16:00–02:00',
                  onTap: () => _todo(context),
                ),
                _NavRow(
                  icon: Icons.call_outlined,
                  label: '门店电话',
                  value: '0438-6688666',
                  onTap: () => _todo(context),
                ),
                _NavRow(
                  icon: Icons.place_outlined,
                  label: '门店地址',
                  value: '松原市宁江区建设路 128 号',
                  onTap: () => _todo(context),
                  last: true,
                ),
              ],
            ),
          ),
          const _GroupTitle('打印与后厨'),
          Card(
            child: Column(
              children: [
                _SwitchRow(
                  icon: Icons.kitchen_outlined,
                  label: '后厨KDS打印',
                  value: _kdsPrint,
                  onChanged: (v) => setState(() => _kdsPrint = v),
                ),
                _SwitchRow(
                  icon: Icons.receipt_long_outlined,
                  label: '前台小票',
                  value: _receiptPrint,
                  onChanged: (v) => setState(() => _receiptPrint = v),
                ),
                _SwitchRow(
                  icon: Icons.bolt_outlined,
                  label: '自动接单',
                  value: _autoAccept,
                  onChanged: (v) => setState(() => _autoAccept = v),
                  last: true,
                ),
              ],
            ),
          ),
          const _GroupTitle('员工与权限'),
          Card(
            child: Column(
              children: [
                _NavRow(
                  icon: Icons.group_outlined,
                  label: '员工管理',
                  onTap: () => _todo(context),
                ),
                _NavRow(
                  icon: Icons.admin_panel_settings_outlined,
                  label: '角色权限',
                  onTap: () => _todo(context),
                ),
                _NavRow(
                  icon: Icons.lock_outline,
                  label: '修改密码',
                  value: '在「我的」页操作',
                  onTap: () => Navigator.of(context).pop(),
                  last: true,
                ),
              ],
            ),
          ),
          const _GroupTitle('关于'),
          Card(
            child: Column(
              children: [
                _NavRow(
                  icon: Icons.info_outline,
                  label: '当前版本',
                  value: 'v${AppConfig.version}',
                  showChevron: false,
                  onTap: () {},
                ),
                _NavRow(
                  icon: Icons.system_update_outlined,
                  label: '检查更新',
                  trailingBadge: '新',
                  onTap: _checkUpdate,
                  last: true,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _checkUpdate() async {
    final client = ref.read(apiClientProvider);
    final service = AppVersionService(client: client);
    try {
      final info = await service.checkUpdate();
      if (!mounted) return;
      if (info.hasUpdate) {
        await showVersionUpgradeDialog(
          context,
          info: info,
          service: service,
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('当前已是最新版本 (v${AppConfig.version})'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('检查更新失败: $e'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  void _todo(BuildContext context) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('原型演示：编辑功能待配置接口定稿')));
  }
}

class _GroupTitle extends StatelessWidget {
  const _GroupTitle(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(
        left: MobileMetrics.spaceXs,
        top: MobileMetrics.spaceMd,
        bottom: MobileMetrics.spaceSm,
      ),
      child: Text(
        text,
        style: context.captionStyle.copyWith(letterSpacing: 1),
      ),
    );
  }
}

class _NavRow extends StatelessWidget {
  const _NavRow({
    required this.icon,
    required this.label,
    required this.onTap,
    this.value,
    this.trailingBadge,
    this.showChevron = true,
    this.last = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final String? value;
  final String? trailingBadge;
  final bool showChevron;
  final bool last;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: MobileMetrics.spaceLg,
              vertical: MobileMetrics.spaceMd,
            ),
            child: Row(
              children: [
                Icon(icon,
                    size: MobileMetrics.iconSize,
                    color: context.palette.brandInk),
                const SizedBox(width: MobileMetrics.spaceMd),
                Expanded(
                  child: Text(label, style: MobileTypography.body),
                ),
                if (value != null)
                  Flexible(
                    child: Text(
                      value!,
                      style: context.bodySecondaryStyle.copyWith(
                        fontSize: 14,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                if (trailingBadge != null)
                  Container(
                    margin: const EdgeInsets.only(
                      left: MobileMetrics.spaceSm,
                    ),
                    padding: const EdgeInsets.symmetric(
                      horizontal: MobileMetrics.spaceSm,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: context.palette.brandSoft,
                      borderRadius: BorderRadius.circular(
                        MobileMetrics.radiusPill,
                      ),
                    ),
                    child: Text(
                      trailingBadge!,
                      style: context.captionStyle.copyWith(
                        color: context.palette.brandInk,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                if (showChevron)
                  Icon(
                    Icons.chevron_right,
                    color: context.palette.textMuted,
                  ),
              ],
            ),
          ),
        ),
        if (!last)
          const Divider(
            height: 1,
            indent: MobileMetrics.spaceLg + MobileMetrics.iconSize +
                MobileMetrics.spaceMd,
          ),
      ],
    );
  }
}

class _SwitchRow extends StatelessWidget {
  const _SwitchRow({
    required this.icon,
    required this.label,
    required this.value,
    required this.onChanged,
    this.last = false,
  });

  final IconData icon;
  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;
  final bool last;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.only(
            left: MobileMetrics.spaceLg,
            right: MobileMetrics.spaceSm,
            top: MobileMetrics.spaceXs,
            bottom: MobileMetrics.spaceXs,
          ),
          child: Row(
            children: [
              Icon(icon,
                  size: MobileMetrics.iconSize, color: context.palette.brandInk),
              const SizedBox(width: MobileMetrics.spaceMd),
              Expanded(child: Text(label, style: MobileTypography.body)),
              Switch(value: value, onChanged: onChanged),
            ],
          ),
        ),
        if (!last)
          const Divider(
            height: 1,
            indent: MobileMetrics.spaceLg + MobileMetrics.iconSize +
                MobileMetrics.spaceMd,
          ),
      ],
    );
  }
}
