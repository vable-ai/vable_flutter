import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vable_flutter/vable_flutter_method_channel.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  MethodChannelVableFlutter platform = MethodChannelVableFlutter();
  const MethodChannel channel = MethodChannel('vable_flutter');

  final List<MethodCall> calls = [];

  setUp(() {
    calls.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      channel,
      (MethodCall methodCall) async {
        calls.add(methodCall);
        if (methodCall.method == 'getPlatformVersion') return '42';
        return true;
      },
    );
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, null);
  });

  test('getPlatformVersion', () async {
    expect(await platform.getPlatformVersion(), '42');
  });

  test('initialize sends the access token only when there is one', () async {
    await platform.initialize('pk', accessToken: 'user.jwt.token');
    await platform.initialize('pk');

    expect(calls[0].method, 'initialize');
    expect((calls[0].arguments as Map)['accessToken'], 'user.jwt.token');
    expect((calls[1].arguments as Map).containsKey('accessToken'), isFalse);
  });

  test('setAccessToken sends the new token, or null to clear it', () async {
    await platform.setAccessToken('refreshed');
    await platform.setAccessToken(null);

    expect(calls.map((c) => c.method), ['setAccessToken', 'setAccessToken']);
    expect(calls.map((c) => (c.arguments as Map)['accessToken']), ['refreshed', null]);
  });

  test('the chat methods go over the channel', () async {
    await platform.openChat();
    await platform.sendChatMessage('Hi');
    await platform.startNewChat();
    await platform.setChatButtonVisible(false);
    await platform.closeChat();

    expect(calls.map((c) => c.method), ['openChat', 'sendChatMessage', 'startNewChat', 'setChatButtonVisible', 'closeChat']);
    expect((calls[1].arguments as Map)['text'], 'Hi');
    expect((calls[3].arguments as Map)['visible'], false);
  });
}
