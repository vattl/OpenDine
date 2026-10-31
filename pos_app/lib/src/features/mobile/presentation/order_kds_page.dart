import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../orders/domain/admin_order.dart';
import '../../orders/domain/order_query.dart';
import '../data/api_providers.dart';
import '../data/auth_state.dart';
import '../design/mobile_colors.dart';
import '../design/mobile_components.dart';
import '../design/mobile_metrics.dart';
import '../design/mobile_typography.dart';

/// 订单KDS出品看板。
///
/// 真实数据来自云端订单列表（`OrderRepository.listOrders`），按
/// `kdsOrderStatus` 分组为待制作 / 制作中 / 待出品 / 已完成。
/// "已完成"tab 展示当前营业时间内所有已完成订单（含已归档）。
class OrderKdsPage extends ConsumerStatefulWidget {
  const OrderKdsPage({super.key});

  @override
  ConsumerState<OrderKdsPage> createState() => _OrderKdsPageState();
}

enum _KdsStatus { pending, cooking, ready, done }

_KdsStatus? _mapKdsStatus(String raw) {
  final v = raw.trim().toLowerCase();
  return switch (v) {
    '10' || 'pending' || 'waiting' => _KdsStatus.pending,
    '20' || 'cooking' || 'in_progress' => _KdsStatus.cooking,
    '30' || 'partially_completed' || 'partial' => _KdsStatus.ready,
    '40' || 'completed' || 'done' || 'ready' => _KdsStatus.done,
    _ => null,
  };
}

String _kdsStatusLabel(_KdsStatus status) => switch (status) {
      _KdsStatus.pending => '待制作',
      _KdsStatus.cooking => '制作中',
      _KdsStatus.ready => '待出品',
      _KdsStatus.done => '已完成',
    };

int _waitingMinutes(String createdAt) {
  final dt = DateTime.tryParse(createdAt);
  if (dt == null) return 0;
  return DateTime.now().difference(dt).inMinutes;
}

class _OrderKdsPageState extends ConsumerState<OrderKdsPage> {
  _KdsStatus? _filter;
  List<AdminOrder> _orders = const [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final shopId = ref.read(authProvider).currentShopId;
    if (shopId == null) {
      setState(() {
        _loading = false;
        _error = '请先选择门店';
      });
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final paged = await ref.read(orderRepositoryProvider).listOrders(
            const OrderQuery(pageNum: 1, pageSize: 100),
            shopId: shopId,
          );
      if (!mounted) return;
      setState(() {
        _orders = paged.orders;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = '$error';
      });
    }
  }

  List<AdminOrder> get _visible {
    if (_filter == null) return _orders;
    return _orders
        .where((o) => _mapKdsStatus(o.kdsOrderStatus) == _filter)
        .toList(growable: false);
  }

  int _count(_KdsStatus status) =>
      _orders.where((o) => _mapKdsStatus(o.kdsOrderStatus) == status).length;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('订单KDS'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loading ? null : _load,
          ),
        ],
      ),
      body: Column(
        children: [
          _buildFilters(),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                    ? ListView(
                        children: [
                          ErrorState(
                            message: '加载失败：$_error',
                            onRetry: _load,
                          ),
                        ],
                      )
                    : RefreshIndicator(
                        onRefresh: _load,
                        child: _visible.isEmpty
                            ? ListView(
                                children: const [
                                  EmptyState(message: '当前状态下暂无订单'),
                                ],
                              )
                            : ListView.separated(
                                padding: MobileMetrics.pagePadding.copyWith(
                                  top: MobileMetrics.spaceSm,
                                  bottom: MobileMetrics.spaceLg,
                                ),
                                itemCount: _visible.length,
                                separatorBuilder: (_, __) =>
                                    const SizedBox(height: MobileMetrics.cardGap),
                                itemBuilder: (_, index) =>
                                    _OrderCard(order: _visible[index]),
                              ),
                      ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilters() {
    const entries = <(_KdsStatus?, String)>[
      (null, '全部'),
      (_KdsStatus.pending, '待制作'),
      (_KdsStatus.cooking, '制作中'),
      (_KdsStatus.ready, '待出品'),
      (_KdsStatus.done, '已完成'),
    ];
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: MobileMetrics.pagePadding.copyWith(
        top: MobileMetrics.spaceSm,
        bottom: MobileMetrics.spaceSm,
      ),
      child: Row(
        children: [
          for (final (status, label) in entries) ...[
            ChoiceChip(
              selected: _filter == status,
              onSelected: (_) => setState(() => _filter = status),
              label: Text(_chipLabel(status, label)),
            ),
            const SizedBox(width: MobileMetrics.spaceSm),
          ],
        ],
      ),
    );
  }

  String _chipLabel(_KdsStatus? status, String label) {
    if (status == null) return label;
    final count = _count(status);
    return count > 0 ? '$label $count' : label;
  }
}

class _OrderCard extends StatelessWidget {
  const _OrderCard({required this.order});

  final AdminOrder order;

  @override
  Widget build(BuildContext context) {
    final status = _mapKdsStatus(order.kdsOrderStatus);
    final done = status == _KdsStatus.done;
    final minutes = _waitingMinutes(order.createdAt);
    final timeout = !done && minutes >= 10;
    final tableLabel = order.tableNumber.isEmpty
        ? (order.isTakeout ? '外卖' : '打包')
        : '${order.tableNumber}号桌';
    return Opacity(
      opacity: done ? 0.6 : 1,
      child: Card(
        child: Padding(
          padding: MobileMetrics.cardPadding,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(
                    tableLabel,
                    style: MobileTypography.itemTitle.copyWith(fontSize: 20),
                  ),
                  const SizedBox(width: MobileMetrics.spaceSm),
                  Text(
                    order.orderNo,
                    style: context.captionStyle,
                  ),
                  const Spacer(),
                  if (done)
                    const StatusTag('已完成', tone: SemanticTone.success)
                  else if (status != null)
                    StatusTag(
                      _kdsStatusLabel(status),
                      tone: switch (status) {
                        _KdsStatus.pending => SemanticTone.warning,
                        _KdsStatus.cooking => SemanticTone.info,
                        _KdsStatus.ready => SemanticTone.info,
                        _ => SemanticTone.success,
                      },
                    )
                  else
                    StatusTag(
                      order.kdsOrderStatus.isEmpty ? '未知' : order.kdsOrderStatus,
                      tone: SemanticTone.neutral,
                    ),
                ],
              ),
              const SizedBox(height: MobileMetrics.spaceSm),
              if (order.lines.isNotEmpty)
                for (final line in order.lines)
                  Padding(
                    padding: const EdgeInsets.only(top: MobileMetrics.spaceXs),
                    child: Wrap(
                      crossAxisAlignment: WrapCrossAlignment.center,
                      spacing: MobileMetrics.spaceSm,
                      children: [
                        Text(
                          '${line.name} ×${line.quantity}',
                          style: MobileTypography.body,
                        ),
                        if (line.specification.isNotEmpty)
                          Container(
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
                              line.specification,
                              style: context.captionStyle.copyWith(
                                color: context.palette.brandInk,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                      ],
                    ),
                  )
              else
                Text(
                  '（订单明细请在订单详情查看）',
                  style: context.captionStyle.copyWith(
                    color: context.palette.textMuted,
                  ),
                ),
              if (order.remark.isNotEmpty) ...[
                const SizedBox(height: MobileMetrics.spaceXs),
                Text(
                  '备注：${order.remark}',
                  style: context.captionStyle.copyWith(
                    color: context.palette.textMuted,
                  ),
                ),
              ],
              if (!done) ...[
                const SizedBox(height: MobileMetrics.spaceSm),
                Text(
                  '已等 $minutes 分钟',
                  style: MobileTypography.label.copyWith(
                    color: timeout
                        ? context.palette.danger
                        : context.palette.textMuted,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
