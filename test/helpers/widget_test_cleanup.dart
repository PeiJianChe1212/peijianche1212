import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Unified widget test tree cleanup helper.
///
/// PeiLink pages (HomePage, ChatPage, GroupChatPage) carry long-lived
/// lifecycle resources: Timer.periodic, StreamSubscription,
/// WidgetsBindingObserver, AnimationController.  These only cancel inside
/// State.dispose(), which is triggered when the widget is removed from the
/// tree.  Relying on the test framework's implicit teardown is fragile
/// under `tester.runAsync()` and concurrent isolates.
///
/// Call [disposeTestWidgetTree] at the end of every widget test that pumps
/// a page with long-lived resources.  It replaces the tree with an empty
/// widget and pumps a bounded number of frames so State.dispose() runs
/// synchronously before the test isolate considers the test complete.
///
/// This helper intentionally does NOT use pumpAndSettle (which can hang
/// on infinite animations) and does NOT attempt to cancel Timers via
/// reflection or VM private APIs.
Future<void> disposeTestWidgetTree(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump();
  // One extra short pump gives any microtasks scheduled during dispose a
  // chance to run, without opening the door to infinite animation settling.
  await tester.pump(const Duration(milliseconds: 10));
}

/// Finite settle helper for pages that must NOT use pumpAndSettle.
///
/// HomePage contains `_DesktopBackground` with an infinite
/// `repeat(reverse: true)` animation, so pumpAndSettle would never return.
/// Use [settleFinite] instead: it pumps a fixed number of frames with a
/// short interval, giving normal finite transitions time to complete while
/// guaranteeing an upper bound.
Future<void> settleFinite(
  WidgetTester tester, {
  int frames = 20,
  Duration interval = const Duration(milliseconds: 50),
}) async {
  for (var i = 0; i < frames; i++) {
    await tester.pump(interval);
  }
  await tester.pump();
}
