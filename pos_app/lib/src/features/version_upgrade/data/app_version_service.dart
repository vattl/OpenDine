import 'dart:async';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:open_filex/open_filex.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/admin_api_client.dart';
import '../../../core/api_contract.dart';
import '../../../core/app_config.dart';
import '../../../core/display_mode.dart';
import '../domain/app_version_info.dart';

typedef ProcessLauncher = Future<Process> Function(
  String executable,
  List<String> arguments, {
  ProcessStartMode mode,
});

typedef UrlLauncher = Future<bool> Function(
  Uri url, {
  LaunchMode mode,
});

typedef FileOpener = Future<OpenResult> Function(
  String filePath, {
  String? type,
});

typedef ExitHandler = void Function(int code);

class AppPackageVerificationException implements Exception {
  const AppPackageVerificationException({
    required this.message,
    this.expectedSha256,
    this.actualSha256,
    this.expectedFileSize,
    this.actualFileSize,
    this.isHtmlFallback = false,
    this.previewHtml,
  });

  final String message;
  final String? expectedSha256;
  final String? actualSha256;
  final int? expectedFileSize;
  final int? actualFileSize;
  final bool isHtmlFallback;
  final String? previewHtml;

  @override
  String toString() => message;
}

class AppVersionService {
  const AppVersionService({
    required this.client,
    this.httpClient,
    this.processLauncher,
    this.urlLauncher,
    this.fileOpener,
    this.exitHandler,
  });

  final AdminApiClient client;
  final http.Client? httpClient;
  final ProcessLauncher? processLauncher;
  final UrlLauncher? urlLauncher;
  final FileOpener? fileOpener;
  final ExitHandler? exitHandler;

  /// 解析当前设备运行平台
  static String resolveCurrentPlatform() {
    if (kIsWeb) return 'web';
    switch (defaultTargetPlatform) {
      case TargetPlatform.windows:
        return 'windows';
      case TargetPlatform.android:
        return 'android';
      case TargetPlatform.iOS:
        return 'ios';
      case TargetPlatform.macOS:
      case TargetPlatform.linux:
      default:
        return 'desktop';
    }
  }

  /// 解析当前分发渠道
  static String resolveCurrentChannel() {
    return kIsMobileApp ? 'mobile' : 'pos';
  }

  /// 检查新版本策略
  Future<AppVersionInfo> checkUpdate({
    String? platform,
    String? channel,
    String? currentVersion,
    int? versionCode,
    int? shopId,
  }) async {
    final query = <String, String>{
      'platform': platform ?? resolveCurrentPlatform(),
      'channel': channel ?? resolveCurrentChannel(),
      'current_version': currentVersion ?? AppConfig.version,
      'version_code': '${versionCode ?? AppConfig.buildNumber}',
    };
    if (shopId != null && shopId > 0) {
      query['shop_id'] = '$shopId';
    }

    try {
      final data = await client.get(
        appVersionEndpoint,
        query: query,
      );
      return AppVersionInfo.fromJson(data);
    } on ApiException catch (error) {
      // 404 说明服务端未配置当前平台/渠道的版本更新策略
      if (error.statusCode == 404 || error.code == 404) {
        return AppVersionInfo(
          platform: query['platform']!,
          channel: query['channel']!,
          latest: query['current_version']!,
          hasUpdate: false,
          upgradeType: UpgradeType.none,
          installMode: InstallMode.interactive,
        );
      }
      rethrow;
    }
  }

  /// 下载安装包到指定路径，支持实时进度汇报与 HTML/大小异常预检
  Future<File> downloadPackage({
    required String downloadUrl,
    required String savePath,
    int? expectedFileSize,
    void Function(int received, int total)? onProgress,
  }) async {
    final clientToUse = httpClient ?? http.Client();
    final shouldCloseClient = httpClient == null;

    try {
      final targetUri = Uri.parse(downloadUrl);
      var response = await clientToUse.send(http.Request('GET', targetUri));

      // 若检测到响应类型为网页 HTML，尝试向后台官方直链 /admin/app/packages/ 进行智能路由回退
      final initialContentType =
          response.headers['content-type']?.toLowerCase() ?? '';
      if (initialContentType.contains('text/html') ||
          initialContentType.contains('text/plain')) {
        if (downloadUrl.contains('/packages/') ||
            downloadUrl.contains('/downloads/')) {
          final fallbackUrl = downloadUrl
              .replaceFirst('/packages/', '/admin/app/packages/')
              .replaceFirst('/downloads/', '/admin/app/packages/windows/');
          if (fallbackUrl != downloadUrl) {
            final fbUri = Uri.parse(fallbackUrl);
            final fbResponse = await clientToUse.send(http.Request('GET', fbUri));
            final fbContentType =
                fbResponse.headers['content-type']?.toLowerCase() ?? '';
            if (fbResponse.statusCode >= 200 &&
                fbResponse.statusCode < 300 &&
                !fbContentType.contains('text/html')) {
              response = fbResponse;
            }
          }
        }
      }

      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw HttpException(
          '下载安装包失败，服务端返回 HTTP ${response.statusCode}',
          uri: targetUri,
        );
      }

      final total = response.contentLength ?? -1;
      var received = 0;

      final targetFile = File(savePath);
      await targetFile.parent.create(recursive: true);
      final sink = targetFile.openWrite();

      try {
        await for (final chunk in response.stream) {
          sink.add(chunk);
          received += chunk.length;
          onProgress?.call(received, total);
        }
      } finally {
        await sink.flush();
        await sink.close();
      }

      final actualSize = await targetFile.length();

      // 小文件安全性与 HTML 页面内容兜底检测
      if (actualSize < 1024 * 10) {
        try {
          final text = await targetFile.readAsString();
          if (text.contains('<!DOCTYPE html') ||
              text.contains('<html') ||
              text.contains('<title>运营后台') ||
              text.contains('<title>点餐系统')) {
            try {
              await targetFile.delete();
            } catch (_) {}
            throw AppPackageVerificationException(
              message: '下载安装包失败：服务端返回了网页(HTML)而非二进制安装包文件。\n'
                  '可能反向代理（如 Nginx）未配置安装包路由，请求回退到了单页应用前端。\n'
                  '页面标题/预览: ${text.length > 200 ? text.substring(0, 200) : text}',
              actualFileSize: actualSize,
              expectedFileSize: expectedFileSize,
              isHtmlFallback: true,
              previewHtml: text,
            );
          }
        } catch (e) {
          if (e is AppPackageVerificationException) rethrow;
        }
      }

      return targetFile;
    } finally {
      if (shouldCloseClient) {
        clientToUse.close();
      }
    }
  }

  /// 计算并强校验文件的 SHA-256 哈希值
  Future<bool> verifySha256({
    required String filePath,
    required String expectedSha256,
    int? expectedFileSize,
  }) async {
    final cleanExpected = expectedSha256
        .replaceAll(RegExp(r'^sha256:', caseSensitive: false), '')
        .replaceAll(RegExp(r'[^a-fA-F0-9]'), '')
        .toLowerCase();
    if (cleanExpected.isEmpty) {
      throw const AppPackageVerificationException(
        message: '未提供有效的 SHA-256 期望值，无法完成安全校验',
      );
    }

    final file = File(filePath);
    if (!await file.exists()) {
      throw const AppPackageVerificationException(
        message: '待校验的本地安装包文件不存在',
      );
    }

    int actualLength = 0;
    Digest digest;
    try {
      actualLength = await file.length();
      digest = await sha256.bind(file.openRead()).first;
    } catch (_) {
      throw const AppPackageVerificationException(
        message: '待校验的本地安装包文件不存在或无法读取',
      );
    }
    final actualHash = digest.toString().toLowerCase();

    if (actualHash != cleanExpected) {
      bool isHtml = false;
      String? preview;
      if (actualLength < 1024 * 10) {
        try {
          final text = await file.readAsString();
          if (text.contains('<!DOCTYPE html') || text.contains('<html')) {
            isHtml = true;
            preview = text.length > 200 ? text.substring(0, 200) : text;
          }
        } catch (_) {}
      }

      throw AppPackageVerificationException(
        message: '安装包 SHA-256 完整性哈希校验失败，已被删除以防篡改。\n'
            '• 策略预期哈希: $cleanExpected\n'
            '• 实际下载哈希: $actualHash\n'
            '• 实际文件大小: $actualLength 字节' +
            (expectedFileSize != null
                ? ' (预期: $expectedFileSize 字节)\n'
                : '\n') +
            (isHtml
                ? '⚠️ 严重排查线索：下载的内容实为 HTML 网页（仅 $actualLength 字节），Nginx 反向代理可能未配置 /admin/app/packages/ 或 /packages/ 路由，导致命中了前端 index.html。\n'
                : '可能文件在传输过程中损坏，或管理后台录入的 SHA-256 签名与文件不一致。'),
        expectedSha256: cleanExpected,
        actualSha256: actualHash,
        expectedFileSize: expectedFileSize,
        actualFileSize: actualLength,
        isHtmlFallback: isHtml,
        previewHtml: preview,
      );
    }

    return true;
  }

  /// 获取适合当前平台的安装包默认保存路径
  Future<String> resolveDownloadSavePath(AppVersionInfo info) async {
    final fileName = _resolveFileName(info);
    if (!kIsWeb && Platform.isWindows) {
      final tempDir = Directory.systemTemp.path;
      return p.join(tempDir, fileName);
    }
    final baseDir = await (kIsWeb
        ? getTemporaryDirectory()
        : getApplicationDocumentsDirectory());
    return p.join(baseDir.path, fileName);
  }

  String _resolveFileName(AppVersionInfo info) {
    if (info.downloadUrl != null && info.downloadUrl!.isNotEmpty) {
      try {
        final uri = Uri.parse(info.downloadUrl!);
        final lastSeg = uri.pathSegments.isNotEmpty ? uri.pathSegments.last : '';
        if (lastSeg.contains('.')) return lastSeg;
      } catch (_) {}
    }
    final ext = info.packageType?.toLowerCase() ??
        (info.platform == 'windows' ? 'exe' : 'apk');
    return 'LaoFei_${info.platform}_${info.latest}.$ext';
  }

  /// 依据 installMode 分流触发安装
  Future<void> executeInstall({
    required AppVersionInfo info,
    String? localFilePath,
  }) async {
    switch (info.installMode) {
      case InstallMode.storeRedirect:
        final urlStr = info.downloadUrl;
        if (urlStr == null || urlStr.trim().isEmpty) {
          throw StateError('未配置应用商店跳转地址');
        }
        final uri = Uri.parse(urlStr);
        final launcher = urlLauncher ?? launchUrl;
        final ok = await launcher(uri, mode: LaunchMode.externalApplication);
        if (!ok) {
          throw StateError('无法唤起应用商店地址: $urlStr');
        }
        break;

      case InstallMode.interactive:
        if (localFilePath == null || localFilePath.isEmpty) {
          throw StateError('交互安装缺少本地安装包路径');
        }
        final opener = fileOpener ?? OpenFilex.open;
        final result = await opener(
          localFilePath,
          type: 'application/vnd.android.package-archive',
        );
        if (result.type != ResultType.done) {
          throw StateError('唤起系统安装器失败: ${result.message}');
        }
        break;

      case InstallMode.silent:
        if (localFilePath == null || localFilePath.isEmpty) {
          throw StateError('静默安装缺少本地安装包路径');
        }
        if (!kIsWeb && Platform.isWindows) {
          final launcher = processLauncher ?? Process.start;
          final isZip = localFilePath.toLowerCase().endsWith('.zip');
          if (isZip) {
            final scriptPath = await _generateWindowsZipUpdaterScript(localFilePath);
            await launcher(
              'powershell.exe',
              [
                '-WindowStyle',
                'Hidden',
                '-ExecutionPolicy',
                'Bypass',
                '-File',
                scriptPath,
              ],
              mode: ProcessStartMode.detached,
            );
          } else {
            // Inno Setup / 常见 Windows 安装包静默安装参数
            await launcher(
              localFilePath,
              ['/VERYSILENT', '/SUPPRESSMSGBOXES', '/NORESTART'],
              mode: ProcessStartMode.detached,
            );
          }
          if (info.isForceUpdate) {
            final onExit = exitHandler ?? exit;
            onExit(0);
          }
        }
        break;
    }
  }

  Future<String> _generateWindowsZipUpdaterScript(String zipPath) async {
    final tempDir = Directory.systemTemp.path;
    final scriptPath = p.join(
      tempDir,
      'cashier_updater_${DateTime.now().millisecondsSinceEpoch}.ps1',
    );
    final scriptFile = File(scriptPath);
    final resolvedExe = Platform.resolvedExecutable;
    final targetDir = File(resolvedExe).parent.path;
    final exeName = p.basename(resolvedExe);
    final appPid = pid;

    final scriptContent = '''
\$ErrorActionPreference = 'SilentlyContinue'
\$currentPid = $appPid
if (\$currentPid -gt 0) {
  try {
    \$proc = Get-Process -Id \$currentPid -ErrorAction SilentlyContinue
    if (\$proc) {
      \$proc.WaitForExit(8000)
    }
  } catch {}
}
Start-Sleep -Milliseconds 500

\$tempExtract = Join-Path \$env:TEMP ('cashier_update_' + [System.Guid]::NewGuid().ToString('N'))
try {
  Expand-Archive -LiteralPath '$zipPath' -DestinationPath \$tempExtract -Force
  \$sourceDir = \$tempExtract
  \$children = Get-ChildItem -LiteralPath \$tempExtract
  if (\$children.Count -eq 1 -and (Test-Path (Join-Path \$children[0].FullName '$exeName'))) {
    \$sourceDir = \$children[0].FullName
  }
  Copy-Item -Path (Join-Path \$sourceDir '*') -Destination '$targetDir' -Recurse -Force
  Remove-Item -LiteralPath \$tempExtract -Recurse -Force -ErrorAction SilentlyContinue
  Start-Process -FilePath (Join-Path '$targetDir' '$exeName') -WorkingDirectory '$targetDir'
} catch {}
''';

    await scriptFile.writeAsString(scriptContent);
    return scriptFile.path;
  }
}

