import '../domain/paged_users.dart';
import '../domain/user_query.dart';

abstract class UserRepository {
  Future<PagedUsers> getUsers(UserQuery query, {required int shopId});
}
