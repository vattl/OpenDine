class TakeoutDeliverySnapshot {
  const TakeoutDeliverySnapshot({required this.delivery, this.tracking});

  final TakeoutDeliveryInfo delivery;
  final RiderTracking? tracking;

  factory TakeoutDeliverySnapshot.fromJson(Map<String, Object?> json) {
    final delivery = _map(json['delivery']) ?? json;
    final tracking = _map(json['tracking']);
    return TakeoutDeliverySnapshot(
      delivery: TakeoutDeliveryInfo.fromJson(delivery),
      tracking: tracking == null ? null : RiderTracking.fromJson(tracking),
    );
  }

  bool get hasAuthoritativeTrackingState =>
      tracking?.effectiveState.hasPhase == true;

  String get effectivePhase {
    final effective = tracking?.effectiveState.phase ?? '';
    if (effective.isNotEmpty) return effective;
    final compatible = tracking?.phase ?? '';
    return compatible.isNotEmpty ? compatible : delivery.zsqPhase;
  }

  String get receivingStatusLabel {
    final phase = effectivePhase;
    if (canRetryDispatch) return '叫骑手失败';
    if (hasAuthoritativeTrackingState) {
      return switch (phase) {
        'WAITING_RIDER' => '等待骑手接单',
        'TO_SHOP' => '骑手取货中',
        'TO_USER' => '骑手配送中',
        'DELIVERED' => '配送已完成',
        'CANCELLED' => '配送已取消',
        'ORDER_MISSING' => '配送订单已删除',
        _ => '状态同步中',
      };
    }
    if (isOrderMissing) return '配送订单已删除';
    if (_zsqDispatchStatus == 'rider_cancelled') return '骑手已取消';
    if (_zsqDispatchStatus == 'failed' ||
        _dispatchStatus == 'dispatch_failed') {
      return '叫骑手失败';
    }
    if (tracking?.isCancelled == true) return '配送已取消';
    if (tracking?.deliverySendStatus == 50) return '配送已完成';
    if (tracking?.deliverySendStatus == 80) return '骑手已到店';
    return switch (phase) {
      'WAITING_RIDER' => '等待骑手接单',
      'TO_SHOP' => '骑手赶往门店',
      'TO_USER' => '骑手配送中',
      'DELIVERED' => '配送已完成',
      'CANCELLED' => '配送已取消',
      _ => switch (tracking?.deliverySendStatus) {
        20 => '等待骑手接单',
        30 => '骑手赶往门店',
        40 => '骑手配送中',
        _ => switch (_zsqDispatchStatus) {
          'pending' => '等待骑手接单',
          'dispatched' => '骑手已接单',
          'completed' => '配送已完成',
          'cancelled' => '配送已取消',
          _ => '尚未叫骑手',
        },
      },
    };
  }

  bool get isOrderMissing {
    if (hasAuthoritativeTrackingState) return effectivePhase == 'ORDER_MISSING';
    return _zsqDispatchStatus == 'order_missing' ||
        delivery.zsqPhase == 'ORDER_MISSING' ||
        tracking?.phase == 'ORDER_MISSING';
  }

  bool get isCompleted {
    if (hasAuthoritativeTrackingState) return effectivePhase == 'DELIVERED';
    return _zsqDispatchStatus == 'completed' ||
        _dispatchStatus == 'completed' ||
        delivery.zsqPhase == 'DELIVERED' ||
        tracking?.phase == 'DELIVERED' ||
        tracking?.deliverySendStatus == 50;
  }

  bool get canRedispatch {
    if (hasAuthoritativeTrackingState) {
      return const {
        'DELIVERED',
        'CANCELLED',
        'ORDER_MISSING',
      }.contains(effectivePhase);
    }
    return const {
          'failed',
          'rider_cancelled',
          'cancelled',
          'order_missing',
          'completed',
        }.contains(_zsqDispatchStatus) ||
        _dispatchStatus == 'dispatch_failed' ||
        _dispatchStatus == 'cancelled' ||
        _dispatchStatus == 'completed' ||
        tracking?.isCancelled == true ||
        tracking?.deliverySendStatus == 50;
  }

  bool get canCancel {
    if (delivery.zsqOpenOrderId <= 0 || canRetryDispatch || !isActive) {
      return false;
    }
    final phase = effectivePhase;
    if (hasAuthoritativeTrackingState) {
      return const {'WAITING_RIDER', 'TO_SHOP', 'TO_USER'}.contains(phase);
    }
    return const {'pending', 'dispatched'}.contains(_zsqDispatchStatus) ||
        const {'accepted', 'delivering'}.contains(_dispatchStatus) ||
        const {'WAITING_RIDER', 'TO_SHOP', 'TO_USER'}.contains(phase);
  }

  bool get canRetryDispatch {
    if (_zsqDispatchStatus == 'failed') return true;
    if (_dispatchStatus != 'dispatch_failed') return false;
    return !const {
          'rider_cancelled',
          'cancelled',
          'order_missing',
          'completed',
        }.contains(_zsqDispatchStatus) &&
        !const {
          'CANCELLED',
          'ORDER_MISSING',
          'DELIVERED',
        }.contains(effectivePhase);
  }

  bool get isActive {
    if (canRetryDispatch) return false;
    final phase = effectivePhase;
    if (hasAuthoritativeTrackingState) {
      return const {
        'WAITING_RIDER',
        'TO_SHOP',
        'TO_USER',
        'UNKNOWN',
      }.contains(phase);
    }
    return !const {'DELIVERED', 'CANCELLED', 'ORDER_MISSING'}.contains(phase) &&
        tracking?.deliverySendStatus != 50 &&
        tracking?.isCancelled != true &&
        !const {
          'completed',
          'cancelled',
          'rider_cancelled',
          'order_missing',
        }.contains(_zsqDispatchStatus) &&
        _dispatchStatus != 'completed' &&
        _dispatchStatus != 'cancelled';
  }

  Duration? get trackingRefreshInterval {
    if (!isActive || delivery.zsqOpenOrderId <= 0) return null;
    return effectivePhase == 'UNKNOWN'
        ? const Duration(seconds: 60)
        : const Duration(seconds: 15);
  }

  String get currentCancelReason => effectivePhase == 'CANCELLED'
      ? tracking?.trajectoryState.cancelReason ?? ''
      : '';

  String get _dispatchStatus => tracking?.dispatchStatus.isNotEmpty == true
      ? tracking!.dispatchStatus
      : delivery.dispatchStatus;

  String get _zsqDispatchStatus =>
      tracking?.zsqDispatchStatus.isNotEmpty == true
      ? tracking!.zsqDispatchStatus
      : delivery.zsqDispatchStatus;

  TakeoutDeliverySnapshot asOrderMissing(String message) =>
      TakeoutDeliverySnapshot(
        delivery: delivery.asOrderMissing(message),
        tracking: const RiderTracking(phase: 'ORDER_MISSING'),
      );
}

class TakeoutDeliveryInfo {
  const TakeoutDeliveryInfo({
    this.dispatchStatus = '',
    this.zsqDispatchStatus = '',
    this.zsqPhase = '',
    this.zsqOpenOrderId = 0,
    this.zsqOrderId = '',
    this.receiverName = '',
    this.receiverPhone = '',
    this.address = '',
    this.userPosition,
    this.riderName = '',
    this.riderPhone = '',
    this.riderPosition,
    this.riderUpdatedAt = '',
    this.lastError = '',
    this.dispatchAttempts = 0,
  });

  final String dispatchStatus;
  final String zsqDispatchStatus;
  final String zsqPhase;
  final int zsqOpenOrderId;
  final String zsqOrderId;
  final String receiverName;
  final String receiverPhone;
  final String address;
  final GeoPoint? userPosition;
  final String riderName;
  final String riderPhone;
  final GeoPoint? riderPosition;
  final String riderUpdatedAt;
  final String lastError;
  final int dispatchAttempts;

  factory TakeoutDeliveryInfo.fromJson(Map<String, Object?> json) {
    return TakeoutDeliveryInfo(
      dispatchStatus: _string(
        json['dispatch_status'] ?? json['dispatchStatus'],
      ).toLowerCase(),
      zsqDispatchStatus: _string(
        json['zsq_dispatch_status'] ?? json['zsqDispatchStatus'],
      ).toLowerCase(),
      zsqPhase: _string(json['zsq_phase'] ?? json['zsqPhase']).toUpperCase(),
      zsqOpenOrderId: _int(json['zsq_open_order_id'] ?? json['zsqOpenOrderId']),
      zsqOrderId: _string(json['zsq_order_id'] ?? json['zsqOrderId']),
      receiverName: _string(json['receiver_name'] ?? json['receiverName']),
      receiverPhone: _string(json['receiver_phone'] ?? json['receiverPhone']),
      address: _string(json['address_full'] ?? json['addressFull']),
      userPosition: GeoPoint.tryParse(json['lat'], json['lng']),
      riderName: _string(json['zsq_rider_name'] ?? json['zsqRiderName']),
      riderPhone: _string(json['zsq_rider_phone'] ?? json['zsqRiderPhone']),
      riderPosition: GeoPoint.tryParse(
        json['zsq_rider_lat'] ?? json['zsqRiderLat'],
        json['zsq_rider_lng'] ?? json['zsqRiderLng'],
      ),
      riderUpdatedAt: _string(
        json['zsq_rider_updated_at'] ?? json['zsqRiderUpdatedAt'],
      ),
      lastError: _string(json['zsq_last_error'] ?? json['zsqLastError']),
      dispatchAttempts: _int(
        json['zsq_dispatch_attempts'] ?? json['zsqDispatchAttempts'],
      ),
    );
  }

  TakeoutDeliveryInfo asOrderMissing(String message) => TakeoutDeliveryInfo(
    dispatchStatus: 'dispatch_failed',
    zsqDispatchStatus: 'order_missing',
    zsqPhase: 'ORDER_MISSING',
    receiverName: receiverName,
    receiverPhone: receiverPhone,
    address: address,
    userPosition: userPosition,
    lastError: message,
    dispatchAttempts: dispatchAttempts,
  );
}

class RiderTracking {
  const RiderTracking({
    this.phase = '',
    this.deliverySendStatus,
    this.statusDescription = '',
    this.coordinateType = '',
    this.dispatchStatus = '',
    this.zsqDispatchStatus = '',
    this.rider,
    this.shop,
    this.user,
    this.platformDuration = '',
    this.platformDistance = '',
    this.toShopMinutes,
    this.toUserMinutes,
    this.riderToShopKm,
    this.riderToUserKm,
    this.effectiveState = const ZsqEffectiveState(),
    this.trajectoryState = const ZsqTrajectoryState(),
  });

  final String phase;
  final int? deliverySendStatus;
  final String statusDescription;
  final String coordinateType;
  final String dispatchStatus;
  final String zsqDispatchStatus;
  final RiderInfo? rider;
  final GeoPoint? shop;
  final GeoPoint? user;
  final String platformDuration;
  final String platformDistance;
  final int? toShopMinutes;
  final int? toUserMinutes;
  final double? riderToShopKm;
  final double? riderToUserKm;
  final ZsqEffectiveState effectiveState;
  final ZsqTrajectoryState trajectoryState;

  factory RiderTracking.fromJson(Map<String, Object?> json) {
    final riderJson = _map(json['rider']);
    final shopJson = _map(json['shop']);
    final userJson = _map(json['user']);
    final platformEta = _map(json['platformEta'] ?? json['platform_eta']);
    final computedEta = _map(json['computedEta'] ?? json['computed_eta']);
    final trajectoryState = _map(
      json['trajectoryState'] ?? json['trajectory_state'],
    );
    final effectiveState = _map(
      json['effectiveState'] ?? json['effective_state'],
    );
    return RiderTracking(
      phase: _string(json['phase']).toUpperCase(),
      deliverySendStatus: _nullableInt(
        json['deliverySendStatus'] ?? json['delivery_send_status'],
      ),
      statusDescription: _string(
        json['deliverySendStatusDesc'] ?? json['delivery_send_status_desc'],
      ),
      coordinateType: _string(
        json['coordinateType'] ?? json['coordinate_type'],
      ).toLowerCase(),
      dispatchStatus: _string(
        json['dispatchStatus'] ?? json['dispatch_status'],
      ).toLowerCase(),
      zsqDispatchStatus: _string(
        json['zsqDispatchStatus'] ?? json['zsq_dispatch_status'],
      ).toLowerCase(),
      rider: riderJson == null ? null : RiderInfo.fromJson(riderJson),
      shop: shopJson == null ? null : GeoPoint.tryParseJson(shopJson),
      user: userJson == null ? null : GeoPoint.tryParseJson(userJson),
      platformDuration: _string(platformEta?['durationText']),
      platformDistance: _string(platformEta?['distanceText']),
      toShopMinutes: _nullableInt(computedEta?['toShopMinutes']),
      toUserMinutes: _nullableInt(computedEta?['toUserMinutes']),
      riderToShopKm: _nullableDouble(computedEta?['riderToShopKm']),
      riderToUserKm: _nullableDouble(computedEta?['riderToUserKm']),
      effectiveState: effectiveState == null
          ? const ZsqEffectiveState()
          : ZsqEffectiveState.fromJson(effectiveState),
      trajectoryState: trajectoryState == null
          ? const ZsqTrajectoryState()
          : ZsqTrajectoryState.fromJson(trajectoryState),
    );
  }

  String get effectivePhase =>
      effectiveState.hasPhase ? effectiveState.phase : phase;

  String get effectiveStatusDescription =>
      effectiveState.statusDescription.isNotEmpty
      ? effectiveState.statusDescription
      : statusDescription;

  bool get isCancelled => effectiveState.hasPhase
      ? effectiveState.phase == 'CANCELLED'
      : deliverySendStatus == 60 || trajectoryState.indicatesCancellation;

  GeoPoint? get activeRiderPosition =>
      const {'TO_SHOP', 'TO_USER'}.contains(effectivePhase)
      ? rider?.position
      : null;

  String get etaText {
    final platform = [
      platformDuration,
      platformDistance,
    ].where((value) => value.isNotEmpty).join(' · ');
    if (platform.isNotEmpty) return platform;
    final toUser = effectivePhase == 'TO_USER';
    final minutes = toUser ? toUserMinutes : toShopMinutes;
    final distance = toUser ? riderToUserKm : riderToShopKm;
    return [
      if (minutes != null) '$minutes分钟',
      if (distance != null) '${distance.toStringAsFixed(1)}公里',
    ].join(' · ');
  }
}

class ZsqEffectiveState {
  const ZsqEffectiveState({
    this.sendStatus,
    this.statusDescription = '',
    this.phase = '',
    this.source = '',
    this.effectiveLogId,
    this.parentOrderNo = '',
    this.thirdPartyOrderNo = '',
    this.updatedAt = '',
  });

  final int? sendStatus;
  final String statusDescription;
  final String phase;
  final String source;
  final int? effectiveLogId;
  final String parentOrderNo;
  final String thirdPartyOrderNo;
  final String updatedAt;

  bool get hasPhase => phase.isNotEmpty;

  factory ZsqEffectiveState.fromJson(Map<String, Object?> json) =>
      ZsqEffectiveState(
        sendStatus: _nullableInt(json['sendStatus'] ?? json['send_status']),
        statusDescription: _string(json['statusDesc'] ?? json['status_desc']),
        phase: _string(json['phase']).toUpperCase(),
        source: _string(json['source']).toUpperCase(),
        effectiveLogId: _nullableInt(
          json['effectiveLogId'] ?? json['effective_log_id'],
        ),
        parentOrderNo: _string(
          json['parentOrderNo'] ?? json['parent_order_no'],
        ),
        thirdPartyOrderNo: _string(
          json['thirdPartyOrderNo'] ?? json['third_party_order_no'],
        ),
        updatedAt: _string(json['updatedAt'] ?? json['updated_at']),
      );
}

class RiderInfo {
  const RiderInfo({
    this.name = '',
    this.phone = '',
    this.position,
    this.locationLogId,
    this.locationUpdatedAt = '',
  });

  final String name;
  final String phone;
  final GeoPoint? position;
  final int? locationLogId;
  final String locationUpdatedAt;

  factory RiderInfo.fromJson(Map<String, Object?> json) => RiderInfo(
    name: _string(json['name']),
    phone: _string(json['phone']),
    position: GeoPoint.tryParse(json['lat'], json['lng']),
    locationLogId: _nullableInt(
      json['locationLogId'] ?? json['location_log_id'],
    ),
    locationUpdatedAt: _string(
      json['locationUpdatedAt'] ?? json['location_updated_at'],
    ),
  );
}

class ZsqTrajectoryState {
  const ZsqTrajectoryState({
    this.callbackStatus = '',
    this.orderStatus = '',
    this.previousOrderStatus = '',
    this.deliveryStatus = '',
    this.cancelReason = '',
    this.latestStatusLogId,
    this.statusUpdatedAt = '',
  });

  final String callbackStatus;
  final String orderStatus;
  final String previousOrderStatus;
  final String deliveryStatus;
  final String cancelReason;
  final int? latestStatusLogId;
  final String statusUpdatedAt;

  factory ZsqTrajectoryState.fromJson(
    Map<String, Object?> json,
  ) => ZsqTrajectoryState(
    callbackStatus: _string(json['callbackStatus'] ?? json['callback_status']),
    orderStatus: _string(json['orderStatus'] ?? json['order_status']),
    previousOrderStatus: _string(
      json['previousOrderStatus'] ?? json['previous_order_status'],
    ),
    deliveryStatus: _string(json['deliveryStatus'] ?? json['delivery_status']),
    cancelReason: _string(json['cancelReason'] ?? json['cancel_reason']),
    latestStatusLogId: _nullableInt(
      json['latestStatusLogId'] ?? json['latest_status_log_id'],
    ),
    statusUpdatedAt: _string(
      json['statusUpdatedAt'] ?? json['status_updated_at'],
    ),
  );

  bool get indicatesCancellation =>
      cancelReason.isNotEmpty ||
      callbackStatus.contains('取消配送单') ||
      deliveryStatus.contains('取消') ||
      orderStatus.contains('取消') ||
      orderStatus.contains('异常单');
}

class GeoPoint {
  const GeoPoint({
    required this.latitude,
    required this.longitude,
    this.address = '',
  });

  final double latitude;
  final double longitude;
  final String address;

  static GeoPoint? tryParseJson(Map<String, Object?> json) => tryParse(
    json['lat'],
    json['lng'],
    address: _string(json['address'] ?? json['addressDetail']),
  );

  static GeoPoint? tryParse(Object? lat, Object? lng, {String address = ''}) {
    final latitude = _nullableDouble(lat);
    final longitude = _nullableDouble(lng);
    if (latitude == null || longitude == null) return null;
    if (latitude.abs() > 90 || longitude.abs() > 180) return null;
    return GeoPoint(latitude: latitude, longitude: longitude, address: address);
  }
}

Map<String, Object?>? _map(Object? value) =>
    value is Map ? value.cast<String, Object?>() : null;

String _string(Object? value) => value == null ? '' : '$value'.trim();

int _int(Object? value) => _nullableInt(value) ?? 0;

int? _nullableInt(Object? value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse('$value');
}

double? _nullableDouble(Object? value) {
  if (value is num) return value.toDouble();
  return double.tryParse('$value');
}
