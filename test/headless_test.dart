import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vable_flutter/vable_flutter.dart';
import 'package:vable_flutter/vable_flutter_platform_interface.dart';

const _channel = MethodChannel('vable_flutter');

void main() {
  final manager = ScreenScannerManager();
  late List<VableEvent> events;
  late StreamSubscription<VableEvent> subscription;

  late Map<String, String> results;

  setUp(() {
    results = {};
    // Makes the method channel, which listens for the native side's calls
    VableFlutterPlatform.instance;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, (call) async {
      if (call.method == 'sendToolResult') {
        results[call.arguments['toolId'] as String] = call.arguments['result'] as String;
      }
      return true;
    });
    events = [];
    subscription = Vable.events.listen(events.add);
  });

  tearDown(() async {
    await subscription.cancel();
    Vable.setActionGate(null);
    Vable.setTyping(VableTyping.instant);
    Vable.resumeActions();
    await Vable.setCallStyle(VableCallStyle.glow);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, null);
  });

  Future<void> open(WidgetTester tester, Widget child) async {
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: Center(child: child))));
    final context = tester.element(find.byType(Navigator));
    manager.startScanning(context: context, scanInterval: const Duration(minutes: 1));
    for (var i = 0; i < 3; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    manager.stopScanning();
    manager.updateContext(context);
  }

  /// Sends a tool call the way the native SDKs do, without waiting for it.
  void send(String tool, Map<String, dynamic> parameters, String toolId) {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.handlePlatformMessage(
      'vable_flutter',
      const StandardMethodCodec().encodeMethodCall(
        MethodCall('onIntent', {'id': tool, 'parameters': parameters, 'toolId': toolId}),
      ),
      (_) {},
    );
  }

  /// Sends a tool call and waits for the result the agent gets.
  Future<String> agent(WidgetTester tester, String tool, Map<String, dynamic> parameters,
      {String toolId = 't1'}) async {
    send(tool, parameters, toolId);
    for (var i = 0; i < 60 && results[toolId] == null; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    manager.stopScanning();
    return results[toolId] ?? fail('the agent never got a result');
  }

  String idOf(String label) =>
      manager.lastClickableElements.lastWhere((e) => e.label == label).id;

  group('the action gate', () {
    testWidgets('sees the target before the tap, with where it is', (tester) async {
      var taps = 0;
      VableAction? seen;
      var tappedBeforeGate = false;
      Vable.setActionGate((action) {
        seen = action;
        tappedBeforeGate = taps > 0;
        return true;
      });
      await open(tester, ElevatedButton(onPressed: () => taps++, child: const Text('Search')));

      await agent(tester, 'clickElement', {'id': idOf('Search')});

      expect(tappedBeforeGate, isFalse);
      expect(taps, 1);
      expect(seen!.id, 't1');
      expect(seen!.kind, VableActionKind.click);
      expect(seen!.label, 'Search');
      expect(seen!.bounds, tester.getRect(find.byType(ElevatedButton)));
    });

    testWidgets('can say no, and the agent hears the user declined', (tester) async {
      var taps = 0;
      Vable.setActionGate((_) => false);
      await open(tester, ElevatedButton(onPressed: () => taps++, child: const Text('Search')));

      final result = await agent(tester, 'clickElement', {'id': idOf('Search')});

      expect(taps, 0);
      expect(result, startsWith('Not done: the user declined'));
      expect(events.whereType<VableActionStarted>(), isEmpty);
    });

    testWidgets('can take its time', (tester) async {
      var taps = 0;
      Vable.setActionGate((_) => Future.delayed(const Duration(milliseconds: 400), () => true));
      await open(tester, ElevatedButton(onPressed: () => taps++, child: const Text('Search')));

      final result = await agent(tester, 'clickElement', {'id': idOf('Search')});

      expect(taps, 1);
      expect(result, startsWith('Clicked.'));
    });

    testWidgets('also covers the app\'s own intents', (tester) async {
      var ran = false;
      await Vable.registerIntent(VableIntent(
        name: 'askUser',
        description: 'Ask',
        onIntent: (_) {
          ran = true;
          return 'The user chose Lisbon';
        },
      ));
      Vable.setActionGate((action) => action.kind != VableActionKind.intent);
      await open(tester, const Text('Home'));

      final result = await agent(tester, 'askUser', {'question': 'Where?'});

      expect(ran, isFalse);
      expect(result, startsWith('Not done: the user declined'));
      await Vable.unregisterIntent('askUser');
    });
  });

  group('pausing', () {
    testWidgets('holds an action until resumed', (tester) async {
      var taps = 0;
      await open(tester, ElevatedButton(onPressed: () => taps++, child: const Text('Search')));
      Vable.pauseActions();

      send('clickElement', {'id': idOf('Search')}, 'p1');
      for (var i = 0; i < 20; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(taps, 0);
      expect(Vable.agentState, VableAgentState.acting);

      Vable.resumeActions();
      for (var i = 0; i < 40 && results['p1'] == null; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      manager.stopScanning();
      expect(taps, 1);
      expect(results['p1'], startsWith('Clicked.'));
    });

    testWidgets('cancelling answers the waiting action instead of doing it', (tester) async {
      var taps = 0;
      await open(tester, ElevatedButton(onPressed: () => taps++, child: const Text('Search')));
      Vable.pauseActions();

      send('clickElement', {'id': idOf('Search')}, 'c1');
      await tester.pump(const Duration(milliseconds: 100));
      Vable.cancelCurrentTask();
      for (var i = 0; i < 10 && results['c1'] == null; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }

      expect(taps, 0);
      expect(results['c1'], startsWith('Not done: the user stopped this task'));
      expect(Vable.actionsPaused, isFalse);

      // An action already on its way is refused too, and then they run again
      final late = await agent(tester, 'clickElement', {'id': idOf('Search')}, toolId: 'c2');
      expect(late, startsWith('Not done: the user stopped this task'));
      await tester.pump(const Duration(seconds: 4));
      final next = await agent(tester, 'clickElement', {'id': idOf('Search')}, toolId: 'c3');
      expect(next, startsWith('Clicked.'));
      expect(taps, 1);
    });

    testWidgets('the user\'s change is passed on with the next result', (tester) async {
      await open(tester, ElevatedButton(onPressed: () {}, child: const Text('Search')));
      Vable.notifyUserInteraction(label: 'Check-in');

      final result = await agent(tester, 'scrollScreen', {'direction': 'down'});

      expect(result, endsWith('Meanwhile the user used "Check-in" themselves, so don\'t undo what they did there.'));
      final again = await agent(tester, 'scrollScreen', {'direction': 'down'}, toolId: 't2');
      expect(again, isNot(contains('Meanwhile')));
    });
  });

  group('events', () {
    testWidgets('an action starts and finishes with its result', (tester) async {
      await open(tester, ElevatedButton(onPressed: () {}, child: const Text('Search')));

      final result = await agent(tester, 'clickElement', {'id': idOf('Search')}, toolId: 'e1');

      final actions = events.whereType<VableEvent>().where((e) => e is VableActionStarted || e is VableActionFinished).toList();
      expect(actions, hasLength(2));
      final started = actions.first as VableActionStarted;
      final finished = actions.last as VableActionFinished;
      expect(started.action.id, 'e1');
      expect(finished.action.id, 'e1');
      expect(finished.ok, isTrue);
      expect(finished.result, result);
      expect(Vable.agentState, isNot(VableAgentState.acting));
    });

    testWidgets('a failed action finishes not ok', (tester) async {
      await open(tester, const Text('Nothing to scroll'));

      await agent(tester, 'scrollScreen', {'direction': 'down'});

      final finished = events.whereType<VableActionFinished>().single;
      expect(finished.ok, isFalse);
      expect(finished.action.kind, VableActionKind.scroll);
    });

    test('a chat reply streams as assistant text, thinking first', () async {
      final at = DateTime(2026);
      VableChatMessage reply(String text, {required bool streaming}) => VableChatMessage(
            id: 'a1',
            role: VableChatRole.assistant,
            text: text,
            isStreaming: streaming,
            timestamp: at,
          );

      Vable.handleChatUpdated([reply('', streaming: true)]);
      expect(Vable.agentState, VableAgentState.thinking);
      Vable.handleChatUpdated([reply('Lisbon has', streaming: true)]);
      Vable.handleChatUpdated([reply('Lisbon has 12 hotels.', streaming: true)]);
      Vable.handleChatUpdated([reply('Lisbon has 12 hotels.', streaming: false)]);
      // The stream delivers in a later microtask
      await Future<void>.delayed(Duration.zero);

      final texts = events.whereType<VableAssistantText>().toList();
      expect(texts.map((t) => t.delta), ['Lisbon has', ' 12 hotels.', '']);
      expect(texts.last.text, 'Lisbon has 12 hotels.');
      expect(texts.last.isStreaming, isFalse);
      expect(Vable.agentState, VableAgentState.idle);
    });

    testWidgets('a call\'s reply and levels come from the native side', (tester) async {
      Future<void> native(String method, Map<String, dynamic> args) =>
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.handlePlatformMessage(
            'vable_flutter',
            const StandardMethodCodec().encodeMethodCall(MethodCall(method, args)),
            (_) {},
          );

      await native('onAssistantText', {'text': 'Sure, ', 'isFinal': false});
      await native('onAssistantText', {'text': 'searching Lisbon.', 'isFinal': false});
      await native('onAssistantText', {'text': '', 'isFinal': true});
      await native('onVoiceLevels', {'agent': 0.5, 'user': 0.25});

      final texts = events.whereType<VableAssistantText>().toList();
      expect(texts.map((t) => t.text), ['Sure, ', 'Sure, searching Lisbon.', 'Sure, searching Lisbon.']);
      expect(texts.last.isStreaming, isFalse);
      final level = events.whereType<VableInputLevel>().single;
      expect(level.level, 0.25);
      expect(level.agentLevel, 0.5);
    });
  });

  group('the engine\'s view of the call', () {
    Future<void> native(String method, [Map<String, dynamic>? args]) =>
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.handlePlatformMessage(
          'vable_flutter',
          const StandardMethodCodec().encodeMethodCall(MethodCall(method, args)),
          (_) {},
        );

    testWidgets('its state is the agent\'s state on a call', (tester) async {
      await open(tester, const Text('Home'));
      await native('onVoiceChatStarted');
      await native('onAgentState', {'state': 'thinking'});
      expect(Vable.agentState, VableAgentState.thinking);
      await native('onAgentState', {'state': 'speaking'});
      expect(Vable.agentState, VableAgentState.speaking);
      await native('onVoiceChatEnded');
      expect(Vable.agentState, VableAgentState.idle);
      manager.stopScanning();
    });

    testWidgets('what the user says comes through', (tester) async {
      await native('onUserTranscript', {'text': 'Find me', 'isFinal': false});
      await native('onUserTranscript', {'text': 'Find me a hotel.', 'isFinal': true});
      await tester.pump();

      final transcripts = events.whereType<VableUserTranscript>().toList();
      expect(transcripts.map((t) => t.text), ['Find me', 'Find me a hotel.']);
      expect(transcripts.last.isFinal, isTrue);
    });

    testWidgets('talking over the agent drops what it was waiting to do', (tester) async {
      var taps = 0;
      await open(tester, ElevatedButton(onPressed: () => taps++, child: const Text('Search')));
      Vable.pauseActions();
      send('clickElement', {'id': idOf('Search')}, 'i1');
      await tester.pump(const Duration(milliseconds: 100));

      await native('onUserInterrupted');
      for (var i = 0; i < 10 && results['i1'] == null; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      manager.stopScanning();

      expect(taps, 0);
      expect(results['i1'], startsWith('Not done: the user was using the screen'));
      expect(events.whereType<VableUserInterrupted>(), hasLength(1));
    });
  });

  group('typing', () {
    testWidgets('can go in a character at a time', (tester) async {
      final controller = TextEditingController();
      final seen = <String>[];
      controller.addListener(() => seen.add(controller.text));
      Vable.setTyping(const VableTyping.perCharacter(Duration(milliseconds: 50)));
      await open(
        tester,
        SizedBox(
          width: 300,
          child: TextField(controller: controller, decoration: const InputDecoration(labelText: 'City')),
        ),
      );

      final id = manager.lastInputElements.single.id;
      final result = await agent(tester, 'inputText', {'id': id, 'text': 'Lisbon'});

      expect(result, startsWith('Filled in.'));
      expect(controller.text, 'Lisbon');
      expect(seen.toSet(), containsAll(['L', 'Li', 'Lis', 'Lisb', 'Lisbo', 'Lisbon']));
    });
  });

  group('VableRequiresUser', () {
    testWidgets('the agent sees it and is told to leave it to the user', (tester) async {
      var taps = 0;
      await open(
        tester,
        VableRequiresUser(
          reason: 'payment',
          child: ElevatedButton(onPressed: () => taps++, child: const Text('Pay')),
        ),
      );

      final id = idOf('Pay (for the user to do: payment)');
      final result = await agent(tester, 'clickElement', {'id': id});

      expect(taps, 0);
      expect(result, startsWith('Waiting for the user: payment.'));
      expect(result, isNot(contains('pointAt')));
    });

    testWidgets('with no native UI, the agent can point at it', (tester) async {
      await Vable.setCallStyle(VableCallStyle.none);
      await open(
        tester,
        VableRequiresUser(
          reason: 'payment',
          child: ElevatedButton(onPressed: () {}, child: const Text('Pay')),
        ),
      );

      final id = idOf('Pay (for the user to do: payment)');
      expect(manager.fullContext().intents.map((i) => i.name), contains('pointAt'));
      final click = await agent(tester, 'clickElement', {'id': id});
      expect(click, contains('show it to them with pointAt'));

      final result = await agent(tester, 'pointAt', {'id': id}, toolId: 'p1');
      expect(result, startsWith('Shown to the user.'));
      final pointed = events.whereType<VableActionStarted>().single.action;
      expect(pointed.kind, VableActionKind.pointAt);
      expect(pointed.bounds, tester.getRect(find.byType(ElevatedButton)));
      expect(events.whereType<VableActionFinished>().single.ok, isTrue);
    });

    testWidgets('pointAt is only offered with no native UI', (tester) async {
      await open(tester, ElevatedButton(onPressed: () {}, child: const Text('Pay')));
      expect(manager.fullContext().intents.map((i) => i.name), isNot(contains('pointAt')));
    });
  });

  group('the user touching the screen', () {
    testWidgets('names the control they touched', (tester) async {
      await open(
        tester,
        const SizedBox(width: 300, child: TextField(decoration: InputDecoration(labelText: 'Check-in'))),
      );
      final rect = tester.getRect(find.byType(TextField));
      expect(manager.labelAt(rect.center), 'Check-in');
      expect(manager.labelAt(const Offset(1, 1)), isNull);
    });
  });
}
