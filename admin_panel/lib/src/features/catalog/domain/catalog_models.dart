class DishShopStock {
  const DishShopStock({
    required this.dishId,
    required this.shopId,
    required this.stock,
    required this.onsale,
    required this.soldOut,
  });

  final int dishId;
  final int shopId;
  final int stock;
  final bool onsale;
  final bool soldOut;

  factory DishShopStock.fromJson(Map<String, Object?> json) {
    return DishShopStock(
      dishId: _int(json['dish_id'] ?? json['dishId']),
      shopId: _int(json['shop_id'] ?? json['shopId']),
      stock: _int(json['stock']),
      onsale: _bool(json['onsale']),
      soldOut: _bool(json['sold_out'] ?? json['soldOut']),
    );
  }

  DishShopStock updateOnSale(bool value) {
    return DishShopStock(
      dishId: dishId,
      shopId: shopId,
      stock: stock,
      onsale: value,
      soldOut: soldOut,
    );
  }

  DishShopStock updateSoldOut(bool value) {
    return DishShopStock(
      dishId: dishId,
      shopId: shopId,
      stock: stock,
      onsale: onsale,
      soldOut: value,
    );
  }
}

class DashboardRevenue {
  const DashboardRevenue({
    required this.settAmount,
    required this.discountAmount,
    required this.serviceFee,
    required this.refundAmount,
    required this.payAmountGift,
  });

  final double settAmount;
  final double discountAmount;
  final double serviceFee;
  final double refundAmount;
  final double payAmountGift;

  double get businessRevenueNet {
    return settAmount -
        discountAmount +
        serviceFee -
        refundAmount -
        payAmountGift;
  }
}

class MemberRechargeFlow {
  const MemberRechargeFlow({
    required this.amount,
    required this.giftAmount,
    required this.status,
  });

  final double amount;
  final double giftAmount;
  final String status;

  bool get successful => status == 'success';
}

double successfulRechargeTotal(Iterable<MemberRechargeFlow> flows) {
  return flows
      .where((flow) => flow.successful)
      .fold<double>(0, (total, flow) => total + flow.amount + flow.giftAmount);
}

int _int(Object? value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse('$value') ?? 0;
}

bool _bool(Object? value) {
  if (value is bool) return value;
  if (value is num) return value != 0;
  return '$value' == 'true' || '$value' == '1';
}
