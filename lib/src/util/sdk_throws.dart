/// What the SDK and Flutter members below are known to throw, so that the
/// `unhandled_throws` rule can treat them as if they carried `@Throws`.
///
/// ## What belongs in this table
///
/// A member is listed when it throws as part of its *contract*: the failure is
/// caused by input or by the outside world, the caller cannot rule it out by
/// inspection, and handling it is ordinary defensive code. `int.parse` on
/// user input and `File.readAsString` on a missing file are the shape of it.
///
/// A member is *excluded* when it throws an `Error`, which by convention
/// reports a bug in the calling code rather than an exceptional condition.
/// The fix for an `Error` is to correct the call, so declaring one with
/// `@Throws` would be advice to catch it, and `avoid_catching_errors` says
/// exactly the opposite. Rather than have two rules contradict each other,
/// nothing that throws an `Error` is listed here, which rules out
/// `Iterable.first` and friends (`StateError`), `list[0]` and
/// `Iterable.elementAt` (`RangeError`), `jsonEncode`
/// (`JsonUnsupportedObjectError`) and `AssetBundle.load` (`FlutterError`).
///
/// The `tryParse` counterparts are absent because returning `null` is exactly
/// how they differ from the throwing ones.
///
/// This is a curated list, not an analysis: the rule never infers what an
/// unannotated body throws. A member that is missing is simply not reported.
/// `dart run tool/verify_sdk_table.dart` checks that every entry here names a
/// member that really exists in the installed SDKs and that the rule's own
/// lookup can actually reach, so an entry can be wrong but never silently
/// dead.
library;

import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/type.dart';
import 'package:analyzer/dart/element/type_provider.dart';
import 'package:checked_exceptions/src/util/cache.dart';

/// A reference to an exception class, by declaring library and name.
///
/// Stored as names rather than as types because the table is a `const`: the
/// actual [InterfaceType] only exists once a library is being analysed, and
/// is resolved on demand by [_resolve].
typedef ExceptionRef = ({String library, String name});

const ExceptionRef _formatException = (
  library: 'dart:core',
  name: 'FormatException',
);
const ExceptionRef _timeoutException = (
  library: 'dart:async',
  name: 'TimeoutException',
);
const ExceptionRef _fileSystemException = (
  library: 'dart:io',
  name: 'FileSystemException',
);
const ExceptionRef _socketException = (
  library: 'dart:io',
  name: 'SocketException',
);
const ExceptionRef _handshakeException = (
  library: 'dart:io',
  name: 'HandshakeException',
);
const ExceptionRef _processException = (
  library: 'dart:io',
  name: 'ProcessException',
);
const ExceptionRef _httpException = (
  library: 'dart:io',
  name: 'HttpException',
);
const ExceptionRef _webSocketException = (
  library: 'dart:io',
  name: 'WebSocketException',
);
const ExceptionRef _redirectException = (
  library: 'dart:io',
  name: 'RedirectException',
);
const ExceptionRef _platformException = (
  library: 'package:flutter/services.dart',
  name: 'PlatformException',
);
const ExceptionRef _missingPluginException = (
  library: 'package:flutter/services.dart',
  name: 'MissingPluginException',
);
const ExceptionRef _networkImageLoadException = (
  library: 'package:flutter/painting.dart',
  name: 'NetworkImageLoadException',
);

/// The `dart:` libraries whose members participate in the table.
///
/// A member from anywhere else is ignored, so a third-party `jsonDecode` or a
/// hand-written `File` class never inherits SDK behaviour it does not have.
///
/// `dart:_http` is listed because an element's library is the one that
/// *declares* it: `HttpClient` is declared there and merely re-exported by
/// `dart:io`.
const _sdkLibraries = {
  'dart:core',
  'dart:async',
  'dart:convert',
  'dart:io',
  'dart:_http',
};

/// The prefix of the Flutter framework's library URIs.
///
/// Flutter's public libraries are thin re-exports of `package:flutter/src/...`
/// files, and an element's library is the file that *declares* it, so matching
/// on the prefix is what actually recognises `MethodChannel.invokeMethod`.
const _flutterPrefix = 'package:flutter/';

/// Static members, keyed by declaring class and member name.
///
/// The `tryParse` counterparts are absent on purpose: returning `null` instead
/// of throwing is exactly how they differ.
const _staticMembers = <String, Map<String, List<ExceptionRef>>>{
  'int': {
    'parse': [_formatException],
  },
  'double': {
    'parse': [_formatException],
  },
  'num': {
    'parse': [_formatException],
  },
  'BigInt': {
    'parse': [_formatException],
  },
  'DateTime': {
    'parse': [_formatException],
  },
  'Uri': {
    'parse': [_formatException],
    'parseIPv4Address': [_formatException],
    'parseIPv6Address': [_formatException],
  },
  'UriData': {
    'parse': [_formatException],
  },
  'Socket': {
    'connect': [_socketException],
  },
  'RawSocket': {
    'connect': [_socketException],
  },
  'ServerSocket': {
    'bind': [_socketException],
  },
  'RawServerSocket': {
    'bind': [_socketException],
  },
  'RawDatagramSocket': {
    'bind': [_socketException],
  },
  'SecureSocket': {
    'connect': [_socketException, _handshakeException],
    'secure': [_socketException, _handshakeException],
    'secureServer': [_socketException, _handshakeException],
  },
  'RawSecureSocket': {
    'connect': [_socketException, _handshakeException],
    'secure': [_socketException, _handshakeException],
    'secureServer': [_socketException, _handshakeException],
  },
  'SecureServerSocket': {
    'bind': [_socketException, _handshakeException],
  },
  'RawSecureServerSocket': {
    'bind': [_socketException, _handshakeException],
  },
  'Process': {
    'start': [_processException],
    'run': [_processException],
    'runSync': [_processException],
  },
  'WebSocket': {
    'connect': [_webSocketException, _socketException],
  },
};

/// Top-level functions, keyed by name.
///
/// `jsonEncode` and friends are absent: they throw a
/// `JsonUnsupportedObjectError`, which reports a bug in the value being
/// encoded rather than an exceptional condition worth propagating.
const _topLevelMembers = <String, List<ExceptionRef>>{
  'jsonDecode': [_formatException],
  'base64Decode': [_formatException],
};

/// Instance members, keyed by the interface that declares them.
///
/// Lookup walks the receiver's class and then its supertypes, so a member is
/// matched through any amount of inheritance: a `Utf8Decoder` reached through
/// a `Converter` variable still resolves to the `Utf8Decoder` entry.
const _instanceMembers = <String, Map<String, List<ExceptionRef>>>{
  // --- dart:async ---
  'Stream': {
    'timeout': [_timeoutException],
  },
  'Future': {
    'timeout': [_timeoutException],
  },
  // --- dart:convert ---
  'JsonCodec': {
    'decode': [_formatException],
  },
  'JsonDecoder': {
    'convert': [_formatException],
  },
  'Utf8Codec': {
    'decode': [_formatException],
  },
  'Utf8Decoder': {
    'convert': [_formatException],
  },
  'Base64Codec': {
    'decode': [_formatException],
  },
  'Base64Decoder': {
    'convert': [_formatException],
  },
  'AsciiCodec': {
    'decode': [_formatException],
  },
  'Latin1Codec': {
    'decode': [_formatException],
  },
  // `AsciiDecoder` and `Latin1Decoder` do not declare `convert` themselves;
  // they inherit it from this private base, which is therefore the class the
  // supertype walk actually finds.
  '_UnicodeSubsetDecoder': {
    'convert': [_formatException],
  },
  // --- dart:io ---
  'FileSystemEntity': {
    'delete': [_fileSystemException],
    'deleteSync': [_fileSystemException],
    'rename': [_fileSystemException],
    'renameSync': [_fileSystemException],
    'resolveSymbolicLinks': [_fileSystemException],
    'resolveSymbolicLinksSync': [_fileSystemException],
  },
  'File': {
    'create': [_fileSystemException],
    'createSync': [_fileSystemException],
    'copy': [_fileSystemException],
    'copySync': [_fileSystemException],
    'length': [_fileSystemException],
    'lengthSync': [_fileSystemException],
    'lastModified': [_fileSystemException],
    'lastModifiedSync': [_fileSystemException],
    'lastAccessed': [_fileSystemException],
    'lastAccessedSync': [_fileSystemException],
    'setLastModified': [_fileSystemException],
    'setLastModifiedSync': [_fileSystemException],
    'setLastAccessed': [_fileSystemException],
    'setLastAccessedSync': [_fileSystemException],
    'open': [_fileSystemException],
    'openSync': [_fileSystemException],
    'openRead': [_fileSystemException],
    'openWrite': [_fileSystemException],
    'readAsBytes': [_fileSystemException],
    'readAsBytesSync': [_fileSystemException],
    'readAsString': [_fileSystemException],
    'readAsStringSync': [_fileSystemException],
    'readAsLines': [_fileSystemException],
    'readAsLinesSync': [_fileSystemException],
    'writeAsBytes': [_fileSystemException],
    'writeAsBytesSync': [_fileSystemException],
    'writeAsString': [_fileSystemException],
    'writeAsStringSync': [_fileSystemException],
  },
  'Directory': {
    'create': [_fileSystemException],
    'createSync': [_fileSystemException],
    'createTemp': [_fileSystemException],
    'createTempSync': [_fileSystemException],
    'list': [_fileSystemException],
    'listSync': [_fileSystemException],
  },
  'Link': {
    'create': [_fileSystemException],
    'createSync': [_fileSystemException],
    'update': [_fileSystemException],
    'updateSync': [_fileSystemException],
    'target': [_fileSystemException],
    'targetSync': [_fileSystemException],
  },
  'RandomAccessFile': {
    'close': [_fileSystemException],
    'closeSync': [_fileSystemException],
    'readByte': [_fileSystemException],
    'readByteSync': [_fileSystemException],
    'read': [_fileSystemException],
    'readSync': [_fileSystemException],
    'readInto': [_fileSystemException],
    'readIntoSync': [_fileSystemException],
    'writeByte': [_fileSystemException],
    'writeByteSync': [_fileSystemException],
    'writeFrom': [_fileSystemException],
    'writeFromSync': [_fileSystemException],
    'writeString': [_fileSystemException],
    'writeStringSync': [_fileSystemException],
    'position': [_fileSystemException],
    'positionSync': [_fileSystemException],
    'setPosition': [_fileSystemException],
    'setPositionSync': [_fileSystemException],
    'truncate': [_fileSystemException],
    'truncateSync': [_fileSystemException],
    'flush': [_fileSystemException],
    'flushSync': [_fileSystemException],
    'lock': [_fileSystemException],
    'lockSync': [_fileSystemException],
    'unlock': [_fileSystemException],
    'unlockSync': [_fileSystemException],
    'length': [_fileSystemException],
    'lengthSync': [_fileSystemException],
  },
  'HttpClient': {
    'open': [_socketException, _httpException],
    'openUrl': [_socketException, _httpException],
    'get': [_socketException, _httpException],
    'getUrl': [_socketException, _httpException],
    'post': [_socketException, _httpException],
    'postUrl': [_socketException, _httpException],
    'put': [_socketException, _httpException],
    'putUrl': [_socketException, _httpException],
    'delete': [_socketException, _httpException],
    'deleteUrl': [_socketException, _httpException],
    'patch': [_socketException, _httpException],
    'patchUrl': [_socketException, _httpException],
    'head': [_socketException, _httpException],
    'headUrl': [_socketException, _httpException],
  },
  'HttpClientRequest': {
    'close': [_socketException, _httpException, _redirectException],
  },
  // --- package:flutter ---
  'MethodChannel': {
    'invokeMethod': [_platformException, _missingPluginException],
    'invokeListMethod': [_platformException, _missingPluginException],
    'invokeMapMethod': [_platformException, _missingPluginException],
  },
  'OptionalMethodChannel': {
    // Only `invokeMethod` is overridden to answer a missing implementation
    // with `null`; `invokeListMethod` and `invokeMapMethod` are inherited
    // unchanged and still throw, so they deliberately have no entry here and
    // pick up `MethodChannel`'s.
    'invokeMethod': [_platformException],
  },
  'MethodCodec': {
    'decodeEnvelope': [_platformException, _formatException],
    'decodeMethodCall': [_formatException],
  },
  'StandardMethodCodec': {
    'decodeEnvelope': [_platformException, _formatException],
    'decodeMethodCall': [_formatException],
  },
  'JSONMethodCodec': {
    'decodeEnvelope': [_platformException, _formatException],
    'decodeMethodCall': [_formatException],
  },
  'MessageCodec': {
    'decodeMessage': [_formatException],
  },
  // `load` is absent: it was removed in favour of `loadImage`.
  'NetworkImage': {
    'loadBuffer': [_networkImageLoadException],
    'loadImage': [_networkImageLoadException],
  },
};

/// Every member name the table mentions, in any of its three sections.
///
/// This is the table's front door. The lookup below runs on every call
/// expression in the program, and the overwhelming majority of them name
/// something the table has never heard of. A single hash-set probe on the
/// name rejects those before anything asks for the element's library or
/// enclosing class, which are the expensive parts.
///
/// Built once, lazily, from the tables themselves, so it cannot drift out of
/// sync with them the way a hand-written list would.
final Set<String> _tabledNames = {
  for (final members in _staticMembers.values) ...members.keys,
  for (final members in _instanceMembers.values) ...members.keys,
  ..._topLevelMembers.keys,
};

/// Memoizes [_isTabledLibrary] per library.
///
/// The underlying test formats a `Uri` into a string, which is far too much
/// work to repeat for every mention of `int.parse` in a program. A library is
/// in the table or not, once and for all.
final _tabledLibraryCache = ElementCache<LibraryElement, bool>('sdkLibrary');

/// Memoizes the table entry found for an element.
///
/// Past the name filter, a lookup still walks the supertypes of the receiver's
/// class. The answer depends only on the element, and a call to the same
/// member from a hundred places asks the same question a hundred times.
final _refsCache = ElementCache<Element, List<ExceptionRef>?>('sdkThrows');

/// Returns the exceptions [element] is known to throw, or `null` when it is
/// not a member this table describes.
///
/// [typeProvider] resolves `dart:core` exception classes; anything declared
/// elsewhere is resolved through [element]'s own library, so the lookup can
/// never pick up a same-named class from the code under analysis.
List<DartType>? sdkThrows(Element? element, TypeProvider typeProvider) {
  if (element == null) {
    return null;
  }
  // Cheapest possible rejection, before the element is asked anything at all.
  final name = element.name;
  if (name == null || !_tabledNames.contains(name)) {
    return null;
  }
  final refs = _refsCache.of(element, () => _refsFor(element, name));
  if (refs == null || refs.isEmpty) {
    return null;
  }
  final types = [
    for (final ref in refs) ?_resolve(ref, element, typeProvider),
  ];
  return types.isEmpty ? null : types;
}

/// Returns the exception references recorded for [element], which is named
/// [name] and already known to appear somewhere in the table.
List<ExceptionRef>? _refsFor(Element element, String name) {
  if (!_isTabledLibrary(element.library)) {
    return null;
  }

  final enclosing = element.enclosingElement;
  if (enclosing is! InterfaceElement) {
    return _topLevelMembers[name];
  }
  if (_isStatic(element)) {
    return _staticMembers[enclosing.name]?[name];
  }
  return _instanceMember(enclosing, name);
}

/// Returns the entry for the instance member [name] of [type], looking through
/// the supertypes of [type].
///
/// The most derived class wins, so `OptionalMethodChannel.invokeMethod` keeps
/// its narrower entry instead of inheriting `MethodChannel`'s.
List<ExceptionRef>? _instanceMember(InterfaceElement type, String name) {
  final own = _instanceMembers[type.name]?[name];
  if (own != null && _isTabledLibrary(type.library)) {
    return own;
  }
  for (final supertype in type.allSupertypes) {
    final element = supertype.element;
    final entry = _instanceMembers[element.name]?[name];
    if (entry != null && _isTabledLibrary(element.library)) {
      return entry;
    }
  }
  return null;
}

/// Whether [library] is one this table describes.
bool _isTabledLibrary(LibraryElement? library) {
  if (library == null) {
    return false;
  }
  return _tabledLibraryCache.of(library, () {
    final uri = '${library.uri}';
    return _sdkLibraries.contains(uri) || uri.startsWith(_flutterPrefix);
  });
}

/// Whether [element] is a static member.
///
/// A field read resolves to its synthetic getter, so both the executable and
/// the variable cases are covered.
bool _isStatic(Element element) => switch (element) {
  ExecutableElement(:final isStatic) => isStatic,
  PropertyInducingElement(:final isStatic) => isStatic,
  _ => false,
};

/// Resolves [ref] to a type, as seen from [member]'s library.
///
/// `dart:core` classes come from [typeProvider]. Everything else is looked up
/// in the export namespace of [member]'s library, which by construction
/// contains the exception a member of that library throws.
InterfaceType? _resolve(
  ExceptionRef ref,
  Element member,
  TypeProvider typeProvider,
) {
  final core = typeProvider.objectElement.library;
  if (ref.library == 'dart:core') {
    return core.getClass(ref.name)?.thisType;
  }
  final library = member.library;
  if (library == null) {
    return null;
  }
  final direct = library.getClass(ref.name);
  if (direct != null) {
    return direct.thisType;
  }
  for (final imported in library.firstFragment.importedLibraries) {
    final found = imported.exportNamespace.get2(ref.name);
    if (found is InterfaceElement) {
      return found.thisType;
    }
  }
  return null;
}

/// One entry of the table, for verification tooling.
///
/// The table is a hand-written list of SDK members, so an entry naming a class
/// or member that does not exist can never match and would silently do
/// nothing. Exposing the entries lets `tool/verify_sdk_table.dart` resolve each
/// one against the real SDKs. It is not used by the rule itself.
typedef SdkTableEntry = ({
  /// `static`, `instance` or `toplevel`.
  String kind,

  /// The declaring class, or `null` for a top-level function.
  String? owner,

  /// The member name.
  String member,

  /// The exceptions the member is recorded as throwing.
  List<ExceptionRef> exceptions,
});

/// Every entry of the table, for verification tooling.
List<SdkTableEntry> get sdkTableEntries => [
  for (final MapEntry(key: owner, value: members) in _staticMembers.entries)
    for (final MapEntry(key: member, value: refs) in members.entries)
      (kind: 'static', owner: owner, member: member, exceptions: refs),
  for (final MapEntry(key: owner, value: members) in _instanceMembers.entries)
    for (final MapEntry(key: member, value: refs) in members.entries)
      (kind: 'instance', owner: owner, member: member, exceptions: refs),
  for (final MapEntry(key: member, value: refs) in _topLevelMembers.entries)
    (kind: 'toplevel', owner: null, member: member, exceptions: refs),
];
