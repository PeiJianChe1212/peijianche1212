import 'dart:convert';

import '../models/echo_visitor_record.dart';
import 'character_scope_service.dart';

class EchoVisitorStorageService {
  EchoVisitorStorageService({required String ownerId})
    : _ownerId = ownerId,
      _scope = CharacterScopeService(ownerId);

  static const _fileName = 'echo_visitors.json';
  final String _ownerId;
  final CharacterScopeService _scope;

  Future<List<EchoVisitorRecord>> load() async {
    final file = await _scope.dataFile(_fileName);
    if (!await file.exists()) return [];
    try {
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! List) return [];
      final records =
          decoded
              .whereType<Map>()
              .map(EchoVisitorRecord.fromJson)
              .where((item) => item.id.isNotEmpty)
              .toList()
            ..sort((a, b) => b.visitTime.compareTo(a.visitTime));
      return records;
    } catch (_) {
      return [];
    }
  }

  Future<List<EchoVisitorRecord>> recordDailyVisit({
    required String visitorId,
    required String visitorName,
    required String visitorAvatarPath,
    DateTime? now,
  }) async {
    final time = now ?? DateTime.now();
    final day = '${time.year}-${time.month}-${time.day}';
    final id = '${_ownerId}_${visitorId}_$day';
    final records = await load();
    if (records.any((item) => item.id == id)) return records;
    final next = <EchoVisitorRecord>[
      EchoVisitorRecord(
        id: id,
        spaceOwnerId: _ownerId,
        visitorId: visitorId,
        visitorType: EchoVisitorType.user,
        visitTime: time,
        visitorName: visitorName,
        visitorAvatarPath: visitorAvatarPath,
      ),
      ...records,
    ];
    final file = await _scope.dataFile(_fileName);
    await file.writeAsString(
      jsonEncode(next.take(200).map((item) => item.toJson()).toList()),
      flush: true,
    );
    return next.take(200).toList();
  }
}
