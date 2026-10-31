import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:admin_panel_flutter/src/core/admin_api_client.dart';
import 'package:admin_panel_flutter/src/core/api_contract.dart';
import 'package:admin_panel_flutter/src/features/version_upgrade/data/app_version_service.dart';
import 'package:admin_panel_flutter/src/features/version_upgrade/domain/app_version_info.dart';
import 'package:admin_panel_flutter/src/features/version_upgrade/presentation/version_upgrade_dialog.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:open_filex/open_filex.dart';
import 'package:url_launcher/url_launcher.dart';

class _FakeApiClient extends Fake implements AdminApiClient {
  _FakeApiClient({this.response, this.statusCode = 200});

  final Object? response;
  final int statusCode;
  AdminEndpoint? lastEndpoint;
  Map<String, String>? lastQuery;

  @override
  Future<Object?> get(
    AdminEndpoint endpoint, {
    Map<String, Object?> query = const {},
    Map<String, String> headers = const {},
  }) async {
    lastEndpoint = endpoint;
    lastQuery = query.map((k, v) => MapEntry(k, '$v'));
    if (statusCode == 404) {
      throw const ApiException(
        'Strategy Not Found',
        statusCode: 404,
        code: 404,
      );
    }
    return response;
  }
}

class _MockStreamClient extends http.BaseClient {
  _MockStreamClient(this.data);

  final List<int> data;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    return http.StreamedResponse(
      Stream.value(data),
      200,
      contentLength: data.length,
      request: request,
    );
  }
}

void main() {
  group('AppVersionInfo Domain Models', () {
    test('parses full server response correctly', () {
      final json = {
        'platform': 'windows',
        'channel': 'pos',
        'latest': '2.2.0',
        'versionCode': 220,
        'minSupported': '2.0.0',
        'hasUpdate': true,
        'upgradeType': 'OPTIONAL',
        'installMode': 'silent',
        'packageType': 'exe',
        'fileSize': 52428800,
        'sha256': 'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855',
        'releaseNotes': '1. 优化结账速度\n2. 修复对账差异',
        'downloadUrl': 'https://download.example.com/pos/CashierSetup_2.2.0.exe',
      };

      final info = AppVersionInfo.fromJson(json);

      expect(info.platform, 'windows');
      expect(info.channel, 'pos');
      expect(info.latest, '2.2.0');
      expect(info.versionCode, 220);
      expect(info.minSupported, '2.0.0');
      expect(info.hasUpdate, true);
      expect(info.upgradeType, UpgradeType.optional);
      expect(info.installMode, InstallMode.silent);
      expect(info.packageType, 'exe');
      expect(info.fileSize, 52428800);
      expect(info.formattedFileSize, '50.0 MB');
      expect(info.isOptionalUpdate, true);
      expect(info.isForceUpdate, false);
      expect(info.hasValidDownloadUrl, true);
      expect(info.releaseNotes, contains('优化结账速度'));
    });

    test('parses FORCE upgrade and storeRedirect correctly', () {
      final json = {
        'platform': 'ios',
        'channel': 'mobile',
        'latest': '2.2.0',
        'hasUpdate': true,
        'upgradeType': 'FORCE',
        'installMode': 'store_redirect',
        'downloadUrl': 'https://apps.apple.com/app/id123456789',
      };

      final info = AppVersionInfo.fromJson(json);

      expect(info.upgradeType, UpgradeType.force);
      expect(info.isForceUpdate, true);
      expect(info.installMode, InstallMode.storeRedirect);
    });

    test('handles legacy response with missing upgradeType fallback', () {
      final json = {
        'platform': 'android',
        'channel': 'mobile',
        'latest': '2.1.5',
        'hasUpdate': true,
        'forceUpdate': true,
      };

      final info = AppVersionInfo.fromJson(json);

      expect(info.upgradeType, UpgradeType.force);
      expect(info.isForceUpdate, true);
    });
  });

  group('AppVersionService Integration & Verification', () {
    test('checkUpdate passes normalized parameters to GET /admin/app/version', () async {
      final fakeClient = _FakeApiClient(
        response: {
          'platform': 'windows',
          'channel': 'pos',
          'latest': '2.2.0',
          'hasUpdate': false,
          'upgradeType': 'NONE',
          'installMode': 'silent',
        },
      );

      final service = AppVersionService(client: fakeClient);
      final info = await service.checkUpdate(
        platform: 'windows',
        channel: 'pos',
        currentVersion: '2.1.2',
        versionCode: 209,
        shopId: 10,
      );

      expect(fakeClient.lastEndpoint?.path, '/admin/app/version');
      expect(fakeClient.lastQuery?['platform'], 'windows');
      expect(fakeClient.lastQuery?['channel'], 'pos');
      expect(fakeClient.lastQuery?['current_version'], '2.1.2');
      expect(fakeClient.lastQuery?['version_code'], '209');
      expect(fakeClient.lastQuery?['shop_id'], '10');
      expect(info.hasUpdate, false);
      expect(info.upgradeType, UpgradeType.none);
    });

    test('checkUpdate gracefully degrades to hasUpdate:false when server returns 404', () async {
      final fakeClient = _FakeApiClient(statusCode: 404);
      final service = AppVersionService(client: fakeClient);

      final info = await service.checkUpdate(
        platform: 'android',
        channel: 'pos',
      );

      expect(info.hasUpdate, false);
      expect(info.upgradeType, UpgradeType.none);
    });

    test('downloadPackage streams content and writes file with progress callback', () async {
      final testData = utf8.encode('Hello LaoFei Cashier Upgrade Package Data');
      final mockHttp = _MockStreamClient(testData);
      final fakeClient = _FakeApiClient();
      final service = AppVersionService(client: fakeClient, httpClient: mockHttp);

      final tempFile = File('${Directory.systemTemp.path}/test_download_pkg.bin');
      if (tempFile.existsSync()) tempFile.deleteSync();

      var reportedProgress = false;
      final resultFile = await service.downloadPackage(
        downloadUrl: 'https://example.com/test.bin',
        savePath: tempFile.path,
        onProgress: (received, total) {
          reportedProgress = true;
          expect(received, testData.length);
          expect(total, testData.length);
        },
      );

      expect(resultFile.existsSync(), true);
      expect(await resultFile.readAsString(), 'Hello LaoFei Cashier Upgrade Package Data');
      expect(reportedProgress, true);

      tempFile.deleteSync();
    });

    test('verifySha256 validates matching hash and rejects tampered files', () async {
      final fakeClient = _FakeApiClient();
      final service = AppVersionService(client: fakeClient);

      final tempFile = File('${Directory.systemTemp.path}/test_sha256.bin');
      final content = utf8.encode('Secure LaoFei Binary Content 2026');
      await tempFile.writeAsBytes(content);

      final correctSha256 = sha256.convert(content).toString();

      final isMatch = await service.verifySha256(
        filePath: tempFile.path,
        expectedSha256: correctSha256,
      );
      expect(isMatch, true);

      await expectLater(
        service.verifySha256(
          filePath: tempFile.path,
          expectedSha256: 'deadbeef00000000000000000000000000000000000000000000000000000000',
        ),
        throwsA(isA<AppPackageVerificationException>()),
      );

      tempFile.deleteSync();
    });

    test('downloadPackage intercepts text/html response and throws AppPackageVerificationException', () async {
      final fakeClient = _FakeApiClient();
      final htmlContent = utf8.encode('<!DOCTYPE html><html><head><title>运营后台 - 点餐系统</title></head><body>SPA</body></html>');
      final mockHttp = _MockStreamClient(htmlContent);
      final service = AppVersionService(client: fakeClient, httpClient: mockHttp);

      final savePath = '${Directory.systemTemp.path}/test_download_html.exe';
      await expectLater(
        service.downloadPackage(
          downloadUrl: 'https://www.laofei.com.cn/direct/pos.exe',
          savePath: savePath,
        ),
        throwsA(isA<AppPackageVerificationException>()),
      );
    });

    test('executeInstall branches accurately by installMode', () async {
      final fakeClient = _FakeApiClient();
      var urlLaunched = false;
      var fileOpened = false;
      var processStarted = false;

      final service = AppVersionService(
        client: fakeClient,
        urlLauncher: (uri, {LaunchMode mode = LaunchMode.platformDefault}) async {
          urlLaunched = true;
          return true;
        },
        fileOpener: (path, {String? type}) async {
          fileOpened = true;
          return OpenResult(type: ResultType.done);
        },
        processLauncher: (exe, args, {ProcessStartMode mode = ProcessStartMode.normal}) async {
          processStarted = true;
          return Process.start('cmd', ['/c', 'exit', '0']);
        },
      );

      // 1. storeRedirect (iOS)
      const iosInfo = AppVersionInfo(
        platform: 'ios',
        channel: 'mobile',
        latest: '2.2.0',
        hasUpdate: true,
        upgradeType: UpgradeType.optional,
        installMode: InstallMode.storeRedirect,
        downloadUrl: 'https://apps.apple.com/app/laofei',
      );
      await service.executeInstall(info: iosInfo);
      expect(urlLaunched, true);

      // 2. interactive (Android)
      const androidInfo = AppVersionInfo(
        platform: 'android',
        channel: 'mobile',
        latest: '2.2.0',
        hasUpdate: true,
        upgradeType: UpgradeType.optional,
        installMode: InstallMode.interactive,
        downloadUrl: 'https://example.com/app.apk',
      );
      await service.executeInstall(info: androidInfo, localFilePath: '/sdcard/app.apk');
      expect(fileOpened, true);

      // 3. silent (Windows .exe)
      const winInfo = AppVersionInfo(
        platform: 'windows',
        channel: 'pos',
        latest: '2.2.0',
        hasUpdate: true,
        upgradeType: UpgradeType.optional,
        installMode: InstallMode.silent,
        downloadUrl: 'https://example.com/setup.exe',
      );
      await service.executeInstall(info: winInfo, localFilePath: r'C:\temp\setup.exe');
      expect(processStarted, true);

      // 4. silent (Windows .zip fallback)
      var zipProcessStarted = false;
      String? launchedExe;
      List<String>? launchedArgs;
      final zipService = AppVersionService(
        client: fakeClient,
        processLauncher: (exe, args, {ProcessStartMode mode = ProcessStartMode.normal}) async {
          zipProcessStarted = true;
          launchedExe = exe;
          launchedArgs = args;
          return Process.start('cmd', ['/c', 'exit', '0']);
        },
      );
      const winZipInfo = AppVersionInfo(
        platform: 'windows',
        channel: 'pos',
        latest: '2.2.0',
        hasUpdate: true,
        upgradeType: UpgradeType.optional,
        installMode: InstallMode.silent,
        downloadUrl: 'https://example.com/package.zip',
      );
      await zipService.executeInstall(info: winZipInfo, localFilePath: r'C:\temp\package.zip');
      expect(zipProcessStarted, true);
      expect(launchedExe, 'powershell.exe');
      expect(launchedArgs, contains('-ExecutionPolicy'));
    });
  });

  group('VersionUpgradeDialog Widget Tests', () {
    testWidgets('renders OPTIONAL upgrade dialog with postpone and confirm buttons', (tester) async {
      final fakeClient = _FakeApiClient();
      final service = AppVersionService(client: fakeClient);

      const info = AppVersionInfo(
        platform: 'windows',
        channel: 'pos',
        latest: '2.2.0',
        hasUpdate: true,
        upgradeType: UpgradeType.optional,
        installMode: InstallMode.silent,
        fileSize: 52428800,
        releaseNotes: '1. 优化结账响应\n2. 修复钱箱交班',
        downloadUrl: 'https://example.com/setup.exe',
      );

      var postponed = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () => showVersionUpgradeDialog(
                context,
                info: info,
                service: service,
                onPostpone: () => postponed = true,
              ),
              child: const Text('Open Dialog'),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open Dialog'));
      await tester.pumpAndSettle();

      expect(find.text('发现新版本'), findsOneWidget);
      expect(find.text('最新版 V2.2.0'), findsOneWidget);
      expect(find.text('大小: 50.0 MB'), findsOneWidget);
      expect(find.text('1. 优化结账响应\n2. 修复钱箱交班'), findsOneWidget);
      expect(find.byKey(const Key('version-upgrade-postpone-button')), findsOneWidget);
      expect(find.byKey(const Key('version-upgrade-confirm-button')), findsOneWidget);

      await tester.tap(find.byKey(const Key('version-upgrade-postpone-button')));
      await tester.pumpAndSettle();

      expect(postponed, true);
      expect(find.text('发现新版本'), findsNothing);
    });

    testWidgets('renders FORCE upgrade dialog without postpone button', (tester) async {
      final fakeClient = _FakeApiClient();
      final service = AppVersionService(client: fakeClient);

      const info = AppVersionInfo(
        platform: 'windows',
        channel: 'pos',
        latest: '2.2.0',
        hasUpdate: true,
        upgradeType: UpgradeType.force,
        installMode: InstallMode.silent,
        releaseNotes: '安全紧急升级',
        downloadUrl: 'https://example.com/setup.exe',
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () => showVersionUpgradeDialog(
                context,
                info: info,
                service: service,
              ),
              child: const Text('Open Force Dialog'),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open Force Dialog'));
      await tester.pumpAndSettle();

      expect(find.text('重要版本强制升级'), findsOneWidget);
      expect(find.text('必须更新'), findsOneWidget);
      expect(find.byKey(const Key('version-upgrade-postpone-button')), findsNothing);
      expect(find.byKey(const Key('version-upgrade-confirm-button')), findsOneWidget);
      expect(find.text('立即升级并重启'), findsOneWidget);
    });
  });
}
