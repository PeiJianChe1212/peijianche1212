import '../models/chat_message.dart';

class PhysicalSessionTurn {
  const PhysicalSessionTurn({
    required this.userTranscript,
    required this.assistantSpokenText,
    required this.completedAt,
    this.displayText,
  });

  final String userTranscript;
  final String assistantSpokenText;

  /// Complete character reply for UI/session/next-turn context. When absent,
  /// [assistantSpokenText] is used for backward compatibility.
  final String? displayText;
  final DateTime completedAt;

  int get characterCount =>
      userTranscript.length + (displayText ?? assistantSpokenText).length;
}

class PhysicalSessionMemory {
  PhysicalSessionMemory({this.maxTurns = 8, this.maxCharacters = 4000});

  final int maxTurns;
  final int maxCharacters;
  final List<PhysicalSessionTurn> _turns = [];

  List<PhysicalSessionTurn> get turns => List.unmodifiable(_turns);
  int get turnCount => _turns.length;

  void add(PhysicalSessionTurn turn) {
    _turns.add(turn);
    while (_turns.length > maxTurns) {
      _turns.removeAt(0);
    }
    while (_turns.length > 1 && _characterCount > maxCharacters) {
      _turns.removeAt(0);
    }
  }

  List<ChatMessage> toChatMessages() => List.unmodifiable([
    for (final turn in _turns) ...[
      ChatMessage(
        role: 'user',
        content: turn.userTranscript,
        createdAt: turn.completedAt,
        source: 'physical',
      ),
      ChatMessage(
        role: 'assistant',
        content: turn.displayText ?? turn.assistantSpokenText,
        createdAt: turn.completedAt,
        source: 'physical',
      ),
    ],
  ]);

  void clear() => _turns.clear();

  int get _characterCount =>
      _turns.fold(0, (total, turn) => total + turn.characterCount);
}