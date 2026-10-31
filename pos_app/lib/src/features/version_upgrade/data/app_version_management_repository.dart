import 'dart:convert';
import 'package:http/http.dart' as http;

import '../../../core/admin_api_client.dart';
import '../../../core/api_contract.dart';
import '../domain/app_version_info.dart';
import '../domain/app_version_management_model.dart';
import 'app_version_service.dart';

abstract class AppVersionManagementRepository {
  Future<List<AppVersionPolicyItem>> fetchVersionList();
  Future<void> saveVersionPolicy(SaveVersionPolicyRequest req);
  Future<void> toggleVersionEnabled({required int id, required bool enabled});
  Future<void> deleteVersion(int id);
  Future<AppVersionUploadResult> uploadPackage({
    String? filePath,
    List<int>? fileBytes,
    required String fileName,
    String? platform,
    String? channel,
    void Function(int bytesSent, int totalBytes)? onProgress,
  });
  Future<AppVersionInfo> simulateUpgradeVerdict({
    required String platform,
    required String channel,
    required String currentVersion,
    int? currentVersionCode,
    int? shopId,
  });
  Future<Map<String, dynamic>> verifyDownloadUrl({
    required String downloadUrl,
    String? expectedSha256,
  });
}

class RealAppVersionManagementRepository implements AppVersionManagementRepository {
  const RealAppVersionManagementRepository({required this.client});

  final AdminApiClient client;

  @override
  Future<List<AppVersionPolicyItem>> fetchVersionList() async {
    final res = await client.get(adminAppVersionsEndpoint);
    if (res is List) {
      return res
          .whereType<Map<String, dynamic>>()
          .map(AppVersionPolicyItem.fromJson)
          .toList();
    }
    if (res is Map && res['data'] is List) {
      return (res['data'] as List)
          .whereType<Map<String, dynamic>>()
          .map(AppVersionPolicyItem.fromJson)
          .toList();
    }
    return const [];
  }

  @override
  Future<void> saveVersionPolicy(SaveVersionPolicyRequest req) async {
    await client.post(
      adminAppVersionSaveEndpoint,
      body: req.toJson(),
    );
  }

  @override
  Future<void> toggleVersionEnabled({
    required int id,
    required bool enabled,
  }) async {
    await client.post(
      adminAppVersionToggleEnabledEndpoint,
      query: {
        'id': id,
        'enabled': enabled ? 1 : 0,
      },
    );
  }

  @override
  Future<void> deleteVersion(int id) async {
    await client.delete(
      adminAppVersionDeleteEndpoint.withPathParams({'id': '$id'}),
    );
  }

  @override
  Future<AppVersionInfo> simulateUpgradeVerdict({
    required String platform,
    required String channel,
    required String currentVersion,
    int? currentVersionCode,
    int? shopId,
  }) async {
    final service = AppVersionService(client: client);
    return service.checkUpdate(
      platform: platform,
      channel: channel,
      currentVersion: currentVersion,
      versionCode: currentVersionCode,
      shopId: shopId,
    );
  }

  @override
  Future<AppVersionUploadResult> uploadPackage({
    String? filePath,
    List<int>? fileBytes,
    required String fileName,
    String? platform,
    String? channel,
    void Function(int bytesSent, int totalBytes)? onProgress,
  }) async {
    final base = client.baseUrl.trim().replaceAll(RegExp(r'/+$'), '');
    final uri = Uri.parse('$base${adminAppVersionUploadEndpoint.path}');
    final request = http.MultipartRequest('POST', uri);
    if (client.token != null && client.token!.isNotEmpty) {
      final token = client.token!.startsWith('Bearer ') ? client.token! : 'Bearer ${client.token}';
      request.headers['Authorization'] = token;
    }
    if (platform != null && platform.isNotEmpty) {
      request.fields['platform'] = platform;
    }
    if (channel != null && channel.isNotEmpty) {
      request.fields['channel'] = channel;
    }
    if (fileBytes != null && fileBytes.isNotEmpty) {
      request.files.add(
        http.MultipartFile.fromBytes('file', fileBytes, filename: fileName),
      );
    } else if (filePath != null && filePath.isNotEmpty) {
      request.files.add(
        await http.MultipartFile.fromPath('file', filePath, filename: fileName),
      );
    } else {
      throw Exception('缺少文件内容');
    }

    final streamedResponse = await request.send();
    final response = await http.Response.fromStream(streamedResponse);

    if (response.statusCode != 200) {
      throw Exception('上传失败 (HTTP ${response.statusCode}): ${response.body}');
    }

    final data = jsonDecode(utf8.decode(response.bodyBytes));
    if (data is Map && data['code'] != null && data['code'] != 0) {
      throw Exception(data['msg']?.toString() ?? '上传失败');
    }
    final rawData = data is Map && data['data'] != null ? data['data'] : data;
    return AppVersionUploadResult.fromJson(
      Map<String, dynamic>.from(rawData as Map),
    );
  }

  @override
  Future<Map<String, dynamic>> verifyDownloadUrl({
    required String downloadUrl,
    String? expectedSha256,
  }) async {
    final body = <String, dynamic>{
      'downloadUrl': downloadUrl,
    };
    if (expectedSha256 != null && expectedSha256.isNotEmpty) {
      body['expectedSha256'] = expectedSha256;
    }
    final res = await client.post(
      adminAppVersionVerifyUrlEndpoint,
      body: body,
    );
    if (res is Map) {
      return Map<String, dynamic>.from(res);
    }
    return {};
  }
}
