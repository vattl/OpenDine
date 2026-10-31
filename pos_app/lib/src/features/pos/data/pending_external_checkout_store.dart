import '../domain/pos_models.dart';
import 'pending_external_checkout_store_stub.dart'
    if (dart.library.io) 'pending_external_checkout_store_io.dart'
    if (dart.library.html) 'pending_external_checkout_store_web.dart'
    as platform;

class PendingExternalCheckout {
  const PendingExternalCheckout({
    required this.orderNo,
    this.offlineChannel,
    this.combinedSettlement,
    this.confirmedChannels = const <String>{},
    this.readyForSubmission = false,
    this.collectionSessionId = '',
  });

  final String orderNo;
  final String? offlineChannel;
  final PosCheckoutSettlement? combinedSettlement;
  final Set<String> confirmedChannels;
  final bool readyForSubmission;
  final String collectionSessionId;

  Map<String, Object?> toJson() => {
    'order_no': orderNo,
    'offline_channel': offlineChannel,
    'confirmed_channels': confirmedChannels.toList(growable: false),
    'ready_for_submission': readyForSubmission,
    'collection_session_id': collectionSessionId,
    if (combinedSettlement case final settlement?)
      'combined_settlement': {
        'cash_minor': settlement.cashMinor,
        'cash_tender_minor': settlement.cashTenderMinor,
        'change_amount_minor': settlement.changeAmountMinor,
        'change_channel': settlement.changeChannel?.apiValue,
        'wechat_minor': settlement.wechatMinor,
        'alipay_minor': settlement.alipayMinor,
        'balance_minor': settlement.balanceMinor,
      },
  };

  factory PendingExternalCheckout.fromJson(Map<String, Object?> json) {
    final settlementJson = json['combined_settlement'];
    PosCheckoutSettlement? settlement;
    if (settlementJson is Map) {
      settlement = PosCheckoutSettlement(
        cashMinor: _integer(settlementJson['cash_minor']),
        cashTenderMinor: _integer(settlementJson['cash_tender_minor']),
        changeAmountMinor: _integer(settlementJson['change_amount_minor']),
        changeChannel: _changeChannel(settlementJson['change_channel']),
        wechatMinor: _integer(settlementJson['wechat_minor']),
        alipayMinor: _integer(settlementJson['alipay_minor']),
        balanceMinor: _integer(settlementJson['balance_minor']),
      );
    }
    return PendingExternalCheckout(
      orderNo: json['order_no']?.toString() ?? '',
      offlineChannel: json['offline_channel']?.toString(),
      combinedSettlement: settlement,
      confirmedChannels: {
        for (final value in json['confirmed_channels'] is List
            ? json['confirmed_channels'] as List
            : const [])
          '$value',
      },
      readyForSubmission: json['ready_for_submission'] == true,
      collectionSessionId: json['collection_session_id']?.toString() ?? '',
    );
  }

  static int _integer(Object? value) =>
      value is num ? value.round() : int.tryParse('$value') ?? 0;

  static PosChangeChannel? _changeChannel(Object? value) {
    final code = value?.toString();
    for (final channel in PosChangeChannel.values) {
      if (channel.apiValue == code) return channel;
    }
    return null;
  }
}

abstract interface class PendingExternalCheckoutStore {
  Future<PendingExternalCheckout?> read(String orderNo);

  Future<void> write(PendingExternalCheckout value);

  Future<void> clear(String orderNo);
}

PendingExternalCheckoutStore createPendingExternalCheckoutStore() =>
    platform.createPlatformPendingExternalCheckoutStore();
