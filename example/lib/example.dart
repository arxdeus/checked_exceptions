// Run `dart pub get && dart analyze` in this directory to see the rules fire.
//
// Expected output: exactly one warning per line marked "reported" below.
import 'package:checked_exceptions/checked_exceptions.dart';

/// Thrown by [loadConfig].
class ConfigError implements Exception;

/// A function that advertises what it can throw.
@Throws({ConfigError})
String loadConfig(String path) => path;

class GoodService {
  /// The exception is caught, so the call is not reported.
  String readOrDefault(String path) {
    try {
      return loadConfig(path);
    } on ConfigError {
      return '';
    }
  }

  /// The exception is propagated instead, which is also accepted.
  @Throws({ConfigError})
  String readOrRethrow(String path) => loadConfig(path);
}

class LeakyService {
  String read(String path) {
    // reported: unhandled_throws, ConfigError escapes silently.
    return loadConfig(path);
  }
}

class SuppressedService {
  String read(String path) {
    // Diagnostics are suppressed with the plugin name as a prefix.
    // ignore: checked_exceptions/unhandled_throws
    return loadConfig(path);
  }
}

class SwallowingService {
  // reported: empty_catch, the clause catches and does nothing. Note that
  // there is no comment *inside* the braces: a comment there is the
  // documented way to say the silence is deliberate, and would clear this.
  String read(String path) {
    try {
      return loadConfig(path);
    } on ConfigError {}
    return '';
  }

  /// Clean: a comment inside the braces documents the deliberate silence.
  String readIgnoringFailure(String path) {
    try {
      return loadConfig(path);
    } on ConfigError {
      // The default is genuinely fine here: a missing config is not an error.
    }
    return '';
  }
}
