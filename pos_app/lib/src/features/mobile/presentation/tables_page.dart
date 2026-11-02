import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../tables/domain/dining_table.dart';
import '../data/api_providers.dart';
import '../data/auth_state.dart';
import '../design/mobile_colors.dart';
import '../design/mobile_components.dart';
import '../design/mobile_metrics.dart';
import 'order_taking_page.dart';

final tableOverviewProvider = FutureProvider<TableOverview>(
  (ref) => ref.watch(tableRepositoryProvider).loadTableOverview(),
);

class TablesPage extends ConsumerStatefulWidget {
  const TablesPage({super.key});

  @override
  ConsumerState<TablesPage> createState() => _TablesPageState();
}

class _TablesPageState extends ConsumerState<TablesPage> {
  Timer? _poll;

  @override
  void initState() {
    super.initState();
    _poll = Timer.periodic(const Duration(seconds: 5), (_) {
      ref.invalidate(tableOverviewProvider);
    });
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final overview = ref.watch(tableOverviewProvider);
    final auth = ref.watch(authProvider);
    final canOperate = auth.hasPermission('cashier:operate') ||
        auth.hasPermission('table:operate');
    return Scaffold(
      appBar: AppBar(title: const Text('桌台')),
      body: RefreshIndicator(
        onRefresh: () async => ref.invalidate(tableOverviewProvider),
        child: overview.when(
          loading: () => const LoadingSkeleton(height: 320),
          error: (error, _) => ListView(
            children: [
              ErrorState(
                message: '桌台加载失败，请检查网络后重试\n$error',
                onRetry: () => ref.invalidate(tableOverviewProvider),
              ),
            ],
          ),
          data: (data) {
            if (data.tables.isEmpty) {
              return ListView(
                children: const [
                  EmptyState(message: '当前门店暂无桌台，请先在桌面端配置'),
                ],
              );
            }
            return GridView.builder(
              padding: MobileMetrics.pagePadding.copyWith(
                top: MobileMetrics.spaceLg,
                bottom: MobileMetrics.spaceLg,
              ),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                mainAxisSpacing: MobileMetrics.cardGap,
                crossAxisSpacing: MobileMetrics.cardGap,
                childAspectRatio: 1.7,
              ),
              itemCount: data.tables.length,
              itemBuilder: (context, index) {
                final table = data.tables[index];
                return TableCard(
                  number: table.number,
                  statusText: _statusLabel(table.status),
                  tone: _statusTone(table.status),
                  people: table.isOccupied ? table.people : null,
                  amount: table.amount != null && table.amount! > 0
                      ? table.amount!.toDouble()
                      : null,
                  onTap: canOperate
                      ? () => _showTableActions(context, ref, table)
                      : null,
                );
              },
            );
          },
        ),
      ),
    );
  }

  SemanticTone _statusTone(TableStatus status) => switch (status) {
        TableStatus.empty => SemanticTone.neutral,
        TableStatus.pending => SemanticTone.warning,
        TableStatus.settled => SemanticTone.danger,
      };

  void _showTableActions(BuildContext context, WidgetRef ref, DiningTable table) {
    showModalBottomSheet<void>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: Text(
                '桌台 ${table.number}',
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              subtitle: Text(_statusLabel(table.status)),
            ),
            const Divider(height: 1),
            if (!table.isOccupied)
              ListTile(
                leading: const Icon(Icons.restaurant_outlined),
                title: const Text('开台并点菜'),
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => OrderTakingPage(table: table),
                    ),
                  );
                },
              ),
            if (table.isOccupied) ...[
              ListTile(
                leading: const Icon(Icons.point_of_sale_outlined),
                title: const Text('点菜 / 加菜 / 结账'),
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => OrderTakingPage(table: table),
                    ),
                  );
                },
              ),
              ListTile(
                leading: const Icon(Icons.merge_type),
                title: const Text('并台'),
                onTap: () => _promptTarget(
                  sheetContext,
                  ref,
                  title: '并入桌台',
                  action: (target) async {
                    final repo = ref.read(posRepositoryProvider);
                    await repo.mergeTables(
                      sourceTableNumber: table.number,
                      targetTableNumber: target,
                    );
                  },
                ),
              ),
              ListTile(
                leading: Icon(
                  Icons.cleaning_services_outlined,
                  color: context.palette.danger,
                ),
                title: Text(
                  '清台',
                  style: TextStyle(color: context.palette.danger),
                ),
                onTap: () => _confirmClear(sheetContext, ref, table),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _confirmClear(
    BuildContext sheetContext,
    WidgetRef ref,
    DiningTable table,
  ) async {
    final confirmed = await showDialog<bool>(
      context: sheetContext,
      builder: (dialogContext) => AlertDialog(
        title: const Text('清台确认'),
        content: Text('清空 ${table.number} 号桌？\n该操作会移除当前未结账状态，请确认已结账。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: context.palette.danger,
            ),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('确认清台'),
          ),
        ],
      ),
    );
    if (confirmed != true || !sheetContext.mounted) return;
    _run(sheetContext, ref, () async {
      final repo = ref.read(posRepositoryProvider);
      await repo.clearTable(table.number);
    });
  }

  Future<void> _promptTarget(
    BuildContext sheetContext,
    WidgetRef ref, {
    required String title,
    required Future<void> Function(String target) action,
  }) async {
    final controller = TextEditingController();
    final target = await showDialog<String>(
      context: sheetContext,
      builder: (dialogContext) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(hintText: '目标桌台号'),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.of(dialogContext).pop(controller.text.trim()),
            child: const Text('确定'),
          ),
        ],
      ),
    );
    if (target == null || target.isEmpty || !sheetContext.mounted) return;
    _run(sheetContext, ref, () => action(target));
  }

  Future<void> _run(
    BuildContext sheetContext,
    WidgetRef ref,
    Future<void> Function() action,
  ) async {
    Navigator.of(sheetContext).pop();
    try {
      await action();
      ref.invalidate(tableOverviewProvider);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('操作失败：$error')),
      );
    }
  }
}

String _statusLabel(TableStatus status) => switch (status) {
  TableStatus.empty => '空闲',
  TableStatus.pending => '就餐中',
  TableStatus.settled => '已结账',
};
