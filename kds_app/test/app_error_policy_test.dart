import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kds_app/core/api/api_exception.dart';
import 'package:kds_app/main.dart';

void main() {
  test('network and API failures are recoverable and must not exit the app',
      () {
    expect(isRecoverableAppError(ApiException('网关错误(502)')), isTrue);
    expect(isRecoverableAppError(TimeoutException('超时')), isTrue);
    expect(isRecoverableAppError(const SocketException('断开')), isTrue);
    expect(isRecoverableAppError(const HttpException('断开')), isTrue);
  });

  test('programming errors remain fatal', () {
    expect(isRecoverableAppError(StateError('unexpected')), isFalse);
  });
}
