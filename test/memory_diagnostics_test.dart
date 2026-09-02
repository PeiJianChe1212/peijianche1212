import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:peijianche_app/models/event_memory.dart';
import 'package:peijianche_app/services/event_memory_lifecycle_service.dart';
import 'package:peijianche_app/services/memory2_retriever.dart';
import 'package:peijianche_app/services/memory2_storage_service.dart';
import 'package:peijianche_app/services/memory_diagnostics_service.dart';

void main() {
  late Directory directory;

  Future<File> fileProvider(String characterId, String fileName) async {
    final role = Directory('${directory.path}/$characterId');
    await role.create(recursive: true);
    return File('${role.path}/$fileName');
  }

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('memory_diagnostics_');
    MemoryDiagnosticsService.debugEnabledOverride = true;
    MemoryDiagnosticsService.clearForTests();
  });

  tearDown(() async {
    MemoryDiagnosticsService.debugEnabledOverride = null;
    MemoryDiagnosticsService.clearForTests();
    if (await directory.exists()) await directory.delete(recursive: true);
  });

  MemoryExtractionReport extraction(int index) => MemoryExtractionReport(
    characterId: 'role-a',
    triggeredAt: DateTime.utc(2026, 1, index + 1),
    result: 'success',
    eventTexts: ['private event $index'],
  );

  MemoryRetrieverReport retrieverReport() => MemoryRetrieverReport(
    characterId: 'role-a',
    createdAt: DateTime.utc(2026, 1, 1),
    queryLength: 4,
    recallIntent: false,
    eventCandidates: 4,
    userCandidates: 1,
    legacyCandidates: 0,
    eventItems: const [
      MemoryRetrieverItemReport(
        id: 'selected',
        status: 'active',
        score: .9,
        reason: MemoryDiagnosticReason.selected,
      ),
      MemoryRetrieverItemReport(
        id: 'forgotten',
        status: 'forgotten',
        score: .9,
        reason: MemoryDiagnosticReason.forgotten,
      ),
      MemoryRetrieverItemReport(
        id: 'weak',
        status: 'active',
        score: .01,
        reason: MemoryDiagnosticReason.lowRelevance,
      ),
      MemoryRetrieverItemReport(
        id: 'trimmed',
        status: 'active',
        score: .4,
        reason: MemoryDiagnosticReason.budgetTrimmed,
      ),
    ],
    selectedEventCount: 1,
    selectedUserCount: 1,
    legacyFallbackCount: 0,
    summaryInjected: false,
    contextCharacters: 120,
  );

  test('keeps only the newest ten reports in each ring', () {
    for (var i = 0; i < 12; i++) {
      MemoryDiagnosticsService.recordExtraction(extraction(i));
      MemoryDiagnosticsService.recordRetriever(retrieverReport());
    }
    expect(MemoryDiagnosticsService.extractionReports, hasLength(10));
    expect(MemoryDiagnosticsService.retrieverReports, hasLength(10));
    expect(
      MemoryDiagnosticsService.extractionReports.first.triggeredAt,
      DateTime.utc(2026, 1, 3),
    );
  });

  test(
    'retriever reports selected, forgotten, low relevance and budget trim',
    () {
      MemoryDiagnosticsService.recordRetriever(retrieverReport());
      final report = MemoryDiagnosticsService.retrieverFor('role-a')!;
      expect(report.selectedEventCount, 1);
      expect(
        report.eventItems.map((item) => item.reason),
        containsAll([
          MemoryDiagnosticReason.selected,
          MemoryDiagnosticReason.forgotten,
          MemoryDiagnosticReason.lowRelevance,
          MemoryDiagnosticReason.budgetTrimmed,
        ]),
      );
    },
  );

  test('records prompt injection and recall success/failure counts', () {
    MemoryDiagnosticsService.recordRetriever(retrieverReport());
    MemoryDiagnosticsService.recordPromptInjection(
      characterId: 'role-a',
      eventIds: ['selected'],
      characterUserProfileInjected: true,
    );
    MemoryDiagnosticsService.recordRecall(characterId: 'role-a', success: true);
    MemoryDiagnosticsService.recordRecall(
      characterId: 'role-a',
      success: false,
    );
    final report = MemoryDiagnosticsService.retrieverFor('role-a')!;
    expect(report.injectedEventIds, ['selected']);
    expect(report.characterUserProfileInjected, isTrue);
    expect(report.recallSuccessCount, 1);
    expect(report.recallFailureCount, 1);
  });

  test('diagnostics disabled does not retain reports', () {
    MemoryDiagnosticsService.debugEnabledOverride = false;
    MemoryDiagnosticsService.recordExtraction(extraction(1));
    MemoryDiagnosticsService.recordRetriever(retrieverReport());
    MemoryDiagnosticsService.recordPromptInjection(
      characterId: 'role-a',
      eventIds: ['selected'],
      characterUserProfileInjected: true,
    );
    MemoryDiagnosticsService.recordRecall(characterId: 'role-a', success: true);
    expect(MemoryDiagnosticsService.extractionReports, isEmpty);
    expect(MemoryDiagnosticsService.retrieverReports, isEmpty);
  });

  test('retriever logger contains no memory body text', () async {
    final storage = Memory2StorageService(
      characterId: 'role-a',
      fileProvider: fileProvider,
    );
    final event = EventMemory(
      id: 'event-a',
      characterId: 'role-a',
      content: 'secret body text',
      createdAt: DateTime.utc(2026, 1, 1),
    );
    await storage.saveEventMemories([event]);
    final logs = <String>[];
    await Memory2Retriever(
      characterId: 'role-a',
      storage: storage,
      lifecycle: EventMemoryLifecycleService(
        characterId: 'role-a',
        storage: storage,
      ),
      legacyLoader: () async => const [],
      logger: logs.add,
    ).retrieve(
      currentMessage: 'unrelated query',
      now: DateTime.utc(2026, 1, 2),
    );
    expect(logs.join('\n'), isNot(contains('secret body text')));
  });

  test('diagnostic injection can be absent without creating a report', () {
    MemoryDiagnosticsService.recordPromptInjection(
      characterId: 'missing',
      eventIds: const [],
      characterUserProfileInjected: false,
    );
    MemoryDiagnosticsService.recordRecall(
      characterId: 'missing',
      success: false,
    );
    expect(MemoryDiagnosticsService.retrieverReports, isEmpty);
  });

  test('extraction report exposes cursor outcome without advancing it', () {
    MemoryDiagnosticsService.recordExtraction(
      MemoryExtractionReport(
        characterId: 'role-a',
        triggeredAt: DateTime.utc(2026, 1, 1),
        result: 'insufficientMessages',
        batchMessageCount: 2,
        userMessageCount: 1,
        cursorAdvanced: false,
      ),
    );
    final report = MemoryDiagnosticsService.extractionFor('role-a')!;
    expect(report.result, 'insufficientMessages');
    expect(report.batchMessageCount, 2);
    expect(report.userMessageCount, 1);
    expect(report.cursorAdvanced, isFalse);
    expect(MemoryDiagnosticsService.extractionReports, hasLength(1));
  });
}
