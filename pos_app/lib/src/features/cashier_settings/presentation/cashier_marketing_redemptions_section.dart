import 'package:flutter/material.dart';

import '../data/marketing_repository.dart';
import '../domain/cashier_settings.dart';
import 'cashier_settings_shared.dart';

/// Read-only history: cancellation/refund restores eligibility on the server.
class CashierMarketingRedemptionsSection extends StatefulWidget {
  const CashierMarketingRedemptionsSection({
    super.key,
    required this.repository,
  });
  final MarketingRepository repository;

  @override
  State<CashierMarketingRedemptionsSection> createState() =>
      _RedemptionsState();
}

class _RedemptionsState extends State<CashierMarketingRedemptionsSection> {
  final _form = GlobalKey<FormState>();
  final _campaign = TextEditingController();
  final _customer = TextEditingController();
  final _order = TextEditingController();
  int? _campaignId;
  String _customerId = '', _orderNo = '';
  int _page = 1;
  late Future<CashierSettingsSectionData> _result;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(CashierMarketingRedemptionsSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.repository != widget.repository) _load();
  }

  void _load() {
    _result = widget.repository.loadRedemptions(
      campaignId: _campaignId,
      customerId: _customerId,
      orderNo: _orderNo,
      page: _page,
    );
  }

  void _search() {
    if (!_form.currentState!.validate()) return;
    setState(() {
      _campaignId = int.tryParse(_campaign.text.trim());
      _customerId = _customer.text.trim();
      _orderNo = _order.text.trim();
      _page = 1;
      _load();
    });
  }

  @override
  void dispose() {
    _campaign.dispose();
    _customer.dispose();
    _order.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.all(20),
    children: [
      SettingsPanel(
        title: '首单核销记录',
        child: Form(
          key: _form,
          child: Wrap(
            spacing: 12,
            runSpacing: 12,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              SizedBox(
                width: 180,
                child: TextFormField(
                  controller: _campaign,
                  decoration: const InputDecoration(
                    labelText: '活动编号',
                    isDense: true,
                    border: OutlineInputBorder(),
                  ),
                  keyboardType: TextInputType.number,
                  validator: (value) =>
                      value!.trim().isEmpty ||
                          (int.tryParse(value.trim()) ?? 0) > 0
                      ? null
                      : '请输入正整数编号',
                ),
              ),
              SizedBox(
                width: 180,
                child: TextFormField(
                  controller: _customer,
                  decoration: const InputDecoration(
                    labelText: '客户编号',
                    isDense: true,
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
              SizedBox(
                width: 220,
                child: TextFormField(
                  controller: _order,
                  decoration: const InputDecoration(
                    labelText: '订单号',
                    isDense: true,
                    border: OutlineInputBorder(),
                  ),
                  onFieldSubmitted: (_) => _search(),
                ),
              ),
              FilledButton.icon(
                onPressed: _search,
                icon: const Icon(Icons.search),
                label: const Text('查询'),
              ),
            ],
          ),
        ),
      ),
      const SizedBox(height: 16),
      FutureBuilder<CashierSettingsSectionData>(
        future: _result,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done)
            return const SettingsSkeletonLoader(rows: 4);
          if (snapshot.hasError)
            return SettingsErrorState(
              message: '核销记录加载失败：${snapshot.error}',
              onRetry: () => setState(_load),
            );
          final data = snapshot.data!;
          return SettingsPanel(
            title: '查询结果 · ${data.total} 条',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (data.items.isEmpty)
                  const SettingsEmptyState(
                    title: '暂无核销记录',
                    description: '可调整活动、客户或订单条件后重新查询。',
                  )
                else
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: DataTable(
                      columns: [
                        for (final label in [
                          '订单号',
                          '活动编号',
                          '客户编号',
                          '优惠金额（元）',
                          '状态',
                          '恢复原因',
                          '核销时间',
                        ])
                          DataColumn(label: Text(label)),
                      ],
                      rows: data.items
                          .map(
                            (row) => DataRow(
                              cells: [
                                for (final key in [
                                  'orderNo',
                                  'campaignId',
                                  'customerId',
                                  'amount',
                                ])
                                  DataCell(Text('${row[key] ?? "—"}')),
                                DataCell(
                                  SettingsStatusBadge(
                                    label: row['status'] == 'USED'
                                        ? '已核销'
                                        : row['status'] == 'RESTORED'
                                        ? '资格已恢复'
                                        : '${row['status'] ?? "—"}',
                                    type: row['status'] == 'USED'
                                        ? StatusBadgeType.success
                                        : StatusBadgeType.neutral,
                                  ),
                                ),
                                DataCell(
                                  Text('${row['restoredReason'] ?? "—"}'),
                                ),
                                DataCell(Text('${row['createdAt'] ?? "—"}')),
                              ],
                            ),
                          )
                          .toList(),
                    ),
                  ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 12,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text('第 ${data.page} 页'),
                    OutlinedButton(
                      onPressed: data.page > 1
                          ? () => setState(() {
                              _page = data.page - 1;
                              _load();
                            })
                          : null,
                      child: const Text('上一页'),
                    ),
                    OutlinedButton(
                      onPressed: data.page * data.pageSize < data.total
                          ? () => setState(() {
                              _page = data.page + 1;
                              _load();
                            })
                          : null,
                      child: const Text('下一页'),
                    ),
                  ],
                ),
              ],
            ),
          );
        },
      ),
    ],
  );
}
