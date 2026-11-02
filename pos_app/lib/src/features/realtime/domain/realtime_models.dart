class KdsDeviceSession {
  const KdsDeviceSession({
    required this.deviceToken,
    required this.screenTag,
    required this.shopId,
  });

  final String deviceToken;
  final String screenTag;
  final int shopId;

  Map<String, String> get headers => {'X-Kds-Device-Token': deviceToken};

  bool acceptsScreenTag(String value) => value == screenTag;
}

class KdsReconnectPlan {
  const KdsReconnectPlan({
    required this.wsPath,
    required this.incrementalSyncPath,
    required this.lastEventId,
  });

  final String wsPath;
  final String incrementalSyncPath;
  final int lastEventId;

  bool get requiresIncrementalSync => lastEventId > 0;
}

class TakeoutDeliveryAction {
  const TakeoutDeliveryAction({
    required this.label,
    required this.path,
    required this.requiresLiabilityPrompt,
  });

  final String label;
  final String path;
  final bool requiresLiabilityPrompt;
}

const refundTakeoutAction = TakeoutDeliveryAction(
  label: '外卖退款',
  path: '/admin/takeout/delivery/refund',
  requiresLiabilityPrompt: true,
);

const cancelDeliveryAction = TakeoutDeliveryAction(
  label: '取消配送',
  path: '/admin/takeout/delivery/cancel',
  requiresLiabilityPrompt: true,
);
