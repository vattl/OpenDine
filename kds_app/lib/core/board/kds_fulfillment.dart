enum KdsFulfillmentChannel {
  dineIn('dine_in', '堂食'),
  takeout('takeout', '外卖配送'),
  pickup('pickup', '自提'),
  pack('pack', '打包'),
  delivery('delivery', '配送');

  const KdsFulfillmentChannel(this.mergeKey, this.displayLabel);

  final String mergeKey;
  final String displayLabel;
}

/// Canonical fulfillment parser used by both grouping and presentation.
abstract final class KdsFulfillment {
  static KdsFulfillmentChannel resolve(Map<String, dynamic> source) {
    final text = const [
      'dineInOrTakeOut',
      'dine_type',
      'dining_type',
      'dining_channel',
      'fulfillment_type',
      'delivery_type',
      'order_type',
    ]
        .map((key) => source[key]?.toString().trim().toLowerCase() ?? '')
        .join(' ');

    if (_flag(source['pickup_flag']) ||
        _flag(source['self_pickup_flag']) ||
        text.contains('自提') ||
        text.contains('到店取') ||
        text.contains('pickup') ||
        text.contains('self_pickup')) {
      return KdsFulfillmentChannel.pickup;
    }
    if (_flag(source['takeout_flag']) ||
        text.contains('外卖') ||
        text.contains('takeout') ||
        text.contains('takeaway')) {
      return KdsFulfillmentChannel.takeout;
    }
    if (text.contains('配送') || text.contains('delivery')) {
      return KdsFulfillmentChannel.delivery;
    }
    if (_flag(source['pack_flag']) ||
        text.contains('打包') ||
        text.contains('pack')) {
      return KdsFulfillmentChannel.pack;
    }
    return KdsFulfillmentChannel.dineIn;
  }

  static bool _flag(dynamic value) {
    if (value == true || value == 1) return true;
    final text = value?.toString().trim().toLowerCase();
    return text == '1' || text == 'true';
  }
}
