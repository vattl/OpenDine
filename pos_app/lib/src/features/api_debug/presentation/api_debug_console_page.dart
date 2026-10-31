import 'package:flutter/material.dart';

import '../../../core/api_debug_log.dart';
import 'api_debug_detail_dialog.dart';
import 'api_debug_request_list.dart';
import '../../cashier_shell/presentation/cashier_tokens.dart';

class ApiDebugConsolePage extends StatefulWidget {
  ApiDebugConsolePage({super.key, ApiDebugLogStore? store})
    : store = store ?? ApiDebugLogStore.instance;

  final ApiDebugLogStore store;

  @override
  State<ApiDebugConsolePage> createState() => _ApiDebugConsolePageState();
}

class _ApiDebugConsolePageState extends State<ApiDebugConsolePage> {
  final searchController = TextEditingController();
  bool errorsOnly = false;

  @override
  void dispose() {
    searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: context.cashier.canvas,
    appBar: AppBar(
      title: const Text('接口调试'),
      backgroundColor: Colors.white,
      foregroundColor: context.cashier.ink,
      surfaceTintColor: Colors.white,
      actions: [
        IconButton(
          key: const Key('api-debug-clear'),
          tooltip: '清空记录',
          onPressed: widget.store.clear,
          icon: const Icon(Icons.delete_sweep_outlined),
        ),
        const SizedBox(width: 8),
      ],
    ),
    body: SafeArea(
      child: AnimatedBuilder(
        animation: widget.store,
        builder: (context, _) {
          final entries = _filteredEntries(widget.store.entries);
          final total = widget.store.entries.length;
          final failures = widget.store.entries
              .where((entry) => !entry.succeeded)
              .length;
          return Column(
            children: [
              Container(
                color: Colors.white,
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 18),
                child: Column(
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: searchController,
                            onChanged: (_) => setState(() {}),
                            decoration: InputDecoration(
                              labelText: '搜索接口、状态码或内容',
                              prefixIcon: const Icon(Icons.search_rounded),
                              suffixIcon: searchController.text.isEmpty
                                  ? null
                                  : IconButton(
                                      tooltip: '清除搜索',
                                      onPressed: () {
                                        searchController.clear();
                                        setState(() {});
                                      },
                                      icon: const Icon(Icons.close_rounded),
                                    ),
                              border: const OutlineInputBorder(),
                              isDense: true,
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        FilterChip(
                          key: const Key('api-debug-filter-errors'),
                          selected: errorsOnly,
                          onSelected: (value) =>
                              setState(() => errorsOnly = value),
                          avatar: const Icon(Icons.error_outline, size: 18),
                          label: const Text('仅看失败'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        ApiDebugCountLabel(label: '全部', value: total),
                        const SizedBox(width: 20),
                        ApiDebugCountLabel(
                          label: '失败',
                          value: failures,
                          error: true,
                        ),
                        const Spacer(),
                        Flexible(
                          child: Text(
                            '最多保留最近 300 条；认证信息、密码与密钥自动脱敏',
                            textAlign: TextAlign.right,
                            style: TextStyle(
                              color: context.cashier.inkMuted,
                              fontSize: 13,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              Expanded(
                child: entries.isEmpty
                    ? const ApiDebugEmptyLog()
                    : ListView.separated(
                        padding: const EdgeInsets.all(20),
                        itemCount: entries.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 10),
                        itemBuilder: (context, index) => ApiDebugRequestCard(
                          entry: entries[index],
                          onTap: () => showDialog<void>(
                            context: context,
                            builder: (_) =>
                                ApiDebugDetailDialog(entry: entries[index]),
                          ),
                        ),
                      ),
              ),
            ],
          );
        },
      ),
    ),
  );

  List<ApiDebugLogEntry> _filteredEntries(List<ApiDebugLogEntry> entries) {
    final query = searchController.text.trim().toLowerCase();
    return entries
        .where((entry) {
          if (errorsOnly && entry.succeeded) return false;
          if (query.isEmpty) return true;
          return entry.method.toLowerCase().contains(query) ||
              entry.uri.toString().toLowerCase().contains(query) ||
              '${entry.statusCode ?? ''}'.contains(query) ||
              entry.requestBody.toLowerCase().contains(query) ||
              entry.responseBody.toLowerCase().contains(query) ||
              entry.error.toLowerCase().contains(query);
        })
        .toList(growable: false);
  }
}
