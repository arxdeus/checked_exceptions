/// A harness for testing this plugin's quick fixes.
///
/// `analyzer_testing` ships a harness for *rules* but not for *fixes*, so this
/// drives the real fix processor against a resolved unit: the same
/// registration, applicability and change-building path the IDE uses, rather
/// than calling a correction producer by hand.
///
/// This is a test-only file rather than a library under `lib/`, and rather than
/// a shared package, because it imports `package:test`. A library under `lib/`
/// may only import from `dependencies`, so shipping it would push `test` onto
/// every consumer of this plugin, where it cannot coexist with the `test_api`
/// that `flutter_test` pins. Sharing it as a package would mean a path
/// dev-dependency, which this package cannot carry: it is developed in its own
/// repository.
///
/// The sibling plugins keep their own copy of this file, which is the cost of
/// that independence. It is about 200 lines and changes rarely. When it does
/// change, the copies should be kept in step.
library;

import 'package:analysis_server_plugin/edit/fix/dart_fix_context.dart';
import 'package:analysis_server_plugin/edit/fix/fix.dart';
import 'package:analysis_server_plugin/plugin.dart';
//
// `computeFixes`, `DartChangeWorkspace` and `PluginRegistryImpl` are the fix
// pipeline the analysis server itself runs, and `analysis_server_plugin`
// exports none of them publicly. Reaching into `src/` is what makes this
// harness test the real path rather than a reimplementation of it; the
// alternative is to assert against a copy of the server's behaviour, which
// would keep passing when the real path broke.
import 'package:analysis_server_plugin/src/correction/dart_change_workspace.dart';
import 'package:analysis_server_plugin/src/correction/fix_processor.dart';
import 'package:analysis_server_plugin/src/registry.dart';
import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/diagnostic/diagnostic.dart';
import 'package:analyzer/instrumentation/service.dart';
import 'package:analyzer_plugin/protocol/protocol_common.dart';
import 'package:analyzer_testing/analysis_rule/analysis_rule.dart';
import 'package:test/test.dart';

/// The plugins whose fixes have been registered in this isolate.
///
/// The generator registry is global and additive, so registering the same
/// plugin once per test would stack duplicate producers and make every fix
/// appear twice. Keyed by plugin name rather than a single flag, so a suite
/// that exercises two plugins registers each of them exactly once.
final Set<String> _registered = {};

/// Applies quick fixes in a test, the way the analysis server does.
///
/// `analyzer_testing` ships a harness for *rules* but not for *fixes*, so this
/// drives `computeFixes` directly against a resolved unit. Going through the
/// real fix processor is what makes the assertion meaningful: it exercises the
/// same registration, applicability and change-building path the IDE uses,
/// rather than calling the producer by hand.
extension FixTestExtensions on AnalysisRuleTest {
  /// Registers [plugin]'s fixes, exactly as the analysis server does.
  ///
  /// Calls the plugin's own `register` against [PluginRegistryImpl], the
  /// registry the server hands it. Naming a producer here instead would let a
  /// test pass while the plugin wires a *different* producer to the same
  /// diagnostic, so the suite would be checking a fix the IDE never offers.
  ///
  /// Registration is global and additive, so each plugin is registered once
  /// per process.
  void registerPluginFixes(Plugin plugin) {
    if (!_registered.add(plugin.name)) {
      return;
    }
    plugin.register(PluginRegistryImpl(plugin.name));
  }

  /// Asserts that applying the single fix offered for [content] yields
  /// [expected].
  ///
  /// The fix is located from the lint the rule reports, so a change to the
  /// rule that stops reporting also fails here rather than silently skipping.
  ///
  /// The result is then resolved in turn, and required both to compile and to
  /// no longer report the lint on the code that was reported. Comparing
  /// against [expected] alone would pass for a fix that writes well-formatted
  /// code that does not compile, or that leaves the warning exactly where it
  /// was.
  ///
  /// The check is by reported *text* rather than by offset, because a fix
  /// inserts code and so shifts every offset after it. It is deliberately not
  /// "no lint anywhere": the `@Throws` fix may annotate a local function, and
  /// the obligation then legitimately reappears at its caller.
  Future<void> assertFixProduces(String content, String expected) async {
    final result = await _resolve(content);
    final diagnostic = _soleLint(result);
    final fixes = await _fixesFor(result, diagnostic);

    expect(
      fixes,
      hasLength(1),
      reason: 'expected exactly one quick fix for the reported lint',
    );
    final fixed = _apply(content, fixes.single.change);
    expect(fixed, expected);

    final reported = content.substring(
      diagnostic.offset,
      diagnostic.offset + diagnostic.length,
    );
    final after = await _resolve(fixed);
    final remaining = after.diagnostics.where(
      (d) =>
          d.diagnosticCode.lowerCaseName == rule.name &&
          fixed.substring(d.offset, d.offset + d.length) == reported,
    );
    expect(
      remaining,
      isEmpty,
      reason: "the fix must resolve the lint reported on '$reported'",
    );
  }

  /// Asserts that [content] reports no lint at all, so no fix can apply.
  ///
  /// Distinct from [assertNoFix], which requires a lint to exist but expects
  /// no fix for it.
  Future<void> assertNoLintAndNoFix(String content) async {
    final result = await _resolve(content);
    expect(
      result.diagnostics.where(
        (d) => d.diagnosticCode.lowerCaseName == rule.name,
      ),
      isEmpty,
    );
  }

  /// Asserts that no quick fix is offered for the lint reported in [content].
  Future<void> assertNoFix(String content) async {
    final result = await _resolve(content);
    final diagnostic = _soleLint(result);
    expect(await _fixesFor(result, diagnostic), isEmpty);
  }

  /// Returns the message of the single fix offered for [content].
  Future<String> fixMessage(String content) async {
    final result = await _resolve(content);
    final fixes = await _fixesFor(result, _soleLint(result));
    expect(fixes, hasLength(1));
    return fixes.single.change.message;
  }

  /// Writes [content] to the test file and resolves it.
  Future<ResolvedUnitResult> _resolve(String content) async {
    newFile(testFile.path, content);
    final result = await resolveFile(testFile.path);
    final errors = result.diagnostics.where(
      (d) =>
          d.diagnosticCode.lowerCaseName != rule.name &&
          d.severity.name == 'ERROR',
    );
    expect(
      errors,
      isEmpty,
      reason: 'the fixture must compile: ${errors.join('\n')}',
    );
    return result;
  }

  /// Returns the one lint the rule under test reported.
  Diagnostic _soleLint(ResolvedUnitResult result) {
    final lints = result.diagnostics
        .where((d) => d.diagnosticCode.lowerCaseName == rule.name)
        .toList();
    expect(
      lints,
      hasLength(1),
      reason: 'the fixture must report exactly one ${rule.name}',
    );
    return lints.single;
  }

  /// Computes the fixes the plugin offers for [diagnostic].
  Future<List<Fix>> _fixesFor(
    ResolvedUnitResult result,
    Diagnostic diagnostic,
  ) async {
    final library = await result.session.getResolvedLibrary(result.path);
    final context = DartFixContext(
      instrumentationService: InstrumentationService.NULL_SERVICE,
      workspace: DartChangeWorkspace([result.session]),
      libraryResult: library as ResolvedLibraryResult,
      unitResult: result,
      error: diagnostic,
    );
    return await computeFixes(context);
  }

  /// Returns [content] with [change] applied.
  String _apply(String content, SourceChange change) {
    var updated = content;
    for (final edit in change.edits) {
      // Later offsets first, so that applying one edit cannot shift the
      // offsets of the edits that follow.
      final ordered = [...edit.edits]
        ..sort((a, b) => b.offset.compareTo(a.offset));
      for (final replacement in ordered) {
        updated = updated.replaceRange(
          replacement.offset,
          replacement.offset + replacement.length,
          replacement.replacement,
        );
      }
    }
    return updated;
  }
}
