// pkgs/aq_security/lib/src/server/dos_protection/request_validator.dart
//
// Server-only. Request validation для защиты от DoS.
// Проверяет размер запроса, timeout, и другие параметры.

import 'dart:async';
import 'dart:convert';
import 'package:shelf/shelf.dart';

/// Request validation configuration
final class RequestValidationConfig {
  const RequestValidationConfig({
    this.maxBodySize = 10 * 1024 * 1024, // 10 MB
    this.maxHeaderSize = 8 * 1024, // 8 KB
    this.maxUrlLength = 2048,
    this.requestTimeout = 30, // 30 seconds
    this.allowedMethods = const ['GET', 'POST', 'PUT', 'DELETE', 'PATCH'],
    this.requireContentType = true,
  });

  /// Максимальный размер body в байтах
  final int maxBodySize;

  /// Максимальный размер headers в байтах
  final int maxHeaderSize;

  /// Максимальная длина URL
  final int maxUrlLength;

  /// Timeout для запроса в секундах
  final int requestTimeout;

  /// Разрешённые HTTP методы
  final List<String> allowedMethods;

  /// Требовать Content-Type для POST/PUT/PATCH
  final bool requireContentType;
}

/// Request validator
final class RequestValidator {
  RequestValidator({
    required this.config,
  });

  final RequestValidationConfig config;

  /// Валидировать запрос
  RequestValidationResult validate(Request request) {
    // 1. Проверить HTTP метод
    if (!config.allowedMethods.contains(request.method)) {
      return RequestValidationResult(
        valid: false,
        reason: 'Method ${request.method} not allowed',
        statusCode: 405,
      );
    }

    // 2. Проверить длину URL
    if (request.requestedUri.toString().length > config.maxUrlLength) {
      return RequestValidationResult(
        valid: false,
        reason: 'URL too long',
        statusCode: 414,
      );
    }

    // 3. Проверить размер headers
    final headersSize = _calculateHeadersSize(request.headers);
    if (headersSize > config.maxHeaderSize) {
      return RequestValidationResult(
        valid: false,
        reason: 'Headers too large',
        statusCode: 431,
      );
    }

    // 4. Проверить Content-Type для POST/PUT/PATCH
    if (config.requireContentType &&
        ['POST', 'PUT', 'PATCH'].contains(request.method)) {
      final contentType = request.headers['content-type'];
      if (contentType == null || contentType.isEmpty) {
        return RequestValidationResult(
          valid: false,
          reason: 'Content-Type required',
          statusCode: 400,
        );
      }
    }

    // 5. Проверить Content-Length
    final contentLength = request.headers['content-length'];
    if (contentLength != null) {
      final length = int.tryParse(contentLength);
      if (length != null && length > config.maxBodySize) {
        return RequestValidationResult(
          valid: false,
          reason: 'Request body too large',
          statusCode: 413,
        );
      }
    }

    return RequestValidationResult(
      valid: true,
      reason: null,
      statusCode: 200,
    );
  }

  /// Валидировать и читать body с ограничением размера
  Future<RequestBodyResult> validateAndReadBody(Request request) async {
    // Валидировать запрос
    final validation = validate(request);
    if (!validation.valid) {
      return RequestBodyResult(
        success: false,
        body: null,
        reason: validation.reason,
        statusCode: validation.statusCode,
      );
    }

    try {
      // Читать body с timeout
      final bodyBytes = await request.read()
          .timeout(
            Duration(seconds: config.requestTimeout),
            onTimeout: (sink) {
              sink.close();
              throw TimeoutException('Request timeout');
            },
          )
          .fold<List<int>>(
            [],
            (previous, element) {
              // Проверить размер на каждом chunk
              if (previous.length + element.length > config.maxBodySize) {
                throw Exception('Request body too large');
              }
              return previous..addAll(element);
            },
          );

      // Декодировать body
      final bodyString = utf8.decode(bodyBytes);

      return RequestBodyResult(
        success: true,
        body: bodyString,
        reason: null,
        statusCode: 200,
      );
    } on TimeoutException {
      return RequestBodyResult(
        success: false,
        body: null,
        reason: 'Request timeout',
        statusCode: 408,
      );
    } catch (e) {
      return RequestBodyResult(
        success: false,
        body: null,
        reason: e.toString(),
        statusCode: 400,
      );
    }
  }

  /// Вычислить размер headers
  int _calculateHeadersSize(Map<String, String> headers) {
    int size = 0;
    for (final entry in headers.entries) {
      size += entry.key.length + entry.value.length + 4; // ": " + "\r\n"
    }
    return size;
  }
}

/// Request validation result
final class RequestValidationResult {
  const RequestValidationResult({
    required this.valid,
    required this.reason,
    required this.statusCode,
  });

  final bool valid;
  final String? reason;
  final int statusCode;
}

/// Request body result
final class RequestBodyResult {
  const RequestBodyResult({
    required this.success,
    required this.body,
    required this.reason,
    required this.statusCode,
  });

  final bool success;
  final String? body;
  final String? reason;
  final int statusCode;
}

/// Middleware для request validation
Middleware requestValidationMiddleware({
  required RequestValidator validator,
}) {
  return (Handler handler) {
    return (Request request) async {
      // Валидировать запрос
      final result = validator.validate(request);

      if (!result.valid) {
        return Response(
          result.statusCode,
          body: jsonEncode({
            'error': 'validation_failed',
            'message': result.reason,
          }),
          headers: {'Content-Type': 'application/json'},
        );
      }

      return handler(request);
    };
  };
}
