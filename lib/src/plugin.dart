import 'package:analysis_server_plugin/plugin.dart';
import 'package:analysis_server_plugin/registry.dart';
import 'package:checked_exceptions/src/fixes/add_throws.dart';
import 'package:checked_exceptions/src/rules/empty_catch.dart';
import 'package:checked_exceptions/src/rules/unhandled_throws.dart';

/// The `checked_exceptions` analyzer plugin.
///
/// Both rules are registered as warning rules, so they are enabled as soon as
/// the plugin is enabled. Either can be turned off from analysis options:
///
/// ```yaml
/// plugins:
///   checked_exceptions:
///     diagnostics:
///       empty_catch: false
/// ```
final class CheckedExceptionsPlugin extends Plugin {
  @override
  String get name => 'checked_exceptions';

  @override
  void register(PluginRegistry registry) {
    registry
      ..registerWarningRule(EmptyCatchRule())
      ..registerWarningRule(UnhandledThrowsRule())
      // Offers to propagate an unhandled exception by annotating the enclosing
      // function, which is the tedious half of what the warning suggests.
      ..registerFixForRule(UnhandledThrowsRule.code, AddThrowsFix.new);
  }
}
