import 'package:analyzer_testing/analysis_rule/analysis_rule.dart';
import 'package:checked_exceptions/src/rules/unhandled_throws.dart';
import 'package:test/test.dart';
import 'package:test_reflective_loader/test_reflective_loader.dart';

import 'src/annotations_source.dart';
import 'src/mock_sdk_extensions.dart';

void main() {
  defineReflectiveSuite(() {
    defineReflectiveTests(SdkThrowsTest);
  });
}

/// Imports shared by every fixture.
///
/// A fixture that needs only some of them still carries all of them, so
/// unused-import reports are suppressed once here rather than per fixture.
const _preamble = '''
// ignore_for_file: unused_import

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';

import 'package:checked_exceptions/checked_exceptions.dart';
''';

@reflectiveTest
class SdkThrowsTest extends AnalysisRuleTest {
  @override
  void setUp() {
    newPackage('checked_exceptions')
        .addFile('lib/checked_exceptions.dart', annotationsSource);
    addMockFlutter();
    rule = UnhandledThrowsRule();
    super.setUp();
    augmentMockSdk();
  }

  /// Asserts that [body], appended to the shared preamble, is clean.
  Future<void> assertClean(String body) =>
      assertNoDiagnostics('$_preamble\n$body');

  /// Asserts that [body] reports a lint on the last occurrence of [expression],
  /// naming every entry of [types].
  Future<void> assertReportsOn(
    String body,
    String expression, {
    List<String> types = const ['FormatException'],
  }) async {
    final content = '$_preamble\n$body';
    final offset = content.lastIndexOf(expression);
    expect(
      offset,
      isNonNegative,
      reason: "fixture contains no expression matching '$expression'",
    );
    await assertDiagnostics(content, [
      lint(offset, expression.length, messageContainsAll: types),
    ]);
  }

  // --- dart:core parsing. ---

  Future<void> test_reports_intParse() async {
    await assertReportsOn(r'''
int f(String s) => int.parse(s);
''', 'int.parse(s)');
  }

  Future<void> test_reports_doubleParse() async {
    await assertReportsOn(r'''
double f(String s) => double.parse(s);
''', 'double.parse(s)');
  }

  Future<void> test_reports_numParse() async {
    await assertReportsOn(r'''
num f(String s) => num.parse(s);
''', 'num.parse(s)');
  }

  Future<void> test_reports_bigIntParse() async {
    await assertReportsOn(r'''
BigInt f(String s) => BigInt.parse(s);
''', 'BigInt.parse(s)');
  }

  Future<void> test_reports_dateTimeParse() async {
    await assertReportsOn(r'''
DateTime f(String s) => DateTime.parse(s);
''', 'DateTime.parse(s)');
  }

  Future<void> test_reports_uriParse() async {
    await assertReportsOn(r'''
Uri f(String s) => Uri.parse(s);
''', 'Uri.parse(s)');
  }

  Future<void> test_reports_uriParseIPv6Address() async {
    await assertReportsOn(r'''
List<int> f(String s) => Uri.parseIPv6Address(s);
''', 'Uri.parseIPv6Address(s)');
  }

  Future<void> test_reports_uriDataParse() async {
    await assertReportsOn(r'''
UriData f(String s) => UriData.parse(s);
''', 'UriData.parse(s)');
  }

  // --- dart:convert. ---

  Future<void> test_reports_jsonDecode() async {
    await assertReportsOn(r'''
Object? f(String s) => jsonDecode(s);
''', 'jsonDecode(s)');
  }

  Future<void> test_reports_jsonCodecDecode() async {
    await assertReportsOn(r'''
Object? f(String s) => json.decode(s);
''', 'json.decode(s)');
  }

  Future<void> test_reports_futureTimeout() async {
    await assertReportsOn(
      r'''
Future<int> f(Future<int> value) async =>
    await value.timeout(const Duration(seconds: 1));
''',
      'value.timeout(const Duration(seconds: 1))',
      types: ['TimeoutException'],
    );
  }

  // --- dart:io. ---

  Future<void> test_reports_fileReadAsString() async {
    await assertReportsOn(
      r'''
Future<String> f(File file) async => await file.readAsString();
''',
      'file.readAsString()',
      types: ['FileSystemException'],
    );
  }

  Future<void> test_reports_fileDeleteThroughSupertype() async {
    await assertReportsOn(
      r'''
Future<void> f(File file) async {
  await file.delete();
}
''',
      'file.delete()',
      types: ['FileSystemException'],
    );
  }

  Future<void> test_reports_directoryCreate() async {
    await assertReportsOn(
      r'''
Future<void> f(Directory dir) async {
  await dir.create();
}
''',
      'dir.create()',
      types: ['FileSystemException'],
    );
  }

  Future<void> test_reports_socketConnect() async {
    await assertReportsOn(
      r'''
Future<Socket> f() async => Socket.connect('localhost', 80);
''',
      "Socket.connect('localhost', 80)",
      types: ['SocketException'],
    );
  }

  Future<void> test_reports_processRun() async {
    await assertReportsOn(
      r'''
Future<Object?> f() async => await Process.run('ls', const <String>[]);
''',
      "Process.run('ls', const <String>[])",
      types: ['ProcessException'],
    );
  }

  Future<void> test_reports_httpClientGetUrl_bothTypes() async {
    await assertReportsOn(
      r'''
Future<Object?> f(HttpClient client, Uri url) async =>
    await client.getUrl(url);
''',
      'client.getUrl(url)',
      types: ['HttpException', 'SocketException'],
    );
  }

  Future<void> test_reports_webSocketConnect() async {
    await assertReportsOn(
      r'''
Future<WebSocket> f(String url) async => WebSocket.connect(url);
''',
      'WebSocket.connect(url)',
      types: ['SocketException', 'WebSocketException'],
    );
  }

  Future<void> test_reports_httpClientRequestClose_includesRedirect() async {
    await assertReportsOn(
      r'''
Future<Object?> f(HttpClientRequest request) async => await request.close();
''',
      'request.close()',
      types: ['HttpException', 'RedirectException', 'SocketException'],
    );
  }

  // --- package:flutter. ---

  Future<void> test_reports_invokeMethod_bothTypes() async {
    await assertReportsOn(
      r'''
Future<Object?> f(MethodChannel channel) async =>
    await channel.invokeMethod<Object>('go');
''',
      "channel.invokeMethod<Object>('go')",
      types: ['MissingPluginException', 'PlatformException'],
    );
  }

  Future<void> test_reports_invokeListMethod() async {
    await assertReportsOn(
      r'''
Future<Object?> f(MethodChannel channel) async =>
    await channel.invokeListMethod<Object>('go');
''',
      "channel.invokeListMethod<Object>('go')",
      types: ['PlatformException'],
    );
  }

  Future<void>
  test_reports_optionalMethodChannel_onlyPlatformException() async {
    // The more derived entry wins, so only `PlatformException` is reported.
    await assertReportsOn(
      r'''
Future<Object?> f(OptionalMethodChannel channel) async =>
    await channel.invokeMethod<Object>('go');
''',
      "channel.invokeMethod<Object>('go')",
      types: ['PlatformException'],
    );
  }

  Future<void> test_clean_optionalMethodChannelNeedsNoMissingPlugin() async {
    // Catching only `PlatformException` suffices, which is the observable
    // difference from `MethodChannel`: a missing implementation yields `null`.
    await assertClean(r'''
Future<Object?> f(OptionalMethodChannel channel) async {
  try {
    return await channel.invokeMethod<Object>('go');
  } on PlatformException {
    return null;
  }
}
''');
  }

  Future<void>
  test_reports_optionalMethodChannelInheritedInvokeListMethod() async {
    // Only `invokeMethod` is overridden. `invokeListMethod` is inherited
    // unchanged, so it still throws `MissingPluginException`.
    await assertReportsOn(
      r'''
Future<Object?> f(OptionalMethodChannel channel) async =>
    await channel.invokeListMethod<Object>('go');
''',
      "channel.invokeListMethod<Object>('go')",
      types: ['MissingPluginException', 'PlatformException'],
    );
  }

  // --- Handled. ---

  Future<void> test_clean_intParseCaught() async {
    await assertClean(r'''
int f(String s) {
  try {
    return int.parse(s);
  } on FormatException {
    return 0;
  }
}
''');
  }

  Future<void> test_clean_intParsePropagated() async {
    await assertClean(r'''
@Throws({FormatException})
int f(String s) => int.parse(s);
''');
  }

  Future<void> test_clean_fileReadCaught() async {
    await assertClean(r'''
Future<String> f(File file) async {
  try {
    return await file.readAsString();
  } on FileSystemException {
    return '';
  }
}
''');
  }

  Future<void> test_clean_invokeMethodCaught() async {
    await assertClean(r'''
Future<Object?> f(MethodChannel channel) async {
  try {
    return await channel.invokeMethod<Object>('go');
  } on PlatformException {
    return null;
  } on MissingPluginException {
    return null;
  }
}
''');
  }

  Future<void> test_clean_invokeMethodCaughtAsException() async {
    await assertClean(r'''
Future<Object?> f(MethodChannel channel) async {
  try {
    return await channel.invokeMethod<Object>('go');
  } on Exception {
    return null;
  }
}
''');
  }

  // --- Exempt. ---

  Future<void> test_clean_intTryParse() async {
    await assertClean(r'''
int? f(String s) => int.tryParse(s);
''');
  }

  Future<void> test_clean_doubleTryParse() async {
    await assertClean(r'''
double? f(String s) => double.tryParse(s);
''');
  }

  Future<void> test_clean_uriTryParse() async {
    await assertClean(r'''
Uri? f(String s) => Uri.tryParse(s);
''');
  }

  Future<void> test_clean_lengthIsNotTabled() async {
    await assertClean(r'''
int f(List<int> xs) => xs.length;
''');
  }

  Future<void> test_clean_fileExistsIsNotTabled() async {
    await assertClean(r'''
Future<bool> f(File file) async => await file.exists();
''');
  }

  Future<void> test_clean_userDefinedParseIsNotTabled() async {
    await assertClean(r'''
class Money {
  static Money parse(String s) => Money();
}

Money f(String s) => Money.parse(s);
''');
  }

  Future<void> test_clean_userDefinedFirstIsNotTabled() async {
    await assertClean(r'''
class Bag {
  int get first => 0;
}

int f(Bag bag) => bag.first;
''');
  }

  Future<void> test_clean_userDefinedJsonDecodeIsNotTabled() async {
    await assertClean(r'''
Object? jsonDecode2(String s) => null;

Object? f(String s) => jsonDecode2(s);
''');
  }

  Future<void> test_clean_userDefinedInvokeMethodIsNotTabled() async {
    await assertClean(r'''
class FakeChannel {
  Future<T?> invokeMethod<T>(String method) async => null;
}

Future<Object?> f(FakeChannel channel) async =>
    await channel.invokeMethod<Object>('go');
''');
  }

  // --- Errors are excluded. ---
  //
  // An `Error` reports a bug in the calling code, and `avoid_catching_errors`
  // says not to catch one. Declaring it with `@Throws` would be advice to do
  // exactly that, so nothing that throws an `Error` is tabled. Each of these
  // would have been reported before that decision.

  Future<void> test_clean_iterableFirstThrowsStateError() async {
    await assertClean(r'''
int f(List<int> xs) => xs.first;
''');
  }

  Future<void> test_clean_iterableLastThrowsStateError() async {
    await assertClean(r'''
int f(Iterable<int> xs) => xs.last;
''');
  }

  Future<void> test_clean_iterableSingleThrowsStateError() async {
    await assertClean(r'''
int f(Iterable<int> xs) => xs.single;
''');
  }

  Future<void> test_clean_iterableReduceThrowsStateError() async {
    await assertClean(r'''
int f(Iterable<int> xs) => xs.reduce((a, b) => a + b);
''');
  }

  Future<void> test_clean_firstWhereThrowsStateError() async {
    // With or without `orElse`: the guard is gone because the exception it
    // ruled out is no longer tabled at all.
    await assertClean(r'''
int f(List<int> xs) => xs.firstWhere((x) => x > 0);
''');
  }

  Future<void> test_clean_streamFirstThrowsStateError() async {
    await assertClean(r'''
Future<int> f(Stream<int> xs) async => await xs.first;
''');
  }

  Future<void> test_clean_indexAccessThrowsRangeError() async {
    await assertClean(r'''
int f(List<int> xs) => xs[0];
''');
  }

  Future<void> test_clean_elementAtThrowsRangeError() async {
    await assertClean(r'''
int f(List<int> xs) => xs.elementAt(0);
''');
  }

  Future<void> test_clean_jsonEncodeThrowsAnError() async {
    await assertClean(r'''
String f(Object? value) => jsonEncode(value);
''');
  }

  Future<void> test_clean_assetBundleLoadThrowsFlutterError() async {
    await assertClean(r'''
Future<String> f(AssetBundle bundle) async => await bundle.loadString('a');
''');
  }

  // --- Tear-offs. ---

  Future<void> test_clean_staticMethodTearOff() async {
    // Naming a method without calling it runs nothing, so nothing can throw.
    await assertClean(r'''
int Function(String) f() => int.parse;
''');
  }

  Future<void> test_clean_instanceMethodTearOff() async {
    await assertClean(r'''
Function f(List<int> xs) => xs.firstWhere;
''');
  }

  Future<void> test_clean_topLevelFunctionTearOff() async {
    await assertClean(r'''
Function f() => jsonDecode;
''');
  }
}
