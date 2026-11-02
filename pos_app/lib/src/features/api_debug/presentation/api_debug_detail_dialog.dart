import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/api_debug_log.dart';

class ApiDebugDetailDialog extends StatelessWidget {
  const ApiDebugDetailDialog({super.key, required this.entry});

  final ApiDebugLogEntry entry;

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    return Dialog(
      insetPadding: const EdgeInsets.all(24),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: 980, maxHeight: size.height - 48),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 16, 12, 12),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      '请求详情',
                      style: Theme.of(context).textTheme.headlineSmall
                          ?.copyWith(fontWeight: FontWeight.w800),
                    ),
                  ),
                  TextButton.icon(
                    key: const Key('api-debug-copy-detail'),
                    onPressed: () => Clipboard.setData(
                      ClipboardData(text: formatApiDebugEntry(entry)),
                    ),
                    icon: const Icon(Icons.copy_all_rounded),
                    label: const Text('复制全部'),
                  ),
                  IconButton(
                    key: const Key('api-debug-detail-close'),
                    tooltip: '关闭',
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.all(24),
                children: [
                  Wrap(
                    spacing: 12,
                    runSpacing: 8,
                    children: [
                      _MetaChip(label: entry.method),
                      _MetaChip(
                        label: entry.statusCode?.toString() ?? '无响应',
                        error: !entry.succeeded,
                      ),
                      _MetaChip(label: '${entry.duration.inMilliseconds} ms'),
                      _MetaChip(label: _dateTime(entry.startedAt)),
                      _MetaChip(label: entry.id),
                    ],
                  ),
                  const SizedBox(height: 20),
                  _DebugSection(title: '请求地址', content: entry.uri.toString()),
                  _DebugSection(
                    title: '请求头（敏感信息已脱敏）',
                    content: entry.requestHeaders.entries
                        .map((item) => '${item.key}: ${item.value}')
                        .join('\n'),
                  ),
                  _DebugSection(title: '请求体', content: entry.requestBody),
                  _DebugSection(title: '响应体', content: entry.responseBody),
                  if (entry.error.isNotEmpty)
                    _DebugSection(
                      title: '异常',
                      content: entry.error,
                      error: true,
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MetaChip extends StatelessWidget {
  const _MetaChip({required this.label, this.error = false});

  final String label;
  final bool error;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
    decoration: BoxDecoration(
      color: error ? const Color(0xffffeded) : const Color(0xffeef4ff),
      borderRadius: BorderRadius.circular(8),
    ),
    child: Text(
      label,
      style: TextStyle(
        color: error ? const Color(0xffa72f2f) : const Color(0xff24589b),
        fontWeight: FontWeight.w700,
      ),
    ),
  );
}

class _DebugSection extends StatelessWidget {
  const _DebugSection({
    required this.title,
    required this.content,
    this.error = false,
  });

  final String title;
  final String content;
  final bool error;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 18),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
        const SizedBox(height: 8),
        Container(
          width: double.infinity,
          constraints: const BoxConstraints(minHeight: 48),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: error ? const Color(0xfffff2f2) : const Color(0xfff6f7f9),
            border: Border.all(
              color: error ? const Color(0xffe5a8a8) : const Color(0xffdfe2e7),
            ),
            borderRadius: BorderRadius.circular(10),
          ),
          child: SelectableText(
            content.isEmpty ? '（空）' : content,
            style: const TextStyle(
              fontFamily: 'monospace',
              fontSize: 14,
              height: 1.45,
            ),
          ),
        ),
      ],
    ),
  );
}

String formatApiDebugEntry(ApiDebugLogEntry entry) =>
    '''
[${entry.id}] ${entry.method} ${entry.uri}
时间: ${_dateTime(entry.startedAt)}
状态: ${entry.statusCode ?? '无响应'} / ${entry.succeeded ? '成功' : '失败'}
耗时: ${entry.duration.inMilliseconds} ms

请求头:
${entry.requestHeaders.entries.map((item) => '${item.key}: ${item.value}').join('\n')}

请求体:
${entry.requestBody.isEmpty ? '（空）' : entry.requestBody}

响应体:
${entry.responseBody.isEmpty ? '（空）' : entry.responseBody}

异常:
${entry.error.isEmpty ? '（无）' : entry.error}
''';

String _dateTime(DateTime value) {
  String two(int part) => part.toString().padLeft(2, '0');
  return '${value.year}-${two(value.month)}-${two(value.day)} '
      '${two(value.hour)}:${two(value.minute)}:${two(value.second)}';
}
