import 'package:analyzer_testing/analysis_rule/analysis_rule.dart';

/// Declarations added to the mock SDK and mock packages used by the tests.
///
/// The analyzer's mock SDK is a reduced approximation: it has no
/// `Iterable.last`, no `HttpClient`, no `dart:io` exceptions and no
/// `package:flutter`. The `unhandled_throws` rule recognises SDK members by
/// library URI and member name, so a fixture can only exercise it against
/// declarations that really live at those URIs. These helpers add exactly the
/// members the table names, with the same signatures as the real SDK.
extension MockSdkExtensions on AnalysisRuleTest {
  /// Adds the `dart:core`, `dart:async` and `dart:io` members the
  /// `unhandled_throws` table names but the mock SDK omits.
  ///
  /// Must be called after `super.setUp()`, which is what writes the mock SDK
  /// that this patches.
  void augmentMockSdk() {
    _patch(
      'core/core.dart',
      _iterableAdditions,
      into: 'abstract mixin class Iterable<E> {',
    );
    _append('core/core.dart', _coreLibraryAdditions);
    _patch(
      'core/core.dart',
      _numAdditions,
      into: 'sealed class num implements Comparable<num> {',
    );
    _patch(
      'core/core.dart',
      _dateTimeAdditions,
      into: 'class DateTime implements Comparable<DateTime> {',
    );
    _patch(
      'core/core.dart',
      _uriAdditions,
      into: 'abstract interface class Uri {',
    );
    _patch(
      'async/stream.dart',
      _streamAdditions,
      into: 'abstract mixin class Stream<T> {',
    );
    _patch(
      'async/async.dart',
      _futureAdditions,
      into: 'abstract interface class Future<T> {',
    );
    _append('async/async.dart', _asyncLibraryAdditions);
    _patch(
      'io/io.dart',
      _fileAdditions,
      into: 'abstract interface class File implements FileSystemEntity {',
    );
    _patch(
      'io/io.dart',
      _directoryAdditions,
      into: 'abstract interface class Directory implements FileSystemEntity {',
    );
    _patch(
      'io/io.dart',
      _fileSystemEntityAdditions,
      into: 'abstract class FileSystemEntity {',
    );
    _append('io/io.dart', _ioAdditions);
    _append('convert/convert.dart', _convertAdditions);
    _patch(
      'convert/convert.dart',
      _jsonCodecAdditions,
      into: 'final class JsonCodec {',
    );
  }

  /// Adds a `package:flutter` with the members the table names.
  ///
  /// Split across `services.dart` and `foundation.dart`, mirroring the real
  /// package, so that the cross-library exception lookup is exercised too.
  void addMockFlutter() {
    newPackage('flutter')
      ..addFile('lib/foundation.dart', _flutterFoundation)
      ..addFile('lib/services.dart', _flutterServices);
  }

  /// Inserts [addition] into the mock SDK file at [path], just after [into].
  void _patch(String path, String addition, {required String into}) {
    final file = getFile('${sdkRoot.path}/lib/$path');
    final content = file.readAsStringSync();
    final offset = content.indexOf(into);
    if (offset < 0) {
      throw StateError("Mock SDK '$path' no longer contains '$into'.");
    }
    final at = offset + into.length;
    newFile(
      file.path,
      '${content.substring(0, at)}\n$addition${content.substring(at)}',
    );
  }

  /// Appends [addition] to the mock SDK file at [path].
  void _append(String path, String addition) {
    final file = getFile('${sdkRoot.path}/lib/$path');
    newFile(file.path, '${file.readAsStringSync()}\n$addition');
  }
}

/// `Iterable` members the mock SDK omits.
const _iterableAdditions = r'''
  E get last;

  E get single;

  E reduce(E combine(E value, E element));
''';

/// `dart:core` top-level declarations the mock SDK omits.
const _coreLibraryAdditions = r'''
class StateError extends Error {
  StateError(String message);
}

class UriData {
  static UriData parse(String uri) => throw 0;
}
''';

/// `num` members the mock SDK omits.
const _numAdditions = r'''
  static num parse(String input);

  static num? tryParse(String input);
''';

/// `DateTime` members the mock SDK omits.
const _dateTimeAdditions = r'''
  static DateTime parse(String formattedString) => throw 0;
''';

/// `Uri` members the mock SDK omits.
const _uriAdditions = r'''
  static Uri parse(String uri, [int start = 0, int? end]) => throw 0;

  static Uri? tryParse(String uri, [int start = 0, int? end]) => throw 0;
''';

/// `dart:convert` declarations the mock SDK omits.
const _convertAdditions = r'''
Object? jsonDecode(
  String source, {
  Object? reviver(Object? key, Object? value)?,
}) => throw 0;
''';

/// `JsonCodec` members the mock SDK omits.
const _jsonCodecAdditions = r'''
  Object? decode(
    String source, {
    Object? reviver(Object? key, Object? value)?,
  }) => throw 0;
''';

/// `Stream` members the mock SDK omits.
const _streamAdditions = r'''
  Future<T> get last;

  Future<T> get single;

  Future<T> reduce(T combine(T previous, T element));

  Future<T> firstWhere(bool test(T element), {T orElse()?});

  Future<T> lastWhere(bool test(T element), {T orElse()?});

  Future<T> singleWhere(bool test(T element), {T orElse()?});

  Stream<T> timeout(Duration timeLimit, {void onTimeout(EventSink<T> sink)?});
''';

/// `Future` members the mock SDK omits.
const _futureAdditions = r'''
  Future<T> timeout(Duration timeLimit, {FutureOr<T> onTimeout()?});
''';

/// `dart:async` top-level declarations the mock SDK omits.
const _asyncLibraryAdditions = r'''
class TimeoutException implements Exception {
  TimeoutException(String message, [Duration? duration]);
}

abstract interface class EventSink<T> {}
''';

/// `dart:io` declarations the mock SDK omits.
///
/// Only the members the table names are declared, with `Object` stand-ins for
/// the types that do not matter to the rule.
const _ioAdditions = r'''
class FileSystemException implements Exception {
  FileSystemException([String message = '', String? path]);
}

class SocketException implements Exception {
  SocketException(String message);
}

class HandshakeException implements Exception {
  HandshakeException([String message = '']);
}

class ProcessException implements Exception {
  ProcessException(String executable, List<String> arguments);
}

class HttpException implements Exception {
  HttpException(String message);
}

class WebSocketException implements Exception {
  WebSocketException([String message = '']);
}

class RedirectException implements Exception {
  RedirectException(String message, List<Object> redirects);
}

abstract interface class WebSocket {
  static Future<WebSocket> connect(String url) => throw 0;
}

abstract interface class HttpClientRequest {
  Future<Object?> close();
}

abstract interface class HttpClient {
  factory HttpClient() => throw 0;

  Future<HttpClientRequest> getUrl(Uri url);

  Future<HttpClientRequest> postUrl(Uri url);

  Future<HttpClientRequest> open(
    String method,
    String host,
    int port,
    String path,
  );
}

abstract final class Process {
  static Future<Object?> run(String executable, List<String> arguments) =>
      throw 0;

  static Object? runSync(String executable, List<String> arguments) => throw 0;

  static Future<Object?> start(String executable, List<String> arguments) =>
      throw 0;
}
''';

/// `File` members the mock SDK omits.
const _fileAdditions = r'''
  Future<List<int>> readAsBytes();

  List<int> readAsBytesSync();

  Future<String> readAsString();

  String readAsStringSync();

  Future<File> writeAsString(String contents);

  Future<File> create({bool recursive = false});

  Future<int> length();
''';

/// `Directory` members the mock SDK omits.
const _directoryAdditions = r'''
  Future<Directory> create({bool recursive = false});

  Stream<FileSystemEntity> list({bool recursive = false});
''';

/// `FileSystemEntity` members the mock SDK omits.
const _fileSystemEntityAdditions = r'''
  Future<FileSystemEntity> delete({bool recursive = false});

  void deleteSync({bool recursive = false});

  Future<FileSystemEntity> rename(String newPath);
''';

/// A stand-in for `package:flutter/foundation.dart`.
const _flutterFoundation = r'''
class FlutterError extends Error {
  FlutterError(String message);
}
''';

/// A stand-in for `package:flutter/services.dart`.
const _flutterServices = r'''
import 'package:flutter/foundation.dart';

class PlatformException implements Exception {
  PlatformException({required String code});
}

class MissingPluginException implements Exception {
  MissingPluginException([String message = '']);
}

class MethodChannel {
  const MethodChannel(String name);

  Future<T?> invokeMethod<T>(String method, [Object? arguments]);

  Future<List<T>?> invokeListMethod<T>(String method, [Object? arguments]);
}

class OptionalMethodChannel extends MethodChannel {
  const OptionalMethodChannel(String name) : super(name);

  // Mirrors the real class, which overrides `invokeMethod` alone. The
  // inherited `invokeListMethod` still throws `MissingPluginException`, and
  // the tests rely on that difference.
  @override
  Future<T?> invokeMethod<T>(String method, [Object? arguments]);
}

abstract class AssetBundle {
  Future<String> loadString(String key, {bool cache = true});

  Future<Object?> load(String key);
}
''';
