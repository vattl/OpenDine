import 'dart:async';

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
import 'order_detail_page.dart';

final orderQueryProvider = StateProvider<OrderQuery>(
  (ref) => const OrderQuery(),
);

final ordersProvider = FutureProvider<PagedOrders>((ref) {
  final query = ref.watch(orderQueryProvider);
  final shopId = ref.watch(authProvider).currentShopId;
  return ref
      .watch(orderRepositoryProvider)
      .listOrders(query, shopId: shopId ?? 0);
});

class OrdersPage extends ConsumerStatefulWidget {
  const OrdersPage({super.key, this.focusOrderId});

  final String? focusOrderId;

  @override
  ConsumerState<OrdersPage> createState() => _OrdersPageState();
}

class _OrdersPageState extends ConsumerState<OrdersPage> {
  late final TextEditingController _searchController = TextEditingController(
    text: widget.focusOrderId ?? '',
  );
  Timer? _searchDebounce;
  bool _focusHandled = false;

  @override
  void initState() {
    super.initState();
    if (widget.focusOrderId?.isNotEmpty ?? false) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        final query = ref.read(orderQueryProvider);
        ref.read(orderQueryProvider.notifier).state = query.copyWith(
          keyword: widget.focusOrderId,
          pageNum: 1,
        );
      });
    }
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  void _search(String value) {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 350), () {
      if (!mounted) return;
      final query = ref.read(orderQueryProvider);
      ref.read(orderQueryProvider.notifier).state = query.copyWith(
        keyword: value.trim(),
        pageNum: 1,
      );
    });
  }

  void _openFocusedOrder(List<AdminOrder> orders) {
    final focus = widget.focusOrderId?.trim();
    if (_focusHandled || focus == null || focus.isEmpty) return;
    AdminOrder? matched;
    for (final order in orders) {
      if ('${order.id}' == focus || order.orderNo == focus) {
        matched = order;
        break;
      }
    }
    if (matched == null) return;
    final orderToOpen = matched;
    _focusHandled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => OrderDetailPage(order: orderToOpen)),
      );
      if (mounted) ref.invalidate(ordersProvider);
    });
  }

  @override
  Widget build(BuildContext context) {
    final orders = ref.watch(ordersProvider);
    final query = ref.watch(orderQueryProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('订单'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(48),
          child: _StatusFilter(
            current: query.status,
            onChanged: (status) => ref.read(orderQueryProvider.notifier).state =
                query.copyWith(status: () => status, pageNum: 1),
          ),
        ),
      ),
      body: RefreshIndicator(
        onRefresh: () async => ref.invalidate(ordersProvider),
        child: orders.when(
          loading: () => const LoadingSkeleton(height: 400),
          error: (error, _) => ListView(
            children: [
              ErrorState(
                message: '订单加载失败，请检查网络后重试',
                onRetry: () => ref.invalidate(ordersProvider),
              ),
            ],
          ),
          data: (data) {
            _openFocusedOrder(data.orders);
            if (data.orders.isEmpty) {
              return ListView(
                children: [
                  _SearchField(
                    controller: _searchController,
                    onChanged: _search,
                  ),
                  const EmptyState(message: '当前筛选条件下暂无订单'),
                ],
              );
            }
            return ListView.builder(
              itemCount: data.orders.length + 2,
              itemBuilder: (context, index) {
                if (index == 0) {
                  return _SearchField(
                    controller: _searchController,
                    onChanged: _search,
                  );
                }
                if (index == data.orders.length + 1) {
                  return _OrderPagination(
                    query: query,
                    total: data.total,
                    onPage: (page) {
                      ref.read(orderQueryProvider.notifier).state = query
                          .copyWith(pageNum: page);
                    },
                  );
                }
                final order = data.orders[index - 1];
                return Column(
                  children: [
                    _OrderTile(order: order),
                    const Divider(height: 1),
                  ],
                );
              },
            );
          },
        ),
      ),
    );
  }
}

class _SearchField extends StatelessWidget {
  const _SearchField({required this.controller, required this.onChanged});

  final TextEditingController controller;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) => Padding(
    padding: MobileMetrics.pagePadding.copyWith(
      top: MobileMetrics.spaceMd,
      bottom: MobileMetrics.spaceMd,
    ),
    child: TextField(
      controller: controller,
      onChanged: onChanged,
      textInputAction: TextInputAction.search,
      decoration: InputDecoration(
        labelText: '搜索订单',
        hintText: '订单号、桌号或手机号',
        prefixIcon: const Icon(Icons.search),
        suffixIcon: controller.text.isEmpty
            ? null
            : IconButton(
                tooltip: '清空搜索',
                onPressed: () {
                  controller.clear();
                  onChanged('');
                },
                icon: const Icon(Icons.clear),
              ),
      ),
    ),
  );
}

class _OrderPagination extends StatelessWidget {
  const _OrderPagination({
    required this.query,
    required this.total,
    required this.onPage,
  });

  final OrderQuery query;
  final int total;
  final ValueChanged<int> onPage;

  @override
  Widget build(BuildContext context) {
    final hasPrevious = query.pageNum > 1;
    final hasNext = query.pageNum * query.pageSize < total;
    return Padding(
      padding: MobileMetrics.pagePadding.copyWith(
        top: MobileMetrics.spaceMd,
        bottom: MobileMetrics.space2xl,
      ),
      child: Row(
        children: [
          Expanded(
            child: OutlinedButton(
              onPressed: hasPrevious ? () => onPage(query.pageNum - 1) : null,
              child: const Text('上一页'),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: MobileMetrics.spaceLg,
            ),
            child: Text('第 ${query.pageNum} 页 · 共 $total 条'),
          ),
          Expanded(
            child: OutlinedButton(
              onPressed: hasNext ? () => onPage(query.pageNum + 1) : null,
              child: const Text('下一页'),
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusFilter extends StatelessWidget {
  const _StatusFilter({required this.current, required this.onChanged});

  final String? current;
  final ValueChanged<String?> onChanged;

  static const _options = <String?, String>{
    null: '全部',
    'unsettled': '未结账',
    'success': '已结账',
  };

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 48,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        children: _options.entries.map((entry) {
          final selected = current == entry.key;
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: ChoiceChip(
              label: Text(entry.value),
              selected: selected,
              onSelected: (_) => onChanged(entry.key),
            ),
          );
        }).toList(),
      ),
    );
  }
}

class _OrderTile extends ConsumerWidget {
  const _OrderTile({required this.order});

  final AdminOrder order;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(
        horizontal: MobileMetrics.spaceLg,
        vertical: MobileMetrics.spaceXs,
      ),
      title: Row(
        children: [
          Expanded(
            child: Text(
              order.tableNumber.isEmpty ? '打包/外卖' : '桌台 ${order.tableNumber}',
              style: MobileTypography.itemTitle,
            ),
          ),
          AmountText(order.totalAmount, style: MobileTypography.itemTitle),
        ],
      ),
      subtitle: Text(
        '${order.orderNo}\n${order.createdAt}',
        style: context.captionStyle,
      ),
      trailing: StatusTag(
        order.isPaid ? '已结账' : '未结账',
        tone: order.isPaid ? SemanticTone.success : SemanticTone.warning,
      ),
      isThreeLine: true,
      onTap: () async {
        await Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => OrderDetailPage(order: order)),
        );
        if (context.mounted) ref.invalidate(ordersProvider);
      },
    );
  }
}
