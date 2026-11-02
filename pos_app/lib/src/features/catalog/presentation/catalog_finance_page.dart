import 'package:flutter/material.dart';

import '../../../core/app_state.dart';
import '../../../core/formatters.dart';
import '../../reports/data/report_repository.dart';
import '../../reports/domain/dashboard_report.dart';
import '../data/catalog_repository.dart';
import '../domain/catalog_models.dart';

class CatalogFinancePage extends StatefulWidget {
  const CatalogFinancePage({
    super.key,
    required this.appState,
    required this.repository,
    required this.reportRepository,
  });

  final AppState appState;
  final CatalogRepository repository;
  final ReportRepository reportRepository;

  @override
  State<CatalogFinancePage> createState() => _CatalogFinancePageState();
}

class _CatalogFinancePageState extends State<CatalogFinancePage> {
  final dishIdController = TextEditingController();
  DishShopStock? stock;
  DashboardReport? report;
  bool loading = false;
  String? error;

  @override
  void initState() {
    super.initState();
    _loadReport();
  }

  @override
  void didUpdateWidget(covariant CatalogFinancePage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.appState.currentShopId != widget.appState.currentShopId) {
      stock = null;
      _loadReport();
    }
  }

  @override
  void dispose() {
    dishIdController.dispose();
    super.dispose();
  }

  Future<void> _loadReport() async {
    final shopId = widget.appState.currentShopId;
    if (shopId == null) return;
    try {
      final next = await widget.reportRepository.loadDashboard(shopId: shopId);
      if (mounted) setState(() => report = next);
    } catch (_) {
      if (mounted) setState(() => report = null);
    }
  }

  Future<void> _loadStock() async {
    final shopId = widget.appState.currentShopId;
    final dishId = int.tryParse(dishIdController.text.trim());
    if (shopId == null || dishId == null) {
      setState(() => error = '请输入有效菜品 ID');
      return;
    }
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final next = await widget.repository.loadDishStock(
        dishId: dishId,
        shopId: shopId,
      );
      if (mounted) setState(() => stock = next);
    } catch (e) {
      if (mounted) setState(() => error = '$e');
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> _updateOnSale(bool value) async {
    final current = stock;
    if (current == null) return;
    final next = await widget.repository.updateOnSale(
      stock: current,
      onsale: value,
    );
    if (mounted) setState(() => stock = next);
  }

  Future<void> _updateSoldOut(bool value) async {
    final current = stock;
    if (current == null) return;
    final next = await widget.repository.updateSoldOut(
      stock: current,
      soldOut: value,
    );
    if (mounted) setState(() => stock = next);
  }

  @override
  Widget build(BuildContext context) {
    final current = stock;
    return ListView(
      children: [
        Wrap(
          spacing: 12,
          runSpacing: 12,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            SizedBox(
              width: 180,
              child: TextField(
                controller: dishIdController,
                decoration: const InputDecoration(labelText: '菜品 ID'),
                keyboardType: TextInputType.number,
                onSubmitted: (_) => _loadStock(),
              ),
            ),
            FilledButton.icon(
              onPressed: loading ? null : _loadStock,
              icon: const Icon(Icons.search),
              label: const Text('查询门店库存'),
            ),
            if (loading) const CircularProgressIndicator(),
          ],
        ),
        if (error != null) ...[
          const SizedBox(height: 12),
          Text(
            error!,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        ],
        const SizedBox(height: 16),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            _InfoCard(
              title: '营业净额',
              value: report == null ? '-' : money(report!.businessRevenueNet),
            ),
            _InfoCard(
              title: '菜品库存',
              value: current == null ? '-' : '${current.stock}',
            ),
            _InfoCard(
              title: '上下架',
              value: current == null
                  ? '-'
                  : current.onsale
                  ? '上架'
                  : '下架',
            ),
            _InfoCard(
              title: '售罄',
              value: current == null
                  ? '-'
                  : current.soldOut
                  ? '已售罄'
                  : '可售',
            ),
          ],
        ),
        const SizedBox(height: 16),
        if (current != null)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Wrap(
                spacing: 12,
                runSpacing: 12,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text('当前门店 ${current.shopId} / 菜品 ${current.dishId}'),
                  OutlinedButton(
                    onPressed: () => _updateOnSale(!current.onsale),
                    child: Text(current.onsale ? '下架' : '上架'),
                  ),
                  OutlinedButton(
                    onPressed: () => _updateSoldOut(!current.soldOut),
                    child: Text(current.soldOut ? '取消售罄' : '设为售罄'),
                  ),
                ],
              ),
            ),
          ),
        const Card(
          child: Padding(
            padding: EdgeInsets.all(16),
            child: Text('菜品库存读写 t_dish_shop 门店维度；上下架不误改售罄，售罄不误改上下架。'),
          ),
        ),
      ],
    );
  }
}

class _InfoCard extends StatelessWidget {
  const _InfoCard({required this.title, required this.value});

  final String title;
  final String value;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 220,
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: Theme.of(context).textTheme.labelLarge),
              const SizedBox(height: 10),
              Text(value, style: Theme.of(context).textTheme.headlineSmall),
            ],
          ),
        ),
      ),
    );
  }
}
