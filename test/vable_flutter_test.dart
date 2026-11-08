import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vable_flutter/vable_flutter.dart';
import 'package:vable_flutter/vable_flutter_platform_interface.dart';
import 'package:vable_flutter/vable_flutter_method_channel.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

class MockVableFlutterPlatform
    with MockPlatformInterfaceMixin
    implements VableFlutterPlatform {

  @override
  Future<String?> getPlatformVersion() => Future.value('42');

  /// The access token each initialize or setAccessToken call passed, in order.
  final List<String?> accessTokens = [];

  @override
  Future<bool> initialize(
    String publicKey, {
    String? environment,
    bool debugLogging = false,
    String? accessToken,
  }) {
    accessTokens.add(accessToken);
    return Future.value(true);
  }

  @override
  Future<void> setAccessToken(String? accessToken) {
    accessTokens.add(accessToken);
    return Future.value();
  }

  @override
  Future<void> setMicrophoneMuted(bool muted) => Future.value();

  @override
  Future<void> setCallPillPosition(String position) => Future.value();

  @override
  Future<void> setCallStyle(String style) => Future.value();

  @override
  Future<void> setGlowColor(int argb) => Future.value();

  @override
  Future<void> setEndButtonVisible(bool visible) => Future.value();

  @override
  Future<bool> startVoiceChat() => Future.value(true);

  @override
  Future<bool> endVoiceChat() => Future.value(true);

  @override
  Future<bool> isVoiceChatActive() => Future.value(false);

  /// What the last updateIntents call sent.
  Map<String, dynamic>? lastContext;

  @override
  Future<bool> updateIntents(Map<String, dynamic> contextUpdate) {
    lastContext = contextUpdate;
    return Future.value(true);
  }

  @override
  Future<bool> sendToolResult(String toolName, String? toolId, String result) => Future.value(true);

  @override
  Future<Map<dynamic, dynamic>?> getScreenFrames() => Future.value(null);

  /// The chat calls made, in order.
  final List<String> chatCalls = [];
  List<dynamic> storedMessages = const [];

  @override
  Future<void> openChat() async => chatCalls.add('openChat');

  @override
  Future<void> closeChat() async => chatCalls.add('closeChat');

  @override
  Future<bool> isChatOpen() => Future.value(false);

  @override
  Future<void> sendChatMessage(String text) async => chatCalls.add('send:$text');

  @override
  Future<List<dynamic>> getChatMessages() => Future.value(storedMessages);

  @override
  Future<void> startNewChat() async => chatCalls.add('startNewChat');

  @override
  Future<void> setChatButtonVisible(bool visible) async => chatCalls.add('chatButton:$visible');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final VableFlutterPlatform initialPlatform = VableFlutterPlatform.instance;

  test('$MethodChannelVableFlutter is the default instance', () {
    expect(initialPlatform, isInstanceOf<MethodChannelVableFlutter>());
  });

  test('getPlatformVersion', () async {
    MockVableFlutterPlatform fakePlatform = MockVableFlutterPlatform();
    VableFlutterPlatform.instance = fakePlatform;

    expect(await Vable.getPlatformVersion(), '42');
  });

  test("sending routes keeps the app's own intents", () async {
    final platform = MockVableFlutterPlatform();
    VableFlutterPlatform.instance = platform;

    await Vable.registerIntent(VableIntent(name: 'startErrandRequest', onIntent: (_) => 'ok'));
    await Vable.initialize('key', routes: [const VableRoute(path: '/home')]);

    final intents = (platform.lastContext!['intents'] as List).map((i) => (i as Map)['name']);
    expect(intents, contains('startErrandRequest'));
    expect(platform.lastContext!['routes'], isNotEmpty);
  });

  test('chat lines read from what the native SDKs send', () {
    final messages = VableChatMessage.listFrom([
      {'id': 'a', 'role': 'user', 'text': 'Hi', 'isStreaming': false, 'timestamp': 1000},
      {'id': 'b', 'role': 'assistant', 'text': 'Hel', 'isStreaming': true, 'timestamp': 2000},
      {'id': 'c', 'role': 'action', 'text': 'Opening Orders', 'isStreaming': false, 'timestamp': 3000},
      {'id': 'd', 'role': 'something_new', 'text': '?', 'timestamp': 4000},
    ]);
    expect(messages.map((m) => m.role), [VableChatRole.user, VableChatRole.assistant, VableChatRole.action]);
    expect(messages[1].isStreaming, isTrue);
    expect(messages[2].timestamp, DateTime.fromMillisecondsSinceEpoch(3000));
    expect(VableChatMessage.listFrom(null), isEmpty);
  });

  testWidgets('openChat loads the conversation, then opens the native chat', (tester) async {
    final platform = MockVableFlutterPlatform()
      ..storedMessages = [
        {'id': 'a', 'role': 'call', 'text': 'Voice call · 2 min', 'isStreaming': false, 'timestamp': 1},
      ];
    VableFlutterPlatform.instance = platform;
    late BuildContext context;
    await tester.pumpWidget(MaterialApp(home: Builder(builder: (c) {
      context = c;
      return const SizedBox();
    })));

    await Vable.openChat(context);
    expect(platform.chatCalls, ['openChat']);
    expect(Vable.currentChatMessages.single.role, VableChatRole.call);
    expect(Vable.isScreenScanningActive, isTrue);

    // Closing on the native side stops the scanning the chat needed
    Vable.handleChatClosed();
    expect(Vable.isScreenScanningActive, isFalse);
  });

  test('the chat API reaches the platform', () async {
    final platform = MockVableFlutterPlatform();
    VableFlutterPlatform.instance = platform;

    await Vable.sendMessage('Where is my order?');
    await Vable.startNewChat();
    await Vable.setChatButtonVisible(false);
    await Vable.closeChat();

    expect(platform.chatCalls, ['send:Where is my order?', 'startNewChat', 'chatButton:false', 'closeChat']);
  });

  test('chat updates from the native side reach the stream', () async {
    final seen = <List<VableChatMessage>>[];
    final sub = Vable.chatMessages.listen(seen.add);
    String? failed;
    Vable.onChatError = (code) => failed = code;

    Vable.handleChatUpdated(VableChatMessage.listFrom([
      {'id': 'a', 'role': 'assistant', 'text': 'Done', 'isStreaming': false, 'timestamp': 1},
    ]));
    Vable.handleChatError('tokens_exhausted');
    await Future<void>.delayed(Duration.zero);

    expect(seen.single.single.text, 'Done');
    expect(Vable.currentChatMessages.single.text, 'Done');
    expect(failed, 'tokens_exhausted');
    await sub.cancel();
    Vable.onChatError = null;
  });

  test('the access token goes to the platform at initialize and when it changes', () async {
    final platform = MockVableFlutterPlatform();
    VableFlutterPlatform.instance = platform;

    await Vable.initialize('key', accessToken: 'first');
    await Vable.setAccessToken('refreshed');
    await Vable.setAccessToken(null);

    expect(platform.accessTokens, ['first', 'refreshed', null]);
  });
}
