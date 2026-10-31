import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../orders/domain/admin_order.dart';
import '../data/api_providers.dart';
import '../data/auth_state.dart';
import '../design/mobile_colors.dart';
import '../design/mobile_metrics.dart';
import '../design/mobile_typography.dart';

class OrderDetailPage extends ConsumerWidget {
  const OrderDetailPage({super.key, required this.order});

  final AdminOrder order;

  Future<void> _refundLine(
    BuildContext context,
    WidgetRef ref,
    OrderLine line,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('退菜确认'),
        content: Text('退掉「${line.name}」×${line.quantity}？\n退款审批将在桌面端完成。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('确认退菜'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    try {
      await ref.read(posRepositoryProvider).refundDish(
            orderNo: order.orderNo,
            detailId: line.id,
            quantity: line.quantity,
          );
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('已发起退菜，待桌面端审批')),
        );
      }
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('退菜失败：$error')),
        );
      }
    }
  }

  /// 反结账（PRD F04.7）：恢复为未结账，原余额分项按本金/赠送金分别退回。
  ///
  /// 服务端对含现金、微信/支付宝临时收款码实收的订单（含组合支付）一律拒绝，
  /// 前端先做提示性拦截：这类订单必须先线下退款与账务核对，不提供反结账入口。
  Future<void> _unCheckout(BuildContext context, WidgetRef ref) async {
    final method = order.paymentMethod;
    final prohibited =
        method.contains('现金') ||
        method.contains('扫码') ||
        method.contains('收款码') ||
        method.contains('微信') ||
        method.contains('支付宝');
    if (prohibited) {
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('暂不支持反结账'),
          content: const Text(
            '该订单包含现金或收款码实收（含组合支付），为避免已到账资金被清空或重复收款，'
            '请先在收银端完成线下退款与账务核对，再处理该订单。',
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('我知道了'),
            ),
          ],
        ),
      );
      return;
    }

    final reasonController = TextEditingController();
    final confirmed = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('反结账确认'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '订单 ${order.orderNo} 将恢复为未结账，桌台回到占用状态。\n'
              '若原结账含会员余额，将按本金/赠送金分别退回钱包。',
              style: context.bodySecondaryStyle,
            ),
            const SizedBox(height: MobileMetrics.spaceMd),
            TextField(
              controller: reasonController,
              autofocus: true,
              maxLength: 200,
              decoration: const InputDecoration(
                labelText: '反结账原因（必填）',
                hintText: '如：顾客要求重开',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(
              dialogContext,
            ).pop(reasonController.text.trim()),
            child: const Text('确认反结账'),
          ),
        ],
      ),
    );
    if (confirmed == null || confirmed.isEmpty || !context.mounted) return;
    try {
      await ref
          .read(posRepositoryProvider)
          .unCheckout(orderNo: order.orderNo, reason: confirmed);
      if (!context.mounted) return;
      ref.invalidate(orderRepositoryProvider);
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('已反结账，订单恢复为未结账')),
      );
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('反结账失败：$error')));
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authProvider);
    final canOperate = auth.hasPermission('order:operate');
    return Scaffold(
      appBar: AppBar(title: Text('订单 ${order.orderNo}')),
      body: ListView(
        padding: MobileMetrics.cardPadding,
        children: [
          Card(
            child: Padding(
              padding: MobileMetrics.cardPadding,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _row(context, '桌台', order.tableNumber.isEmpty ? '打包/外卖' : order.tableNumber),
                  _row(context, '状态', order.isPaid ? '已结账' : '未结账'),
                  _row(context, '下单时间', order.createdAt),
                  if (order.payTime.isNotEmpty) _row(context, '支付时间', order.payTime),
                  if (order.paymentMethod.isNotEmpty)
                    _row(context, '支付方式', order.paymentMethod),
                  if (order.remark.isNotEmpty) _row(context, '备注', order.remark),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: MobileMetrics.cardPadding,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '菜品明细',
                    style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
                  ),
                  const SizedBox(height: 8),
                  ...order.lines.map(
                    (line) => Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              line.name +
                                  (line.lineStatus == 'refunded' ? '（已退）' : ''),
                            ),
                          ),
                          Text('×${line.quantity}'),
                          const SizedBox(width: 16),
                          AmountText(
                            line.totalPrice,
                            style: MobileTypography.body.copyWith(
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          if (canOperate && line.refundable && order.isPaid)
                            IconButton(
                              icon: Icon(
                                Icons.undo,
                                size: 18,
                                color: context.palette.danger,
                              ),
                              tooltip: '退菜',
                              onPressed: () => _refundLine(context, ref, line),
                            ),
                        ],
                      ),
                    ),
                  ),
                  const Divider(height: 24),
                  _amount(context, '菜品金额', order.goodsAmount),
                  if (order.discountAmount > 0)
                    _amount(context, '折扣', -order.discountAmount),
                  if (order.serviceFee > 0) _amount(context, '服务费', order.serviceFee),
                  if (order.refundAmount > 0)
                    _amount(context, '已退款', -order.refundAmount),
                  _amount(context, '实收', order.totalAmount, bold: true),
                ],
              ),
            ),
          ),
          if (canOperate) ...[
            const SizedBox(height: 12),
            Card(
              child: Column(
                children: [
                  if (order.isUnsettled)
                    const ListTile(
                      leading: const Icon(Icons.point_of_sale_outlined),
                      title: const Text('去结账（M3）'),
                      enabled: false,
                    ),
                  if (order.isPaid)
                    ListTile(
                      leading: Icon(Icons.undo, color: context.palette.danger),
                      title: Text(
                        '反结账',
                        style: TextStyle(color: context.palette.danger),
                      ),
                      subtitle: const Text(
                        '恢复为未结账；余额分项退回钱包',
                      ),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => _unCheckout(context, ref),
                    ),
                  if (order.canWechatRefund)
                    ListTile(
                      leading: Icon(Icons.undo, color: context.palette.danger),
                      title: Text(
                        '微信退款（审批在桌面端）',
                        style: TextStyle(color: context.palette.danger),
                      ),
                      enabled: false,
                    ),
                  ListTile(
                    leading: const Icon(Icons.print_outlined),
                    title: const Text('补打厨单'),
                    onTap: () async {
                      try {
                        await ref
                            .read(orderRepositoryProvider)
                            .reprintKitchenTicket(order);
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('已补打')),
                          );
                        }
                      } catch (error) {
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('失败：$error')),
                          );
                        }
                      }
                    },
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _row(BuildContext context, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: MobileMetrics.spaceXs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 72,
            child: Text(label, style: context.captionStyle),
          ),
          Expanded(child: Text(value, style: MobileTypography.body)),
        ],
      ),
    );
  }

  Widget _amount(BuildContext context, String label, double value, {bool bold = false}) {
    final style = bold
        ? MobileTypography.itemTitle.copyWith(
            fontFeatures: const [FontFeature.tabularFigures()],
          )
        : context.bodySecondaryStyle.copyWith(
            fontFeatures: const [FontFeature.tabularFigures()],
          );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: MobileMetrics.spaceXs),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: style),
          AmountText(
            value,
            negative: value < 0,
            style: style,
          ),
        ],
      ),
    );
  }
}
