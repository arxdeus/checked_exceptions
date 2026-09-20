// Measures what the plugin's rules cost on a real codebase.
//
//     dart run tool/benchmark.dart <lib-dir> [iterations]
//
// The `dart analyze` CLI does not load analyzer plugins, so the only honest
// way to time these rules against real Flutter code is to resolve the files
// with the analyzer and then drive the rules exactly as the analysis server
// does: register each rule's node processors into a `RuleVisitorRegistry`,
// and run that registry's visitor over every resolved unit.
//
// Resolution is done once, up front, and excluded from the timing. What is
// measured is the part this package owns: the rules' own work over an already
// resolved AST.
import 'dart:io';

import 'package:analyzer/analysis_rule/rule_context.dart';
import 'package:analyzer/dart/analysis/analysis_context_collection.dart';
import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/diagnostic/diagnostic.dart';
import 'package:analyzer/error/listener.dart';
import 'package:analyzer/file_system/physical_file_system.dart';
import 'package:analyzer/src/analysis_rule/rule_context.dart';
import 'package:analyzer/src/lint/linter_visitor.dart';
import 'package:checked_exceptions/src/rules/empty_catch.dart';
import 'package:checked_exceptions/src/rules/unhandled_throws.dart';

Future<void> main(List<String> args) async {
  if (args.isEmpty) {
    stderr.writeln('usage: benchmark.dart <lib-dir> [iterations]');
    exit(2);
  }
  final root = Directory(args.first).absolute.path;
  final iterations = args.length > 1 && args[1] != '--dump'
      ? int.parse(args[1])
      : 5;

  final collection = AnalysisContextCollection(
    includedPaths: [root],
    resourceProvider: PhysicalResourceProvider.INSTANCE,
  );

  stdout.writeln('resolving...');
  final resolved = <ResolvedUnitResult>[];
  final watch = Stopwatch()..start();
  for (final context in collection.contexts) {
    for (final path in context.contextRoot.analyzedFiles()) {
      if (!path.endsWith('.dart')) {
        continue;
      }
      final result = await context.currentSession.getResolvedUnit(path);
      if (result is ResolvedUnitResult) {
        resolved.add(result);
      }
    }
  }
  watch.stop();
  stdout.writeln(
    'resolved ${resolved.length} units in ${watch.elapsedMilliseconds} ms '
    '(not measured below)',
  );

  // `--dump` prints every diagnostic instead of timing, so that the output of
  // two revisions can be compared directly.
  if (args.contains('--dump')) {
    final dump = <String>[];
    _runRules(resolved, dump: dump);
    dump.sort();
    dump.forEach(stdout.writeln);
    return;
  }

  // Warm up, so that JIT compilation of the rules is not attributed to the
  // first measured iteration.
  _runRules(resolved);

  final timings = <int>[];
  for (var i = 0; i < iterations; i++) {
    final run = Stopwatch()..start();
    final count = _runRules(resolved);
    run.stop();
    timings.add(run.elapsedMicroseconds);
    stdout.writeln(
      'iteration ${i + 1}: ${(run.elapsedMicroseconds / 1000).toStringAsFixed(1)} ms '
      '($count diagnostics)',
    );
  }

  _perRule(resolved);

  timings.sort();
  final best = timings.first / 1000;
  final median = timings[timings.length ~/ 2] / 1000;
  stdout.writeln(
    'best ${best.toStringAsFixed(1)} ms, median ${median.toStringAsFixed(1)} ms',
  );
}

/// Times each rule on its own, so the cost is attributable.
void _perRule(List<ResolvedUnitResult> units) {
  final factories = <String, AnalysisRule Function()>{
    'empty_catch': EmptyCatchRule.new,
    'unhandled_throws': UnhandledThrowsRule.new,
  };
  stdout.writeln('per-rule:');
  for (final entry in factories.entries) {
    _runRules(units, only: entry.value);
    final w = Stopwatch()..start();
    final n = _runRules(units, only: entry.value);
    w.stop();
    stdout.writeln(
      '  ${entry.key.padRight(30)} '
      '${(w.elapsedMicroseconds / 1000).toStringAsFixed(1)} ms ($n)',
    );
  }
}

/// Runs every rule over every [units], returning how many diagnostics were
/// reported.
///
/// The diagnostic count is returned and printed so that an "optimization"
/// that quietly stops reporting things cannot look like a speed-up.
int _runRules(
  List<ResolvedUnitResult> units, {
  AnalysisRule Function()? only,
  List<String>? dump,
}) {
  var reported = 0;
  for (final unit in units) {
    final rules = only != null
        ? <AnalysisRule>[only()]
        : <AnalysisRule>[
            EmptyCatchRule(),
            UnhandledThrowsRule(),
          ];

    final listener = _CountingListener(sink: dump);
    final reporter = DiagnosticReporter(
      listener,
      unit.libraryElement.firstFragment.source,
    );
    final contextUnit = RuleContextUnit(
      file: unit.file,
      content: unit.content,
      diagnosticReporter: reporter,
      unit: unit.unit,
    );
    final context = RuleContextWithResolvedResults(
      [contextUnit],
      contextUnit,
      unit.typeProvider,
      unit.typeSystem,
      null,
    );
    context.currentUnit = contextUnit;

    final registry = RuleVisitorRegistryImpl(enableTiming: false);
    for (final rule in rules) {
      rule.reporter = reporter;
      rule.registerNodeProcessors(registry, context);
    }
    unit.unit.accept(
      AnalysisRuleVisitor(registry, shouldPropagateExceptions: true),
    );
    reported += listener.count;
  }
  return reported;
}

/// Counts diagnostics, and records them when asked.
///
/// The recorded form is what makes an optimization checkable rather than
/// merely fast: two revisions must produce byte-identical output.
final class _CountingListener extends DiagnosticListener {
  _CountingListener({this.sink});

  final List<String>? sink;
  int count = 0;

  @override
  void onDiagnostic(Diagnostic diagnostic) {
    count++;
    sink?.add(
      '${diagnostic.offset}:${diagnostic.length} '
      '${diagnostic.diagnosticCode.lowerCaseName} ${diagnostic.message}',
    );
  }
}
