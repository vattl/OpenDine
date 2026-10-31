import 'package:admin_panel_flutter/src/features/kds_local/runtime/cashier_kds_lan_binding.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const physicalWifi = CashierKdsLanInterfaceAddress(
    interfaceName: 'Wi-Fi',
    address: '192.168.10.25',
  );
  const physicalEthernet = CashierKdsLanInterfaceAddress(
    interfaceName: 'Ethernet',
    address: '172.20.1.8',
  );
  const docker = CashierKdsLanInterfaceAddress(
    interfaceName: 'vEthernet (DockerNAT)',
    address: '10.0.75.1',
  );

  test('default binding selects a physical private interface', () {
    final selected = CashierKdsLanBindingPolicy.select(const [
      docker,
      physicalEthernet,
      physicalWifi,
    ]);

    expect(selected, physicalWifi);
  });

  test('default binding rejects virtual-only and public interfaces', () {
    expect(
      () => CashierKdsLanBindingPolicy.select(const [
        docker,
        CashierKdsLanInterfaceAddress(
          interfaceName: 'Ethernet',
          address: '203.0.113.8',
        ),
      ]),
      throwsA(isA<StateError>()),
    );
  });

  test('explicit binding may select an existing private VPN interface', () {
    final selected = CashierKdsLanBindingPolicy.select(const [
      CashierKdsLanInterfaceAddress(
        interfaceName: 'Tailscale',
        address: '10.10.10.2',
      ),
      physicalWifi,
    ], configuredAddress: '10.10.10.2');

    expect(selected.address, '10.10.10.2');
  });

  test('explicit binding fails closed for wildcard or absent addresses', () {
    expect(
      () => CashierKdsLanBindingPolicy.select(const [
        physicalWifi,
      ], configuredAddress: '0.0.0.0'),
      throwsA(isA<StateError>()),
    );
    expect(
      () => CashierKdsLanBindingPolicy.select(const [
        physicalWifi,
      ], configuredAddress: '192.168.10.99'),
      throwsA(isA<StateError>()),
    );
  });
}
