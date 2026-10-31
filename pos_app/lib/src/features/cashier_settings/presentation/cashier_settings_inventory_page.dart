import 'dart:convert';

import 'package:flutter/material.dart';

import '../../../core/admin_api_client.dart';
import '../../../core/api_contract.dart';
import '../data/cashier_settings_repository.dart';
import '../data/inventory_repository.dart';
import '../data/real_inventory_repository.dart';
import '../domain/inventory_models.dart';
import 'cashier_settings_prototype_pages.dart';
import 'cashier_settings_shared.dart';
import '../../cashier_shell/presentation/cashier_tokens.dart';

/// 库存设置页（M-E 库存增强）。
/// purchase（采购）/ transfers（调拨）/ bom（BOM）三个分区提供运营操作闭环，
/// 其余分区（原料/供应商/仓库/批次/流水）沿用原型占位页。
class CashierSettingsInventoryPage extends StatelessWidget {
  const CashierSettingsInventoryPage({
    super.key,
    required this.repository,
    required this.client,
    required this.section,
    this.permissions = const {},
  });

  final CashierSettingsRepository repository;
  final AdminApiClient? client;
  final SettingsSectionSpec section;
  final Set<String> permissions;

  bool get _canManage =>
      permissions.contains('inventory:manage') ||
      permissions.contains('admin:manage');

  @override
  Widget build(BuildContext context) {
    final apiClient = client;
    final isOperationalSection = section.id == 'purchase' ||
        section.id == 'transfers' ||
        section.id == 'bom' ||
        section.id == 'suppliers' ||
        section.id == 'warehouses' ||
        section.id == 'batches';
    if (isOperationalSection && apiClient != null) {
      final inventory = RealInventoryRepository(apiClient);
      if (section.id == 'purchase') {
        return _PurchaseSection(
          repository: inventory,
          canManage: _canManage);
      }
      if (section.id == 'transfers') {
        return _TransfersSection(
          repository: inventory,
          canManage: _canManage);
      }
      if (section.id == 'bom') {
        return _BomSection(
          repository: inventory,
          canManage: _canManage);
      }
      if (section.id == 'suppliers') {
        return _SuppliersSection(
          repository: inventory,
          canManage: _canManage);
      }
      if (section.id == 'warehouses') {
        return _WarehousesSection(
          repository: inventory,
          canManage: _canManage);
      }
      return _BatchesSection(
        repository: inventory,
        canManage: _canManage);
    }
    return SettingsReadOnlySection(
      repository: repository,
      destination: SettingsDestination.inventory,
      section: section,
    );
  }
}

const _purchaseStatusMeta = <String, (StatusBadgeType, String)>{
  'DRAFT': (StatusBadgeType.neutral, '草稿'),
  'PENDING_REVIEW': (StatusBadgeType.warning, '待审核'),
  'APPROVED': (StatusBadgeType.info, '已审核'),
  'REJECTED': (StatusBadgeType.danger, '已驳回'),
  'RECEIVED': (StatusBadgeType.success, '已收货'),
};

const _transferStatusMeta = <String, (StatusBadgeType, String)>{
  'OUTBOUND': (StatusBadgeType.info, '待出库'),
  'IN_TRANSIT': (StatusBadgeType.warning, '在途'),
  'RECEIVED': (StatusBadgeType.success, '已收货'),
};

const _bomStatusMeta = <String, (StatusBadgeType, String)>{
  'DRAFT': (StatusBadgeType.neutral, '草稿'),
  'ACTIVE': (StatusBadgeType.success, '生效中'),
  'HISTORY': (StatusBadgeType.info, '历史版本'),
};

class _PurchaseSection extends StatefulWidget {
  const _PurchaseSection({required this.repository, required this.canManage});

  final InventoryRepository repository;
  final bool canManage;

  @override
  State<_PurchaseSection> createState() => _PurchaseSectionState();
}

class _PurchaseSectionState extends State<_PurchaseSection> {
  late Future<List<InventoryPurchase>> _future;

  @override
  void initState() {
    super.initState();
    _future = widget.repository.listPurchases();
  }

  void _reload() => setState(() {
        _future = widget.repository.listPurchases();
      });

  Future<void> _createPurchase() async {
    final created = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => _CreatePurchaseDialog(
        client: (widget.repository as RealInventoryRepository).client,
        repository: widget.repository,
      ),
    );
    if (created == true && mounted) {
      showSettingsSaved(context, '采购单已创建，等待审核');
      _reload();
    }
  }

  Future<void> _transition(
    InventoryPurchase purchase,
    String action,
    String actionLabel,
  ) async {
    var reason = '';
    if (action == 'reject') {
      reason = await _promptReason(context, '驳回原因');
      if (reason.isEmpty || !mounted) return;
    }
    final ok = await showSettingsConfirmDialog(
      context: context,
      title: '$actionLabel采购单 #${purchase.id}',
      message: action == 'receive'
          ? '确认收货后库存将按采购明细入库，该操作不可撤销。'
          : '确认对采购单 #${purchase.id} 执行「$actionLabel」？',
      destructive: action == 'reject',
      confirmLabel: actionLabel,
    );
    if (ok != true || !mounted) return;
    try {
      await widget.repository
          .updatePurchaseStatus(id: purchase.id, action: action, reason: reason,
      );
      if (!mounted) return;
      showSettingsSaved(context, '已$actionLabel采购单 #${purchase.id}');
      _reload();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context,
      ).showSnackBar(
        SnackBar(content: Text('操作失败：$error')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<InventoryPurchase>>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return SettingsErrorState(
            message: '加载采购单失败：${snapshot.error}',
            onRetry: _reload,
          );
        }
        if (!snapshot.hasData) {
          return const SettingsSkeletonLoader(rows: 3);
        }
        final purchases = snapshot.data!;
        return SettingsPagePadding(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SettingsPanel(
                title: '采购单',
                trailing: widget.canManage
                    ? FilledButton.icon(
                        key: const Key('inventory-create-purchase'),
                        onPressed: _createPurchase,
                        icon: const Icon(Icons.add, size: 18),
                        label: const Text('新建采购单'),
                      )
                    : null,
                child: purchases.isEmpty
                    ? const SettingsEmptyState(
                        title: '暂无采购单',
                        description: '点击「新建采购单」发起采购并进入审核流。',
                      )
                    : Column(
                        children: [
                          for (final item in purchases)
                            _purchaseRow(context, item),
                        ],
                      ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _purchaseRow(BuildContext context, InventoryPurchase purchase) {
    final (badgeType, badgeLabel) =
        _purchaseStatusMeta[purchase.status] ??
            (StatusBadgeType.neutral, purchase.status);
    final actionWidgets = <Widget>[];
    if (widget.canManage) {
      if (purchase.status == 'PENDING_REVIEW') {
        actionWidgets.addAll([
          OutlinedButton(
            key: Key('inventory-purchase-reject-${purchase.id}'),
            onPressed: () => _transition(purchase, 'reject', '驳回'),
            style: OutlinedButton.styleFrom(
              foregroundColor: context.cashier.danger,
              minimumSize: const Size(0, 34),
            ),
            child: const Text('驳回'),
          ),
          const SizedBox(width: 8),
          FilledButton(
            key: Key('inventory-purchase-approve-${purchase.id}'),
            onPressed: () => _transition(purchase, 'approve', '审核通过'),
            style: FilledButton.styleFrom(
              backgroundColor: context.cashier.ink,
              minimumSize: const Size(0, 34),
            ),
            child: const Text('审核通过'),
          ),
        ]);
      } else if (purchase.status == 'APPROVED') {
        actionWidgets.add(
          FilledButton(
            key: Key('inventory-purchase-receive-${purchase.id}'),
            onPressed: () => _transition(purchase, 'receive', '收货'),
            style: FilledButton.styleFrom(
              backgroundColor: context.cashier.ink,
              minimumSize: const Size(0, 34),
            ),
            child: const Text('收货'),
          ),
        );
      }
    }
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: context.cashier.subtle,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      '采购单 #${purchase.id}',
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(width: 8),
                    SettingsStatusBadge(label: badgeLabel, type: badgeType),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  '${purchase.supplierName ?? '供应商 #${purchase.supplierId}'}'
                  ' · ${purchase.warehouseName ?? '仓库 #${purchase.warehouseId}'}'
                  ' · ${purchase.itemCount} 项'
                  ' · 合计 ¥${purchase.totalAmount.toStringAsFixed(2)}',
                  style: TextStyle(
                    fontSize: 13,
                    color: context.cashier.inkSecondary,
                  ),
                ),
                if (purchase.reason != null && purchase.reason!.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      '原因：${purchase.reason}',
                      style: TextStyle(
                        fontSize: 12,
                        color: context.cashier.danger,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          ...actionWidgets,
        ],
      ),
    );
  }
}

class _TransfersSection extends StatefulWidget {
  const _TransfersSection({required this.repository, required this.canManage});

  final InventoryRepository repository;
  final bool canManage;

  @override
  State<_TransfersSection> createState() => _TransfersSectionState();
}

class _TransfersSectionState extends State<_TransfersSection> {
  late Future<List<InventoryTransfer>> _future;

  @override
  void initState() {
    super.initState();
    _future = widget.repository.listTransfers();
  }

  void _reload() => setState(() {
        _future = widget.repository.listTransfers();
      });

  Future<void> _receive(InventoryTransfer transfer) async {
    final ok = await showSettingsConfirmDialog(
      context: context,
      title: '确认收货',
      message: '调拨单 #${transfer.id} 到达目标仓后收货，将生成新的库存批次（沿用源批次号）。是否确认？',
      confirmLabel: '确认收货',
    );
    if (ok != true || !mounted) return;
    try {
      await widget.repository.receiveTransfer(id: transfer.id);
      if (!mounted) return;
      showSettingsSaved(context, '调拨单 #${transfer.id} 已收货');
      _reload();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context,
      ).showSnackBar(
        SnackBar(content: Text('收货失败：$error')));
    }
  }

  Future<void> _create() async {
    final saved = await showDialog<({int from, int to, String itemsJson, String? fefoReason})>(
      context: context,
      builder: (context) => _TransferCreateDialog(repository: widget.repository),
    );
    if (saved == null || !mounted) return;
    try {
      final items = _parseItemsJson(saved.itemsJson);
      if (items == null) throw const FormatException('明细 JSON 格式错误');
      await widget.repository.createTransfer(
        fromWarehouseId: saved.from,
        toWarehouseId: saved.to,
        items: items,
      );
      if (!mounted) return;
      showSettingsSaved(context, '调拨单已创建（在途）');
      _reload();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('创建调拨失败：$error')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<InventoryTransfer>>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return SettingsErrorState(
            message: '加载调拨单失败：${snapshot.error}',
            onRetry: _reload,
          );
        }
        if (!snapshot.hasData) {
          return const SettingsSkeletonLoader(rows: 3);
        }
        final transfers = snapshot.data!;
        return SettingsPagePadding(
          child: SettingsPanel(
            title: '调拨单',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (widget.canManage)
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton.icon(
                      key: const Key('inventory-transfer-create'),
                      onPressed: _create,
                      icon: const Icon(Icons.add_circle_outline, size: 18),
                      label: const Text('创建调拨'),
                    ),
                  ),
                if (transfers.isEmpty)
                  const SettingsEmptyState(
                    title: '暂无调拨单',
                    description: '调拨单由门店发起后在此跟踪并完成收货。',
                  )
                else
                  for (final transfer in transfers)
                    _transferRow(context, transfer),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _transferRow(BuildContext context, InventoryTransfer transfer) {
    final (badgeType, badgeLabel) =
        _transferStatusMeta[transfer.status] ??
            (StatusBadgeType.neutral, transfer.status);
    final canReceive = widget.canManage && transfer.status == 'IN_TRANSIT';
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: context.cashier.subtle,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      '调拨单 #${transfer.id}',
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(width: 8),
                    SettingsStatusBadge(label: badgeLabel, type: badgeType),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  '${transfer.fromWarehouseName ?? '仓 #${transfer.fromWarehouseId}'}'
                  ' → ${transfer.toWarehouseName ?? '仓 #${transfer.toWarehouseId}'}'
                  ' · ${transfer.materialName ?? '物料 #${transfer.materialId}'}'
                  ' × ${transfer.qty}',
                  style: TextStyle(
                    fontSize: 13,
                    color: context.cashier.inkSecondary,
                  ),
                ),
                if (transfer.batchNo != null && transfer.batchNo!.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      '批次：${transfer.batchNo}',
                      style: TextStyle(
                        fontSize: 12,
                        color: context.cashier.inkMuted,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          if (canReceive)
            FilledButton(
              key: Key('inventory-transfer-receive-${transfer.id}'),
              onPressed: () => _receive(transfer),
              style: FilledButton.styleFrom(
                backgroundColor: context.cashier.ink,
                minimumSize: const Size(0, 34),
              ),
              child: const Text('确认收货'),
            ),
        ],
      ),
    );
  }
}

class _BomSection extends StatefulWidget {
  const _BomSection({required this.repository, required this.canManage});

  final InventoryRepository repository;
  final bool canManage;

  @override
  State<_BomSection> createState() => _BomSectionState();
}

class _BomSectionState extends State<_BomSection> {
  late Future<List<InventoryBom>> _future;

  @override
  void initState() {
    super.initState();
    _future = widget.repository.listBoms();
  }

  void _reload() => setState(() {
        _future = widget.repository.listBoms();
      });

  Future<void> _activate(InventoryBom bom) async {
    final ok = await showSettingsConfirmDialog(
      context: context,
      title: '激活 BOM 版本',
      message: '激活后该版本将作为菜品的当前配方生效，同菜品的其他生效版本将转为历史版本。是否确认？',
      confirmLabel: '激活',
    );
    if (ok != true || !mounted) return;
    try {
      await widget.repository.activateBom(id: bom.id);
      if (!mounted) return;
      showSettingsSaved(context, 'BOM #${bom.id}（${bom.versionNo}）已激活');
      _reload();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context,
      ).showSnackBar(
        SnackBar(content: Text('激活失败：$error')));
    }
  }

  Future<void> _create() async {
    final saved = await showDialog<({int dishId, String itemsJson, String? effectiveFrom})>(
      context: context,
      builder: (context) => const _BomCreateDialog());
    if (saved == null || !mounted) return;
    try {
      final items = _parseItemsJson(saved.itemsJson);
      if (items == null) throw const FormatException('明细 JSON 格式错误');
      await widget.repository.createBom(
        dishId: saved.dishId,
        items: items,
        effectiveFrom: saved.effectiveFrom,
      );
      if (!mounted) return;
      showSettingsSaved(context, 'BOM 新版本已创建（草稿）');
      _reload();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('创建 BOM 失败：$error')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<InventoryBom>>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return SettingsErrorState(
            message: '加载 BOM 失败：${snapshot.error}',
            onRetry: _reload,
          );
        }
        if (!snapshot.hasData) {
          return const SettingsSkeletonLoader(rows: 3);
        }
        final boms = snapshot.data!;
        return SettingsPagePadding(
          child: SettingsPanel(
            title: 'BOM 配方版本',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (widget.canManage)
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton.icon(
                      key: const Key('inventory-bom-create'),
                      onPressed: _create,
                      icon: const Icon(Icons.add_circle_outline, size: 18),
                      label: const Text('新建配方'),
                    ),
                  ),
                if (boms.isEmpty)
                  const SettingsEmptyState(
                    title: '暂无 BOM',
                    description: '菜品配方版本管理，仅一个版本可处于生效状态。',
                  )
                else
                  for (final bom in boms) _bomRow(context, bom),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _bomRow(BuildContext context, InventoryBom bom) {
    final (badgeType, badgeLabel) =
        _bomStatusMeta[bom.status] ?? (StatusBadgeType.neutral, bom.status);
    final canActivate = widget.canManage && bom.status != 'ACTIVE';
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: context.cashier.subtle,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      '${bom.dishName ?? '菜品 #${bom.dishId}'} · ${bom.versionNo}',
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(width: 8),
                    SettingsStatusBadge(label: badgeLabel, type: badgeType),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  'BOM #${bom.id} · ${bom.itemCount} 项原料'
                  '${bom.effectiveFrom != null && bom.effectiveFrom!.isNotEmpty ? ' · 生效自 ${bom.effectiveFrom}' : ''}',
                  style: TextStyle(
                    fontSize: 13,
                    color: context.cashier.inkSecondary,
                  ),
                ),
              ],
            ),
          ),
          if (canActivate)
            FilledButton(
              key: Key('inventory-bom-activate-${bom.id}'),
              onPressed: () => _activate(bom),
              style: FilledButton.styleFrom(
                backgroundColor: context.cashier.ink,
                minimumSize: const Size(0, 34),
              ),
              child: const Text('激活'),
            ),
        ],
      ),
    );
  }
}

class _CreatePurchaseDialog extends StatefulWidget {
  const _CreatePurchaseDialog({
    required this.client,
    required this.repository});

  final AdminApiClient client;
  final InventoryRepository repository;

  @override
  State<_CreatePurchaseDialog> createState() => _CreatePurchaseDialogState();
}

class _CreatePurchaseDialogState extends State<_CreatePurchaseDialog> {
  final _formKey = GlobalKey<FormState>();
  var _supplierId = 0;
  var _warehouseId = 0;
  var _submitting = false;
  final _rows = <_PurchaseItemRow>[_PurchaseItemRow()];

  late Future<List<Map<String, Object?>>> _suppliers;
  late Future<List<Map<String, Object?>>> _warehouses;

  @override
  void initState() {
    super.initState();
    _suppliers = _loadOptions(settingsInventorySuppliersEndpoint);
    _warehouses = _loadOptions(settingsInventoryWarehousesEndpoint);
  }

  Future<List<Map<String, Object?>>> _loadOptions(AdminEndpoint endpoint,
  ) async {
    final response = await widget.client.get(endpoint);
    return extractInventoryList(response);
  }

  String _optionLabel(Map<String, Object?> row, {required bool warehouse}) {
    final name = row['name'] ??
        (warehouse ? row['warehouseName'] : row['supplierName']);
    final id = row['id'];
    return '$name（ID $id）';
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final items = <Map<String, Object?>>[];
    for (final row in _rows) {
      final materialId = int.tryParse(row.materialId.text.trim());
      final qty = double.tryParse(row.qty.text.trim());
      final price = double.tryParse(row.price.text.trim());
      if (materialId == null || qty == null || price == null || qty <= 0) {
        continue;
      }
      items.add({'materialId': materialId, 'qty': qty, 'price': price});
    }
    if (items.isEmpty || _supplierId <= 0 || _warehouseId <= 0) {
      ScaffoldMessenger.of(context,
      ).showSnackBar(
        const SnackBar(content: Text('请选择供应商/仓库，并至少填写一条有效明细')));
      return;
    }
    setState(() => _submitting = true);
    try {
      await widget.repository.createPurchase(
        supplierId: _supplierId,
        warehouseId: _warehouseId,
        items: items,
      );
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (error) {
      if (!mounted) return;
      setState(() => _submitting = false);
      ScaffoldMessenger.of(context,
      ).showSnackBar(
        SnackBar(content: Text('创建失败：$error')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('新建采购单'),
      content: SizedBox(
        width: 560,
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              FutureBuilder<List<Map<String, Object?>>>(
                future: _suppliers,
                builder: (context, snapshot) {
                  final options =
                      snapshot.data ?? const <Map<String, Object?>>[];
                  return DropdownButtonFormField<int>(
                    key: const Key('inventory-purchase-supplier'),
                    initialValue: _supplierId == 0 ? null : _supplierId,
                    decoration: const InputDecoration(
                      labelText: '供应商',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    items: [
                      for (final row in options)
                        DropdownMenuItem(
                          value:
                              row['id'] is num ? (row['id'] as num).toInt() : 0,
                          child: Text(
                            _optionLabel(row, warehouse: false),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                    ],
                    onChanged: (value) =>
                        setState(() => _supplierId = value ?? 0),
                  );
                },
              ),
              const SizedBox(height: 12),
              FutureBuilder<List<Map<String, Object?>>>(
                future: _warehouses,
                builder: (context, snapshot) {
                  final options =
                      snapshot.data ?? const <Map<String, Object?>>[];
                  return DropdownButtonFormField<int>(
                    key: const Key('inventory-purchase-warehouse'),
                    initialValue: _warehouseId == 0 ? null : _warehouseId,
                    decoration: const InputDecoration(
                      labelText: '收货仓库',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    items: [
                      for (final row in options)
                        DropdownMenuItem(
                          value:
                              row['id'] is num ? (row['id'] as num).toInt() : 0,
                          child: Text(
                            _optionLabel(row, warehouse: true),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                    ],
                    onChanged: (value) =>
                        setState(() => _warehouseId = value ?? 0),
                  );
                },
              ),
              const SizedBox(height: 14),
              Text(
                '采购明细',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: context.cashier.ink,
                ),
              ),
              const SizedBox(height: 8),
              for (var index = 0; index < _rows.length; index++)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    children: [
                      Expanded(
                        child: TextFormField(
                          key: ValueKey('inventory-purchase-row-$index-material',
                          ),
                          controller: _rows[index].materialId,
                          decoration: const InputDecoration(
                            labelText: '原料ID',
                            border: OutlineInputBorder(),
                            isDense: true,
                          ),
                          keyboardType: TextInputType.number,
                          validator: (value) =>
                              int.tryParse(value?.trim() ?? '') == null
                                  ? '请输入原料ID'
                                  : null,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextFormField(
                          key: ValueKey('inventory-purchase-row-$index-qty'),
                          controller: _rows[index].qty,
                          decoration: const InputDecoration(
                            labelText: '数量',
                            border: OutlineInputBorder(),
                            isDense: true,
                          ),
                          keyboardType: const TextInputType.numberWithOptions(
                              decimal: true,
                          ),
                          validator: (value) =>
                              (double.tryParse(value?.trim() ?? '') ?? 0) <= 0
                                  ? '数量需大于 0'
                                  : null,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextFormField(
                          key: ValueKey('inventory-purchase-row-$index-price'),
                          controller: _rows[index].price,
                          decoration: const InputDecoration(
                            labelText: '单价',
                            border: OutlineInputBorder(),
                            isDense: true,
                          ),
                          keyboardType: const TextInputType.numberWithOptions(
                              decimal: true,
                          ),
                          validator: (value) =>
                              double.tryParse(value?.trim() ?? '') == null
                                  ? '请输入单价'
                                  : null,
                        ),
                      ),
                      const SizedBox(width: 8),
                      IconButton(
                        onPressed: _rows.length == 1
                            ? null
                            : () => setState(() => _rows.removeAt(index)),
                        icon: const Icon(Icons.remove_circle_outline),
                      ),
                    ],
                  ),
                ),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: () =>
                      setState(() => _rows.add(_PurchaseItemRow())),
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('添加明细行'),
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _submitting ? null : () => Navigator.of(context).pop(false),
          child: const Text('取消'),
        ),
        FilledButton(
          key: const Key('inventory-purchase-submit'),
          onPressed: _submitting ? null : _submit,
          style: FilledButton.styleFrom(
            backgroundColor: context.cashier.ink),
          child: _submitting
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('创建（待审核）'),
        ),
      ],
    );
  }
}

class _PurchaseItemRow {
  final TextEditingController materialId = TextEditingController();
  final TextEditingController qty = TextEditingController();
  final TextEditingController price = TextEditingController();
}

Future<String> _promptReason(BuildContext context, String title) async {
  final controller = TextEditingController();
  final value = await showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: TextField(
        controller: controller,
        autofocus: true,
        decoration: const InputDecoration(
          hintText: '请输入原因（必填）',
          border: OutlineInputBorder(),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(''),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(controller.text.trim()),
          style: FilledButton.styleFrom(backgroundColor: context.cashier.ink),
          child: const Text('确认'),
        ),
      ],
    ),
  );
  return value ?? '';
}

/// 供应商分区：列表 + 新增/编辑/删除（完整 CRUD）。
class _SuppliersSection extends StatefulWidget {
  const _SuppliersSection({required this.repository, required this.canManage});

  final InventoryRepository repository;
  final bool canManage;

  @override
  State<_SuppliersSection> createState() => _SuppliersSectionState();
}

class _SuppliersSectionState extends State<_SuppliersSection> {
  late Future<List<InventorySupplier>> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<List<InventorySupplier>> _load() =>
      widget.repository.listSuppliers();

  void _reload() => setState(() => _future = _load());

  Future<void> _openForm(InventorySupplier? existing) async {
    final saved = await showDialog<InventorySupplier>(
      context: context,
      builder: (context) => _SupplierFormDialog(initial: existing),
    );
    if (saved == null || !mounted) return;
    try {
      if (existing == null) {
        await widget.repository.addSupplier(saved);
        showSettingsSaved(context, '供应商已新增');
      } else {
        await widget.repository.updateSupplier(saved);
        showSettingsSaved(context, '供应商已更新');
      }
      _reload();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('保存失败：$error')));
    }
  }

  Future<void> _delete(InventorySupplier supplier) async {
    final confirmed = await showSettingsConfirmDialog(
      context: context,
      title: '删除供应商',
      message: '删除「${supplier.name}」？历史采购单仍保留供应商快照。',
      destructive: true,
      confirmLabel: '删除',
    );
    if (confirmed != true || !mounted) return;
    try {
      await widget.repository.deleteSupplier(id: supplier.id);
      if (!mounted) return;
      showSettingsSaved(context, '供应商已删除');
      _reload();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('删除失败：$error')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<InventorySupplier>>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return SettingsErrorState(
            message: '加载供应商失败：${snapshot.error}',
            onRetry: _reload,
          );
        }
        if (!snapshot.hasData) {
          return const SettingsSkeletonLoader(rows: 3);
        }
        final suppliers = snapshot.data!;
        return SettingsPagePadding(
          child: SettingsPanel(
            title: '供应商',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (widget.canManage)
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton.icon(
                      key: const Key('inventory-supplier-add'),
                      onPressed: () => _openForm(null),
                      icon: const Icon(Icons.add_circle_outline, size: 18),
                      label: const Text('新增供应商'),
                    ),
                  ),
                if (suppliers.isEmpty)
                  const SettingsEmptyState(
                    title: '暂无供应商',
                    description: '新增供应商后可在采购单中选择。',
                  )
                else
                  for (final supplier in suppliers)
                    Container(
                      margin: const EdgeInsets.only(bottom: 10),
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: context.cashier.subtle,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  supplier.name,
                                  style: const TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  '#${supplier.id}'
                                  '${supplier.contactName != null ? ' · ${supplier.contactName}' : ''}'
                                  '${supplier.contactPhone != null ? ' · ${supplier.contactPhone}' : ''}'
                                  '${supplier.supplyScope != null && supplier.supplyScope!.isNotEmpty ? ' · ${supplier.supplyScope}' : ''}',
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: context.cashier.inkSecondary,
                                  ),
                                ),
                                if (supplier.settlementInfo != null &&
                                    supplier.settlementInfo!.isNotEmpty)
                                  Padding(
                                    padding: const EdgeInsets.only(top: 4),
                                    child: Text(
                                      '结算：${supplier.settlementInfo}',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: context.cashier.inkMuted,
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                          if (widget.canManage) ...[
                            TextButton(
                              key: Key('inventory-supplier-edit-${supplier.id}',
                              ),
                              onPressed: () => _openForm(supplier),
                              child: const Text('编辑'),
                            ),
                            TextButton(
                              key: Key('inventory-supplier-delete-${supplier.id}',
                              ),
                              onPressed: () => _delete(supplier),
                              child: Text(
                                '删除',
                                style: TextStyle(color: context.cashier.danger),
                              ),
                            ),
                          ],
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
}

class _SupplierFormDialog extends StatefulWidget {
  const _SupplierFormDialog({this.initial});

  final InventorySupplier? initial;

  @override
  State<_SupplierFormDialog> createState() => _SupplierFormDialogState();
}

class _SupplierFormDialogState extends State<_SupplierFormDialog> {
  late final TextEditingController _name;
  late final TextEditingController _contactName;
  late final TextEditingController _contactPhone;
  late final TextEditingController _supplyScope;
  late final TextEditingController _settlementInfo;
  String? _error;

  @override
  void initState() {
    super.initState();
    final initial = widget.initial;
    _name = TextEditingController(text: initial?.name ?? '');
    _contactName = TextEditingController(text: initial?.contactName ?? '');
    _contactPhone = TextEditingController(text: initial?.contactPhone ?? '');
    _supplyScope = TextEditingController(text: initial?.supplyScope ?? '');
    _settlementInfo =
        TextEditingController(text: initial?.settlementInfo ?? '',
    );
  }

  @override
  void dispose() {
    _name.dispose();
    _contactName.dispose();
    _contactPhone.dispose();
    _supplyScope.dispose();
    _settlementInfo.dispose();
    super.dispose();
  }

  void _submit() {
    final name = _name.text.trim();
    if (name.isEmpty) {
      setState(() => _error = '请填写供应商名称');
      return;
    }
    final initial = widget.initial;
    Navigator.of(context).pop(
      InventorySupplier(
        id: initial?.id ?? 0,
        name: name,
        contactName: _contactName.text.trim().isEmpty
            ? null
            : _contactName.text.trim(),
        contactPhone: _contactPhone.text.trim().isEmpty
            ? null
            : _contactPhone.text.trim(),
        supplyScope: _supplyScope.text.trim().isEmpty
            ? null
            : _supplyScope.text.trim(),
        settlementInfo: _settlementInfo.text.trim().isEmpty
            ? null
            : _settlementInfo.text.trim(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.initial == null ? '新增供应商' : '编辑供应商'),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                key: const Key('inventory-supplier-form-name'),
                controller: _name,
                decoration: const InputDecoration(
                  labelText: '名称 *',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _contactName,
                      decoration: const InputDecoration(
                        labelText: '联系人',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextField(
                      controller: _contactPhone,
                      decoration: const InputDecoration(
                        labelText: '联系电话',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _supplyScope,
                decoration: const InputDecoration(
                  labelText: '供货范围',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _settlementInfo,
                decoration: const InputDecoration(
                  labelText: '结算信息（仅库存管理权限可见）',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
              if (_error != null) ...[
                const SizedBox(height: 10),
                Text(
                  _error!,
                  style: TextStyle(color: context.cashier.danger)),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        TextButton(
          key: const Key('inventory-supplier-form-submit'),
          onPressed: _submit,
          child: Text(widget.initial == null ? '创建' : '保存'),
        ),
      ],
    );
  }
}

/// 仓库分区：列表 + 新增/编辑（openapi 未定义删除端点）。
class _WarehousesSection extends StatefulWidget {
  const _WarehousesSection({
    required this.repository,
    required this.canManage});

  final InventoryRepository repository;
  final bool canManage;

  @override
  State<_WarehousesSection> createState() => _WarehousesSectionState();
}

class _WarehousesSectionState extends State<_WarehousesSection> {
  late Future<List<InventoryWarehouse>> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<List<InventoryWarehouse>> _load() =>
      widget.repository.listWarehouses();

  void _reload() => setState(() => _future = _load());

  Future<void> _openForm(InventoryWarehouse? existing) async {
    final saved = await showDialog<InventoryWarehouse>(
      context: context,
      builder: (context) => _WarehouseFormDialog(initial: existing),
    );
    if (saved == null || !mounted) return;
    try {
      if (existing == null) {
        await widget.repository.addWarehouse(saved);
        showSettingsSaved(context, '仓库已新增');
      } else {
        await widget.repository.updateWarehouse(saved);
        showSettingsSaved(context, '仓库已更新');
      }
      _reload();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('保存失败：$error')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<InventoryWarehouse>>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return SettingsErrorState(
            message: '加载仓库失败：${snapshot.error}',
            onRetry: _reload,
          );
        }
        if (!snapshot.hasData) {
          return const SettingsSkeletonLoader(rows: 3);
        }
        final warehouses = snapshot.data!;
        return SettingsPagePadding(
          child: SettingsPanel(
            title: '仓库',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (widget.canManage)
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton.icon(
                      key: const Key('inventory-warehouse-add'),
                      onPressed: () => _openForm(null),
                      icon: const Icon(Icons.add_circle_outline, size: 18),
                      label: const Text('新增仓库'),
                    ),
                  ),
                if (warehouses.isEmpty)
                  const SettingsEmptyState(
                    title: '暂无仓库',
                    description: '新增仓库后可用于采购与调拨。',
                  )
                else
                  for (final warehouse in warehouses)
                    Container(
                      margin: const EdgeInsets.only(bottom: 10),
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: context.cashier.subtle,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  warehouse.name,
                                  style: const TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  '#${warehouse.id}'
                                  ' · 主体 ${warehouse.legalEntity}'
                                  '${warehouse.address != null && warehouse.address!.isNotEmpty ? ' · ${warehouse.address}' : ''}',
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: context.cashier.inkSecondary,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          if (widget.canManage)
                            TextButton(
                              key: Key(
                                'inventory-warehouse-edit-${warehouse.id}',
                              ),
                              onPressed: () => _openForm(warehouse),
                              child: const Text('编辑'),
                            ),
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
}

class _WarehouseFormDialog extends StatefulWidget {
  const _WarehouseFormDialog({this.initial});

  final InventoryWarehouse? initial;

  @override
  State<_WarehouseFormDialog> createState() => _WarehouseFormDialogState();
}

class _WarehouseFormDialogState extends State<_WarehouseFormDialog> {
  late final TextEditingController _name;
  late final TextEditingController _legalEntity;
  late final TextEditingController _address;
  String? _error;

  @override
  void initState() {
    super.initState();
    final initial = widget.initial;
    _name = TextEditingController(text: initial?.name ?? '');
    _legalEntity = TextEditingController(text: initial?.legalEntity ?? '');
    _address = TextEditingController(text: initial?.address ?? '');
  }

  @override
  void dispose() {
    _name.dispose();
    _legalEntity.dispose();
    _address.dispose();
    super.dispose();
  }

  void _submit() {
    if (_name.text.trim().isEmpty || _legalEntity.text.trim().isEmpty) {
      setState(() => _error = '名称与经营主体必填');
      return;
    }
    final initial = widget.initial;
    Navigator.of(context).pop(
      InventoryWarehouse(
        id: initial?.id ?? 0,
        name: _name.text.trim(),
        legalEntity: _legalEntity.text.trim(),
        address: _address.text.trim().isEmpty ? null : _address.text.trim(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.initial == null ? '新增仓库' : '编辑仓库'),
      content: SizedBox(
        width: 520,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              key: const Key('inventory-warehouse-form-name'),
              controller: _name,
              decoration: const InputDecoration(
                labelText: '名称 *',
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              key: const Key('inventory-warehouse-form-entity'),
              controller: _legalEntity,
              decoration: const InputDecoration(
                labelText: '经营主体 *（调拨禁止跨主体）',
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _address,
              decoration: const InputDecoration(
                labelText: '地址',
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 10),
              Text(
                _error!,
                style: TextStyle(color: context.cashier.danger)),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        TextButton(
          key: const Key('inventory-warehouse-form-submit'),
          onPressed: _submit,
          child: Text(widget.initial == null ? '创建' : '保存'),
        ),
      ],
    );
  }
}

/// 创建调拨单弹窗：源/目标仓下拉（加载仓库列表）+ 明细 JSON。
class _TransferCreateDialog extends StatefulWidget {
  const _TransferCreateDialog({required this.repository});

  final InventoryRepository repository;

  @override
  State<_TransferCreateDialog> createState() => _TransferCreateDialogState();
}

class _TransferCreateDialogState extends State<_TransferCreateDialog> {
  final _items = TextEditingController();
  final _fefoReason = TextEditingController();
  int? _from;
  int? _to;
  String? _error;
  bool _loading = true;
  List<InventoryWarehouse> _warehouses = const [];

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    try {
      final warehouses = await widget.repository.listWarehouses();
      if (!mounted) return;
      setState(() {
        _warehouses = warehouses;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = '加载仓库失败：$error';
        _loading = false;
      });
    }
  }

  @override
  void dispose() {
    _items.dispose();
    _fefoReason.dispose();
    super.dispose();
  }

  void _submit() {
    if (_from == null || _to == null) {
      setState(() => _error = '请选择源仓库与目标仓库');
      return;
    }
    if (_items.text.trim().isEmpty) {
      setState(() => _error = '请填写调拨明细 JSON');
      return;
    }
    final parsed = _parseItemsJson(_items.text);
    if (parsed == null) {
      setState(() => _error = '明细 JSON 格式错误，应为 [{batchId,materialId,qty}] 数组');
      return;
    }
    Navigator.of(context).pop((
      from: _from!,
      to: _to!,
      itemsJson: _items.text.trim(),
      fefoReason: _fefoReason.text.trim().isEmpty
          ? null
          : _fefoReason.text.trim(),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('创建调拨单'),
      content: SizedBox(
        width: 560,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (_loading)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 16),
                  child: Center(child: CircularProgressIndicator()),
                )
              else ...[
                DropdownButtonFormField<int?>(
                  key: const Key('inventory-transfer-form-from'),
                  initialValue: _from,
                  decoration: const InputDecoration(
                    labelText: '源仓库 *',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  items: [
                    for (final warehouse in _warehouses)
                      DropdownMenuItem(
                        value: warehouse.id,
                        child: Text(
                          '${warehouse.name}（#${warehouse.id} · ${warehouse.legalEntity}）',
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                  ],
                  onChanged: (value) => setState(() => _from = value),
                ),
                const SizedBox(height: 10),
                DropdownButtonFormField<int?>(
                  key: const Key('inventory-transfer-form-to'),
                  initialValue: _to,
                  decoration: const InputDecoration(
                    labelText: '目标仓库 *（禁止跨经营主体）',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  items: [
                    for (final warehouse in _warehouses)
                      DropdownMenuItem(
                        value: warehouse.id,
                        child: Text(
                          '${warehouse.name}（#${warehouse.id} · ${warehouse.legalEntity}）',
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                  ],
                  onChanged: (value) => setState(() => _to = value),
                ),
                const SizedBox(height: 10),
                TextField(
                  key: const Key('inventory-transfer-form-items'),
                  controller: _items,
                  maxLines: 4,
                  decoration: const InputDecoration(
                    labelText: '明细 JSON *（[{"batchId":1,"materialId":2,"qty":5}]）',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _fefoReason,
                  decoration: const InputDecoration(
                    labelText: '跳过 FEFO 原因（默认按最早到期批次扣减，可空）',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
              ],
              if (_error != null) ...[
                const SizedBox(height: 10),
                Text(
                  _error!,
                  style: TextStyle(color: context.cashier.danger)),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        TextButton(
          key: const Key('inventory-transfer-form-submit'),
          onPressed: _loading ? null : _submit,
          child: const Text('创建'),
        ),
      ],
    );
  }
}

/// 解析调拨明细 JSON 数组（batchId/materialId/qty 必填）；失败返回 null。
List<Map<String, Object?>>? _parseItemsJson(String raw) {
  try {
    final decoded = jsonDecode(raw);
    if (decoded is! List) return null;
    final items = <Map<String, Object?>>[];
    for (final row in decoded) {
      if (row is! Map) return null;
      final map = row.cast<String, Object?>();
      if (map['batchId'] == null || map['materialId'] == null ||
          map['qty'] == null) {
        return null;
      }
      items.add(map);
    }
    return items;
  } catch (_) {
    return null;
  }
}

/// 解析 BOM 配方明细 JSON 数组（materialId/qty 必填，unit/alternates 可选）。
List<Map<String, Object?>>? _parseBomItemsJson(String raw) {
  try {
    final decoded = jsonDecode(raw);
    if (decoded is! List) return null;
    final items = <Map<String, Object?>>[];
    for (final row in decoded) {
      if (row is! Map) return null;
      final map = row.cast<String, Object?>();
      if (map['materialId'] == null || map['qty'] == null) return null;
      items.add(map);
    }
    return items;
  } catch (_) {
    return null;
  }
}

/// 新建 BOM 版本弹窗：菜品 ID + 配方明细 JSON + 生效时间。
class _BomCreateDialog extends StatefulWidget {
  const _BomCreateDialog();

  @override
  State<_BomCreateDialog> createState() => _BomCreateDialogState();
}

class _BomCreateDialogState extends State<_BomCreateDialog> {
  final _dishId = TextEditingController();
  final _items = TextEditingController();
  final _effectiveFrom = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _dishId.dispose();
    _items.dispose();
    _effectiveFrom.dispose();
    super.dispose();
  }

  void _submit() {
    final dishId = int.tryParse(_dishId.text.trim());
    if (dishId == null) {
      setState(() => _error = '菜品 ID 需为整数');
      return;
    }
    if (_items.text.trim().isEmpty) {
      setState(() => _error = '请填写配方明细 JSON');
      return;
    }
    final parsed = _parseBomItemsJson(_items.text);
    if (parsed == null) {
      setState(() => _error = '明细 JSON 格式错误，应为 [{"materialId":1,"qty":2,"unit":"kg","alternates":[2]}] 数组',
      );
      return;
    }
    Navigator.of(context).pop((
      dishId: dishId,
      itemsJson: _items.text.trim(),
      effectiveFrom: _effectiveFrom.text.trim().isEmpty
          ? null
          : _effectiveFrom.text.trim(),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('新建 BOM 配方'),
      content: SizedBox(
        width: 560,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              key: const Key('inventory-bom-form-dish'),
              controller: _dishId,
              decoration: const InputDecoration(
                labelText: '菜品 ID *',
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              key: const Key('inventory-bom-form-items'),
              controller: _items,
              maxLines: 4,
              decoration: const InputDecoration(
                labelText: '配方明细 JSON *（[{"materialId":1,"qty":2,"unit":"kg"}]）',
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _effectiveFrom,
              decoration: const InputDecoration(
                labelText: '生效时间（yyyy-MM-dd HH:mm:ss，可空）',
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 10),
              Text(
                _error!,
                style: TextStyle(color: context.cashier.danger)),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        TextButton(
          key: const Key('inventory-bom-form-submit'),
          onPressed: _submit,
          child: const Text('创建'),
        ),
      ],
    );
  }
}
class _BatchesSection extends StatefulWidget {
  const _BatchesSection({required this.repository, required this.canManage});

  final InventoryRepository repository;
  final bool canManage;

  @override
  State<_BatchesSection> createState() => _BatchesSectionState();
}

class _BatchesSectionState extends State<_BatchesSection> {
  late Future<List<InventoryBatch>> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<List<InventoryBatch>> _load() => widget.repository.listBatches();

  void _reload() => setState(() => _future = _load());

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<InventoryBatch>>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return SettingsErrorState(
            message: '加载批次失败：${snapshot.error}',
            onRetry: _reload,
          );
        }
        if (!snapshot.hasData) {
          return const SettingsSkeletonLoader(rows: 3);
        }
        final batches = snapshot.data!;
        return SettingsPagePadding(
          child: SettingsPanel(
            title: '库存批次（FEFO 建议）',
            child: batches.isEmpty
                ? const SettingsEmptyState(
                    title: '暂无批次',
                    description: '采购收货后生成库存批次。',
                  )
                : Column(
                    children: [
                      for (final batch in batches)
                        Container(
                          margin: const EdgeInsets.only(bottom: 10),
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: context.cashier.subtle,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '批次 ${batch.batchNo ?? '#${batch.id}'}'
                                '${batch.materialName != null ? ' · ${batch.materialName}' : ''}',
                                style: const TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                '物料 #${batch.materialId ?? '-'} · 仓 #${batch.warehouseId ?? '-'}'
                                ' · 数量 ${batch.qty.toStringAsFixed(2)}'
                                '${batch.available != null ? '（可用 ${batch.available!.toStringAsFixed(2)}）' : ''}'
                                '${batch.expiryDate != null ? ' · 到期 ${batch.expiryDate}' : ''}',
                                style: TextStyle(
                                  fontSize: 13,
                                  color: context.cashier.inkSecondary,
                                ),
                              ),
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
}
