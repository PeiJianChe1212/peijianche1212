import 'dart:convert';
import 'dart:io';

import '../config/peilink_runtime.dart';

import '../models/world_event.dart';
import '../models/world_resource.dart';

class SharedWorldResourceService {
  static const String _fileName = 'shared_world_resources.json';

  Future<File> _file() async {
    final directory = await getApplicationDocumentsDirectory();
    return File('${directory.path}/$_fileName');
  }

  Future<List<WorldResource>> loadAll({DateTime? now}) async {
    final time = now ?? DateTime.now();
    final file = await _file();
    if (!await file.exists()) return const [];
    try {
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! List) return const [];
      final resources = decoded
          .whereType<Map>()
          .map(WorldResource.fromJson)
          .where((item) => item.id.isNotEmpty && item.name.isNotEmpty)
          .map(
            (item) => item.copyWith(
              reservations: item.reservations
                  .where((reservation) => !reservation.isExpiredAt(time))
                  .toList(),
            ),
          )
          .toList();
      await _save(resources);
      return resources;
    } catch (_) {
      return const [];
    }
  }

  Future<void> syncFromWorldEvents(
    Iterable<WorldEvent> events, {
    DateTime? now,
  }) async {
    final time = now ?? DateTime.now();
    final resources = await loadAll(now: time);
    final byId = {for (final item in resources) item.id: item};

    for (final event in events) {
      final raw = event.metadata['resources'];
      if (raw is! List) continue;
      for (final entry in raw.whereType<Map>()) {
        final map = Map<String, dynamic>.from(entry);
        final id = map['id']?.toString().trim() ?? '';
        final name = map['name']?.toString().trim() ?? '';
        if (id.isEmpty || name.isEmpty) continue;
        final quantity = _readNonNegativeInt(map['quantity']);
        final old = byId[id];
        byId[id] = WorldResource(
          id: id,
          name: name,
          totalQuantity: quantity,
          remainingQuantity: old == null
              ? quantity
              : old.remainingQuantity.clamp(0, quantity).toInt(),
          updatedAt: time,
          locationId: map['locationId']?.toString().trim().isNotEmpty == true
              ? map['locationId'].toString().trim()
              : event.locationId,
          locationName:
              map['locationName']?.toString().trim().isNotEmpty == true
              ? map['locationName'].toString().trim()
              : event.locationName,
          sourceWorldEventId: event.id,
          isReusable: map['isReusable'] == true,
          reservations: old?.reservations ?? const [],
          metadata: map['metadata'] is Map
              ? Map<String, dynamic>.from(map['metadata'] as Map)
              : const {},
        );
      }
    }
    await _save(byId.values.toList());
  }

  Future<List<WorldResource>> loadAvailable({DateTime? now}) async {
    final time = now ?? DateTime.now();
    final resources = await loadAll(now: time);
    return resources.where((item) => item.availableAt(time) > 0).toList();
  }

  Future<bool> reserve({
    required String decisionId,
    required String characterId,
    required Map<String, int> claims,
    required DateTime scheduledAt,
    DateTime? now,
  }) async {
    if (claims.isEmpty) return true;
    final time = now ?? DateTime.now();
    final resources = await loadAll(now: time);
    final byId = {for (final item in resources) item.id: item};

    for (final entry in claims.entries) {
      final resource = byId[entry.key];
      if (resource == null || entry.value <= 0) return false;
      if (resource.availableAt(time) < entry.value) return false;
    }

    final expiryBase = scheduledAt.isAfter(time) ? scheduledAt : time;
    final expiresAt = expiryBase.add(const Duration(hours: 2));
    for (final entry in claims.entries) {
      final resource = byId[entry.key]!;
      final reservations =
          resource.reservations
              .where((item) => item.decisionId != decisionId)
              .toList()
            ..add(
              WorldResourceReservation(
                decisionId: decisionId,
                characterId: characterId,
                quantity: entry.value,
                reservedAt: time,
                expiresAt: expiresAt,
              ),
            );
      byId[entry.key] = resource.copyWith(
        reservations: reservations,
        updatedAt: time,
      );
    }
    await _save(byId.values.toList());
    return true;
  }

  Future<void> commitDecision(String decisionId, {DateTime? now}) async {
    final id = decisionId.trim();
    if (id.isEmpty) return;
    final time = now ?? DateTime.now();
    final resources = await loadAll(now: time);
    final updated = resources.map((resource) {
      final owned = resource.reservations
          .where((item) => item.decisionId == id)
          .fold<int>(0, (sum, item) => sum + item.quantity);
      if (owned == 0) return resource;
      final remaining = resource.isReusable
          ? resource.remainingQuantity
          : (resource.remainingQuantity - owned)
                .clamp(0, resource.totalQuantity)
                .toInt();
      return resource.copyWith(
        remainingQuantity: remaining,
        reservations: resource.reservations
            .where((item) => item.decisionId != id)
            .toList(),
        updatedAt: time,
      );
    }).toList();
    await _save(updated);
  }

  Future<void> releaseDecision(String decisionId, {DateTime? now}) async {
    final id = decisionId.trim();
    if (id.isEmpty) return;
    final time = now ?? DateTime.now();
    final resources = await loadAll(now: time);
    final updated = resources
        .map(
          (resource) => resource.copyWith(
            reservations: resource.reservations
                .where((item) => item.decisionId != id)
                .toList(),
            updatedAt: time,
          ),
        )
        .toList();
    await _save(updated);
  }

  Future<void> _save(List<WorldResource> resources) async {
    resources.sort((a, b) => a.name.compareTo(b.name));
    final file = await _file();
    await file.writeAsString(
      jsonEncode(resources.map((item) => item.toJson()).toList()),
      flush: true,
    );
  }

  int _readNonNegativeInt(dynamic value) {
    final parsed = value is num ? value.toInt() : int.tryParse('$value');
    if (parsed == null || parsed < 0) return 0;
    return parsed;
  }
}
