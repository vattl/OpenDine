import '../../../core/admin_api_client.dart';
import '../../../core/api_contract.dart';

/// 公告/通知。后端 v1.2.172 已支持 `announcement:view` 只读权限码。
/// 默认走真实接口；联调期可用 --dart-define=MOCK_ANNOUNCEMENT=true 回退 mock。
const kUseMockAnnouncement = bool.fromEnvironment(
  'MOCK_ANNOUNCEMENT',
  defaultValue: false,
);

class Announcement {
  const Announcement({
    required this.id,
    required this.title,
    required this.content,
    required this.publishedAt,
    this.read = false,
  });

  final int id;
  final String title;
  final String content;
  final String publishedAt;
  final bool read;

  factory Announcement.fromJson(Map<String, Object?> map) {
    final id = map['id'] ?? map['announcementId'];
    return Announcement(
      id: id is num ? id.toInt() : int.tryParse('$id') ?? 0,
      title: '${map['title'] ?? ''}',
      content: '${map['content'] ?? map['body'] ?? ''}',
      publishedAt:
          '${map['publishedAt'] ?? map['createdAt'] ?? map['createTime'] ?? ''}',
    );
  }
}

abstract class AnnouncementRepository {
  Future<List<Announcement>> list({int page = 1, int pageSize = 20});
  Future<Announcement?> get(int id);
}

class RealAnnouncementRepository implements AnnouncementRepository {
  const RealAnnouncementRepository(this.client);

  final AdminApiClient client;

  @override
  Future<List<Announcement>> list({int page = 1, int pageSize = 20}) async {
    final data = await client.get(
      announcementListEndpoint,
      query: {'page': page, 'pageSize': pageSize},
    );
    return objectList(data).map(Announcement.fromJson).toList();
  }

  @override
  Future<Announcement?> get(int id) async {
    final data = await client.get(
      announcementGetEndpoint,
      query: {'id': id},
    );
    if (data is Map) {
      return Announcement.fromJson(data.cast<String, Object?>());
    }
    return null;
  }
}

class MockAnnouncementRepository implements AnnouncementRepository {
  const MockAnnouncementRepository();

  static final _items = List.generate(
    8,
    (i) => Announcement(
      id: i + 1,
      title: '系统公告 ${i + 1}',
      content: '这是 mock 公告内容 ${i + 1}，待后端补 announcement:view 权限码后切换真实接口。',
      publishedAt: '2026-07-${28 - i} 10:00',
    ),
  );

  @override
  Future<List<Announcement>> list({int page = 1, int pageSize = 20}) async =>
      _items;

  @override
  Future<Announcement?> get(int id) async =>
      _items.where((a) => a.id == id).firstOrNull;
}
