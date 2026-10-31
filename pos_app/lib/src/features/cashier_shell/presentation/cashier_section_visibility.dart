import 'dart:async';

import 'package:flutter/material.dart';

/// 收银工作区 section 页面的可见性刷新约定。
///
/// 宿主（CashierWorkspace）用 Offstage + TickerMode 保活已访问页面：
/// 页面不可见时 State 仍然存在，但 Timer 不受 TickerMode 管控，
/// 因此轮询必须按可见性手动门控——
///
/// - 页面可见：启动轮询，按 [sectionPollInterval] 静默刷新；
/// - 页面隐藏：立即停止轮询，不再产生请求，避免资源浪费；
/// - 由隐藏切回可见：立即补偿一次静默刷新，保证数据新鲜。
mixin CashierSectionVisibilityMixin<T extends StatefulWidget> on State<T> {
  Timer? _sectionPollTimer;
  bool _sectionPolling = false;
  bool _sectionFirstActivation = true;

  /// 可见时的轮询间隔，各页面可按业务频率覆盖。
  Duration get sectionPollInterval => const Duration(seconds: 10);

  /// 静默刷新入口。实现方需保证：可重入、失败静默保留旧数据、
  /// 不打断页面上的进行中操作（可自行选择跳过）。
  Future<void> refreshSectionSilently();

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final visible = TickerMode.valuesOf(context).enabled;
    if (visible && !_sectionPolling) {
      if (_sectionFirstActivation) {
        // 首次激活紧跟 initState 的首页加载，无需重复补偿。
        _sectionFirstActivation = false;
      } else {
        unawaited(refreshSectionSilently());
      }
      _startSectionPolling();
    } else if (!visible && _sectionPolling) {
      _stopSectionPolling();
    }
  }

  void _startSectionPolling() {
    _sectionPolling = true;
    _sectionPollTimer ??= Timer.periodic(sectionPollInterval, (_) {
      unawaited(refreshSectionSilently());
    });
  }

  void _stopSectionPolling() {
    _sectionPolling = false;
    _sectionPollTimer?.cancel();
    _sectionPollTimer = null;
  }

  @override
  void dispose() {
    _stopSectionPolling();
    super.dispose();
  }
}
