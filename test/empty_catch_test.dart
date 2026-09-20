import 'package:analyzer_testing/analysis_rule/analysis_rule.dart';
import 'package:checked_exceptions/src/rules/empty_catch.dart';
import 'package:test/test.dart';
import 'package:test_reflective_loader/test_reflective_loader.dart';

import 'src/annotations_source.dart';

void main() {
  defineReflectiveSuite(() {
    defineReflectiveTests(EmptyCatchTest);
  });
}

/// The exception hierarchy and annotated targets shared by the fixtures.
const _preamble = '''
import 'package:checked_exceptions/checked_exceptions.dart';

class Boom implements Exception {}

@Throws({Boom})
void risky() {}

void safe() {}

void log(Object value) {}
''';

@reflectiveTest
class EmptyCatchTest extends AnalysisRuleTest {
  @override
  void setUp() {
    newPackage('checked_exceptions')
        .addFile('lib/checked_exceptions.dart', annotationsSource);
    rule = EmptyCatchRule();
    super.setUp();
  }

  /// Asserts that [body], appended to the shared preamble, is clean.
  Future<void> assertClean(String body) =>
      assertNoDiagnostics('$_preamble\n$body');

  /// Asserts that [body] reports a lint on the last occurrence of [clause],
  /// with a message containing [messageParts].
  Future<void> assertReportsOn(
    String body,
    String clause, {
    List<String> messageParts = const [],
  }) async {
    final content = '$_preamble\n$body';
    final offset = content.lastIndexOf(clause);
    expect(
      offset,
      isNonNegative,
      reason: "fixture contains no clause matching '$clause'",
    );
    await assertDiagnostics(content, [
      lint(offset, clause.length, messageContainsAll: messageParts),
    ]);
  }

  // --- Reports. ---

  Future<void> test_reports_bareCatchWithEmptyBody() async {
    await assertReportsOn(
      r'''
void f() {
  try {
    safe();
  } catch (e) {}
}
''',
      'catch (e) {}',
      messageParts: ['every exception'],
    );
  }

  Future<void> test_reports_onClauseWithEmptyBody() async {
    await assertReportsOn(
      r'''
void f() {
  try {
    safe();
  } on Boom {}
}
''',
      'on Boom {}',
      messageParts: ['Boom'],
    );
  }

  Future<void> test_reports_underscoreNamedException() async {
    // `empty_catches`, the built-in rule, accepts this. Naming the variable
    // `_` does not handle anything, so this rule still reports it.
    await assertReportsOn(r'''
void f() {
  try {
    safe();
  } catch (_) {}
}
''', 'catch (_) {}');
  }

  Future<void> test_reports_bodyOfOnlyEmptyStatements() async {
    await assertReportsOn(r'''
void f() {
  try {
    safe();
  } on Boom {;}
}
''', 'on Boom {;}');
  }

  Future<void> test_reports_throwsCallSwallowed() async {
    // The point of the rule: a `@Throws` call formally "handled", actually
    // swallowed. The message says so.
    await assertReportsOn(
      r'''
void f() {
  try {
    risky();
  } on Boom {}
}
''',
      'on Boom {}',
      messageParts: ['Boom', '@Throws'],
    );
  }

  Future<void> test_reports_eachEmptyClauseOfSameTry() async {
    const content =
        '$_preamble\n'
        r'''
void f() {
  try {
    safe();
  } on Boom {} catch (e) {}
}
''';
    await assertDiagnostics(content, [
      lint(content.indexOf('on Boom {}'), 'on Boom {}'.length),
      lint(content.indexOf('catch (e) {}'), 'catch (e) {}'.length),
    ]);
  }

  Future<void> test_reports_insideNestedFunction() async {
    await assertReportsOn(r'''
void f() {
  void g() {
    try {
      safe();
    } catch (e) {}
  }
  g();
}
''', 'catch (e) {}');
  }

  // --- No diagnostics. ---

  Future<void> test_clean_rethrow() async {
    await assertClean(r'''
void f() {
  try {
    risky();
  } on Boom {
    rethrow;
  }
}
''');
  }

  Future<void> test_clean_usesException() async {
    await assertClean(r'''
void f() {
  try {
    risky();
  } catch (e) {
    log(e);
  }
}
''');
  }

  Future<void> test_clean_anyNonEmptyBody() async {
    await assertClean(r'''
void f() {
  try {
    risky();
  } on Boom {
    safe();
  }
}
''');
  }

  Future<void> test_clean_throwsSomethingElse() async {
    await assertClean(r'''
void f() {
  try {
    risky();
  } on Boom {
    throw Boom();
  }
}
''');
  }

  Future<void> test_clean_lineCommentExplainsTheSilence() async {
    // A comment in the block is the documented escape hatch: the author has
    // written down why nothing happens here.
    await assertClean(r'''
void f() {
  try {
    risky();
  } on Boom {
    // Best effort; the caller cannot act on this.
  }
}
''');
  }

  Future<void> test_clean_blockCommentExplainsTheSilence() async {
    await assertClean(r'''
void f() {
  try {
    risky();
  } on Boom {
    /* nothing to do */
  }
}
''');
  }

  Future<void> test_clean_emptyFinallyBlock() async {
    // `finally` is not a catch clause; an empty one swallows nothing.
    await assertClean(r'''
void f() {
  try {
    safe();
  } finally {}
}
''');
  }
}
