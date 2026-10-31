import '../../../core/admin_api_client.dart';
import '../../../core/api_contract.dart';
import '../domain/marketing_models.dart';
import '../domain/cashier_settings.dart';
import 'marketing_repository.dart';

/// 营销配置仓库实现（X-Shop-Id 由 client 注入）。
class RealMarketingRepository implements MarketingRepository {
  const RealMarketingRepository(this.client);

  final AdminApiClient client;

  @override
  Future<CashierSettingsSectionData> loadRedemptions({
    int? campaignId,
    String? customerId,
    String? orderNo,
    int page = 1,
  }) async {
    final response = await client.get(
      settingsFirstOrderRedemptionsEndpoint,
      query: {
        'page': page,
        'pageSize': 20,
        if (campaignId != null) 'campaignId': campaignId,
        if (customerId?.trim().isNotEmpty == true)
          'customerId': customerId!.trim(),
        if (orderNo?.trim().isNotEmpty == true) 'orderNo': orderNo!.trim(),
      },
    );
    return CashierSettingsSectionData.fromResponse(response);
  }

  @override
  Future<MarketingInviteReward> loadInviteReward() async {
    final response = await client.get(marketingInviteRewardEndpoint);
    return MarketingInviteReward.fromJson(_object(response));
  }

  @override
  Future<MarketingInviteReward> saveInviteReward({
    required bool enabled,
    required double rewardPercent,
  }) async {
    final response = await client.request(
      marketingInviteRewardSaveEndpoint,
      body: {'enabled': enabled, 'rewardPercent': rewardPercent},
    );
    return MarketingInviteReward.fromJson(_object(response));
  }

  @override
  Future<MarketingInvitePoster> loadInvitePoster() async {
    final response = await client.get(marketingInvitePosterEndpoint);
    return MarketingInvitePoster.fromJson(_object(response));
  }

  @override
  Future<MarketingInvitePoster> saveInvitePoster({
    required String backgroundPath,
    required int qrX,
    required int qrY,
    required int qrSize,
  }) async {
    final response = await client.request(
      marketingInvitePosterSaveEndpoint,
      body: {
        'backgroundPath': backgroundPath,
        'qr': {'x': qrX, 'y': qrY, 'size': qrSize},
      },
    );
    return MarketingInvitePoster.fromJson(_object(response));
  }

  @override
  Future<MarketingNinefoldConfig> loadNinefold() async {
    final response = await client.get(paymentNinefoldEndpoint);
    return MarketingNinefoldConfig.fromJson(_object(response));
  }

  @override
  Future<MarketingNinefoldConfig> saveNinefold(
    MarketingNinefoldConfig config,
  ) async {
    final response = await client.request(
      paymentNinefoldSaveEndpoint,
      body: config.toSaveJson(),
    );
    return MarketingNinefoldConfig.fromJson(_object(response));
  }

  @override
  Future<List<MarketingCampaign>> loadCampaigns({String? status}) async {
    final response = await client.get(
      marketingFirstOrderCampaignsEndpoint,
      query: {
        if (status != null && status.trim().isNotEmpty) 'status': status},
    );
    final raw = _extractList(response);
    return raw.map(MarketingCampaign.fromJson).toList(growable: false);
  }

  @override
  Future<MarketingCampaign> loadCampaignDetail(int id) async {
    final response =
        await client.get(marketingFirstOrderCampaignDetailEndpoint(id),
    );
    return MarketingCampaign.fromJson(_object(response));
  }

  @override
  Future<MarketingCampaign> createCampaign(
    MarketingCampaign campaign) async {
    if (campaign.name.trim().isEmpty) {
      throw ArgumentError('campaign name must not be empty');
    }
    final response = await client.post(
      marketingFirstOrderCampaignCreateEndpoint,
      body: campaign.toSaveJson(),
    );
    return MarketingCampaign.fromJson(_object(response));
  }

  @override
  Future<MarketingCampaign> updateCampaign(
    MarketingCampaign campaign) async {
    if (campaign.id == 0) throw ArgumentError('campaign id required');
    if (campaign.version == null) {
      throw ArgumentError('campaign version required for update');
    }
    final response = await client.request(
      marketingFirstOrderCampaignUpdateEndpoint(campaign.id),
      body: campaign.toSaveJson(includeVersion: true),
    );
    return MarketingCampaign.fromJson(_object(response));
  }

  @override
  Future<List<MarketingBanner>> listBanners() async {
    final response = await client.get(adminBannersEndpoint);
    final map = _object(response);
    final raw = map['banners'];
    if (raw is List) {
      return raw
          .whereType<Map>()
          .map((row) => MarketingBanner.fromJson(row.cast<String, Object?>()))
          .toList(growable: false);
    }
    return const [];
  }

  @override
  Future<MarketingBanner> addBanner(MarketingBanner banner) async {
    if (banner.image == null || banner.image!.trim().isEmpty) {
      throw ArgumentError('banner image must not be empty');
    }
    final response = await client.post(
      adminBannerAddEndpoint,
      body: banner.toSaveJson(),
    );
    final map = _object(response);
    if (map.isEmpty) return banner;
    return MarketingBanner(
      id: map['bannerId'] is num
          ? (map['bannerId'] as num).toInt()
          : banner.id,
      image: banner.image,
      url: banner.url,
      status: banner.status,
      type: banner.type,
    );
  }

  @override
  Future<void> deleteBanner({required int id}) async {
    await client.delete(adminBannerDeleteEndpoint(id));
  }

  @override
  Future<void> updateBanner(MarketingBanner banner) async {
    await client.put(adminBannerUpdateEndpoint(banner.id), body: banner.toSaveJson(),
    );
  }

  @override
  Future<String> uploadBannerImage({
    required List<int> bytes,
    required String filename,
  }) async {
    if (bytes.isEmpty) throw ArgumentError('banner image bytes must not be empty');
    final response = await client.postMultipart(
      adminBannerUploadEndpoint,
      files: {
        'file': (
          bytes: bytes,
          filename: filename,
          contentType: _imageContentType(filename),
        ),
      },
    );
    // 服务端 R.ok(relativePath) 把路径放进 msg 字段：{code:0, msg:'/image/avatar/x.png'}
    final map = _object(response);
    final path = map['msg'];
    if (path == null || '$path'.trim().isEmpty) {
      throw StateError('banner upload response missing image path');
    }
    return '$path';
  }

  @override
  Future<List<MarketingPopup>> listPopups() async {
    final response = await client.get(activityPopupListEndpoint);
    final raw = _object(response)['popup'];
    if (raw is List) {
      return raw
          .whereType<Map>()
          .map((row) => MarketingPopup.fromJson(row.cast<String, Object?>()))
          .toList(growable: false);
    }
    return const [];
  }

  @override
  Future<MarketingPopup> loadPopupDetail({required int id}) async {
    final response = await client.post(
      activityPopupDetailEndpoint,
      body: {'id': id},
    );
    final raw = _object(response)['popup'];
    if (raw is! Map) throw StateError('popup detail response missing popup');
    return MarketingPopup.fromJson(raw.cast<String, Object?>());
  }

  @override
  Future<void> addPopup(MarketingPopup popup) async {
    final name = popup.name?.trim() ?? '';
    final image = popup.popupImage?.trim() ?? '';
    if (name.isEmpty || image.isEmpty) {
      throw ArgumentError('popup name and image are required');
    }
    if (popup.startTime == null ||
        popup.startTime!.trim().isEmpty ||
        popup.endTime == null ||
        popup.endTime!.trim().isEmpty) {
      throw ArgumentError('popup start/end time are required');
    }
    await client.post(activityPopupAddEndpoint, body: popup.toSaveJson());
  }

  @override
  Future<void> updatePopup(MarketingPopup popup) async {
    if (popup.id == null) throw ArgumentError('popup id required');
    await client.post(activityPopupUpdateEndpoint, body: popup.toSaveJson());
  }

  @override
  Future<void> deletePopup({required int id}) async {
    await client.post(activityPopupDeleteEndpoint, body: {'id': id});
  }

  @override
  Future<MarketingEligibilityResult> evaluateEligibility({
    required String customerId,
    double? orderAmount,
    int? shopId,
  }) async {
    if (customerId.trim().isEmpty) {
      throw ArgumentError('customerId must not be empty');
    }
    final response = await client.post(
      marketingFirstOrderEligibilityEvaluateEndpoint,
      body: {
        'customerId': customerId.trim(),
        if (orderAmount != null) 'orderAmount': orderAmount,
        if (shopId != null) 'shopId': shopId,
      },
    );
    return MarketingEligibilityResult.fromJson(_object(response));
  }
}

Map<String, Object?> _object(Object? value) {
  if (value is Map<String, Object?>) return value;
  if (value is Map) return value.cast<String, Object?>();
  return const {};
}

String _imageContentType(String filename) {
  final lower = filename.toLowerCase();
  if (lower.endsWith('.jpg') || lower.endsWith('.jpeg')) return 'image/jpeg';
  if (lower.endsWith('.webp')) return 'image/webp';
  return 'image/png';
}

List<Map<String, Object?>> _extractList(Object? response) {
  if (response is List) {
    return response
        .whereType<Map>()
        .map((row) => row.cast<String, Object?>())
        .toList(growable: false);
  }
  if (response is Map) {
    final map = response.cast<String, Object?>();
    for (final key in const ['items', 'data', 'list', 'records']) {
      final raw = map[key];
      if (raw is List) {
        return raw
            .whereType<Map>()
            .map((row) => row.cast<String, Object?>())
            .toList(growable: false);
      }
    }
  }
  return const [];
}
