class RedPacketEventContext {
  const RedPacketEventContext.received();

  String toPromptSection() => '''[Temporary Chat Event]
User sent you a red packet.
You have received it.
Respond naturally in character.
Do not mention or guess the amount.''';
}
