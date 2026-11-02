import 'admin_user.dart';

class PagedUsers {
  const PagedUsers({required this.users, required this.total});

  final List<AdminUser> users;
  final int total;
}
