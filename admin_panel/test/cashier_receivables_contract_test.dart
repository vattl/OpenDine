import 'dart:convert';

import 'package:admin_panel_flutter/src/core/admin_api_client.dart';
import 'package:admin_panel_flutter/src/core/api_contract.dart';
import 'package:admin_panel_flutter/src/features/cashier_shift/domain/cashier_shift.dart';
import 'package:admin_panel_flutter/src/features/pos/data/pos_repository.dart';
import 'package:admin_panel_flutter/src/features/pos/data/real_pos_repository.dart';
import 'package:admin_panel_flutter/src/features/pos/domain/pos_models.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_http_transport.dart';

void main() {
  group('cashier receivables API contracts & endpoints', () {
    test('endpoints have correct paths, methods and permissions', () {
      expect(cashierReceivableEligibleAccountsEndpoint.method, 'GET');
      expect(cashierReceivableEligibleAccountsEndpoint.path, '/cashier/receivables/eligible-accounts');
      expect(cashierReceivableEligibleAccountsEndpoint.permissionCode, 'cashier:operate');

      expect(cashierReceivableChargesEndpoint.method, 'POST');
      expect(cashierReceivableChargesEndpoint.path, '/cashier/receivables/charges');
      expect(cashierReceivableChargesEndpoint.permissionCode, 'cashier:operate');

      expect(cashierReceivableClaimsEndpoint.method, 'GET');
      expect(cashierReceivableClaimsEndpoint.path, '/cashier/receivables/claims');
      expect(cashierReceivableClaimsEndpoint.permissionCode, 'cashier:operate');

      expect(cashierReceivableClaimDetailEndpoint.method, 'GET');
      expect(cashierReceivableClaimDetailEndpoint.path, '/cashier/receivables/claims/{id}');
      expect(cashierReceivableClaimDetailEndpoint.permissionCode, 'cashier:operate');

      expect(cashierReceivableCollectionsEndpoint.method, 'POST');
      expect(cashierReceivableCollectionsEndpoint.path, '/cashier/receivables/claims/{id}/collections');
      expect(cashierReceivableCollectionsEndpoint.permissionCode, 'cashier:operate');
    });

    test('PosPaymentChannelKind supports receivable channel and normalization', () {
      expect(PosPaymentChannelKind.normalize('receivable'), PosPaymentChannelKind.receivable);
      expect(PosPaymentChannelKind.normalize('RECEIVABLE'), PosPaymentChannelKind.receivable);
      expect(PosPaymentChannelKind.normalize('挂账'), PosPaymentChannelKind.receivable);
      expect(PosPaymentChannelKind.normalize('客户挂账'), PosPaymentChannelKind.receivable);
      expect(PosPaymentChannelKind.normalize('ar'), PosPaymentChannelKind.receivable);
      expect(PosPaymentChannelKind.normalize('credit'), PosPaymentChannelKind.receivable);
    });

    test('PosReceivableEligibleAccount model parses json correctly', () {
      final json = {
        'id': 101,
        'customerName': '腾讯科技商务招待',
        'contactName': '马经理',
        'contactPhone': '13800138000',
        'creditLimitFen': 500000,
        'availableLimitFen': 380000,
        'settlementType': 'MONTHLY',
        'status': 'ACTIVE',
      };
      final account = PosReceivableEligibleAccount.fromJson(json);
      expect(account.id, 101);
      expect(account.customerName, '腾讯科技商务招待');
      expect(account.contactName, '马经理');
      expect(account.contactPhone, '13800138000');
      expect(account.creditLimitFen, 500000);
      expect(account.availableLimitFen, 380000);
      expect(account.creditLimitYuan, 5000.00);
      expect(account.availableLimitYuan, 3800.00);
      expect(account.canCover(3000.0), true);
      expect(account.canCover(4000.0), false);
    });

    test('PosReceivableEligibleAccount correctly computes availableLimitFen when missing in JSON', () {
      final jsonWithoutAvailable = {
        'id': 102,
        'customerName': '万达商管餐饮部',
        'creditLimitFen': 2000000, // 20,000.00 元
        'outstandingFen': 0, // 0 元未清
        'status': 'ACTIVE',
      };
      final account = PosReceivableEligibleAccount.fromJson(jsonWithoutAvailable);
      expect(account.id, 102);
      expect(account.creditLimitFen, 2000000);
      expect(account.availableLimitFen, 2000000);
      expect(account.creditLimitYuan, 20000.00);
      expect(account.availableLimitYuan, 20000.00);
      expect(account.canCover(19999.00), true);
      expect(account.canCover(20000.00), true);
      expect(account.canCover(20001.00), false);
    });

    test('PosReceivableClaim and PosReceivableLedger parse json correctly', () {
      final claimJson = {
        'id': 2001,
        'claimNo': 'REC202610180001',
        'accountId': 101,
        'customerName': '腾讯科技商务招待',
        'orderNo': 'ORD202610189999',
        'originalAmountFen': 45000,
        'collectedAmountFen': 0,
        'outstandingFen': 45000,
        'status': 'OPEN',
      };
      final claim = PosReceivableClaim.fromJson(claimJson);
      expect(claim.id, 2001);
      expect(claim.claimNo, 'REC202610180001');
      expect(claim.accountId, 101);
      expect(claim.customerName, '腾讯科技商务招待');
      expect(claim.originalAmountFen, 45000);
      expect(claim.outstandingFen, 45000);
      expect(claim.originalAmountYuan, 450.00);
      expect(claim.outstandingYuan, 450.00);
      expect(claim.status, 'OPEN');

      final ledgerJson = {
        'id': 3001,
        'ledgerNo': 'LED-001',
        'claimId': 2001,
        'orderNo': 'ORD202610189999',
        'direction': 'CREDIT',
        'entryType': 'COLLECTION',
        'amountFen': 45000,
        'channel': 'CASH',
        'drawerSessionId': 88,
        'createdAt': '2026-10-18T12:00:00Z',
      };
      final ledger = PosReceivableLedger.fromJson(ledgerJson);
      expect(ledger.id, 3001);
      expect(ledger.amountFen, 45000);
      expect(ledger.amountYuan, 450.00);
      expect(ledger.drawerSessionId, 88);
    });

    test('DailyPrecheckBlocker parses reasonSummary and ledgerMismatches', () {
      final json = {
        'code': 'ORDER_LEDGER_MISMATCH',
        'message': '存在 2 笔未平账交易',
        'count': 2,
        'reason_summary': '发现 2 笔结账流水与订单实收金额不一致，差异总计 ¥85.00，请排查补录或冲正。',
        'ledger_mismatches': [
          {
            'order_id': 901,
            'order_no': 'ORD20261018001',
            'reason_code': 'AMOUNT_MISMATCH',
            'reason': '挂账回款少记 20 元',
            'order_amount_fen': 12000,
            'ledger_amount_fen': 10000,
            'difference_fen': -2000,
          },
          {
            'order_id': 902,
            'order_no': 'ORD20261018002',
            'reason_code': 'MISSING_LEDGER',
            'reason': '订单结账未生成对应支付流水',
            'order_amount_fen': 6500,
            'ledger_amount_fen': 0,
            'difference_fen': -6500,
          }
        ]
      };
      final blocker = DailyPrecheckBlocker.fromJson(json);
      expect(blocker.code, 'ORDER_LEDGER_MISMATCH');
      expect(blocker.reasonSummary, '发现 2 笔结账流水与订单实收金额不一致，差异总计 ¥85.00，请排查补录或冲正。');
      expect(blocker.ledgerMismatches.length, 2);
      expect(blocker.ledgerMismatches.first.orderNo, 'ORD20261018001');
      expect(blocker.ledgerMismatches.first.orderAmountYuan, 120.00);
      expect(blocker.ledgerMismatches.first.differenceYuan, -20.00);
    });

    test('CashierWechatNativeException evaluates isExplicitRejection properly', () {
      const exReject = CashierWechatNativeException(
        code: 40231,
        message: '微信支付商户通道明确拒绝：商户号受限或风控阻断',
        wechatCode: 'MERCHANT_RESTRICTED',
      );
      expect(exReject.isExplicitRejection, true);

      const exTimeout = CashierWechatNativeException(
        code: 40230,
        message: '微信下单网络超时',
      );
      expect(exTimeout.isExplicitRejection, false);
    });
  });

  group('RealPosRepository receivables operations with mock transport', () {
    test('loadEligibleAccounts, chargeReceivable, loadReceivableClaims and collectReceivable', () async {
      final fakeTransport = FakeHttpTransport({
        'GET /cashier/receivables/eligible-accounts': jsonEncode({
          'code': 0,
          'message': 'success',
          'data': [
            {
              'id': 101,
              'customerName': '某科技股份有限公司',
              'contactName': '张总',
              'contactPhone': '13900001111',
              'creditLimitFen': 1000000,
              'availableLimitFen': 800000,
              'status': 'ACTIVE',
            }
          ]
        }),
        'POST /cashier/receivables/charges': jsonEncode({
          'code': 0,
          'message': 'success',
          'data': {
            'id': 2001,
            'claimNo': 'REC202610188888',
            'accountId': 101,
            'customerName': '某科技股份有限公司',
            'orderNo': 'ORD202610180001',
            'originalAmountFen': 50000,
            'outstandingBalanceFen': 50000,
            'status': 'OPEN',
          }
        }),
        'GET /cashier/receivables/claims': jsonEncode({
          'code': 0,
          'message': 'success',
          'data': {
            'items': [
              {
                'id': 2001,
                'claimNo': 'REC202610188888',
                'accountId': 101,
                'customerName': '某科技股份有限公司',
                'orderNo': 'ORD202610180001',
                'originalAmountFen': 50000,
                'outstandingBalanceFen': 50000,
                'status': 'OPEN',
              }
            ]
          }
        }),
        'POST /cashier/receivables/claims/2001/collections': jsonEncode({
          'code': 0,
          'message': 'success',
          'data': {
            'id': 3002,
            'claimId': 2001,
            'entryType': 'COLLECTION',
            'amountFen': 50000,
            'channel': 'CASH',
            'drawerSessionId': 88,
            'createdAt': '2026-10-18T14:00:00Z',
          }
        }),
      });

      final client = AdminApiClient(
        baseUrl: 'http://test-server',
        transport: fakeTransport,
      );
      final repo = RealPosRepository(client);

      // 1. loadEligibleAccounts
      final accounts = await repo.loadEligibleAccounts();
      expect(accounts.length, 1);
      expect(accounts.first.customerName, '某科技股份有限公司');

      // 2. chargeReceivable
      final claim = await repo.chargeReceivable(
        orderNo: 'ORD202610180001',
        accountId: 101,
        requestId: 'REQ-123456',
        note: '签单经办人：张三',
      );
      expect(claim.id, 2001);
      expect(claim.claimNo, 'REC202610188888');

      // 3. loadReceivableClaims
      final claims = await repo.loadReceivableClaims();
      expect(claims.length, 1);
      expect(claims.first.id, 2001);

      // 4. collectReceivable
      final ledger = await repo.collectReceivable(
        claimId: 2001,
        amountFen: 50000,
        channel: 'CASH',
        requestId: 'REQ-COLL-789',
        drawerSessionId: 88,
      );
      expect(ledger.id, 3002);
      expect(ledger.amountFen, 50000);
      expect(ledger.drawerSessionId, 88);
    });
  });
}
