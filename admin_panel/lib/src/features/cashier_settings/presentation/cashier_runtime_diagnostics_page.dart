import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/crash_log.dart';
import 'cashier_settings_shared.dart';

/// 本机运行与崩溃诊断。
///
/// 该页面不依赖后台接口，确保服务端不可用时仍能取出闪退证据。
class CashierRuntimeDiagnosticsPage extends StatefulWidget {
  const CashierRuntimeDiagnosticsPage({super.key});

  @override
  State<CashierRuntimeDiagnosticsPage> createState() =>
      _CashierRuntimeDiagnosticsPageState();
}

class _CashierRuntimeDiagnosticsPageState
    extends State<CashierRuntimeDiagnosticsPage> {
  late Future<String> _content;
  late Future<String> _location;
  late Future<Map<String, Object?>?> _lastCrashReport;
  bool _showCrashReport = false;
  final ScrollController _vScroll = ScrollController();
  final ScrollController _hScroll = ScrollController();

  @override
  void initState() {
    super.initState();
    _reload();
  }

  @override
  void dispose() {
    _vScroll.dispose();
    _hScroll.dispose();
    super.dispose();
  }

  void _reload() {
    _content = CrashLog.instance.readRecent();
    _location = CrashLog.instance.logFileLocation;
    _lastCrashReport = CrashLog.instance.readLastCrashReport();
  }

  Future<void> _copy() async {
    final String textToCopy;
    if (_showCrashReport) {
      final report = await _lastCrashReport;
      textToCopy = report == null
          ? '（暂无崩溃快照）'
          : const JsonEncoder.withIndent('  ').convert(report);
    } else {
      textToCopy = await _content;
    }
    if (!mounted) return;
    await Clipboard.setData(ClipboardData(text: textToCopy));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(_showCrashReport ? '崩溃诊断快照已复制' : '运行日志已复制')),
    );
  }

  @override
  Widget build(BuildContext context) => SettingsPagePadding(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '本机运行诊断',
                    style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
                  ),
                  SizedBox(height: 5),
                  Text(
                    '原生崩溃会保留最近 5 份 minidump；异常退出将在下次启动时自动生成快照。',
                    style: TextStyle(fontSize: 13, color: Color(0xff737373)),
                  ),
                ],
              ),
            ),
            IconButton(
              tooltip: '刷新',
              onPressed: () => setState(_reload),
              icon: const Icon(Icons.refresh),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Align(
          alignment: Alignment.centerLeft,
          child: SegmentedButton<bool>(
            segments: const [
              ButtonSegment<bool>(
                value: false,
                label: Text('运行日志'),
                icon: Icon(Icons.description_outlined, size: 16),
              ),
              ButtonSegment<bool>(
                value: true,
                label: Text('崩溃快照'),
                icon: Icon(Icons.bug_report_outlined, size: 16),
              ),
            ],
            selected: {_showCrashReport},
            onSelectionChanged: (selection) {
              setState(() => _showCrashReport = selection.first);
            },
          ),
        ),
        const SizedBox(height: 10),
        FutureBuilder<String>(
          future: _showCrashReport
              ? CrashLog.instance.crashReportLocation
              : _location,
          builder: (context, snapshot) => SelectableText(
            '${_showCrashReport ? '崩溃快照' : '日志文件'}：${snapshot.data ?? '…'}',
            style: const TextStyle(fontSize: 12, color: Color(0xff6b7280)),
          ),
        ),
        const SizedBox(height: 12),
        Expanded(
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xff0b1220),
              borderRadius: BorderRadius.circular(10),
            ),
            child: _showCrashReport
                ? FutureBuilder<Map<String, Object?>?>(
                    future: _lastCrashReport,
                    builder: (context, snapshot) {
                      if (snapshot.connectionState != ConnectionState.done) {
                        return const Center(child: CircularProgressIndicator());
                      }
                      final report = snapshot.data;
                      if (report == null) {
                        return const Center(
                          child: Text(
                            '尚未捕获到崩溃或异常退出',
                            style: TextStyle(
                              fontFamily: 'monospace',
                              color: Color(0xff10b981),
                            ),
                          ),
                        );
                      }
                      return _buildConsole(
                        const JsonEncoder.withIndent('  ').convert(report),
                      );
                    },
                  )
                : FutureBuilder<String>(
                    future: _content,
                    builder: (context, snapshot) {
                      if (snapshot.connectionState != ConnectionState.done) {
                        return const Center(child: CircularProgressIndicator());
                      }
                      return _buildConsole(snapshot.data ?? '（暂无日志）');
                    },
                  ),
          ),
        ),
        const SizedBox(height: 12),
        Align(
          alignment: Alignment.centerRight,
          child: OutlinedButton.icon(
            onPressed: _copy,
            icon: const Icon(Icons.copy_outlined, size: 18),
            label: Text(_showCrashReport ? '复制崩溃快照' : '复制运行日志'),
          ),
        ),
      ],
    ),
  );

  Widget _buildConsole(String text) {
    return Scrollbar(
      controller: _vScroll,
      thumbVisibility: true,
      child: Scrollbar(
        controller: _hScroll,
        thumbVisibility: true,
        notificationPredicate: (notif) => notif.metrics.axis == Axis.horizontal,
        child: SingleChildScrollView(
          controller: _vScroll,
          child: SingleChildScrollView(
            controller: _hScroll,
            scrollDirection: Axis.horizontal,
            child: SelectableText(text, style: _consoleStyle),
          ),
        ),
      ),
    );
  }

  static const _consoleStyle = TextStyle(
    fontFamily: 'monospace',
    fontSize: 12,
    height: 1.45,
    color: Color(0xffe2e8f0),
  );
}
