/// What the app must do about its own version.
enum UpdateRequirement {
  /// Nothing to do.
  none,

  /// A newer version exists; the user may update or dismiss.
  optional,

  /// This version is no longer supported; the app must be blocked until the
  /// user updates.
  required,
}

/// Decides whether the running app must / may be updated.
///
/// Contract (hidden tests check this exactly - see ASSIGNMENT.md, Feature 2):
/// * Versions are dotted numbers like `1.4.0`, `1.10.2`, `2.0`. Compare them
///   numerically, segment by segment. Missing segments count as 0
///   (`1.4` == `1.4.0`).
/// * `current < minSupported`  -> [UpdateRequirement.required]
/// * `current < latest`        -> [UpdateRequirement.optional]
/// * otherwise                 -> [UpdateRequirement.none]
/// * If ANY of the three versions is malformed (empty, letters, negative
///   numbers, ...) return [UpdateRequirement.none]. A bad value in the
///   config console must never lock users out of the app.
class UpdatePolicy {
  const UpdatePolicy._();

  static UpdateRequirement evaluate({
    required String currentVersion,
    required String minSupportedVersion,
    required String latestVersion,
  }) {
    final current = _parse(currentVersion);
    final min = _parse(minSupportedVersion);
    final latest = _parse(latestVersion);
    if (current == null || min == null || latest == null) {
      return UpdateRequirement.none;
    }
    if (_compare(current, min) < 0) return UpdateRequirement.required;
    if (_compare(current, latest) < 0) return UpdateRequirement.optional;
    return UpdateRequirement.none;
  }

  /// Only plain digits per segment: rejects "", "1..2", "1.a", "-1", "1.4-beta",
  /// "+1", " 1" etc. Returns null when malformed.
  static final _segment = RegExp(r'^\d+$');

  static List<int>? _parse(String version) {
    final parts = version.split('.');
    final out = <int>[];
    for (final p in parts) {
      if (!_segment.hasMatch(p)) return null;
      final n = int.tryParse(p);
      if (n == null) return null; // absurdly long number
      out.add(n);
    }
    return out;
  }

  /// Numeric, segment by segment; missing segments count as 0.
  static int _compare(List<int> a, List<int> b) {
    final length = a.length > b.length ? a.length : b.length;
    for (var i = 0; i < length; i++) {
      final x = i < a.length ? a[i] : 0;
      final y = i < b.length ? b[i] : 0;
      if (x != y) return x < y ? -1 : 1;
    }
    return 0;
  }
}
