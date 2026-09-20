// Run `dart analyze` in this directory to see `unhandled_throws` fire against
// the real Flutter SDK, the real `dart:io` and the real `dart:core`.
//
// NOTE: use `dart analyze`, not `flutter analyze`. `flutter analyze` drops
// diagnostics coming from a third-party analyzer plugin.
//
// NOTE: analyze this *file*, not the directory. `dart analyze lib/` drops
// plugin diagnostics too, so it reports none of the warnings below. This is
// long-standing analyzer behaviour, not something about these rules:
//
//   dart analyze lib/sdk_throws_example.dart
//
// Expected output: one `unhandled_throws` warning per line marked "reported"
// below, and nothing on the handled cases.
import 'dart:convert';
import 'dart:io';

import 'package:checked_exceptions/checked_exceptions.dart';
import 'package:flutter/services.dart';
import 'package:flutter/src/services/message_codec.dart';

// --- dart:core: parsing. ---

/// reported: `int.parse` may throw `FormatException`.
int parseAgeUnhandled(String raw) => int.parse(raw);

/// Clean: the exception is caught.
int parseAgeCaught(String raw) {
  try {
    return int.parse(raw);
  } on FormatException {
    return 0;
  }
}

/// Clean: the exception is propagated to the caller.
@Throws({FormatException})
int parseAgePropagated(String raw) => int.parse(raw);

/// Clean: `tryParse` reports failure with `null` instead of throwing.
int? parseAgeOrNull(String raw) => int.tryParse(raw);

/// reported: `Uri.parse` may throw `FormatException`.
Uri parseEndpointUnhandled(String raw) => Uri.parse(raw);

// --- dart:core: Iterable. ---
//
// Every member here throws a `StateError` or a `RangeError`, both of which
// are `Error`s reporting a bug in the calling code. `avoid_catching_errors`
// says not to catch those, so declaring them with `@Throws` would be
// contradictory advice and none of them is tabled.

/// Clean: `first` throws `StateError`.
int firstScore(List<int> scores) => scores.first;

/// Clean: `single` throws `StateError`.
int onlyScore(Iterable<int> scores) => scores.single;

/// Clean: `reduce` throws `StateError`.
int totalScore(Iterable<int> scores) => scores.reduce((a, b) => a + b);

/// Clean: `firstWhere` throws `StateError`.
int firstPositiveScore(List<int> scores) =>
    scores.firstWhere((score) => score > 0);

/// Clean: indexing throws `RangeError`.
int scoreAt(List<int> scores) => scores[0];

// --- dart:convert. ---

/// reported: `jsonDecode` may throw `FormatException`.
Object? decodeBodyUnhandled(String body) => jsonDecode(body);

/// Clean: caught as the supertype of `FormatException`.
Object? decodeBodyCaught(String body) {
  try {
    return jsonDecode(body);
  } on Exception {
    return null;
  }
}

// --- dart:io. ---

/// reported: `readAsString` may throw `FileSystemException`.
Future<String> readConfigUnhandled(File file) => file.readAsString();

/// Clean: the exception is caught.
Future<String> readConfigCaught(File file) async {
  try {
    return await file.readAsString();
  } on Object {
    return '';
  }
}

/// reported: `delete` may throw `FileSystemException`, inherited from
/// `FileSystemEntity`.
Future<void> deleteCacheUnhandled(Directory dir) async {
  await dir.delete(recursive: true);
}

/// reported: `Socket.connect` may throw `SocketException`.
Future<Socket> connectUnhandled(String host) => Socket.connect(host, 443);

/// reported: `getUrl` may throw both `SocketException` and `HttpException`.
Future<HttpClientRequest> fetchUnhandled(HttpClient client, Uri url) =>
    client.getUrl(url);

// --- package:flutter. ---

const MethodChannel _channel = MethodChannel('example');
const OptionalMethodChannel _optional = OptionalMethodChannel('example');

/// reported: may throw `PlatformException` and `MissingPluginException`.
Future<String?> platformNameUnhandled() =>
    _channel.invokeMethod<String>('getName');

/// Clean: both declared exceptions are caught.
Future<String?> platformNameCaught() async {
  try {
    return await _channel.invokeMethod<String>('getName');
  } on PlatformException {
    return null;
  } on MissingPluginException {
    return null;
  }
}

/// reported: only `PlatformException`, because an `OptionalMethodChannel`
/// answers a missing implementation with `null` rather than by throwing.
@Throws({PlatformException})
Future<String?> optionalPlatformNameUnhandled() =>
    _optional.invokeMethod<String>('getName');

/// Clean: catching `PlatformException` alone is enough here.
Future<String?> optionalPlatformNameCaught() async {
  try {
    return await _optional.invokeMethod<String>('getName');
  } on PlatformException {
    return null;
  }
}

// --- Not tabled. ---

/// Clean: a same-named member of a user class is not an SDK member.
class Money {
  static Money parse(String raw) => Money();
}

Money parseMoney(String raw) => Money.parse(raw);

/// Clean: a same-named getter of a user class is not an SDK member.
class Bag {
  int get first => 0;
}

int firstOfBag(Bag bag) => bag.first;

/// Clean: a same-named channel method of a user class is not an SDK member.
class FakeChannel {
  Future<T?> invokeMethod<T>(String method) async => null;
}

Future<Object?> fakeInvoke(FakeChannel channel) =>
    channel.invokeMethod<Object>('go');

// --- Deliberately excluded. ---
//
// These throw an `Error`, which by convention reports a bug at the call site
// rather than an exceptional condition. `avoid_catching_errors` says not to
// catch one, so nothing that throws an `Error` is tabled: the two rules would
// otherwise give opposite advice. Every line below must stay clean.

/// Clean: `elementAt` throws `RangeError`.
int scoreElementAt(List<int> scores) => scores.elementAt(0);

/// Clean: `jsonEncode` throws `JsonUnsupportedObjectError`.
String encodeBody(Object? value) => jsonEncode(value);

/// Clean: `tryParse` reports failure with `null`.
double? parsePriceOrNull(String raw) => double.tryParse(raw);

/// Clean: the `*Where` members throw `StateError`, with or without `orElse`.
int lastPositive(List<int> scores) => scores.lastWhere((score) => score > 0);

int onlyPositive(List<int> scores) => scores.singleWhere((score) => score > 0);

/// Clean: a tear-off names a member without calling it, so nothing runs.
int Function(String) parserTearOff() => int.parse;

/// Clean: `existsSync` reports absence with `false` rather than by throwing.
bool configExists(File file) => file.existsSync();
