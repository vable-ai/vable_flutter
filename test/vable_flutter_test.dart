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

  @override
  Future<bool> initialize(String publicKey) => Future.value(true);

  @override
  Future<bool> startVoiceChat() => Future.value(true);

  @override
  Future<bool> endVoiceChat() => Future.value(true);

  @override
  Future<bool> isVoiceChatActive() => Future.value(false);

  @override
  Future<bool> updateIntents(Map<String, dynamic> contextUpdate) => Future.value(true);
}

void main() {
  final VableFlutterPlatform initialPlatform = VableFlutterPlatform.instance;

  test('$MethodChannelVableFlutter is the default instance', () {
    expect(initialPlatform, isInstanceOf<MethodChannelVableFlutter>());
  });

  test('getPlatformVersion', () async {
    MockVableFlutterPlatform fakePlatform = MockVableFlutterPlatform();
    VableFlutterPlatform.instance = fakePlatform;

    expect(await Vable.getPlatformVersion(), '42');
  });
}
