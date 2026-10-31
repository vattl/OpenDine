import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/admin_api_client.dart';
import '../../../core/api_contract.dart';
import '../../../core/app_state.dart';

class ApiModuleAction {
  const ApiModuleAction({
    required this.label,
    required this.endpoint,
    this.defaultBody = const {},
    this.defaultQuery = const {},
  });

  final String label;
  final AdminEndpoint endpoint;
  final Map<String, Object?> defaultBody;
  final Map<String, Object?> defaultQuery;
}

class ApiModulePage extends StatefulWidget {
  const ApiModulePage({
    super.key,
    required this.title,
    required this.description,
    required this.appState,
    required this.client,
    required this.actions,
  }) : currentShopId = null,
       storeName = null;

  const ApiModulePage.scoped({
    super.key,
    required this.title,
    required this.description,
    required this.currentShopId,
    required this.storeName,
    required this.client,
    required this.actions,
  }) : appState = null;

  final String title;
  final String description;
  final AppState? appState;
  final int? currentShopId;
  final String? storeName;
  final AdminApiClient client;
  final List<ApiModuleAction> actions;

  int? get effectiveShopId => appState?.currentShopId ?? currentShopId;

  String get effectiveStoreName =>
      appState?.currentShop?.name ?? storeName ?? '未选择门店';

  @override
  State<ApiModulePage> createState() => _ApiModulePageState();
}

class _ApiModulePageState extends State<ApiModulePage> {
  final keywordController = TextEditingController();
  final pageController = TextEditingController(text: '1');
  final sizeController = TextEditingController(text: '20');
  late ApiModuleAction selected = widget.actions.first;
  late final queryController = TextEditingController(
    text: _pretty(selected.defaultQuery),
  );
  late final bodyController = TextEditingController(
    text: _pretty(selected.defaultBody),
  );
  Object? data;
  bool loading = false;
  String? error;

  @override
  void initState() {
    super.initState();
    _applyQuickFilters();
    _load();
  }

  @override
  void didUpdateWidget(covariant ApiModulePage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.effectiveShopId != widget.effectiveShopId) {
      _load();
    }
  }

  @override
  void dispose() {
    keywordController.dispose();
    pageController.dispose();
    sizeController.dispose();
    queryController.dispose();
    bodyController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final shopId = widget.effectiveShopId;
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final scoped = widget.client.copyWith(shopId: shopId);
      final query = _decodeObject(queryController.text);
      final body = _decodeObject(bodyController.text);
      final resolved = _resolveEndpoint(selected.endpoint, query, body);
      final result = await scoped.request(resolved, query: query, body: body);
      if (mounted) setState(() => data = result);
    } catch (e) {
      if (mounted) setState(() => error = '$e');
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  void _select(ApiModuleAction action) {
    setState(() {
      selected = action;
      queryController.text = _pretty(action.defaultQuery);
      bodyController.text = _pretty(action.defaultBody);
      pageController.text = '1';
      sizeController.text =
          '${action.endpoint.pageSizeLimit == null ? 20 : 20}';
      keywordController.clear();
      data = null;
      error = null;
    });
    _applyQuickFilters();
    _load();
  }

  void _applyQuickFilters() {
    final query = _decodeObject(queryController.text);
    final body = _decodeObject(bodyController.text);
    final target = selected.endpoint.method == 'GET' ? query : body;
    final keyword = keywordController.text.trim();

    if (selected.endpoint.pageSizeLimit != null) {
      final page = int.tryParse(pageController.text.trim()) ?? 1;
      final rawSize = int.tryParse(sizeController.text.trim()) ?? 20;
      final limit = selected.endpoint.pageSizeLimit ?? 100;
      final pageSize = rawSize > limit ? limit : rawSize;
      target['pageNum'] = page < 1 ? 1 : page;
      target['pageSize'] = pageSize < 1 ? 20 : pageSize;
    }
    if (keyword.isEmpty) {
      target.remove('keyword');
      target.remove('query');
      target.remove('name');
    } else {
      target['keyword'] = keyword;
      target['query'] = keyword;
    }

    queryController.text = _pretty(query);
    bodyController.text = _pretty(body);
  }

  void _quickSearch() {
    pageController.text = '1';
    _applyQuickFilters();
    _load();
  }

  void _turnPage(int delta) {
    final current = int.tryParse(pageController.text.trim()) ?? 1;
    final next = current + delta;
    if (next < 1) return;
    pageController.text = '$next';
    _applyQuickFilters();
    _load();
  }

  Future<void> _copyResponse() async {
    await Clipboard.setData(ClipboardData(text: _prettyObject(data)));
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('已复制响应 JSON')));
  }

  void _fillQuery(Map<String, Object?> row) {
    final id =
        row['id'] ?? row['orderId'] ?? row['order_id'] ?? row['order_no'];
    final next = <String, Object?>{
      if (id != null) 'id': id,
      if (row['order_no'] != null) 'order_no': row['order_no'],
      if (row['openid'] != null) 'openid': row['openid'],
    };
    setState(() => queryController.text = _pretty(next));
  }

  void _fillBody(Map<String, Object?> row) {
    setState(() => bodyController.text = _pretty(row));
  }

  @override
  Widget build(BuildContext context) {
    final rows = objectList(data);
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          _ModuleHero(
            title: widget.title,
            description: widget.description,
            endpoint: selected.endpoint,
            shopName: widget.effectiveStoreName,
            rowCount: rows.length,
            loading: loading,
          ),
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final action in widget.actions)
                        ChoiceChip(
                          label: Text(action.label),
                          selected: selected == action,
                          onSelected: (_) => _select(action),
                        ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  _QuickToolbar(
                    keywordController: keywordController,
                    pageController: pageController,
                    sizeController: sizeController,
                    onSearch: _quickSearch,
                    onRefresh: _load,
                    onPrevious: loading ? null : () => _turnPage(-1),
                    onNext: loading ? null : () => _turnPage(1),
                  ),
                ],
              ),
            ),
          ),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('请求参数', style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: [
                      SizedBox(
                        width: 360,
                        child: TextField(
                          controller: queryController,
                          minLines: 4,
                          maxLines: 8,
                          decoration: const InputDecoration(
                            labelText: 'Query JSON',
                            helperText: 'GET 列表通常使用这里的参数',
                          ),
                        ),
                      ),
                      SizedBox(
                        width: 460,
                        child: TextField(
                          controller: bodyController,
                          minLines: 4,
                          maxLines: 8,
                          decoration: const InputDecoration(
                            labelText: 'Body JSON',
                            helperText: 'POST/PUT 操作会发送这里的参数',
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: [
                      FilledButton.icon(
                        onPressed: loading ? null : _load,
                        icon: loading
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Icon(Icons.cloud_sync_outlined),
                        label: const Text('请求真实接口'),
                      ),
                      OutlinedButton.icon(
                        onPressed: data == null ? null : _copyResponse,
                        icon: const Icon(Icons.content_copy_outlined),
                        label: const Text('复制响应'),
                      ),
                    ],
                  ),
                  if (error != null) ...[
                    const SizedBox(height: 12),
                    Text(
                      error!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          _ResultView(
            data: data,
            onFillQuery: _fillQuery,
            onFillBody: _fillBody,
          ),
        ],
      ),
    );
  }
}

AdminEndpoint _resolveEndpoint(
  AdminEndpoint endpoint,
  Map<String, Object?> query,
  Map<String, Object?> body,
) {
  var path = endpoint.path;
  final matches = RegExp(r'\{([^}]+)\}').allMatches(path).toList();
  for (final match in matches) {
    final key = match.group(1)!;
    final value = query.remove(key) ?? body.remove(key);
    if (value == null || '$value'.trim().isEmpty) {
      throw FormatException('请在 Query 或 Body 中提供路径参数 $key');
    }
    path = path.replaceAll('{$key}', Uri.encodeComponent('$value'));
  }
  return AdminEndpoint(
    method: endpoint.method,
    path: path,
    permissionCode: endpoint.permissionCode,
    attachShopHeader: endpoint.attachShopHeader,
    pageSizeLimit: endpoint.pageSizeLimit,
    preserveEmptyStrings: endpoint.preserveEmptyStrings,
    preserveEmptyCollections: endpoint.preserveEmptyCollections,
  );
}

class _ModuleHero extends StatelessWidget {
  const _ModuleHero({
    required this.title,
    required this.description,
    required this.endpoint,
    required this.shopName,
    required this.rowCount,
    required this.loading,
  });

  final String title;
  final String description;
  final AdminEndpoint endpoint;
  final String shopName;
  final int rowCount;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xff111827),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Wrap(
        spacing: 16,
        runSpacing: 14,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          SizedBox(
            width: 520,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  description,
                  style: const TextStyle(color: Color(0xffd1d5db)),
                ),
                const SizedBox(height: 10),
                SelectableText(
                  '${endpoint.method} ${endpoint.path} · 权限 ${endpoint.permissionCode}',
                  style: const TextStyle(color: Color(0xffffd166)),
                ),
              ],
            ),
          ),
          _HeroChip(label: '门店', value: shopName),
          _HeroChip(label: '本次行数', value: '$rowCount'),
          _HeroChip(
            label: '门店头',
            value: endpoint.attachShopHeader ? '开启' : '免传',
          ),
          if (loading)
            const SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Colors.white,
              ),
            ),
        ],
      ),
    );
  }
}

class _HeroChip extends StatelessWidget {
  const _HeroChip({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 130,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: .08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withValues(alpha: .18)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(color: Color(0xff9ca3af))),
          const SizedBox(height: 6),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

class _QuickToolbar extends StatelessWidget {
  const _QuickToolbar({
    required this.keywordController,
    required this.pageController,
    required this.sizeController,
    required this.onSearch,
    required this.onRefresh,
    required this.onPrevious,
    required this.onNext,
  });

  final TextEditingController keywordController;
  final TextEditingController pageController;
  final TextEditingController sizeController;
  final VoidCallback onSearch;
  final VoidCallback onRefresh;
  final VoidCallback? onPrevious;
  final VoidCallback? onNext;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        SizedBox(
          width: 280,
          child: TextField(
            controller: keywordController,
            textInputAction: TextInputAction.search,
            onSubmitted: (_) => onSearch(),
            decoration: const InputDecoration(
              labelText: '关键词',
              prefixIcon: Icon(Icons.search),
            ),
          ),
        ),
        SizedBox(
          width: 92,
          child: TextField(
            controller: pageController,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: '页码'),
          ),
        ),
        SizedBox(
          width: 104,
          child: TextField(
            controller: sizeController,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: '每页'),
          ),
        ),
        FilledButton.icon(
          onPressed: onSearch,
          icon: const Icon(Icons.manage_search),
          label: const Text('查询'),
        ),
        OutlinedButton.icon(
          onPressed: onRefresh,
          icon: const Icon(Icons.refresh),
          label: const Text('刷新'),
        ),
        IconButton.outlined(
          onPressed: onPrevious,
          tooltip: '上一页',
          icon: const Icon(Icons.chevron_left),
        ),
        IconButton.filled(
          onPressed: onNext,
          tooltip: '下一页',
          icon: const Icon(Icons.chevron_right),
        ),
      ],
    );
  }
}

class _ResultView extends StatelessWidget {
  const _ResultView({
    required this.data,
    required this.onFillQuery,
    required this.onFillBody,
  });

  final Object? data;
  final ValueChanged<Map<String, Object?>> onFillQuery;
  final ValueChanged<Map<String, Object?>> onFillBody;

  @override
  Widget build(BuildContext context) {
    final rows = objectList(data);
    if (data == null) {
      return const Card(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text('暂无响应数据，请先请求真实接口。'),
        ),
      );
    }
    if (rows.isEmpty) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: SelectableText(_prettyObject(data)),
        ),
      );
    }
    final columns = <String>{
      for (final row in rows.take(30)) ...row.keys,
    }.take(10).toList();
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
            child: Text(
              '接口结果表格',
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: DataTable(
              headingRowColor: WidgetStateProperty.all(const Color(0xfffff7ed)),
              columns: [
                for (final column in columns) DataColumn(label: Text(column)),
                const DataColumn(label: Text('操作')),
              ],
              rows: [
                for (final row in rows.take(100))
                  DataRow(
                    cells: [
                      for (final column in columns)
                        DataCell(
                          SizedBox(
                            width: 150,
                            child: Text(
                              '${row[column] ?? ''}',
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ),
                      DataCell(
                        Wrap(
                          spacing: 4,
                          children: [
                            TextButton(
                              onPressed: () => _showRowDetail(context, row),
                              child: const Text('查看'),
                            ),
                            TextButton(
                              onPressed: () => onFillQuery(row),
                              child: const Text('查'),
                            ),
                            TextButton(
                              onPressed: () => onFillBody(row),
                              child: const Text('编辑'),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _showRowDetail(BuildContext context, Map<String, Object?> row) {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('行数据明细'),
        content: SizedBox(
          width: 640,
          child: SingleChildScrollView(
            child: SelectableText(_prettyObject(row)),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('关闭'),
          ),
        ],
      ),
    );
  }
}

String _pretty(Map<String, Object?> value) =>
    const JsonEncoder.withIndent('  ').convert(value);

String _prettyObject(Object? value) =>
    const JsonEncoder.withIndent('  ').convert(value);

Map<String, Object?> _decodeObject(String text) {
  final trimmed = text.trim();
  if (trimmed.isEmpty) return <String, Object?>{};
  final decoded = jsonDecode(trimmed);
  if (decoded is Map) return decoded.cast<String, Object?>();
  throw const FormatException('JSON 必须是对象');
}
