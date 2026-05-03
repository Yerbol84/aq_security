// lib/middleware/error_handler.dart
//
// Global error handling middleware

import 'dart:convert';
import 'package:shelf/shelf.dart';

/// Global error handler middleware
///
/// Catches all unhandled exceptions and returns proper error responses
Middleware errorHandlerMiddleware() {
  return (Handler handler) {
    return (Request request) async {
      try {
        return await handler(request);
      } on FormatException catch (e) {
        // JSON parsing errors
        return Response.badRequest(
          body: jsonEncode({
            'error': 'Invalid JSON',
            'message': e.message,
          }),
          headers: {'Content-Type': 'application/json'},
        );
      } catch (error, stackTrace) {
        // Log error
        print('❌ Unhandled error:');
        print('   Request: ${request.method} ${request.url}');
        print('   Error: $error');
        print('   Stack trace:');
        print(stackTrace);

        // Return generic error response
        return Response.internalServerError(
          body: jsonEncode({
            'error': 'Internal Server Error',
            'message': 'An unexpected error occurred',
          }),
          headers: {'Content-Type': 'application/json'},
        );
      }
    };
  };
}
