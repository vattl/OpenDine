import 'package:flutter/material.dart';

import '../../../core/api_debug_log.dart';
import '../../cashier_shell/presentation/cashier_tokens.dart';

class ApiDebugCountLabel extends StatelessWidget {
  const ApiDebugCountLabel({
    super.key,
    required this.label,
    required this.value,
    this.error = false,
  });

  final String label;
  final int value;
  final bool error;

  @override
  Widget build(BuildContext context) => Text(
    '$label $value',
    style: TextStyle(
      color: error ? const Color(0xffbd3434) : context.cashier.ink,
      fontWeight: FontWeight.w800,
    ),
  );
}

class ApiDebugRequestCard extends StatelessWidget {
  const ApiDebugRequestCard({
    super.key,
    required this.entry,
    required this.onTap,
  });

  final ApiDebugLogEntry entry;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final status = entry.statusCode?.toString() ?? '无响应';
    return Material(
      key: Key('api-debug-entry-${entry.id}'),
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: context.cashier.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Icon(
                entry.succeeded
                    ? Icons.check_circle_outline_rounded
                    : Icons.error_outline_rounded,
                color: entry.succeeded
                    ? const Color(0xff278844)
                    : const Color(0xffc43838),
              ),
              const SizedBox(width: 14),
              SizedBox(
                width: 62,
                child: Text(
                  entry.method,
                  style: const TextStyle(fontWeight: FontWeight.w900),
                ),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      entry.uri.path,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    if (entry.uri.hasQuery)
                      Text(
                        entry.uri.query,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: context.cashier.inkMuted,
                          fontSize: 12,
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 16),
              Text(
                status,
                style: TextStyle(
                  color: entry.succeeded
                      ? const Color(0xff278844)
                      : const Color(0xffc43838),
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(width: 20),
              SizedBox(
                width: 82,
                child: Text(
                  '${entry.duration.inMilliseconds} ms',
                  textAlign: TextAlign.right,
                ),
              ),
              const SizedBox(width: 10),
              const Icon(Icons.chevron_right_rounded),
            ],
          ),
        ),
      ),
    );
  }
}

class ApiDebugEmptyLog extends StatelessWidget {
  const ApiDebugEmptyLog({super.key});

  @override
  Widget build(BuildContext context) => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          Icons.cloud_sync_outlined,
          size: 56,
          color: context.cashier.inkMuted,
        ),
        SizedBox(height: 12),
        const Text(
          '暂无接口记录',
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
        ),
        SizedBox(height: 6),
        Text(
          '操作收银系统后，请求与响应会实时显示在这里',
          style: TextStyle(color: context.cashier.inkMuted),
        ),
      ],
    ),
  );
}
