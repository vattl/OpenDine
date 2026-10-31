import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kds_app/core/layout/kds_display_metrics.dart';
import 'package:kds_app/core/storage/kds_file_logger.dart';

final kdsDisplayMetricsProvider =
    StateProvider<KdsDisplayMetrics?>((ref) => null);

/// 启动时读取屏幕分辨率并注入全局布局缩放
class KdsDisplayScope extends ConsumerWidget {
  const KdsDisplayScope({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mq = MediaQuery.of(context);
    final metrics =
        KdsDisplayMetrics.fromLogicalSize(mq.size, mq.devicePixelRatio);

    final prev = ref.read(kdsDisplayMetricsProvider);
    if (prev == null ||
        prev.logicalWidth != metrics.logicalWidth ||
        prev.logicalHeight != metrics.logicalHeight) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        ref.read(kdsDisplayMetricsProvider.notifier).state = metrics;
        KdsFileLogger.info(
          '[Display] ${metrics.resolutionLabel} · ${metrics.formFactorLabel} · scale=${metrics.uiScale.toStringAsFixed(2)}',
        );
      });
    }

    return _KdsDisplayInherited(
      metrics: metrics,
      child: MediaQuery(
        data: mq.copyWith(textScaler: TextScaler.linear(metrics.textScale)),
        child: child,
      ),
    );
  }
}

class _KdsDisplayInherited extends InheritedWidget {
  const _KdsDisplayInherited({required this.metrics, required super.child});

  final KdsDisplayMetrics metrics;

  static KdsDisplayMetrics of(BuildContext context) {
    final scope =
        context.dependOnInheritedWidgetOfExactType<_KdsDisplayInherited>();
    return scope?.metrics ??
        KdsDisplayMetrics.fromLogicalSize(
          MediaQuery.sizeOf(context),
          MediaQuery.devicePixelRatioOf(context),
        );
  }

  @override
  bool updateShouldNotify(_KdsDisplayInherited oldWidget) =>
      oldWidget.metrics.logicalWidth != metrics.logicalWidth ||
      oldWidget.metrics.logicalHeight != metrics.logicalHeight ||
      oldWidget.metrics.uiScale != metrics.uiScale;
}

extension KdsDisplayContext on BuildContext {
  KdsDisplayMetrics get kdsDisplay => _KdsDisplayInherited.of(this);
}
