import 'dart:convert';

import 'package:admin_panel_flutter/src/core/admin_api_client.dart';
import 'package:admin_panel_flutter/src/core/api_contract.dart';
import 'package:admin_panel_flutter/src/core/http_transport.dart';
import 'package:admin_panel_flutter/src/features/auth/data/access_approval_repository.dart';
import 'package:admin_panel_flutter/src/features/auth/domain/access_approval_models.dart';
import 'package:admin_panel_flutter/src/features/cashier_settings/domain/cashier_settings.dart';
import 'package:admin_panel_flutter/src/features/cashier_shell/presentation/cashier_approval_dialog.dart';
import 'package:admin_panel_flutter/src/core/terminal_device_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_http_transport.dart';

void main() {
  group('方案A·API 契约', () {
    test('cashierAccessQrCreateEndpoint', () {
      expect(cashierAccessQrCreateEndpoint.method, 'POST');
      expect(cashierAccessQrCreateEndpoint.path, '/cashier/access/qr/create');
      expect(cashierAccessQrCreateEndpoint.permissionCode, 'cashier:operate');
      expect(cashierAccessQrCreateEndpoint.attachShopHeader, isTrue);
    });

    test('cashierAccessQrStatusEndpoint', () {
      expect(cashierAccessQrStatusEndpoint.method, 'GET');
      expect(cashierAccessQrStatusEndpoint.path, '/cashier/access/qr/status');
      expect(cashierAccessQrStatusEndpoint.permissionCode, 'cashier:operate');
      expect(cashierAccessQrStatusEndpoint.attachShopHeader, isTrue);
    });

    test('adminAccessQrDetailsEndpoint 不带门店头', () {
      expect(adminAccessQrDetailsEndpoint.method, 'GET');
      expect(adminAccessQrDetailsEndpoint.path, '/admin/access/qr/details');
      expect(adminAccessQrDetailsEndpoint.permissionCode, 'access:view');
      expect(adminAccessQrDetailsEndpoint.attachShopHeader, isFalse);
    });

    test('adminAccessQrConfirmEndpoint 不带门店头', () {
      expect(adminAccessQrConfirmEndpoint.method, 'POST');
      expect(adminAccessQrConfirmEndpoint.path, '/admin/access/qr/confirm');
      expect(adminAccessQrConfirmEndpoint.permissionCode, 'access:view');
      expect(adminAccessQrConfirmEndpoint.attachShopHeader, isFalse);
    });

    test('cashierAccessRecentAuthorsEndpoint', () {
      expect(cashierAccessRecentAuthorsEndpoint.method, 'GET');
      expect(cashierAccessRecentAuthorsEndpoint.path,
          '/cashier/access/recent-authors');
      expect(cashierAccessRecentAuthorsEndpoint.permissionCode,
          'cashier:operate');
      expect(cashierAccessRecentAuthorsEndpoint.attachShopHeader, isTrue);
    });
  });

  group('方案A·模型解析', () {
    test('CashierQrApprovalRequest 解析 camel/snake', () {
      final camel = CashierQrApprovalRequest.fromJson(const {
        'approvalCode': 'QAP_1_1_1234',
        'qrPayload': 'bbq://approval?code=QAP_1_1_1234',
        'status': 'PENDING',
        'expireSeconds': 120,
      });
      expect(camel.approvalCode, 'QAP_1_1_1234');
      expect(camel.qrPayload, 'bbq://approval?code=QAP_1_1_1234');
      expect(camel.expireSeconds, 120);
      expect(camel.isExpired, isFalse);

      final snake = CashierQrApprovalRequest.fromJson({
        'approval_code': 'QAP_2_2_5678',
        'qr_payload': 'bbq://approval?code=QAP_2_2_5678',
        'expires_at': DateTime.now().add(const Duration(seconds: 30)).toIso8601String(),
      });
      expect(snake.approvalCode, 'QAP_2_2_5678');
      expect(snake.qrPayload, 'bbq://approval?code=QAP_2_2_5678');
      expect(snake.isExpired, isFalse);
    });

    test('CashierQrApprovalStatus 解析 APPROVED 与 REJECTED', () {
      final approved = CashierQrApprovalStatus.fromJson(const {
        'approvalCode': 'QAP_1_1_1234',
        'status': 'APPROVED',
        'approvalToken': 'token-abc',
        'authorizerId': 9,
        'authorizerName': '店长甲',
      });
      expect(approved.isApproved, isTrue);
      expect(approved.approvalToken, 'token-abc');
      expect(approved.authorizerId, 9);
      expect(approved.authorizerName, '店长甲');

      final rejected = CashierQrApprovalStatus.fromJson(const {
        'approval_code': 'QAP_1_1_1234',
        'status': 'REJECTED',
        'reason': '金额有误',
      });
      expect(rejected.isRejected, isTrue);
      expect(rejected.reason, '金额有误');
    });

    test('CashierQrApprovalDetails 与 ConfirmResult 解析', () {
      final details = CashierQrApprovalDetails.fromJson({
        'approvalCode': 'QAP_1_1_1234',
        'shopId': 3,
        'permission': 'order:operate:refund',
        'bizType': 'ORDER_REFUND',
        'bizId': 'A00012122',
        'amount': 88.5,
        'operatorName': '小林',
        'operatorWorkNo': 'W001',
        'expiresAt': DateTime.now().add(const Duration(seconds: 60)).toIso8601String(),
      });
      expect(details.approvalCode, 'QAP_1_1_1234');
      expect(details.shopId, 3);
      expect(details.permission, 'order:operate:refund');
      expect(details.amount, 88.5);
      expect(details.isExpired, isFalse);

      final confirmed = CashierQrApprovalConfirmResult.fromJson({
        'approval_code': 'QAP_1_1_1234',
        'status': 'APPROVED',
        'authorizer_id': 9,
        'authorizer_name': '店长甲',
      });
      expect(confirmed.status, 'APPROVED');
      expect(confirmed.authorizerId, 9);
      expect(confirmed.authorizerName, '店长甲');
    });

    test('AccessApprovalRecord 解析操作人/授权人名称与工号', () {
      final camel = AccessApprovalRecord.fromJson(const {
        'id': 1,
        'approvalNo': 'AP2026100800012',
        'permissionCode': 'order:refund',
        'operatorId': 2003,
        'authorizerId': 1001,
        'operatorName': '陈收银',
        'operatorWorkNo': '2003',
        'authorizerName': '王店长',
        'authorizerWorkNo': '1001',
      });
      expect(camel.operatorName, '陈收银');
      expect(camel.operatorWorkNo, '2003');
      expect(camel.authorizerName, '王店长');
      expect(camel.authorizerWorkNo, '1001');

      final snake = AccessApprovalRecord.fromJson(const {
        'id': 2,
        'approval_no': 'AP2026100800011',
        'permission_code': 'order:discount',
        'operator_id': 2005,
        'authorizer_id': 1002,
        'operator_name': '周收银',
        'operator_work_no': '2005',
        'authorizer_name': '李经理',
        'authorizer_work_no': '1002',
      });
      expect(snake.operatorName, '周收银');
      expect(snake.operatorWorkNo, '2005');
      expect(snake.authorizerName, '李经理');
      expect(snake.authorizerWorkNo, '1002');

      // 旧版响应（无名称/工号）不报错，字段为 null。
      final legacy = AccessApprovalRecord.fromJson(const {
        'id': 3,
        'approvalNo': 'AP2026100800008',
        'permissionCode': 'cashbox:open',
        'operatorId': 7,
        'authorizerId': 9,
      });
      expect(legacy.operatorName, isNull);
      expect(legacy.authorizerWorkNo, isNull);
    });

    test('RecentAuthor 解析并生成快捷选择文案', () {
      final author = RecentAuthor.fromJson({
        'authorizerId': 1001,
        'authorizerName': '王店长',
        'authorizerWorkNo': '1001',
        'lastApprovalAt':
            DateTime.now().subtract(const Duration(minutes: 5)).toIso8601String(),
      });
      expect(author.authorizerId, 1001);
      expect(author.authorizerName, '王店长');
      expect(author.authorizerWorkNo, '1001');
      expect(author.lastApprovalAt, isNotNull);
      expect(author.displayLabel, '王店长 · 1001');

      final noName = RecentAuthor.fromJson({
        'authorizer_id': 1002,
        'authorizer_work_no': '1002',
      });
      expect(noName.displayLabel, '店长 · 1002');
    });
  });

  group('方案A·仓库', () {
    late FakeHttpTransport transport;
    late AdminApiClient client;
    late AccessApprovalRepository repository;

    setUp(() {
      transport = FakeHttpTransport({});
      client = AdminApiClient(
        baseUrl: 'http://fake',
        transport: transport,
        token: 'fake-token',
        shopId: 3,
      );
      repository = AccessApprovalRepository(client);
    });

    test('createQrApproval 请求正确并解析响应', () async {
      transport.routes['POST /cashier/access/qr/create'] = jsonEncode({
        'code': 0,
        'data': {
          'approvalCode': 'QAP_3_1_4321',
          'qrPayload': 'bbq://approval?code=QAP_3_1_4321',
          'status': 'PENDING',
          'expiresAt':
              DateTime.now().add(const Duration(seconds: 120)).toIso8601String(),
          'expireSeconds': 120,
        },
      });
      final request = await repository.createQrApproval(
        permission: 'order:operate:refund',
        bizType: 'ORDER_REFUND',
        bizId: 'A00012122',
        amount: 88.5,
        reason: '顾客要求退款',
        terminalId: 'MAIN-POS',
      );
      expect(request.approvalCode, 'QAP_3_1_4321');
      expect(request.qrPayload, 'bbq://approval?code=QAP_3_1_4321');
      expect(request.expireSeconds, 120);

      final recorded = transport.requests.single;
      expect(recorded.method, 'POST');
      expect(recorded.uri.path, '/cashier/access/qr/create');
      expect(recorded.headers['X-Shop-Id'], '3');
      final body = jsonDecode(recorded.body!) as Map<String, Object?>;
      expect(body['permission'], 'order:operate:refund');
      expect(body['bizType'], 'ORDER_REFUND');
      expect(body['bizId'], 'A00012122');
      expect(body['amount'], 88.5);
      expect(body['terminalId'], 'MAIN-POS');
    });

    test('pollQrApprovalStatus 轮询并取回令牌', () async {
      transport.routes['GET /cashier/access/qr/status'] = jsonEncode({
        'code': 0,
        'data': {
          'approvalCode': 'QAP_3_1_4321',
          'status': 'APPROVED',
          'approvalToken': 'single-use-token',
          'authorizerId': 9,
          'authorizerName': '店长甲',
        },
      });
      final status = await repository.pollQrApprovalStatus('QAP_3_1_4321');
      expect(status.isApproved, isTrue);
      expect(status.approvalToken, 'single-use-token');

      final recorded = transport.requests.single;
      expect(recorded.method, 'GET');
      expect(recorded.uri.path, '/cashier/access/qr/status');
      expect(recorded.uri.queryParameters['approvalCode'], 'QAP_3_1_4321');
      expect(recorded.headers['X-Shop-Id'], '3');
    });

    test('confirmQrApproval 校验动作并提交 body', () async {
      transport.routes['POST /admin/access/qr/confirm'] = jsonEncode({
        'code': 0,
        'data': {
          'approvalCode': 'QAP_3_1_4321',
          'status': 'REJECTED',
          'authorizerId': 9,
          'authorizerName': '店长甲',
        },
      });
      final result = await repository.confirmQrApproval(
        approvalCode: 'QAP_3_1_4321',
        action: 'REJECT',
        rejectReason: '金额有误',
      );
      expect(result.status, 'REJECTED');

      final recorded = transport.requests.single;
      expect(recorded.uri.path, '/admin/access/qr/confirm');
      expect(recorded.headers.containsKey('X-Shop-Id'), isFalse,
          reason: '店长端确认接口不依赖收银端门店上下文');
      final body = jsonDecode(recorded.body!) as Map<String, Object?>;
      expect(body['approvalCode'], 'QAP_3_1_4321');
      expect(body['action'], 'REJECT');
      expect(body['rejectReason'], '金额有误');

      await expectLater(
        repository.confirmQrApproval(
          approvalCode: 'QAP_3_1_4321',
          action: 'UNKNOWN',
        ),
        throwsArgumentError,
      );
    });

    test('loadQrApprovalDetails 请求并解析详情', () async {
      transport.routes['GET /admin/access/qr/details'] = jsonEncode({
        'code': 0,
        'data': {
          'approvalCode': 'QAP_3_1_4321',
          'shopId': 3,
          'permission': 'order:operate:refund',
          'bizType': 'ORDER_REFUND',
          'bizId': 'A00012122',
          'amount': 88.5,
          'operatorName': '小林',
        },
      });
      final details = await repository.loadQrApprovalDetails('QAP_3_1_4321');
      expect(details.approvalCode, 'QAP_3_1_4321');
      expect(details.shopId, 3);
      expect(details.amount, 88.5);

      final recorded = transport.requests.single;
      expect(recorded.method, 'GET');
      expect(recorded.uri.path, '/admin/access/qr/details');
      expect(recorded.uri.queryParameters['approvalCode'], 'QAP_3_1_4321');
      expect(recorded.headers.containsKey('X-Shop-Id'), isFalse);
    });

    test('loadRecentAuthors 请求并解析本门店最近授权人', () async {
      transport.routes['GET /cashier/access/recent-authors'] = jsonEncode({
        'code': 0,
        'data': [
          {
            'authorizerId': 1001,
            'authorizerName': '王店长',
            'authorizerWorkNo': '1001',
            'lastApprovalAt':
                DateTime.now().subtract(const Duration(minutes: 3)).toIso8601String(),
          },
          {
            'authorizer_id': 1002,
            'authorizer_name': '李经理',
            'authorizer_work_no': '1002',
          },
        ],
      });
      final authors = await repository.loadRecentAuthors(limit: 10);
      expect(authors, hasLength(2));
      expect(authors.first.authorizerName, '王店长');
      expect(authors.first.authorizerWorkNo, '1001');
      expect(authors.first.displayLabel, '王店长 · 1001');
      expect(authors.last.authorizerId, 1002);
      expect(authors.last.authorizerWorkNo, '1002');

      final recorded = transport.requests.single;
      expect(recorded.method, 'GET');
      expect(recorded.uri.path, '/cashier/access/recent-authors');
      expect(recorded.uri.queryParameters['limit'], '10');
      expect(recorded.headers['X-Shop-Id'], '3');
    });

    test('loadRecentAuthors 接口异常时抛 ApiException（弹窗层负责静默降级）',
        () async {
      // 未配置路由 → 404 → AdminApiClient 抛 ApiException。
      await expectLater(
        repository.loadRecentAuthors(),
        throwsA(isA<ApiException>()),
      );
    });
  });

  group('方案A·审批弹窗扫码模式', () {
    testWidgets('切换扫码审批并生成二维码等待店长审批', (tester) async {
      final transport = FakeHttpTransport({
        'POST /cashier/access/qr/create': jsonEncode({
          'code': 0,
          'data': {
            'approvalCode': 'QAP_1_1_1234',
            'qrPayload': 'bbq://approval?code=QAP_1_1_1234',
            'status': 'PENDING',
            'expireSeconds': 120,
          },
        }),
        'GET /cashier/access/qr/status': jsonEncode({
          'code': 0,
          'data': {'approvalCode': 'QAP_1_1_1234', 'status': 'PENDING'},
        }),
      });
      final client = AdminApiClient(
        baseUrl: 'http://fake',
        transport: transport,
        token: 'fake-token',
        shopId: 1,
        terminalId: 'POS-01',
      );
      final repository = AccessApprovalRepository(client);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => Center(
                child: ElevatedButton(
                  onPressed: () {
                    showCashierApprovalDialog(
                      context,
                      request: const CashierApprovalRequest(
                        title: '退菜审批',
                        permission: 'order:operate:refund',
                        permissionLabel: '退菜 / 人工退款',
                        bizType: 'DISH_REFUND',
                        bizId: 'A00012122',
                        amount: 88.5,
                      ),
                      repository: repository,
                    );
                  },
                  child: const Text('打开审批'),
                ),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('打开审批'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('cashier-approval-dialog')), findsOneWidget);

      // 切换到扫码审批模式。
      await tester.tap(find.text('扫码审批'));
      await tester.pumpAndSettle();
      expect(find.text('生成审批二维码'), findsOneWidget);
      expect(find.textContaining('扫码无密审批'), findsOneWidget);

      // 生成二维码：出码接口 + 渲染 QrImageView + 轮询等待。
      await tester.tap(find.byKey(const Key('approval-qr-create')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.byKey(const Key('approval-qr-image')), findsOneWidget);
      expect(find.textContaining('等待店长手机扫码审批'), findsOneWidget);
      expect(find.textContaining('二维码'), findsWidgets);
      final createReq = transport.requests.firstWhere((r) => r.uri.path == '/cashier/access/qr/create');
      expect(createReq.headers['X-Terminal-Id'], 'POS-01');
      final reqBody = jsonDecode(createReq.body!) as Map<String, Object?>;
      expect(reqBody['bindingVersion'], 2);
      expect(reqBody['terminalId'], 'POS-01');

      // 取消关闭弹窗（停止倒计时与轮询计时器）。
      await tester.tap(find.byKey(const Key('approval-cancel')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('cashier-approval-dialog')), findsNothing);
    });

    testWidgets('账号密码模式显示最近授权账号并快捷填入', (tester) async {
      final transport = FakeHttpTransport({
        'GET /cashier/access/recent-authors': jsonEncode({
          'code': 0,
          'data': [
            {
              'authorizerId': 1001,
              'authorizerName': '王店长',
              'authorizerWorkNo': '1001',
            },
            {
              'authorizerId': 1002,
              'authorizerName': '李经理',
              'authorizerWorkNo': '1002',
            },
          ],
        }),
      });
      final client = AdminApiClient(
        baseUrl: 'http://fake',
        transport: transport,
        token: 'fake-token',
        shopId: 1,
      );
      final repository = AccessApprovalRepository(client);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => Center(
                child: ElevatedButton(
                  onPressed: () {
                    showCashierApprovalDialog(
                      context,
                      request: const CashierApprovalRequest(
                        title: '退菜审批',
                        permission: 'order:operate:refund',
                        permissionLabel: '退菜 / 人工退款',
                      ),
                      repository: repository,
                    );
                  },
                  child: const Text('打开审批'),
                ),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('打开审批'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('cashier-approval-dialog')), findsOneWidget);

      // 最近授权账号区与 chips 已渲染。
      expect(find.text('最近授权账号'), findsOneWidget);
      expect(find.text('王店长'), findsOneWidget);
      expect(find.text('李经理'), findsOneWidget);
      expect(find.textContaining('点击快捷填入账号'), findsOneWidget);

      // 点击 chip 将工号填入账号输入框。
      await tester.tap(find.text('李经理'));
      await tester.pumpAndSettle();
      final accountField = tester.widget<TextField>(
        find.byKey(const Key('approval-account')),
      );
      expect(accountField.controller?.text, '1002');

      // 请求已带上门店上下文。
      expect(
        transport.requests.any(
          (r) =>
              r.uri.path == '/cashier/access/recent-authors' &&
              r.headers['X-Shop-Id'] == '1',
        ),
        isTrue,
      );

      // 关闭弹窗。
      await tester.tap(find.byKey(const Key('approval-cancel')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('cashier-approval-dialog')), findsNothing);
    });

    testWidgets('429 限流时显示倒计时并禁用提交按钮，倒计时结束后恢复', (tester) async {
      final transport = FakeHttpTransport({
        'POST /cashier/access/authorize': HttpResponseData(
          statusCode: 429,
          headers: const {'retry-after': '2'},
          body: jsonEncode({
            'code': 429,
            'message': '操作过于频繁，请稍后再试',
            'data': {
              'rateLimitScope': 'CREDENTIAL_FAILURE',
              'retryAfterSeconds': 2,
            },
          }),
        ),
      });
      final client = AdminApiClient(
        baseUrl: 'http://fake',
        transport: transport,
        token: 'fake-token',
        shopId: 1,
        terminalId: 'POS-01',
      );
      final repository = AccessApprovalRepository(client);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => Center(
                child: ElevatedButton(
                  onPressed: () {
                    showCashierApprovalDialog(
                      context,
                      request: const CashierApprovalRequest(
                        title: '退款审批',
                        permission: 'order:operate:refund',
                        permissionLabel: '退款',
                      ),
                      repository: repository,
                    );
                  },
                  child: const Text('打开审批'),
                ),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('打开审批'));
      await tester.pumpAndSettle();

      // 输入账号密码
      await tester.enterText(
        find.byKey(const Key('approval-account')),
        'manager',
      );
      await tester.enterText(
        find.byKey(const Key('approval-credential')),
        'wrong-pass',
      );

      // 点击提交触发 429
      await tester.tap(find.byKey(const Key('approval-submit')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // 验证提示与按钮禁用
      expect(find.textContaining('密码或PIN码错误次数过多'), findsOneWidget);
      expect(find.textContaining('请等待 (2 s)'), findsOneWidget);

      final submitBtn = tester.widget<FilledButton>(
        find.byKey(const Key('approval-submit')),
      );
      expect(submitBtn.onPressed, isNull);

      // 本地倒计时 1 秒
      await tester.pump(const Duration(seconds: 1));
      expect(find.textContaining('请等待 (1 s)'), findsOneWidget);

      // 再过 1 秒，倒计时结束恢复为可点击
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('授权并继续'), findsOneWidget);
      final submitBtnRestored = tester.widget<FilledButton>(
        find.byKey(const Key('approval-submit')),
      );
      expect(submitBtnRestored.onPressed, isNotNull);

      // 关闭弹窗
      await tester.tap(find.byKey(const Key('approval-cancel')));
      await tester.pumpAndSettle();
    });

    testWidgets('未初始化 terminalId 提示且阻止提交授权与出码', (tester) async {
      TerminalDeviceService.instance.setTerminalId(null);
      final transport = FakeHttpTransport({});
      final client = AdminApiClient(
        baseUrl: 'http://fake',
        transport: transport,
        token: 'fake-token',
        shopId: 1,
        // 没有注入 terminalId
      );
      final repository = AccessApprovalRepository(client);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => Center(
                child: ElevatedButton(
                  onPressed: () {
                    showCashierApprovalDialog(
                      context,
                      request: const CashierApprovalRequest(
                        title: '退款审批',
                        permission: 'order:operate:refund',
                        permissionLabel: '退款',
                      ),
                      repository: repository,
                    );
                  },
                  child: const Text('打开审批'),
                ),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('打开审批'));
      await tester.pumpAndSettle();

      // 输入账号密码
      await tester.enterText(
        find.byKey(const Key('approval-account')),
        'manager',
      );
      await tester.enterText(
        find.byKey(const Key('approval-credential')),
        '123456',
      );

      // 提交应报错尚未初始化终端标识，且不发送 authorize 网络请求
      await tester.tap(find.byKey(const Key('approval-submit')));
      await tester.pumpAndSettle();

      expect(find.textContaining('尚未初始化终端标识'), findsOneWidget);
      expect(
        transport.requests.any((r) => r.uri.path == '/cashier/access/authorize'),
        isFalse,
      );

      // 切换到扫码审批同样阻止出码
      await tester.tap(find.byKey(const Key('approval-mode-qr')));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('approval-qr-create')));
      await tester.pumpAndSettle();

      expect(find.textContaining('尚未初始化终端标识'), findsOneWidget);
      expect(
        transport.requests.any((r) => r.uri.path == '/cashier/access/qr/create'),
        isFalse,
      );

      await tester.tap(find.byKey(const Key('approval-cancel')));
      await tester.pumpAndSettle();
    });

    testWidgets('未注入 terminalId 时自动自愈并成功出码', (tester) async {
      // 注册有效终端标识，模拟真实运行时存储中有稳定终端编号但未显式传给 Client
      await TerminalDeviceService.instance.registerTerminalId('AUTO-TERM-001');
      final transport = FakeHttpTransport({
        'GET /cashier/access/recent-authors': jsonEncode({
          'code': 0,
          'data': <Map<String, dynamic>>[],
        }),
        'POST /cashier/access/qr/create': jsonEncode({
          'code': 0,
          'data': {
            'approvalCode': 'QAP_AUTO_123',
            'qrContent': 'https://pos.test/qr?code=QAP_AUTO_123',
            'expireSeconds': 120,
            'status': 'PENDING',
          },
        }),
        'GET /cashier/access/qr/status': jsonEncode({
          'code': 0,
          'data': {'approvalCode': 'QAP_AUTO_123', 'status': 'PENDING'},
        }),
      });
      final client = AdminApiClient(
        baseUrl: 'http://fake',
        transport: transport,
        token: 'fake-token',
        shopId: 1,
        // 故意不传 terminalId
      );
      final repository = AccessApprovalRepository(client);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => Center(
                child: ElevatedButton(
                  onPressed: () {
                    showCashierApprovalDialog(
                      context,
                      request: const CashierApprovalRequest(
                        title: '退款审批',
                        permission: 'order:operate:refund',
                        permissionLabel: '退款',
                      ),
                      repository: repository,
                    );
                  },
                  child: const Text('打开审批'),
                ),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('打开审批'));
      await tester.pumpAndSettle();

      // 切换到扫码审批并出码
      await tester.tap(find.byKey(const Key('approval-mode-qr')));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('approval-qr-create')));
      await tester.pumpAndSettle();

      // 验证未出现错误提示，且成功发送出码请求
      expect(find.textContaining('尚未初始化终端标识'), findsNothing);
      final createReq = transport.requests.firstWhere(
        (r) => r.uri.path == '/cashier/access/qr/create',
      );
      expect(createReq.headers['X-Terminal-Id'], 'AUTO-TERM-001');

      await tester.tap(find.byKey(const Key('approval-cancel')));
      await tester.pumpAndSettle();
    });
  });

  group('方案A·店长移动端扫码审批与权限映射', () {
    test('ApprovalPermissionHelper 中文权限映射覆盖度', () {
      expect(
        ApprovalPermissionHelper.readableName('order:operate:refund:approve'),
        '退款审批',
      );
      expect(
        ApprovalPermissionHelper.readableName('order:operate:changePrice:approve'),
        '改价审批',
      );
      expect(
        ApprovalPermissionHelper.readableName('order:operate:discount:approve'),
        '折扣审批',
      );
      expect(
        ApprovalPermissionHelper.readableName('order:operate:refund'),
        '退款/退菜',
      );
      expect(
        ApprovalPermissionHelper.readableName('order:operate:changePrice'),
        '改价/赠菜',
      );
      expect(
        ApprovalPermissionHelper.readableName('order:operate:discount'),
        '整单优惠/折扣',
      );
    });

    test('CashierApprovalGrant 解析 bindingVersion 2 与 requiredApprovalPermission', () {
      final grant = CashierApprovalGrant.fromJson({
        'approvalNo': 'AP001',
        'approvalToken': 'token-v2',
        'permission': 'order:operate:refund',
        'bindingVersion': 2,
        'legacyBinding': false,
        'requiredApprovalPermission': 'order:operate:refund:approve',
      });
      expect(grant.bindingVersion, 2);
      expect(grant.legacyBinding, isFalse);
      expect(grant.requiredApprovalPermission, 'order:operate:refund:approve');
    });

    test('CashierQrApprovalDetails 解析 bindingVersion 2 与 requiredApprovalPermission', () {
      final details = CashierQrApprovalDetails.fromJson({
        'approvalCode': 'QAP_999',
        'binding_version': 2,
        'legacy_binding': false,
        'required_approval_permission': 'order:operate:changePrice:approve',
      });
      expect(details.bindingVersion, 2);
      expect(details.legacyBinding, isFalse);
      expect(details.requiredApprovalPermission, 'order:operate:changePrice:approve');
    });

    test('ApiException 解析 429 retryAfterSeconds 与 rateLimitScope', () {
      final ex = ApiException(
        'Too Many Requests',
        statusCode: 429,
        code: 429,
        data: const {
          'retryAfterSeconds': 5,
          'rateLimitScope': 'CREDENTIAL_FAILURE',
        },
      );
      expect(ex.isRateLimited, isTrue);
      expect(ex.retryAfterSeconds, 5);
      expect(ex.rateLimitScope, 'CREDENTIAL_FAILURE');
    });
  });

  group('WI-062·三态决策与严格敏感权限适配', () {
    test('parseOutcome 能够正确识别 ALLOW, REQUIRE_APPROVAL, DENY 三态', () {
      expect(
        parseOutcome({'outcome': 'ALLOW'}),
        AuthorizationOutcome.allow,
      );
      expect(
        parseOutcome({'outcome': 'REQUIRE_APPROVAL'}),
        AuthorizationOutcome.requireApproval,
      );
      expect(
        parseOutcome({'outcome': 'DENY'}),
        AuthorizationOutcome.deny,
      );
    });

    test('parseOutcome 保持旧版服务端布尔字段向后兼容性', () {
      // 老服务端 allow == true
      expect(
        parseOutcome({'allow': true}),
        AuthorizationOutcome.allow,
      );
      // 老服务端 allow == false, approvalRequired == true
      expect(
        parseOutcome({'allow': false, 'approvalRequired': true}),
        AuthorizationOutcome.requireApproval,
      );
      // 老服务端 allow == false, approvalRequired == false
      expect(
        parseOutcome({'allow': false, 'approvalRequired': false}),
        AuthorizationOutcome.deny,
      );
      // 空响应默认拒绝
      expect(
        parseOutcome({}),
        AuthorizationOutcome.deny,
      );
    });

    test('敏感操作严格权限常量与收敛', () {
      expect(refundPermission, 'order:operate:refund');
      expect(changePricePermission, 'order:operate:changePrice');
      expect(discountPermission, 'order:operate:discount');
      expect(reopenPermission, 'order:operate:reopen');

      // 审批端展示名称与操作名称映射
      expect(ApprovalPermissionHelper.readableName(reopenPermission), '反结账');
      expect(
        ApprovalPermissionHelper.readableName('$reopenPermission:approve'),
        '反结账审批',
      );
      expect(ApprovalPermissionHelper.readableName(refundPermission), '退款/退菜');
      expect(
        ApprovalPermissionHelper.readableName('$refundPermission:approve'),
        '退款审批',
      );
      expect(
        ApprovalPermissionHelper.readableName(changePricePermission),
        '改价/赠菜',
      );
      expect(
        ApprovalPermissionHelper.readableName('$changePricePermission:approve'),
        '改价审批',
      );
      expect(
        ApprovalPermissionHelper.readableName(discountPermission),
        '整单优惠/折扣',
      );
      expect(
        ApprovalPermissionHelper.readableName('$discountPermission:approve'),
        '折扣审批',
      );
    });

    test('CashierAccessEvaluation 领域模型解析与三态判断', () {
      final allowEval = CashierAccessEvaluation.fromJson({
        'outcome': 'ALLOW',
        'allow': true,
      });
      expect(allowEval.outcome, AuthorizationOutcome.allow);
      expect(allowEval.isAllowed, isTrue);
      expect(allowEval.requiresApproval, isFalse);
      expect(allowEval.isDenied, isFalse);

      final reqApprovalEval = CashierAccessEvaluation.fromJson({
        'outcome': 'REQUIRE_APPROVAL',
        'allow': false,
        'approvalRequired': true,
        'explanation': '退款金额超过阈值，需主管现场授权',
      });
      expect(reqApprovalEval.outcome, AuthorizationOutcome.requireApproval);
      expect(reqApprovalEval.isAllowed, isFalse);
      expect(reqApprovalEval.requiresApproval, isTrue);
      expect(reqApprovalEval.isDenied, isFalse);
      expect(reqApprovalEval.explanation, '退款金额超过阈值，需主管现场授权');

      final denyEval = CashierAccessEvaluation.fromJson({
        'outcome': 'DENY',
        'allow': false,
        'reasonCode': 'ROLE_NOT_AUTHORIZED',
        'explanation': '当前账号无权执行反结账',
      });
      expect(denyEval.outcome, AuthorizationOutcome.deny);
      expect(denyEval.isAllowed, isFalse);
      expect(denyEval.requiresApproval, isFalse);
      expect(denyEval.isDenied, isTrue);
    });

    test('ApiException 错误分类与诊断信息提取 (40321, 403未配置, traceId)', () {
      // 40321 ACCESS_APPROVAL_INVALID
      final invalidTokenEx = ApiException(
        '审批令牌已过期或已使用',
        statusCode: 403,
        code: 40321,
      );
      expect(invalidTokenEx.isApprovalInvalid, isTrue);
      expect(invalidTokenEx.isExplicitDeny, isFalse);

      // 显式拒绝
      final explicitDenyEx = ApiException(
        'ACCESS_EXPLICIT_DENY: 操作被策略拦截',
        statusCode: 403,
        code: 40300,
      );
      expect(explicitDenyEx.isExplicitDeny, isTrue);

      // 403 部署接口权限未配置
      final missingMappingEx = ApiException(
        '接口权限未配置，已被安全拦截',
        statusCode: 403,
        endpointPath: '/cashier/order/uncheckout',
        traceId: 'tr-abc-123',
      );
      expect(missingMappingEx.isPermissionMappingMissing, isTrue);
      expect(missingMappingEx.endpointPath, '/cashier/order/uncheckout');
      expect(missingMappingEx.traceId, 'tr-abc-123');
    });

    testWidgets('runSensitiveWithApproval: 事前评估 DENY 时直接阻断且不弹出审批弹窗',
        (tester) async {
      final transport = FakeHttpTransport({
        'POST /admin/access/evaluate': jsonEncode({
          'code': 0,
          'data': {
            'outcome': 'DENY',
            'reasonCode': 'INSUFFICIENT_PRIVILEGE',
            'explanation': '无权进行反结账',
          },
        }),
      });
      final client = AdminApiClient(
        baseUrl: 'http://fake',
        transport: transport,
        token: 'fake-token',
        shopId: 1,
        terminalId: 'TERM-001',
      );
      final repo = AccessApprovalRepository(client);

      bool executed = false;
      bool? result;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () async {
                  result = await runSensitiveWithApproval(
                    context: context,
                    userId: 101,
                    shopId: 1,
                    repository: repo,
                    request: const CashierApprovalRequest(
                      title: '反结账审批',
                      permission: reopenPermission,
                      permissionLabel: '反结账',
                    ),
                    execute: (token) async {
                      executed = true;
                    },
                  );
                },
                child: const Text('执行反结账'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('执行反结账'));
      await tester.pumpAndSettle();

      expect(executed, isFalse);
      // 确认未弹出审批弹窗
      expect(find.byKey(const Key('approval-mode-credential')), findsNothing);
      expect(find.byKey(const Key('approval-mode-qr')), findsNothing);
      // 弹出权限不足提示
      expect(find.text('权限不足'), findsOneWidget);
      expect(find.text('无权进行反结账'), findsOneWidget);

      // 关闭通知弹窗后完成流程
      await tester.tap(find.text('确定'));
      await tester.pumpAndSettle();
      expect(result, isFalse);
    });

    testWidgets('runSensitiveWithApproval: 直连执行遇到接口权限未配置 403 时上报 traceId 且不重试',
        (tester) async {
      final transport = FakeHttpTransport({});
      final client = AdminApiClient(
        baseUrl: 'http://fake',
        transport: transport,
        token: 'fake-token',
      );
      final repo = AccessApprovalRepository(client);

      int executeCount = 0;
      bool? result;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () async {
                  result = await runSensitiveWithApproval(
                    context: context,
                    repository: repo,
                    request: const CashierApprovalRequest(
                      title: '退款审批',
                      permission: refundPermission,
                      permissionLabel: '订单退款',
                    ),
                    execute: (token) async {
                      executeCount++;
                      throw ApiException(
                        '接口权限未配置',
                        statusCode: 403,
                        endpointPath: '/cashier/order/refund',
                        traceId: 'trace-perm-999',
                      );
                    },
                  );
                },
                child: const Text('触发退款'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('触发退款'));
      await tester.pumpAndSettle();

      expect(executeCount, 1);
      // 弹出系统权限配置异常提示，包含 path 与 traceId
      expect(find.text('系统权限配置异常'), findsOneWidget);
      expect(find.textContaining('traceId: trace-perm-999'), findsOneWidget);
      expect(find.textContaining('/cashier/order/refund'), findsOneWidget);

      // 关闭通知弹窗后完成流程
      await tester.tap(find.text('确定'));
      await tester.pumpAndSettle();
      expect(result, isFalse);
    });

    testWidgets('runSensitiveWithApproval: ACCESS_APPROVAL_INVALID 40321 最多允许重试一次',
        (tester) async {
      final transport = FakeHttpTransport({
        'POST /cashier/access/authorize': jsonEncode({
          'code': 0,
          'data': {
            'approvalNo': 'AP-NEW-001',
            'approvalToken': 'token-new-retry',
            'permission': refundPermission,
            'bindingVersion': 2,
            'legacyBinding': false,
          },
        }),
      });
      final client = AdminApiClient(
        baseUrl: 'http://fake',
        transport: transport,
        token: 'fake-token',
        terminalId: 'TERM-001',
        shopId: 1,
      );
      final repo = AccessApprovalRepository(client);

      int executeCalls = 0;
      final receivedTokens = <String?>[];

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () async {
                  await runSensitiveWithApproval(
                    context: context,
                    repository: repo,
                    request: const CashierApprovalRequest(
                      title: '退款审批',
                      permission: refundPermission,
                      permissionLabel: '退款',
                    ),
                    execute: (token) async {
                      executeCalls++;
                      receivedTokens.add(token);
                      if (executeCalls == 1) {
                        // 首次直连执行，要求现场授权
                        throw ApiException(
                          '需要现场授权',
                          code: 40320,
                          data: const {'reason': 'NEED_APPROVAL'},
                        );
                      } else if (executeCalls == 2) {
                        // 首次携带 token 执行，服务端返回 token 无效 (40321)
                        throw ApiException(
                          '令牌已失效',
                          code: 40321,
                        );
                      } else {
                        // 第二次携带 token 重试执行成功
                        return;
                      }
                    },
                  );
                },
                child: const Text('测试退款重试'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('测试退款重试'));
      await tester.pumpAndSettle();

      // 第一次执行返回 40320 -> 唤起首次授权弹窗
      expect(find.text('退款审批'), findsOneWidget);
      await tester.enterText(
        find.byKey(const Key('approval-account')),
        'manager',
      );
      await tester.enterText(
        find.byKey(const Key('approval-credential')),
        '123456',
      );
      await tester.tap(find.byKey(const Key('approval-submit')));
      await tester.pumpAndSettle();

      // 第二次执行因 token 无效失败 (40321) -> 自动提示并允许再次发起审批
      expect(find.text('退款审批'), findsOneWidget);
      await tester.enterText(
        find.byKey(const Key('approval-account')),
        'manager',
      );
      await tester.enterText(
        find.byKey(const Key('approval-credential')),
        '123456',
      );
      await tester.tap(find.byKey(const Key('approval-submit')));
      await tester.pumpAndSettle();

      // 验证执行次数与收到的令牌
      expect(executeCalls, 3);
      expect(receivedTokens[0], isNull);
      expect(receivedTokens[1], 'token-new-retry');
      expect(receivedTokens[2], 'token-new-retry');
    });
  });

  group('WI-063·高风险操作鉴权契约与三态流转适配', () {
    test('ApiException 与 unwrapResponse 正确提取 outcome, reasonCode, approval', () {
      final jsonPayload = jsonEncode({
        'code': 40320,
        'msg': '当前操作需要店长现场授权后执行',
        'outcome': 'REQUIRE_APPROVAL',
        'reasonCode': 'APPROVAL_REQUIRED',
        'approval': {
          'required': true,
          'permission': 'order:operate:refund',
          'scope': 'ORDER_REFUND',
          'shopId': 1,
          'terminalId': 'POS-01',
          'orderNo': 'ORD-123',
          'amount': 50.0,
        },
      });

      expect(
        () => unwrapResponse(jsonPayload),
        throwsA(
          isA<ApiException>()
              .having((e) => e.code, 'code', 40320)
              .having((e) => e.outcome, 'outcome', 'REQUIRE_APPROVAL')
              .having((e) => e.reasonCode, 'reasonCode', 'APPROVAL_REQUIRED')
              .having((e) => e.isRequireApproval, 'isRequireApproval', isTrue)
              .having((e) => e.isDeny, 'isDeny', isFalse)
              .having(
                (e) => e.approvalPermission,
                'approvalPermission',
                'order:operate:refund',
              ),
        ),
      );
    });

    test('ActionAccessFailure 正确封装 REQUIRE_APPROVAL 与 DENY', () {
      const requireApprovalEx = ApiException(
        '需审批',
        code: 40320,
        outcome: 'REQUIRE_APPROVAL',
        reasonCode: 'APPROVAL_REQUIRED',
        approval: {'permission': 'order:operate:refund'},
      );
      final failure1 = ActionAccessFailure.fromApiException(requireApprovalEx);
      expect(failure1.outcome, AuthorizationOutcome.requireApproval);
      expect(failure1.reasonCode, 'APPROVAL_REQUIRED');
      expect(failure1.approvalPermission, 'order:operate:refund');

      const denyEx = ApiException(
        '无权操作',
        code: 40300,
        outcome: 'DENY',
        reasonCode: 'DENIED',
      );
      final failure2 = ActionAccessFailure.fromApiException(denyEx);
      expect(failure2.outcome, AuthorizationOutcome.deny);
      expect(failure2.reasonCode, 'DENIED');
      expect(failure2.approvalPermission, isNull);
    });

    test('AdminApiClient 非 GET 请求自动注入 X-Client-Request-Id，且保留外部指定的 ID', () async {
      final transport = FakeHttpTransport({
        'POST /cashier/order/test': HttpResponseData(
          statusCode: 200,
          headers: const {},
          body: jsonEncode({'code': 0, 'data': {}}),
        ),
      });
      final client = AdminApiClient(
        baseUrl: 'http://fake',
        transport: transport,
        token: 'test-token',
        shopId: 10,
        terminalId: 'T-001',
      );

      // 1. 未指定 X-Client-Request-Id，自动生成
      await client.post(
        const AdminEndpoint(
          path: '/cashier/order/test',
          method: 'POST',
          permissionCode: 'order:test',
        ),
        body: {'test': true},
      );
      expect(transport.requests.length, 1);
      final req1 = transport.requests.first;
      expect(req1.headers['X-Shop-Id'], '10');
      expect(req1.headers['X-Terminal-Id'], 'T-001');
      expect(req1.headers['X-Client-Request-Id'], startsWith('req-'));

      // 2. 指定了 X-Client-Request-Id，外部 ID 生效
      await client.post(
        const AdminEndpoint(
          path: '/cashier/order/test',
          method: 'POST',
          permissionCode: 'order:test',
        ),
        headers: {'X-Client-Request-Id': 'custom-id-999'},
        body: {'test': true},
      );
      expect(transport.requests.length, 2);
      final req2 = transport.requests.last;
      expect(req2.headers['X-Client-Request-Id'], 'custom-id-999');
    });

    testWidgets('runSensitiveWithApproval: 直连执行遇到 outcome=DENY 时硬阻断且不弹出审批弹窗', (tester) async {
      final transport = FakeHttpTransport({});
      final client = AdminApiClient(
        baseUrl: 'http://fake',
        transport: transport,
        token: 'fake-token',
        shopId: 1,
        terminalId: 'POS-01',
      );
      final repo = AccessApprovalRepository(client);

      int executeCalls = 0;
      bool? result;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () async {
                  result = await runSensitiveWithApproval(
                    context: context,
                    repository: repo,
                    request: const CashierApprovalRequest(
                      title: '退款审批',
                      permission: refundPermission,
                      permissionLabel: '退款',
                    ),
                    execute: (token) async {
                      executeCalls++;
                      throw const ApiException(
                        '无权执行退款操作，且当前不允许审批',
                        code: 40300,
                        outcome: 'DENY',
                        reasonCode: 'DENIED',
                      );
                    },
                  );
                },
                child: const Text('执行退款'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('执行退款'));
      await tester.pumpAndSettle();

      // 执行了 1 次直连
      expect(executeCalls, 1);
      // 禁止弹出审批弹窗
      expect(find.byKey(const Key('cashier-approval-dialog')), findsNothing);
      // 弹出错误提示
      expect(find.text('操作被拒绝'), findsOneWidget);
      expect(find.text('无权执行退款操作，且当前不允许审批'), findsOneWidget);

      // 关闭错误弹窗后返回 false
      await tester.tap(find.text('确定'));
      await tester.pumpAndSettle();
      expect(result, isFalse);
    });

    testWidgets('runSensitiveWithApproval: 直连执行遇到 outcome=REQUIRE_APPROVAL 时唤起弹窗重试', (tester) async {
      final transport = FakeHttpTransport({
        'GET /cashier/access/recent-authors': HttpResponseData(
          statusCode: 200,
          headers: const {},
          body: jsonEncode({'code': 0, 'data': []}),
        ),
        'POST /cashier/access/authorize': HttpResponseData(
          statusCode: 200,
          headers: const {},
          body: jsonEncode({
            'code': 0,
            'data': {
              'approvalNo': 'AP-063',
              'approvalToken': 'token-wi-063',
              'permission': refundPermission,
              'operatorId': 100,
              'authorizerId': 1,
              'authorizerName': '店长',
              'shopId': 1,
              'bindingVersion': 2,
            },
          }),
        ),
      });
      final client = AdminApiClient(
        baseUrl: 'http://fake',
        transport: transport,
        token: 'fake-token',
        shopId: 1,
        terminalId: 'POS-01',
      );
      final repo = AccessApprovalRepository(client);

      int executeCalls = 0;
      final receivedTokens = <String?>[];
      bool? result;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () async {
                  result = await runSensitiveWithApproval(
                    context: context,
                    repository: repo,
                    request: const CashierApprovalRequest(
                      title: '退款审批',
                      permission: refundPermission,
                      permissionLabel: '退款',
                    ),
                    execute: (token) async {
                      executeCalls++;
                      receivedTokens.add(token);
                      if (executeCalls == 1) {
                        throw const ApiException(
                          '需要店长现场授权',
                          code: 40320,
                          outcome: 'REQUIRE_APPROVAL',
                          reasonCode: 'APPROVAL_REQUIRED',
                          approval: {'permission': refundPermission},
                        );
                      }
                      // 第二次携带 token 成功
                      return;
                    },
                  );
                },
                child: const Text('执行退款审批'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('执行退款审批'));
      await tester.pumpAndSettle();

      // 弹窗已打开
      expect(find.byKey(const Key('cashier-approval-dialog')), findsOneWidget);
      await tester.enterText(
        find.byKey(const Key('approval-account')),
        'manager',
      );
      await tester.enterText(
        find.byKey(const Key('approval-credential')),
        '123456',
      );
      await tester.tap(find.byKey(const Key('approval-submit')));
      await tester.pumpAndSettle();

      // 验证执行次数与收到的令牌
      expect(executeCalls, 2);
      expect(receivedTokens[0], isNull);
      expect(receivedTokens[1], 'token-wi-063');
      expect(result, isTrue);
    });
  });
}
