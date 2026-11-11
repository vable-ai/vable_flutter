import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vable_flutter/vable_flutter.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('vable_flutter');

  test('every log line goes to the native SDK, debug included, whatever enabled is', () async {
    final logged = <Map<Object?, Object?>>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'log') logged.add(call.arguments as Map<Object?, Object?>);
      return null;
    });
    addTearDown(() => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null));

    VableLogger.enabled = false;
    VableLogger.debug('scanning', tag: 'screen');
    VableLogger.info('started');
    VableLogger.warn('slow');
    VableLogger.error('failed', fields: {'code': '500'});
    await Future<void>.delayed(Duration.zero);

    expect(logged.map((e) => e['level']), ['debug', 'info', 'warn', 'error']);
    expect(logged[0]['tag'], 'screen');
    expect(logged[1]['tag'], 'flutter');
    expect(logged[0].containsKey('fields'), isFalse);
    expect(logged[3]['fields'], {'code': '500'});
  });
}
