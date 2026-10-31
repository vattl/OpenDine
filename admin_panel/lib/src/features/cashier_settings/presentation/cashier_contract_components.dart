import 'package:flutter/material.dart';
import '../../cashier_shell/presentation/cashier_tokens.dart';

/// 接口契约说明元数据模型
class OpenApiContractSpec {
  const OpenApiContractSpec({
    required this.title,
    required this.endpoint,
    required this.method,
    required this.permission,
    this.queryParams,
    this.requestBody,
    required this.responseSchema,
    this.invariants = const [],
  });

  final String title;
  final String endpoint;
  final String method;
  final String permission;
  final String? queryParams;
  final String? requestBody;
  final String responseSchema;
  final List<String> invariants;
}

/// 依据 UI061 原型规范设计的二级子功能胶囊横滑栏 (.subnav-tabs)
class ManageSubTabsBar extends StatelessWidget {
  const ManageSubTabsBar({
    super.key,
    required this.tabs,
    required this.selectedIndex,
    required this.onChanged,
    this.onViewContract,
  });

  final List<String> tabs;
  final int selectedIndex;
  final ValueChanged<int> onChanged;
  final VoidCallback? onViewContract;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      height: 48,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xff18181b) : const Color(0xfffafafa),
        border: Border(
          bottom: BorderSide(
            color: isDark ? const Color(0xff27272a) : const Color(0xffe4e4e7),
          ),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (int i = 0; i < tabs.length; i++) ...[
                    if (i > 0) const SizedBox(width: 8),
                    _buildPill(context, index: i, label: tabs[i], isSelected: i == selectedIndex),
                  ],
                ],
              ),
            ),
          ),
          if (onViewContract != null) ...[
            const SizedBox(width: 12),
            OutlinedButton.icon(
              onPressed: onViewContract,
              icon: const Icon(Icons.code, size: 14),
              label: const Text('查看接口契约', style: TextStyle(fontSize: 12)),
              style: OutlinedButton.styleFrom(
                foregroundColor: isDark ? const Color(0xff38bdf8) : const Color(0xff0284c7),
                side: BorderSide(
                  color: isDark ? const Color(0xff0369a1) : const Color(0xffbae6fd),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                minimumSize: const Size(0, 30),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildPill(
    BuildContext context, {
    required int index,
    required String label,
    required bool isSelected,
  }) {
    final theme = context.cashier;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return InkWell(
      key: Key('manage-subtab-$index'),
      onTap: () => onChanged(index),
      borderRadius: BorderRadius.circular(6),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color: isSelected
              ? (isDark ? const Color(0xff27272a) : Colors.white)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
          border: isSelected
              ? Border.all(
                  color: isDark ? const Color(0xff52525b) : const Color(0xffd4d4d8),
                  width: 1,
                )
              : Border.all(color: Colors.transparent, width: 1),
          boxShadow: isSelected && !isDark
              ? [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.04),
                    blurRadius: 3,
                    offset: const Offset(0, 1),
                  ),
                ]
              : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: isSelected
                    ? (isDark ? const Color(0xff38bdf8) : const Color(0xff0284c7))
                    : (isDark ? const Color(0xff52525b) : const Color(0xffa1a1aa)),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                color: isSelected ? theme.ink : theme.inkMuted,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 接口契约查看弹窗
void showOpenApiContractDialog(BuildContext context, OpenApiContractSpec spec) {
  final isDark = Theme.of(context).brightness == Brightness.dark;

  showDialog<void>(
    context: context,
    builder: (ctx) => Dialog(
      backgroundColor: isDark ? const Color(0xff18181b) : Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 680, maxHeight: 600),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: spec.method == 'GET'
                          ? const Color(0xff0369a1).withOpacity(0.2)
                          : const Color(0xff15803d).withOpacity(0.2),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      spec.method,
                      style: TextStyle(
                        fontFamily: 'monospace',
                        fontWeight: FontWeight.w900,
                        fontSize: 13,
                        color: spec.method == 'GET'
                            ? const Color(0xff38bdf8)
                            : const Color(0xff4ade80),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      spec.title,
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(ctx).pop(),
                    icon: const Icon(Icons.close, size: 20),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xff09090b) : const Color(0xfff4f4f5),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  spec.endpoint,
                  style: const TextStyle(fontFamily: 'monospace', fontSize: 13, fontWeight: FontWeight.w600),
                ),
              ),
              const SizedBox(height: 16),
              Expanded(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _buildContractSection(
                        '权限标识 (x-permission)',
                        spec.permission,
                        isDark: isDark,
                      ),
                      if (spec.queryParams != null) ...[
                        const SizedBox(height: 12),
                        _buildContractSection(
                          'Query / Path 入参',
                          spec.queryParams!,
                          isDark: isDark,
                        ),
                      ],
                      if (spec.requestBody != null) ...[
                        const SizedBox(height: 12),
                        _buildContractSection(
                          'Request Body Schema',
                          spec.requestBody!,
                          isDark: isDark,
                        ),
                      ],
                      const SizedBox(height: 12),
                      _buildContractSection(
                        'Response 200 OK Schema',
                        spec.responseSchema,
                        isDark: isDark,
                      ),
                      if (spec.invariants.isNotEmpty) ...[
                        const SizedBox(height: 12),
                        const Text(
                          '业务不可变约束 (Invariants):',
                          style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 6),
                        for (final inv in spec.invariants)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 4),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text('• ', style: TextStyle(color: Color(0xff38bdf8), fontWeight: FontWeight.bold)),
                                Expanded(
                                  child: Text(
                                    inv,
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: isDark ? const Color(0xffa1a1aa) : const Color(0xff52525b),
                                      height: 1.4,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

Widget _buildContractSection(String title, String content, {required bool isDark}) {
  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        title,
        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
      ),
      const SizedBox(height: 4),
      Container(
        width: double.infinity,
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xff09090b) : const Color(0xfff4f4f5),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: isDark ? const Color(0xff27272a) : const Color(0xffe4e4e7),
          ),
        ),
        child: SelectableText(
          content,
          style: const TextStyle(fontFamily: 'monospace', fontSize: 12, height: 1.4),
        ),
      ),
    ],
  );
}
