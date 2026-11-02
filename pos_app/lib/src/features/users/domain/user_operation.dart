class UserOperation {
  const UserOperation({required this.label, required this.permissionCode});

  final String label;
  final String permissionCode;
}

const userOperations = [
  UserOperation(label: '充值', permissionCode: 'user:recharge'),
  UserOperation(label: '加积分', permissionCode: 'user:points'),
  UserOperation(label: '发券', permissionCode: 'coupon:manage'),
  UserOperation(label: '批量发券', permissionCode: 'coupon:manage'),
  UserOperation(label: '会员画像抽屉', permissionCode: 'user:view'),
];

List<UserOperation> visibleUserOperations(Set<String> permissions) {
  return userOperations
      .where((operation) => permissions.contains(operation.permissionCode))
      .toList(growable: false);
}
