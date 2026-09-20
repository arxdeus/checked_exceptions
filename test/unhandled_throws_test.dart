import 'package:analyzer_testing/analysis_rule/analysis_rule.dart';
import 'package:checked_exceptions/src/rules/unhandled_throws.dart';
import 'package:test/test.dart';
import 'package:test_reflective_loader/test_reflective_loader.dart';

import 'src/annotations_source.dart';

void main() {
  defineReflectiveSuite(() {
    defineReflectiveTests(UnhandledThrowsTest);
  });
}

/// The exception hierarchy and annotated targets shared by the fixtures.
const _preamble = '''
import 'package:checked_exceptions/checked_exceptions.dart';

class Boom implements Exception {}

class SubBoom extends Boom {}

class Other implements Exception {}

@Throws({Boom})
void risky() {}

@Throws({Boom, Other})
void riskyTwice() {}

@Throws({Boom})
Future<void> riskyAsync() async {}

void safe() {}

class Resource {
  @Throws({Boom})
  Resource();

  @Throws({Boom})
  void method() {}
}
''';

@reflectiveTest
class UnhandledThrowsTest extends AnalysisRuleTest {
  @override
  void setUp() {
    newPackage('checked_exceptions')
        .addFile('lib/checked_exceptions.dart', annotationsSource);
    rule = UnhandledThrowsRule();
    super.setUp();
  }

  /// Asserts that [body], appended to the shared preamble, is clean.
  Future<void> assertClean(String body) =>
      assertNoDiagnostics('$_preamble\n$body');

  /// Asserts that [body], appended to the shared preamble, reports a lint on
  /// the last occurrence of [call], mentioning [types] in the message.
  Future<void> assertReportsOn(
    String body,
    String call, {
    List<String> types = const ['Boom'],
  }) async {
    final content = '$_preamble\n$body';
    final offset = content.lastIndexOf(call);
    expect(
      offset,
      isNonNegative,
      reason: "fixture contains no call matching '$call'",
    );
    await assertDiagnostics(content, [
      lint(offset, call.length, messageContainsAll: types),
    ]);
  }

  // --- Reports. ---

  Future<void> test_reports_whenUnhandled() async {
    await assertReportsOn(r'''
void f() {
  risky();
}
''', 'risky()');
  }

  Future<void> test_reports_whenCaughtTypeIsUnrelated() async {
    await assertReportsOn(r'''
void f() {
  try {
    risky();
  } on Other {}
}
''', 'risky()');
  }

  Future<void> test_reports_whenCaughtTypeIsOnlyASubtype() async {
    await assertReportsOn(r'''
void f() {
  try {
    risky();
  } on SubBoom {}
}
''', 'risky()');
  }

  Future<void> test_reports_remainingTypeOfPartialCatch() async {
    await assertReportsOn(
      r'''
void f() {
  try {
    riskyTwice();
  } on Boom {}
}
''',
      'riskyTwice()',
      types: ['Other'],
    );
  }

  Future<void> test_reports_remainingTypeOfPartialPropagation() async {
    await assertReportsOn(
      r'''
@Throws({Boom})
void f() {
  riskyTwice();
}
''',
      'riskyTwice()',
      types: ['Other'],
    );
  }

  Future<void> test_reports_bothTypesWhenNothingHandles() async {
    await assertReportsOn(
      r'''
void f() {
  riskyTwice();
}
''',
      'riskyTwice()',
      types: ['Boom', 'Other'],
    );
  }

  Future<void> test_reports_insideCatchBlockOfSameTry() async {
    await assertReportsOn(r'''
void f() {
  try {
    safe();
  } on Boom {
    risky();
  }
}
''', 'risky()');
  }

  Future<void> test_reports_insideFinallyBlockOfSameTry() async {
    await assertReportsOn(r'''
void f() {
  try {
    safe();
  } on Boom {
  } finally {
    risky();
  }
}
''', 'risky()');
  }

  Future<void> test_reports_insideClosureWrappedInOuterTry() async {
    await assertReportsOn(r'''
void run(void Function() callback) {}

void f() {
  try {
    run(() {
      risky();
    });
  } on Boom {}
}
''', 'risky()');
  }

  Future<void> test_reports_insideClosureOfPropagatingFunction() async {
    await assertReportsOn(r'''
void run(void Function() callback) {}

@Throws({Boom})
void f() {
  run(() {
    risky();
  });
}
''', 'risky()');
  }

  Future<void> test_reports_futureNotAwaitedInsideTry() async {
    await assertReportsOn(r'''
void f() {
  try {
    riskyAsync();
  } on Boom {}
}
''', 'riskyAsync()');
  }

  Future<void> test_reports_unhandledConstructor() async {
    await assertReportsOn(r'''
void f() {
  Resource();
}
''', 'Resource()');
  }

  Future<void> test_reports_unhandledMethodCall() async {
    await assertReportsOn(r'''
void f(Resource resource) {
  resource.method();
}
''', 'resource.method()');
  }

  Future<void> test_reports_insideTryWithOnlyFinally() async {
    await assertReportsOn(r'''
void f() {
  try {
    risky();
  } finally {
    safe();
  }
}
''', 'risky()');
  }

  Future<void> test_reports_inMethodOfClass() async {
    await assertReportsOn(r'''
class Caller {
  void f() {
    risky();
  }
}
''', 'risky()');
  }

  // --- No diagnostics. ---

  Future<void> test_clean_caughtByExactType() async {
    await assertClean(r'''
void f() {
  try {
    risky();
  } on Boom {}
}
''');
  }

  Future<void> test_clean_caughtBySupertype() async {
    await assertClean(r'''
void f() {
  try {
    risky();
  } on Exception {}
}
''');
  }

  Future<void> test_clean_caughtByObject() async {
    await assertClean(r'''
void f() {
  try {
    risky();
  } on Object {}
}
''');
  }

  Future<void> test_clean_caughtByBareCatch() async {
    await assertClean(r'''
void f() {
  try {
    risky();
  } catch (e) {}
}
''');
  }

  Future<void> test_clean_caughtByLaterClauseOfSameTry() async {
    await assertClean(r'''
void f() {
  try {
    risky();
  } on Other {
  } on Boom {}
}
''');
  }

  Future<void> test_clean_bothTypesCaught() async {
    await assertClean(r'''
void f() {
  try {
    riskyTwice();
  } on Boom {
  } on Other {}
}
''');
  }

  Future<void> test_clean_splitBetweenNestedTries() async {
    await assertClean(r'''
void f() {
  try {
    try {
      riskyTwice();
    } on Boom {}
  } on Other {}
}
''');
  }

  Future<void> test_clean_propagatedByCaller() async {
    await assertClean(r'''
@Throws({Boom})
void f() {
  risky();
}
''');
  }

  Future<void> test_clean_propagatedAsSupertype() async {
    await assertClean(r'''
@Throws({Exception})
void f() {
  risky();
}
''');
  }

  Future<void> test_clean_propagatedByEnclosingMethod() async {
    await assertClean(r'''
class Caller {
  @Throws({Boom})
  void f() {
    risky();
  }
}
''');
  }

  Future<void> test_clean_propagatedByEnclosingConstructor() async {
    await assertClean(r'''
class Caller {
  @Throws({Boom})
  Caller() {
    risky();
  }
}
''');
  }

  Future<void> test_clean_splitBetweenCatchAndPropagation() async {
    await assertClean(r'''
@Throws({Other})
void f() {
  try {
    riskyTwice();
  } on Boom {}
}
''');
  }

  Future<void> test_clean_awaitedFutureInsideTry() async {
    await assertClean(r'''
Future<void> f() async {
  try {
    await riskyAsync();
  } on Boom {}
}
''');
  }

  Future<void> test_clean_futureNotAwaitedButPropagated() async {
    await assertClean(r'''
@Throws({Boom})
void f() {
  riskyAsync();
}
''');
  }

  Future<void> test_clean_constructorInsideTry() async {
    await assertClean(r'''
void f() {
  try {
    Resource();
  } on Boom {}
}
''');
  }

  Future<void> test_clean_methodCallInsideTry() async {
    await assertClean(r'''
void f(Resource resource) {
  try {
    resource.method();
  } on Boom {}
}
''');
  }

  Future<void> test_clean_unannotatedCallee() async {
    await assertClean(r'''
void f() {
  safe();
}
''');
  }

  Future<void> test_clean_caughtWithStackTraceParameter() async {
    await assertClean(r'''
void f() {
  try {
    risky();
  } on Boom catch (e, st) {
    print('$e $st');
  }
}
''');
  }

  Future<void> test_clean_nestedFunctionDeclarationPropagates() async {
    await assertClean(r'''
void f() {
  @Throws({Boom})
  void inner() {
    risky();
  }

  try {
    inner();
  } on Boom {}
}
''');
  }

  Future<void> test_reports_readOfAnnotatedGetter() async {
    // A `@Throws` getter must propagate to whoever reads it, exactly as an
    // annotated method propagates to whoever calls it. Without this the quick
    // fix could annotate a getter, silence the warning there, and leave the
    // caller with no idea the exception exists.
    await assertReportsOn(r'''
class Holder {
  @Throws({Boom})
  int get value => 0;
}

int f(Holder holder) => holder.value;
''', 'holder.value');
  }

  Future<void> test_clean_readOfAnnotatedGetterCaught() async {
    await assertClean(r'''
class Holder {
  @Throws({Boom})
  int get value => 0;
}

int f(Holder holder) {
  try {
    return holder.value;
  } on Boom {
    return 0;
  }
}
''');
  }

  Future<void> test_clean_annotatedGetterDischargesItsOwnBody() async {
    // The annotation on the getter covers the call inside it.
    await assertClean(r'''
class Holder {
  @Throws({Boom})
  int get value {
    risky();
    return 0;
  }
}
''');
  }

  Future<void> test_clean_tearOffCallIsNotAnalyzed() async {
    // Calling through a variable loses the annotation: the variable's type is
    // a plain function type. Documented as a limit rather than a bug.
    await assertClean(r'''
void f() {
  final indirect = risky;
  indirect();
}
''');
  }

  Future<void> test_clean_closureWithItsOwnTry() async {
    await assertClean(r'''
void run(void Function() callback) {}

void f() {
  run(() {
    try {
      risky();
    } on Boom {}
  });
}
''');
  }
}
