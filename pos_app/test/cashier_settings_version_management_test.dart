import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:admin_panel_flutter/src/features/cashier_settings/data/cashier_settings_repository.dart';
import 'package:admin_panel_flutter/src/features/cashier_settings/domain/cashier_settings.dart';
import 'package:admin_panel_flutter/src/features/cashier_settings/presentation/cashier_settings_page.dart';
import 'package:admin_panel_flutter/src/features/cashier_settings/presentation/cashier_settings_version_page.dart';
import 'package:admin_panel_flutter/src/features/cashier_payment/data/cashier_payment_repository.dart';
import 'package:admin_panel_flutter/src/features/version_upgrade/data/app_version_management_repository.dart';
import 'package:admin_panel_flutter/src/features/version_upgrade/domain/app_version_info.dart';
import 'package:admin_panel_flutter/src/features/version_upgrade/domain/app_version_management_model.dart';
import 'package:admin_panel_flutter/src/core/admin_api_client.dart';
import 'package:admin_panel_flutter/src/core/api_contract.dart';
import 'package:admin_panel_flutter/src/features/cashier_shell/presentation/cashier_tokens.dart';

class MockCashierSettingsRepository implements CashierSettingsRepository {
  @override
  Future<CashierSettingsOverview> loadSettingsOverview() async {
    return const CashierSettingsOverview(
      shopId: 1,
      modules: [
        CashierSettingsModule(
          module: 'store',
          permission: 'settings:view',
          permitted: true,
          source: 'SHOP',
          summary: '测试店铺',
          alerts: 0,
        ),
      ],
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class MockCashierPaymentRepository implements CashierPaymentRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeAppVersionManagementRepository
    implements AppVersionManagementRepository {
  FakeAppVersionManagementRepository({List<AppVersionPolicyItem>? items})
      : items = items ??
            [
              const AppVersionPolicyItem(
                id: 1,
                platform: 'windows',
                channel: 'pos',
                latest: '2.1.0',
                versionCode: 20100,
                minSupported: '2.0.0',
                forceUpdate: false,
                packageType: 'full',
                installMode: 'silent',
                fileSize: 45200000,
                sha256: '7d8f9a2e4b1c8f3a5e7d9b2c4a6e8f0a',
                releaseNotes: 'Windows 发版说明',
                enabled: true,
              ),
              const AppVersionPolicyItem(
                id: 2,
                platform: 'android',
                channel: 'mobile',
                latest: '2.1.0',
                versionCode: 20100,
                minSupported: '2.1.0',
                forceUpdate: true,
                packageType: 'full',
                installMode: 'interactive',
                grayShopIds: '1,2',
                releaseNotes: 'Android 强更说明',
                enabled: true,
              ),
            ];

  List<AppVersionPolicyItem> items;
  bool toggleCalled = false;
  bool deleteCalled = false;
  bool saveCalled = false;
  bool uploadCalled = false;

  @override
  Future<AppVersionUploadResult> uploadPackage({
    String? filePath,
    List<int>? fileBytes,
    required String fileName,
    String? platform,
    String? channel,
    void Function(int bytesSent, int totalBytes)? onProgress,
  }) async {
    uploadCalled = true;
    return const AppVersionUploadResult(
      fileName: 'pos-setup-2.1.3+210.exe',
      storedFileName: 'pkg-uuid-2.1.3.exe',
      downloadUrl: 'http://cdn.example.com/packages/pos-setup-2.1.3.exe',
      sha256: 'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855',
      fileSize: 52428800,
      packageType: 'full',
    );
  }

  @override
  Future<List<AppVersionPolicyItem>> fetchVersionList() async => items;

  @override
  Future<void> saveVersionPolicy(SaveVersionPolicyRequest req) async {
    saveCalled = true;
  }

  @override
  Future<void> toggleVersionEnabled({
    required int id,
    required bool enabled,
  }) async {
    toggleCalled = true;
  }

  @override
  Future<void> deleteVersion(int id) async {
    deleteCalled = true;
  }

  @override
  Future<AppVersionInfo> simulateUpgradeVerdict({
    required String platform,
    required String channel,
    required String currentVersion,
    int? currentVersionCode,
    int? shopId,
  }) async {
    return AppVersionInfo(
      platform: platform,
      channel: channel,
      latest: '2.1.0',
      versionCode: 20100,
      hasUpdate: true,
      upgradeType: platform == 'android' ? UpgradeType.force : UpgradeType.optional,
      installMode: platform == 'ios' ? InstallMode.storeRedirect : InstallMode.silent,
    );
  }

  @override
  Future<Map<String, dynamic>> verifyDownloadUrl({
    required String downloadUrl,
    String? expectedSha256,
  }) async {
    return {
      'statusCode': 200,
      'contentType': 'application/octet-stream',
      'fileSize': 52428800,
      'isHtmlFallback': false,
      'actualSha256': expectedSha256 ?? 'mock-sha',
      'hashMatched': true,
    };
  }
}

Widget _wrapWithTokens(Widget child) {
  return MaterialApp(
    theme: ThemeData(
      extensions: const [
        CashierTokens.light]),
    home: child,
  );
}

void main() {
  testWidgets(
    'version page without a backend cannot fabricate policies or successful uploads',
    (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: CashierSettingsVersionPage(permissions: {'admin:super'}),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('版本服务未连接'), findsOneWidget);
      expect(find.text('2.1.0'), findsNothing);
      expect(find.byType(FilledButton), findsNothing);
    },
  );
  group('Cashier Settings Version Management Access Control & UI Tests', () {
    testWidgets(
        'S01: Ordinary cashier WITHOUT admin:super does NOT see Version Management in Settings',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(1280, 800));

      await tester.pumpWidget(
        _wrapWithTokens(
          CashierSettingsPage(
            repository: MockCashierSettingsRepository(),
            paymentRepository: MockCashierPaymentRepository(),
            storeName: '测试总店',
            kdsAvailable: true,
            permissions: const {'cashier:operate'},
          ),
        ),
      );

      await tester.pumpAndSettle();

      // 应显示系统设置标题
      expect(find.text('系统设置'), findsOneWidget);
      // 应显示店铺信息等常规设置
      expect(find.text('店铺信息'), findsOneWidget);
      // 必须绝对不展示「版本管理」磁贴
      expect(find.text('版本管理'), findsNothing);
    },
    );

    testWidgets(
        'S02: Super admin WITH admin:super SEES Version Management in Settings',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(1280, 800));

      await tester.pumpWidget(
        _wrapWithTokens(
          CashierSettingsPage(
            repository: MockCashierSettingsRepository(),
            paymentRepository: MockCashierPaymentRepository(),
            storeName: '测试总店',
            kdsAvailable: true,
            permissions: const {'cashier:operate', 'admin:super'},
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('系统设置'), findsOneWidget);
      // 必须展示「版本管理」磁贴
      expect(find.text('版本管理'), findsOneWidget);
      expect(find.text('平台策略·灰度发布·升级控制'), findsOneWidget);
    },
    );

    testWidgets(
        'S03: Direct access to CashierSettingsVersionPage without admin:super renders 403 Barrier',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(1280, 800));

      await tester.pumpWidget(
        _wrapWithTokens(
          const CashierSettingsVersionPage(
            permissions: {'cashier:operate'}),
        ),
      );

      await tester.pumpAndSettle();

      // 403 屏障应当被呈现
      expect(find.byKey(const Key('version-management-forbidden-barrier')),
          findsOneWidget,
        );
      expect(find.text('访问受限：无权限访问此模块'), findsOneWidget);
      expect(find.textContaining('仅限超级管理员 (admin:super)'), findsOneWidget);
    },
    );

    testWidgets(
        'S04: Direct access to CashierSettingsVersionPage with admin:super renders management suite',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(1280, 800));

      final fakeRepo = FakeAppVersionManagementRepository();

      await tester.pumpWidget(
        _wrapWithTokens(
          CashierSettingsVersionPage(
            repository: fakeRepo,
            permissions: const {'admin:super'},
          ),
        ),
      );

      await tester.pumpAndSettle();

      // 403 屏障绝对不能出现
      expect(find.byKey(const Key('version-management-forbidden-barrier')),
          findsNothing,
        );

      // 超管专属徽标
      expect(find.text('超级管理员 (admin:super) 专属'), findsOneWidget);
      expect(find.text('发布新版策略'), findsOneWidget);

      // 指标卡片
      expect(find.text('覆盖平台'), findsOneWidget);
      expect(find.text('生效策略'), findsOneWidget);
      expect(find.text('强更拦截中'), findsOneWidget);

      // 策略卡片
      expect(find.text('v2.1.0'), findsNWidgets(2));
      expect(find.text('WINDOWS · pos'), findsOneWidget);
      expect(find.text('ANDROID · mobile'), findsOneWidget);
      expect(find.text('强制升级'), findsOneWidget);
      expect(find.text('建议升级'), findsOneWidget);
    },
    );

    testWidgets('S05: Sandbox simulator runs verdict and renders output',
        (tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(1280, 900));

      final fakeRepo = FakeAppVersionManagementRepository();

      await tester.pumpWidget(
        _wrapWithTokens(
          CashierSettingsVersionPage(
            repository: fakeRepo,
            permissions: const {'admin:super'},
          ),
        ),
      );

      await tester.pumpAndSettle();

      // 点击沙箱运行决断
      final runBtn = find.byKey(const Key('sandbox-run-button'));
      expect(runBtn, findsOneWidget);
      await tester.tap(runBtn);
      await tester.pumpAndSettle();

      // 检查结果渲染
      expect(find.byKey(const Key('sandbox-result-box')), findsOneWidget);
      expect(find.textContaining('hasUpdate=true'), findsOneWidget);
      expect(find.textContaining('目标最新版本: v2.1.0'), findsOneWidget);
    });

    test('S06: RealAppVersionManagementRepository contract methods', () async {
      final fakeClient = _MockApiClient(
        mockVersions: [
          {
            'id': 1,
            'platform': 'windows',
            'channel': 'pos',
            'latest': '2.1.0',
            'version_code': 20100,
            'min_supported': '2.0.0',
            'force_update': 0,
            'package_type': 'full',
            'install_mode': 'silent',
            'enabled': 1,
          },
        ],
      );
      final repo = RealAppVersionManagementRepository(client: fakeClient);

      final list = await repo.fetchVersionList();
      expect(list.length, 1);
      expect(list.first.platform, 'windows');
      expect(list.first.latest, '2.1.0');
      expect(list.first.versionCode, 20100);

      await repo.saveVersionPolicy(const SaveVersionPolicyRequest(
        platform: 'windows',
        channel: 'pos',
        latest: '2.2.0',
        versionCode: 20200,
        forceUpdate: true,
        packageType: 'full',
        installMode: 'silent',
        enabled: true,
      ),
      );
      expect(fakeClient.lastPostEndpoint?.path, '/admin/app/version/save');

      await repo.toggleVersionEnabled(id: 1, enabled: false);
      expect(fakeClient.lastPostEndpoint?.path,
          '/admin/app/version/toggle-enabled',
      );
      expect(fakeClient.lastQuery?['enabled'], 0);

      await repo.deleteVersion(1);
      expect(fakeClient.lastDeleteEndpoint?.path, '/admin/app/version/1');
    });

    testWidgets('S07: open edit dialog and verify package uploader widget is rendered',
        (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final fakeRepo = FakeAppVersionManagementRepository();

      await tester.pumpWidget(
        _wrapWithTokens(
          CashierSettingsVersionPage(
            repository: fakeRepo,
            permissions: const {'admin:super'},
          ),
        ),
      );

      await tester.pumpAndSettle();

      final addBtn = find.byKey(const Key('btn-add-version-policy'));
      expect(addBtn, findsOneWidget);
      await tester.tap(addBtn);
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('box-package-uploader')), findsOneWidget);
      expect(find.byKey(const Key('btn-pick-and-upload-package')), findsOneWidget,
        );
      expect(find.textContaining('上传安装/更新包文件'), findsOneWidget);
    },
    );

    test('S08: AppVersionUploadResult JSON serialization and domain model', () {
      final json = {
        'download_url': 'http://oss.example.com/pos-2.1.3.exe',
        'file_name': 'pos-2.1.3.exe',
        'stored_file_name': 'uuid-pos.exe',
        'file_size': 104857600,
        'sha256': 'abc123def456',
        'package_type': 'full',
      };
      final model = AppVersionUploadResult.fromJson(json);
      expect(model.downloadUrl, 'http://oss.example.com/pos-2.1.3.exe');
      expect(model.fileName, 'pos-2.1.3.exe');
      expect(model.storedFileName, 'uuid-pos.exe');
      expect(model.fileSize, 104857600);
      expect(model.sha256, 'abc123def456');
      expect(model.packageType, 'full');

      final back = model.toJson();
      expect(back['downloadUrl'], 'http://oss.example.com/pos-2.1.3.exe');
      expect(back['storedFileName'], 'uuid-pos.exe');
      expect(back['fileSize'], 104857600);
    });
  });
}

class _MockApiClient extends Fake implements AdminApiClient {
  _MockApiClient({this.mockVersions = const []});

  final List<Map<String, dynamic>> mockVersions;
  AdminEndpoint? lastGetEndpoint;
  AdminEndpoint? lastPostEndpoint;
  AdminEndpoint? lastDeleteEndpoint;
  Map<String, Object?>? lastQuery;
  Object? lastBody;

  @override
  Future<Object?> get(
    AdminEndpoint endpoint, {
    Map<String, Object?> query = const {},
    Map<String, String> headers = const {},
  }) async {
    lastGetEndpoint = endpoint;
    lastQuery = query;
    return mockVersions;
  }

  @override
  Future<Object?> post(
    AdminEndpoint endpoint, {
    Object? body,
    Map<String, Object?> query = const {},
    Map<String, String> headers = const {},
  }) async {
    lastPostEndpoint = endpoint;
    lastBody = body;
    lastQuery = query;
    return {'code': 0, 'msg': 'success'};
  }

  @override
  Future<Object?> delete(
    AdminEndpoint endpoint, {
    Object? body,
    Map<String, Object?> query = const {},
    Map<String, String> headers = const {},
  }) async {
    lastDeleteEndpoint = endpoint;
    return {'code': 0, 'msg': 'success'};
  }
}
