enum ChatImageSubject { object, environment, selfie, outfit, character, other }

enum ChatCharacterPresence { none, required }

class ChatImageSceneIntent {
  const ChatImageSceneIntent({
    required this.subject,
    required this.characterPresence,
    required this.visualFocus,
    this.requiredCharacterIds = const [],
    this.mood = '',
  });

  final ChatImageSubject subject;
  final ChatCharacterPresence characterPresence;
  final String visualFocus;
  final List<String> requiredCharacterIds;
  final String mood;
}
