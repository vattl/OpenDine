import 'package:admin_panel_flutter/src/features/pos/domain/pos_models.dart';
import 'package:admin_panel_flutter/src/features/pos/presentation/order_checkout_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('stored-value debit is disabled when member balance is low', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1920, 1080);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    const order = PosOrder(
      id: 9,
      orderNo: 'ORD40',
      tableNumber: '40',
      diners: 2,
      total: 80,
      grossAmount: 80,
      memberPhone: '13800000000',
      memberOpenid: 'member-openid',
      memberBalance: 50,
      createdAt: null,
      lines: [],
    );

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: BalanceCheckoutDialog(order: order, chargeAmount: 80),
        ),
      ),
    );

    expect(find.text('会员余额不足，还差 ¥30.00'), findsOneWidget);
    final button = tester.widget<FilledButton>(
      find.byKey(const Key('balance-checkout-confirm')),
    );
    expect(button.onPressed, isNull);
  });

  testWidgets('stored-value debit is blocked when the order has a discount', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1920, 1080);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    const order = PosOrder(
      id: 9,
      orderNo: 'ORD40',
      tableNumber: '40',
      diners: 2,
      total: 80,
      grossAmount: 100,
      discountAmount: 20,
      memberPhone: '13800000000',
      memberOpenid: 'member-openid',
      memberBalance: 200,
      createdAt: null,
      lines: [],
    );

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: BalanceCheckoutDialog(order: order, chargeAmount: 100),
        ),
      ),
    );

    expect(find.text('当前订单已使用优惠，不能使用储值划扣'), findsOneWidget);
    final button = tester.widget<FilledButton>(
      find.byKey(const Key('balance-checkout-confirm')),
    );
    expect(button.onPressed, isNull);
  });

  testWidgets('combined checkout requires exact split and QR confirmation', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1920, 1080);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    const order = PosOrder(
      id: 9,
      orderNo: 'ORD40',
      tableNumber: '40',
      diners: 2,
      total: 100,
      memberPhone: '13800000000',
      memberOpenid: 'member-openid',
      memberBalance: 40,
      createdAt: null,
      lines: [],
    );
    const methods = [
      PosPaymentMethod(
        id: 1,
        code: 'clients.cashier.channels.cash',
        name: '现金',
        sortOrder: 1,
        enabled: true,
      ),
      PosPaymentMethod(
        id: 2,
        code: 'clients.cashier.channels.wechat',
        name: '微信',
        sortOrder: 2,
        enabled: true,
      ),
      PosPaymentMethod(
        id: 3,
        code: 'cashierBalanceEnabled',
        name: '余额',
        sortOrder: 3,
        enabled: true,
      ),
    ];
    String? confirmedChannel;
    int? confirmedAmount;
    PosCheckoutSettlement? persistedDraft;
    Set<String>? persistedConfirmedChannels;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CombinedCheckoutDialog(
            order: order,
            paymentMethods: methods,
            confirmCollection: (channel, amountMinor, _) async {
              confirmedChannel = channel;
              confirmedAmount = amountMinor;
              return true;
            },
            onCollectionConfirmed: (settlement, channels) async {
              persistedDraft = settlement;
              persistedConfirmedChannels = channels;
            },
          ),
        ),
      ),
    );
    await tester.enterText(find.byKey(const Key('combined-cash-field')), '30');
    await tester.enterText(
      find.byKey(const Key('combined-wechat-field')),
      '70',
    );
    await tester.pump();

    var button = tester.widget<FilledButton>(
      find.byKey(const Key('combined-checkout-confirm')),
    );
    expect(button.onPressed, isNull);

    await tester.tap(find.byKey(const Key('combined-wechat-confirm')));
    await tester.pumpAndSettle();

    expect(confirmedChannel, 'wechat');
    expect(confirmedAmount, 7000);
    expect(persistedDraft?.wechatMinor, 7000);
    expect(persistedConfirmedChannels, {'wechat'});
    final collectionButton = tester.widget<FilledButton>(
      find.byKey(const Key('combined-wechat-confirm')),
    );
    expect(collectionButton.onPressed, isNull);
    expect(find.text('已确认到账'), findsOneWidget);
    button = tester.widget<FilledButton>(
      find.byKey(const Key('combined-checkout-confirm')),
    );
    expect(button.onPressed, isNotNull);
  });

  testWidgets('combined checkout caps member balance allocation', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1920, 1080);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    const order = PosOrder(
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
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CombinedCheckoutDialog(
            order: order,
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
            ],
            confirmCollection: (_, _, _) async => true,
          ),
        ),
      ),
    );
    await tester.enterText(find.byKey(const Key('combined-cash-field')), '60');
    await tester.enterText(
      find.byKey(const Key('combined-balance-field')),
      '40',
    );
    await tester.pump();

    expect(find.text('余额分配金额不能超过会员可用余额'), findsOneWidget);
    final button = tester.widget<FilledButton>(
      find.byKey(const Key('combined-checkout-confirm')),
    );
    expect(button.onPressed, isNull);
  });

  testWidgets('combined checkout fits a 1024 by 768 landscape display', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1024, 768);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CombinedCheckoutDialog(
            order: const PosOrder(
              id: 40,
              orderNo: 'ORD40',
              tableNumber: '40',
              diners: 2,
              total: 100,
              memberPhone: '13800000000',
              memberOpenid: 'member-openid',
              memberBalance: 100,
              createdAt: null,
              lines: [],
            ),
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
                code: 'wechat',
                name: '微信',
                sortOrder: 2,
                enabled: true,
              ),
              PosPaymentMethod(
                id: 3,
                code: 'alipay',
                name: '支付宝',
                sortOrder: 3,
                enabled: true,
              ),
              PosPaymentMethod(
                id: 4,
                code: 'balance',
                name: '余额',
                sortOrder: 4,
                enabled: true,
              ),
            ],
            confirmCollection: (_, _, _) async => true,
          ),
        ),
      ),
    );

    expect(find.byKey(const Key('combined-checkout-confirm')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('four-channel split requires both QR confirmations and submits', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1920, 1080);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    CombinedCheckoutDialogResult? result;

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => FilledButton(
            onPressed: () async {
              result = await showDialog<CombinedCheckoutDialogResult>(
                context: context,
                builder: (_) => CombinedCheckoutDialog(
                  order: const PosOrder(
                    id: 40,
                    orderNo: 'ORD40',
                    tableNumber: '40',
                    diners: 2,
                    total: 100,
                    memberPhone: '13800000000',
                    memberOpenid: 'member-openid',
                    memberBalance: 100,
                    createdAt: null,
                    lines: [],
                  ),
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
                      code: 'offline_wechat_qr',
                      name: '微信',
                      sortOrder: 2,
                      enabled: true,
                    ),
                    PosPaymentMethod(
                      id: 3,
                      code: 'offline_alipay_qr',
                      name: '支付宝',
                      sortOrder: 3,
                      enabled: true,
                    ),
                    PosPaymentMethod(
                      id: 4,
                      code: 'online_balance',
                      name: '余额',
                      sortOrder: 4,
                      enabled: true,
                    ),
                  ],
                  confirmCollection: (_, _, _) async => true,
                ),
              );
            },
            child: const Text('打开组合支付'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('打开组合支付'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('combined-cash-field')), '10');
    await tester.enterText(
      find.byKey(const Key('combined-wechat-field')),
      '20',
    );
    await tester.enterText(
      find.byKey(const Key('combined-alipay-field')),
      '30',
    );
    await tester.enterText(
      find.byKey(const Key('combined-balance-field')),
      '40',
    );
    await tester.tap(find.byKey(const Key('combined-wechat-confirm')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('combined-alipay-confirm')));
    await tester.pumpAndSettle();

    var button = tester.widget<FilledButton>(
      find.byKey(const Key('combined-checkout-confirm')),
    );
    expect(button.onPressed, isNotNull);
    expect(
      tester
          .widget<TextField>(
            find.byKey(const Key('combined-wechat-field')),
          )
          .enabled,
      isFalse,
    );
    await tester.tap(find.byKey(const Key('combined-checkout-confirm')));
    await tester.pumpAndSettle();

    expect(result?.cashMinor, 1000);
    expect(result?.wechatMinor, 2000);
    expect(result?.alipayMinor, 3000);
    expect(result?.balanceMinor, 4000);
  });

  testWidgets('combined checkout can close after QR collection is confirmed', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1920, 1080);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    var dialogCompleted = false;
    CombinedCheckoutDialogResult? result;

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => FilledButton(
            onPressed: () async {
              result = await showDialog<CombinedCheckoutDialogResult>(
                context: context,
                barrierDismissible: false,
                builder: (_) => CombinedCheckoutDialog(
                  order: const PosOrder(
                    id: 40,
                    orderNo: 'ORD40',
                    tableNumber: '40',
                    diners: 2,
                    total: 100,
                    createdAt: null,
                    lines: [],
                  ),
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
                      code: 'offline_wechat_qr',
                      name: '微信',
                      sortOrder: 2,
                      enabled: true,
                    ),
                  ],
                  confirmCollection: (_, _, _) async => true,
                ),
              );
              dialogCompleted = true;
            },
            child: const Text('打开组合支付'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('打开组合支付'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('combined-cash-field')), '30');
    await tester.enterText(
      find.byKey(const Key('combined-wechat-field')),
      '70',
    );
    await tester.tap(find.byKey(const Key('combined-wechat-confirm')));
    await tester.pumpAndSettle();
    expect(find.text('已确认到账'), findsOneWidget);

    await tester.tap(find.byKey(const Key('checkout-dialog-close')));
    await tester.pumpAndSettle();

    expect(dialogCompleted, isTrue);
    expect(result, isNull);
    expect(find.byKey(const Key('combined-checkout-dialog')), findsNothing);
  });

  testWidgets(
    'offline collection dialog auto-polls order settlement and pops true upon success',
    (tester) async {
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      bool settled = false;
      OfflineCollectionDialogResult? result;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () async {
                  result = await showDialog<OfflineCollectionDialogResult>(
                    context: context,
                    builder: (_) => OfflineCollectionCheckoutDialog(
                      amount: 88,
                      channel: 'wechat',
                      channelLabel: '微信',
                      checkSettled: () async => settled,
                      loadQr: () async => const PosOfflineCollectionQr(
                        shopId: 1,
                        channel: 'wechat',
                        qrImageBase64:
                            'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=',
                        jumpUrl: 'https://pay.test/jump',
                        expiresInSeconds: 180,
                      ),
                    ),
                  );
                },
                child: const Text('打开收款码'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('打开收款码'));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const Key('offline-collection-checkout-dialog')),
        findsOneWidget,
      );

      // Advance time by 1 second - not settled yet
      await tester.pump(const Duration(seconds: 1));
      expect(
        find.byKey(const Key('offline-collection-checkout-dialog')),
        findsOneWidget,
      );
      expect(result, isNull);

      // Now set settled to true and advance by 2 seconds
      settled = true;
      await tester.pump(const Duration(seconds: 2));
      await tester.pumpAndSettle();

      // Dialog should automatically pop with autoSettled!
      expect(
        find.byKey(const Key('offline-collection-checkout-dialog')),
        findsNothing,
      );
      expect(result, equals(OfflineCollectionDialogResult.autoSettled));
    },
  );

  testWidgets('offline collection confirm button is guarded for 3 seconds with spinner and status prompt', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1920, 1080);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () {
                showDialog<OfflineCollectionDialogResult>(
                  context: context,
                  builder: (_) => OfflineCollectionCheckoutDialog(
                    amount: 88,
                    channel: 'wechat',
                    channelLabel: '微信',
                    checkSettled: () async => false,
                    loadQr: () async => const PosOfflineCollectionQr(
                      shopId: 1,
                      channel: 'wechat',
                      qrImageBase64:
                          'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=',
                      jumpUrl: 'https://pay.test/jump',
                      expiresInSeconds: 180,
                    ),
                  ),
                );
              },
              child: const Text('打开收款码'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('打开收款码'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    // Guard active: button disabled and shows the countdown label + spinner.
    var confirm = tester.widget<FilledButton>(
      find.byKey(const Key('offline-collection-confirm')),
    );
    expect(confirm.onPressed, isNull);
    expect(find.text('正在检测支付状态 3S'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsWidgets);

    // Mid-countdown (1s in): still disabled, label counts down to 2S.
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('正在检测支付状态 2S'), findsOneWidget);
    confirm = tester.widget<FilledButton>(
      find.byKey(const Key('offline-collection-confirm')),
    );
    expect(confirm.onPressed, isNull);

    // After the 3s countdown the button returns to clickable.
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();
    confirm = tester.widget<FilledButton>(
      find.byKey(const Key('offline-collection-confirm')),
    );
    expect(confirm.onPressed, isNotNull);
    expect(find.text('确认已收款'), findsOneWidget);
  });

  testWidgets('offline collection polls settlement every 3 seconds', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1920, 1080);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    var checkCalls = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () {
                showDialog<OfflineCollectionDialogResult>(
                  context: context,
                  builder: (_) => OfflineCollectionCheckoutDialog(
                    amount: 88,
                    channel: 'wechat',
                    channelLabel: '微信',
                    checkSettled: () async {
                      checkCalls += 1;
                      return false;
                    },
                    loadQr: () async => const PosOfflineCollectionQr(
                      shopId: 1,
                      channel: 'wechat',
                      qrImageBase64:
                          'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=',
                      jumpUrl: 'https://pay.test/jump',
                      expiresInSeconds: 180,
                    ),
                  ),
                );
              },
              child: const Text('打开收款码'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('打开收款码'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(checkCalls, 0);
    // No check at 2s: the polling interval is 3s.
    await tester.pump(const Duration(seconds: 2));
    expect(checkCalls, 0);

    // First check fires at 3s, then every 3s.
    await tester.pump(const Duration(seconds: 1));
    expect(checkCalls, 1);
    await tester.pump(const Duration(seconds: 3));
    expect(checkCalls, 2);
  });

  testWidgets('offline collection stops polling after the QR expires', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1920, 1080);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    var checkCalls = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () {
                showDialog<OfflineCollectionDialogResult>(
                  context: context,
                  builder: (_) => OfflineCollectionCheckoutDialog(
                    amount: 88,
                    channel: 'wechat',
                    channelLabel: '微信',
                    checkSettled: () async {
                      checkCalls += 1;
                      return false;
                    },
                    loadQr: () async => const PosOfflineCollectionQr(
                      shopId: 1,
                      channel: 'wechat',
                      qrImageBase64:
                          'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=',
                      jumpUrl: 'https://pay.test/jump',
                      expiresInSeconds: 10,
                    ),
                  ),
                );
              },
              child: const Text('打开收款码'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('打开收款码'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    // Checks run at 3s, 6s, 9s while the QR is still valid.
    await tester.pump(const Duration(seconds: 3));
    expect(checkCalls, 1);
    await tester.pump(const Duration(seconds: 9));
    expect(checkCalls, 3);

    // The QR expired at 10s; polling must stop and never resume.
    expect(find.text('收款码已失效，请刷新'), findsOneWidget);
    await tester.pump(const Duration(seconds: 15));
    expect(checkCalls, 3);
  });

  testWidgets('payment success dialog displays amount and confirms with close', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1920, 1080);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: PaymentSuccessDialog(
            amount: 128.50,
            orderNo: 'ORD9999',
            channelLabel: '微信',
          ),
        ),
      ),
    );

    expect(find.byKey(const Key('payment-success-dialog')), findsOneWidget);
    expect(find.text('收款成功'), findsOneWidget);
    expect(find.text('¥128.50'), findsOneWidget);
    expect(find.text('订单号：ORD9999  |  方式：微信自动核销'), findsOneWidget);
    expect(find.byKey(const Key('payment-success-confirm')), findsOneWidget);
  });

  testWidgets('CashierForceCheckoutDialog allows selecting payment method and entering reason', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1920, 1080);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    ForceCheckoutResult? result;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) {
              return ElevatedButton(
                onPressed: () async {
                  result = await showDialog<ForceCheckoutResult>(
                    context: context,
                    builder: (_) => const CashierForceCheckoutDialog(
                      orderNo: 'ORD_TEST_FORCE',
                      amount: 268.0,
                      paymentMethods: [
                        PosPaymentMethod(id: 1, code: 'cash', name: '现金支付', sortOrder: 1, enabled: true),
                        PosPaymentMethod(id: 2, code: 'wechat', name: '微信支付', sortOrder: 2, enabled: true),
                        PosPaymentMethod(id: 3, code: 'alipay', name: '支付宝支付', sortOrder: 3, enabled: true),
                      ],
                    ),
                  );
                },
                child: const Text('Open'),
              );
            },
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('force-checkout-dialog')), findsOneWidget);
    expect(find.text('关联单号'), findsOneWidget);
    expect(find.text('ORD_TEST_FORCE'), findsOneWidget);
    expect(find.text('¥268.00'), findsOneWidget);

    // Select Alipay chip
    await tester.tap(find.byKey(const Key('force-pay-chip-alipay')));
    await tester.pumpAndSettle();

    // Enter reason
    await tester.enterText(
      find.byKey(const Key('force-checkout-reason-field')),
      '顾客离店现金已付',
    );
    await tester.pumpAndSettle();

    // Confirm
    await tester.tap(find.byKey(const Key('force-checkout-confirm-btn')));
    await tester.pumpAndSettle();

    expect(result, isNotNull);
    expect(result!.paymentMethod, 'alipay');
    expect(result!.reason, '顾客离店现金已付');
  });
}
