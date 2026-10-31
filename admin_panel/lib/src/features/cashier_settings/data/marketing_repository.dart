import '../domain/marketing_models.dart';
import '../domain/cashier_settings.dart';

/// 营销配置仓库（M-G 营销配置）。
/// 覆盖首单返利/邀请海报/夜间九折配置、首单活动列表与详情、首单资格评估。
abstract interface class MarketingRepository {
  Future<CashierSettingsSectionData> loadRedemptions({
    int? campaignId,
    String? customerId,
    String? orderNo,
    int page = 1,
  });

  Future<MarketingInviteReward> loadInviteReward();

  Future<MarketingInviteReward> saveInviteReward({
    required bool enabled,
    required double rewardPercent,
  });

  Future<MarketingInvitePoster> loadInvitePoster();

  Future<MarketingInvitePoster> saveInvitePoster({
    required String backgroundPath,
    required int qrX,
    required int qrY,
    required int qrSize,
  });

  Future<MarketingNinefoldConfig> loadNinefold();

  Future<MarketingNinefoldConfig> saveNinefold(
    MarketingNinefoldConfig config);

  Future<List<MarketingCampaign>> loadCampaigns({String? status});

  Future<MarketingCampaign> loadCampaignDetail(int id);

  /// 创建首单活动，返回服务端分配 id 的完整活动（含 version=1）。
  Future<MarketingCampaign> createCampaign(MarketingCampaign campaign);

  /// 更新首单活动（乐观锁：提交体携带 version；409 版本/规则冲突抛异常）。
  Future<MarketingCampaign> updateCampaign(MarketingCampaign campaign);

  /// 轮播图列表（全部，banner:manage）。
  Future<List<MarketingBanner>> listBanners();

  /// 新增轮播图，返回服务端分配 bannerId 的完整对象。
  Future<MarketingBanner> addBanner(MarketingBanner banner);

  /// 删除轮播图。
  Future<void> deleteBanner({required int id});

  /// 更新轮播图（2.1.25 新增端点 PUT /admin/order/update_banners/{id}，支持快捷启用/禁用）。
  Future<void> updateBanner(MarketingBanner banner);

  /// 上传轮播图图片，返回服务端可访问相对路径（如 /image/avatar/{uuid}.png）。
  Future<String> uploadBannerImage({
    required List<int> bytes,
    required String filename,
  });

  /// 活动弹窗列表（全部，banner:manage 体系）。
  Future<List<MarketingPopup>> listPopups();

  /// 活动弹窗详情。
  Future<MarketingPopup> loadPopupDetail({required int id});

  /// 新增活动弹窗。
  Future<void> addPopup(MarketingPopup popup);

  /// 更新活动弹窗（全量提交，含 id）。
  Future<void> updatePopup(MarketingPopup popup);

  /// 删除活动弹窗。
  Future<void> deletePopup({required int id});

  Future<MarketingEligibilityResult> evaluateEligibility({
    required String customerId,
    double? orderAmount,
    int? shopId,
  });
}
