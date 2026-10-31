import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../cashier_shell/presentation/cashier_tokens.dart';

/// 安卓平板自带摄像头扫码取景器组件
/// 在不需要外接扫码枪的情况下，利用平板自带摄像头直接扫描顾客微信付款码。
class PosCameraScannerView extends StatefulWidget {
  const PosCameraScannerView({
    super.key,
    required this.onBarcodeScanned,
    required this.onSwitchToManualOrGun,
    this.initialIsFrontCamera = false,
    this.controller,
  });

  /// 扫描成功识别出 18 位付款码时的回调
  final ValueChanged<String> onBarcodeScanned;

  /// 收银员点击切回扫码枪或键盘输入时的回调
  final VoidCallback onSwitchToManualOrGun;

  /// 初始是否使用前置摄像头
  final bool initialIsFrontCamera;

  /// 可选注入的扫描控制器（便于测试或上层定制）
  final MobileScannerController? controller;

  @override
  State<PosCameraScannerView> createState() => _PosCameraScannerViewState();
}

class _PosCameraScannerViewState extends State<PosCameraScannerView>
    with SingleTickerProviderStateMixin {
  late final AnimationController _scanAnimationController;
  late final Animation<double> _scanAnimation;

  late bool _isFrontCamera;
  bool _torchEnabled = false;
  bool _hasScanned = false;

  MobileScannerController? _internalController;
  MobileScannerController? get _activeController => widget.controller ?? _internalController;

  static bool get _isTestEnvironment {
    if (kIsWeb) return false;
    try {
      return Platform.environment.containsKey('FLUTTER_TEST');
    } catch (_) {
      return false;
    }
  }

  @override
  void initState() {
    super.initState();
    _isFrontCamera = widget.initialIsFrontCamera;
    _scanAnimationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2200),
    )..repeat(reverse: true);

    _scanAnimation = CurvedAnimation(
      parent: _scanAnimationController,
      curve: Curves.easeInOut,
    );

    if (widget.controller == null && !_isTestEnvironment) {
      _internalController = MobileScannerController(
        facing: _isFrontCamera ? CameraFacing.front : CameraFacing.back,
        torchEnabled: _torchEnabled,
        detectionSpeed: DetectionSpeed.normal,
        autoStart: true,
      );
    }
  }

  @override
  void dispose() {
    _scanAnimationController.dispose();
    _internalController?.dispose();
    super.dispose();
  }

  Future<void> _toggleCameraLens() async {
    setState(() {
      _isFrontCamera = !_isFrontCamera;
    });
    try {
      await _activeController?.switchCamera();
    } catch (_) {}
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          _isFrontCamera
              ? '已切换为前置摄像头（适合立式收银台顾客主动贴合扫码）'
              : '已切换为后置摄像头（适合手持平板对准顾客付款码）',
        ),
        duration: const Duration(seconds: 1),
      ),
    );
  }

  Future<void> _toggleTorch() async {
    setState(() {
      _torchEnabled = !_torchEnabled;
    });
    try {
      await _activeController?.toggleTorch();
    } catch (_) {}
  }

  void _onDetect(BarcodeCapture capture) {
    if (_hasScanned) return;
    for (final barcode in capture.barcodes) {
      final code = (barcode.rawValue ?? barcode.displayValue ?? '').trim();
      if (code.isNotEmpty) {
        _hasScanned = true;
        widget.onBarcodeScanned(code);
        break;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // 摄像头取景器视口
        Container(
          height: 250,
          decoration: BoxDecoration(
            color: Colors.black,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: context.cashier.border),
          ),
          clipBehavior: Clip.antiAlias,
          child: Stack(
            alignment: Alignment.center,
            children: [
              // 实际摄像头画面 (使用 mobile_scanner 实时取景)
              Positioned.fill(
                child: _activeController != null
                    ? MobileScanner(
                        controller: _activeController,
                        fit: BoxFit.cover,
                        onDetect: _onDetect,
                        placeholderBuilder: (ctx) => Container(
                          color: const Color(0xFF091220),
                          child: const Center(
                            child: SizedBox(
                              width: 32,
                              height: 32,
                              child: CircularProgressIndicator(
                                strokeWidth: 2.5,
                                color: Color(0xFF38BDF8),
                              ),
                            ),
                          ),
                        ),
                        errorBuilder: (ctx, error) => Container(
                          color: const Color(0xFF0F172A),
                          padding: const EdgeInsets.all(16),
                          child: Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(
                                  Icons.videocam_off_rounded,
                                  color: Colors.amber,
                                  size: 36,
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  error.errorCode == MobileScannerErrorCode.permissionDenied
                                      ? '未授予相机权限，请在安卓系统设置中允许相机访问'
                                      : '无法启动摄像头: ${error.errorDetails?.message ?? error.errorCode.name}',
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 12,
                                  ),
                                ),
                                const SizedBox(height: 10),
                                OutlinedButton(
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: Colors.white,
                                    side: const BorderSide(color: Colors.white38),
                                  ),
                                  onPressed: widget.onSwitchToManualOrGun,
                                  child: const Text('切回扫码枪/键盘'),
                                ),
                              ],
                            ),
                          ),
                        ),
                      )
                    : DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [
                              const Color(0xFF091220),
                              _torchEnabled
                                  ? const Color(0xFF334155)
                                  : const Color(0xFF1E293B),
                              const Color(0xFF0F172A),
                            ],
                          ),
                        ),
                      ),
              ),

              // 顶部对准提示药丸
              Positioned(
                top: 10,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.6),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.white10),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.crop_free_rounded, size: 14, color: context.cashier.selected),
                      const SizedBox(width: 4),
                      const Text(
                        '请将顾客微信付款码（条形码/二维码）对准扫描框',
                        style: TextStyle(fontSize: 11, color: Colors.white70),
                      ),
                    ],
                  ),
                ),
              ),

              // 取景对准框与暗化遮罩
              _buildTargetReticle(context),

              // 底部控制按钮浮条
              Positioned(
                bottom: 10,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0F172A).withValues(alpha: 0.85),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: Colors.white12),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TextButton.icon(
                        key: const Key('camera-switch-lens-button'),
                        style: TextButton.styleFrom(
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          minimumSize: Size.zero,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                        icon: const Icon(Icons.flip_camera_ios_rounded, size: 14),
                        label: Text(
                          _isFrontCamera ? '前置镜头' : '后置镜头',
                          style: const TextStyle(fontSize: 11),
                        ),
                        onPressed: _toggleCameraLens,
                      ),
                      Container(
                        width: 1,
                        height: 12,
                        color: Colors.white24,
                        margin: const EdgeInsets.symmetric(horizontal: 4),
                      ),
                      TextButton.icon(
                        key: const Key('camera-toggle-torch-button'),
                        style: TextButton.styleFrom(
                          foregroundColor: _torchEnabled ? Colors.amber : Colors.white70,
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          minimumSize: Size.zero,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                        icon: Icon(
                          _torchEnabled ? Icons.flash_on_rounded : Icons.flash_off_rounded,
                          size: 14,
                        ),
                        label: Text(
                          _torchEnabled ? '补光已开' : '补光关',
                          style: const TextStyle(fontSize: 11),
                        ),
                        onPressed: _toggleTorch,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 14),

        // 底部动作栏：切回扫码枪
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                Icon(Icons.tablet_android_rounded, size: 16, color: context.cashier.inkMuted),
                const SizedBox(width: 4),
                Text(
                  '平板摄像头免扫码枪扫码模式',
                  style: TextStyle(fontSize: 12, color: context.cashier.inkMuted),
                ),
              ],
            ),
            OutlinedButton.icon(
              key: const Key('camera-switch-to-scanner-gun-button'),
              icon: const Icon(Icons.keyboard_alt_outlined, size: 16),
              label: const Text('切回扫码枪/键盘'),
              onPressed: widget.onSwitchToManualOrGun,
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildTargetReticle(BuildContext context) {
    const reticleWidth = 240.0;
    const reticleHeight = 150.0;

    return Stack(
      alignment: Alignment.center,
      children: [
        // 目标框四角定位
        SizedBox(
          width: reticleWidth,
          height: reticleHeight,
          child: Stack(
            children: [
              // 四角直角边框
              _buildCorner(top: 0, left: 0, isTop: true, isLeft: true),
              _buildCorner(top: 0, right: 0, isTop: true, isLeft: false),
              _buildCorner(bottom: 0, left: 0, isTop: false, isLeft: true),
              _buildCorner(bottom: 0, right: 0, isTop: false, isLeft: false),

              // 激光动态往复扫描线
              AnimatedBuilder(
                animation: _scanAnimation,
                builder: (context, _) {
                  return Positioned(
                    top: _scanAnimation.value * (reticleHeight - 10) + 5,
                    left: 6,
                    right: 6,
                    child: Container(
                      height: 2.5,
                      decoration: BoxDecoration(
                        color: const Color(0xFF38BDF8),
                        boxShadow: const [
                          BoxShadow(
                            color: Color(0xFF38BDF8),
                            blurRadius: 8,
                            spreadRadius: 1,
                          ),
                          BoxShadow(
                            color: Color(0xFF0284C7),
                            blurRadius: 14,
                            spreadRadius: 2,
                          ),
                        ],
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  );
                },
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildCorner({
    double? top,
    double? bottom,
    double? left,
    double? right,
    required bool isTop,
    required bool isLeft,
  }) {
    const size = 18.0;
    const thickness = 3.5;
    const color = Color(0xFF38BDF8);

    return Positioned(
      top: top,
      bottom: bottom,
      left: left,
      right: right,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          border: Border(
            top: isTop ? const BorderSide(color: color, width: thickness) : BorderSide.none,
            bottom: !isTop ? const BorderSide(color: color, width: thickness) : BorderSide.none,
            left: isLeft ? const BorderSide(color: color, width: thickness) : BorderSide.none,
            right: !isLeft ? const BorderSide(color: color, width: thickness) : BorderSide.none,
          ),
          borderRadius: BorderRadius.only(
            topLeft: isTop && isLeft ? const Radius.circular(6) : Radius.zero,
            topRight: isTop && !isLeft ? const Radius.circular(6) : Radius.zero,
            bottomLeft: !isTop && isLeft ? const Radius.circular(6) : Radius.zero,
            bottomRight: !isTop && !isLeft ? const Radius.circular(6) : Radius.zero,
          ),
        ),
      ),
    );
  }
}
