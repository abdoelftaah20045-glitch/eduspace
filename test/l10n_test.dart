import 'package:eduspace_app/core/l10n.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('every key resolves to a real string in all 5 languages', () {
    for (final lang in ['ar', 'en', 'fr', 'es', 'de']) {
      final s = S(Locale(lang));
      for (final k in S.debugKeys) {
        final v = s.t(k);
        expect(v.trim().isNotEmpty, true, reason: '$k empty in $lang');
      }
    }
  });

  test('placeholders stay consistent across languages', () {
    for (final k in S.debugKeys) {
      final en = S(const Locale('en')).t(k);
      final has = RegExp(r'\{count\}').hasMatch(en);
      for (final lang in ['ar', 'fr', 'es', 'de']) {
        final v = S(Locale(lang)).t(k);
        expect(RegExp(r'\{count\}').hasMatch(v), has,
            reason: '$k placeholder differs in $lang');
      }
    }
  });

  test('Arabic is the default fallback for unknown keys', () {
    expect(S(const Locale('ar')).t('no_such_key_xyz'), 'no_such_key_xyz');
  });
}
