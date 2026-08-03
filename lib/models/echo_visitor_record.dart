enum EchoVisitorType { user, character, world }

class EchoVisitorRecord {
  const EchoVisitorRecord({
    required this.id,
    required this.spaceOwnerId,
    required this.visitorId,
    required this.visitorType,
    required this.visitTime,
    this.visitorName = '',
    this.visitorAvatarPath = '',
  });

  final String id;
  final String spaceOwnerId;
  final String visitorId;
  final EchoVisitorType visitorType;
  final DateTime visitTime;
  final String visitorName;
  final String visitorAvatarPath;

  Map<String, dynamic> toJson() => {
    'id': id,
    'spaceOwnerId': spaceOwnerId,
    'visitorId': visitorId,
    'visitorType': visitorType.name,
    'visitTime': visitTime.toIso8601String(),
    'visitorName': visitorName,
    'visitorAvatarPath': visitorAvatarPath,
  };

  factory EchoVisitorRecord.fromJson(Map<dynamic, dynamic> json) =>
      EchoVisitorRecord(
        id: json['id']?.toString() ?? '',
        spaceOwnerId: json['spaceOwnerId']?.toString() ?? '',
        visitorId: json['visitorId']?.toString() ?? '',
        visitorType: EchoVisitorType.values.firstWhere(
          (value) => value.name == json['visitorType']?.toString(),
          orElse: () => EchoVisitorType.user,
        ),
        visitTime:
            DateTime.tryParse(json['visitTime']?.toString() ?? '') ??
            DateTime.now(),
        visitorName: json['visitorName']?.toString() ?? '',
        visitorAvatarPath: json['visitorAvatarPath']?.toString() ?? '',
      );
}
