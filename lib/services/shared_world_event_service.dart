import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../models/ai_character.dart';
import '../models/life_moment.dart';
import 'character_registry_service.dart';
import 'life_moment_storage_service.dart';

class SharedWorldEventService {
  static const String _fileName = 'shared_world_events.json';

  Future<File> _file() async {
    final directory = await getApplicationDocumentsDirectory();
    return File('${directory.path}/$_fileName');
  }

  Future<void> recordConfirmedMoment({
    required AiCharacter originCharacter,
    required LifeMomentCandidate moment,
    DateTime? occurredAt,
  }) async {
    final time = occurredAt ?? moment.occurredAt;
    final characters = await CharacterRegistryService().loadCharacters();
    final related = _resolveRelatedCharacters(
      originCharacter: originCharacter,
      moment: moment,
      characters: characters,
    );

    if (related.isEmpty) return;

    final eventId = 'world_${time.microsecondsSinceEpoch}_${moment.id}';
    final record = <String, dynamic>{
      'id': eventId,
      'originCharacterId': originCharacter.id,
      'originCharacterName': originCharacter.characterName,
      'participantCharacterIds': [
        originCharacter.id,
        ...related.map((item) => item.id),
      ],
      'participantCharacterNames': [
        originCharacter.characterName,
        ...related.map((item) => item.characterName),
      ],
      'scene': moment.scene,
      'event': moment.event,
      'detail': moment.detail,
      'feeling': moment.feeling,
      'relationshipOpportunityId': moment.relationshipOpportunityId,
      'occurredAt': time.toIso8601String(),
      'createdAt': DateTime.now().toIso8601String(),
    };

    final records = await _loadRecords();
    records.removeWhere((item) => item['id']?.toString() == eventId);
    records.insert(0, record);
    await _saveRecords(records.take(120).toList());

    for (final character in related) {
      final mirroredNames = <String>{
        originCharacter.characterName,
        originCharacter.displayName,
        ...related
            .where((item) => item.id != character.id)
            .expand((item) => [item.characterName, item.displayName]),
      }..removeWhere((name) => name.trim().isEmpty);

      final mirrored = moment.copyWith(
        id: '${eventId}_${character.id}',
        occurredAt: time,
        relatedCharacterNames: mirroredNames.take(2).toList(),
      );
      await LifeMomentStorageService(characterId: character.id).addItem(mirrored);
    }
  }

  Future<List<Map<String, dynamic>>> loadRecentForCharacter(
    String characterId, {
    int limit = 20,
    Duration maxAge = const Duration(days: 7),
  }) async {
    final earliest = DateTime.now().subtract(maxAge);
    final records = await _loadRecords();
    return records.where((record) {
      final ids = record['participantCharacterIds'];
      final occurredAt = DateTime.tryParse(
        record['occurredAt']?.toString() ?? '',
      );
      return ids is List &&
          ids.map((item) => item.toString()).contains(characterId) &&
          occurredAt != null &&
          occurredAt.isAfter(earliest);
    }).take(limit).toList();
  }

  Future<String> buildChatPromptSection(
    String characterId, {
    int limit = 6,
  }) async {
    final records = await loadRecentForCharacter(
      characterId,
      limit: limit,
      maxAge: const Duration(days: 7),
    );
    if (records.isEmpty) return '';

    final lines = records.map((record) => _formatRecord(record)).join('\n');
    return '''
【共享世界中的已确认经历】
$lines

这些事情已经真实发生，并且参与者都应记得同一件事。
可以在话题自然相关时提起，但不要每轮主动复述，也不要凭空增加没有记录的共同经历。
不同角色可以对同一事件有不同感受，但时间、地点与核心事实必须保持一致。
''';
  }

  Future<String> buildLifeEngineSection(
    String characterId, {
    int limit = 8,
  }) async {
    final records = await loadRecentForCharacter(
      characterId,
      limit: limit,
      maxAge: const Duration(days: 10),
    );
    if (records.isEmpty) return '无。';
    return records.map(_formatRecord).join('\n');
  }

  String _formatRecord(Map<String, dynamic> record) {
    final time = DateTime.tryParse(record['occurredAt']?.toString() ?? '');
    final date = time == null ? '日期未知' : '${time.month}/${time.day}';
    final names = record['participantCharacterNames'];
    final participants = names is List
        ? names.map((item) => item.toString().trim()).where((item) => item.isNotEmpty).join('、')
        : '';
    final scene = record['scene']?.toString().trim() ?? '';
    final event = record['event']?.toString().trim() ?? '';
    final detail = record['detail']?.toString().trim() ?? '';

    final parts = <String>[
      if (participants.isNotEmpty) '参与者：$participants',
      if (scene.isNotEmpty) '场景：$scene',
      if (event.isNotEmpty) '事件：$event',
      if (detail.isNotEmpty) '细节：$detail',
    ];
    return '- $date，${parts.join('；')}';
  }

  List<AiCharacter> _resolveRelatedCharacters({
    required AiCharacter originCharacter,
    required LifeMomentCandidate moment,
    required List<AiCharacter> characters,
  }) {
    final names = moment.relatedCharacterNames
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty)
        .toSet();
    if (names.isEmpty) return const [];

    return characters.where((character) {
      if (character.id == originCharacter.id) return false;
      return names.contains(character.characterName) ||
          names.contains(character.displayName);
    }).take(1).toList();
  }

  Future<List<Map<String, dynamic>>> _loadRecords() async {
    final file = await _file();
    if (!await file.exists()) return [];
    try {
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! List) return [];
      return decoded
          .whereType<Map>()
          .map((item) => Map<String, dynamic>.from(item))
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> _saveRecords(List<Map<String, dynamic>> records) async {
    final file = await _file();
    await file.writeAsString(jsonEncode(records), flush: true);
  }
}
