class AppVersionPolicyItem {
  const AppVersionPolicyItem({
    required this.id,
    required this.platform,
    required this.channel,
    required this.latest,
    required this.versionCode,
    this.minSupported,
    required this.forceUpdate,
    required this.packageType,
    required this.installMode,
    this.fileSize,
    this.sha256,
    this.grayShopIds,
    this.releaseNotes,
    this.downloadUrl,
    required this.enabled,
    this.updatedAt,
  });

  final int id;
  final String platform;
  final String channel;
  final String latest;
  final int versionCode;
  final String? minSupported;
  final bool forceUpdate;
  final String packageType;
  final String installMode;
  final int? fileSize;
  final String? sha256;
  final String? grayShopIds;
  final String? releaseNotes;
  final String? downloadUrl;
  final bool enabled;
  final String? updatedAt;

  factory AppVersionPolicyItem.fromJson(Map<String, dynamic> json) {
    return AppVersionPolicyItem(
      id: json['id'] is int ? json['id'] as int : int.tryParse(json['id']?.toString() ?? '0') ?? 0,
      platform: json['platform']?.toString() ?? 'windows',
      channel: json['channel']?.toString() ?? 'pos',
      latest: json['latest']?.toString() ?? '1.0.0',
      versionCode: json['version_code'] is int
          ? json['version_code'] as int
          : (json['versionCode'] is int
              ? json['versionCode'] as int
              : int.tryParse(json['version_code']?.toString() ?? json['versionCode']?.toString() ?? '0') ?? 0),
      minSupported: json['min_supported']?.toString() ?? json['minSupported']?.toString(),
      forceUpdate: json['force_update'] == 1 || json['forceUpdate'] == true || json['force_update'] == '1',
      packageType: json['package_type']?.toString() ?? json['packageType']?.toString() ?? 'full',
      installMode: json['install_mode']?.toString() ?? json['installMode']?.toString() ?? 'silent',
      fileSize: json['file_size'] is int
          ? json['file_size'] as int
          : (json['fileSize'] is int ? json['fileSize'] as int : int.tryParse(json['file_size']?.toString() ?? '')),
      sha256: json['sha256']?.toString(),
      grayShopIds: json['gray_shop_ids']?.toString() ?? json['grayShopIds']?.toString(),
      releaseNotes: json['release_notes']?.toString() ?? json['releaseNotes']?.toString(),
      downloadUrl: json['download_url']?.toString() ?? json['downloadUrl']?.toString(),
      enabled: json['enabled'] != 0 && json['enabled'] != false && json['enabled'] != '0',
      updatedAt: json['updated_at']?.toString() ?? json['updatedAt']?.toString(),
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'platform': platform,
    'channel': channel,
    'latest': latest,
    'version_code': versionCode,
    'min_supported': minSupported,
    'force_update': forceUpdate ? 1 : 0,
    'package_type': packageType,
    'install_mode': installMode,
    'file_size': fileSize,
    'sha256': sha256,
    'gray_shop_ids': grayShopIds,
    'release_notes': releaseNotes,
    'download_url': downloadUrl,
    'enabled': enabled ? 1 : 0,
    'updated_at': updatedAt,
  };
}

class SaveVersionPolicyRequest {
  const SaveVersionPolicyRequest({
    this.id,
    required this.platform,
    required this.channel,
    required this.latest,
    required this.versionCode,
    this.minSupported,
    required this.forceUpdate,
    required this.packageType,
    required this.installMode,
    this.fileSize,
    this.sha256,
    this.grayShopIds,
    this.releaseNotes,
    this.downloadUrl,
    required this.enabled,
  });

  final int? id;
  final String platform;
  final String channel;
  final String latest;
  final int versionCode;
  final String? minSupported;
  final bool forceUpdate;
  final String packageType;
  final String installMode;
  final int? fileSize;
  final String? sha256;
  final String? grayShopIds;
  final String? releaseNotes;
  final String? downloadUrl;
  final bool enabled;

  Map<String, dynamic> toJson() => {
    if (id != null && id! > 0) 'id': id,
    'platform': platform,
    'channel': channel,
    'latest': latest,
    'version_code': versionCode,
    'min_supported': minSupported,
    'force_update': forceUpdate ? 1 : 0,
    'package_type': packageType,
    'install_mode': installMode,
    'file_size': fileSize,
    'sha256': sha256,
    'gray_shop_ids': grayShopIds,
    'release_notes': releaseNotes,
    'download_url': downloadUrl,
    'enabled': enabled ? 1 : 0,
  };
}

class AppVersionUploadResult {
  const AppVersionUploadResult({
    required this.fileName,
    required this.storedFileName,
    required this.downloadUrl,
    required this.sha256,
    required this.fileSize,
    required this.packageType,
    this.platform,
    this.channel,
  });

  final String fileName;
  final String storedFileName;
  final String downloadUrl;
  final String sha256;
  final int fileSize;
  final String packageType;
  final String? platform;
  final String? channel;

  factory AppVersionUploadResult.fromJson(Map<String, dynamic> json) {
    return AppVersionUploadResult(
      fileName: json['fileName']?.toString() ?? json['file_name']?.toString() ?? '',
      storedFileName: json['storedFileName']?.toString() ?? json['stored_file_name']?.toString() ?? '',
      downloadUrl: json['downloadUrl']?.toString() ?? json['download_url']?.toString() ?? '',
      sha256: json['sha256']?.toString() ?? '',
      fileSize: (json['fileSize'] ?? json['file_size'] as num?)?.toInt() ?? 0,
      packageType: json['packageType']?.toString() ?? json['package_type']?.toString() ?? 'full',
      platform: json['platform']?.toString(),
      channel: json['channel']?.toString(),
    );
  }

  Map<String, dynamic> toJson() => {
    'fileName': fileName,
    'storedFileName': storedFileName,
    'downloadUrl': downloadUrl,
    'sha256': sha256,
    'fileSize': fileSize,
    'packageType': packageType,
    if (platform != null) 'platform': platform,
    if (channel != null) 'channel': channel,
  };
}
