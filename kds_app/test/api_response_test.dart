import 'package:flutter_test/flutter_test.dart';
import 'package:kds_app/core/api/api_exception.dart';
import 'package:kds_app/core/api/api_response.dart';

void main() {
  test('normalizeApiResponse rejects HTML', () {
    expect(
      () => normalizeApiResponse('<!DOCTYPE html><html><body>app</body></html>',
          path: '/kds/v2/bootstrap'),
      throwsA(isA<ApiException>()),
    );
  });

  test('readDeviceJson reads top-level device', () {
    final json = readDeviceJson({
      'code': 0,
      'device': {'id': 1, 'device_token': 'abc'},
    });
    expect(json['device_token'], 'abc');
  });

  test('readDeviceJson reads nested data.device', () {
    final json = readDeviceJson({
      'code': 0,
      'data': {
        'device': {'id': 2, 'device_token': 'xyz'},
      },
    });
    expect(json['device_token'], 'xyz');
  });

  test('formatHttpError maps 500 to readable Chinese', () {
    expect(
      formatHttpError(statusCode: 500, path: '/kds/v2/bootstrap'),
      contains('服务器内部错误(500)'),
    );
    expect(
      formatHttpError(
        statusCode: 500,
        path: '/kds/v2/bootstrap',
        data: {'msg': '数据库连接失败'},
      ),
      '数据库连接失败',
    );
  });
}
