import 'package:flutter/foundation.dart';
import 'package:logger/logger.dart';

/// Shared app-wide logger, replacing scattered `debugPrint` calls.
///
/// `debugPrint` still writes to the system log in release builds (it isn't
/// gated by [kReleaseMode] on its own), so every call site silently shipped
/// its debug output to production. Routing everything through one [Logger]
/// instance lets us turn that off in one place instead of 79 of them.
final appLogger = Logger(
  printer: PrettyPrinter(methodCount: 0, colors: false),
  level: kReleaseMode ? Level.nothing : Level.debug,
);
