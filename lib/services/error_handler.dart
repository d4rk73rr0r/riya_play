import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:riya_play/services/download_service.dart'
    show HttpStatusException, InsufficientStorageException;

/// What went wrong, in a shape the UI can act on.
enum ErrorType {
  network,
  timeout,
  unauthorized,
  forbidden,
  notFound,
  rateLimited,
  serverError,
  badRequest,
  storage,
  parse,
  unknown,
}

/// One classified failure: a technical [message] for the log and a
/// [userMessage] fit to put on screen, plus whether retrying can help.
class ErrorInfo {
  final ErrorType type;
  final String message;
  final String userMessage;
  final bool canRetry;
  final int? statusCode;
  final Duration? retryAfter;

  const ErrorInfo({
    required this.type,
    required this.message,
    required this.userMessage,
    required this.canRetry,
    this.statusCode,
    this.retryAfter,
  });

  @override
  String toString() => '$type($statusCode): $message';
}

/// Turns any thrown object into an [ErrorInfo].
///
/// The point is to stop each screen inventing its own wording — and to keep
/// a server answer distinct from a lost connection. Reporting "internet
/// aloqasi uzildi" for what was really an HTTP 404 sends the user to check
/// their Wi-Fi while the app retries something that can never succeed; the
/// downloader hit exactly that bug before this classification existed.
class ApiErrorHandler {
  static ErrorInfo handle(Object? error) {
    if (error is ErrorInfo) return error;

    if (error is InsufficientStorageException) {
      return ErrorInfo(
        type: ErrorType.storage,
        message: error.toString(),
        userMessage: error.toString(),
        canRetry: false,
      );
    }

    // Server javob berdi — bu tarmoq muammosi emas.
    if (error is HttpStatusException) {
      return _fromStatus(error.statusCode);
    }
    if (error is http.Response) {
      return _fromStatus(error.statusCode);
    }

    if (error is SocketException) {
      return const ErrorInfo(
        type: ErrorType.network,
        message: 'SocketException',
        userMessage: 'Internet aloqasi yo‘q. Ulanishni tekshiring.',
        canRetry: true,
      );
    }

    if (error is TimeoutException) {
      return const ErrorInfo(
        type: ErrorType.timeout,
        message: 'TimeoutException',
        userMessage: 'Ulanish juda sekin. Qaytadan urinib ko‘ring.',
        canRetry: true,
      );
    }

    if (error is http.ClientException || error is HttpException) {
      return ErrorInfo(
        type: ErrorType.network,
        message: error.toString(),
        userMessage: 'Server bilan bog‘lanib bo‘lmadi.',
        canRetry: true,
      );
    }

    if (error is FormatException) {
      return ErrorInfo(
        type: ErrorType.parse,
        message: error.toString(),
        userMessage: 'Serverdan noto‘g‘ri ma‘lumot keldi.',
        canRetry: false,
      );
    }

    return ErrorInfo(
      type: ErrorType.unknown,
      message: error?.toString() ?? 'null',
      userMessage: 'Kutilmagan xatolik yuz berdi.',
      canRetry: true,
    );
  }

  static ErrorInfo _fromStatus(int statusCode) {
    switch (statusCode) {
      case 400:
        return const ErrorInfo(
          type: ErrorType.badRequest,
          message: 'HTTP 400',
          userMessage: 'So‘rov noto‘g‘ri.',
          canRetry: false,
          statusCode: 400,
        );
      case 401:
        return const ErrorInfo(
          type: ErrorType.unauthorized,
          message: 'HTTP 401',
          userMessage: 'Sessiya muddati tugagan. Qaytadan kiring.',
          canRetry: false,
          statusCode: 401,
        );
      case 403:
        return const ErrorInfo(
          type: ErrorType.forbidden,
          message: 'HTTP 403',
          userMessage: 'Bu kontentga ruxsat yo‘q yoki havola muddati tugagan.',
          canRetry: false,
          statusCode: 403,
        );
      case 404:
      case 410:
        return ErrorInfo(
          type: ErrorType.notFound,
          message: 'HTTP $statusCode',
          userMessage: 'So‘ralgan ma‘lumot serverda topilmadi.',
          canRetry: false,
          statusCode: statusCode,
        );
      case 429:
        return const ErrorInfo(
          type: ErrorType.rateLimited,
          message: 'HTTP 429',
          userMessage: 'Juda ko‘p so‘rov. Biroz kutib urinib ko‘ring.',
          canRetry: true,
          retryAfter: Duration(seconds: 30),
          statusCode: 429,
        );
      case 500:
      case 502:
      case 503:
      case 504:
        return ErrorInfo(
          type: ErrorType.serverError,
          message: 'HTTP $statusCode',
          userMessage: 'Serverda muammo. Keyinroq urinib ko‘ring.',
          canRetry: true,
          statusCode: statusCode,
        );
      default:
        return ErrorInfo(
          type: ErrorType.unknown,
          message: 'HTTP $statusCode',
          userMessage: 'Noma‘lum xatolik ($statusCode).',
          canRetry: statusCode >= 500,
          statusCode: statusCode,
        );
    }
  }

  /// Shows the classified error, offering "Qayta urinish" only when a retry
  /// could actually change the outcome.
  static void showSnackBar(
    BuildContext context,
    Object? error, {
    VoidCallback? onRetry,
  }) {
    final info = handle(error);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(info.userMessage),
        action:
            (info.canRetry && onRetry != null)
                ? SnackBarAction(label: 'Qayta urinish', onPressed: onRetry)
                : null,
      ),
    );
  }
}
