import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:peijianche_app/theme/chat_visual_theme.dart';

/// Targeted coverage for the bundled open-source chat fonts.
void main() {
  const expected = <String, String>{
    'hard_pen': 'assets/fonts/MaShanZheng-Regular.ttf',
    'kai': 'assets/fonts/LXGWWenKai-Regular.ttf',
    'gentle_rounded': 'assets/fonts/ZenMaruGothic-Regular.ttf',
    'tech': 'assets/fonts/NotoSansMonoCJKsc-Regular.otf',
  };

  test('every bundled font asset exists and is non-empty', () {
    for (final entry in expected.entries) {
      final file = File(entry.value);
      expect(file.existsSync(), isTrue, reason: '${entry.value} missing');
      expect(file.lengthSync(), greaterThan(1024 * 1024));
      expect(file.lengthSync(), lessThan(40 * 1024 * 1024));
    }
  });

  test('pubspec registers every font family with its asset', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    const families = <String, String>{
      'PeiLinkHandwriting': 'assets/fonts/MaShanZheng-Regular.ttf',
      'PeiLinkKai': 'assets/fonts/LXGWWenKai-Regular.ttf',
      'PeiLinkGentleRounded': 'assets/fonts/ZenMaruGothic-Regular.ttf',
      'PeiLinkTechMono': 'assets/fonts/NotoSansMonoCJKsc-Regular.otf',
    };
    expect(pubspec.contains('fonts:'), isTrue);
    for (final entry in families.entries) {
      expect(pubspec.contains('family: ${entry.key}'), isTrue,
          reason: '${entry.key} must be registered');
      expect(pubspec.contains(entry.value), isTrue,
          reason: '${entry.key} asset must be registered');
    }
  });

  test('OFL licences are kept next to the font assets', () {
    final licenses = Directory('assets/fonts/licenses')
        .listSync()
        .whereType<File>()
        .map((file) => file.path)
        .toList();
    expect(licenses.length, greaterThanOrEqualTo(4));
    for (final file in licenses) {
      expect(
        File(file).readAsStringSync().contains('SIL Open Font License'),
        isTrue,
        reason: '$file must carry the OFL text',
      );
    }
  });

  test('decoration ids map to the bundled families only', () {
    final byId = {
      for (final font in ChatVisualThemeCatalog.fontThemes) font.id: font,
    };
    expect(byId.keys, containsAll(expected.keys));
    expect(byId['hard_pen']!.fontFamily, 'PeiLinkHandwriting');
    expect(byId['kai']!.fontFamily, 'PeiLinkKai');
    expect(byId['gentle_rounded']!.fontFamily, 'PeiLinkGentleRounded');
    expect(byId['tech']!.fontFamily, 'PeiLinkTechMono');
    expect(byId['system']!.fontFamily, 'sans-serif');
    for (final id in expected.keys) {
      expect(byId[id]!.isAvailable, isTrue);
      // Partial-coverage fonts must declare a real fallback, never tofu-only.
      expect(byId[id]!.fontFamilyFallback, isNotEmpty);
    }
  });
}
