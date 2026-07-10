class AppException implements Exception {
  final String message;
  final int? statusCode;
  const AppException({required this.message, this.statusCode});
  @override String toString() => message;
}

class NetworkException extends AppException {
  const NetworkException() : super(message: 'No internet connection.');
}

class UnauthorizedException extends AppException {
  const UnauthorizedException()
      : super(message: 'Session expired. Please log in again.', statusCode: 401);
}

class ServerException extends AppException {
  const ServerException()
      : super(message: 'Server error. Please try again.', statusCode: 500);
}

class ValidationException extends AppException {
  const ValidationException(String msg) : super(message: msg, statusCode: 422);
}
