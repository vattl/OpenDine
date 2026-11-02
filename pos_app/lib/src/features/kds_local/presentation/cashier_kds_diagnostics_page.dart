import 'dart:io';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../domain/cashier_kds_interaction_log.dart';
import '../runtime/cashier_kds_runtime.dart';
import 'cashier_kds_interaction_log_table.dart';

class CashierKdsDiagnosticsPage extends StatelessWidget {
  const CashierKdsDiagnosticsPage({
    super.key,
    required this.runtime,
    this.canManage = false,
  });

  final CashierKdsRuntime runtime;
  final bool canManage;

  @override
  Widget build(BuildContext context) => DefaultTabController(
    length: 2,
    child: Scaffold(
      appBar: AppBar(
        title: const Text('KDS 代理管理'),
        bottom: const TabBar(
          tabs: [
            Tab(text: 'KDS 连接'),
            Tab(text: '代理请求'),
          ],
        ),
      ),
      body: TabBarView(
        children: [
          CashierKdsConnectionPanel(runtime: runtime, canManage: canManage),
          CashierKdsProxyRequestPanel(runtime: runtime),
        ],
      ),
    ),
  );
}

class CashierKdsConnectionPanel extends StatefulWidget {
  const CashierKdsConnectionPanel({
    super.key,
    required this.runtime,
    this.canManage = false,
  });

  final CashierKdsRuntime runtime;
  final bool canManage;

  @override
  State<CashierKdsConnectionPanel> createState() =>
      _CashierKdsConnectionPanelState();
}

class _CashierKdsConnectionPanelState extends State<CashierKdsConnectionPanel> {
  List<String> _addresses = const [];
  bool _refreshing = false;
  bool _restarting = false;
  bool _generatingCert = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    unawaited(_loadAddresses());
  }

  Future<void> _loadAddresses() async {
    try {
      final addresses = await widget.runtime.lanAddresses();
      if (!mounted) return;
      setState(() {
        _addresses = addresses;
        _error = null;
      });
    } catch (error) {
      if (mounted) setState(() => _error = '$error');
    }
  }

  Future<void> _refresh() async {
    if (_refreshing) return;
    setState(() => _refreshing = true);
    try {
      await widget.runtime.refreshProxyListener();
      await _loadAddresses();
      if (mounted) setState(() {});
    } catch (error) {
      if (mounted) setState(() => _error = '$error');
    } finally {
      if (mounted) setState(() => _refreshing = false);
    }
  }

  Future<void> _restart() async {
    if (_restarting) return;
    setState(() => _restarting = true);
    try {
      await widget.runtime.restartLanServer();
      await _loadAddresses();
      if (mounted) setState(() {});
    } catch (error) {
      if (mounted) setState(() => _error = '$error');
    } finally {
      if (mounted) setState(() => _restarting = false);
    }
  }

  Future<void> _regenerateCerts() async {
    if (_generatingCert) return;
    setState(() => _generatingCert = true);
    try {
      await widget.runtime.regenerateTlsCertificates();
      await _loadAddresses();
      if (mounted) {
        setState(() {});
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('已重新生成局域网 TLS 证书并重启监听'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('生成证书失败: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _generatingCert = false);
    }
  }

  Future<void> _exportCaCertificate() async {
    final caPath = widget.runtime.caCertificatePath;
    if (caPath == null || caPath.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('当前未找到门店根 CA 证书文件')),
      );
      return;
    }
    final file = File(caPath);
    String pem = '';
    if (file.existsSync()) {
      try {
        pem = file.readAsStringSync();
      } catch (_) {}
    }
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.verified_user, color: Colors.blue),
            SizedBox(width: 8),
            Text('门店根 CA 证书 (ca.crt)'),
          ],
        ),
        content: SizedBox(
          width: 520,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                '请将此根 CA 证书安装至各后厨触屏设备（受信任的根证书颁发机构），以确保局域网 WSS / HTTPS 安全通信无报警。',
                style: TextStyle(fontSize: 13, color: Colors.black87),
              ),
              const SizedBox(height: 12),
              Text(
                '本地文件路径：',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.grey[700]),
              ),
              const SizedBox(height: 4),
              SelectableText(
                caPath,
                style: const TextStyle(fontSize: 12, fontFamily: 'monospace'),
              ),
              if (pem.isNotEmpty) ...[
                const SizedBox(height: 12),
                Text(
                  '证书内容预览 (PEM)：',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.grey[700]),
                ),
                const SizedBox(height: 4),
                Container(
                  height: 120,
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.grey[100],
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: Colors.grey[300]!),
                  ),
                  child: SingleChildScrollView(
                    child: SelectableText(
                      pem,
                      style: const TextStyle(fontSize: 11, fontFamily: 'monospace'),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
        actions: [
          OutlinedButton.icon(
            onPressed: () {
              Clipboard.setData(ClipboardData(text: caPath));
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('已复制 CA 文件路径到剪贴板')),
              );
            },
            icon: const Icon(Icons.copy, size: 16),
            label: const Text('复制路径'),
          ),
          if (pem.isNotEmpty)
            FilledButton.icon(
              onPressed: () {
                Clipboard.setData(ClipboardData(text: pem));
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('已复制 CA 证书内容 (PEM) 到剪贴板')),
                );
              },
              icon: const Icon(Icons.content_copy, size: 16),
              label: const Text('复制证书 PEM'),
            ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('关闭'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final runtime = widget.runtime;
    final running = runtime.lanStatus == 'active' && runtime.lanPort > 0;
    CashierKdsInteractionLog? latestProxy;
    for (final log in runtime.interactionLogs) {
      if (log.stage == KdsInteractionStage.proxyHttpForward ||
          log.stage == KdsInteractionStage.proxyWebSocketForward) {
        latestProxy = log;
        break;
      }
    }
    final upstreamHealthy =
        latestProxy != null && !latestProxy.status.isProblem;
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'KDS 连接',
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 4),
                  const Text('收银端仅提供局域网接入，并将 KDS 请求透明转发至云端。'),
                ],
              ),
            ),
            OutlinedButton.icon(
              key: const Key('kds-connection-refresh'),
              onPressed: _refreshing ? null : _refresh,
              icon: _refreshing
                  ? const SizedBox.square(
                      dimension: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.refresh),
              label: Text(_refreshing ? '刷新中' : '刷新连接状态'),
            ),
          ],
        ),
        const SizedBox(height: 20),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            _MetricCard(
              label: '局域网代理',
              value: running ? '运行中' : _statusLabel(runtime.lanStatus),
              healthy: running,
            ),
            _MetricCard(
              label: '当前 LAN 代理连接',
              value: '${runtime.connectedDeviceCount} 台',
              // Cloud-first KDS devices normally connect straight to cloud.
              // Zero is therefore an idle proxy, not a cashier-side failure.
              healthy: running,
            ),
            _MetricCard(
              label: '云端上游',
              value: latestProxy == null
                  ? '等待首个请求'
                  : upstreamHealthy
                  ? '最近请求正常'
                  : '最近请求异常',
              healthy: upstreamHealthy,
            ),
          ],
        ),
        const SizedBox(height: 16),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text('连接信息', style: Theme.of(context).textTheme.titleLarge),
                    const Spacer(),
                    if (widget.canManage) ...[
                      OutlinedButton.icon(
                        key: const Key('kds-export-ca-button'),
                        onPressed: _exportCaCertificate,
                        icon: const Icon(Icons.shield_outlined),
                        label: const Text('导出门店根 CA'),
                      ),
                      const SizedBox(width: 8),
                      OutlinedButton.icon(
                        key: const Key('kds-regenerate-cert-button'),
                        onPressed: _generatingCert ? null : _regenerateCerts,
                        icon: _generatingCert
                            ? const SizedBox.square(
                                dimension: 16,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.autorenew),
                        label: Text(_generatingCert ? '签发中' : '重新签发证书'),
                      ),
                      const SizedBox(width: 8),
                      OutlinedButton.icon(
                        key: const Key('kds-proxy-restart-button'),
                        onPressed: _restarting ? null : _restart,
                        icon: const Icon(Icons.restart_alt),
                        label: Text(_restarting ? '重启中' : '重启代理监听'),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 16),
                _ConnectionRow(
                  label: '本机设备编码',
                  value: runtime.cashierDeviceCode.isEmpty
                      ? '—'
                      : runtime.cashierDeviceCode,
                ),
                _ConnectionRow(
                  label: '监听端口',
                  value:
                      '${runtime.lanPort > 0 ? runtime.lanPort : runtime.configuredPort}',
                ),
                _ConnectionRow(
                  label: 'LAN 传输保护',
                  value: runtime.lanCertificateSha256 != null
                      ? 'TLS 已启用'
                      : 'TLS 未配置',
                ),
                if (runtime.lanCertificateSha256 case final fingerprint?)
                  _CopyableConnectionRow(
                    label: '证书 SHA-256',
                    value: fingerprint,
                  ),
                if (runtime.caCertificatePath case final caPath?)
                  _CopyableConnectionRow(
                    label: '门店根 CA 路径',
                    value: caPath,
                  ),
                if (runtime.serverCertificatePath case final serverPath?)
                  _CopyableConnectionRow(
                    label: '服务端证书路径',
                    value: serverPath,
                  ),
                if (_addresses.isEmpty)
                  const _ConnectionRow(label: 'KDS 局域网地址', value: '暂无可用私网地址')
                else
                  for (final address in _addresses) ...[
                    _CopyableConnectionRow(label: 'KDS 局域网地址', value: address),
                    _CopyableConnectionRow(
                      label: 'WebSocket 地址',
                      value: _webSocketAddress(address),
                    ),
                  ],
                const _ConnectionRow(
                  label: '职责边界',
                  value: '连接接入、请求透明转发与有限只读响应缓存；鉴权和业务结果以云端为准',
                ),
                if (runtime.lanError case final error?) ...[
                  const SizedBox(height: 12),
                  Text(
                    error,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ],
                if (_error case final error?) ...[
                  const SizedBox(height: 12),
                  Text(
                    error,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }

  static String _statusLabel(String status) => switch (status) {
    'waiting_for_login' => '等待登录',
    'waiting_for_cloud_proxy' => '等待云端会话',
    'listen_blocked' => '安全监听已阻断',
    'listen_failed' => '监听失败',
    _ => '未运行',
  };

  static String _webSocketAddress(String address) {
    final uri = Uri.tryParse(address);
    if (uri == null || uri.host.isEmpty) return address;
    return uri
        .replace(
          scheme: uri.scheme.toLowerCase() == 'https' ? 'wss' : 'ws',
          path: '/ws/kds/v2',
        )
        .toString();
  }
}

class CashierKdsProxyRequestPanel extends StatefulWidget {
  const CashierKdsProxyRequestPanel({super.key, required this.runtime});

  final CashierKdsRuntime runtime;

  @override
  State<CashierKdsProxyRequestPanel> createState() =>
      _CashierKdsProxyRequestPanelState();
}

class _CashierKdsProxyRequestPanelState
    extends State<CashierKdsProxyRequestPanel> {
  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.all(24),
    children: [
      CashierKdsInteractionLogTable(
        logs: widget.runtime.interactionLogs,
        droppedLogCount: widget.runtime.droppedInteractionLogCount,
        onRefresh: () async => setState(() {}),
      ),
    ],
  );
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({
    required this.label,
    required this.value,
    required this.healthy,
  });

  final String label;
  final String value;
  final bool healthy;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 240,
    child: Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 8),
            Row(
              children: [
                Icon(
                  healthy ? Icons.check_circle : Icons.info_outline,
                  size: 18,
                  color: healthy ? Colors.green : Colors.orange,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    value,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    ),
  );
}

class _ConnectionRow extends StatelessWidget {
  const _ConnectionRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 7),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 150,
          child: Text(label, style: Theme.of(context).textTheme.bodySmall),
        ),
        Expanded(child: SelectableText(value)),
      ],
    ),
  );
}

class _CopyableConnectionRow extends StatelessWidget {
  const _CopyableConnectionRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Expanded(
        child: _ConnectionRow(label: label, value: value),
      ),
      IconButton(
        tooltip: '复制',
        onPressed: () {
          Clipboard.setData(ClipboardData(text: value));
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('已复制')));
        },
        icon: const Icon(Icons.copy, size: 18),
      ),
    ],
  );
}
