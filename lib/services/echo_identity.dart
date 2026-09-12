/// Stable identity values used by the Echo system.
///
/// Echo timelines are stored per owner scope. The current user owns a
/// synthetic scope so their own Echo can never collide with a character id.
/// Always compare against these constants instead of display names.
abstract final class EchoIdentity {
  /// Owner scope that stores the current user's own Echo timeline.
  static const String userEchoOwnerId = 'peilink_user_echo';
}
