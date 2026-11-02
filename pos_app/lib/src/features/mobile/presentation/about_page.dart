import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/app_config.dart';
import '../data/api_providers.dart';
import '../design/mobile_colors.dart';
import '../design/mobile_metrics.dart';
import '../design/mobile_typography.dart';
import '../../version_upgrade/data/app_version_service.dart';
import '../../version_upgrade/presentation/version_upgrade_dialog.dart';

/// 关于与帮助（PRD F09）：版本信息、客服、FAQ 三级页（列表 → 详情）。
class AboutPage extends ConsumerWidget {
  const AboutPage({super.key});

  static const _faqs = <(String, String)>[
    ('如何开班和交班？', '进入「交接班」页面：无班次时先「开班」并填写备用金；当班时点击「确认交班」，盘点并填写实收现金后交班，系统生成交班记录。'),
    ('如何给会员充值？', '进入「会员中心」，输入手机号查询会员，点击「余额充值」。本金单笔不低于 50 元，可选赠送金额，提交前会二次确认。'),
    ('反结账有什么限制？', '含现金或收款码实收（含组合支付）的订单禁止直接反结账，需先线下退款并核对账务；其余订单可填写原因后反结账，余额分项会自动退回。'),
    ('员工看不到经营数据怎么办？', '经营看板、报表、员工授权仅老板/被授权账号可见（权限码 statistics:view / admin:manage）。请联系老板在「员工管理」中调整角色授权，重新登录后生效。'),
    ('收据打印失败怎么办？', '结账成功与打印是独立的：打印失败不影响结账结果。可在订单详情点击「补打厨单」重试，或检查打印机/飞鹅设备是否在线。'),
    ('多门店如何切换？', '在「我的」页面点击目标门店即可切换，切换后所有操作均以该门店为准（X-Shop-Id 全链路生效）。'),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(title: const Text('关于与帮助')),
      body: ListView(
        padding: MobileMetrics.pagePadding.copyWith(top: MobileMetrics.spaceLg),
        children: [
          Card(
            child: Padding(
              padding: MobileMetrics.cardPadding,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      CircleAvatar(
                        radius: 24,
                        backgroundColor: context.palette.brandSoft,
                        child: Icon(
                          Icons.storefront_outlined,
                          color: context.palette.brandInk,
                          size: 28,
                        ),
                      ),
                      const SizedBox(width: MobileMetrics.spaceMd),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('门店助手', style: MobileTypography.sectionTitle),
                          Text('版本 ${AppConfig.version}', style: context.captionStyle),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: MobileMetrics.spaceMd),
                  const Divider(height: 1),
                  ListTile(
                    leading: const Icon(Icons.support_agent_outlined),
                    title: const Text('联系客服'),
                    subtitle: const Text('营业时间 9:00–22:00'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('客服电话：400-000-0000（演示）')),
                    ),
                  ),
                  ListTile(
                    leading: const Icon(Icons.description_outlined),
                    title: const Text('用户协议与隐私政策'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => _showAgreement(context),
                  ),
                  ListTile(
                    leading: const Icon(Icons.system_update_outlined),
                    title: const Text('检查新版本'),
                    subtitle: const Text('当前版本 v${AppConfig.version}'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => _checkUpdate(context, ref),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: MobileMetrics.cardGap),
          const Text('常见问题', style: MobileTypography.sectionTitle),
          const SizedBox(height: MobileMetrics.spaceSm),
          Card(
            child: Column(
              children: [
                for (var i = 0; i < _faqs.length; i++) ...[
                  ListTile(
                    title: Text(_faqs[i].$1),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => _showFaq(context, _faqs[i].$1, _faqs[i].$2),
                  ),
                  if (i < _faqs.length - 1) const Divider(height: 1),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _showFaq(BuildContext context, String title, String content) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(MobileMetrics.radiusSheet)),
      ),
      builder: (_) => Padding(
        padding: const EdgeInsets.all(MobileMetrics.spaceLg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: MobileTypography.sectionTitle),
            const SizedBox(height: MobileMetrics.spaceMd),
            Flexible(
              child: SingleChildScrollView(
                child: Text(content, style: MobileTypography.body),
              ),
            ),
            const SizedBox(height: MobileMetrics.spaceLg),
          ],
        ),
      ),
    );
  }

  void _showAgreement(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(MobileMetrics.radiusSheet)),
      ),
      builder: (_) => const Padding(
        padding: EdgeInsets.all(MobileMetrics.spaceLg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('用户协议与隐私政策', style: MobileTypography.sectionTitle),
            SizedBox(height: MobileMetrics.spaceMd),
            Flexible(
              child: SingleChildScrollView(
                child: Text(
                  '本应用为门店运营工具。您理解并同意：'
                  '\n· 账号与权限由门店管理者分配，请妥善保管登录凭据；'
                  '\n· 订单、收款、会员等数据仅用于本门店经营管理；'
                  '\n· 客户手机号等个人信息在列表中默认脱敏展示；'
                  '\n· 退出登录后本机将清除登录凭证并解绑推送设备。'
                  '\n\n详细条款以纸质协议为准（演示版本）。',
                ),
              ),
            ),
            const SizedBox(height: MobileMetrics.spaceLg),
          ],
        ),
      ),
    );
  }

  Future<void> _checkUpdate(BuildContext context, WidgetRef ref) async {
    final client = ref.read(apiClientProvider);
    final service = AppVersionService(client: client);
    try {
      final info = await service.checkUpdate();
      if (!context.mounted) return;
      if (info.hasUpdate) {
        await showVersionUpgradeDialog(context, info: info, service: service);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('当前已是最新版本 (v${AppConfig.version})'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('检查更新失败: $e'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }
}
