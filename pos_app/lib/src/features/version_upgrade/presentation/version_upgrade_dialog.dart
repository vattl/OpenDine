import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/app_version_service.dart';
import '../domain/app_version_info.dart';

/// 弹出跨平台版本升级弹窗
Future<bool?> showVersionUpgradeDialog(
  BuildContext context, {
  required AppVersionInfo info,
  required AppVersionService service,
  VoidCallback? onPostpone,
}) {
  return showDialog<bool>(
    context: context,
    barrierDismissible: !info.isForceUpdate,
    builder: (dialogContext) => PopScope(
      canPop: !info.isForceUpdate,
      child: Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        clipBehavior: Clip.antiAlias,
        insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520, minWidth: 360),
          child: _VersionUpgradeContent(
            info: info,
            service: service,
            onPostpone: () {
              Navigator.of(dialogContext).pop(false);
              onPostpone?.call();
            },
          ),
        ),
      ),
    ),
  );
}

class _VersionUpgradeContent extends StatefulWidget {
  const _VersionUpgradeContent({
    required this.info,
    required this.service,
    this.onPostpone,
  });

  final AppVersionInfo info;
  final AppVersionService service;
  final VoidCallback? onPostpone;

  @override
  State<_VersionUpgradeContent> createState() => _VersionUpgradeContentState();
}

enum _UpgradeStep { initial, downloading, verifying, ready, error }

class _VersionUpgradeContentState extends State<_VersionUpgradeContent> {
  _UpgradeStep _step = _UpgradeStep.initial;
  double _progress = 0;
  int _receivedBytes = 0;
  int _totalBytes = 0;
  String? _downloadedFilePath;
  String? _errorMessage;

  bool get _isForce => widget.info.isForceUpdate;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildHeader(),
        Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildVersionRow(),
              const SizedBox(height: 16),
              if (_step == _UpgradeStep.initial) ...[
                _buildReleaseNotes(),
                const SizedBox(height: 24),
                _buildActionButtons(),
              ] else if (_step == _UpgradeStep.downloading ||
                  _step == _UpgradeStep.verifying) ...[
                _buildDownloadProgress(),
              ] else if (_step == _UpgradeStep.ready) ...[
                _buildReadyView(),
              ] else if (_step == _UpgradeStep.error) ...[
                _buildErrorView(),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildHeader() {
    final isForce = _isForce;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: isForce
              ? const [Color(0xffb91c1c), Color(0xff7f1d1d)]
              : const [Color(0xff0284c7), Color(0xff0369a1)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Column(
        children: [
          Icon(
            isForce ? Icons.warning_rounded : Icons.rocket_launch_rounded,
            size: 42,
            color: Colors.white,
          ),
          const SizedBox(height: 8),
          Text(
            isForce ? '重要版本强制升级' : '发现新版本',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            isForce
                ? '当前版本已低于最低支持标准，需升级后继续使用'
                : '${widget.info.platform.toUpperCase()} · ${widget.info.installMode.toWire()}',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.9),
              fontSize: 13,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildVersionRow() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: _isForce ? const Color(0xfffee2e2) : const Color(0xffe0f2fe),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                '最新版 V${widget.info.latest}',
                style: TextStyle(
                  color: _isForce ? const Color(0xffdc2626) : const Color(0xff0284c7),
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                ),
              ),
            ),
            if (_isForce) ...[
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xfffee2e2),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Text(
                  '必须更新',
                  style: TextStyle(
                    color: Color(0xffdc2626),
                    fontWeight: FontWeight.w600,
                    fontSize: 12,
                  ),
                ),
              ),
            ],
          ],
        ),
        if (widget.info.formattedFileSize.isNotEmpty)
          Text(
            '大小: ${widget.info.formattedFileSize}',
            style: const TextStyle(color: Color(0xff64748b), fontSize: 13),
          ),
      ],
    );
  }

  Widget _buildReleaseNotes() {
    final notes = widget.info.releaseNotes?.trim();
    return Container(
      constraints: const BoxConstraints(maxHeight: 180),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xfff8fafc),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xffe2e8f0)),
      ),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '更新日志：',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
            ),
            const SizedBox(height: 6),
            Text(
              (notes != null && notes.isNotEmpty) ? notes : '常规性能提升与稳定性优化。',
              style: const TextStyle(
                fontSize: 13,
                height: 1.5,
                color: Color(0xff334155),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActionButtons() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        if (!_isForce) ...[
          OutlinedButton(
            key: const Key('version-upgrade-postpone-button'),
            onPressed: widget.onPostpone,
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            child: const Text('稍后再说'),
          ),
          const SizedBox(width: 12),
        ],
        Expanded(
          flex: _isForce ? 1 : 0,
          child: ElevatedButton(
            key: const Key('version-upgrade-confirm-button'),
            onPressed: _startUpgrade,
            style: ElevatedButton.styleFrom(
              backgroundColor: _isForce ? const Color(0xffdc2626) : const Color(0xff0284c7),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            child: Text(
              widget.info.installMode == InstallMode.storeRedirect
                  ? '前往 App Store 更新'
                  : (_isForce ? '立即升级并重启' : '立即更新'),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildDownloadProgress() {
    final percent = (_progress * 100).clamp(0, 100).toInt();
    final mbReceived = (_receivedBytes / (1024 * 1024)).toStringAsFixed(1);
    final mbTotal = _totalBytes > 0
        ? (_totalBytes / (1024 * 1024)).toStringAsFixed(1)
        : '--';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              _step == _UpgradeStep.verifying ? '正在校验完整性...' : '正在下载安装包...',
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
            ),
            Text(
              _step == _UpgradeStep.verifying ? 'SHA-256' : '$percent%',
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.bold,
                color: Color(0xff0284c7),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: _step == _UpgradeStep.verifying ? null : (_progress > 0 ? _progress : null),
            minHeight: 8,
            backgroundColor: const Color(0xffe2e8f0),
            valueColor: AlwaysStoppedAnimation<Color>(
              _isForce ? const Color(0xffdc2626) : const Color(0xff0284c7),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              '$mbReceived MB / $mbTotal MB',
              style: const TextStyle(fontSize: 12, color: Color(0xff64748b)),
            ),
            const Row(
              children: [
                Icon(Icons.security_rounded, size: 14, color: Color(0xff16a34a)),
                SizedBox(width: 4),
                Text(
                  'SHA-256 防篡改校验',
                  style: TextStyle(fontSize: 12, color: Color(0xff16a34a)),
                ),
              ],
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildReadyView() {
    if (widget.info.installMode == InstallMode.silent && !kIsWeb && Platform.isWindows) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xfff0fdf4),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: const Color(0xffbbf7d0)),
            ),
            child: const Row(
              children: [
                Icon(Icons.check_circle_rounded, color: Color(0xff16a34a)),
                SizedBox(width: 10),
                Expanded(
                  child: Text(
                    '新版本安装包已校验并就绪，是否立即重启应用？',
                    style: TextStyle(fontSize: 13, color: Color(0xff166534)),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              if (!_isForce) ...[
                OutlinedButton(
                  onPressed: widget.onPostpone,
                  child: const Text('稍后重启'),
                ),
                const SizedBox(width: 12),
              ],
              ElevatedButton(
                onPressed: _executeInstall,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xff16a34a),
                  foregroundColor: Colors.white,
                ),
                child: const Text('立即重启完成安装'),
              ),
            ],
          ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: const Color(0xfff0fdf4),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: const Color(0xffbbf7d0)),
          ),
          child: const Row(
            children: [
              Icon(Icons.check_circle_rounded, color: Color(0xff16a34a)),
              SizedBox(width: 10),
              Expanded(
                child: Text(
                  '已成功调起系统安装器，请按屏幕指引完成更新。',
                  style: TextStyle(fontSize: 13, color: Color(0xff166534)),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        if (!_isForce)
          Align(
            alignment: Alignment.centerRight,
            child: ElevatedButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('完成'),
            ),
          ),
      ],
    );
  }

  Widget _buildErrorView() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: const Color(0xfffef2f2),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: const Color(0xfffecaca)),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.error_outline_rounded, color: Color(0xffdc2626)),
              const SizedBox(width: 10),
              Expanded(
                child: SelectableText(
                  _errorMessage ?? '升级失败，请重试',
                  style: const TextStyle(
                    fontSize: 13,
                    color: Color(0xff991b1b),
                    height: 1.4,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            if (_errorMessage != null && _errorMessage!.isNotEmpty) ...[
              OutlinedButton.icon(
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: _errorMessage!));
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('已复制错误诊断信息到剪贴板'),
                      behavior: SnackBarBehavior.floating,
                    ),
                  );
                },
                icon: const Icon(Icons.copy_rounded, size: 16),
                label: const Text('复制错误'),
              ),
              const SizedBox(width: 12),
            ],
            if (!_isForce) ...[
              OutlinedButton(
                onPressed: widget.onPostpone,
                child: const Text('取消'),
              ),
              const SizedBox(width: 12),
            ],
            ElevatedButton(
              onPressed: _startUpgrade,
              child: const Text('重新下载'),
            ),
          ],
        ),
      ],
    );
  }

  Future<void> _startUpgrade() async {
    // 1. 如果是 storeRedirect，直接调起商店并返回
    if (widget.info.installMode == InstallMode.storeRedirect) {
      try {
        await widget.service.executeInstall(info: widget.info);
        if (!_isForce && mounted) {
          Navigator.of(context).pop(true);
        }
      } catch (e) {
        if (mounted) {
          setState(() {
            _step = _UpgradeStep.error;
            _errorMessage = '打开应用商店失败: $e';
          });
        }
      }
      return;
    }

    final downloadUrl = widget.info.downloadUrl;
    if (downloadUrl == null || downloadUrl.trim().isEmpty) {
      setState(() {
        _step = _UpgradeStep.error;
        _errorMessage = '未配置安装包下载地址';
      });
      return;
    }

    setState(() {
      _step = _UpgradeStep.downloading;
      _progress = 0;
      _receivedBytes = 0;
      _totalBytes = 0;
      _errorMessage = null;
    });

    try {
      final savePath = await widget.service.resolveDownloadSavePath(widget.info);
      await widget.service.downloadPackage(
        downloadUrl: downloadUrl,
        savePath: savePath,
        expectedFileSize: widget.info.fileSize,
        onProgress: (received, total) {
          if (mounted) {
            setState(() {
              _receivedBytes = received;
              _totalBytes = total;
              if (total > 0) {
                _progress = received / total;
              }
            });
          }
        },
      );

      if (mounted) {
        setState(() => _step = _UpgradeStep.verifying);
      }

      // 2. 校验 SHA-256
      final expectedSha = widget.info.sha256;
      final isSilentOrForce = widget.info.installMode == InstallMode.silent || _isForce;
      if (isSilentOrForce && (expectedSha == null || expectedSha.trim().isEmpty)) {
        try {
          await File(savePath).delete();
        } catch (_) {}
        throw const AppPackageVerificationException(
          message: '静默/强制更新缺少安全 SHA-256 校验码，更新已终止',
        );
      }
      if (expectedSha != null && expectedSha.trim().isNotEmpty) {
        try {
          await widget.service.verifySha256(
            filePath: savePath,
            expectedSha256: expectedSha,
            expectedFileSize: widget.info.fileSize,
          );
        } catch (e) {
          try {
            await File(savePath).delete();
          } catch (_) {}
          rethrow;
        }
      }

      _downloadedFilePath = savePath;

      // 3. 唤起安装
      if (widget.info.installMode == InstallMode.interactive) {
        await widget.service.executeInstall(
          info: widget.info,
          localFilePath: savePath,
        );
        if (mounted) {
          setState(() => _step = _UpgradeStep.ready);
        }
      } else if (widget.info.installMode == InstallMode.silent) {
        if (_isForce) {
          // 强更直接静默执行并退出
          await widget.service.executeInstall(
            info: widget.info,
            localFilePath: savePath,
          );
        } else {
          if (mounted) {
            setState(() => _step = _UpgradeStep.ready);
          }
        }
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _step = _UpgradeStep.error;
          _errorMessage = error.toString().replaceFirst('Exception: ', '');
        });
      }
    }
  }

  Future<void> _executeInstall() async {
    if (_downloadedFilePath == null) return;
    try {
      await widget.service.executeInstall(
        info: widget.info,
        localFilePath: _downloadedFilePath,
      );
      if (!kIsWeb && Platform.isWindows && widget.info.installMode == InstallMode.silent) {
        exit(0);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _step = _UpgradeStep.error;
          _errorMessage = '执行安装失败: $e';
        });
      }
    }
  }
}
