class CashierKdsLanInterfaceAddress {
  const CashierKdsLanInterfaceAddress({
    required this.interfaceName,
    required this.address,
  });

  final String interfaceName;
  final String address;

  @override
  bool operator ==(Object other) =>
      other is CashierKdsLanInterfaceAddress &&
      other.interfaceName == interfaceName &&
      other.address == address;

  @override
  int get hashCode => Object.hash(interfaceName, address);
}

class CashierKdsLanBindingPolicy {
  const CashierKdsLanBindingPolicy._();

  static CashierKdsLanInterfaceAddress select(
    Iterable<CashierKdsLanInterfaceAddress> candidates, {
    String? configuredAddress,
  }) {
    final available = candidates
        .where((candidate) => isPrivateIpv4(candidate.address))
        .toList(growable: false);
    final configured = configuredAddress?.trim() ?? '';
    if (configured.isNotEmpty) {
      if (!isPrivateIpv4(configured)) {
        throw StateError('CASHIER_KDS_BIND_ADDRESS 必须是受信任的私网 IPv4 地址');
      }
      for (final candidate in available) {
        if (candidate.address == configured) return candidate;
      }
      throw StateError('CASHIER_KDS_BIND_ADDRESS 未绑定到本机活动网卡');
    }

    final trusted = available
        .where((candidate) => !_looksVirtual(candidate.interfaceName))
        .toList();
    if (trusted.isEmpty) {
      throw StateError(
        '未发现可信私网网卡；LAN KDS 代理未启动。若确需使用 VPN/虚拟网卡，请显式配置 CASHIER_KDS_BIND_ADDRESS',
      );
    }
    trusted.sort((left, right) {
      final subnet = privateIpv4Priority(
        left.address,
      ).compareTo(privateIpv4Priority(right.address));
      if (subnet != 0) return subnet;
      final name = left.interfaceName.compareTo(right.interfaceName);
      if (name != 0) return name;
      return left.address.compareTo(right.address);
    });
    return trusted.first;
  }

  static bool isPrivateIpv4(String address) {
    final parts = address.split('.').map(int.tryParse).toList();
    if (parts.length != 4 ||
        parts.any((part) => part == null || part < 0 || part > 255)) {
      return false;
    }
    final first = parts[0]!;
    final second = parts[1]!;
    return first == 10 ||
        (first == 172 && second >= 16 && second <= 31) ||
        (first == 192 && second == 168);
  }

  static int privateIpv4Priority(String address) {
    if (address.startsWith('192.168.')) return 0;
    final parts = address.split('.');
    if (parts.length == 4 && parts[0] == '172') {
      final second = int.tryParse(parts[1]) ?? 0;
      if (second >= 16 && second <= 31) return 1;
    }
    if (address.startsWith('10.')) return 2;
    return 3;
  }

  static bool _looksVirtual(String interfaceName) {
    final value = interfaceName.toLowerCase();
    return const [
      'vethernet',
      'docker',
      'hyper-v',
      'vmware',
      'virtualbox',
      'wsl',
      'tailscale',
      'zerotier',
      'wireguard',
      'vpn',
      'pseudo',
      'loopback',
      'tunnel',
      ' tap',
      ' tun',
    ].any(value.contains) ||
        value.startsWith('tap') ||
        value.startsWith('tun');
  }
}
