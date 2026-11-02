import '../../../core/admin_api_client.dart';
import '../../../core/api_contract.dart';
import '../domain/admin_user.dart';
import '../domain/paged_users.dart';
import '../domain/user_query.dart';
import 'user_repository.dart';

class RealUserRepository implements UserRepository {
  const RealUserRepository(this.client);

  final AdminApiClient client;

  @override
  Future<PagedUsers> getUsers(UserQuery query, {required int shopId}) async {
    final data = await client
        .copyWith(shopId: shopId)
        .post(getUserInfoEndpoint, body: query.toRequestBody());
    final rows = objectList(
      data,
    ).map(AdminUser.fromJson).toList(growable: false);
    return PagedUsers(users: rows, total: totalFrom(data, rows.length));
  }
}
