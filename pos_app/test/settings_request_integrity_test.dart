import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:admin_panel_flutter/src/core/admin_api_client.dart';
import 'package:admin_panel_flutter/src/core/api_contract.dart';
import 'package:admin_panel_flutter/src/features/cashier_settings/domain/coupon_models.dart';
import 'package:admin_panel_flutter/src/features/cashier_settings/domain/cashier_settings.dart';
import 'package:admin_panel_flutter/src/features/receivable_management/data/receivable_management_repository.dart';
import 'package:admin_panel_flutter/src/core/http_transport.dart';
import 'package:admin_panel_flutter/src/features/cashier_settings/data/real_cashier_settings_repository.dart';
import 'fake_http_transport.dart';

void main() {
  test('cash collection requires an open drawer in the current shop', () async {
    for (final response in [
      {'shift': null, 'drawer_session': null},
      {
        'shift': {'shop_id': 1, 'drawer_session_id': 8},
        'drawer_session': {'id': 8, 'state': 'CLOSED'},
      },
      {
        'shift': {'shop_id': 2, 'drawer_session_id': 8},
        'drawer_session': {'id': 8, 'state': 'OPEN'},
      },
      {
        'shift': {'shop_id': 1, 'drawer_session_id': 8},
        'drawer_session': {'id': 9, 'state': 'OPEN'},
      },
    ]) {
      final transport = FakeHttpTransport({
        'GET /cashier/shift/current': jsonEncode(response),
      });
      final repo = ReceivableManagementRepository(
        AdminApiClient(
          baseUrl: 'http://api.test',
          transport: transport,
          token: 'test',
          shopId: 1,
        ),
      );
      await expectLater(
        repo.collectClaim(
          claimId: 9,
          amountFen: 100,
          channel: 'CASH',
          requestId: 'retry-1',
        ),
        throwsStateError,
      );
      expect(transport.requests.where((r) => r.method == 'POST'), isEmpty);
    }
  });
  test(
    'cash collection sends the real drawer and keeps the idempotency key',
    () async {
      final transport = FakeHttpTransport({
        'GET /cashier/shift/current': jsonEncode({
          'shift': {'shop_id': 1, 'drawer_session_id': 81, 'end_time': null},
          'drawer_session': {'id': 81, 'state': 'OPEN'},
        }),
        'POST /admin/receivables/claims/9/collections': '{}',
      });
      final repo = ReceivableManagementRepository(
        AdminApiClient(
          baseUrl: 'http://api.test',
          transport: transport,
          token: 'test',
          shopId: 1,
        ),
      );
      await repo.collectClaim(
        claimId: 9,
        amountFen: 100,
        channel: 'CASH',
        requestId: 'retry-1',
      );
      expect(jsonDecode(transport.requests.last.body!)['drawerSessionId'], 81);
      expect(jsonDecode(transport.requests.last.body!)['requestId'], 'retry-1');
      transport.requests.clear();
      await repo.collectClaim(
        claimId: 9,
        amountFen: 100,
        channel: 'BANK_TRANSFER',
        requestId: 'retry-2',
      );
      expect(transport.requests.length, 1);
      expect(
        jsonDecode(
          transport.requests.last.body!,
        ).containsKey('drawerSessionId'),
        false,
      );
    },
  );
  test(
    'employee assignment failure exposes the created account instead of success',
    () async {
      final transport = FakeHttpTransport({
        'POST /admin/administrator/create': '{"id":91}',
        'POST /admin/access/employees': const HttpResponseData(
          statusCode: 403,
          body: 'denied',
        ),
      });
      final repository = RealCashierSettingsRepository(
        AdminApiClient(
          baseUrl: 'http://api.test',
          transport: transport,
          token: 'test',
          shopId: 1,
        ),
      );
      await expectLater(
        repository.createEmployee(
          userName: 'employee',
          password: 'test-only',
          roleIds: [1],
          shopIds: [1],
        ),
        throwsA(
          isA<EmployeeAssignmentException>().having(
            (e) => e.adminId,
            'created id',
            91,
          ),
        ),
      );
      expect(transport.requests.length, 2);
    },
  );
  test('coupon editing preserves dining and dish scope from the server', () {
    final coupon = CouponTemplate.fromJson({
      'id': 9,
      'coupon_name': '堂食券',
      'apply_dining_type': 'dine_in',
      'apply_dish_ids': '[12,34]',
    });
    expect(coupon.toSaveJson()['apply_dining_type'], 'dine_in');
    expect(coupon.toSaveJson()['apply_dish_ids'], '[12,34]');
  });
  test('RBAC deletes target the requested record', () {
    expect(
      rbacPermissionDeleteByIdEndpoint(17).path,
      '/admin/rbac/permissions/17',
    );
    expect(
      rbacApiPermissionDeleteByIdEndpoint(29).path,
      '/admin/rbac/api-permissions/29',
    );
  });
  test('announcement sends server sortOrder', () async {
    final transport = FakeHttpTransport({
      'POST /admin/announcement/add': jsonEncode({'id': 8}),
    });
    final repository = RealCashierSettingsRepository(
      AdminApiClient(
        baseUrl: 'http://api.test',
        transport: transport,
        token: 'test',
        shopId: 1,
      ),
    );
    await repository.publishAnnouncement(
      title: '公告',
      content: '内容',
      status: 1,
      sort: 9,
    );
    final body = jsonDecode(transport.requests.single.body!);
    expect(body['sortOrder'], 9);
    expect(body.containsKey('sort'), false);
  });
}
