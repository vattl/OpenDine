import 'package:flutter/material.dart';
import 'package:kds_app/core/theme/kds_theme.dart';

/// 全局友好错误页
class KdsErrorPage extends StatelessWidget {
  const KdsErrorPage({
    super.key,
    required this.message,
    required this.onRestart,
  });

  final String message;
  final VoidCallback onRestart;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: KdsColors.shellBg,
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.error_outline,
                    size: 64, color: KdsColors.headerOverdue),
                const SizedBox(height: 16),
                const Text(
                  '应用遇到问题',
                  style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                      color: KdsColors.textPrimary),
                ),
                const SizedBox(height: 12),
                Text(
                  message,
                  textAlign: TextAlign.center,
                  style:
                      const TextStyle(color: KdsColors.textMuted, fontSize: 14),
                ),
                const SizedBox(height: 24),
                FilledButton.icon(
                  onPressed: onRestart,
                  icon: const Icon(Icons.refresh),
                  label: const Text('返回登录并重试'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
