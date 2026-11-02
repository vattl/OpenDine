import '../../../core/admin_api_client.dart';
import '../../../core/api_contract.dart';
import '../domain/receivable_account_model.dart';

class ReceivableManagementRepository {
  const ReceivableManagementRepository(this.client);

  final AdminApiClient client;

  Future<List<ReceivableAccountModel>> fetchAccounts({
    String? status,
    String? keyword,
    int page = 1,
    int pageSize = 50,
  }) async {
    final query = <String, Object?>{
      'page': page,
      'pageSize': pageSize};
    if (status != null && status.isNotEmpty && status != 'ALL') {
      query['status'] = status;
    }
    if (keyword != null && keyword.trim().isNotEmpty) {
      query['keyword'] = keyword.trim();
    }
    final res = await client.get(
      adminReceivableAccountsEndpoint,
      query: query);
    if (res is Map) {
      final items = res['items'];
      if (items is List) {
        return items
            .whereType<Map<String, dynamic>>()
            .map(ReceivableAccountModel.fromJson)
            .toList();
      }
    }
    return const [];
  }

  Future<ReceivableAccountModel> createAccount(ReceivableAccountFormData form,
  ) async {
    final res = await client.post(
      adminReceivableAccountCreateEndpoint,
      body: form.toJson(),
    );
    if (res is Map && res['account'] is Map) {
      return ReceivableAccountModel.fromJson(
        Map<String, dynamic>.from(res['account'] as Map),
      );
    }
    throw const ApiException('创建授信账户失败，未返回账户数据');
  }

  Future<ReceivableAccountModel> updateAccount(int id, ReceivableAccountFormData form,
  ) async {
    final endpoint = adminReceivableAccountUpdateEndpoint.withPathParams({'id': id.toString(),
    });
    final res = await client.put(
      endpoint,
      body: form.toJson());
    if (res is Map && res['account'] is Map) {
      return ReceivableAccountModel.fromJson(
        Map<String, dynamic>.from(res['account'] as Map),
      );
    }
    throw const ApiException('更新授信账户失败，未返回账户数据');
  }

  Future<ReceivableAccountModel> updateAccountStatus(int id, String status,
  ) async {
    final endpoint = adminReceivableAccountStatusEndpoint.withPathParams({'id': id.toString(),
    });
    final res = await client.post(
      endpoint,
      body: {'status': status});
    if (res is Map && res['account'] is Map) {
      return ReceivableAccountModel.fromJson(
        Map<String, dynamic>.from(res['account'] as Map),
      );
    }
    throw const ApiException('切换状态失败，未返回账户数据');
  }

  Future<ReceivableAccountModel> closeAccount(int id) async {
    final endpoint = adminReceivableAccountCloseEndpoint.withPathParams({'id': id.toString(),
    });
    final res = await client.post(endpoint);
    if (res is Map && res['account'] is Map) {
      return ReceivableAccountModel.fromJson(
        Map<String, dynamic>.from(res['account'] as Map),
      );
    }
    throw const ApiException('关闭账户失败');
  }

  Future<Map<String, Object?>> deleteAccount(int id) async {
    final endpoint = adminReceivableAccountDeleteEndpoint.withPathParams({'id': id.toString(),
    });
    final res = await client.delete(endpoint);
    if (res is Map) {
      return Map<String, Object?>.from(res);
    }
    return {'deleted': true};
  }

  Future<List<ReceivableStatementItem>> fetchStatement(int id, {int limit = 100,
  }) async {
    final endpoint = adminReceivableAccountStatementEndpoint.withPathParams({'id': id.toString(),
    });
    final res = await client.get(
      endpoint,
      query: {'limit': limit});
    if (res is Map) {
      final items = res['items'];
      if (items is List) {
        return items
            .whereType<Map<String, dynamic>>()
            .map((e) => ReceivableStatementItem.fromJson(Map<String, dynamic>.from(e),
              ),
            )
            .toList();
      }
    }
    return const [];
  }

  Future<ReceivableAgingSummary> fetchAging() async {
    final res = await client.get(adminReceivableAgingEndpoint);
    if (res is Map && res['aging'] is Map) {
      return ReceivableAgingSummary.fromJson(
        Map<String, dynamic>.from(res['aging'] as Map),
      );
    }
    return const ReceivableAgingSummary();
  }

  Future<List<ReceivableClaimModel>> fetchClaims({
    int? accountId,
    String? status,
    int page = 1,
    int pageSize = 50,
  }) async {
    final query = <String, Object?>{
      'page': page,
      'pageSize': pageSize};
    if (accountId != null && accountId > 0) {
      query['accountId'] = accountId;
    }
    if (status != null && status.isNotEmpty && status != 'ALL') {
      query['status'] = status;
    }
    final res = await client.get(
      adminReceivableClaimsEndpoint,
      query: query);
    if (res is Map) {
      final items = res['items'];
      if (items is List) {
        return items
            .whereType<Map<String, dynamic>>()
            .map(ReceivableClaimModel.fromJson)
            .toList();
      }
    }
    return const [];
  }

  Future<Map<String, Object?>> collectClaim({
    required int claimId,
    required int amountFen,
    required String channel,
    required String requestId,
    String? note,
  }) async {
    int? drawerSessionId;
    if (channel == 'CASH') {
      final response = await client.get(cashierShiftCurrentEndpoint);
      final container = response is Map ? response : const {};
      final rawShift = container.containsKey('shift')
          ? container['shift']
          : container;
      final shift = rawShift is Map ? rawShift : const {};
      final id = int.tryParse(
        '${shift['drawerSessionId'] ?? shift['drawer_session_id']}',
      );
      final shopId = int.tryParse('${shift['shopId'] ?? shift['shop_id']}');
      final rawDrawer = container['drawer_session'];
      final drawer = rawDrawer is Map ? rawDrawer : const {};
      final activeId = int.tryParse('${drawer['id']}');
      final state = '${drawer['state'] ?? ''}'.toUpperCase();
      if (id == null ||
          id <= 0 ||
          activeId != id ||
          state != 'OPEN' ||
          client.shopId == null ||
          shopId != client.shopId) {
        throw StateError('当前门店未找到开放的钱箱会话，请先到日结页面开班后重试现金回款。');
      }
      drawerSessionId = id;
    }
    final endpoint = adminReceivableClaimCollectEndpoint.withPathParams({'id': claimId.toString(),
    });
    final res = await client.post(
      endpoint,
      body: {
        'amountFen': amountFen,
        'channel': channel,
        'requestId': requestId,
        if (drawerSessionId != null) 'drawerSessionId': drawerSessionId,
        if (note != null && note.trim().isNotEmpty) 'note': note.trim(),
      },
    );
    if (res is Map) {
      return Map<String, Object?>.from(res);
    }
    return {'collected': true};
  }

  Future<Map<String, Object?>> writeOffClaim({
    required int claimId,
    required String requestId,
    required String reason,
  }) async {
    final endpoint = adminReceivableClaimWriteOffEndpoint.withPathParams({'id': claimId.toString(),
    });
    final res = await client.post(
      endpoint,
      body: {
        'requestId': requestId,
        'reason': reason.trim()},
    );
    if (res is Map) {
      return Map<String, Object?>.from(res);
    }
    return {'writtenOff': true};
  }

  Future<Map<String, Object?>> reverseClaim({
    required int claimId,
    required String requestId,
    required String reason,
  }) async {
    final endpoint = adminReceivableClaimReverseEndpoint.withPathParams({'id': claimId.toString(),
    });
    final res = await client.post(
      endpoint,
      body: {
        'requestId': requestId,
        'reason': reason.trim()},
    );
    if (res is Map) {
      return Map<String, Object?>.from(res);
    }
    return {'reversed': true};
  }

  Future<void> verifyPassword({
    required String username,
    required String password,
  }) async {
    final account = username.trim();
    await client.post(
      adminLoginEndpoint,
      body: {
        'workNo': account,
        'userName': account,
        'password': password},
    );
  }
}
