import 'package:flutter/material.dart';

import '../../cashier_shell/presentation/cashier_tokens.dart';

enum SettingsDestination {
  store('店铺信息', Icons.storefront_outlined, '基础资料·店铺公告·营业日'),
  printer('打印设置', Icons.print_outlined, '飞鹅云已接入·本地打印'),
  payment('支付渠道', Icons.payments_outlined, '4 种支付方式·多终端启停'),
  notification('通知消息', Icons.notifications_none_rounded, '3 类通知规则已开启'),
  marketing('营销活动', Icons.campaign_outlined, '首单活动·资格互斥·核销'),
  employee('员工权限', Icons.manage_accounts_outlined, '员工管理·角色与权限矩阵'),
  inventory('库存原料', Icons.inventory_2_outlined, '原料·BOM·采购·调拨·批次'),
  delivery('外卖管理', Icons.delivery_dining_outlined, '平台接入·真省钱配送'),
  report('数据报表', Icons.bar_chart_rounded, '营业日口径·异步导出'),
  log('日志', Icons.receipt_long_outlined, '30天在线·归档与审计'),
  kds('厨房KDS', Icons.kitchen_outlined, '局域网安全代理·设备管理·链路监控'),
  coupon('优惠券管理', Icons.confirmation_number_outlined, '券模板·兑换码·发券·用户券'),
  version('版本管理', Icons.system_update_rounded, '平台策略·灰度发布·升级控制'),
  receivable('挂账管理', Icons.account_balance_wallet_outlined, '授信账户·商业应收·额度管控·对账单',
  ),
  apiConsole('接口调试', Icons.monitor_heart_outlined, '请求日志·响应详情');

  const SettingsDestination(this.label, this.icon, this.summary);
  final String label;
  final IconData icon;
  final String summary;
}

extension SettingsDestinationBackend on SettingsDestination {
  String get backendModule => switch (this) {
    SettingsDestination.store => 'store',
    SettingsDestination.printer => 'printing',
    SettingsDestination.payment => 'payment',
    SettingsDestination.notification => 'notifications',
    SettingsDestination.marketing => 'marketing',
    SettingsDestination.employee => 'access',
    SettingsDestination.inventory => 'inventory',
    SettingsDestination.delivery => 'delivery',
    SettingsDestination.report => 'reports',
    SettingsDestination.log => 'logs',
    SettingsDestination.kds => 'kds',
    SettingsDestination.coupon => 'coupon',
    SettingsDestination.version => 'app-version',
    SettingsDestination.receivable => 'receivable',
    SettingsDestination.apiConsole => 'api-console',
  };
}

class SettingsSectionSpec {
  const SettingsSectionSpec(this.id, this.label, this.icon);

  final String id;
  final String label;
  final IconData icon;
}

extension SettingsDestinationSections on SettingsDestination {
  List<SettingsSectionSpec> get sections => switch (this) {
    SettingsDestination.store => const [
      SettingsSectionSpec('profile', '基础资料', Icons.badge_outlined),
      SettingsSectionSpec('notice', '店铺公告', Icons.campaign_outlined),
      SettingsSectionSpec('business-day', '营业日', Icons.today_outlined),
      SettingsSectionSpec('inheritance', '继承设置', Icons.account_tree_outlined),
    ],
    SettingsDestination.printer => const [
      SettingsSectionSpec('devices', '打印机', Icons.print_outlined),
      SettingsSectionSpec('rules', '打印规则', Icons.rule_outlined),
      SettingsSectionSpec('templates', '票据模板', Icons.description_outlined),
      SettingsSectionSpec('test', '打印测试', Icons.fact_check_outlined),
      SettingsSectionSpec('jobs', '任务记录', Icons.history_outlined),
    ],
    SettingsDestination.payment => const [
      SettingsSectionSpec('channels', '支付渠道', Icons.payments_outlined),
    ],
    SettingsDestination.notification => const [
      SettingsSectionSpec('templates', '微信订阅模板', Icons.mark_email_read_outlined),
      SettingsSectionSpec('rules', '出餐超时规则', Icons.notifications_outlined),
      SettingsSectionSpec('deliveries', '投递审计日志', Icons.receipt_long_outlined),
    ],
    SettingsDestination.marketing => const [
      SettingsSectionSpec('campaigns', '首单活动', Icons.campaign_outlined),
      SettingsSectionSpec('banners', '轮播图', Icons.view_carousel_outlined),
      SettingsSectionSpec('eligibility', '资格与互斥', Icons.verified_user_outlined),
      SettingsSectionSpec('invite-reward', '首单返利', Icons.card_giftcard_outlined,
      ),
      SettingsSectionSpec('invite-poster', '邀请海报', Icons.photo_outlined),
      SettingsSectionSpec('ninefold', '夜间九折', Icons.nights_stay_outlined),
      SettingsSectionSpec('redemptions', '核销记录', Icons.receipt_long_outlined),
    ],
    SettingsDestination.employee => const [
      SettingsSectionSpec('employees', '员工', Icons.people_outline),
      SettingsSectionSpec('roles', '角色', Icons.admin_panel_settings_outlined),
      SettingsSectionSpec('matrix', '权限矩阵', Icons.grid_on_outlined),
      SettingsSectionSpec(
        'api-permissions',
        '接口权限映射',
        Icons.alt_route_outlined,
      ),
      SettingsSectionSpec('permission-codes', '权限码管理', Icons.vpn_key_outlined),
      SettingsSectionSpec('policies', '策略中心', Icons.rule_outlined),
      SettingsSectionSpec('shops', '多店授权', Icons.store_mall_directory_outlined),
      SettingsSectionSpec('changes', '变更记录', Icons.manage_history_outlined),
      SettingsSectionSpec('approvals', '审批记录', Icons.approval_outlined),
    ],
    SettingsDestination.inventory => const [
      SettingsSectionSpec('materials', '原料', Icons.inventory_2_outlined),
      SettingsSectionSpec('bom', 'BOM配方', Icons.account_tree_outlined),
      SettingsSectionSpec('purchase', '采购', Icons.shopping_cart_outlined),
      SettingsSectionSpec('suppliers', '供应商', Icons.local_shipping_outlined),
      SettingsSectionSpec('warehouses', '仓库', Icons.warehouse_outlined),
      SettingsSectionSpec('transfers', '调拨', Icons.swap_horiz_outlined),
      SettingsSectionSpec('batches', '批次', Icons.qr_code_2_outlined),
      SettingsSectionSpec('ledger', '库存预警', Icons.warning_amber_outlined),
    ],
    SettingsDestination.delivery => const [
      SettingsSectionSpec('platforms', '外卖平台', Icons.storefront_outlined),
      SettingsSectionSpec('rules', '配送规则', Icons.alt_route_outlined),
      SettingsSectionSpec('zsq', '真省钱配送', Icons.delivery_dining_outlined),
      SettingsSectionSpec('records', '配送记录', Icons.history_outlined),
    ],
    SettingsDestination.report => const [
      SettingsSectionSpec('catalog', '数据看板', Icons.bar_chart_outlined),
      SettingsSectionSpec('business-day', '营业日设置', Icons.today_outlined),
      SettingsSectionSpec('exports', '导出任务', Icons.download_outlined),
    ],
    SettingsDestination.log => const [
      SettingsSectionSpec('operations', '操作日志', Icons.manage_search_outlined),
      SettingsSectionSpec('devices', '设备日志', Icons.devices_outlined),
      SettingsSectionSpec('archive', '归档查询', Icons.archive_outlined),
      SettingsSectionSpec('exports', '导出任务', Icons.download_outlined),
      SettingsSectionSpec('runtime', '运行日志', Icons.bug_report_outlined),
    ],
    SettingsDestination.apiConsole => const [
      SettingsSectionSpec('debug', '接口调试', Icons.monitor_heart_outlined),
    ],
    SettingsDestination.coupon => const [
      SettingsSectionSpec('coupons', '券模板', Icons.confirmation_number_outlined),
      SettingsSectionSpec('redeem-codes', '兑换码', Icons.qr_code_outlined),
      SettingsSectionSpec('grant', '批量发券', Icons.upload_file_outlined),
      SettingsSectionSpec('user-coupons', '用户券', Icons.card_membership_outlined,
      ),
    ],
    SettingsDestination.kds => const [
      SettingsSectionSpec('connection', 'KDS 连接', Icons.lan_outlined),
      SettingsSectionSpec('requests', '代理请求', Icons.swap_horiz_outlined),
      SettingsSectionSpec('devices', '设备管理', Icons.devices_outlined),
    ],
    SettingsDestination.version => const [
      SettingsSectionSpec('policy', '版本策略', Icons.policy_outlined),
      SettingsSectionSpec('publish', '发布配置', Icons.upload_file_outlined),
      SettingsSectionSpec('gray', '灰度管控', Icons.tune_outlined),
      SettingsSectionSpec('sandbox', '沙箱模拟', Icons.play_circle_outline_rounded),
    ],
    SettingsDestination.receivable => const [
      SettingsSectionSpec('accounts', '授信账户', Icons.people_outline),
      SettingsSectionSpec('claims', '应收账单', Icons.receipt_long_outlined),
      SettingsSectionSpec('aging', '账龄分析', Icons.pie_chart_outline),
      SettingsSectionSpec('statement', '流水对账', Icons.history_outlined),
    ],
  };
}

enum SettingsConfigSource {
  headquarters('继承总店', Color(0xff0369a1), Color(0xffe0f2fe)),
  shop('门店覆盖', Color(0xff92400e), Color(0xfffef3c7)),
  system('系统固定', Color(0xff166534), Color(0xffdcfce7));

  const SettingsConfigSource(this.label, this.textColor, this.backgroundColor);
  final String label;
  final Color textColor;
  final Color backgroundColor;
}

class SettingsConfigSourceBadge extends StatelessWidget {
  const SettingsConfigSourceBadge({
    super.key,
    required this.source,
    this.onSwitchToOverride,
    this.onRestoreInherited,
  });

  final SettingsConfigSource source;
  final VoidCallback? onSwitchToOverride;
  final VoidCallback? onRestoreInherited;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: source.backgroundColor,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: source.textColor.withOpacity(0.3)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                source == SettingsConfigSource.headquarters
                    ? Icons.account_tree_outlined
                    : source == SettingsConfigSource.shop
                    ? Icons.store_outlined
                    : Icons.lock_outline,
                size: 14,
                color: source.textColor,
              ),
              const SizedBox(width: 4),
              Text(
                source.label,
                style: TextStyle(
                  color: source.textColor,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
        if (source == SettingsConfigSource.headquarters &&
            onSwitchToOverride != null) ...[
          const SizedBox(width: 8),
          TextButton.icon(
            onPressed: onSwitchToOverride,
            icon: const Icon(Icons.edit_outlined, size: 14),
            label: const Text('改为门店配置', style: TextStyle(fontSize: 12)),
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              minimumSize: const Size(0, 28),
            ),
          ),
        ],
        if (source == SettingsConfigSource.shop &&
            onRestoreInherited != null) ...[
          const SizedBox(width: 8),
          TextButton.icon(
            onPressed: onRestoreInherited,
            icon: const Icon(Icons.restore_outlined, size: 14),
            label: const Text('恢复继承', style: TextStyle(fontSize: 12)),
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              minimumSize: const Size(0, 28),
            ),
          ),
        ],
      ],
    );
  }
}

enum StatusBadgeType { success, warning, danger, info, neutral }

class SettingsStatusBadge extends StatelessWidget {
  const SettingsStatusBadge({
    super.key,
    required this.label,
    this.type = StatusBadgeType.neutral,
    this.icon,
  });

  final String label;
  final StatusBadgeType type;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final (textColor, bgColor, defaultIcon) = switch (type) {
      StatusBadgeType.success => (
        context.cashier.success,
        context.cashier.successBackground,
        Icons.check_circle_outline_rounded,
      ),
      StatusBadgeType.warning => (
        context.cashier.warning,
        context.cashier.warningBackground,
        Icons.warning_amber_rounded,
      ),
      StatusBadgeType.danger => (
        context.cashier.danger,
        context.cashier.dangerBackground,
        Icons.error_outline_rounded,
      ),
      StatusBadgeType.info => (
        const Color(0xff0369a1),
        const Color(0xffe0f2fe),
        Icons.info_outline_rounded,
      ),
      StatusBadgeType.neutral => (
        context.cashier.inkSecondary,
        context.cashier.subtle,
        Icons.circle_outlined,
      ),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon ?? defaultIcon, size: 13, color: textColor),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              color: textColor,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class SettingsEmptyState extends StatelessWidget {
  const SettingsEmptyState({
    super.key,
    required this.title,
    this.description,
    this.icon = Icons.inbox_outlined,
    this.primaryActionLabel,
    this.onPrimaryAction,
    this.secondaryActionLabel,
    this.onSecondaryAction,
  });

  final String title;
  final String? description;
  final IconData icon;
  final String? primaryActionLabel;
  final VoidCallback? onPrimaryAction;
  final String? secondaryActionLabel;
  final VoidCallback? onSecondaryAction;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 48, color: context.cashier.inkMuted),
            const SizedBox(height: 16),
            Text(
              title,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: context.cashier.ink,
              ),
              textAlign: TextAlign.center,
            ),
            if (description != null) ...[
              const SizedBox(height: 8),
              Text(
                description!,
                style: TextStyle(fontSize: 13, color: context.cashier.inkMuted),
                textAlign: TextAlign.center,
              ),
            ],
            if (primaryActionLabel != null && onPrimaryAction != null) ...[
              const SizedBox(height: 20),
              FilledButton(
                onPressed: onPrimaryAction,
                style: FilledButton.styleFrom(
                  backgroundColor: context.cashier.ink,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                child: Text(primaryActionLabel!),
              ),
            ],
            if (secondaryActionLabel != null && onSecondaryAction != null) ...[
              const SizedBox(height: 8),
              TextButton(
                onPressed: onSecondaryAction,
                child: Text(secondaryActionLabel!),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class SettingsErrorState extends StatelessWidget {
  const SettingsErrorState({super.key, required this.message, this.onRetry});

  final String message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.error_outline_rounded,
              size: 44,
              color: context.cashier.danger,
            ),
            const SizedBox(height: 14),
            Text(
              message,
              style: TextStyle(fontSize: 14, color: context.cashier.danger),
              textAlign: TextAlign.center,
            ),
            if (onRetry != null) ...[
              const SizedBox(height: 18),
              OutlinedButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh, size: 16),
                label: const Text('重试'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class SettingsForbiddenPlaceholder extends StatelessWidget {
  const SettingsForbiddenPlaceholder({super.key, this.moduleName});

  final String? moduleName;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.lock_outline_rounded,
              size: 54,
              color: context.cashier.inkMuted,
            ),
            const SizedBox(height: 16),
            Text(
              moduleName != null ? '暂无「$moduleName」访问权限' : '暂无访问权限',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: context.cashier.ink,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '如需开通，请联系总店管理员在「员工权限」中分配对应角色。',
              style: TextStyle(fontSize: 13, color: context.cashier.inkMuted),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

class SettingsSkeletonLoader extends StatelessWidget {
  const SettingsSkeletonLoader({super.key, this.rows = 4});
  final int rows;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: List.generate(
          rows,
          (index) => Container(
            margin: const EdgeInsets.only(bottom: 16),
            height: index == 0 ? 32 : 56,
            decoration: BoxDecoration(
              color: context.cashier.subtle,
              borderRadius: BorderRadius.circular(8),
            ),
          ),
        ),
      ),
    );
  }
}

class SettingsPanel extends StatelessWidget {
  const SettingsPanel({
    super.key,
    required this.title,
    required this.child,
    this.trailing,
  });

  final String title;
  final Widget child;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: context.cashier.surface,
        borderRadius: BorderRadius.circular(12),
        border: isDark ? Border.all(color: context.cashier.border) : null,
        boxShadow: const [
          BoxShadow(
            color: Color(0x0f000000),
            blurRadius: 16,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                    color: context.cashier.ink,
                  ),
                ),
              ),
              if (trailing != null) trailing!,
            ],
          ),
          const SizedBox(height: 22),
          child,
        ],
      ),
    );
  }
}

class SettingsPagePadding extends StatelessWidget {
  const SettingsPagePadding({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) =>
      Padding(padding: const EdgeInsets.fromLTRB(16, 22, 16, 0), child: child);
}

class SettingsField extends StatelessWidget {
  const SettingsField({
    super.key,
    required this.label,
    required this.value,
    this.maxLines = 1,
    this.onChanged,
    this.readOnly = false,
  });
  final String label;
  final String value;
  final int maxLines;
  final ValueChanged<String>? onChanged;
  final bool readOnly;

  @override
  Widget build(BuildContext context) => TextFormField(
    initialValue: value,
    maxLines: maxLines,
    readOnly: readOnly,
    onChanged: onChanged,
    decoration: InputDecoration(
      labelText: label,
      border: const OutlineInputBorder(),
      isDense: true,
    ),
  );
}

class SettingsPrimaryButton extends StatelessWidget {
  const SettingsPrimaryButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.loading = false,
    this.destructive = false,
  });
  final String label;
  final VoidCallback? onPressed;
  final bool loading;
  final bool destructive;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: 48,
    child: FilledButton(
      onPressed: loading ? null : onPressed,
      style: FilledButton.styleFrom(
        backgroundColor: destructive
            ? context.cashier.danger
            : context.cashier.ink,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
      child: loading
          ? const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Colors.white,
              ),
            )
          : Text(
              label,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
            ),
    ),
  );
}

Future<bool?> showSettingsConfirmDialog({
  required BuildContext context,
  required String title,
  required String message,
  List<String> impacts = const [],
  bool destructive = false,
  String confirmLabel = '确认',
  String cancelLabel = '取消',
}) {
  return showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (context) => AlertDialog(
      title: Row(
        children: [
          Icon(
            destructive
                ? Icons.warning_amber_rounded
                : Icons.help_outline_rounded,
            color: destructive ? context.cashier.danger : context.cashier.ink,
          ),
          const SizedBox(width: 10),
          Text(title),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(message, style: const TextStyle(fontSize: 14, height: 1.4)),
          if (impacts.isNotEmpty) ...[
            const SizedBox(height: 14),
            Text(
              '受影响的业务或入口：',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: context.cashier.danger,
              ),
            ),
            const SizedBox(height: 6),
            ...impacts.map(
              (item) => Padding(
                padding: const EdgeInsets.only(left: 8, bottom: 4),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('• ', style: TextStyle(color: context.cashier.danger)),
                    Expanded(
                      child: Text(
                        item,
                        style: TextStyle(
                          fontSize: 12,
                          color: context.cashier.inkSecondary,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(cancelLabel),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(true),
          style: FilledButton.styleFrom(
            backgroundColor: destructive
                ? context.cashier.danger
                : context.cashier.ink,
          ),
          child: Text(confirmLabel),
        ),
      ],
    ),
  );
}

Future<bool?> showUnsavedChangesDialog(BuildContext context) {
  return showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('未保存的修改'),
      content: const Text('当前页面有尚未保存的配置，离开后修改将会丢失。是否确认放弃修改？'),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('继续编辑'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(true),
          style: FilledButton.styleFrom(
            backgroundColor: context.cashier.danger,
          ),
          child: const Text('放弃修改'),
        ),
      ],
    ),
  );
}

void showSettingsSaved(BuildContext context, String message) {
  final isDark = Theme.of(context).brightness == Brightness.dark;
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(
              Icons.check_circle_rounded,
              color: isDark ? Colors.black : Colors.white,
              size: 18,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                message,
                style: TextStyle(color: isDark ? Colors.black : Colors.white),
              ),
            ),
          ],
        ),
        backgroundColor: context.cashier.ink,
        behavior: SnackBarBehavior.floating,
      ),
    );
}
