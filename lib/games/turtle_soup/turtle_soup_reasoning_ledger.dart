class PublicReasoningClue {
  PublicReasoningClue({
    required this.text,
    required List<String> provenanceMessageIds,
    required this.updatedAtTurn,
  }) : provenanceMessageIds = List.unmodifiable(provenanceMessageIds);
  final String text;
  final List<String> provenanceMessageIds;
  final int updatedAtTurn;
  String get source => 'hint';
  Map<String, dynamic> toJson() => {
    'text': text,
    'source': source,
    'provenanceMessageIds': provenanceMessageIds,
    'updatedAtTurn': updatedAtTurn,
  };
  factory PublicReasoningClue.fromJson(Map<dynamic, dynamic> json) =>
      PublicReasoningClue(
        text: json['text']?.toString() ?? '',
        provenanceMessageIds: (json['provenanceMessageIds'] as List? ?? [])
            .map((e) => e.toString())
            .toList(),
        updatedAtTurn: (json['updatedAtTurn'] as num?)?.toInt() ?? 0,
      );
}

class ReasoningLedgerEntry {
  const ReasoningLedgerEntry({
    required this.opaqueRef,
    required this.publicText,
    required this.provenanceMessageIds,
    required this.updatedAtTurn,
  });

  final String opaqueRef;
  final String publicText;
  final List<String> provenanceMessageIds;
  final int updatedAtTurn;

  Map<String, dynamic> toJson() => {
    'opaqueRef': opaqueRef,
    'publicText': publicText,
    'provenanceMessageIds': provenanceMessageIds,
    'updatedAtTurn': updatedAtTurn,
  };

  factory ReasoningLedgerEntry.fromJson(Map<dynamic, dynamic> json) =>
      ReasoningLedgerEntry(
        opaqueRef: json['opaqueRef']?.toString() ?? '',
        publicText: json['publicText']?.toString() ?? '',
        provenanceMessageIds:
            (json['provenanceMessageIds'] as List? ?? const [])
                .map((item) => item.toString())
                .toList(growable: false),
        updatedAtTurn: (json['updatedAtTurn'] as num?)?.toInt() ?? 0,
      );
}

class PublicReasoningItem {
  const PublicReasoningItem({
    required this.text,
    required this.provenanceMessageIds,
    required this.updatedAtTurn,
  });

  final String text;
  final List<String> provenanceMessageIds;
  final int updatedAtTurn;

  Map<String, dynamic> toJson() => {
    'text': text,
    'provenanceMessageIds': provenanceMessageIds,
    'updatedAtTurn': updatedAtTurn,
  };
}

/// Character/UI-safe view. It deliberately has no node-reference field.
class PublicReasoningLedgerView {
  const PublicReasoningLedgerView({
    required this.confirmedFacts,
    required this.partialFacts,
    required this.rejectedDirections,
    required this.resolvedEdges,
    required this.openQuestions,
    required this.exhaustedDirections,
    this.publicHintClues = const [],
  });

  final List<PublicReasoningItem> confirmedFacts;
  final List<PublicReasoningItem> partialFacts;
  final List<PublicReasoningItem> rejectedDirections;
  final List<PublicReasoningItem> resolvedEdges;
  final List<PublicReasoningItem> openQuestions;
  final List<PublicReasoningItem> exhaustedDirections;
  final List<PublicReasoningClue> publicHintClues;

  Map<String, dynamic> toJson() => {
    'publicHintClues': publicHintClues.map((item) => item.toJson()).toList(),
    'confirmedFacts': confirmedFacts.map((item) => item.toJson()).toList(),
    'partialFacts': partialFacts.map((item) => item.toJson()).toList(),
    'rejectedDirections': rejectedDirections
        .map((item) => item.toJson())
        .toList(),
    'resolvedEdges': resolvedEdges.map((item) => item.toJson()).toList(),
    'openQuestions': openQuestions.map((item) => item.toJson()).toList(),
    'exhaustedDirections': exhaustedDirections
        .map((item) => item.toJson())
        .toList(),
  };
}

class PublicReasoningLedger {
  PublicReasoningLedger({
    this.version = 1,
    required this.profileVersion,
    List<ReasoningLedgerEntry> confirmedFacts = const [],
    List<ReasoningLedgerEntry> partialFacts = const [],
    List<ReasoningLedgerEntry> rejectedDirections = const [],
    List<ReasoningLedgerEntry> resolvedEdges = const [],
    List<ReasoningLedgerEntry> openQuestions = const [],
    List<ReasoningLedgerEntry> exhaustedDirections = const [],
    List<PublicReasoningClue> publicHintClues = const [],
  }) : confirmedFacts = List.unmodifiable(confirmedFacts),
       partialFacts = List.unmodifiable(partialFacts),
       rejectedDirections = List.unmodifiable(rejectedDirections),
       resolvedEdges = List.unmodifiable(resolvedEdges),
       openQuestions = List.unmodifiable(openQuestions),
       exhaustedDirections = List.unmodifiable(exhaustedDirections),
       publicHintClues = List.unmodifiable(publicHintClues);

  final int version;
  final List<PublicReasoningClue> publicHintClues;
  final int profileVersion;
  final List<ReasoningLedgerEntry> confirmedFacts;
  final List<ReasoningLedgerEntry> partialFacts;
  final List<ReasoningLedgerEntry> rejectedDirections;
  final List<ReasoningLedgerEntry> resolvedEdges;
  final List<ReasoningLedgerEntry> openQuestions;
  final List<ReasoningLedgerEntry> exhaustedDirections;

  PublicReasoningLedger copyWith({
    List<PublicReasoningClue>? publicHintClues,
    int? version,
    int? profileVersion,
    List<ReasoningLedgerEntry>? confirmedFacts,
    List<ReasoningLedgerEntry>? partialFacts,
    List<ReasoningLedgerEntry>? rejectedDirections,
    List<ReasoningLedgerEntry>? resolvedEdges,
    List<ReasoningLedgerEntry>? openQuestions,
    List<ReasoningLedgerEntry>? exhaustedDirections,
  }) => PublicReasoningLedger(
    publicHintClues: publicHintClues ?? this.publicHintClues,
    version: version ?? this.version,
    profileVersion: profileVersion ?? this.profileVersion,
    confirmedFacts: confirmedFacts ?? this.confirmedFacts,
    partialFacts: partialFacts ?? this.partialFacts,
    rejectedDirections: rejectedDirections ?? this.rejectedDirections,
    resolvedEdges: resolvedEdges ?? this.resolvedEdges,
    openQuestions: openQuestions ?? this.openQuestions,
    exhaustedDirections: exhaustedDirections ?? this.exhaustedDirections,
  );

  PublicReasoningLedger withConfirmedFact(ReasoningLedgerEntry entry) =>
      copyWith(confirmedFacts: _upsert(confirmedFacts, entry));

  PublicReasoningLedger withPartialFact(ReasoningLedgerEntry entry) =>
      copyWith(partialFacts: _upsert(partialFacts, entry));

  PublicReasoningLedger withRejectedDirection(ReasoningLedgerEntry entry) =>
      copyWith(rejectedDirections: _upsert(rejectedDirections, entry));

  PublicReasoningLedger withResolvedEdge(ReasoningLedgerEntry entry) =>
      copyWith(resolvedEdges: _upsert(resolvedEdges, entry));

  PublicReasoningLedger withOpenQuestion(ReasoningLedgerEntry entry) =>
      copyWith(openQuestions: _upsert(openQuestions, entry));

  PublicReasoningLedger withExhaustedDirection(ReasoningLedgerEntry entry) =>
      copyWith(exhaustedDirections: _upsert(exhaustedDirections, entry));

  PublicReasoningLedgerView toPublicView() => PublicReasoningLedgerView(
    publicHintClues: publicHintClues,
    confirmedFacts: _public(confirmedFacts),
    // A partial node reference does not prove its entire approved summary.
    // Keep internal progress (including legacy saves), but never publish that
    // summary. Players can still read the actual public question and answer.
    partialFacts: const [],
    rejectedDirections: _public(rejectedDirections),
    resolvedEdges: _public(resolvedEdges),
    openQuestions: _public(openQuestions),
    exhaustedDirections: _public(exhaustedDirections),
  );

  Map<String, dynamic> toJson() => {
    'version': version,
    'publicHintClues': publicHintClues.map((item) => item.toJson()).toList(),
    'profileVersion': profileVersion,
    'confirmedFacts': confirmedFacts.map((item) => item.toJson()).toList(),
    'partialFacts': partialFacts.map((item) => item.toJson()).toList(),
    'rejectedDirections': rejectedDirections
        .map((item) => item.toJson())
        .toList(),
    'resolvedEdges': resolvedEdges.map((item) => item.toJson()).toList(),
    'openQuestions': openQuestions.map((item) => item.toJson()).toList(),
    'exhaustedDirections': exhaustedDirections
        .map((item) => item.toJson())
        .toList(),
  };

  factory PublicReasoningLedger.fromJson(Map<dynamic, dynamic> json) =>
      PublicReasoningLedger(
        publicHintClues: (json['publicHintClues'] as List? ?? const [])
            .whereType<Map>()
            .where((item) => item['source'] == 'hint')
            .map(PublicReasoningClue.fromJson)
            .toList(),
        version: (json['version'] as num?)?.toInt() ?? 1,
        profileVersion: (json['profileVersion'] as num?)?.toInt() ?? 0,
        confirmedFacts: _entries(json['confirmedFacts']),
        partialFacts: _entries(json['partialFacts']),
        rejectedDirections: _entries(json['rejectedDirections']),
        resolvedEdges: _entries(json['resolvedEdges']),
        openQuestions: _entries(json['openQuestions']),
        exhaustedDirections: _entries(json['exhaustedDirections']),
      );

  static List<ReasoningLedgerEntry> _upsert(
    List<ReasoningLedgerEntry> current,
    ReasoningLedgerEntry entry,
  ) => List.unmodifiable([
    ...current.where((item) => item.opaqueRef != entry.opaqueRef),
    entry,
  ]);

  static List<PublicReasoningItem> _public(
    List<ReasoningLedgerEntry> entries,
  ) => List.unmodifiable(
    entries.map(
      (entry) => PublicReasoningItem(
        text: entry.publicText,
        provenanceMessageIds: List.unmodifiable(entry.provenanceMessageIds),
        updatedAtTurn: entry.updatedAtTurn,
      ),
    ),
  );

  static List<ReasoningLedgerEntry> _entries(dynamic value) =>
      (value as List? ?? const [])
          .whereType<Map>()
          .map(ReasoningLedgerEntry.fromJson)
          .toList(growable: false);
}
