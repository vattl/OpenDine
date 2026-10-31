import '../../../core/admin_api_client.dart';
import '../../../core/api_contract.dart';
import '../../version_upgrade/data/app_version_service.dart';

export '../../version_upgrade/data/app_version_service.dart';
export '../../version_upgrade/domain/app_version_info.dart';

class AppVersionPolicy {
  const AppVersionPolicy({
    required this.latest,
    required this.minSupported,
    required this.forceUpdate,
    this.releaseNotes,
    this.downloadUrl,
  });

  final String latest;
  final String minSupported;
  final bool forceUpdate;
  final String? releaseNotes;
  final String? downloadUrl;

  factory AppVersionPolicy.fromJson(Object? data) {
    final map = data is Map ? data.cast<String, Object?>() : const {};
    return AppVersionPolicy(
      latest: '${map['latest'] ?? ''}',
      minSupported: '${map['minSupported'] ?? ''}',
      forceUpdate: map['forceUpdate'] == true,
      releaseNotes: map['releaseNotes'] as String?,
      downloadUrl: map['downloadUrl'] as String?,
    );
  }
}

/// 版本比较结果（语义化版本逐段比较，不按字符串字典序）。
enum VersionStatus { belowMinSupported, forceUpdate, optionalUpdate, upToDate }

VersionStatus evaluateVersion(String current, AppVersionPolicy policy) {
  if (_compareSemver(current, policy.minSupported) < 0) {
    return VersionStatus.belowMinSupported;
  }
  if (_compareSemver(current, policy.latest) < 0) {
    return policy.forceUpdate
        ? VersionStatus.forceUpdate
        : VersionStatus.optionalUpdate;
  }
  return VersionStatus.upToDate;
}

/// 语义化版本逐段比较。返回负数=a<b，0=相等，正数=a>b。
/// 只比较数字段（忽略 +build 与预发布后缀，'2.0.1+202' 视为 2.0.1）。
int _compareSemver(String a, String b) {
  List<int> parts(String v) {
    final core = v.split('+').first.split('-').first;
    final segs = core.split('.');
    return List.generate(
      3,
      (i) => i < segs.length ? int.tryParse(segs[i]) ?? 0 : 0,
    );
  }

  final pa = parts(a);
  final pb = parts(b);
  for (var i = 0; i < 3; i++) {
    if (pa[i] != pb[i]) return pa[i] - pb[i];
  }
  return 0;
}

class AppVersionRepository {
  const AppVersionRepository(this.client);

  final AdminApiClient client;

  AppVersionService get service => AppVersionService(client: client);

  /// 查询版本策略。后端 404 表示当前平台/渠道未发布策略，返回 null。
  Future<AppVersionPolicy?> check({required String platform}) async {
    try {
      final data = await client.get(
        appVersionEndpoint,
        query: {'platform': platform, 'channel': 'mobile'},
      );
      return AppVersionPolicy.fromJson(data);
    } on ApiException catch (error) {
      if (error.statusCode == 404 || error.code == 404) return null;
      rethrow;
    }
  }
}
