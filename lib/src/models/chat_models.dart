/// Who a chat line is from, or what it records.
enum VableChatRole {
  /// Something the user typed.
  user,

  /// The assistant's reply.
  assistant,

  /// An action the assistant took in the app, such as opening a screen.
  action,

  /// A turn that failed.
  error,

  /// A voice call that took place in the same conversation.
  call,
}

/// One line of the text chat.
class VableChatMessage {
  const VableChatMessage({
    required this.id,
    required this.role,
    required this.text,
    required this.isStreaming,
    required this.timestamp,
  });

  final String id;
  final VableChatRole role;
  final String text;

  /// True while the assistant's reply is still arriving.
  final bool isStreaming;

  final DateTime timestamp;

  /// Reads a line as the native SDKs send it. Returns null for a role this
  /// version doesn't know.
  static VableChatMessage? fromMap(Map<dynamic, dynamic> map) {
    final roleName = map['role'] as String?;
    final role = VableChatRole.values.where((r) => r.name == roleName).firstOrNull;
    if (role == null) return null;
    return VableChatMessage(
      id: map['id'] as String? ?? '',
      role: role,
      text: map['text'] as String? ?? '',
      isStreaming: map['isStreaming'] as bool? ?? false,
      timestamp: DateTime.fromMillisecondsSinceEpoch((map['timestamp'] as num?)?.toInt() ?? 0),
    );
  }

  /// Reads the list the native SDKs send.
  static List<VableChatMessage> listFrom(dynamic value) {
    if (value is! List) return const [];
    return value.whereType<Map>().map(fromMap).whereType<VableChatMessage>().toList(growable: false);
  }

  @override
  String toString() => 'VableChatMessage(${role.name}: $text${isStreaming ? '…' : ''})';
}
