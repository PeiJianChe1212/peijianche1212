class RedPacketData {
  const RedPacketData({
    required this.amount,
    required this.message,
    required this.senderId,
    this.receiverId = '',
    this.isOpened = false,
    this.openedAt,
  }) : assert(amount >= 0, 'Red packet amount cannot be negative.');

  /// Amount in the smallest currency unit (cents/fen).
  final int amount;
  final String message;
  final String senderId;
  final String receiverId;
  final bool isOpened;
  final DateTime? openedAt;

  RedPacketData copyWith({
    int? amount,
    String? message,
    String? senderId,
    String? receiverId,
    bool? isOpened,
    DateTime? openedAt,
  }) {
    return RedPacketData(
      amount: amount ?? this.amount,
      message: message ?? this.message,
      senderId: senderId ?? this.senderId,
      receiverId: receiverId ?? this.receiverId,
      isOpened: isOpened ?? this.isOpened,
      openedAt: openedAt ?? this.openedAt,
    );
  }

  Map<String, dynamic> toJson() => {
    'amount': amount,
    'message': message,
    'senderId': senderId,
    'receiverId': receiverId,
    'isOpened': isOpened,
    'openedAt': openedAt?.toIso8601String(),
  };

  factory RedPacketData.fromJson(Map<dynamic, dynamic> json) {
    final amount =
        int.tryParse(
          (json['amount'] ?? json['amountInCents'])?.toString() ?? '',
        ) ??
        0;
    return RedPacketData(
      amount: amount < 0 ? 0 : amount,
      message: json['message']?.toString() ?? '',
      senderId: json['senderId']?.toString() ?? '',
      receiverId: json['receiverId']?.toString() ?? '',
      isOpened: json['isOpened'] == true,
      openedAt: DateTime.tryParse(json['openedAt']?.toString() ?? ''),
    );
  }
}
