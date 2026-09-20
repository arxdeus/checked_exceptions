// Checks that the example demonstrates what it claims to.
//
// The example is the only place the plugin runs end to end: the unit tests
// drive rules through the analyzer's testing harness, which never loads the
// plugin the way the analysis server does. So a mistake in registration, in the
// plugin name, or in the `plugins:` block would leave every test passing while
// the plugin did nothing for a real user. That failure mode is not
// hypothetical: this example spent its whole life resolving the plugin from
// pub.dev, where the package was not published, so the server quietly declined
// to start it and reported nothing at all.
//
// Rather than hard-code a tally that drifts, this reads the example's own
// comments as the specification. Each `// reported: <rule>` comment claims one
// diagnostic of that rule, and the totals per rule must match exactly. Adding a
// case to the example therefore extends this check for free.
//
// Matching is by rule name rather than by line, because a marker here may sit
// several lines above the code it describes: the `empty_catch` case documents
// the whole method, including why the braces contain no comment. Counting per
// rule keeps the comments free to explain themselves while still failing when a
// rule stops firing, starts firing twice, or fires where nothing was claimed.
//
// Run from the package root:
//
//     dart run tool/verify_example.dart
//
// Exits non-zero, naming the rule that disagreed, when the example and the
// plugin have drifted apart.

import 'dart:convert';
import 'dart:io';

/// The rules this plugin contributes.
///
/// A diagnostic from anything else, the SDK's own lints included, is not this
/// tool's business: the example includes plenty deliberately.
const _rules = {'unhandled_throws', 'empty_catch'};

void main() async {
  final example = File('example/lib/example.dart');
  if (!example.existsSync()) {
    _fail('run this from the package root: ${example.path} not found');
  }

  final expected = _claimedCounts(example.readAsLinesSync());
  if (expected.isEmpty) {
    _fail('found no `// reported: <rule>` markers in ${example.path}');
  }

  final actual = await _reportedCounts();

  final rules = {...expected.keys, ...actual.keys}.toList()..sort();
  final problems = <String>[];
  for (final rule in rules) {
    final claimed = expected[rule] ?? 0;
    final reported = actual[rule] ?? 0;
    if (claimed != reported) {
      problems.add(
        '  $rule: example claims $claimed, analyzer reported $reported',
      );
    }
  }

  if (problems.isEmpty) {
    final total = expected.values.fold(0, (sum, count) => sum + count);
    stdout.writeln(
      'OK: $total diagnostics across ${expected.length} rules, matching every '
      '`// reported:` claim in the example.',
    );
    return;
  }

  stderr.writeln('The example and the plugin disagree:');
  problems.forEach(stderr.writeln);
  stderr.writeln(
    '\nA rule reporting nothing usually means the plugin never started: check '
    '`dart analyze` in example/ for a plugin setup error. A rule reporting more '
    'than claimed means either the rule became too eager, or the example gained '
    'a case without a comment describing it.',
  );
  exit(1);
}

/// How many diagnostics of each rule the example says it should produce.
Map<String, int> _claimedCounts(List<String> lines) {
  final counts = <String, int>{};
  // Deliberately anchored to the line's start so that prose mentioning a rule
  // name mid-sentence cannot be mistaken for a claim.
  final marker = RegExp(r'^//\s*reported:\s*([a-z_]+)');

  for (final line in lines) {
    final match = marker.firstMatch(line.trim());
    if (match == null) {
      continue;
    }
    final rule = match.group(1)!;
    if (!_rules.contains(rule)) {
      _fail(
        'unknown rule "$rule" claimed in the example. This tool knows '
        '${_rules.toList()..sort()}; add the new rule there if one was added.',
      );
    }
    counts.update(rule, (n) => n + 1, ifAbsent: () => 1);
  }
  return counts;
}

/// How many diagnostics of each rule the analyzer actually reports.
///
/// Uses the machine-readable output rather than parsing the human format,
/// which is not a stable interface.
Future<Map<String, int>> _reportedCounts() async {
  final result = await Process.run(
    Platform.resolvedExecutable,
    ['analyze', '--format=json', '.'],
    workingDirectory: 'example',
  );

  // `dart analyze` exits non-zero simply for having found diagnostics, which is
  // the expected case here, so the exit code says nothing on its own. A plugin
  // that failed to load reports on stderr while still exiting non-zero, so that
  // is surfaced rather than swallowed.
  final stderrText = (result.stderr as String).trim();
  if (stderrText.isNotEmpty) {
    stderr.writeln('dart analyze wrote to stderr:\n$stderrText\n');
  }

  final Object? decoded;
  try {
    decoded = jsonDecode(result.stdout as String);
  } on FormatException catch (error) {
    _fail('could not parse `dart analyze --format=json` output: $error');
  }

  if (decoded is! Map<String, Object?>) {
    _fail('unexpected analyze output shape: ${decoded.runtimeType}');
  }
  final diagnostics = decoded['diagnostics'];
  if (diagnostics is! List) {
    _fail('analyze output carried no diagnostics list');
  }

  final counts = <String, int>{};
  for (final diagnostic in diagnostics) {
    if (diagnostic is! Map<String, Object?>) {
      continue;
    }
    final code = diagnostic['code'];
    if (code is! String || !_rules.contains(code)) {
      continue;
    }
    counts.update(code, (n) => n + 1, ifAbsent: () => 1);
  }
  return counts;
}

Never _fail(String message) {
  stderr.writeln(message);
  exit(1);
}
