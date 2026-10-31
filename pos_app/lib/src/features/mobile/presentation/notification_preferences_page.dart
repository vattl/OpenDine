import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api_contract.dart';
import '../data/api_providers.dart';
import '../design/mobile_metrics.dart';
import '../design/mobile_typography.dart';

/// 通知偏好（PRD F08.2）：订阅/关闭业务通知类型，保存到 `/admin/push/preference`。
/// 全部关闭时提交空数组，表示当前门店关闭全部业务通知。
class NotificationPreferencesPage extends ConsumerStatefulWidget {
  const NotificationPreferencesPage({super.key});

  @override
  ConsumerState<NotificationPreferencesPage> createState() =>
      _NotificationPreferencesPageState();
}

class _NotificationPreferencesPageState
    extends ConsumerState<NotificationPreferencesPage> {
  static const _options = <(String, String)>[
    ('new_order', '新订单'),
    ('add_dishes', '加菜'),
    ('refund', '退菜审批'),
    ('uncheckout', '反结账'),
    ('table_call', '桌台呼叫'),
    ('recharge', '会员充值'),
    ('daily', '日结提醒'),
  ];

  late final Set<String> _selected = <String>{'new_order', 'refund', 'table_call'};
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final data = await ref
          .read(apiClientProvider)
          .get(pushPreferenceEndpoint);
      if (mounted && data is Map) {
        final types = data['types'];
        if (types is List) {
          setState(() {
            _selected
              ..clear()
              ..addAll(types.whereType<String>());
          });
        }
      }
    } catch (_) {
      // 读取失败沿用默认订阅，不阻断页面。
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _save() async {
    try {
      await ref.read(apiClientProvider).post(
            pushPreferenceEndpoint,
            body: {'types': _selected.toList()},
          );
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('通知偏好已保存')));
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('保存失败：$error')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('通知偏好')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: MobileMetrics.pagePadding.copyWith(top: MobileMetrics.spaceMd),
              children: [
                Text(
                  '选择需要接收的业务通知，关闭全部将停用本店业务推送。',
                  style: context.bodySecondaryStyle,
                ),
                const SizedBox(height: MobileMetrics.spaceMd),
                Card(
                  child: Column(
                    children: [
                      for (var i = 0; i < _options.length; i++) ...[
                        SwitchListTile(
                          title: Text(_options[i].$2),
                          value: _selected.contains(_options[i].$1),
                          onChanged: (on) => setState(() {
                            if (on) {
                              _selected.add(_options[i].$1);
                            } else {
                              _selected.remove(_options[i].$1);
                            }
                          }),
                        ),
                        if (i < _options.length - 1) const Divider(height: 1),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: MobileMetrics.spaceLg),
                FilledButton(
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(MobileMetrics.buttonHeightCta),
                  ),
                  onPressed: _save,
                  child: const Text('保存偏好'),
                ),
              ],
            ),
    );
  }
}
