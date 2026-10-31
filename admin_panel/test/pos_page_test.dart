import 'dart:async';

import 'package:admin_panel_flutter/src/core/admin_api_client.dart';
import 'package:admin_panel_flutter/src/features/auth/data/access_approval_repository.dart';
import 'package:admin_panel_flutter/src/features/auth/domain/access_approval_models.dart';
import 'package:admin_panel_flutter/src/features/cashier_member/data/cashier_member_repository.dart';
import 'package:admin_panel_flutter/src/features/cashier_member/domain/cashier_member.dart';
import 'package:admin_panel_flutter/src/features/cashier_settings/domain/cashier_settings.dart';
import 'package:admin_panel_flutter/src/features/cashier_settings/domain/receipt_preview_models.dart';
import 'package:admin_panel_flutter/src/features/cashier_shell/presentation/cashier_tokens.dart';
import 'package:admin_panel_flutter/src/features/pos/data/pending_external_checkout_store.dart';
import 'package:admin_panel_flutter/src/features/pos/data/pos_repository.dart';
import 'package:admin_panel_flutter/src/features/pos/domain/pos_models.dart';
import 'package:admin_panel_flutter/src/features/pos/presentation/occupied_table_view.dart';
import 'package:admin_panel_flutter/src/features/pos/presentation/pos_raw_print_result_dialog.dart';
import 'package:admin_panel_flutter/src/features/pos/presentation/refund_dish_dialog.dart';
import 'package:admin_panel_flutter/src/features/pos/presentation/table_order_page.dart';
import 'package:admin_panel_flutter/src/features/tables/data/table_repository.dart';
import 'package:admin_panel_flutter/src/features/tables/domain/dining_table.dart';
import 'package:admin_panel_flutter/src/features/tables/presentation/table_overview_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_http_transport.dart';

/// 审批中心测试桩：authorize 直接签发固定令牌，供敏感操作流程断言。
class _FakeAccessApprovalRepository implements AccessApprovalRepository {
  _FakeAccessApprovalRepository()
    : client = AdminApiClient(
        baseUrl: 'http://fake',
        transport: FakeHttpTransport(const {}),
        token: 'fake-token',
        terminalId: 'POS-TEST-TERM',
      );

  @override
  final AdminApiClient client;

  String? lastAuthorizerAccount;
  String? lastCredential;
  String? lastAuthMethod;
  String? lastPermission;

  @override
  Future<CashierApprovalGrant> authorize({
    required String permission,
    String? bizType,
    String? bizId,
    double? amount,
    String? reason,
    required String authorizerAccount,
    required String credential,
    String authMethod = 'PASSWORD',
    String? requestId,
    String? terminalId,
  }) async {
    if (credential == 'wrong_password') {
      throw const ApiException('账号或密码错误', statusCode: 401, code: 401);
    }
    lastAuthorizerAccount = authorizerAccount;
    lastCredential = credential;
    lastAuthMethod = authMethod;
    lastPermission = permission;
    return CashierApprovalGrant(
      approvalNo: 'APP-2026-TEST',
      approvalToken: 'fake-approval-token',
      permission: permission,
      operatorId: 1,
      authorizerId: 9,
      authorizerName: authorizerAccount,
      shopId: 1,
      expireSeconds: 120,
    );
  }

  @override
  Future<AccessApprovalPage> listApprovals({
    int page = 1,
    int pageSize = 20,
    String? status,
    String? bizType,
    int? shopId,
  }) async {
    return const AccessApprovalPage();
  }

  @override
  Future<AccessApprovalRecord?> loadApprovalDetail(int id) async => null;

  @override
  Future<List<RecentAuthor>> loadRecentAuthors({int limit = 10}) async =>
      const [];

  @override
  Future<CashierQrApprovalRequest> createQrApproval({
    required String permission,
    String? bizType,
    String? bizId,
    double? amount,
    String? reason,
    String? requestId,
    String? terminalId,
  }) async {
    throw UnimplementedError();
  }

  @override
  Future<CashierQrApprovalStatus> pollQrApprovalStatus(
    String approvalCode,
  ) async {
    throw UnimplementedError();
  }

  @override
  Future<CashierQrApprovalDetails> loadQrApprovalDetails(
    String approvalCode,
  ) async {
    throw UnimplementedError();
  }

  @override
  Future<CashierQrApprovalConfirmResult> confirmQrApproval({
    required String approvalCode,
    required String action,
    String? rejectReason,
  }) async {
    throw UnimplementedError();
  }

  @override
  Future<CashierAccessEvaluation> evaluate({
    required int userId,
    int? shopId,
    required String permission,
    Map<String, Object?>? context,
  }) async => const CashierAccessEvaluation(
    allow: true,
    approvalRequired: false,
    outcome: AuthorizationOutcome.allow,
  );
}

void main() {
  testWidgets('failed quick order shows API error and keeps the page open', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1920, 1080);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final table = DiningTable.fromJson({'number': '40', 'status': 1});
    final repository = _FakePosRepository(
      PosWorkspace(
        table: table,
        categories: const [
          PosCategory(id: 3, name: '招牌菜品', code: 'signature', sorting: 1),
        ],
        dishes: const [
          PosDish(
            id: 7,
            name: '油边王',
            categoryId: 3,
            price: 15,
            unit: '份',
            stock: 12,
            onSale: true,
            soldOut: false,
            specGroups: [],
          ),
        ],
        paymentMethods: const [],
        currentOrder: null,
      ),
      submitError: const ApiException('菜品价格校验失败'),
    );
    var completed = false;

    await tester.pumpWidget(
      MaterialApp(
        home: TableOrderPage(
          table: table,
          repository: repository,
          approvalRepository: _FakeAccessApprovalRepository(),
          onCompleted: () => completed = true,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('油边王'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('确认下单'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('下单失败'), findsOneWidget);
    expect(find.text('菜品价格校验失败'), findsOneWidget);
    expect(find.byType(TableOrderPage), findsOneWidget);
    expect(completed, isFalse);
    expect(repository.submitRequestIds, hasLength(1));

    await tester.tap(find.byKey(const Key('pos-notice-primary')));
    await tester.pumpAndSettle();
    repository.submitError = null;
    await tester.tap(find.text('确认下单'));
    await tester.pumpAndSettle();

    expect(repository.submitRequestIds, hasLength(2));
    expect(repository.submitRequestIds.toSet(), hasLength(1));
  });

  testWidgets('empty table selects a specification and opens the table', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1920, 1080);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final table = DiningTable.fromJson({'number': '40', 'status': 0});
    final repository = _FakePosRepository(
      PosWorkspace(
        table: table,
        categories: const [
          PosCategory(id: 3, name: '招牌菜品', code: 'signature', sorting: 1),
        ],
        dishes: const [
          PosDish(
            id: 7,
            name: '油边王',
            categoryId: 3,
            price: 15,
            unit: '份',
            stock: 12,
            onSale: true,
            soldOut: false,
            specGroups: [
              PosSpecGroup(label: '辣度', options: ['微辣', '不辣']),
            ],
          ),
        ],
        paymentMethods: const [],
        currentOrder: null,
      ),
    );
    var completed = false;

    await tester.pumpWidget(
      MaterialApp(
        home: TableOrderPage(
          table: table,
          repository: repository,
          approvalRepository: _FakeAccessApprovalRepository(),
          onCompleted: () => completed = true,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('是否开台'), findsOneWidget);
    expect(repository.openedTableNumber, isNull);
    await tester.tap(find.byKey(const Key('pos-notice-primary')));
    await tester.pumpAndSettle();
    expect(repository.openedTableNumber, '40');
    expect(find.text('开台成功'), findsNothing);
    expect(find.text('40号'), findsOneWidget);

    expect(find.text('招牌菜品'), findsOneWidget);
    expect(find.text('油边王'), findsOneWidget);
    expect(
      tester.getRect(find.byKey(const Key('pos-left-column'))),
      const Rect.fromLTWH(10, 10, 140, 1060),
    );
    expect(
      tester.getRect(find.byKey(const Key('pos-category-rail'))),
      const Rect.fromLTWH(10, 10, 140, 1060),
    );
    expect(
      tester.getRect(find.byKey(const Key('pos-cart-panel'))),
      const Rect.fromLTWH(1530, 10, 380, 1060),
    );
    expect(
      tester.getRect(find.byKey(const Key('pos-category-all'))),
      const Rect.fromLTWH(11, 11, 138, 48),
    );
    expect(find.byKey(const Key('pos-submit-empty')), findsNothing);
    expect(find.text('请从左侧点选菜品'), findsOneWidget);
    await tester.tap(find.text('油边王'));
    await tester.pumpAndSettle();
    expect(find.text('选择辣度'), findsOneWidget);
    final dialogRect = tester.getRect(find.byKey(const Key('spec-dialog')));
    expect(dialogRect.left, 584);
    expect(dialogRect.width, 752);

    final optRect = tester.getRect(find.byKey(const Key('spec-option-辣度-微辣')));
    expect(optRect.left, 624);
    expect(optRect.width, 170);
    expect(optRect.height, 60);

    expect(
      tester.getSize(find.byKey(const Key('spec-quantity-decrease'))).width,
      greaterThanOrEqualTo(48),
    );
    expect(
      tester.getSize(find.byKey(const Key('spec-quantity-decrease'))).height,
      greaterThanOrEqualTo(48),
    );
    expect(
      tester.getSize(find.byKey(const Key('spec-quantity-increase'))).width,
      greaterThanOrEqualTo(48),
    );
    expect(
      tester.getSize(find.byKey(const Key('spec-quantity-increase'))).height,
      greaterThanOrEqualTo(48),
    );
    final cancelRect = tester.getRect(find.byKey(const Key('spec-cancel')));
    expect(cancelRect.left, 624);
    expect(cancelRect.width, 326);
    expect(cancelRect.height, 58);

    final confirmRect = tester.getRect(find.byKey(const Key('spec-confirm')));
    expect(confirmRect.left, 970);
    expect(confirmRect.width, 326);
    expect(confirmRect.height, 58);
    await tester.tap(find.text('微辣'));
    await tester.tap(find.byKey(const Key('spec-quantity-increase')));
    await tester.tap(find.text('确认'));
    await tester.pumpAndSettle();

    expect(find.textContaining('微辣'), findsOneWidget);
    final backBtnFinder = find.byKey(const Key('pos-cart-back-button'));
    expect(backBtnFinder, findsOneWidget);
    final backBtn = tester.widget<FilledButton>(backBtnFinder);
    expect(backBtn.style!.backgroundColor!.resolve({}), const Color(0xff2563eb));
    expect(tester.getSize(backBtnFinder).height, greaterThanOrEqualTo(36));

    final priceTextFinder = find.descendant(
      of: find.byKey(const Key('cart-row-1')),
      matching: find.text('¥15.00'),
    );
    expect(priceTextFinder, findsOneWidget);
    final priceText = tester.widget<Text>(priceTextFinder);
    expect(priceText.style!.color, const Color(0xffdc2626));
    final submitRect = tester.getRect(find.byKey(const Key('pos-submit-populated')));
    expect(submitRect.top, 1005);
    expect(submitRect.height, 52);
    expect(submitRect.right, 1895);
    final rowRect = tester.getRect(find.byKey(const Key('cart-row-1')));
    expect(rowRect.left, 1541);
    expect(rowRect.top, 73);
    expect(rowRect.width, 358);
    expect(rowRect.height, closeTo(78.5, 0.5));
    await tester.tap(find.text('确认下单'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('下单成功'), findsNothing);
    await tester.pumpAndSettle();

    expect(repository.submittedLines, hasLength(1));
    expect(repository.submittedLines.single.selections, {'辣度': '微辣'});
    expect(repository.submittedLines.single.quantity, 2);
    expect(completed, isTrue);

    // 下单成功后停留并进入桌台明细（而非返回/停留下单页）
    expect(find.byKey(const Key('occupied-left-column')), findsOneWidget);
    expect(find.byKey(const Key('occupied-print-button')), findsOneWidget);
    expect(find.byKey(const Key('pos-submit-populated')), findsNothing);
  });

  testWidgets('加菜成功后强制重载云端真实订单并停留桌台明细', (tester) async {
    tester.view.physicalSize = const Size(1920, 1080);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final table = DiningTable.fromJson({'number': '40', 'status': 1});
    final categories = const [
      PosCategory(id: 3, name: '招牌菜品', code: 'signature', sorting: 1),
    ];
    final dishes = const [
      PosDish(
        id: 7,
        name: '油边王',
        categoryId: 3,
        price: 15,
        unit: '份',
        stock: 12,
        onSale: true,
        soldOut: false,
        specGroups: [],
      ),
    ];
    final existingOrder = const PosOrder(
      id: 40,
      orderNo: 'ORD40',
      tableNumber: '40',
      diners: 2,
      total: 0,
      grossAmount: 0,
      createdAt: null,
      lines: [],
    );
    final repository = _FakePosRepository(
      PosWorkspace(
        table: table,
        categories: categories,
        dishes: dishes,
        paymentMethods: const [],
        currentOrder: existingOrder,
      ),
      refreshedWorkspace: PosWorkspace(
        table: table,
        categories: categories,
        dishes: dishes,
        paymentMethods: const [],
        currentOrder: PosOrder(
          id: existingOrder.id,
          orderNo: existingOrder.orderNo,
          tableNumber: existingOrder.tableNumber,
          diners: existingOrder.diners,
          total: 15,
          grossAmount: 15,
          createdAt: null,
          lines: const [
            PosOrderLine(
              id: 501,
              name: '油边王',
              quantity: 1,
              total: 15,
              unit: '份',
              specification: '',
              refunded: false,
            ),
          ],
        ),
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: TableOrderPage(
          table: table,
          repository: repository,
          approvalRepository: _FakeAccessApprovalRepository(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // 占用桌直接展示桌台明细
    expect(find.byKey(const Key('occupied-left-column')), findsOneWidget);

    // 加菜：进入点菜页，选菜，提交加菜
    await tester.tap(find.text('加菜'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('油边王'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('确认加菜'));
    await tester.pumpAndSettle();

    // 加菜成功后停留桌台明细，二次强制重载覆盖为云端真实订单（真实 detailId=501）
    expect(find.byKey(const Key('occupied-left-column')), findsOneWidget);
    expect(find.byKey(const Key('order-refund-501')), findsOneWidget);
    expect(repository.workspaceLoadCount, 2);
  });

  testWidgets('加菜失败重试复用同一请求标识，成功后不再重复', (tester) async {
    tester.view.physicalSize = const Size(1920, 1080);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final table = DiningTable.fromJson({'number': '40', 'status': 1});
    const categories = [
      PosCategory(id: 3, name: '招牌菜品', code: 'signature', sorting: 1),
    ];
    const dishes = [
      PosDish(
        id: 7,
        name: '油边王',
        categoryId: 3,
        price: 15,
        unit: '份',
        stock: 12,
        onSale: true,
        soldOut: false,
        specGroups: [],
      ),
    ];
    const existingOrder = PosOrder(
      id: 40,
      orderNo: 'ORD40',
      tableNumber: '40',
      diners: 2,
      total: 0,
      grossAmount: 0,
      createdAt: null,
      lines: [],
    );
    final repository = _FakePosRepository(
      PosWorkspace(
        table: table,
        categories: categories,
        dishes: dishes,
        paymentMethods: const [],
        currentOrder: existingOrder,
      ),
      refreshedWorkspace: PosWorkspace(
        table: table,
        categories: categories,
        dishes: dishes,
        paymentMethods: const [],
        currentOrder: const PosOrder(
          id: 40,
          orderNo: 'ORD40',
          tableNumber: '40',
          diners: 2,
          total: 15,
          grossAmount: 15,
          createdAt: null,
          lines: [
            PosOrderLine(
              id: 501,
              name: '油边王',
              quantity: 1,
              total: 15,
              unit: '份',
              specification: '',
              refunded: false,
            ),
          ],
        ),
      ),
    );
    // 首次加菜返回模糊失败（如响应丢失），模拟用户随后重试。
    repository.addDishesError = const ApiException('网络超时');

    await tester.pumpWidget(
      MaterialApp(
        home: TableOrderPage(
          table: table,
          repository: repository,
          approvalRepository: _FakeAccessApprovalRepository(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('加菜'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('油边王'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('确认加菜'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('加菜失败'), findsOneWidget);
    expect(repository.addDishRequestIds, hasLength(1));
    expect(repository.addDishRequestIds.single, isNotEmpty);

    // 关闭失败弹窗，接口恢复后以相同购物车重试：必须复用同一请求标识。
    await tester.tap(find.byKey(const Key('pos-notice-primary')));
    await tester.pumpAndSettle();
    repository.addDishesError = null;
    await tester.tap(find.text('确认加菜'));
    await tester.pumpAndSettle();

    expect(repository.addDishRequestIds, hasLength(2));
    expect(repository.addDishRequestIds.toSet(), hasLength(1));
    expect(find.byKey(const Key('occupied-left-column')), findsOneWidget);
  });

  testWidgets('加菜发生未预期的 Error（如类型转换异常）时被保护拦截并提示，不引发原生崩溃', (tester) async {
    tester.view.physicalSize = const Size(1920, 1080);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final table = DiningTable.fromJson({'number': '40', 'status': 1});
    const categories = [
      PosCategory(id: 3, name: '招牌菜品', code: 'signature', sorting: 1),
    ];
    const dishes = [
      PosDish(
        id: 7,
        name: '油边王',
        categoryId: 3,
        price: 15,
        unit: '份',
        stock: 12,
        onSale: true,
        soldOut: false,
        specGroups: [],
      ),
    ];
    const existingOrder = PosOrder(
      id: 40,
      orderNo: 'ORD40',
      tableNumber: '40',
      diners: 2,
      total: 15,
      grossAmount: 15,
      createdAt: null,
      lines: [
        PosOrderLine(
          id: 501,
          name: '油边王',
          quantity: 1,
          total: 15,
          unit: '份',
          specification: '',
          refunded: false,
        ),
      ],
    );
    final repository = _FakePosRepository(
      PosWorkspace(
        table: table,
        categories: categories,
        dishes: dishes,
        paymentMethods: const [],
        currentOrder: existingOrder,
      ),
    );
    // 模拟底层抛出非 Exception 的 Error（例如 TypeError/StateError）
    repository.addDishesError = TypeError();

    await tester.pumpWidget(
      MaterialApp(
        home: TableOrderPage(
          table: table,
          repository: repository,
          approvalRepository: _FakeAccessApprovalRepository(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('加菜'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('油边王'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('确认加菜'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('加菜失败'), findsOneWidget);
    expect(find.byKey(const Key('pos-notice-primary')), findsOneWidget);

    // 关闭错误提示，界面恢复正常交互并未崩溃退出
    await tester.tap(find.byKey(const Key('pos-notice-primary')));
    await tester.pumpAndSettle();
    expect(find.text('确认加菜'), findsOneWidget);
  });

  testWidgets('OccupiedTableView 在 currentOrder 异常为空时安全降级不引发空指针崩溃', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1920, 1080);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final table = DiningTable.fromJson({'number': '40', 'status': 1});
    var backTapped = false;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: OccupiedTableView(
            workspace: PosWorkspace(
              table: table,
              categories: const [],
              dishes: const [],
              paymentMethods: const [],
              currentOrder: null,
            ),
            busy: false,
            onBack: () => backTapped = true,
            onAddDishes: ([_]) {},
            onMerge: () {},
            onTransfer: ([_]) {},
            onClear: () {},
            onRefund: (_) {},
            onGift: (_) {},
            onDiscount: ([_]) {},
            onPrintReceipt: (_, [_]) {},
            paymentMethods: const [],
            onCheckout: (_) {},
            onBalanceCheckout: () {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('暂无当前账单信息'), findsOneWidget);
    await tester.tap(find.text('返回桌台'));
    expect(backTapped, isTrue);
  });

  testWidgets('整单优惠确认后停留桌台明细，不跳回点餐页', (tester) async {
    tester.view.physicalSize = const Size(1920, 1080);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final table = DiningTable.fromJson({'number': '40', 'status': 1});
    final categories = const [
      PosCategory(id: 3, name: '招牌菜品', code: 'signature', sorting: 1),
    ];
    final dishes = const [
      PosDish(
        id: 7,
        name: '油边王',
        categoryId: 3,
        price: 50,
        unit: '份',
        stock: 12,
        onSale: true,
        soldOut: false,
        specGroups: [],
      ),
    ];
    final repository = _FakePosRepository(
      PosWorkspace(
        table: table,
        categories: categories,
        dishes: dishes,
        paymentMethods: const [],
        currentOrder: const PosOrder(
          id: 40,
          orderNo: 'ORD40',
          tableNumber: '40',
          diners: 2,
          total: 100,
          grossAmount: 100,
          createdAt: null,
          lines: [
            PosOrderLine(
              id: 501,
              name: '油边王',
              quantity: 2,
              total: 100,
              unit: '份',
              specification: '',
              refunded: false,
            ),
          ],
        ),
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: TableOrderPage(
          table: table,
          repository: repository,
          approvalRepository: _FakeAccessApprovalRepository(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // 占用桌直接展示桌台明细
    expect(find.byKey(const Key('occupied-left-column')), findsOneWidget);

    // 整单优惠：选择 9 折并确认
    await tester.tap(find.byKey(const Key('occupied-discount-button')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('discount-dialog')), findsOneWidget);
    await tester.tap(find.byKey(const Key('discount-preset-9')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('discount-confirm')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('cashier-approval-dialog')), findsOneWidget);
    await tester.enterText(
      find.byKey(const Key('approval-account')),
      'manager',
    );
    await tester.enterText(
      find.byKey(const Key('approval-credential')),
      'pass123',
    );
    await tester.tap(find.byKey(const Key('approval-submit')));
    await tester.pumpAndSettle();

    // 优惠确认后仍在桌台明细，弹窗已关，未跳回点餐页
    expect(find.byKey(const Key('occupied-left-column')), findsOneWidget);
    expect(find.byKey(const Key('discount-dialog')), findsNothing);
    expect(find.byKey(const Key('cashier-approval-dialog')), findsNothing);
    expect(find.byKey(const Key('pos-submit-populated')), findsNothing);
    expect(repository.discountApprovalToken, 'fake-approval-token');
  });

  testWidgets(
    'empty opened table warns on back and clears after confirmation',
    (tester) async {
      tester.view.devicePixelRatio = 1.0;
      tester.view.physicalSize = const Size(1920, 1080);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final table = DiningTable.fromJson({'number': '40', 'status': 0});
      final repository = _FakePosRepository(
        PosWorkspace(
          table: DiningTable.fromJson({'number': '40', 'status': 1}),
          categories: const [],
          dishes: const [],
          paymentMethods: const [],
          currentOrder: null,
        ),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: FilledButton(
                key: const Key('open-table-order-page'),
                onPressed: () => Navigator.of(context).push<void>(
                  MaterialPageRoute<void>(
                    builder: (_) => TableOrderPage(
                      table: table,
                      repository: repository,
                      approvalRepository: _FakeAccessApprovalRepository(),
                      initiallyOpened: true,
                    ),
                  ),
                ),
                child: const Text('进入点餐'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.byKey(const Key('open-table-order-page')));
      await tester.pumpAndSettle();

      // 开台未点餐点返回：直接返回，不弹"尚未点餐"确认，也不自动清台。
      await tester.tap(find.byTooltip('返回桌台'));
      await tester.pumpAndSettle();

      expect(find.text('尚未点餐'), findsNothing);
      expect(repository.clearedTableNumber, isNull);
      expect(find.byKey(const Key('open-table-order-page')), findsOneWidget);
    },
  );

  testWidgets(
    'occupied order details keep original dishes before added dishes',
    (tester) async {
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final table = DiningTable.fromJson({
        'id': 120,
        'number': '40',
        'status': 1,
        'number_of_diners': 2,
        'sett_amount': 30,
      });
      final repository = _FakePosRepository(
        PosWorkspace(
          table: table,
          categories: const [],
          dishes: const [],
          paymentMethods: const [],
          currentOrder: const PosOrder(
            id: 9,
            orderNo: 'ORD40',
            tableNumber: '40',
            diners: 2,
            total: 30,
            createdAt: null,
            // 模拟云端返回最新加菜在前的数组顺序。
            lines: [
              PosOrderLine(
                id: 102,
                name: '后加拍黄瓜',
                quantity: 1,
                total: 15,
                specification: '',
                refunded: false,
              ),
              PosOrderLine(
                id: 101,
                name: '原单油边王',
                quantity: 1,
                total: 15,
                specification: '',
                refunded: false,
              ),
            ],
          ),
        ),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: TableOrderPage(
            table: table,
            repository: repository,
            approvalRepository: _FakeAccessApprovalRepository(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final originalY = tester
          .getTopLeft(find.byKey(const Key('order-refund-101')))
          .dy;
      final addedY = tester
          .getTopLeft(find.byKey(const Key('order-refund-102')))
          .dy;
      expect(originalY, lessThan(addedY));
    },
  );

  testWidgets('occupied table exposes order actions and confirms clearing', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1920, 1080);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final table = DiningTable.fromJson({
      'id': 120,
      'number': '40',
      'status': 1,
      'number_of_diners': 4,
      'sett_amount': 60,
    });
    final repository = _FakePosRepository(
      PosWorkspace(
        table: table,
        categories: const [],
        dishes: const [],
        paymentMethods: const [
          PosPaymentMethod(
            id: 1,
            code: 'wechat',
            name: '微信支付',
            sortOrder: 1,
            enabled: true,
          ),
          PosPaymentMethod(
            id: 2,
            code: 'alipay',
            name: '支付宝',
            sortOrder: 2,
            enabled: true,
          ),
          PosPaymentMethod(
            id: 3,
            code: 'cash',
            name: '现金支付',
            sortOrder: 3,
            enabled: true,
          ),
          PosPaymentMethod(
            id: 4,
            code: 'balance',
            name: '储值划扣',
            sortOrder: 4,
            enabled: true,
          ),
        ],
        currentOrder: const PosOrder(
          id: 9,
          orderNo: 'ORD40',
          tableNumber: '40',
          diners: 4,
          total: 60,
          memberPhone: '13800000000',
          createdAt: null,
          lines: const [
            PosOrderLine(
              id: 91,
              name: '油边王',
              quantity: 4,
              total: 60,
              specification: '不辣',
              refunded: false,
            ),
          ],
        ),
      ),
    );
    var completed = false;

    await tester.pumpWidget(
      MaterialApp(
        home: TableOrderPage(
          table: table,
          repository: repository,
          approvalRepository: _FakeAccessApprovalRepository(),
          memberRepository: _FakeMemberHistoryRepository(),
          onCompleted: () => completed = true,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('订单编号：ORD40'), findsOneWidget);
    expect(find.text('(4人就餐-老肥会员)'), findsOneWidget);
    expect(find.byKey(const Key('occupied-member-history')), findsOneWidget);
    await tester.tap(find.byKey(const Key('occupied-member-history')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('member-consumption-dialog')), findsOneWidget);
    expect(find.text('会员消费记录'), findsOneWidget);
    expect(find.text('ORD-HISTORY-1'), findsOneWidget);
    // 摘要条「累计消费」+ 表格行实付金额 各一处
    expect(find.text('¥88.80'), findsNWidgets(2));
    await tester.tap(find.byKey(const Key('member-consumption-close')));
    await tester.pumpAndSettle();
    expect(find.text('未结账'), findsOneWidget);
    expect(
      _decorationColor(tester, const Key('occupied-status-ribbon-fill')),
      const Color(0xff59a0f0),
    );
    expect(find.text('油边王'), findsOneWidget);
    expect(find.text('并台'), findsOneWidget);
    expect(find.text('换台'), findsOneWidget);
    expect(find.text('清台'), findsOneWidget);
    expect(find.text('加菜'), findsOneWidget);
    expect(find.text('整单折扣'), findsOneWidget);
    expect(find.text('打印小票'), findsOneWidget);
    expect(find.text('打印前台小票'), findsNothing);
    expect(find.text('补打厨房小票'), findsNothing);
    expect(find.text('组合支付'), findsNothing);
    expect(find.text('整单免单'), findsNothing);
    expect(find.text('储值划扣'), findsNothing);
    expect(find.byKey(const Key('order-gift-91')), findsOneWidget);
    expect(
      tester.getSize(find.byKey(const Key('occupied-left-column'))),
      const Size(420, 1050),
    );
    expect(
      tester.getTopLeft(find.byKey(const Key('occupied-order-lines'))).dy,
      100,
    );
    final mergeRect = tester.getRect(
      find.byKey(const Key('occupied-merge-button')),
    );
    expect(mergeRect.height, greaterThanOrEqualTo(48));
    expect(find.byKey(const Key('occupied-status-ribbon')), findsOneWidget);
    final discountRect = tester.getRect(
      find.byKey(const Key('occupied-discount-button')),
    );
    expect(discountRect.height, greaterThanOrEqualTo(48));
    expect(find.byKey(const Key('occupied-print-button')), findsOneWidget);
    expect(
      find.byKey(const Key('occupied-kitchen-print-button')),
      findsNothing,
    );
    final amountBarFinder = find.byKey(const Key('occupied-amount-bar'));
    final paymentBarFinder = find.byKey(const Key('occupied-payment-bar'));
    final wechatCardFinder = find.byKey(const Key('pay-card-wechat'));
    expect(amountBarFinder, findsOneWidget);
    expect(paymentBarFinder, findsOneWidget);
    expect(wechatCardFinder, findsOneWidget);
    expect(tester.getRect(amountBarFinder).left, equals(1541.0));
    expect(tester.getRect(amountBarFinder).width, equals(360.0));
    expect(tester.getRect(paymentBarFinder).left, equals(1541.0));
    expect(tester.getRect(paymentBarFinder).width, equals(360.0));
    expect(tester.getRect(wechatCardFinder).height, equals(64.0));
    for (final code in ['wechat', 'alipay', 'cash']) {
      expect(_decorationColor(tester, Key('pay-fill-$code')), Colors.white);
      final cardCenter = tester
          .getRect(find.byKey(Key('pay-card-$code')))
          .center;
      final iconCenter = tester
          .getRect(find.byKey(Key('pay-icon-$code')))
          .center;
      final labelCenter = tester
          .getRect(find.byKey(Key('pay-label-$code')))
          .center;
      expect(iconCenter.dy, closeTo(cardCenter.dy, .5));
      expect(labelCenter.dy, closeTo(cardCenter.dy, .5));
      expect(iconCenter.dx, lessThan(cardCenter.dx));
      expect(labelCenter.dx, greaterThan(cardCenter.dx));
    }
    await tester.tap(find.byKey(const Key('pay-card-alipay')));
    await tester.pump();
    expect(
      _decorationColor(tester, const Key('pay-fill-alipay')),
      const Color(0x3858a6ff),
    );
    await tester.tap(find.byKey(const Key('checkout-dialog-cancel')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('清台'));
    await tester.pumpAndSettle();
    expect(find.text('清台提示'), findsOneWidget);
    expect(find.text('确定要清台吗？'), findsOneWidget);
    expect(
      tester.getRect(find.byKey(const Key('pos-notice-dialog'))),
      const Rect.fromLTWH(658, 358, 604, 364),
    );
    expect(find.byKey(const Key('pos-notice-close')), findsOneWidget);
    await tester.tap(find.text('确认'));
    await tester.pumpAndSettle();

    expect(repository.clearedTableNumber, '40');
    expect(find.text('清台成功'), findsNothing);
    expect(completed, isTrue);
  });

  testWidgets('occupied table hangs the order and releases the table', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1920, 1080);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final table = DiningTable.fromJson({
      'id': 120,
      'number': '40',
      'status': 1,
      'number_of_diners': 4,
      'sett_amount': 60,
    });
    final repository = _FakePosRepository(
      PosWorkspace(
        table: table,
        categories: const [],
        dishes: const [],
        paymentMethods: const [
          PosPaymentMethod(
            id: 1,
            code: 'wechat',
            name: '微信支付',
            sortOrder: 1,
            enabled: true,
          ),
        ],
        currentOrder: const PosOrder(
          id: 9,
          orderNo: 'ORD40',
          tableNumber: '40',
          diners: 4,
          total: 60,
          createdAt: null,
          lines: const [
            PosOrderLine(
              id: 91,
              name: '油边王',
              quantity: 4,
              total: 60,
              specification: '不辣',
              refunded: false,
            ),
          ],
        ),
      ),
    );
    var completed = false;

    await tester.pumpWidget(
      MaterialApp(
        home: TableOrderPage(
          table: table,
          repository: repository,
          approvalRepository: _FakeAccessApprovalRepository(),
          onCompleted: () => completed = true,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('occupied-hang-button')), findsOneWidget);
    await tester.tap(find.byKey(const Key('occupied-hang-button')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('hang-dialog-confirm-button')), findsOneWidget);
    await tester.tap(find.byKey(const Key('hang-dialog-confirm-button')));
    await tester.pumpAndSettle();

    expect(repository.hungOrderNo, 'ORD40');
    expect(completed, isTrue);
  });

  testWidgets('settled table uses a red settlement ribbon', (tester) async {
    tester.view.physicalSize = const Size(1920, 1080);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final table = DiningTable.fromJson({
      'id': 120,
      'number': '40',
      'status': 2,
      'sett_amount': 60,
    });
    final repository = _FakePosRepository(
      PosWorkspace(
        table: table,
        categories: const [],
        dishes: const [],
        currentOrder: const PosOrder(
          id: 9,
          orderNo: 'ORD40',
          tableNumber: '40',
          diners: 2,
          total: 60,
          createdAt: null,
          lines: [],
        ),
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: TableOrderPage(
          table: table,
          repository: repository,
          approvalRepository: _FakeAccessApprovalRepository(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('已结账'), findsOneWidget);
    expect(find.text('(2人就餐-无绑定)'), findsOneWidget);
    expect(find.byKey(const Key('occupied-member-history')), findsNothing);
    expect(
      _decorationColor(tester, const Key('occupied-status-ribbon-fill')),
      const Color(0xffed5b5d),
    );
  });

  testWidgets(
    'settled table without cloud order shows settled placeholder instead of empty ordering view',
    (tester) async {
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final table = DiningTable.fromJson({
        'id': 121,
        'number': '41',
        'status': 2,
        'sett_amount': 0,
      });
      final repository = _FakePosRepository(
        PosWorkspace(
          table: table,
          categories: const [],
          dishes: const [],
          currentOrder: null,
        ),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: TableOrderPage(
            table: table,
            repository: repository,
            approvalRepository: _FakeAccessApprovalRepository(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // 已结账未清台且云端未返回订单：渲染已结账占位页，不渲染空点单
      expect(find.byKey(const Key('pos-settled-empty-table')), findsOneWidget);
      expect(find.text('41号桌已结账'), findsOneWidget);
      expect(find.byKey(const Key('pos-settled-clear')), findsOneWidget);
      expect(find.text('请从右侧选择菜品'), findsNothing);
      expect(find.text('尚未点餐'), findsNothing);
    },
  );

  testWidgets('failed opening blocks ordering and exposes a retry entry', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1920, 1080);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final table = DiningTable.fromJson({'number': '40', 'status': 0});
    final repository = _FakePosRepository(
      PosWorkspace(
        table: table,
        categories: const [],
        dishes: const [
          PosDish(
            id: 7,
            name: '油边王',
            categoryId: 3,
            price: 15,
            unit: '份',
            stock: 5,
            onSale: true,
            soldOut: false,
            specGroups: [],
          ),
        ],
        currentOrder: null,
      ),
      failOpen: true,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: TableOrderPage(
          table: table,
          repository: repository,
          approvalRepository: _FakeAccessApprovalRepository(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('pos-notice-primary')));
    await tester.pumpAndSettle();

    expect(find.text('开台失败'), findsOneWidget);
    await tester.tap(find.byKey(const Key('pos-notice-primary')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('pos-unopened-table')), findsOneWidget);
    expect(find.text('油边王'), findsNothing);

    await tester.tap(find.byKey(const Key('pos-open-retry')));
    await tester.pumpAndSettle();
    expect(find.text('是否开台'), findsOneWidget);
  });

  testWidgets('merge and transfer finish without a second success dialog', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1920, 1080);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final table = DiningTable.fromJson({'number': '40', 'status': 1});
    final repository = _FakePosRepository(
      PosWorkspace(
        table: table,
        categories: const [],
        dishes: const [],
        paymentMethods: const [],
        currentOrder: const PosOrder(
          id: 9,
          orderNo: 'ORD40',
          tableNumber: '40',
          diners: 2,
          total: 0,
          createdAt: null,
          lines: [],
        ),
      ),
    );
    var completedCount = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: TableOrderPage(
          table: table,
          repository: repository,
          approvalRepository: _FakeAccessApprovalRepository(),
          onCompleted: () => completedCount += 1,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('occupied-merge-button')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '41');
    await tester.tap(find.text('确认'));
    await tester.pumpAndSettle();

    expect(repository.mergedSourceTableNumber, '40');
    expect(repository.mergedTargetTableNumber, '41');
    expect(find.text('并台成功'), findsNothing);
    expect(completedCount, 1);

    await tester.tap(find.text('换台'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '42');
    await tester.tap(find.text('确认'));
    await tester.pumpAndSettle();

    expect(repository.transferredOrderNo, 'ORD40');
    expect(repository.transferredTargetTableNumber, '42');
    expect(find.text('换台成功'), findsNothing);
    expect(completedCount, 2);
  });

  testWidgets('payment bar scrolls when more than three methods are enabled', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1920, 1080);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final table = DiningTable.fromJson({'number': '40', 'status': 1});
    final repository = _FakePosRepository(
      PosWorkspace(
        table: table,
        categories: const [],
        dishes: const [],
        paymentMethods: const [
          PosPaymentMethod(
            id: 1,
            code: 'wechat',
            name: '微信',
            sortOrder: 1,
            enabled: true,
          ),
          PosPaymentMethod(
            id: 2,
            code: 'alipay',
            name: '支付宝',
            sortOrder: 2,
            enabled: true,
          ),
          PosPaymentMethod(
            id: 3,
            code: 'cash',
            name: '现金',
            sortOrder: 3,
            enabled: true,
          ),
          PosPaymentMethod(
            id: 4,
            code: 'card',
            name: '银行卡',
            sortOrder: 4,
            enabled: true,
          ),
        ],
        currentOrder: const PosOrder(
          id: 9,
          orderNo: 'ORD40',
          tableNumber: '40',
          diners: 2,
          total: 60,
          createdAt: null,
          lines: [],
        ),
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: TableOrderPage(
          table: table,
          repository: repository,
          approvalRepository: _FakeAccessApprovalRepository(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('pay-card-card')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('order line gift action changes the line price to zero', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1920, 1080);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final table = DiningTable.fromJson({'number': '40', 'status': 1});
    final repository = _FakePosRepository(
      PosWorkspace(
        table: table,
        categories: const [],
        dishes: const [],
        paymentMethods: const [],
        currentOrder: const PosOrder(
          id: 9,
          orderNo: 'ORD40',
          tableNumber: '40',
          diners: 2,
          total: 15,
          createdAt: null,
          lines: [
            PosOrderLine(
              id: 91,
              name: '油边王',
              quantity: 1,
              total: 15,
              specification: '不辣',
              refunded: false,
            ),
          ],
        ),
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: TableOrderPage(
          table: table,
          repository: repository,
          approvalRepository: _FakeAccessApprovalRepository(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('order-gift-91')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('pos-notice-dialog')), findsOneWidget);
    expect(find.text('确认赠送'), findsNWidgets(2));
    await tester.tap(find.byKey(const Key('pos-notice-primary')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('cashier-approval-dialog')), findsOneWidget);
    await tester.enterText(
      find.byKey(const Key('approval-account')),
      'manager',
    );
    await tester.enterText(
      find.byKey(const Key('approval-credential')),
      'pass123',
    );
    await tester.tap(find.byKey(const Key('approval-submit')));
    await tester.pumpAndSettle();

    expect(repository.giftedOrderNo, 'ORD40');
    expect(repository.giftedDetailId, 91);
    expect(repository.giftDishApprovalToken, 'fake-approval-token');
  });

  testWidgets('refund silently refreshes order and table amounts', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1920, 1080);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final table = DiningTable.fromJson({'number': '40', 'status': 1});
    final repository = _FakePosRepository(
      PosWorkspace(
        table: table,
        categories: const [],
        dishes: const [],
        paymentMethods: const [],
        currentOrder: const PosOrder(
          id: 9,
          orderNo: 'ORD40',
          tableNumber: '40',
          diners: 2,
          total: 30,
          createdAt: null,
          lines: [
            PosOrderLine(
              id: 91,
              name: '油边王',
              quantity: 2,
              total: 30,
              unit: '串',
              specification: '不辣',
              refunded: false,
            ),
          ],
        ),
      ),
      refreshedWorkspace: PosWorkspace(
        table: DiningTable.fromJson({
          'number': '40',
          'status': 1,
          'sett_amount': 0,
        }),
        categories: const [],
        dishes: const [],
        paymentMethods: const [],
        currentOrder: const PosOrder(
          id: 9,
          orderNo: 'ORD40',
          tableNumber: '40',
          diners: 2,
          total: 15,
          createdAt: null,
          lines: [
            PosOrderLine(
              id: 91,
              name: '油边王',
              quantity: 1,
              total: 15,
              unit: '串',
              specification: '不辣',
              refunded: false,
            ),
          ],
        ),
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: TableOrderPage(
          table: table,
          repository: repository,
          approvalRepository: _FakeAccessApprovalRepository(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(repository.workspaceLoadCount, 1);
    await tester.tap(find.byKey(const Key('order-refund-91')));
    await tester.pumpAndSettle();
    final dishCenter = tester.getCenter(
      find.byKey(const Key('refund-dish-name')),
    );
    final quantityCenter = tester.getCenter(
      find.byKey(const Key('refund-quantity-input')),
    );
    final amountCenter = tester.getCenter(
      find.byKey(const Key('refund-amount')),
    );
    expect(dishCenter.dx, lessThan(quantityCenter.dx));
    expect(quantityCenter.dx, lessThan(amountCenter.dx));
    expect(find.text('退菜数量'), findsNothing);
    expect(
      tester.widget<Text>(find.byKey(const Key('refund-amount'))).data,
      '¥15.00',
    );
    await tester.tap(find.byKey(const Key('refund-quantity-increment')));
    await tester.pump();
    expect(
      tester
          .widget<TextField>(find.byKey(const Key('refund-quantity-input')))
          .controller
          ?.text,
      '2',
    );
    expect(
      tester.widget<Text>(find.byKey(const Key('refund-amount'))).data,
      '¥30.00',
    );
    await tester.enterText(find.byKey(const Key('refund-quantity-input')), '3');
    await tester.pump();
    expect(
      tester
          .widget<FilledButton>(find.byKey(const Key('refund-dish-confirm')))
          .onPressed,
      isNull,
    );
    await tester.enterText(find.byKey(const Key('refund-quantity-input')), '2');
    await tester.pump();
    expect(
      tester.widget<Text>(find.byKey(const Key('refund-amount'))).data,
      '¥30.00',
    );
    expect(
      tester
          .widget<FilledButton>(find.byKey(const Key('refund-dish-confirm')))
          .onPressed,
      isNotNull,
    );
    await tester.enterText(find.byKey(const Key('refund-quantity-input')), '1');
    await tester.pump();
    // 新版退菜弹窗：默认回退库存，选择缺货估清并自动带出原因
    await tester.tap(find.byKey(const Key('refund-action-OUT_OF_STOCK')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('refund-dish-confirm')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('cashier-approval-dialog')), findsOneWidget);
    await tester.enterText(
      find.byKey(const Key('approval-account')),
      'manager',
    );
    await tester.enterText(
      find.byKey(const Key('approval-credential')),
      'pass123',
    );
    await tester.tap(find.byKey(const Key('approval-submit')));
    await tester.pumpAndSettle();

    expect(repository.refundedOrderNo, 'ORD40');
    expect(repository.refundedDetailId, 91);
    expect(repository.refundedQuantity, 1);
    expect(repository.refundedStockAction, PosRefundStockAction.outOfStock);
    expect(repository.refundedReason, '食材缺货');
    expect(repository.refundDishApprovalToken, 'fake-approval-token');
    expect(repository.workspaceLoadCount, 2);
    expect(find.text('退菜'), findsOneWidget);
    expect(find.text('￥15.00'), findsOneWidget);
    expect(
      tester
          .widget<TextButton>(find.byKey(const Key('order-refund-91')))
          .onPressed,
      isNotNull,
    );
  });

  testWidgets('refund quantity dialog scrolls on compact cashier screens', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1024, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      const MaterialApp(
        home: RefundDishDialog(
          line: PosOrderLine(
            id: 92,
            name: '凉菜',
            quantity: 3,
            total: 36,
            unit: '份',
            specification: '',
            refunded: false,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      tester.widget<Text>(find.byKey(const Key('refund-amount'))).data,
      '¥12.00',
    );
    expect(find.byType(SingleChildScrollView), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('closing an unconfirmed QR releases its payment session', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1920, 1080);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final table = DiningTable.fromJson({
      'id': 120,
      'number': '40',
      'status': 1,
      'sett_amount': 60,
    });
    final repository = _FakePaymentPosRepository(
      PosWorkspace(
        table: table,
        categories: const [],
        dishes: const [],
        paymentMethods: const [
          PosPaymentMethod(
            id: 1,
            code: 'wechat',
            name: '微信支付',
            sortOrder: 1,
            enabled: true,
          ),
          PosPaymentMethod(
            id: 2,
            code: 'alipay',
            name: '支付宝',
            sortOrder: 2,
            enabled: true,
          ),
        ],
        currentOrder: const PosOrder(
          id: 9,
          orderNo: 'ORD40',
          tableNumber: '40',
          diners: 2,
          total: 60,
          createdAt: null,
          lines: [],
        ),
      ),
    );
    final pendingStore = _FakePendingExternalCheckoutStore();

    await tester.pumpWidget(
      MaterialApp(
        home: TableOrderPage(
          table: table,
          repository: repository,
          approvalRepository: _FakeAccessApprovalRepository(),
          pendingExternalCheckoutStore: pendingStore,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('pay-card-wechat')));
    await tester.pumpAndSettle();

    expect(repository.qrRequestCount, 1);
    expect(pendingStore.values['ORD40']?.offlineChannel, 'wechat');
    await tester.tap(find.byKey(const Key('checkout-dialog-close')));
    await tester.pumpAndSettle();

    expect(repository.cancelledQrChannels, ['wechat']);
    expect(pendingStore.values['ORD40'], isNull);

    await tester.tap(find.byKey(const Key('pay-card-alipay')));
    await tester.pumpAndSettle();
    expect(repository.qrChannel, 'alipay');
  });

  testWidgets('leaving an order releases its restored pending QR session', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1920, 1080);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final table = DiningTable.fromJson({
      'id': 120,
      'number': '40',
      'status': 1,
      'sett_amount': 60,
    });
    final repository = _FakePaymentPosRepository(
      PosWorkspace(
        table: table,
        categories: const [],
        dishes: const [],
        paymentMethods: const [],
        currentOrder: const PosOrder(
          id: 9,
          orderNo: 'ORD40',
          tableNumber: '40',
          diners: 2,
          total: 60,
          createdAt: null,
          lines: [],
        ),
      ),
    );
    final pendingStore = _FakePendingExternalCheckoutStore()
      ..values['ORD40'] = const PendingExternalCheckout(
        orderNo: 'ORD40',
        offlineChannel: 'wechat',
        collectionSessionId: 'restored-session',
      );

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: FilledButton(
              key: const Key('open-table-order-page'),
              onPressed: () => Navigator.of(context).push<void>(
                MaterialPageRoute<void>(
                  builder: (_) => TableOrderPage(
                    table: table,
                    repository: repository,
                    approvalRepository: _FakeAccessApprovalRepository(),
                    pendingExternalCheckoutStore: pendingStore,
                  ),
                ),
              ),
              child: const Text('进入订单'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.byKey(const Key('open-table-order-page')));
    await tester.pumpAndSettle();
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    expect(repository.cancelledQrChannels, ['wechat']);
    expect(pendingStore.values['ORD40'], isNull);
    expect(find.byKey(const Key('open-table-order-page')), findsOneWidget);
  });

  testWidgets('switching channels releases the previous pending QR session', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1920, 1080);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final table = DiningTable.fromJson({
      'id': 120,
      'number': '40',
      'status': 1,
      'sett_amount': 60,
    });
    final repository = _FakePaymentPosRepository(
      PosWorkspace(
        table: table,
        categories: const [],
        dishes: const [],
        paymentMethods: const [
          PosPaymentMethod(
            id: 1,
            code: 'wechat',
            name: '微信支付',
            sortOrder: 1,
            enabled: true,
          ),
          PosPaymentMethod(
            id: 2,
            code: 'alipay',
            name: '支付宝',
            sortOrder: 2,
            enabled: true,
          ),
        ],
        currentOrder: const PosOrder(
          id: 9,
          orderNo: 'ORD40',
          tableNumber: '40',
          diners: 2,
          total: 60,
          createdAt: null,
          lines: [],
        ),
      ),
    );
    final pendingStore = _FakePendingExternalCheckoutStore()
      ..values['ORD40'] = const PendingExternalCheckout(
        orderNo: 'ORD40',
        offlineChannel: 'wechat',
        collectionSessionId: 'restored-session',
      );

    await tester.pumpWidget(
      MaterialApp(
        home: TableOrderPage(
          table: table,
          repository: repository,
          approvalRepository: _FakeAccessApprovalRepository(),
          pendingExternalCheckoutStore: pendingStore,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('pay-card-alipay')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('pos-notice-primary')));
    await tester.pumpAndSettle();

    expect(repository.cancelledQrChannels, ['wechat']);
    expect(find.text('支付宝收款'), findsOneWidget);
  });

  testWidgets('cash checkout submits tender, calculated change and channel', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1920, 1080);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final table = DiningTable.fromJson({
      'id': 120,
      'number': '40',
      'status': 1,
      'sett_amount': 60,
    });
    final repository = _FakePosRepository(
      PosWorkspace(
        table: table,
        categories: const [],
        dishes: const [],
        paymentMethods: const [
          PosPaymentMethod(
            id: 3,
            code: 'cash',
            name: '现金收款',
            sortOrder: 1,
            enabled: true,
          ),
          PosPaymentMethod(
            id: 9,
            code: 'store_credit',
            name: '门店挂账',
            sortOrder: 2,
            enabled: true,
          ),
        ],
        currentOrder: const PosOrder(
          id: 9,
          orderNo: 'ORD40',
          tableNumber: '40',
          diners: 2,
          total: 60,
          createdAt: null,
          lines: [],
        ),
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: TableOrderPage(
          table: table,
          repository: repository,
          approvalRepository: _FakeAccessApprovalRepository(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('现金收款'), findsOneWidget);
    expect(find.text('门店挂账'), findsOneWidget);
    expect(find.text('微信支付'), findsNothing);

    await tester.tap(find.text('现金收款'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('cash-tender-field')), '100');
    await tester.pump();

    expect(find.text('找零金额'), findsOneWidget);
    expect(find.text('¥40.00'), findsOneWidget);
    await tester.tap(find.byKey(const Key('cash-change-channel-wechat')));
    await tester.tap(find.byKey(const Key('cash-checkout-confirm')));
    await tester.pumpAndSettle();

    expect(repository.checkoutPaymentMethod, 'cash');
    expect(repository.cashSettlement?.cashReceivedMinor, 6000);
    expect(repository.cashSettlement?.cashTenderMinor, 10000);
    expect(repository.cashSettlement?.changeAmountMinor, 4000);
    expect(repository.cashSettlement?.changeChannel, PosChangeChannel.wechat);
  });

  testWidgets('cashier response alias still uses the QR collection flow', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1920, 1080);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final table = DiningTable.fromJson({
      'id': 120,
      'number': '40',
      'status': 1,
      'sett_amount': 60,
    });
    final repository = _FakePaymentPosRepository(
      PosWorkspace(
        table: table,
        categories: const [],
        dishes: const [],
        paymentMethods: const [
          PosPaymentMethod(
            id: 1,
            code: 'cashierWechatEnabled',
            name: '微信支付',
            sortOrder: 1,
            enabled: true,
          ),
        ],
        currentOrder: const PosOrder(
          id: 9,
          orderNo: 'ORD40',
          tableNumber: '40',
          diners: 2,
          total: 60,
          createdAt: null,
          lines: [],
        ),
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: TableOrderPage(
          table: table,
          repository: repository,
          approvalRepository: _FakeAccessApprovalRepository(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('pay-card-cashierWechatEnabled')));
    await tester.pumpAndSettle();

    expect(repository.qrChannel, 'wechat');
    expect(
      find.byKey(const Key('offline-collection-checkout-dialog')),
      findsOneWidget,
    );
    expect(find.text('微信收款'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const Key('offline-collection-checkout-dialog')),
        matching: find.byKey(const Key('offline-collection-amount')),
      ),
      findsOneWidget,
    );
    expect(find.byKey(const Key('offline-collection-qr')), findsOneWidget);
    // Offline collection has a 30s confirm guard; button becomes clickable after the countdown.
    await tester.pump(const Duration(seconds: 31));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('offline-collection-confirm')));
    await tester.pumpAndSettle();

    expect(repository.checkoutPaymentMethod, 'offline_wechat_qr');
    expect(repository.qrConfirmationCount, 1);
    expect(repository.checkoutCollectionSessionId, isNotEmpty);
  });

  testWidgets(
    'confirmed QR payment survives page recreation without collecting again',
    (tester) async {
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final table = DiningTable.fromJson({
        'id': 120,
        'number': '40',
        'status': 1,
        'sett_amount': 60,
      });
      final repository = _FakePaymentPosRepository(
        PosWorkspace(
          table: table,
          categories: const [],
          dishes: const [],
          paymentMethods: const [
            PosPaymentMethod(
              id: 1,
              code: 'wechat',
              name: '微信支付',
              sortOrder: 1,
              enabled: true,
            ),
          ],
          currentOrder: const PosOrder(
            id: 9,
            orderNo: 'ORD40',
            tableNumber: '40',
            diners: 2,
            total: 60,
            createdAt: null,
            lines: [],
          ),
        ),
      )..failCheckoutOnce = true;
      final pendingStore = _FakePendingExternalCheckoutStore();

      await tester.pumpWidget(
        MaterialApp(
          home: TableOrderPage(
            table: table,
            repository: repository,
            approvalRepository: _FakeAccessApprovalRepository(),
            pendingExternalCheckoutStore: pendingStore,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('pay-card-wechat')));
      await tester.pumpAndSettle();
      // Offline collection has a 30s confirm guard; button becomes clickable after the countdown.
      await tester.pump(const Duration(seconds: 31));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('offline-collection-confirm')));
      await tester.pumpAndSettle();

      expect(find.textContaining('请勿重复收款'), findsOneWidget);
      await tester.tap(find.byKey(const Key('pos-notice-primary')));
      await tester.pumpAndSettle();

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      await tester.pumpWidget(
        MaterialApp(
          home: TableOrderPage(
            table: table,
            repository: repository,
            approvalRepository: _FakeAccessApprovalRepository(),
            pendingExternalCheckoutStore: pendingStore,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('pay-card-wechat')));
      await tester.pumpAndSettle();

      expect(find.text('待入账支付'), findsOneWidget);
      expect(repository.qrRequestCount, 1);
      await tester.tap(find.byKey(const Key('pos-notice-primary')));
      await tester.pumpAndSettle();
      expect(repository.checkoutAttempts, 2);
      expect(repository.qrRequestCount, 1);
      expect(repository.qrConfirmationCount, 1);
    },
  );

  testWidgets('confirmed QR payment cannot switch to another payment channel', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1920, 1080);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final table = DiningTable.fromJson({
      'id': 120,
      'number': '40',
      'status': 1,
      'sett_amount': 60,
    });
    final repository = _FakePaymentPosRepository(
      PosWorkspace(
        table: table,
        categories: const [],
        dishes: const [],
        paymentMethods: const [
          PosPaymentMethod(
            id: 1,
            code: 'wechat',
            name: '微信支付',
            sortOrder: 1,
            enabled: true,
          ),
          PosPaymentMethod(
            id: 2,
            code: 'alipay',
            name: '支付宝',
            sortOrder: 2,
            enabled: true,
          ),
        ],
        currentOrder: const PosOrder(
          id: 9,
          orderNo: 'ORD40',
          tableNumber: '40',
          diners: 2,
          total: 60,
          createdAt: null,
          lines: [],
        ),
      ),
    );
    final pendingStore = _FakePendingExternalCheckoutStore()
      ..values['ORD40'] = const PendingExternalCheckout(
        orderNo: 'ORD40',
        offlineChannel: 'wechat',
        confirmedChannels: {'wechat'},
        readyForSubmission: true,
        collectionSessionId: 'old-wechat-session',
      );

    await tester.pumpWidget(
      MaterialApp(
        home: TableOrderPage(
          table: table,
          repository: repository,
          approvalRepository: _FakeAccessApprovalRepository(),
          pendingExternalCheckoutStore: pendingStore,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('pay-card-alipay')));
    await tester.pumpAndSettle();

    expect(find.text('已确认到账拦截'), findsOneWidget);
    expect(find.textContaining('不能直接切换支付渠道'), findsOneWidget);
    expect(repository.qrChannel, isNull);
    expect(pendingStore.values['ORD40']?.offlineChannel, 'wechat');
    expect(
      pendingStore.values['ORD40']?.collectionSessionId,
      'old-wechat-session',
    );
  });

  testWidgets('checkout receipt can skip the returned print result', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1920, 1080);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final table = DiningTable.fromJson({
      'id': 120,
      'number': '40',
      'status': 1,
      'sett_amount': 60,
    });
    final repository = _FakePrintPosRepository(
      PosWorkspace(
        table: table,
        categories: const [],
        dishes: const [],
        paymentMethods: const [],
        currentOrder: const PosOrder(
          id: 9,
          orderNo: 'ORD40',
          tableNumber: '40',
          diners: 2,
          total: 60,
          createdAt: null,
          lines: [],
        ),
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: TableOrderPage(
          table: table,
          repository: repository,
          approvalRepository: _FakeAccessApprovalRepository(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('occupied-print-button')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('receipt-print-dialog')), findsOneWidget);
    expect(find.text('前台小票'), findsOneWidget);
    expect(find.text('厨房小票'), findsOneWidget);
    expect(find.text('预结单'), findsOneWidget);
    expect(find.text('结账单'), findsOneWidget);
    await tester.tap(find.byKey(const Key('receipt-print-confirm')));
    await tester.pumpAndSettle();
    expect(find.text('是否预览打印结果？'), findsOneWidget);
    expect(repository.printedOrderId, isNull);
    await tester.tap(
      find.byKey(const Key('checkout-print-preview-choice-skip')),
    );
    await tester.pumpAndSettle();

    expect(repository.printedOrderId, 9);
    expect(find.text('40号桌'), findsNothing);
    expect(find.text('打印成功'), findsNothing);
    expect(find.text('结账单已发送至门店打印机。'), findsNothing);
  });

  testWidgets('occupied table can reprint the kitchen ticket', (tester) async {
    tester.view.physicalSize = const Size(1920, 1080);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final table = DiningTable.fromJson({
      'id': 120,
      'number': '40',
      'status': 1,
      'sett_amount': 60,
    });
    final repository = _FakePrintPosRepository(
      PosWorkspace(
        table: table,
        categories: const [],
        dishes: const [],
        paymentMethods: const [],
        currentOrder: const PosOrder(
          id: 9,
          orderNo: 'ORD40',
          tableNumber: '40',
          diners: 2,
          total: 60,
          createdAt: null,
          lines: [],
        ),
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: TableOrderPage(
          table: table,
          repository: repository,
          approvalRepository: _FakeAccessApprovalRepository(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('occupied-print-button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('receipt-print-option-kitchen')));
    await tester.tap(find.byKey(const Key('receipt-print-confirm')));
    await tester.pumpAndSettle();

    expect(repository.kitchenPrintedOrderNo, 'ORD40');
    expect(find.byKey(const Key('pos-notice-dialog')), findsNothing);
    expect(
      tester
          .widget<FilledButton>(
            find.descendant(
              of: find.byKey(const Key('occupied-print-button')),
              matching: find.byType(FilledButton),
            ),
          )
          .onPressed,
      isNotNull,
    );
  });

  testWidgets(
    'unsettled table can print pre-checkout but not checkout receipt',
    (tester) async {
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final table = DiningTable.fromJson({
        'id': 120,
        'number': '40',
        'status': 1,
        'sett_amount': 60,
      });
      final repository = _FakePrintPosRepository(
        PosWorkspace(
          table: table,
          categories: const [],
          dishes: const [],
          paymentMethods: const [],
          currentOrder: const PosOrder(
            id: 9,
            orderNo: 'ORD40',
            tableNumber: '40',
            diners: 2,
            total: 60,
            createdAt: null,
            lines: [],
          ),
        ),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: TableOrderPage(
            table: table,
            repository: repository,
            approvalRepository: _FakeAccessApprovalRepository(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('occupied-print-button')));
      await tester.pumpAndSettle();

      final checkout = tester.widget<InkWell>(
        find.byKey(const Key('receipt-print-option-checkout')),
      );
      expect(checkout.onTap, isNull);
      await tester.tap(
        find.byKey(const Key('receipt-print-option-preCheckout')),
      );
      await tester.tap(find.byKey(const Key('receipt-print-confirm')));
      await tester.pumpAndSettle();

      expect(repository.printedReceiptTypes, [PosReceiptPrintType.preCheckout]);
    },
  );

  testWidgets(
    'checkout receipt parses and shows returned print content when preview is chosen',
    (tester) async {
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final table = DiningTable.fromJson({
        'id': 120,
        'number': '40',
        'status': 1,
        'sett_amount': 60,
      });
      final repository = _FakePrintPosRepository(
        PosWorkspace(
          table: table,
          categories: const [],
          dishes: const [],
          paymentMethods: const [],
          currentOrder: const PosOrder(
            id: 9,
            orderNo: 'ORD40',
            tableNumber: '40',
            diners: 2,
            total: 60,
            createdAt: null,
            lines: [],
          ),
        ),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: TableOrderPage(
            table: table,
            repository: repository,
            approvalRepository: _FakeAccessApprovalRepository(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('occupied-print-button')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('receipt-print-confirm')));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const Key('checkout-print-preview-choice-show')),
      );
      await tester.pumpAndSettle();

      expect(repository.printedOrderId, 9);
      expect(find.text('本次打印结果'), findsOneWidget);
      expect(find.text('40号桌'), findsOneWidget);
      expect(find.text('<CB>40号桌</CB>'), findsNothing);
    },
  );

  test(
    'raw print content parser preserves receipt text and formatting directives',
    () {
      final lines = parsePosRawPrintContent(
        '<CB>40号桌</CB><BR><B>合计：¥60</B><BR>----<BR><CUT>',
      );

      expect(lines, hasLength(4));
      expect(lines[0].text, '40号桌');
      expect(lines[0].alignment, PosRawPrintAlignment.center);
      expect(lines[0].fontSize, 28);
      expect(lines[0].bold, isTrue);
      expect(lines[1].text, '合计：¥60');
      expect(lines[1].fontSize, 28);
      expect(lines[1].bold, isFalse);
      expect(lines[2].isDivider, isTrue);
      expect(lines[3].isCut, isTrue);
    },
  );

  testWidgets('stored-value debit shows balance and submits the bound openid', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1920, 1080);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final table = DiningTable.fromJson({
      'id': 120,
      'number': '40',
      'status': 1,
      'sett_amount': 80,
    });
    final repository = _FakePaymentPosRepository(
      PosWorkspace(
        table: table,
        categories: const [],
        dishes: const [],
        paymentMethods: const [
          PosPaymentMethod(
            id: 4,
            code: 'balance',
            name: '储值划扣',
            sortOrder: 4,
            enabled: true,
          ),
        ],
        currentOrder: const PosOrder(
          id: 9,
          orderNo: 'ORD40',
          tableNumber: '40',
          diners: 2,
          total: 80,
          grossAmount: 80,
          discountAmount: 0,
          memberPhone: '13800000000',
          memberOpenid: 'member-openid',
          memberBalance: 100,
          createdAt: null,
          lines: [],
        ),
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: TableOrderPage(
          table: table,
          repository: repository,
          approvalRepository: _FakeAccessApprovalRepository(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('pay-card-balance')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('balance-checkout-dialog')), findsOneWidget);
    expect(find.text('当前余额'), findsOneWidget);
    expect(find.text('¥100.00'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const Key('balance-checkout-dialog')),
        matching: find.text('¥80.00'),
      ),
      findsOneWidget,
    );
    expect(find.text('¥20.00'), findsOneWidget);
    await tester.tap(find.byKey(const Key('balance-checkout-confirm')));
    await tester.pump();

    expect(repository.balanceOrderNo, 'ORD40');
    expect(repository.balanceOpenid, 'member-openid');
  });

  testWidgets('combined checkout submits an exact cash and balance split', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1920, 1080);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final table = DiningTable.fromJson({
      'id': 120,
      'number': '40',
      'status': 1,
      'sett_amount': 100,
    });
    final repository = _FakePaymentPosRepository(
      PosWorkspace(
        table: table,
        categories: const [],
        dishes: const [],
        paymentMethods: const [
          PosPaymentMethod(
            id: 1,
            code: 'cash',
            name: '现金',
            sortOrder: 1,
            enabled: true,
          ),
          PosPaymentMethod(
            id: 2,
            code: 'online_balance',
            name: '余额',
            sortOrder: 2,
            enabled: true,
          ),
          PosPaymentMethod(
            id: 3,
            code: 'online_combined',
            name: '组合支付',
            sortOrder: 3,
            enabled: true,
          ),
        ],
        currentOrder: const PosOrder(
          id: 9,
          orderNo: 'ORD40',
          tableNumber: '40',
          diners: 2,
          total: 100,
          memberPhone: '13800000000',
          memberOpenid: 'member-openid',
          memberBalance: 30,
          createdAt: null,
          lines: [],
        ),
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: TableOrderPage(
          table: table,
          repository: repository,
          approvalRepository: _FakeAccessApprovalRepository(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('pay-card-online_combined')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('combined-cash-field')), '70');
    await tester.enterText(
      find.byKey(const Key('combined-balance-field')),
      '30',
    );
    await tester.pump();
    await tester.tap(find.byKey(const Key('combined-checkout-confirm')));
    await tester.pumpAndSettle();

    expect(repository.combinedOrderNo, 'ORD40');
    expect(repository.combinedSettlement?.cashMinor, 7000);
    expect(repository.combinedSettlement?.balanceMinor, 3000);
    expect(repository.combinedSettlement?.positiveChannelCount, 2);
  });

  testWidgets('payment configuration failure disables every checkout entry', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1920, 1080);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final table = DiningTable.fromJson({
      'id': 120,
      'number': '40',
      'status': 1,
      'sett_amount': 80,
    });
    final repository = _FakePaymentPosRepository(
      PosWorkspace(
        table: table,
        categories: const [],
        dishes: const [],
        paymentMethods: const [],
        paymentConfigurationAvailable: false,
        currentOrder: const PosOrder(
          id: 9,
          orderNo: 'ORD40',
          tableNumber: '40',
          diners: 2,
          total: 80,
          memberPhone: '13800000000',
          memberOpenid: 'member-openid',
          memberBalance: 100,
          createdAt: null,
          lines: [],
        ),
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: TableOrderPage(
          table: table,
          repository: repository,
          approvalRepository: _FakeAccessApprovalRepository(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('payment-configuration-error')),
      findsOneWidget,
    );
    expect(find.byKey(const Key('pay-card-balance')), findsNothing);
    expect(find.byKey(const Key('pay-card-wechat')), findsNothing);
    expect(repository.balanceOrderNo, isNull);
  });

  testWidgets('empty table asks for confirmation before opening', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1920, 1080);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final table = DiningTable.fromJson({'number': '40', 'status': 0});
    final repository = _FakePosRepository(
      PosWorkspace(
        table: table,
        categories: const [],
        dishes: const [],
        paymentMethods: const [],
        currentOrder: null,
      ),
    );
    var completed = false;

    await tester.pumpWidget(
      MaterialApp(
        home: TableOrderPage(
          table: table,
          repository: repository,
          approvalRepository: _FakeAccessApprovalRepository(),
          onCompleted: () => completed = true,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('是否开台'), findsOneWidget);
    expect(repository.openedTableNumber, isNull);
    await tester.tap(find.byKey(const Key('pos-notice-primary')));
    await tester.pumpAndSettle();

    expect(repository.openedTableNumber, '40');
    expect(find.text('开台成功'), findsNothing);
    expect(repository.submittedLines, isEmpty);
    expect(completed, isFalse);
    expect(find.text('40号'), findsOneWidget);
  });

  testWidgets('category rail filters dishes whose API category field is cid', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1920, 1080);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final table = DiningTable.fromJson({'number': '40', 'status': 1});
    final repository = _FakePosRepository(
      PosWorkspace(
        table: table,
        categories: const [
          PosCategory(id: 3, name: '招牌菜品', code: 'signature', sorting: 1),
          PosCategory(id: 4, name: '饮料', code: 'drinks', sorting: 2),
        ],
        dishes: [
          PosDish.fromJson({
            'id': 7,
            'name': '油边王',
            'cid': 'signature',
            'unitprice': 15,
            'stock': 12,
          }),
          PosDish.fromJson({
            'id': 8,
            'name': '可乐',
            'cid': 'drinks',
            'unitprice': 5,
            'stock': 12,
          }),
        ],
        currentOrder: null,
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: TableOrderPage(
          table: table,
          repository: repository,
          approvalRepository: _FakeAccessApprovalRepository(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('pos-category-3')));
    await tester.pump();

    expect(find.text('油边王'), findsOneWidget);
    expect(find.text('可乐'), findsNothing);
  });

  testWidgets('cart quantity cannot exceed the finite stock', (tester) async {
    tester.view.physicalSize = const Size(1920, 1080);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final table = DiningTable.fromJson({'number': '40', 'status': 1});
    final repository = _FakePosRepository(
      PosWorkspace(
        table: table,
        categories: const [],
        dishes: const [
          PosDish(
            id: 7,
            name: '油边王',
            categoryId: 3,
            price: 15,
            unit: '份',
            stock: 1,
            onSale: true,
            soldOut: false,
            specGroups: [],
          ),
        ],
        currentOrder: null,
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: TableOrderPage(
          table: table,
          repository: repository,
          approvalRepository: _FakeAccessApprovalRepository(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('油边王'));
    await tester.pump();
    await tester.tap(find.byKey(const Key('cart-quantity-increase-1')));
    await tester.pumpAndSettle();

    expect(find.text('库存不足'), findsOneWidget);
    expect(find.textContaining('库存仅剩 1 份'), findsOneWidget);
    expect(find.text('1'), findsWidgets);
  });

  testWidgets('table overview opens the selected dine-in table', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1920, 1080);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    DiningTable? selected;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TableOverviewPage(
            repository: _FakeTableRepository(),
            onTableSelected: (table) async => selected = table,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('40号桌'));
    await tester.pumpAndSettle();

    expect(find.text('是否开台'), findsOneWidget);
    expect(selected, isNull);
    await tester.tap(find.byKey(const Key('pos-notice-primary')));
    await tester.pumpAndSettle();

    expect(selected?.number, '40');
  });

  testWidgets(
    'table grid matches the canvas while cards keep status fills and no empty icon',
    (tester) async {
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: TableOverviewPage(
              repository: _FakeTableRepository(
                overview: TableOverview(
                  tables: [
                    DiningTable.fromJson({'number': '39', 'status': 0}),
                    DiningTable.fromJson({
                      'number': '40',
                      'status': 1,
                      'amount': 88.8,
                    }),
                    DiningTable.fromJson({
                      'number': '41',
                      'status': 2,
                      'amount': 32,
                    }),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final gridBackground = tester.widget<Container>(
        find.byKey(const Key('table-grid-panel-background')),
      );
      expect(gridBackground.color, CashierTokens.light.canvas);

      for (final (tableNumber, expectedFill) in [
        ('39', CashierTokens.light.tableStateIdleBar),
        ('40', CashierTokens.light.tableStateDiningBar),
        ('41', CashierTokens.light.tableStateCleaningBar),
      ]) {
        final cardMaterial = tester.widget<Material>(
          find
              .ancestor(
                of: find.byKey(Key('table-card-$tableNumber')),
                matching: find.byType(Material),
              )
              .first,
        );
        final cardShape = cardMaterial.shape! as RoundedRectangleBorder;

        expect(cardMaterial.color, expectedFill);
        expect(cardMaterial.elevation, greaterThan(0));
        expect(cardShape.side, isNot(BorderSide.none));
        expect(cardShape.side.width, lessThanOrEqualTo(1.5));
      }

      expect(
        find.descendant(
          of: find.byKey(const Key('table-card-39')),
          matching: find.byIcon(Icons.table_restaurant_outlined),
        ),
        findsNothing,
      );

      final tableLabel = tester.widget<Text>(find.text('40号桌'));
      final amountLabel = tester.widget<Text>(find.text('¥88.80'));

      expect(
        amountLabel.style!.fontSize!,
        greaterThan(tableLabel.style!.fontSize! * 2),
      );
      expect(
        find.ancestor(
          of: find.text('¥88.80'),
          matching: find.byType(FittedBox),
        ),
        findsOneWidget,
      );
    },
  );

  testWidgets('cancelling an empty table confirmation keeps overview open', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1920, 1080);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    DiningTable? selected;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TableOverviewPage(
            repository: _FakeTableRepository(),
            onTableSelected: (table) async => selected = table,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('40号桌'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('pos-notice-secondary')));
    await tester.pumpAndSettle();

    expect(selected, isNull);
    expect(find.text('40号桌'), findsOneWidget);
    expect(find.text('是否开台'), findsNothing);
  });

  testWidgets('opening a table does not leave a gray dialog barrier over POS', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1920, 1080);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final emptyTable = DiningTable.fromJson({'number': '40', 'status': 0});
    final openedTable = DiningTable.fromJson({'number': '40', 'status': 1});
    var selectionStartedBehindBarrier = false;
    var baselineBarrierCount = 0;
    final posRepository = _FakePosRepository(
      PosWorkspace(
        table: openedTable,
        categories: const [
          PosCategory(id: 3, name: '招牌菜品', code: 'signature', sorting: 1),
        ],
        dishes: const [
          PosDish(
            id: 7,
            name: '油边王',
            categoryId: 3,
            price: 15,
            unit: '份',
            stock: 12,
            onSale: true,
            soldOut: false,
            specGroups: [],
          ),
        ],
        paymentMethods: const [],
        currentOrder: null,
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (pageContext) => Scaffold(
            body: TableOverviewPage(
              repository: _FakeTableRepository(table: emptyTable),
              onTableSelected: (table) async {
                selectionStartedBehindBarrier =
                    find.byType(ModalBarrier).evaluate().length >
                    baselineBarrierCount;
                await posRepository.openTable(table.number);
                await Navigator.of(pageContext).push<void>(
                  PageRouteBuilder<void>(
                    transitionDuration: Duration.zero,
                    reverseTransitionDuration: Duration.zero,
                    pageBuilder: (_, _, _) => TableOrderPage(
                      table: table,
                      initiallyOpened: true,
                      repository: posRepository,
                      approvalRepository: _FakeAccessApprovalRepository(),
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    baselineBarrierCount = find.byType(ModalBarrier).evaluate().length;

    await tester.tap(find.text('40号桌'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('pos-notice-primary')));
    await tester.pump(const Duration(milliseconds: 1));

    await tester.pumpAndSettle();
    expect(selectionStartedBehindBarrier, isFalse);
    expect(find.byKey(const Key('pos-notice-dialog')), findsNothing);
    expect(find.text('油边王'), findsOneWidget);
    expect(posRepository.openedTableNumber, '40');
  });

  testWidgets('zero amount settled table asks to clear before opening', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1920, 1080);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    DiningTable? opened;
    DiningTable? cleared;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TableOverviewPage(
            repository: _FakeTableRepository(
              table: DiningTable.fromJson({
                'id': 120,
                'number': '40',
                'status': 2,
                'amount': 0,
              }),
            ),
            onTableSelected: (table) async => opened = table,
            onClearTable: (table) async => cleared = table,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('40号桌'));
    await tester.pumpAndSettle();

    expect(find.text('清台提示'), findsOneWidget);
    expect(find.text('40号桌已结账且金额为 ¥0.00，是否清台？'), findsOneWidget);
    expect(opened, isNull);
    await tester.tap(find.byKey(const Key('pos-notice-primary')));
    await tester.pumpAndSettle();

    expect(cleared?.number, '40');
    expect(opened, isNull);
  });

  testWidgets('clear-all button clears all occupied tables and skips errors', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1920, 1080);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final cleared = <String>[];

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TableOverviewPage(
            repository: _FakeTableRepository(
              overview: TableOverview(
                tables: [
                  DiningTable.fromJson({
                    'id': 1,
                    'number': '40',
                    'status': 2,
                    'amount': 0,
                  }),
                  DiningTable.fromJson({
                    'id': 2,
                    'number': '41',
                    'status': 1,
                    'amount': 55,
                  }),
                  DiningTable.fromJson({
                    'id': 3,
                    'number': '42',
                    'status': 2,
                    'amount': 100,
                  }),
                  DiningTable.fromJson({
                    'id': 4,
                    'number': '43',
                    'status': 0,
                    'amount': 0,
                  }),
                ],
              ),
            ),
            onClearTable: (table) async {
              if (table.number == '41') {
                throw Exception('41号桌清台失败');
              }
              cleared.add(table.number);
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // 只要开台的桌台（40、41、42）均计入；空台 43 不计入
    await tester.tap(find.byKey(const Key('clear-all-settled-tables')));
    await tester.pumpAndSettle();

    expect(find.text('一键清台确认'), findsOneWidget);
    expect(find.textContaining('40号桌、41号桌、42号桌'), findsOneWidget);
    await tester.tap(find.byKey(const Key('pos-notice-primary')));
    await tester.pumpAndSettle();

    // 41 报错被跳过，40 与 42 正常清台
    expect(cleared, ['40', '42']);
    expect(find.text('部分清台失败'), findsOneWidget);
    expect(find.textContaining('成功 2 台，失败 1 台：41号桌'), findsOneWidget);
    await tester.tap(find.byKey(const Key('pos-notice-primary')));
    await tester.pumpAndSettle();
  });

  testWidgets('switching order-type tabs triggers a silent refresh', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1920, 1080);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final repository = _FakeTableRepository();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: TableOverviewPage(repository: repository)),
      ),
    );
    await tester.pumpAndSettle();
    expect(repository.loadCount, 1);

    await tester.tap(find.text('外卖'));
    await tester.pumpAndSettle();
    expect(repository.loadCount, 2);
  });

  testWidgets('table polling runs only while the page is visible', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1920, 1080);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final repository = _FakeTableRepository();

    Widget wrap({required bool visible}) => MaterialApp(
      home: TickerMode(
        enabled: visible,
        child: Scaffold(body: TableOverviewPage(repository: repository)),
      ),
    );

    await tester.pumpWidget(wrap(visible: true));
    await tester.pumpAndSettle();
    expect(repository.loadCount, 1);

    // 可见时：5s 轮询正常触发
    await tester.pump(const Duration(seconds: 6));
    expect(repository.loadCount, 2);

    // 隐藏时：轮询停止，不再请求
    await tester.pumpWidget(wrap(visible: false));
    await tester.pump(const Duration(seconds: 12));
    expect(repository.loadCount, 2);

    // 恢复可见：立即补偿刷新一次并恢复轮询
    await tester.pumpWidget(wrap(visible: true));
    await tester.pump();
    expect(repository.loadCount, 3);
    await tester.pump(const Duration(seconds: 6));
    expect(repository.loadCount, 4);
  });

  testWidgets('table overview refreshes immediately on a realtime event', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1920, 1080);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final repository = _FakeTableRepository();
    final events = StreamController<void>.broadcast();
    addTearDown(events.close);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TableOverviewPage(
            repository: repository,
            refreshEvents: events.stream,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(repository.loadCount, 1);

    events.add(null);
    await tester.pumpAndSettle();

    expect(repository.loadCount, 2);
  });

  testWidgets('pickup tab exposes the front desk packing order entry', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1920, 1080);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    var opened = false;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TableOverviewPage(
            repository: _FakeTableRepository(),
            onPickupOrder: () async => opened = true,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('自提'));
    await tester.pump();

    expect(find.byKey(const Key('pickup-order-entry')), findsOneWidget);
    await tester.tap(find.byKey(const Key('pickup-order-entry')));
    await tester.pump();
    expect(opened, isTrue);
  });

  testWidgets('takeout shows pending checkout and opens order detail', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1920, 1080);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final pending = FulfillmentOrder.fromJson({
      'id': 77,
      'order_no': 'ORD77',
      'pickup_code': 'B2077',
      'transac_status': 'unsettled',
      'receiving_status': 'rec_order',
      'kds_order_status': 20,
      'sett_amount': 98,
    }, type: FulfillmentType.takeout);

    FulfillmentOrderDetail? checkoutDetail;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TableOverviewPage(
            repository: _FakeTableRepository(
              overview: TableOverview(
                tables: const [],
                takeoutOrders: [pending],
              ),
            ),
            onFulfillmentCheckout: (detail) async {
              checkoutDetail = detail;
              return true;
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('外卖'));
    await tester.pump();

    expect(find.text('待结账（1）'), findsOneWidget);
    final fulfillmentCard = tester.widget<Material>(
      find.byKey(const Key('fulfillment-order-77')),
    );
    expect(
      (fulfillmentCard.shape as RoundedRectangleBorder).side.color,
      const Color(0xff0284c7),
    );
    await tester.tap(find.byKey(const Key('fulfillment-order-77')));
    await tester.pumpAndSettle();

    expect(find.text('外卖订单明细'), findsOneWidget);
    expect(find.text('ORD77'), findsOneWidget);
    expect(find.text('待结账'), findsWidgets);
    expect(find.text('接单状态'), findsOneWidget);
    expect(find.text('已接单'), findsOneWidget);
    expect(find.text('制作状态'), findsOneWidget);
    expect(find.text('制作中'), findsOneWidget);
    expect(find.text('开始配送'), findsNothing);
    expect(
      find.byKey(const Key('fulfillment-checkout-button')),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const Key('fulfillment-checkout-button')));
    await tester.pumpAndSettle();
    expect(checkoutDetail?.order.orderNo, 'ORD77');
    expect(find.text('外卖订单明细'), findsNothing);
  });

  testWidgets('pickup ordering proceeds to checkout with packaging fee', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1920, 1080);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    const table = DiningTable(
      number: '打包',
      status: TableStatus.empty,
      people: 1,
    );
    final repository = _FakePosRepository(
      const PosWorkspace(
        table: table,
        categories: [],
        dishes: [
          PosDish(
            id: 7,
            name: '油边王',
            categoryId: 3,
            price: 15,
            unit: '份',
            stock: 12,
            onSale: true,
            soldOut: false,
            specGroups: [],
          ),
        ],
        paymentMethods: [
          PosPaymentMethod(
            id: 1,
            code: 'wechat',
            name: '微信支付',
            sortOrder: 1,
            enabled: true,
          ),
        ],
        currentOrder: null,
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: TableOrderPage(
          table: table,
          repository: repository,
          approvalRepository: _FakeAccessApprovalRepository(),
          pickupOrder: true,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('打包点餐'), findsOneWidget);
    expect(find.text('是否开台'), findsNothing);
    await tester.tap(find.text('油边王'));
    await tester.pump();
    expect(find.text('含打包费 ¥1.00'), findsOneWidget);
    expect(find.text('¥16.00'), findsOneWidget);
    await tester.tap(find.text('确认打包'));
    await tester.pumpAndSettle();

    expect(repository.pickupLines, hasLength(1));
    expect(repository.pickupRequestIds.single, isNotEmpty);
    expect(find.text('订单编号：ORD-PICKUP'), findsOneWidget);
    expect(find.text('自提打包'), findsOneWidget);
    expect(find.text('(前台打包-无绑定)'), findsOneWidget);
    expect(find.text('未结账'), findsOneWidget);
    expect(find.text('微信支付'), findsOneWidget);
  });

  testWidgets('fulfillment checkout reuses the occupied table payment module', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1920, 1080);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    const table = DiningTable(
      number: '外卖 B2077',
      status: TableStatus.pending,
      people: 1,
    );
    const workspace = PosWorkspace(
      table: table,
      categories: [],
      dishes: [],
      currentOrder: PosOrder(
        id: 77,
        orderNo: 'ORD77',
        tableNumber: '',
        diners: 1,
        total: 98,
        createdAt: null,
        lines: [],
      ),
      paymentMethods: [
        PosPaymentMethod(
          id: 1,
          code: 'cash',
          name: '现金',
          sortOrder: 0,
          enabled: true,
        ),
      ],
    );
    final repository = _FakePosRepository(workspace);

    await tester.pumpWidget(
      MaterialApp(
        home: TableOrderPage(
          table: table,
          repository: repository,
          approvalRepository: _FakeAccessApprovalRepository(),
          initialWorkspace: workspace,
          checkoutOnly: true,
          fulfillmentTitle: '外卖 B2077',
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('occupied-payment-bar')), findsOneWidget);
    expect(find.text('外卖 B2077'), findsOneWidget);
    await tester.tap(find.byKey(const Key('pay-card-cash')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('cash-checkout-dialog')), findsOneWidget);
    expect(
      find.byKey(const Key('fulfillment-cash-tender-field')),
      findsNothing,
    );
  });

  testWidgets(
    'all tab displays tables, takeout orders, and pickup orders on one canvas',
    (tester) async {
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final emptyTable = DiningTable.fromJson({
        'id': 1,
        'number': '01',
        'status': 0,
      });
      final occupiedTable = DiningTable.fromJson({
        'id': 2,
        'number': '02',
        'status': 1,
        'amount': 88,
      });
      final takeoutOrder = FulfillmentOrder.fromJson({
        'id': 101,
        'order_no': 'TK101',
        'pickup_code': 'B101',
        'transac_status': 'paid',
        'receiving_status': 'rec_order',
      }, type: FulfillmentType.takeout);
      final pickupOrder = FulfillmentOrder.fromJson({
        'id': 201,
        'order_no': 'PK201',
        'pickup_code': 'A201',
        'transac_status': 'paid',
        'receiving_status': 'rec_order',
      }, type: FulfillmentType.pickup);

      final overview = TableOverview(
        tables: [emptyTable, occupiedTable],
        takeoutOrders: [takeoutOrder],
        pickupOrders: [pickupOrder],
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: TableOverviewPage(
              repository: _FakeTableRepository(overview: overview),
              onTableSelected: (_) async {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // 检查标签页名称与存在
      expect(find.text('全部'), findsOneWidget);
      expect(find.text('全部桌位'), findsNothing);
      expect(find.text('堂食'), findsOneWidget);
      expect(find.text('外卖'), findsOneWidget);
      expect(find.text('自提'), findsOneWidget);

      // 在“全部”标签下，堂食桌位、外卖单、自提单全部显示
      expect(find.text('01号桌'), findsOneWidget);
      expect(find.text('02号桌'), findsOneWidget);
      expect(find.text('B101'), findsOneWidget);
      expect(find.text('A201'), findsOneWidget);
      expect(find.text('外卖取餐码'), findsOneWidget);
      expect(find.text('自提取餐码'), findsOneWidget);

      // 验证空桌统一带有“空闲”高对比状态徽章
      expect(find.text('01号桌'), findsOneWidget);
      expect(find.text('空闲'), findsOneWidget);

      // 验证待结账开台桌带有“就餐中”状态徽章
      expect(find.text('02号桌'), findsOneWidget);
      expect(find.text('就餐中'), findsOneWidget);

      // 切换到“堂食”标签：只显示桌位
      await tester.tap(find.text('堂食'));
      await tester.pumpAndSettle();
      expect(find.text('01号桌'), findsOneWidget);
      expect(find.text('02号桌'), findsOneWidget);
      expect(find.text('B101'), findsNothing);
      expect(find.text('A201'), findsNothing);

      // 切换回“全部”标签并测试状态筛选
      await tester.tap(find.text('全部'));
      await tester.pumpAndSettle();
      expect(find.text('01号桌'), findsOneWidget);
      expect(find.text('B101'), findsOneWidget);

      // 点击底部图例“空桌”筛选
      await tester.tap(find.text('空桌（1）'));
      await tester.pumpAndSettle();
      expect(find.text('01号桌'), findsOneWidget);
      expect(find.text('02号桌'), findsNothing);
      expect(find.text('B101'), findsNothing);
      expect(find.text('A201'), findsNothing);

      // 点击底部图例“待结账”筛选
      await tester.tap(find.text('待结账（1）'));
      await tester.pumpAndSettle();
      expect(find.text('02号桌'), findsOneWidget);
      expect(find.text('01号桌'), findsNothing);

      // 点击“全部状态”恢复
      await tester.tap(find.text('全部状态（4）'));
      await tester.pumpAndSettle();
      expect(find.text('01号桌'), findsOneWidget);
      expect(find.text('02号桌'), findsOneWidget);
      expect(find.text('B101'), findsOneWidget);
      expect(find.text('A201'), findsOneWidget);
    },
  );

  testWidgets(
    'table create button and delete table icon visibility depend on canManageTable',
    (tester) async {
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final emptyTable = DiningTable.fromJson({
        'id': 10,
        'number': '10',
        'status': 0,
      });
      final repository = _FakeTableRepository(table: emptyTable);

      // 1. canManageTable: false -> create button and delete icon are hidden
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: TableOverviewPage(
              repository: repository,
              showSidebar: false,
              canManageTable: false,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('create-table-button')), findsNothing);
      expect(find.byKey(const Key('delete-table-10')), findsNothing);
      await tester.longPress(find.text('10号桌'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('delete-table-10')), findsNothing);

      // 2. canManageTable: true -> create button is visible, card itself has no delete icon, long press shows delete action
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: TableOverviewPage(
              repository: repository,
              showSidebar: false,
              canManageTable: true,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('create-table-button')), findsOneWidget);
      expect(find.byKey(const Key('delete-table-10')), findsNothing);
      await tester.longPress(find.text('10号桌'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('delete-table-10')), findsOneWidget);
    },
  );

  testWidgets(
    'create table dialog validates inputs and calls repository.createTable',
    (tester) async {
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final emptyTable = DiningTable.fromJson({
        'id': 10,
        'number': '10',
        'status': 0,
      });
      final repository = _FakeTableRepository(table: emptyTable);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: TableOverviewPage(
              repository: repository,
              showSidebar: false,
              canManageTable: true,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('create-table-button')));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('create-table-confirm-button')),
        findsOneWidget,
      );
      await tester.enterText(
        find.byKey(const Key('create-table-number-input')),
        '20',
      );
      await tester.enterText(
        find.byKey(const Key('create-table-people-input')),
        '6',
      );
      await tester.tap(find.byKey(const Key('create-table-confirm-button')));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('create-table-confirm-button')),
        findsNothing,
      );
      expect(repository.createdTables, contains('20'));
    },
  );

  testWidgets(
    'delete table button on empty table shows confirmation and calls repository.deleteTable',
    (tester) async {
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final emptyTable = DiningTable.fromJson({
        'id': 10,
        'number': '10',
        'status': 0,
      });
      final repository = _FakeTableRepository(table: emptyTable);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: TableOverviewPage(
              repository: repository,
              showSidebar: false,
              canManageTable: true,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Long press empty table to pop up management action dialog
      await tester.longPress(find.text('10号桌'));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('delete-table-10')), findsOneWidget);
      await tester.tap(find.byKey(const Key('delete-table-10')));
      await tester.pumpAndSettle();

      // Verify admin auth dialog appears
      expect(find.text('管理员权限验证'), findsOneWidget);
      expect(
        find.byKey(const Key('delete-table-auth-password')),
        findsOneWidget,
      );

      // Test wrong password
      await tester.enterText(
        find.byKey(const Key('delete-table-auth-password')),
        'wrong-password',
      );
      await tester.tap(find.byKey(const Key('delete-table-auth-confirm')));
      await tester.pumpAndSettle();

      expect(find.text('密码错误，请重新输入'), findsOneWidget);
      expect(repository.deletedTableIds, isEmpty);

      // Enter correct password and confirm
      await tester.enterText(
        find.byKey(const Key('delete-table-auth-password')),
        '123456',
      );
      await tester.tap(find.byKey(const Key('delete-table-auth-confirm')));
      await tester.pumpAndSettle();

      expect(find.text('管理员权限验证'), findsNothing);
      expect(repository.deletedTableIds, contains(10));
    },
  );

  testWidgets(
    'settled table with non-zero amount displays 已结账 rather than 待结账',
    (tester) async {
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final settledTable = DiningTable.fromJson({
        'id': 15,
        'number': '15',
        'status': 2, // settled
        'amount': 158.0,
        'people': 4,
      });
      final repository = _FakeTableRepository(table: settledTable);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: TableOverviewPage(
              repository: repository,
              showSidebar: false,
              canManageTable: true,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Table banner and body badge should show 已结账, never 待结账
      expect(find.text('待结账'), findsNothing);
      expect(find.text('已结账'), findsWidgets);
    },
  );

  testWidgets(
    'long press table opens QR dialog with edit button, allowing table modification',
    (tester) async {
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final table = DiningTable.fromJson({
        'id': 18,
        'number': '18',
        'status': 0,
        'people': 4,
        'area_code': 'hall',
        'area_name': '大厅散座',
      });
      final repository = _FakeTableRepository(table: table);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: TableOverviewPage(
              repository: repository,
              showSidebar: false,
              canManageTable: true,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Long press table card to open QR and management dialog
      await tester.longPress(find.text('18号桌'));
      await tester.pumpAndSettle();

      // Verify edit button is present
      final editBtn = find.byKey(const Key('edit-table-18'));
      expect(editBtn, findsOneWidget);
      expect(find.byKey(const Key('table-wxacode-image-18')), findsOneWidget);
      expect(find.text('桌号：18 · 微信扫码点餐'), findsOneWidget);

      // Tap edit button to open edit dialog
      await tester.tap(editBtn);
      await tester.pumpAndSettle();

      // Check edit dialog inputs
      expect(find.text('编辑桌台 · 18号桌'), findsOneWidget);
      expect(find.byKey(const Key('edit-table-number-input')), findsOneWidget);
      expect(find.byKey(const Key('edit-table-area-select')), findsOneWidget);
      expect(find.byKey(const Key('edit-table-people-input')), findsOneWidget);

      // Modify values
      await tester.enterText(
        find.byKey(const Key('edit-table-number-input')),
        '18B',
      );
      await tester.enterText(
        find.byKey(const Key('edit-table-people-input')),
        '8',
      );

      // Tap save
      await tester.tap(find.byKey(const Key('edit-table-confirm-button')));
      await tester.pumpAndSettle();

      expect(repository.updatedTables, isNotEmpty);
      expect(repository.updatedTables.first.id, 18);
      expect(repository.updatedTables.first.number, '18B');
      expect(repository.updatedTables.first.peopleCount, 8);
    },
  );

  testWidgets(
    'direct ordering without table defaults to empty table number and prompts dining mode for pickup',
    (tester) async {
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final dish = PosDish(
        id: 1,
        name: '招牌红烧肉',
        price: 38.0,
        unit: '份',
        categoryId: 1,
        stock: 10,
        onSale: true,
        soldOut: false,
        specGroups: const [],
      );
      final workspace = PosWorkspace(
        table: const DiningTable(number: '', status: TableStatus.empty, people: 0),
        categories: const [PosCategory(id: 1, name: '热菜', code: 'hot', sorting: 1)],
        dishes: [dish],
        paymentMethods: const [],
        currentOrder: null,
      );
      final repository = _FakePosRepository(workspace);

      await tester.pumpWidget(
        MaterialApp(
          home: TableOrderPage(
            table: const DiningTable(number: '', status: TableStatus.empty, people: 0),
            initiallyOpened: true,
            repository: repository,
            approvalRepository: _FakeAccessApprovalRepository(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Title should show 待选桌台 · 点单小票
      expect(find.text('待选桌台'), findsOneWidget);
      expect(find.text('· 点单小票'), findsOneWidget);

      // Add dish to cart
      await tester.tap(find.text('招牌红烧肉'));
      await tester.pumpAndSettle();

      // Tap 立即下单
      await tester.tap(find.text('立即下单'));
      await tester.pumpAndSettle();

      // Dining mode dialog should be shown
      expect(find.byKey(const Key('dining-mode-dialog')), findsOneWidget);
      expect(find.text('选择就餐方式'), findsOneWidget);
      expect(find.byKey(const Key('dining-mode-takeout')), findsOneWidget);
      expect(find.byKey(const Key('dining-mode-dinein')), findsOneWidget);

      // Tap 打包自提
      await tester.tap(find.byKey(const Key('dining-mode-takeout')));
      await tester.pumpAndSettle();

      // Verify pickup order was submitted
      expect(repository.pickupLines, isNotEmpty);
      expect(repository.pickupLines.first.dish.name, '招牌红烧肉');

      // Now on detail page, tap back button
      expect(find.byKey(const Key('occupied-left-back-button')), findsOneWidget);
      await tester.tap(find.byKey(const Key('occupied-left-back-button')));
      await tester.pumpAndSettle();

      // Should return to the initial ordering page (not tables overview)
      expect(find.text('待选桌台'), findsOneWidget);
      expect(find.text('· 点单小票'), findsOneWidget);
      expect(find.text('招牌红烧肉'), findsOneWidget);
    },
  );

  testWidgets(
    'direct ordering selecting dine-in displays table grid and opens selected table',
    (tester) async {
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final dish = PosDish(
        id: 2,
        name: '清蒸鲈鱼',
        price: 58.0,
        unit: '条',
        categoryId: 1,
        stock: 10,
        onSale: true,
        soldOut: false,
        specGroups: const [],
      );
      final workspace = PosWorkspace(
        table: const DiningTable(number: '', status: TableStatus.empty, people: 0),
        categories: const [PosCategory(id: 1, name: '热菜', code: 'hot', sorting: 1)],
        dishes: [dish],
        paymentMethods: const [],
        currentOrder: null,
      );
      final repository = _FakePosRepository(workspace);

      final t1 = DiningTable.fromJson({
        'id': 101,
        'number': 'A01',
        'status': 0,
        'people': 4,
        'area_name': '大厅',
      });
      final t2 = DiningTable.fromJson({
        'id': 102,
        'number': 'A02',
        'status': 1,
        'people': 6,
        'area_name': '大厅',
        'amount': 120,
      });
      final tableRepo = _FakeTableRepository(
        overview: TableOverview(tables: [t1, t2]),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: TableOrderPage(
            table: const DiningTable(number: '', status: TableStatus.empty, people: 0),
            initiallyOpened: true,
            repository: repository,
            tableRepository: tableRepo,
            approvalRepository: _FakeAccessApprovalRepository(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Add dish to cart
      await tester.tap(find.text('清蒸鲈鱼'));
      await tester.pumpAndSettle();

      // Tap 立即下单
      await tester.tap(find.text('立即下单'));
      await tester.pumpAndSettle();

      // Tap 堂食就餐
      await tester.tap(find.byKey(const Key('dining-mode-dinein')));
      await tester.pumpAndSettle();

      // Table selection grid dialog should appear
      expect(find.byKey(const Key('table-selection-grid-dialog')), findsOneWidget);
      expect(find.text('选择堂食桌台'), findsOneWidget);
      expect(find.byKey(const Key('table-grid-item-A01')), findsOneWidget);
      expect(find.byKey(const Key('table-grid-item-A02')), findsOneWidget);

      // Tap empty table A01
      await tester.tap(find.byKey(const Key('table-grid-item-A01')));
      await tester.pumpAndSettle();

      // Verify A01 was opened and submitted
      expect(repository.openedTableNumber, 'A01');
      expect(repository.submittedLines, isNotEmpty);
      expect(repository.submittedLines.first.dish.name, '清蒸鲈鱼');
    },
  );

  testWidgets(
    'merged table displays merged badges, filters dishes, and routes checkout to checkoutTable',
    (tester) async {
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final table = DiningTable.fromJson({'number': '10', 'status': 1});
      final masterOrder = PosOrder(
        id: 101,
        orderNo: 'ORD-MASTER',
        tableNumber: '10',
        total: 50.0,
        diners: 2,
        createdAt: null,
        lines: const [
          PosOrderLine(
            id: 1,
            name: '烤羊肉串',
            quantity: 10,
            total: 50.0,
            unit: '串',
            specification: '',
            refunded: false,
          ),
        ],
      );
      final slaveOrder = PosOrder(
        id: 102,
        orderNo: 'ORD-SLAVE',
        masterOrderNo: 'ORD-MASTER',
        tableNumber: '10',
        total: 30.0,
        diners: 1,
        createdAt: null,
        lines: const [
          PosOrderLine(
            id: 2,
            name: '烤鸡翅',
            quantity: 2,
            total: 30.0,
            unit: '对',
            specification: '',
            refunded: false,
          ),
        ],
      );

      final workspace = PosWorkspace(
        table: table,
        categories: const [],
        dishes: const [],
        paymentMethods: const [
          PosPaymentMethod(
            id: 1,
            name: '微信支付',
            code: 'wechat',
            sortOrder: 1,
            enabled: true,
          ),
          PosPaymentMethod(
            id: 2,
            name: '现金',
            code: 'cash',
            sortOrder: 2,
            enabled: true,
          ),
        ],
        currentOrder: masterOrder,
        tableOrders: [masterOrder, slaveOrder],
      );

      expect(workspace.isMergedTable, isTrue);
      expect(slaveOrder.isMergedSlaveOrder, isTrue);
      expect(masterOrder.isMergedSlaveOrder, isFalse);
      expect(workspace.tableTotalPayable, 80.0);

      final repository = _FakePosRepository(workspace);

      await tester.pumpWidget(
        MaterialApp(
          home: TableOrderPage(
            table: table,
            repository: repository,
            approvalRepository: _FakeAccessApprovalRepository(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Check merged table badge
      expect(
        find.byKey(const Key('occupied-merged-table-badge')),
        findsOneWidget,
      );
      expect(find.text('并台 (2单)'), findsOneWidget);

      // Check filter chips
      expect(find.text('全部菜品'), findsOneWidget);
      expect(find.text('主单 MASTER'), findsOneWidget);
      expect(find.text('从单 -SLAVE'), findsOneWidget);

      // Both dishes visible in '全部菜品' view
      expect(find.text('烤羊肉串'), findsOneWidget);
      expect(find.text('烤鸡翅'), findsOneWidget);

      // Filter to slave order
      await tester.tap(find.text('从单 -SLAVE'));
      await tester.pumpAndSettle();
      expect(find.text('烤鸡翅'), findsOneWidget);
      expect(find.text('烤羊肉串'), findsNothing);

      // Return to all dishes
      await tester.tap(find.text('全部菜品'));
      await tester.pumpAndSettle();
      expect(find.text('烤羊肉串'), findsOneWidget);
      expect(find.text('烤鸡翅'), findsOneWidget);

      // Checkout via wechat (StandardCheckoutDialog)
      await tester.tap(find.text('微信支付'));
      await tester.pumpAndSettle();

      // Confirm dialog should state merged table checkout
      expect(find.text('确认结账'), findsOneWidget);
      expect(find.textContaining('并台整桌结账'), findsOneWidget);

      await tester.tap(find.text('确认收款'));
      await tester.pumpAndSettle();

      // Verify checkoutTable was called instead of checkout
      expect(repository.checkedOutTableNumber, '10');
      expect(repository.tableCheckoutPaymentMethod, 'wechat');
      expect(repository.checkoutPaymentMethod, isNull);
    },
  );

  testWidgets(
    'merged table cash checkout routes to checkoutTable with cash received',
    (tester) async {
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final table = DiningTable.fromJson({'number': '20', 'status': 1});
      final masterOrder = PosOrder(
        id: 201,
        orderNo: 'ORD-201',
        tableNumber: '20',
        total: 60.0,
        diners: 2,
        createdAt: null,
        lines: const [
          PosOrderLine(
            id: 1,
            name: '特色牛肉',
            quantity: 2,
            total: 60.0,
            unit: '份',
            specification: '',
            refunded: false,
          ),
        ],
      );
      final slaveOrder = PosOrder(
        id: 202,
        orderNo: 'ORD-202',
        masterOrderNo: 'ORD-201',
        tableNumber: '20',
        total: 40.0,
        diners: 2,
        createdAt: null,
        lines: const [
          PosOrderLine(
            id: 2,
            name: '大拌菜',
            quantity: 2,
            total: 40.0,
            unit: '份',
            specification: '',
            refunded: false,
          ),
        ],
      );

      final workspace = PosWorkspace(
        table: table,
        categories: const [],
        dishes: const [],
        paymentMethods: const [
          PosPaymentMethod(
            id: 1,
            name: '现金',
            code: 'cash',
            sortOrder: 1,
            enabled: true,
          ),
        ],
        currentOrder: masterOrder,
        tableOrders: [masterOrder, slaveOrder],
      );

      final repository = _FakePosRepository(workspace);

      await tester.pumpWidget(
        MaterialApp(
          home: TableOrderPage(
            table: table,
            repository: repository,
            approvalRepository: _FakeAccessApprovalRepository(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('现金'));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('cash-checkout-dialog')), findsOneWidget);
      // Total payable is 100.0 (60 + 40)
      expect(
        find.descendant(
          of: find.byKey(const Key('cash-checkout-dialog')),
          matching: find.text('¥100.00'),
        ),
        findsOneWidget,
      );

      await tester.enterText(find.byKey(const Key('cash-tender-field')), '100');
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('cash-checkout-confirm')));
      await tester.pumpAndSettle();

      expect(repository.checkedOutTableNumber, '20');
      expect(repository.tableCheckoutPaymentMethod, 'cash');
      expect(repository.tableCheckoutCashAmount, 100.0);
    },
  );

  testWidgets(
    'merged table refunding dish belonging to slave order routes to slave orderNo and updates local state',
    (tester) async {
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      final table = DiningTable.fromJson({'number': '20', 'status': 1});
      final masterOrder = PosOrder(
        id: 201,
        orderNo: 'ORD-201',
        tableNumber: '20',
        total: 60.0,
        grossAmount: 60.0,
        diners: 2,
        createdAt: null,
        lines: const [
          PosOrderLine(
            id: 101,
            name: '烤牛肉',
            quantity: 1,
            total: 60.0,
            unit: '份',
            specification: '',
            refunded: false,
            orderNo: 'ORD-201',
          ),
        ],
      );
      final slaveOrder = PosOrder(
        id: 202,
        orderNo: 'ORD-202',
        masterOrderNo: 'ORD-201',
        tableNumber: '20',
        total: 40.0,
        grossAmount: 40.0,
        diners: 2,
        createdAt: null,
        lines: const [
          PosOrderLine(
            id: 102,
            name: '大拌菜',
            quantity: 2,
            total: 40.0,
            unit: '份',
            specification: '',
            refunded: false,
            orderNo: 'ORD-202',
          ),
        ],
      );

      final workspace = PosWorkspace(
        table: table,
        categories: const [],
        dishes: const [],
        paymentMethods: const [],
        currentOrder: masterOrder,
        tableOrders: [masterOrder, slaveOrder],
      );

      final repository = _FakePosRepository(workspace);

      await tester.pumpWidget(
        MaterialApp(
          home: TableOrderPage(
            table: table,
            repository: repository,
            approvalRepository: _FakeAccessApprovalRepository(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // 退菜：大拌菜（子单2明细，ID 102）
      await tester.tap(find.byKey(const Key('order-refund-102')));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(const Key('refund-quantity-input')),
        '1',
      );
      await tester.pump();
      await tester.tap(find.byKey(const Key('refund-dish-confirm')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('cashier-approval-dialog')), findsOneWidget);
      await tester.enterText(
        find.byKey(const Key('approval-account')),
        'manager',
      );
      await tester.enterText(
        find.byKey(const Key('approval-credential')),
        'pass123',
      );
      await tester.tap(find.byKey(const Key('approval-submit')));
      await tester.pumpAndSettle();

      // 断言退菜订单号为子单 ORD-202，而非主单 ORD-201
      expect(repository.refundedOrderNo, 'ORD-202');
      expect(repository.refundedDetailId, 102);
      expect(repository.refundedQuantity, 1);
      expect(repository.refundDishApprovalToken, 'fake-approval-token');
    },
  );

  testWidgets(
    'merged table gifting dish belonging to slave order routes to slave orderNo',
    (tester) async {
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      final table = DiningTable.fromJson({'number': '20', 'status': 1});
      final masterOrder = PosOrder(
        id: 201,
        orderNo: 'ORD-201',
        tableNumber: '20',
        total: 60.0,
        grossAmount: 60.0,
        diners: 2,
        createdAt: null,
        lines: const [
          PosOrderLine(
            id: 101,
            name: '烤牛肉',
            quantity: 1,
            total: 60.0,
            unit: '份',
            specification: '',
            refunded: false,
            orderNo: 'ORD-201',
          ),
        ],
      );
      final slaveOrder = PosOrder(
        id: 202,
        orderNo: 'ORD-202',
        masterOrderNo: 'ORD-201',
        tableNumber: '20',
        total: 40.0,
        grossAmount: 40.0,
        diners: 2,
        createdAt: null,
        lines: const [
          PosOrderLine(
            id: 102,
            name: '大拌菜',
            quantity: 2,
            total: 40.0,
            unit: '份',
            specification: '',
            refunded: false,
            orderNo: 'ORD-202',
          ),
        ],
      );

      final workspace = PosWorkspace(
        table: table,
        categories: const [],
        dishes: const [],
        paymentMethods: const [],
        currentOrder: masterOrder,
        tableOrders: [masterOrder, slaveOrder],
      );

      final repository = _FakePosRepository(workspace);

      await tester.pumpWidget(
        MaterialApp(
          home: TableOrderPage(
            table: table,
            repository: repository,
            approvalRepository: _FakeAccessApprovalRepository(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // 赠菜：大拌菜（子单2明细，ID 102）
      await tester.tap(find.byKey(const Key('order-gift-102')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('pos-notice-dialog')), findsOneWidget);
      await tester.tap(find.byKey(const Key('pos-notice-primary')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('cashier-approval-dialog')), findsOneWidget);
      await tester.enterText(
        find.byKey(const Key('approval-account')),
        'manager',
      );
      await tester.enterText(
        find.byKey(const Key('approval-credential')),
        'pass123',
      );
      await tester.tap(find.byKey(const Key('approval-submit')));
      await tester.pumpAndSettle();

      // 断言赠菜订单号为子单 ORD-202，而非主单 ORD-201
      expect(repository.giftedOrderNo, 'ORD-202');
      expect(repository.giftedDetailId, 102);
      expect(repository.giftDishApprovalToken, 'fake-approval-token');
    },
  );

  testWidgets(
    'merged table transferring active slave order routes to slave orderNo',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1920, 1080));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final table = DiningTable.fromJson({'number': '20', 'status': 1});
      final masterOrder = PosOrder(
        id: 201,
        orderNo: 'ORD-201',
        tableNumber: '20',
        total: 60.0,
        grossAmount: 60.0,
        diners: 2,
        createdAt: null,
        lines: const [
          PosOrderLine(
            id: 101,
            name: '烤牛肉',
            quantity: 1,
            total: 60.0,
            unit: '份',
            specification: '',
            refunded: false,
            orderNo: 'ORD-201',
          ),
        ],
      );
      final slaveOrder = PosOrder(
        id: 202,
        orderNo: 'ORD-202',
        masterOrderNo: 'ORD-201',
        tableNumber: '20',
        total: 40.0,
        grossAmount: 40.0,
        diners: 2,
        createdAt: null,
        lines: const [
          PosOrderLine(
            id: 102,
            name: '大拌菜',
            quantity: 2,
            total: 40.0,
            unit: '份',
            specification: '',
            refunded: false,
            orderNo: 'ORD-202',
          ),
        ],
      );

      final workspace = PosWorkspace(
        table: table,
        categories: const [],
        dishes: const [],
        paymentMethods: const [],
        currentOrder: masterOrder,
        tableOrders: [masterOrder, slaveOrder],
      );

      final repository = _FakePosRepository(workspace);

      await tester.pumpWidget(
        MaterialApp(
          home: TableOrderPage(
            table: table,
            repository: repository,
            approvalRepository: _FakeAccessApprovalRepository(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // 切换到从单过滤卡片
      await tester.tap(find.text('从单 ORD-202'));
      await tester.pumpAndSettle();

      // 换台
      await tester.tap(find.text('换台'));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), '30');
      await tester.pump();
      await tester.tap(find.text('确认'));
      await tester.pumpAndSettle();

      // 断言换台订单号为从单 ORD-202
      expect(repository.transferredOrderNo, 'ORD-202');
      expect(repository.transferredTargetTableNumber, '30');
    },
  );

  testWidgets(
    'merged table discounting active slave order routes to slave orderNo',
    (tester) async {
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.binding.setSurfaceSize(const Size(1920, 1080));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final table = DiningTable.fromJson({'number': '20', 'status': 1});
      final masterOrder = PosOrder(
        id: 201,
        orderNo: 'ORD-201',
        tableNumber: '20',
        total: 60.0,
        grossAmount: 60.0,
        diners: 2,
        createdAt: null,
        lines: const [
          PosOrderLine(
            id: 101,
            name: '烤牛肉',
            quantity: 1,
            total: 60.0,
            unit: '份',
            specification: '',
            refunded: false,
            orderNo: 'ORD-201',
          ),
        ],
      );
      final slaveOrder = PosOrder(
        id: 202,
        orderNo: 'ORD-202',
        masterOrderNo: 'ORD-201',
        tableNumber: '20',
        total: 40.0,
        grossAmount: 40.0,
        diners: 2,
        createdAt: null,
        lines: const [
          PosOrderLine(
            id: 102,
            name: '大拌菜',
            quantity: 2,
            total: 40.0,
            unit: '份',
            specification: '',
            refunded: false,
            orderNo: 'ORD-202',
          ),
        ],
      );

      final workspace = PosWorkspace(
        table: table,
        categories: const [],
        dishes: const [],
        paymentMethods: const [],
        currentOrder: masterOrder,
        tableOrders: [masterOrder, slaveOrder],
      );

      final repository = _FakePosRepository(workspace);

      await tester.pumpWidget(
        MaterialApp(
          home: TableOrderPage(
            table: table,
            repository: repository,
            approvalRepository: _FakeAccessApprovalRepository(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // 切换到从单过滤卡片
      await tester.tap(find.text('从单 ORD-202'));
      await tester.pumpAndSettle();

      // 整单折扣
      await tester.tap(find.byKey(const Key('occupied-discount-button')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('discount-dialog')), findsOneWidget);
      await tester.tap(find.byKey(const Key('discount-preset-9')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('discount-confirm')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('cashier-approval-dialog')), findsOneWidget);
      await tester.enterText(
        find.byKey(const Key('approval-account')),
        'manager',
      );
      await tester.enterText(
        find.byKey(const Key('approval-credential')),
        'pass123',
      );
      await tester.tap(find.byKey(const Key('approval-submit')));
      await tester.pumpAndSettle();

      // 断言折扣针对子单 ORD-202
      expect(repository.discountedOrderNo, 'ORD-202');
      expect(repository.discountedAmount, 4.0); // 40 * 0.1
      expect(repository.discountApprovalToken, 'fake-approval-token');
    },
  );

  testWidgets(
    'merged table adding dishes to active slave order routes to slave orderNo',
    (tester) async {
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.binding.setSurfaceSize(const Size(1920, 1080));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final table = DiningTable.fromJson({'number': '20', 'status': 1});
      final masterOrder = PosOrder(
        id: 201,
        orderNo: 'ORD-201',
        tableNumber: '20',
        total: 60.0,
        grossAmount: 60.0,
        diners: 2,
        createdAt: null,
        lines: const [
          PosOrderLine(
            id: 101,
            name: '烤牛肉',
            quantity: 1,
            total: 60.0,
            unit: '份',
            specification: '',
            refunded: false,
            orderNo: 'ORD-201',
          ),
        ],
      );
      final slaveOrder = PosOrder(
        id: 202,
        orderNo: 'ORD-202',
        masterOrderNo: 'ORD-201',
        tableNumber: '20',
        total: 40.0,
        grossAmount: 40.0,
        diners: 2,
        createdAt: null,
        lines: const [
          PosOrderLine(
            id: 102,
            name: '大拌菜',
            quantity: 2,
            total: 40.0,
            unit: '份',
            specification: '',
            refunded: false,
            orderNo: 'ORD-202',
          ),
        ],
      );

      const categories = [
        PosCategory(id: 1, name: '热销', code: 'hot', sorting: 1),
      ];
      const dishes = [
        PosDish(
          id: 1,
          name: '烤串',
          categoryId: 1,
          price: 10,
          unit: '串',
          stock: 50,
          onSale: true,
          soldOut: false,
          specGroups: [],
        ),
      ];

      final workspace = PosWorkspace(
        table: table,
        categories: categories,
        dishes: dishes,
        paymentMethods: const [],
        currentOrder: masterOrder,
        tableOrders: [masterOrder, slaveOrder],
      );

      final repository = _FakePosRepository(workspace);

      await tester.pumpWidget(
        MaterialApp(
          home: TableOrderPage(
            table: table,
            repository: repository,
            approvalRepository: _FakeAccessApprovalRepository(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // 切换到从单过滤卡片
      await tester.tap(find.text('从单 ORD-202'));
      await tester.pumpAndSettle();

      // 加菜
      await tester.tap(find.text('加菜'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('烤串'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('确认加菜'));
      await tester.pumpAndSettle();

      // 断言加菜针对子单 ORD-202
      expect(repository.addedDishesOrderNo, 'ORD-202');
    },
  );

  group('POS sensitive operation secondary authorization', () {
    testWidgets('cancelling discount secondary authorization aborts action', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final table = DiningTable.fromJson({'number': '10', 'status': 1});
      const order = PosOrder(
        id: 10,
        orderNo: 'ORD-DISC-CANCEL',
        tableNumber: '10',
        total: 40.0,
        diners: 2,
        createdAt: null,
        lines: const [
          PosOrderLine(
            id: 1,
            name: '羊肉串',
            quantity: 2,
            total: 40.0,
            unit: '串',
            specification: '',
            refunded: false,
          ),
        ],
      );
      final workspace = PosWorkspace(
        table: table,
        categories: const [],
        dishes: const [],
        paymentMethods: const [],
        currentOrder: order,
        tableOrders: [order],
      );
      final repository = _FakePosRepository(workspace);

      await tester.pumpWidget(
        MaterialApp(
          home: TableOrderPage(
            table: table,
            repository: repository,
            approvalRepository: _FakeAccessApprovalRepository(),
            currentAccount: 'CASHIER_01',
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('occupied-discount-button')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('discount-preset-9')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('discount-confirm')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('cashier-approval-dialog')), findsOneWidget);

      // 取消授权
      await tester.tap(find.byKey(const Key('approval-cancel')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('cashier-approval-dialog')), findsNothing);
      expect(repository.discountedOrderNo, isNull);
    });

    testWidgets(
      'secondary authorization shows error on wrong password and succeeds on retry',
      (tester) async {
        tester.view.physicalSize = const Size(1920, 1080);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        final table = DiningTable.fromJson({'number': '10', 'status': 1});
        const order = PosOrder(
          id: 10,
          orderNo: 'ORD-REFUND-AUTH',
          tableNumber: '10',
          total: 30.0,
          diners: 2,
          createdAt: null,
          lines: const [
            PosOrderLine(
              id: 201,
              name: '烤鸡翅',
              quantity: 2,
              total: 30.0,
              unit: '串',
              specification: '',
              refunded: false,
            ),
          ],
        );
        final workspace = PosWorkspace(
          table: table,
          categories: const [],
          dishes: const [],
          paymentMethods: const [],
          currentOrder: order,
          tableOrders: [order],
        );
        final repository = _FakePosRepository(workspace);

        await tester.pumpWidget(
          MaterialApp(
            home: TableOrderPage(
              table: table,
              repository: repository,
              approvalRepository: _FakeAccessApprovalRepository(),
            ),
          ),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(const Key('order-refund-201')));
        await tester.pumpAndSettle();
        await tester.enterText(
          find.byKey(const Key('refund-quantity-input')),
          '1',
        );
        await tester.pump();
        await tester.tap(find.byKey(const Key('refund-dish-confirm')));
        await tester.pumpAndSettle();

        expect(
          find.byKey(const Key('cashier-approval-dialog')),
          findsOneWidget,
        );

        // 密码错误
        await tester.enterText(
          find.byKey(const Key('approval-account')),
          'manager',
        );
        await tester.enterText(
          find.byKey(const Key('approval-credential')),
          'wrong_password',
        );
        await tester.tap(find.byKey(const Key('approval-submit')));
        await tester.pumpAndSettle();

        // 提示错误且弹窗仍存在
        expect(find.text('授权凭证错误，请重新输入'), findsOneWidget);
        expect(repository.refundedOrderNo, isNull);

        // 输入正确密码并重试
        await tester.enterText(
          find.byKey(const Key('approval-credential')),
          'correct_pass',
        );
        await tester.tap(find.byKey(const Key('approval-submit')));
        await tester.pumpAndSettle();

        expect(find.byKey(const Key('cashier-approval-dialog')), findsNothing);
        expect(repository.refundedOrderNo, 'ORD-REFUND-AUTH');
        expect(repository.refundDishApprovalToken, 'fake-approval-token');
      },
    );

    testWidgets(
      'workspace permission error shows explanation, account badge, and allows back, reload, and logout',
      (tester) async {
        tester.view.physicalSize = const Size(1920, 1080);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        final table = DiningTable.fromJson({'number': '12', 'status': 0});
        final workspace = PosWorkspace(
          table: table,
          categories: const [],
          dishes: const [],
          paymentMethods: const [],
          currentOrder: null,
        );
        final repository = _FakePosRepository(
          workspace,
          loadWorkspaceError: Exception('无权限：dish:manage'),
        );

        var loggedOut = false;
        var backed = false;

        await tester.pumpWidget(
          MaterialApp(
            home: TableOrderPage(
              table: table,
              repository: repository,
              approvalRepository: _FakeAccessApprovalRepository(),
              currentAccount: 'cashier01',
              onBack: () => backed = true,
              onLogout: () => loggedOut = true,
            ),
          ),
        );
        await tester.pumpAndSettle();

        // 验证错误提示结构
        expect(find.byKey(const Key('pos-workspace-error')), findsOneWidget);
        expect(find.text('点餐工作台权限不足'), findsOneWidget);
        expect(find.textContaining('dish:manage'), findsWidgets);
        expect(find.text('当前登录账号：cashier01'), findsOneWidget);
        expect(find.byKey(const Key('pos-top-back-button')), findsOneWidget);
        expect(find.byKey(const Key('pos-error-back-button')), findsOneWidget);
        expect(
          find.byKey(const Key('pos-error-reload-button')),
          findsOneWidget,
        );
        expect(
          find.byKey(const Key('pos-error-logout-button')),
          findsOneWidget,
        );

        // 点击重新加载
        expect(repository.workspaceLoadCount, 1);
        await tester.tap(find.byKey(const Key('pos-error-reload-button')));
        await tester.pumpAndSettle();
        expect(repository.workspaceLoadCount, 2);

        // 点击退出登录
        await tester.tap(find.byKey(const Key('pos-error-logout-button')));
        await tester.pumpAndSettle();
        expect(loggedOut, isTrue);

        // 点击返回桌台
        await tester.tap(find.byKey(const Key('pos-error-back-button')));
        await tester.pumpAndSettle();
        expect(backed, isTrue);
      },
    );

    testWidgets('loading workspace displays back button to return to tables', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final table = DiningTable.fromJson({'number': '12', 'status': 0});
      final workspaceCompleter = Completer<PosWorkspace>();
      final workspace = PosWorkspace(
        table: table,
        categories: const [],
        dishes: const [],
        paymentMethods: const [],
        currentOrder: null,
      );
      final repository = _FakePosRepository(
        workspace,
        workspaceCompleter: workspaceCompleter,
      );

      var backed = false;

      await tester.pumpWidget(
        MaterialApp(
          home: TableOrderPage(
            table: table,
            repository: repository,
            approvalRepository: _FakeAccessApprovalRepository(),
            onBack: () => backed = true,
          ),
        ),
      );
      await tester.pump();

      expect(find.byKey(const Key('pos-workspace-loading')), findsOneWidget);
      expect(find.byKey(const Key('pos-loading-back-button')), findsOneWidget);
      expect(find.byKey(const Key('pos-top-back-button')), findsOneWidget);

      await tester.tap(find.byKey(const Key('pos-loading-back-button')));
      await tester.pump();
      expect(backed, isTrue);

      workspaceCompleter.complete(workspace);
      await tester.pumpAndSettle();
    });
  });
}

class _FakeTableRepository implements TableRepository {
  _FakeTableRepository({DiningTable? table, this.overview})
    : table = table ?? DiningTable.fromJson({'number': '40', 'status': 0});

  final DiningTable table;
  final TableOverview? overview;
  FulfillmentStatus? updatedStatus;
  var loadCount = 0;

  @override
  Future<TableOverview> loadTableOverview() async {
    loadCount++;
    return overview ?? TableOverview(tables: [table]);
  }

  @override
  Future<FulfillmentOrderDetail> loadFulfillmentOrderDetail(
    FulfillmentOrder order,
  ) async {
    return FulfillmentOrderDetail(order: order, lines: const []);
  }

  final List<String> createdTables = [];
  final List<int> deletedTableIds = [];

  @override
  Future<void> verifyPassword({
    required String username,
    required String password,
  }) async {
    if (password != '123456') {
      throw Exception('密码错误，请重新输入');
    }
  }

  @override
  Future<void> updateFulfillmentStatus(
    FulfillmentOrder order,
    FulfillmentStatus status,
  ) async {
    updatedStatus = status;
  }

  @override
  Future<void> createTable({
    required String number,
    int peopleCount = 4,
    String? areaCode,
    String? areaName,
  }) async {
    createdTables.add(number);
  }

  final List<
      ({
        int id,
        String number,
        int? peopleCount,
        String? areaCode,
        String? areaName
      })> updatedTables = [];

  @override
  Future<void> updateTable({
    required int id,
    required String number,
    int? peopleCount,
    String? areaCode,
    String? areaName,
  }) async {
    updatedTables.add((
      id: id,
      number: number,
      peopleCount: peopleCount,
      areaCode: areaCode,
      areaName: areaName,
    ));
  }

  @override
  Future<void> deleteTable(int id) async {
    deletedTableIds.add(id);
  }

  @override
  Future<List<Map<String, dynamic>>> loadTableAreas() async => const [];

  @override
  Future<void> batchClearTables({
    List<int>? tableIds,
    List<String>? tableNumbers,
    String? operatorAccount,
  }) async {}

  @override
  Future<void> updateTableDiners({
    required String orderNo,
    required String tableNumber,
    required int diners,
    String? operatorAccount,
  }) async {}

  @override
  Future<Map<String, dynamic>?> loadTablePulse() async => null;
}

Color? _decorationColor(WidgetTester tester, Key key) {
  final widget = tester.widget(find.byKey(key));
  if (widget is Ink) {
    return (widget.decoration as BoxDecoration).color;
  }
  if (widget is Container) return widget.color;
  throw StateError('Unsupported decoration widget: ${widget.runtimeType}');
}

class _FakePosRepository
    implements
        PosRepository,
        PosCashCheckoutRepository,
        PosPickupOrderRepository {
  _FakePosRepository(
    this.workspace, {
    this.failOpen = false,
    this.submitError,
    this.refreshedWorkspace,
    this.loadWorkspaceError,
    this.workspaceCompleter,
  });

  final PosWorkspace workspace;
  final PosWorkspace? refreshedWorkspace;
  final bool failOpen;
  Object? submitError;
  Object? loadWorkspaceError;
  Completer<PosWorkspace>? workspaceCompleter;
  List<PosCartLine> submittedLines = const [];
  List<PosCartLine> pickupLines = const [];
  final List<String> submitRequestIds = [];
  final List<String> pickupRequestIds = [];
  final List<String> addDishRequestIds = [];
  Object? addDishesError;
  String? clearedTableNumber;
  String? openedTableNumber;
  String? checkoutPaymentMethod;
  PosCashSettlement? cashSettlement;
  String? giftedOrderNo;
  int? giftedDetailId;
  String? mergedSourceTableNumber;
  String? mergedTargetTableNumber;
  String? transferredOrderNo;
  String? transferredTargetTableNumber;
  String? addedDishesOrderNo;
  String? discountedOrderNo;
  double? discountedAmount;
  String? refundedOrderNo;
  int? refundedDetailId;
  int? refundedQuantity;
  PosRefundStockAction? refundedStockAction;
  String? refundedReason;
  String? manualRefundOrderNo;
  double? manualRefundAmount;
  String? hungOrderNo;
  int workspaceLoadCount = 0;

  @override
  Future<PosWorkspace> loadWorkspace(DiningTable table) async {
    workspaceLoadCount += 1;
    if (workspaceCompleter != null) {
      return await workspaceCompleter!.future;
    }
    if (loadWorkspaceError != null) throw loadWorkspaceError!;
    return workspaceLoadCount > 1 && refreshedWorkspace != null
        ? refreshedWorkspace!
        : workspace;
  }

  @override
  Future<PosSubmissionResult> submitOrder({
    required String tableNumber,
    required int diners,
    required String remark,
    required List<PosCartLine> lines,
    String? clientRequestId,
  }) async {
    submittedLines = lines;
    submitRequestIds.add(clientRequestId ?? '');
    if (submitError != null) throw submitError!;
    return const PosSubmissionResult(id: 1, orderNo: 'ORD40');
  }

  @override
  Future<PosSubmissionResult> submitPickupOrder({
    required String remark,
    required List<PosCartLine> lines,
    String? clientRequestId,
  }) async {
    pickupLines = lines;
    pickupRequestIds.add(clientRequestId ?? '');
    return const PosSubmissionResult(id: 2, orderNo: 'ORD-PICKUP');
  }

  @override
  Future<int?> addDishes({
    required String orderNo,
    required String tableNumber,
    required List<PosCartLine> lines,
    String? clientRequestId,
    int? expectedVersion,
  }) async {
    addedDishesOrderNo = orderNo;
    addDishRequestIds.add(clientRequestId ?? '');
    if (addDishesError != null) throw addDishesError!;
    return null;
  }

  @override
  Future<void> updateDiners({
    required String orderNo,
    required int diners,
  }) async {}

  @override
  Future<void> checkout({
    required String orderNo,
    required String paymentMethod,
    double? cashAmount,
    String collectionSessionId = '',
    bool force = false,
    String? approvalToken,
  }) async {
    checkoutPaymentMethod = paymentMethod;
  }

  @override
  Future<void> unCheckout({
    required String orderNo,
    required String reason,
    String? approvalToken,
  }) async {
    checkoutPaymentMethod = 'uncheckout';
  }

  @override
  Future<void> checkoutCash({
    required String orderNo,
    required String paymentMethod,
    required PosCashSettlement settlement,
  }) async {
    checkoutPaymentMethod = paymentMethod;
    cashSettlement = settlement;
  }

  String? discountAccount;
  String? discountPassword;
  String? discountApprovalToken;
  String? refundDishAccount;
  String? refundDishPassword;
  String? refundDishApprovalToken;
  String? giftDishAccount;
  String? giftDishPassword;
  String? giftDishApprovalToken;
  String? manualRefundAccount;
  String? manualRefundPassword;
  String? manualRefundApprovalToken;

  @override
  Future<int?> discountOrder({
    required String orderNo,
    required double discountAmount,
    required String reason,
    String? account,
    String? password,
    String? approvalToken,
    int? expectedVersion,
  }) async {
    if (approvalToken == null && account == null) {
      throw const ApiException('敏感操作需要现场输入授权员工账号和密码');
    }
    discountedOrderNo = orderNo;
    discountedAmount = discountAmount;
    discountAccount = account;
    discountPassword = password;
    discountApprovalToken = approvalToken;
    return null;
  }

  @override
  Future<void> clearTable(String tableNumber) async {
    clearedTableNumber = tableNumber;
  }

  String? hungReason;
  List<HangOrderSummary> hangList = const [];

  @override
  Future<String?> hangOrder({required String orderNo, String? reason}) async {
    hungOrderNo = orderNo;
    hungReason = reason;
    return 'HANG-$orderNo';
  }

  @override
  Future<bool> unhangOrder({required String orderNo}) async {
    return true;
  }

  @override
  Future<List<HangOrderSummary>> getHangList() async {
    return hangList;
  }

  @override
  Future<void> openTable(String tableNumber) async {
    openedTableNumber = tableNumber;
    if (failOpen) throw StateError('开台接口异常');
  }

  @override
  Future<void> mergeTables({
    required String sourceTableNumber,
    required String targetTableNumber,
  }) async {
    mergedSourceTableNumber = sourceTableNumber;
    mergedTargetTableNumber = targetTableNumber;
  }

  String? checkedOutTableNumber;
  String? tableCheckoutPaymentMethod;
  double? tableCheckoutCashAmount;

  @override
  Future<PosTableCheckoutResult> checkoutTable({
    required String tableNumber,
    String paymentMethod = 'cash',
    double? cashAmount,
    bool force = false,
    String? approvalToken,
  }) async {
    checkedOutTableNumber = tableNumber;
    tableCheckoutPaymentMethod = paymentMethod;
    tableCheckoutCashAmount = cashAmount;
    return PosTableCheckoutResult(
      tableNumber: tableNumber,
      settledOrders: [workspace.currentOrder?.orderNo ?? 'ORD-TABLE'],
      totalAmount: cashAmount ?? workspace.tableTotalPayable,
      cashAmount: cashAmount,
      changeAmount: 0,
    );
  }

  @override
  Future<int?> refundDish({
    required String orderNo,
    required int detailId,
    required int quantity,
    PosRefundStockAction? stockAction,
    String? reason,
    String? account,
    String? password,
    String? approvalToken,
    int? expectedVersion,
  }) async {
    if (approvalToken == null && account == null) {
      throw const ApiException('敏感操作需要现场输入授权员工账号和密码');
    }
    refundedOrderNo = orderNo;
    refundedDetailId = detailId;
    refundedQuantity = quantity;
    refundedStockAction = stockAction;
    refundedReason = reason;
    refundDishAccount = account;
    refundDishPassword = password;
    refundDishApprovalToken = approvalToken;
    return null;
  }

  @override
  Future<int?> giftDish({
    required String orderNo,
    required int detailId,
    String? account,
    String? password,
    String? approvalToken,
    int? expectedVersion,
  }) async {
    if (approvalToken == null && account == null) {
      throw const ApiException('敏感操作需要现场输入授权员工账号和密码');
    }
    giftedOrderNo = orderNo;
    giftedDetailId = detailId;
    giftDishAccount = account;
    giftDishPassword = password;
    giftDishApprovalToken = approvalToken;
    return null;
  }

  @override
  Future<CashierManualRefundResult> manualRefund({
    required String orderNo,
    double? refundAmount,
    String? reason,
    String? account,
    String? password,
    String? approvalToken,
  }) async {
    if (approvalToken == null && account == null) {
      throw const ApiException('敏感操作需要现场输入授权员工账号和密码');
    }
    manualRefundOrderNo = orderNo;
    manualRefundAmount = refundAmount;
    manualRefundAccount = account;
    manualRefundPassword = password;
    manualRefundApprovalToken = approvalToken;
    return CashierManualRefundResult(
      orderNo: orderNo,
      refundAmount: refundAmount ?? 50,
      refundTotal: 50,
      cashRemaining: 0,
    );
  }

  @override
  Future<void> verifyPassword({
    required String username,
    required String password,
  }) async {
    if (password == 'wrong_password') {
      throw StateError('账号或密码错误');
    }
  }

  @override
  Future<void> transferTable({
    required String orderNo,
    required String targetTableNumber,
  }) async {
    transferredOrderNo = orderNo;
    transferredTargetTableNumber = targetTableNumber;
  }
}

class _FakePaymentPosRepository extends _FakePosRepository
    implements
        PosOfflineCollectionRepository,
        PosBalanceCheckoutRepository,
        PosCombinedCheckoutRepository {
  _FakePaymentPosRepository(super.workspace);

  String? qrChannel;
  String? balanceOrderNo;
  String? balanceOpenid;
  String? combinedOrderNo;
  PosCheckoutSettlement? combinedSettlement;
  bool failCheckoutOnce = false;
  int checkoutAttempts = 0;
  int qrRequestCount = 0;
  int qrConfirmationCount = 0;
  final List<String> cancelledQrChannels = [];
  String? checkoutCollectionSessionId;

  @override
  Future<void> checkout({
    required String orderNo,
    required String paymentMethod,
    double? cashAmount,
    String collectionSessionId = '',
    bool force = false,
    String? approvalToken,
  }) async {
    checkoutAttempts += 1;
    if (failCheckoutOnce) {
      failCheckoutOnce = false;
      throw StateError('模拟入账失败');
    }
    await super.checkout(
      orderNo: orderNo,
      paymentMethod: paymentMethod,
      cashAmount: cashAmount,
      collectionSessionId: collectionSessionId,
      force: force,
      approvalToken: approvalToken,
    );
    checkoutCollectionSessionId = collectionSessionId;
  }

  @override
  Future<PosOfflineCollectionQr> createOfflineCollectionQr({
    required String channel,
    required String orderNo,
    required String sessionId,
    required int amountMinor,
  }) async {
    qrRequestCount += 1;
    qrChannel = channel;
    return PosOfflineCollectionQr(
      shopId: 2,
      channel: channel,
      qrImageBase64:
          'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=',
      jumpUrl: 'https://pay.test/jump?t=1',
      expiresInSeconds: 180,
    );
  }

  @override
  Future<void> confirmOfflineCollection({
    required String channel,
    required String orderNo,
    required String sessionId,
    required int amountMinor,
  }) async {
    qrConfirmationCount += 1;
  }

  @override
  Future<void> cancelOfflineCollection({
    required String channel,
    required String orderNo,
    required String sessionId,
  }) async {
    cancelledQrChannels.add(channel);
  }

  @override
  Future<bool> checkOrderSettled(String orderNo) async => false;

  @override
  Future<void> checkoutByBalance({
    required String orderNo,
    required String openid,
    required String memberPhone,
  }) async {
    balanceOrderNo = orderNo;
    balanceOpenid = openid;
  }

  @override
  Future<void> checkoutCombined({
    required String orderNo,
    required PosCheckoutSettlement settlement,
    String memberOpenid = '',
    String memberPhone = '',
    String collectionSessionId = '',
  }) async {
    combinedOrderNo = orderNo;
    combinedSettlement = settlement;
  }
}

class _FakePendingExternalCheckoutStore
    implements PendingExternalCheckoutStore {
  final values = <String, PendingExternalCheckout>{};

  @override
  Future<void> clear(String orderNo) async => values.remove(orderNo);

  @override
  Future<PendingExternalCheckout?> read(String orderNo) async =>
      values[orderNo];

  @override
  Future<void> write(PendingExternalCheckout value) async {
    values[value.orderNo] = value;
  }
}

class _FakePrintPosRepository extends _FakePosRepository
    implements
        PosOrderPrintRepository,
        PosKitchenPrintRepository,
        PosReceiptPrintRepository,
        PosPrintPreviewRepository {
  _FakePrintPosRepository(super.workspace);

  int? printedOrderId;
  String? kitchenPrintedOrderNo;
  final printedReceiptTypes = <PosReceiptPrintType>[];

  @override
  Future<PosPrintResult> printReceiptTicket({
    required PosReceiptPrintType type,
    required int orderId,
    required String orderNo,
  }) async {
    printedReceiptTypes.add(type);
    if (type == PosReceiptPrintType.front) printedOrderId = orderId;
    if (type == PosReceiptPrintType.kitchen) kitchenPrintedOrderNo = orderNo;
    return PosPrintResult(
      content: '<CB>40号桌</CB>',
      printSuccess: true,
      orderNo: orderNo,
    );
  }

  @override
  Future<PosPrintResult> printFrontTicket({
    required int orderId,
    String? orderNo,
  }) async {
    printedOrderId = orderId;
    return const PosPrintResult(
      content: '<CB>40号桌</CB>',
      printSuccess: true,
      orderNo: 'ORD40',
    );
  }

  @override
  Future<void> reprintKitchenTicket({required String orderNo}) async {
    kitchenPrintedOrderNo = orderNo;
  }

  @override
  Future<PrintPreviewResult> fetchPrintPreview({
    String scenario = 'ORDER',
    int? orderId,
    String? orderNo,
    int? deviceId,
    String paperSize = '58mm',
    bool isAddDishes = false,
    String? customContent,
  }) async {
    return PrintPreviewResult(
      scenario: scenario,
      scenarioName: '结账小票',
      paperSize: paperSize,
      paperWidthMm: paperSize == '80mm' ? 80 : 58,
      paperWidthChars: paperSize == '80mm' ? 48 : 32,
      shopName: '老肥油边王',
      totalTickets: 1,
      tickets: [
        const PrintTicket(
          ticketIndex: 1,
          title: '结账小票',
          rawContent: 'RAW_POS',
          plainText: '40号桌 结账单',
          elements: [
            PrintElement(
              type: PrintElementType.header,
              text: '40号桌 结账单',
              align: PrintElementAlign.center,
              size: PrintElementSize.large,
            ),
          ],
        ),
      ],
    );
  }
}

class _FakeMemberHistoryRepository implements CashierMemberRepository {
  @override
  Future<List<MemberConsumptionRecord>> loadConsumption(String phone) async {
    expect(phone, '13800000000');
    return const [
      MemberConsumptionRecord(
        id: 1,
        orderNo: 'ORD-HISTORY-1',
        amount: 88.8,
        paidAt: '2026-07-23 18:30:00',
        tableNumber: '20',
        paymentMethod: '微信支付',
      ),
    ];
  }

  @override
  Future<MemberConsumptionDetail> loadConsumptionDetail(
    MemberConsumptionRecord record,
  ) async {
    return MemberConsumptionDetail(record: record, lines: const []);
  }

  @override
  Future<void> bindOrder({required int orderId, required String phone}) async {
    throw UnimplementedError();
  }

  @override
  Future<CashierMemberProfile> loadProfile(String phone) async {
    throw UnimplementedError();
  }

  @override
  Future<List<MemberRechargeRecord>> loadRecharges(String phone) async {
    throw UnimplementedError();
  }

  @override
  Future<MemberRechargeResult> recharge({
    required String phone,
    required double amount,
    required double giftAmount,
  }) async {
    throw UnimplementedError();
  }

  @override
  Future<PagedCashierMembers> loadMembers({
    required int page,
    int pageSize = 20,
    String query = '',
    String phone = '',
  }) async {
    throw UnimplementedError();
  }

  @override
  Future<CashierMemberStats> loadStats() async {
    throw UnimplementedError();
  }

  @override
  Future<PagedRechargeLogs> loadRechargeLogs({
    int page = 1,
    int pageSize = 20,
    String phone = '',
    String startTime = '',
    String endTime = '',
  }) async {
    throw UnimplementedError();
  }

  @override
  Future<List<CashierCoupon>> loadCoupons() async {
    throw UnimplementedError();
  }

  @override
  Future<int> batchSendCoupon({required int couponId}) async {
    throw UnimplementedError();
  }

  @override
  Future<List<CashierPersonaTag>> loadPersonaTags({
    String? phone,
    int? memberId,
  }) async {
    return const [];
  }
}
