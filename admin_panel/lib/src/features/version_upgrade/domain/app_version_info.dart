enum UpgradeType {
  none,
  optional,
  force;

  static UpgradeType fromString(String? value) {
    switch (value?.trim().toUpperCase()) {
      case 'FORCE':
        return UpgradeType.force;
      case 'OPTIONAL':
        return UpgradeType.optional;
      case 'NONE':
      default:
        return UpgradeType.none;
    }
  }

  String toWire() {
    switch (this) {
      case UpgradeType.force:
        return 'FORCE';
      case UpgradeType.optional:
        return 'OPTIONAL';
      case UpgradeType.none:
        return 'NONE';
    }
  }
}

enum InstallMode {
  silent,
  interactive,
  storeRedirect;

  static InstallMode fromString(String? value) {
    switch (value?.trim().toLowerCase()) {
      case 'silent':
        return InstallMode.silent;
      case 'interactive':
        return InstallMode.interactive;
      case 'store_redirect':
      case 'storeredirect':
        return InstallMode.storeRedirect;
      default:
        return InstallMode.interactive;
    }
  }

  String toWire() {
    switch (this) {
      case InstallMode.silent:
        return 'silent';
      case InstallMode.interactive:
        return 'interactive';
      case InstallMode.storeRedirect:
        return 'store_redirect';
    }
  }
}

class AppVersionInfo {
  const AppVersionInfo({
    required this.platform,
    required this.channel,
    required this.latest,
    this.versionCode,
    this.minSupported,
    this.forceUpdate = false,
    required this.hasUpdate,
    required this.upgradeType,
    required this.installMode,
    this.packageType,
    this.fileSize,
    this.sha256,
    this.releaseNotes,
    this.downloadUrl,
  });

  final String platform;
  final String channel;
  final String latest;
  final int? versionCode;
  final String? minSupported;
  final bool forceUpdate;
  final bool hasUpdate;
  final UpgradeType upgradeType;
  final InstallMode installMode;
  final String? packageType;
  final int? fileSize;
  final String? sha256;
  final String? releaseNotes;
  final String? downloadUrl;

  bool get isForceUpdate => upgradeType == UpgradeType.force;
  bool get isOptionalUpdate => upgradeType == UpgradeType.optional;
  bool get hasValidDownloadUrl => downloadUrl != null && downloadUrl!.trim().isNotEmpty;

  String get formattedFileSize {
    if (fileSize == null || fileSize! <= 0) return '';
    final bytes = fileSize!;
    if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(1)} KB';
    }
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  factory AppVersionInfo.fromJson(Object? data) {
    final map = data is Map ? data.cast<String, Object?>() : const <String, Object?>{};
    final rawUpgrade = map['upgradeType'] as String?;
    final rawInstall = map['installMode'] as String?;
    final forceUpdateBool = map['forceUpdate'] == true;
    final hasUpdateBool = map['hasUpdate'] == true;

    // 适配老接口无 hasUpdate/upgradeType 时的降级决断
    final resolvedUpgrade = rawUpgrade != null
        ? UpgradeType.fromString(rawUpgrade)
        : (hasUpdateBool ? (forceUpdateBool ? UpgradeType.force : UpgradeType.optional) : UpgradeType.none);

    return AppVersionInfo(
      platform: '${map['platform'] ?? ''}',
      channel: '${map['channel'] ?? ''}',
      latest: '${map['latest'] ?? ''}',
      versionCode: (map['versionCode'] as num?)?.toInt(),
      minSupported: map['minSupported'] as String?,
      forceUpdate: forceUpdateBool,
      hasUpdate: hasUpdateBool,
      upgradeType: resolvedUpgrade,
      installMode: InstallMode.fromString(rawInstall),
      packageType: map['packageType'] as String?,
      fileSize: (map['fileSize'] as num?)?.toInt(),
      sha256: map['sha256'] as String?,
      releaseNotes: map['releaseNotes'] as String?,
      downloadUrl: map['downloadUrl'] as String?,
    );
  }

  Map<String, Object?> toJson() => {
    'platform': platform,
    'channel': channel,
    'latest': latest,
    if (versionCode != null) 'versionCode': versionCode,
    if (minSupported != null) 'minSupported': minSupported,
    'forceUpdate': forceUpdate,
    'hasUpdate': hasUpdate,
    'upgradeType': upgradeType.toWire(),
    'installMode': installMode.toWire(),
    if (packageType != null) 'packageType': packageType,
    if (fileSize != null) 'fileSize': fileSize,
    if (sha256 != null) 'sha256': sha256,
    if (releaseNotes != null) 'releaseNotes': releaseNotes,
    if (downloadUrl != null) 'downloadUrl': downloadUrl,
  };
}
