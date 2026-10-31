import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/admin_api_client.dart';
import '../../../core/api_contract.dart';
import '../../../core/app_state.dart';
import '../runtime/cashier_kds_runtime.dart';

/// D026 统一看板设备级岗分流：设备绑定/编辑管理页。
///
/// - 列表：GET /admin/kds/device/list（回显 screen_tags 供编辑）
/// - 绑定/编辑：POST /admin/kds/device/bind
///   （deviceCode/screenTag 必填；可见烤制岗多选，不选 = 三岗全选）
const _kGrillTags = <String, String>{
  'meat_grill': '荤烤',
  'veg_grill': '素烤',
  'seafood_special': '海鲜',
};

class KdsDevicesPage extends StatefulWidget {
  const KdsDevicesPage({
    super.key,
    this.appState,
    required this.client,
    this.currentShopId,
    this.kdsRuntime,
    this.canManage = true,
    this.showLanPairing = true,
    this.showCloudSync = true,
  });

  final AppState? appState;
  final AdminApiClient client;
  final int? currentShopId;
  final CashierKdsRuntime? kdsRuntime;
  final bool canManage;
  final bool showLanPairing;
  final bool showCloudSync;

  @override
  State<KdsDevicesPage> createState() => _KdsDevicesPageState();
}

class _KdsDevicesPageState extends State<KdsDevicesPage> {
  List<Map<String, Object?>> _devices = const [];
  bool _loading = true;
  String? _error;
  List<String> _addresses = const [];
  String? _pairingCode;
  String? _selectedPairingDeviceCode;
  int _pairingRemainingSeconds = 0;
  Timer? _pairingTimer;
  String _kdsPin = '123456';

  AdminApiClient get _client => widget.client.copyWith(
    shopId: widget.currentShopId ?? widget.appState?.currentShopId,
  );

  @override
  void initState() {
    super.initState();
    _load();
    _loadAddresses();
  }

  @override
  void dispose() {
    _pairingTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadAddresses() async {
    final runtime = widget.kdsRuntime;
    if (runtime == null) return;
    try {
      final list = await runtime.lanAddresses();
      if (mounted) {
        setState(() => _addresses = list);
      }
    } catch (_) {}
  }

  Future<void> _generatePairingCode() async {
    final candidates = _devices
        .where((device) => '${device['enabled'] ?? 1}' != '0')
        .map(
          (device) => '${device['device_code'] ?? device['deviceCode'] ?? ''}',
        )
        .where((code) => code.isNotEmpty)
        .toList();
    final deviceCode =
        _selectedPairingDeviceCode ??
        (candidates.isEmpty ? null : candidates.first);
    if (deviceCode == null || deviceCode.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('请先在设备列表绑定并选择 KDS 设备')));
      return;
    }
    try {
      final response = await _client.post(
        kdsDevicePairingTicketEndpoint,
        body: {'device_code': deviceCode},
      );
      final envelope = response is Map ? response : const <String, Object?>{};
      final rawData = envelope['data'];
      final data = rawData is Map ? rawData : envelope;
      final code = '${data['pairing_code'] ?? ''}'.trim();
      final expiresAtMs = switch (data['expires_at_ms']) {
        final num value => value.toInt(),
        final Object value => int.tryParse('$value') ?? 0,
        null => 0,
      };
      if (code.isEmpty ||
          expiresAtMs <= DateTime.now().millisecondsSinceEpoch) {
        throw const FormatException('云端未返回有效配对码');
      }
      _pairingTimer?.cancel();
      final seconds =
          ((expiresAtMs - DateTime.now().millisecondsSinceEpoch) / 1000)
              .ceil()
              .clamp(1, 900)
              .toInt();
      if (!mounted) return;
      setState(() {
        _pairingCode = code;
        _pairingRemainingSeconds = seconds;
      });
      _pairingTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
        if (!mounted) {
          timer.cancel();
          return;
        }
        setState(() {
          if (_pairingRemainingSeconds > 1) {
            _pairingRemainingSeconds--;
          } else {
            _pairingRemainingSeconds = 0;
            _pairingCode = null;
            timer.cancel();
          }
        });
      });
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('生成配对码失败: $e'), backgroundColor: Colors.red),
      );
    }
  }

  String _formatRemaining(int seconds) {
    final m = (seconds ~/ 60).toString().padLeft(2, '0');
    final s = (seconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final effectiveShopId =
        widget.currentShopId ?? widget.appState?.currentShopId ?? 1;
    try {
      final result = await _client.get(kdsDeviceListEndpoint);
      final list = _asDeviceList(result);
      try {
        final configRes = await _client.get(kdsConfigEndpoint);
        final envelope = configRes is Map ? configRes : const <String, Object?>{};
        final rawConfig = envelope['config'] ?? envelope['data'] ?? envelope;
        if (rawConfig is Map && rawConfig['kds_pin'] != null) {
          final pin = '${rawConfig['kds_pin']}'.trim();
          if (pin.isNotEmpty) _kdsPin = pin;
        }
      } catch (_) {}
      if (widget.kdsRuntime != null && list.isNotEmpty) {
        await widget.kdsRuntime!.syncBoundDevices(
          list,
          shopId: effectiveShopId,
        );
      }
      if (!mounted) return;
      setState(() {
        _devices = list;
        final enabledCodes = list
            .where((device) => '${device['enabled'] ?? 1}' != '0')
            .map(
              (device) =>
                  '${device['device_code'] ?? device['deviceCode'] ?? ''}',
            )
            .where((code) => code.isNotEmpty)
            .toList();
        if (!enabledCodes.contains(_selectedPairingDeviceCode)) {
          _selectedPairingDeviceCode = enabledCodes.isEmpty
              ? null
              : enabledCodes.first;
        }
        _loading = false;
      });
    } catch (e) {
      if (widget.kdsRuntime != null) {
        final localDevices = widget.kdsRuntime!.pairedDevices;
        if (localDevices.isNotEmpty) {
          if (!mounted) return;
          setState(() {
            _devices = localDevices
                .map(
                  (d) => {
                    'deviceCode': d.deviceCode,
                    'device_code': d.deviceCode,
                    'deviceName': d.deviceName,
                    'device_name': d.deviceName,
                    'screenTag': d.screenTag,
                    'screen_tag': d.screenTag,
                    'screenTags': d.screenTags,
                    'screen_tags': d.screenTags,
                    'workflows': d.workflows,
                    'enabled': d.enabled ? 1 : 0,
                  },
                )
                .toList();
            _loading = false;
          });
          return;
        }
      }
      if (!mounted) return;
      setState(() {
        _error = '$e';
        _loading = false;
      });
    }
  }

  List<Map<String, Object?>> _asDeviceList(Object? result) {
    if (result is Map) {
      final raw = result['list'];
      if (raw is List) {
        return raw
            .whereType<Map>()
            .map((e) => Map<String, Object?>.from(e))
            .toList();
      }
      final data = result['data'];
      if (data is Map) {
        final nested = data['list'];
        if (nested is List) {
          return nested
              .whereType<Map>()
              .map((e) => Map<String, Object?>.from(e))
              .toList();
        }
      }
    }
    if (result is List) {
      return result
          .whereType<Map>()
          .map((e) => Map<String, Object?>.from(e))
          .toList();
    }
    return const [];
  }

  Future<void> _openForm([Map<String, Object?>? device]) async {
    final saved = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _DeviceFormDialog(
        client: _client,
        initial: device,
        kdsRuntime: widget.kdsRuntime,
        shopId: widget.currentShopId ?? widget.appState?.currentShopId,
      ),
    );
    if (saved == true) await _load();
  }

  Future<void> _confirmDelete(Map<String, Object?> device) async {
    final code = '${device['device_code'] ?? device['deviceCode'] ?? ''}';
    if (code.isEmpty) return;
    final name = '${device['device_name'] ?? device['deviceName'] ?? ''}';
    final displayName = name.isEmpty ? code : '$name（$code）';

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: const Text('删除设备'),
        content: Text('确定要删除/解绑设备「$displayName」吗？删除后该设备需重新绑定方可接入。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogCtx).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red.shade600),
            onPressed: () => Navigator.of(dialogCtx).pop(true),
            child: const Text('删除'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    setState(() {
      _loading = true;
      _error = null;
    });

    final effectiveShopId =
        widget.currentShopId ?? widget.appState?.currentShopId ?? 1;

    try {
      await _client.post(
        kdsDeviceUnbindEndpoint,
        body: {'device_code': code, 'deviceCode': code},
      );
      Object? cacheError;
      if (widget.kdsRuntime != null) {
        try {
          await widget.kdsRuntime!.unbindDevice(
            shopId: effectiveShopId,
            deviceCode: code,
          );
        } catch (e) {
          cacheError = e;
        }
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            cacheError == null
                ? '设备「$displayName」已成功删除'
                : '云端已删除设备「$displayName」，本地缓存刷新失败，将在下次同步时重试: $cacheError',
          ),
          backgroundColor: cacheError == null ? null : Colors.orange,
        ),
      );
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('删除设备失败: $e')));
      setState(() {
        _loading = false;
      });
    }
  }

  String _tagsLabel(List<Object?>? tags) {
    final effective = (tags ?? const [])
        .whereType<String>()
        .where((t) => _kGrillTags.containsKey(t))
        .toList();
    if (effective.isEmpty) return '三岗全选';
    return effective.map((t) => _kGrillTags[t]).join('、');
  }

  bool _syncingCloud = false;

  Future<void> _syncAllToCloud() async {
    if (_syncingCloud || _devices.isEmpty) return;
    setState(() => _syncingCloud = true);
    int successCount = 0;
    int failCount = 0;
    String? lastError;
    try {
      for (final dev in _devices) {
        final code = '${dev['device_code'] ?? dev['deviceCode'] ?? ''}'.trim();
        final tag =
            '${dev['screen_tag'] ?? dev['screenTag'] ?? 'workflow_board'}'
                .trim();
        final name = '${dev['device_name'] ?? dev['deviceName'] ?? ''}'.trim();
        final tags = dev['screen_tags'] ?? dev['screenTags'];
        final screenTags = tags is List
            ? tags.whereType<String>().toList()
            : <String>[];
        final rawWorkflows = dev['workflows'] ?? dev['workflows_json'];
        final workflows = rawWorkflows is List
            ? rawWorkflows.whereType<String>().toList()
            : <String>[];
        if (code.isEmpty) continue;
        try {
          await _client.post(
            kdsDeviceBindEndpoint,
            body: {
              'deviceCode': code,
              'device_code': code,
              'screenTag': tag,
              'screen_tag': tag,
              if (name.isNotEmpty) ...{'deviceName': name, 'device_name': name},
              if (screenTags.isNotEmpty) ...{
                'screenTags': screenTags,
                'screen_tags': screenTags,
              },
              if (workflows.isNotEmpty) ...{
                'workflows': workflows,
                'workflows_json': workflows,
              },
            },
          );
          successCount++;
        } catch (e) {
          failCount++;
          lastError = e.toString();
        }
      }
      if (!mounted) return;
      if (failCount == 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('已成功将 $successCount 台设备同步至云端'),
            backgroundColor: Colors.green,
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('同步完成：$successCount 台成功，$failCount 台失败（$lastError）'),
            backgroundColor: Colors.orange,
          ),
        );
      }
      await _load();
    } finally {
      if (mounted) setState(() => _syncingCloud = false);
    }
  }

  Widget _buildLanPairingCard() {
    final runtime = widget.kdsRuntime;
    final port = runtime?.lanPort ?? runtime?.configuredPort ?? 17026;
    final effectiveAddresses = _addresses.isNotEmpty
        ? _addresses
        : ['http://127.0.0.1:$port'];
    final primaryAddress = effectiveAddresses.first;
    final active = runtime != null && runtime.lanStatus == 'active';

    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.grey.shade300),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.wifi_tethering,
                  color: Theme.of(context).primaryColor,
                  size: 20,
                ),
                const SizedBox(width: 8),
                const Text(
                  '局域网连接与厨显配对',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                const Spacer(),
                if (runtime != null)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: active
                          ? const Color(0xfff0fdf4)
                          : const Color(0xfffffbeb),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: active
                            ? const Color(0xffbbf7d0)
                            : const Color(0xfffde68a),
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          active
                              ? Icons.check_circle
                              : Icons.warning_amber_rounded,
                          size: 13,
                          color: active
                              ? const Color(0xff15803d)
                              : const Color(0xffd97706),
                        ),
                        const SizedBox(width: 4),
                        Text(
                          active
                              ? '局域网服务运行中 · 端口 $port'
                              : '权威状态：${runtime.lanStatus}',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: active
                                ? const Color(0xff166534)
                                : const Color(0xff92400e),
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            LayoutBuilder(
              builder: (context, constraints) {
                final isWide = constraints.maxWidth >= 720;
                final addressWidget = Expanded(
                  flex: isWide ? 5 : 0,
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xfff9fafb),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: const Color(0xffe5e7eb)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Row(
                          children: [
                            Icon(
                              Icons.router_outlined,
                              size: 16,
                              color: Colors.blueGrey,
                            ),
                            SizedBox(width: 6),
                            Text(
                              '收银端局域网服务地址（KDS 平板输入此地址）',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: Colors.black87,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Expanded(
                              child: SelectableText(
                                primaryAddress,
                                style: const TextStyle(
                                  fontSize: 17,
                                  fontWeight: FontWeight.bold,
                                  fontFamily: 'monospace',
                                  color: Color(0xff1e293b),
                                ),
                              ),
                            ),
                            FilledButton.tonalIcon(
                              onPressed: () {
                                Clipboard.setData(
                                  ClipboardData(text: primaryAddress),
                                );
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text('已复制连接地址: $primaryAddress'),
                                    duration: const Duration(seconds: 2),
                                    backgroundColor: Colors.green,
                                  ),
                                );
                              },
                              icon: const Icon(Icons.copy, size: 15),
                              label: const Text(
                                '复制',
                                style: TextStyle(fontSize: 12),
                              ),
                            ),
                          ],
                        ),
                        if (effectiveAddresses.length > 1) ...[
                          const SizedBox(height: 6),
                          Wrap(
                            spacing: 6,
                            runSpacing: 4,
                            children: [
                              Text(
                                '候选网卡: ',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: Colors.grey.shade600,
                                ),
                              ),
                              for (final addr in effectiveAddresses.skip(1))
                                InkWell(
                                  onTap: () {
                                    Clipboard.setData(
                                      ClipboardData(text: addr),
                                    );
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(content: Text('已复制候选地址: $addr')),
                                    );
                                  },
                                  child: Text(
                                    addr,
                                    style: const TextStyle(
                                      fontSize: 11,
                                      fontFamily: 'monospace',
                                      color: Color(0xff2563eb),
                                      decoration: TextDecoration.underline,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ],
                        const SizedBox(height: 6),
                        Text(
                          '💡 提示：后厨平板必须与收银机处于同一 Wi-Fi 或店内局域网网络。',
                          style: TextStyle(
                            fontSize: 11,
                            color: Colors.grey.shade600,
                          ),
                        ),
                      ],
                    ),
                  ),
                );

                final pairingWidget = Expanded(
                  flex: isWide ? 5 : 0,
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: _pairingCode != null
                          ? const Color(0xffeff6ff)
                          : const Color(0xfff9fafb),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: _pairingCode != null
                            ? const Color(0xffbfdbfe)
                            : const Color(0xffe5e7eb),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(
                              Icons.pin_outlined,
                              size: 16,
                              color: _pairingCode != null
                                  ? const Color(0xff2563eb)
                                  : Colors.blueGrey,
                            ),
                            const SizedBox(width: 6),
                            const Text(
                              '云端一次性配对码',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: Colors.black87,
                              ),
                            ),
                            const Spacer(),
                            if (_pairingCode != null)
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: _pairingRemainingSeconds < 60
                                      ? const Color(0xfffef2f2)
                                      : const Color(0xffecfdf5),
                                  borderRadius: BorderRadius.circular(4),
                                  border: Border.all(
                                    color: _pairingRemainingSeconds < 60
                                        ? const Color(0xfffecaca)
                                        : const Color(0xffa7f3d0),
                                  ),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      Icons.timer_outlined,
                                      size: 12,
                                      color: _pairingRemainingSeconds < 60
                                          ? const Color(0xffdc2626)
                                          : const Color(0xff059669),
                                    ),
                                    const SizedBox(width: 3),
                                    Text(
                                      _formatRemaining(
                                        _pairingRemainingSeconds,
                                      ),
                                      style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.bold,
                                        color: _pairingRemainingSeconds < 60
                                            ? const Color(0xffdc2626)
                                            : const Color(0xff059669),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        if (_pairingCode == null) ...[
                          DropdownButtonFormField<String>(
                            key: const Key('kds-pairing-device-select'),
                            isExpanded: true,
                            initialValue: _selectedPairingDeviceCode,
                            decoration: const InputDecoration(
                              labelText: '已绑定 KDS 设备',
                              isDense: true,
                              border: OutlineInputBorder(),
                            ),
                            items: _devices
                                .where(
                                  (device) =>
                                      '${device['enabled'] ?? 1}' != '0',
                                )
                                .map((device) {
                                  final code =
                                      '${device['device_code'] ?? device['deviceCode'] ?? ''}';
                                  return DropdownMenuItem(
                                    value: code,
                                    child: Text(
                                      code,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  );
                                })
                                .where((item) => item.value?.isNotEmpty == true)
                                .toList(),
                            onChanged: widget.canManage
                                ? (value) => setState(
                                    () => _selectedPairingDeviceCode = value,
                                  )
                                : null,
                          ),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  '先绑定设备，再由云端签发 8 位一次性配对码；收银端不参与鉴权',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.grey.shade600,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              FilledButton.icon(
                                key: const Key('kds-generate-pairing-code-btn'),
                                onPressed: widget.canManage
                                    ? () => _generatePairingCode()
                                    : null,
                                icon: const Icon(Icons.qr_code, size: 16),
                                label: const Text(
                                  '生成配对码',
                                  style: TextStyle(fontSize: 12),
                                ),
                              ),
                            ],
                          ),
                        ] else ...[
                          Row(
                            children: [
                              Expanded(
                                child: SelectableText(
                                  _pairingCode!.split('').join('  '),
                                  style: const TextStyle(
                                    fontSize: 24,
                                    fontWeight: FontWeight.w900,
                                    letterSpacing: 3,
                                    color: Color(0xff1d4ed8),
                                  ),
                                ),
                              ),
                              IconButton(
                                tooltip: '复制配对码',
                                icon: const Icon(Icons.copy, size: 18),
                                onPressed: () {
                                  Clipboard.setData(
                                    ClipboardData(text: _pairingCode!),
                                  );
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text('已复制配对码: $_pairingCode'),
                                    ),
                                  );
                                },
                              ),
                              OutlinedButton.icon(
                                onPressed: widget.canManage
                                    ? () => _generatePairingCode()
                                    : null,
                                icon: const Icon(Icons.refresh, size: 14),
                                label: const Text(
                                  '换一个',
                                  style: TextStyle(fontSize: 12),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '后厨平板输入上方配对码后，由云端原子核销并签发 Token；局域网仅透明转发。',
                            style: TextStyle(
                              fontSize: 11,
                              color: Colors.blue.shade900,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                );

                if (isWide) {
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      addressWidget,
                      const SizedBox(width: 12),
                      pairingWidget,
                    ],
                  );
                } else {
                  return Column(
                    children: [
                      addressWidget,
                      const SizedBox(height: 12),
                      pairingWidget,
                    ],
                  );
                }
              },
            ),
          ],
        ),
      ),
    );
  }


  Widget _buildKdsQuickLoginCard(int shopId) {
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      elevation: 0,
      color: const Color(0xfff0fdf4),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: Color(0xffbbf7d0), width: 1.5),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.flash_on, color: Color(0xff16a34a), size: 22),
                const SizedBox(width: 8),
                const Text(
                  'KDS 后厨大屏极简直登凭证',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Color(0xff15803d),
                  ),
                ),
                const Spacer(),
                OutlinedButton.icon(
                  onPressed: _showEditPinDialog,
                  icon: const Icon(Icons.edit, size: 16),
                  label: const Text('修改 PIN 码'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xff15803d),
                    side: const BorderSide(color: Color(0xff86efac)),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: const Color(0xffdcfce7)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '当前门店编号 (Shop ID)',
                          style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Text(
                              '$shopId',
                              style: const TextStyle(
                                fontSize: 22,
                                fontWeight: FontWeight.bold,
                                color: Color(0xff1e293b),
                              ),
                            ),
                            const SizedBox(width: 8),
                            IconButton(
                              icon: const Icon(Icons.copy, size: 16),
                              tooltip: '复制门店编号',
                              onPressed: () {
                                Clipboard.setData(ClipboardData(text: '$shopId'));
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(content: Text('门店编号已复制')),
                                );
                              },
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: const Color(0xffdcfce7)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'KDS 后厨登录 PIN 码',
                          style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Text(
                              _kdsPin,
                              style: const TextStyle(
                                fontSize: 22,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 2,
                                color: Color(0xff16a34a),
                              ),
                            ),
                            const SizedBox(width: 8),
                            IconButton(
                              icon: const Icon(Icons.copy, size: 16),
                              tooltip: '复制 PIN 码',
                              onPressed: () {
                                Clipboard.setData(ClipboardData(text: _kdsPin));
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(content: Text('PIN 码已复制')),
                                );
                              },
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              '💡 使用方法：后厨新屏开机打开 KDS，只需输入上方【门店编号: $shopId】与【PIN 码: $_kdsPin】，点击登录即可秒级自动绑定接入并进入做菜看板，无需人工手动添加设备或获取配对码。',
              style: const TextStyle(fontSize: 13, color: Color(0xff166534), height: 1.4),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showEditPinDialog() async {
    final ctrl = TextEditingController(text: _kdsPin);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('修改 KDS 登录 PIN 码'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('请为本店后厨屏幕设置专属简易 PIN 码（建议 6 位数字）：'),
            const SizedBox(height: 12),
            TextField(
              controller: ctrl,
              autofocus: true,
              keyboardType: TextInputType.number,
              maxLength: 12,
              decoration: const InputDecoration(
                labelText: 'KDS 登录 PIN 码',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('保存修改'),
          ),
        ],
      ),
    );
    if (confirmed == true && ctrl.text.trim().isNotEmpty) {
      final newPin = ctrl.text.trim();
      try {
        await _client.post(
          kdsConfigSaveEndpoint,
          body: {'kds_pin': newPin},
        );
        if (!mounted) return;
        setState(() => _kdsPin = newPin);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('KDS 登录 PIN 码已更新为 $newPin'), backgroundColor: Colors.green),
        );
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('保存 PIN 码失败: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildKdsQuickLoginCard(widget.currentShopId ?? widget.appState?.currentShopId ?? 1),
        if (widget.showLanPairing) _buildLanPairingCard(),
        Row(
          children: [
            Expanded(
              child: Text(
                widget.showLanPairing || widget.showCloudSync
                    ? '已绑定设备列表（D026 可见烤制岗）'
                    : '已绑定 KDS 设备',
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            if (widget.showCloudSync && widget.canManage) ...[
              OutlinedButton.icon(
                onPressed: _loading || _syncingCloud ? null : _syncAllToCloud,
                icon: _syncingCloud
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.cloud_upload_outlined, size: 18),
                label: const Text('同步到云端'),
              ),
              const SizedBox(width: 8),
            ],
            OutlinedButton.icon(
              onPressed: _loading ? null : _load,
              icon: const Icon(Icons.refresh, size: 18),
              label: const Text('刷新'),
            ),
            if (widget.canManage) ...[
              const SizedBox(width: 8),
              FilledButton.icon(
                onPressed: () => _openForm(),
                icon: const Icon(Icons.add, size: 18),
                label: const Text('绑定设备'),
              ),
            ],
          ],
        ),
        const SizedBox(height: 12),
        Expanded(child: _buildBody()),
      ],
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_error!, style: TextStyle(color: Colors.red.shade700)),
            const SizedBox(height: 8),
            OutlinedButton(onPressed: _load, child: const Text('重试')),
          ],
        ),
      );
    }
    if (_devices.isEmpty) {
      return Center(
        child: Text(widget.canManage ? '暂无设备，点击右上角「绑定设备」添加' : '暂无已绑定设备'),
      );
    }
    return Card(
      child: ListView.separated(
        itemCount: _devices.length,
        separatorBuilder: (_, __) => const Divider(height: 1),
        itemBuilder: (context, index) {
          final device = _devices[index];
          final code = '${device['device_code'] ?? '—'}';
          final name = '${device['device_name'] ?? ''}';
          final screenTag = '${device['screen_tag'] ?? '—'}';
          final tags = device['screen_tags'] as List<Object?>?;
          final enabled = device['enabled'];
          final enabledFlag = enabled is num
              ? enabled.toInt() != 0
              : enabled != false;
          return ListTile(
            dense: true,
            onTap: widget.canManage ? () => _openForm(device) : null,
            title: Text(
              name.isEmpty ? code : '$name（$code）',
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            subtitle: Text(
              '屏幕 $screenTag · 可见岗：${_tagsLabel(tags)}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  enabledFlag ? Icons.check_circle : Icons.cancel,
                  size: 18,
                  color: enabledFlag ? Colors.green.shade600 : Colors.grey,
                ),
                if (widget.canManage) ...[
                  const SizedBox(width: 4),
                  IconButton(
                    tooltip: '编辑',
                    icon: Icon(
                      Icons.edit_outlined,
                      size: 18,
                      color: Colors.grey.shade600,
                    ),
                    onPressed: () => _openForm(device),
                  ),
                  IconButton(
                    tooltip: '删除',
                    icon: Icon(
                      Icons.delete_outline,
                      size: 18,
                      color: Colors.red.shade600,
                    ),
                    onPressed: () => _confirmDelete(device),
                  ),
                ],
              ],
            ),
          );
        },
      ),
    );
  }
}

class _DeviceFormDialog extends StatefulWidget {
  const _DeviceFormDialog({
    required this.client,
    this.initial,
    this.kdsRuntime,
    this.shopId,
  });

  final AdminApiClient client;
  final Map<String, Object?>? initial;
  final CashierKdsRuntime? kdsRuntime;
  final int? shopId;

  @override
  State<_DeviceFormDialog> createState() => _DeviceFormDialogState();
}

class _DeviceFormDialogState extends State<_DeviceFormDialog> {
  late final TextEditingController _codeController;
  late final TextEditingController _nameController;
  late final TextEditingController _screenTagController;
  late final Set<String> _selectedTags;
  bool _saving = false;
  String? _error;

  bool get _isEdit => widget.initial != null;

  @override
  void initState() {
    super.initState();
    final initial = widget.initial;
    _codeController = TextEditingController(
      text: '${initial?['device_code'] ?? ''}',
    );
    _nameController = TextEditingController(
      text: '${initial?['device_name'] ?? ''}',
    );
    _screenTagController = TextEditingController(
      text: '${initial?['screen_tag'] ?? 'workflow_board'}',
    );
    final tags = initial?['screen_tags'];
    _selectedTags = <String>{
      if (tags is List)
        for (final t in tags.whereType<String>())
          if (_kGrillTags.containsKey(t)) t,
    };
  }

  @override
  void dispose() {
    _codeController.dispose();
    _nameController.dispose();
    _screenTagController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final code = _codeController.text.trim();
    final screenTag = _screenTagController.text.trim();
    if (code.isEmpty) {
      setState(() => _error = '设备编号（deviceCode）不能为空');
      return;
    }
    if (screenTag.isEmpty) {
      setState(() => _error = '屏幕类型（screenTag）不能为空');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final body = <String, Object?>{
        'deviceCode': code,
        'screenTag': screenTag,
        if (_nameController.text.trim().isNotEmpty)
          'deviceName': _nameController.text.trim(),
        // 不选/空 = 省略 = 服务端回退三岗全选（旧设备兼容）
        if (_selectedTags.isNotEmpty) 'screenTags': _selectedTags.toList(),
      };
      final result = await widget.client.post(
        kdsDeviceBindEndpoint,
        body: body,
      );
      if (result is! Map || result['device'] == null) {
        throw StateError('云端未返回已绑定设备');
      }

      Object? cacheError;
      if (widget.kdsRuntime != null) {
        try {
          await widget.kdsRuntime!.upsertBoundDevice(
            shopId: widget.shopId ?? 1,
            deviceCode: code,
            deviceName: _nameController.text.trim().isEmpty
                ? code
                : _nameController.text.trim(),
            screenTag: screenTag,
            screenTags: _selectedTags.toList(),
          );
        } catch (e) {
          cacheError = e;
        }
      }
      if (!mounted) return;
      if (cacheError != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('云端已绑定，本地缓存刷新失败，将在下次同步时重试: $cacheError'),
            backgroundColor: Colors.orange,
          ),
        );
      }
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = '$e';
      });
    }
  }

  Future<void> _handleDelete() async {
    final code = _codeController.text.trim();
    if (code.isEmpty) return;
    final name = _nameController.text.trim();
    final displayName = name.isEmpty ? code : '$name（$code）';

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除设备'),
        content: Text('确定要删除/解绑设备「$displayName」吗？删除后该设备需重新绑定方可接入。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red.shade600),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() {
      _saving = true;
      _error = null;
    });

    try {
      final effectiveShopId = widget.shopId ?? 1;
      await widget.client.post(
        kdsDeviceUnbindEndpoint,
        body: {'device_code': code, 'deviceCode': code},
      );
      Object? cacheError;
      if (widget.kdsRuntime != null) {
        try {
          await widget.kdsRuntime!.unbindDevice(
            shopId: effectiveShopId,
            deviceCode: code,
          );
        } catch (e) {
          cacheError = e;
        }
      }
      if (!mounted) return;
      if (cacheError != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('云端已删除，本地缓存刷新失败，将在下次同步时重试: $cacheError'),
            backgroundColor: Colors.orange,
          ),
        );
      }
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = '删除失败: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(_isEdit ? '编辑设备（可见岗）' : '绑定设备（可见岗）'),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: _codeController,
                enabled: !_isEdit,
                decoration: const InputDecoration(
                  labelText: '设备编号（deviceCode）*',
                  hintText: '如 KDS-GRILL-01',
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _nameController,
                decoration: const InputDecoration(
                  labelText: '设备名称（可选）',
                  hintText: '如 烤台一',
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _screenTagController,
                decoration: const InputDecoration(
                  labelText: '屏幕类型（screenTag）*',
                  helperText: '统一看板使用 workflow_board',
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                '可见烤制岗（不选 = 三岗全选，旧设备兼容）',
                style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
              ),
              for (final entry in _kGrillTags.entries)
                CheckboxListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.leading,
                  title: Text(
                    '${entry.value}（${entry.key}）',
                    style: const TextStyle(fontSize: 13),
                  ),
                  value: _selectedTags.contains(entry.key),
                  onChanged: (checked) {
                    setState(() {
                      if (checked == true) {
                        _selectedTags.add(entry.key);
                      } else {
                        _selectedTags.remove(entry.key);
                      }
                    });
                  },
                ),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text(
                    _error!,
                    style: TextStyle(color: Colors.red.shade700, fontSize: 13),
                  ),
                ),
            ],
          ),
        ),
      ),
      actions: [
        if (_isEdit)
          TextButton.icon(
            style: TextButton.styleFrom(foregroundColor: Colors.red.shade600),
            onPressed: _saving ? null : _handleDelete,
            icon: const Icon(Icons.delete_outline, size: 16),
            label: const Text('删除设备'),
          ),
        TextButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(false),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: _saving
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('保存'),
        ),
      ],
    );
  }
}
