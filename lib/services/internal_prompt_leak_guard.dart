/// Last-line defence for text that is about to become user-visible.
///
/// The image prompt must be kept out of the visible-message data flow. This
/// guard is intentionally small and only rejects unmistakable prompt
/// templates; it is not the primary separation mechanism.
abstract final class InternalPromptLeakGuard {
  static const _markers = <String>[
    '【图片主体】',
    '【人物出镜】',
    '【构图与视觉风格】',
    '【必要角色视觉资料】',
    '【事实边界】',
  ];

  static bool looksInternal(String text) {
    final value = text.trim();
    if (value.isEmpty) return false;
    final markerCount = _markers.where(value.contains).length;
    return markerCount >= 2 ||
        (value.contains('图片场景：') && markerCount >= 1) ||
        (value.contains('半写实 2.5D') && value.contains('高级 CG'));
  }

  static String visibleText(String text, {String fallback = ''}) =>
      looksInternal(text) ? fallback : text.trim();
}
