import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../domain/takeout_delivery.dart';
import 'amap_tile_map.dart';
import '../../cashier_shell/presentation/cashier_tokens.dart';

class TakeoutDeliveryPanel extends StatelessWidget {
  const TakeoutDeliveryPanel({
    super.key,
    this.snapshot,
    this.errorMessage = '',
  });

  final TakeoutDeliverySnapshot? snapshot;
  final String errorMessage;

  @override
  Widget build(BuildContext context) {
    final current = snapshot;
    if (current == null) {
      return Container(
        key: const Key('takeout-rider-map'),
        height: 190,
        decoration: BoxDecoration(
          color: context.cashier.canvas,
          border: Border.all(color: context.cashier.border),
          borderRadius: BorderRadius.circular(12),
        ),
        alignment: Alignment.center,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.delivery_dining_outlined, size: 36),
            const SizedBox(height: 8),
            Text(
              errorMessage.isEmpty ? '尚未生成真省钱配送单' : '配送信息加载失败：$errorMessage',
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }
    final delivery = current.delivery;
    final tracking = current.tracking;
    final rider = tracking?.rider;
    final riderName = rider?.name.isNotEmpty == true
        ? rider!.name
        : delivery.riderName;
    final riderPhone = rider?.phone.isNotEmpty == true
        ? rider!.phone
        : delivery.riderPhone;
    final riderLocationUpdatedAt = rider?.locationUpdatedAt.isNotEmpty == true
        ? rider!.locationUpdatedAt
        : delivery.riderUpdatedAt;
    final trajectory = tracking?.trajectoryState;
    final riderPosition = tracking != null
        ? tracking.activeRiderPosition
        : const {'TO_SHOP', 'TO_USER'}.contains(current.effectivePhase)
        ? delivery.riderPosition
        : null;
    final map = Container(
      key: const Key('takeout-rider-map'),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: const Color(0xffedf2ec),
        border: Border.all(color: context.cashier.border),
        borderRadius: BorderRadius.circular(12),
      ),
      child: LayoutBuilder(
        builder: (context, _) => _DeliveryRoadMap(
          shop: tracking?.shop,
          user: tracking?.user ?? delivery.userPosition,
          rider: riderPosition,
        ),
      ),
    );
    final information = Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: context.cashier.surface,
        border: Border.all(color: context.cashier.border),
        borderRadius: BorderRadius.circular(12),
      ),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _DeliveryInfoLine(
              label: '配送状态',
              value: current.receivingStatusLabel,
            ),
            if (tracking?.effectiveStatusDescription.isNotEmpty == true)
              _DeliveryInfoLine(
                label: '真省钱状态',
                value: tracking!.effectiveStatusDescription,
              ),
            if (trajectory?.callbackStatus.isNotEmpty == true)
              _DeliveryInfoLine(
                label: '回传状态',
                value: trajectory!.callbackStatus,
              ),
            if (trajectory?.orderStatus.isNotEmpty == true)
              _DeliveryInfoLine(
                label: '平台订单状态',
                value: trajectory!.orderStatus,
              ),
            if (trajectory?.deliveryStatus.isNotEmpty == true)
              _DeliveryInfoLine(
                label: '平台配送状态',
                value: trajectory!.deliveryStatus,
              ),
            if (current.currentCancelReason.isNotEmpty)
              _DeliveryInfoLine(
                label: '取消原因',
                value: current.currentCancelReason,
                danger: true,
              ),
            _DeliveryInfoLine(
              label: '骑手',
              value: [
                riderName,
                riderPhone,
              ].where((value) => value.isNotEmpty).join('  '),
            ),
            if (riderLocationUpdatedAt.isNotEmpty)
              _DeliveryInfoLine(label: '骑手定位时间', value: riderLocationUpdatedAt),
            _DeliveryInfoLine(label: '预计送达', value: tracking?.etaText ?? ''),
            if (trajectory?.statusUpdatedAt.isNotEmpty == true)
              _DeliveryInfoLine(
                label: '状态更新时间',
                value: trajectory!.statusUpdatedAt,
              ),
            _DeliveryInfoLine(
              label: '真省钱单号',
              value: delivery.zsqOrderId.isNotEmpty
                  ? delivery.zsqOrderId
                  : delivery.zsqOpenOrderId > 0
                  ? '${delivery.zsqOpenOrderId}'
                  : '',
            ),
            _DeliveryInfoLine(
              label: '收货人',
              value: [
                delivery.receiverName,
                delivery.receiverPhone,
              ].where((value) => value.isNotEmpty).join('  '),
            ),
            _DeliveryInfoLine(label: '配送地址', value: delivery.address),
            if (delivery.lastError.isNotEmpty && !current.isOrderMissing)
              _DeliveryInfoLine(
                label: '最近异常',
                value: delivery.lastError,
                danger: true,
              ),
          ],
        ),
      ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            const Expanded(
              child: Text(
                '真省钱配送与骑手位置',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
              ),
            ),
            Text(
              '鼠标滚轮 / 双指缩放 · 自动加载道路详情',
              style: TextStyle(
                color: context.cashier.inkMuted,
                fontSize: 13,
              ),
            ),
          ],
        ),
        if (current.isOrderMissing) ...[
          const SizedBox(height: 10),
          Container(
            key: const Key('takeout-order-missing-alert'),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: context.cashier.warning.withValues(alpha: 0.12),
              border: Border.all(color: context.cashier.warning),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              children: [
                Icon(Icons.warning_amber_rounded, color: context.cashier.warning),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    '真省钱配送订单不存在或已删除，可重新下单配送',
                    style: TextStyle(
                      color: context.cashier.ink,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
        const SizedBox(height: 10),
        LayoutBuilder(
          builder: (context, constraints) {
            if (constraints.maxWidth < 800) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SizedBox(height: 400, child: map),
                  const SizedBox(height: 12),
                  information,
                ],
              );
            }
            return SizedBox(
              height: 440,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(flex: 7, child: map),
                  const SizedBox(width: 16),
                  Expanded(flex: 3, child: information),
                ],
              ),
            );
          },
        ),
      ],
    );
  }
}

class _DeliveryRoadMap extends StatelessWidget {
  const _DeliveryRoadMap({
    required this.shop,
    required this.user,
    required this.rider,
  });

  final GeoPoint? shop;
  final GeoPoint? user;
  final GeoPoint? rider;

  @override
  Widget build(BuildContext context) {
    final points = [shop, user, rider].whereType<GeoPoint>().toList();
    final fallback = CustomPaint(
      painter: _DeliveryMapPainter(
        shop: shop,
        user: user,
        rider: rider,
        ink: context.cashier.ink,
        inkMuted: context.cashier.inkMuted,
        danger: context.cashier.danger,
      ),
      child: const SizedBox.expand(),
    );
    if (points.isEmpty) return fallback;

    LatLng position(GeoPoint point) => LatLng(point.latitude, point.longitude);
    final routeTarget = user ?? shop;
    final markers = <Marker>[
      if (shop != null)
        _mapMarker(
          key: const Key('takeout-map-shop-marker'),
          point: position(shop!),
          label: '门店',
          color: context.cashier.ink,
          icon: Icons.store_rounded,
        ),
      if (user != null)
        _mapMarker(
          key: const Key('takeout-map-user-marker'),
          point: position(user!),
          label: '顾客',
          color: context.cashier.danger,
          icon: Icons.home_rounded,
        ),
      if (rider != null)
        _mapMarker(
          key: const Key('takeout-map-rider-marker'),
          point: position(rider!),
          label: '骑手',
          color: const Color(0xff168353),
          icon: Icons.delivery_dining_rounded,
        ),
    ];
    return Stack(
      fit: StackFit.expand,
      children: [
        FlutterMap(
          options: MapOptions(
            initialCameraFit: CameraFit.coordinates(
              coordinates: points.map(position).toList(),
              padding: const EdgeInsets.all(64),
              minZoom: 3,
              maxZoom: 17,
            ),
            minZoom: 3,
            maxZoom: 19,
            backgroundColor: const Color(0xffedf2ec),
            interactionOptions: const InteractionOptions(
              flags:
                  InteractiveFlag.drag |
                  InteractiveFlag.flingAnimation |
                  InteractiveFlag.pinchMove |
                  InteractiveFlag.pinchZoom |
                  InteractiveFlag.doubleTapZoom |
                  InteractiveFlag.doubleTapDragZoom |
                  InteractiveFlag.scrollWheelZoom,
              enableMultiFingerGestureRace: true,
              pinchZoomThreshold: 0.15,
              scrollWheelVelocity: 0.004,
            ),
          ),
          children: [
            TileLayer(
              urlTemplate: amapRoadTileUrlTemplate,
              subdomains: amapRoadTileSubdomains,
              userAgentPackageName: 'com.laofei.cashier',
              maxNativeZoom: 19,
              keepBuffer: 3,
              panBuffer: 1,
            ),
            if (rider != null && routeTarget != null)
              PolylineLayer(
                polylines: [
                  Polyline(
                    points: [position(rider!), position(routeTarget)],
                    color: const Color(0xff168353),
                    borderColor: Colors.white,
                    borderStrokeWidth: 2,
                    strokeWidth: 5,
                  ),
                ],
              ),
            MarkerLayer(markers: markers),
          ],
        ),
        Align(
          alignment: Alignment.bottomRight,
          child: Container(
            margin: const EdgeInsets.all(8),
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
            color: Colors.white.withValues(alpha: 0.86),
            child: Text(
              '高德地图 · GCJ-02',
              style: TextStyle(
                color: context.cashier.inkMuted,
                fontSize: 11,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Marker _mapMarker({
    required Key key,
    required LatLng point,
    required String label,
    required Color color,
    required IconData icon,
  }) => Marker(
    key: key,
    point: point,
    width: 74,
    height: 54,
    alignment: Alignment.bottomCenter,
    child: _DeliveryMapMarker(label: label, color: color, icon: icon),
  );
}

class _DeliveryMapMarker extends StatelessWidget {
  const _DeliveryMapMarker({
    required this.label,
    required this.color,
    required this.icon,
  });

  final String label;
  final Color color;
  final IconData icon;

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(6),
          boxShadow: const [
            BoxShadow(
              color: Color(0x26000000),
              blurRadius: 5,
              offset: Offset(0, 2),
            ),
          ],
        ),
        child: Text(
          label,
          style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800),
        ),
      ),
      Container(
        width: 28,
        height: 28,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white, width: 2),
        ),
        child: Icon(icon, color: Colors.white, size: 17),
      ),
    ],
  );
}

class _DeliveryInfoLine extends StatelessWidget {
  const _DeliveryInfoLine({
    required this.label,
    required this.value,
    this.danger = false,
  });

  final String label;
  final String value;
  final bool danger;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            color: context.cashier.inkMuted,
            fontSize: 12,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          value.isEmpty ? '—' : value,
          style: TextStyle(
            color: danger ? context.cashier.danger : context.cashier.ink,
            fontSize: 15,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    ),
  );
}

class _DeliveryMapPainter extends CustomPainter {
  const _DeliveryMapPainter({
    this.shop,
    this.user,
    this.rider,
    required this.ink,
    required this.inkMuted,
    required this.danger,
  });

  final GeoPoint? shop;
  final GeoPoint? user;
  final GeoPoint? rider;
  final Color ink;
  final Color inkMuted;
  final Color danger;

  @override
  void paint(Canvas canvas, Size size) {
    final roadPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.9)
      ..strokeWidth = 9
      ..strokeCap = StrokeCap.round;
    final minorRoadPaint = Paint()
      ..color = const Color(0xffd9e2d7)
      ..strokeWidth = 2;
    for (var i = 1; i < 5; i++) {
      final x = size.width * i / 5;
      final y = size.height * i / 5;
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), minorRoadPaint);
      canvas.drawLine(Offset(0, y), Offset(size.width, y), minorRoadPaint);
    }
    canvas.drawLine(
      Offset(size.width * 0.08, size.height * 0.82),
      Offset(size.width * 0.9, size.height * 0.16),
      roadPaint,
    );

    final points =
        <({GeoPoint point, String label, Color color, IconData icon})>[
          if (shop != null)
            (
              point: shop!,
              label: '门店',
              color: ink,
              icon: Icons.store,
            ),
          if (user != null)
            (
              point: user!,
              label: '顾客',
              color: danger,
              icon: Icons.home,
            ),
          if (rider != null)
            (
              point: rider!,
              label: '骑手',
              color: const Color(0xff168353),
              icon: Icons.delivery_dining,
            ),
        ];
    if (points.isEmpty) {
      _drawCenteredText(canvas, size, '等待骑手定位');
      return;
    }
    final minLat = points.map((item) => item.point.latitude).reduce(math.min);
    final maxLat = points.map((item) => item.point.latitude).reduce(math.max);
    final minLng = points.map((item) => item.point.longitude).reduce(math.min);
    final maxLng = points.map((item) => item.point.longitude).reduce(math.max);
    Offset project(GeoPoint point) {
      final lngRange = math.max(maxLng - minLng, 0.002);
      final latRange = math.max(maxLat - minLat, 0.002);
      return Offset(
        size.width * (0.15 + 0.7 * (point.longitude - minLng) / lngRange),
        size.height * (0.85 - 0.7 * (point.latitude - minLat) / latRange),
      );
    }

    if (rider != null && user != null) {
      canvas.drawLine(
        project(rider!),
        project(user!),
        Paint()
          ..color = const Color(0xff168353)
          ..strokeWidth = 3,
      );
    }
    for (final item in points) {
      final offset = project(item.point);
      canvas.drawCircle(offset, 14, Paint()..color = item.color);
      _drawIcon(canvas, offset, item.icon);
      _drawLabel(canvas, offset, item.label);
    }
  }

  void _drawIcon(Canvas canvas, Offset offset, IconData icon) {
    final painter = TextPainter(
      text: TextSpan(
        text: String.fromCharCode(icon.codePoint),
        style: TextStyle(
          fontFamily: icon.fontFamily,
          package: icon.fontPackage,
          color: Colors.white,
          fontSize: 18,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    painter.paint(canvas, offset - const Offset(9, 9));
  }

  void _drawLabel(Canvas canvas, Offset offset, String label) {
    final painter = TextPainter(
      text: TextSpan(
        text: label,
        style: TextStyle(
          color: ink,
          fontSize: 12,
          fontWeight: FontWeight.w800,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    painter.paint(canvas, offset + const Offset(17, -7));
  }

  void _drawCenteredText(Canvas canvas, Size size, String text) {
    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          color: inkMuted,
          fontSize: 15,
          fontWeight: FontWeight.w700,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    painter.paint(
      canvas,
      Offset(
        (size.width - painter.width) / 2,
        (size.height - painter.height) / 2,
      ),
    );
  }

  @override
  bool shouldRepaint(covariant _DeliveryMapPainter oldDelegate) =>
      oldDelegate.shop != shop ||
      oldDelegate.user != user ||
      oldDelegate.rider != rider;
}
