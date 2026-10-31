class ApiException implements Exception {
  ApiException(
    this.message, {
    this.code,
    this.statusCode,
    this.isNetworkError = false,
  });

  final String message;
  final int? code;
  final int? statusCode;
  final bool isNetworkError;

  bool get isUnauthorized => code == 401 || statusCode == 401;

  /// A gateway/service failure cannot prove whether a write reached the cloud
  /// authority. Callers must keep the original id and resolve/retry safely.
  bool get isTransientServiceFailure =>
      statusCode != null && statusCode! >= 500 && statusCode! < 600;

  @override
  String toString() => message;
}
