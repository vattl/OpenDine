import 'package:admin_panel_flutter/src/core/api_contract.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('cashier extension API contract', () {
    const cases =
        <
          ({
            AdminEndpoint endpoint,
            String method,
            String path,
            String permissionCode,
            bool attachShopHeader,
          })
        >[
          (
            endpoint: cashierOrderTodayEndpoint,
            method: 'GET',
            path: '/cashier/order/today',
            permissionCode: 'cashier:operate',
            attachShopHeader: true,
          ),
          (
            endpoint: cashierOrderSearchEndpoint,
            method: 'GET',
            path: '/cashier/order/search',
            permissionCode: 'cashier:operate',
            attachShopHeader: true,
          ),
          (
            endpoint: cashierPrintDispatchEndpoint,
            method: 'POST',
            path: '/cashier/print/dispatch',
            permissionCode: 'cashier:operate',
            attachShopHeader: true,
          ),
          (
            endpoint: adminPrintDispatchEndpoint,
            method: 'POST',
            path: '/admin/printing/dispatch',
            permissionCode: 'printing:manage',
            attachShopHeader: true,
          ),
          (
            endpoint: cashierPrintKitchenEndpoint,
            method: 'POST',
            path: '/cashier/print/kitchen',
            permissionCode: 'cashier:operate',
            attachShopHeader: true,
          ),
          (
            endpoint: cashierOrderUnCheckoutEndpoint,
            method: 'POST',
            path: '/cashier/order/unCheckout',
            permissionCode: 'cashier:operate',
            attachShopHeader: true,
          ),
          (
            endpoint: cashierShiftCurrentEndpoint,
            method: 'GET',
            path: '/cashier/shift/current',
            permissionCode: 'cashier:operate',
            attachShopHeader: true,
          ),
          (
            endpoint: cashierShiftStartEndpoint,
            method: 'POST',
            path: '/cashier/shift/start',
            permissionCode: 'cashier:operate',
            attachShopHeader: true,
          ),
          (
            endpoint: cashierShiftHandoverEndpoint,
            method: 'POST',
            path: '/cashier/shift/handover',
            permissionCode: 'cashier:operate',
            attachShopHeader: true,
          ),
          (
            endpoint: offlineCollectCancelEndpoint,
            method: 'POST',
            path: '/pay/offline-collect/cancel',
            permissionCode: 'cashier:operate',
            attachShopHeader: true,
          ),
          (
            endpoint: orderReassignOpenidByPhoneEndpoint,
            method: 'POST',
            path: '/admin/order/reassignOpenidByPhone',
            permissionCode: 'order:operate',
            attachShopHeader: true,
          ),
          (
            endpoint: memberRechargeListEndpoint,
            method: 'GET',
            path: '/admin/member/recharge/list',
            permissionCode: 'user:view',
            attachShopHeader: true,
          ),
          (
            endpoint: reportDashboardEndpoint,
            method: 'GET',
            path: '/admin/report/dashboard',
            permissionCode: 'report:view',
            attachShopHeader: true,
          ),

        ];

    for (final contractCase in cases) {
      test('${contractCase.method} ${contractCase.path}', () {
        expect(contractCase.endpoint.method, contractCase.method);
        expect(contractCase.endpoint.path, contractCase.path);
        expect(
          contractCase.endpoint.permissionCode,
          contractCase.permissionCode,
        );
        expect(
          contractCase.endpoint.attachShopHeader,
          contractCase.attachShopHeader,
        );
      });
    }

    test('does not expose the nonexistent cashier order list path', () {
      expect(
        cases.map((contractCase) => contractCase.endpoint.path),
        isNot(contains('/cashier/order/list')),
      );
    });

    test('builds the formal order KDS rebuild endpoint', () {
      final endpoint = cashierOrderKdsDetailsEndpoint(9001);

      expect(endpoint.method, 'GET');
      expect(endpoint.path, '/cashier/orders/9001/details');
      expect(endpoint.permissionCode, 'cashier:operate');
      expect(endpoint.attachShopHeader, isTrue);
    });
  });
}
