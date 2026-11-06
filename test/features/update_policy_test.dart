import 'package:flutter_test/flutter_test.dart';
import 'package:quickkart/features/app_config/domain/update_policy.dart';

UpdateRequirement eval(String current, String min, String latest) =>
    UpdatePolicy.evaluate(
      currentVersion: current,
      minSupportedVersion: min,
      latestVersion: latest,
    );

void main() {
  test('below the minimum -> required', () {
    expect(eval('1.4.0', '2.0.0', '2.0.0'), UpdateRequirement.required);
    expect(eval('1.9.9', '2.0', '2.1'), UpdateRequirement.required);
  });

  test('below latest only -> optional', () {
    expect(eval('1.4.0', '1.0.0', '1.5.0'), UpdateRequirement.optional);
  });

  test('up to date or newer -> none', () {
    expect(eval('1.4.0', '1.0.0', '1.4.0'), UpdateRequirement.none);
    expect(eval('1.5.0', '1.0.0', '1.4.0'), UpdateRequirement.none);
  });

  test('segments compare numerically, not as text', () {
    expect(eval('1.10.0', '1.9.0', '1.10.0'), UpdateRequirement.none);
    expect(eval('1.9.0', '1.10.0', '1.10.0'), UpdateRequirement.required);
    expect(eval('1.4.2', '1.4.10', '2.0'), UpdateRequirement.required);
  });

  test('missing segments count as 0', () {
    expect(eval('1.4', '1.4.0', '1.4.0.0'), UpdateRequirement.none);
    expect(eval('2', '1.0', '2.0.0'), UpdateRequirement.none);
    expect(eval('1.4', '1.4.1', '1.5'), UpdateRequirement.required);
  });

  test('required wins over optional', () {
    expect(eval('1.0.0', '1.2.0', '1.5.0'), UpdateRequirement.required);
  });

  test('any malformed version -> none (never lock users out)', () {
    for (final bad in [
      '',
      'abc',
      '1.a.0',
      '-1.0',
      '1.-2',
      '1..0',
      '1.0.',
      '.1',
      '1.4.0-beta',
      'v1.4',
      ' 1.4',
      '1,4'
    ]) {
      expect(eval(bad, '1.0.0', '1.5.0'), UpdateRequirement.none,
          reason: 'current "$bad"');
      expect(eval('1.4.0', bad, '1.5.0'), UpdateRequirement.none,
          reason: 'min "$bad"');
      expect(eval('1.4.0', '1.0.0', bad), UpdateRequirement.none,
          reason: 'latest "$bad"');
    }
  });

  test('a typo in min_supported_version never blocks the app', () {
    expect(eval('1.0.0', 'x', '9.0.0'), UpdateRequirement.none);
  });
}
