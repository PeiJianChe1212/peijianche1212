import '../models/character_profile.dart';
import '../models/echo_image_intent.dart';
import '../models/peilink_character_visual_profile.dart';
import '../models/peilink_visual_intent.dart';
import 'peilink_image_prompt_builder.dart';

class EchoImagePrompt {
  const EchoImagePrompt._();

  static String build({
    required EchoImageIntent intent,
    CharacterProfile? characterProfile,
  }) {
    if (!intent.shouldGenerateImage || intent.visualFocus.trim().isEmpty) {
      return '';
    }
    final visualProfile = characterProfile == null
        ? null
        : PeiLinkCharacterVisualProfile.fromProfile(characterProfile);
    final profiles = visualProfile == null
        ? const <String, PeiLinkCharacterVisualProfile>{}
        : {visualProfile.characterId: visualProfile};
    return PeiLinkImagePromptBuilder.build(
      intent: PeiLinkVisualIntent(
        subject: _subject(intent.subjectType),
        characterPresence: switch (intent.characterPresence) {
          EchoCharacterPresence.none => PeiLinkCharacterPresence.none,
          EchoCharacterPresence.optional => PeiLinkCharacterPresence.optional,
          EchoCharacterPresence.required => PeiLinkCharacterPresence.required,
        },
        visualFocus: intent.visualFocus,
        mood: intent.mood,
        requiredCharacterIds: intent.requiredCharacterIds,
        includeEyes: intent.subjectType == EchoImageSubjectType.selfie,
        includeClothing: intent.subjectType == EchoImageSubjectType.outfit,
        includeBodyProportions: const {
          EchoImageSubjectType.outfit,
          EchoImageSubjectType.group,
        }.contains(intent.subjectType),
      ),
      context: PeiLinkVisualContext(characterProfiles: profiles),
    );
  }

  static PeiLinkVisualSubject _subject(EchoImageSubjectType subject) =>
      switch (subject) {
        EchoImageSubjectType.object => PeiLinkVisualSubject.object,
        EchoImageSubjectType.food => PeiLinkVisualSubject.food,
        EchoImageSubjectType.environment => PeiLinkVisualSubject.environment,
        EchoImageSubjectType.scenery => PeiLinkVisualSubject.scenery,
        EchoImageSubjectType.workStudy => PeiLinkVisualSubject.workStudy,
        EchoImageSubjectType.shopping => PeiLinkVisualSubject.shopping,
        EchoImageSubjectType.travel => PeiLinkVisualSubject.travel,
        EchoImageSubjectType.pet => PeiLinkVisualSubject.pet,
        EchoImageSubjectType.screenshotLike => PeiLinkVisualSubject.interface,
        EchoImageSubjectType.character => PeiLinkVisualSubject.character,
        EchoImageSubjectType.selfie => PeiLinkVisualSubject.selfie,
        EchoImageSubjectType.outfit => PeiLinkVisualSubject.outfit,
        EchoImageSubjectType.group => PeiLinkVisualSubject.group,
        EchoImageSubjectType.other => PeiLinkVisualSubject.other,
      };
}

String echoImageStatus({
  required String prompt,
  required String imagePath,
  required bool generationFailed,
}) {
  if (imagePath.trim().isNotEmpty) return 'generated';
  if (prompt.trim().isEmpty) return 'not_needed';
  return generationFailed ? 'failed' : 'pending';
}
