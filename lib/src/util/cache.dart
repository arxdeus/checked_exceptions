/// Per-element memoization for the answers the rules ask repeatedly.
///
/// Every rule runs over every node of every unit, and the expensive questions
/// ("does this carry `@Throws`?", "is this a member the SDK table names?") are
/// asked about *elements*, of which a file mentions far fewer than it has
/// nodes. A call to `int.parse` from four hundred places is four hundred
/// questions about a single element.
///
/// Answers are keyed on the element with an [Expando], so an entry lives
/// exactly as long as the element it describes. That matters in the analysis
/// server, which is a long-running process that discards and rebuilds element
/// models as files change: a plain `Map` would pin every element of every file
/// ever analysed, and an LRU would need a size nobody can pick correctly.
/// [Expando] entries are collected with their keys, so the cache cannot leak.
///
/// `tool/verify_cache_invalidation.dart` in the `arxdeus_lints` package checks
/// the assumption this rests on: that editing a file yields fresh element
/// objects, so a cached answer can never be read back for changed source.
library;

/// A memo table for answers of type [T] about elements of type [K].
///
/// [Expando] cannot store `null`, and "the answer is `null`" is a real answer
/// worth caching here (most elements carry no `@Throws`), so values are boxed.
/// The box is what distinguishes "computed, and the answer was nothing" from
/// "not computed yet".
final class ElementCache<K extends Object, T> {
  ElementCache(this._name);

  final String _name;
  late final Expando<_Box<T>> _entries = Expando<_Box<T>>(_name);

  /// Returns the memoized answer for [key], computing it with [ifAbsent] on
  /// the first call.
  T of(K key, T Function() ifAbsent) {
    final existing = _entries[key];
    if (existing != null) {
      return existing.value;
    }
    final value = ifAbsent();
    _entries[key] = _Box(value);
    return value;
  }
}

/// A memoized value, boxed so that `null` can be stored.
final class _Box<T> {
  const _Box(this.value);

  final T value;
}
