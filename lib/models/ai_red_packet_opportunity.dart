enum AiRedPacketOpportunityKind { none, comfort, specialEvent }

class AiRedPacketOpportunity {
  const AiRedPacketOpportunity({
    required this.shouldSendRedPacket,
    required this.reason,
    this.kind = AiRedPacketOpportunityKind.none,
    this.futureGiftIntent = '',
  });

  const AiRedPacketOpportunity.none()
    : shouldSendRedPacket = false,
      reason = '',
      kind = AiRedPacketOpportunityKind.none,
      futureGiftIntent = '';

  final bool shouldSendRedPacket;
  final String reason;
  final AiRedPacketOpportunityKind kind;

  /// Reserved for a future Gift System. It has no behavior in this version.
  final String futureGiftIntent;
}
