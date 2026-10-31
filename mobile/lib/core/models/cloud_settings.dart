/// Cài đặt nơi nhận cảnh báo (khớp `/devices/<id>/control/settings`).
class CloudSettings {
  const CloudSettings({
    this.telegramOn = false,
    this.gmailOn = false,
    this.chatIds = '',
    this.emailTo = '',
    this.inactiveMin = defaultInactiveMin,
  });

  static const int defaultInactiveMin = 60;

  final bool telegramOn;
  final bool gmailOn;
  final String chatIds;
  final String emailTo;

  /// Cảnh báo bất động sau N phút, 0 = tắt.
  final int inactiveMin;

  /// Đúng 5 khóa mà database.rules.json cho phép.
  Map<String, dynamic> toJson() => {
        'telegramOn': telegramOn,
        'gmailOn': gmailOn,
        'chatIds': chatIds,
        'emailTo': emailTo,
        'inactiveMin': inactiveMin,
      };

  factory CloudSettings.fromJson(Map<dynamic, dynamic> j) {
    final minutes = j['inactiveMin'];
    return CloudSettings(
      telegramOn: j['telegramOn'] == true,
      gmailOn: j['gmailOn'] == true,
      chatIds: j['chatIds'] is String ? j['chatIds'] as String : '',
      emailTo: j['emailTo'] is String ? j['emailTo'] as String : '',
      inactiveMin: minutes is num ? minutes.toInt() : defaultInactiveMin,
    );
  }

  CloudSettings copyWith({
    bool? telegramOn,
    bool? gmailOn,
    String? chatIds,
    String? emailTo,
    int? inactiveMin,
  }) =>
      CloudSettings(
        telegramOn: telegramOn ?? this.telegramOn,
        gmailOn: gmailOn ?? this.gmailOn,
        chatIds: chatIds ?? this.chatIds,
        emailTo: emailTo ?? this.emailTo,
        inactiveMin: inactiveMin ?? this.inactiveMin,
      );

  @override
  bool operator ==(Object other) =>
      other is CloudSettings &&
      other.telegramOn == telegramOn &&
      other.gmailOn == gmailOn &&
      other.chatIds == chatIds &&
      other.emailTo == emailTo &&
      other.inactiveMin == inactiveMin;

  @override
  int get hashCode =>
      Object.hash(telegramOn, gmailOn, chatIds, emailTo, inactiveMin);
}
