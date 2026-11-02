import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vable_flutter/vable_flutter.dart';

const _channel = MethodChannel('vable_flutter');

void main() {
  final manager = ScreenScannerManager();
  late List<Map<String, dynamic>> sentContexts;

  setUp(() {
    sentContexts = [];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, (call) async {
      if (call.method == 'updateIntents') {
        sentContexts.add(
          (call.arguments['contextUpdate'] as Map).cast<String, dynamic>(),
        );
      }
      return true;
    });
  });

  tearDown(() {
    manager.updateHostContext(const VableContextUpdate());
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, null);
  });

  /// Starts scanning [child] and waits for the first scan.
  Future<void> open(WidgetTester tester, Widget child) async {
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: Center(child: child))));
    final context = tester.element(find.byType(Navigator));
    manager.startScanning(context: context, scanInterval: const Duration(minutes: 1));
    for (var i = 0; i < 3; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    // Agent actions scan for themselves, and a running timer would fail the test.
    manager.stopScanning();
    manager.updateContext(context);
  }

  /// Scans what's already on screen.
  Future<void> scan(WidgetTester tester) async {
    final context = tester.element(find.byType(Navigator));
    manager.startScanning(context: context, scanInterval: const Duration(minutes: 1));
    for (var i = 0; i < 3; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    manager.stopScanning();
    manager.updateContext(context);
  }

  /// Runs an agent action to the end, moving the clock through its settle wait.
  Future<String> act(WidgetTester tester, Future<String> Function() action) async {
    String? result;
    action().then((value) => result = value);
    for (var i = 0; i < 40 && result == null; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    manager.stopScanning();
    return result ?? fail('the action never finished');
  }

  /// Parents list their children's text too, so match the exact label.
  String idOf(String label) =>
      manager.lastClickableElements.lastWhere((e) => e.label == label).id;

  group('clicking', () {
    testWidgets('reports new text as evidence', (tester) async {
      await open(tester, const _Saver());
      final result = await act(tester, () => manager.clickForAgent(idOf('Save')));

      expect(result, startsWith('Clicked. New on the screen: "Saved"'));
    });

    testWidgets('says so when nothing happened', (tester) async {
      await open(tester, ElevatedButton(onPressed: () {}, child: const Text('Save')));
      final result = await act(tester, () => manager.clickForAgent(idOf('Save')));

      expect(result, 'Clicked. Nothing changed on the screen, so this is not confirmed.');
    });

    testWidgets('fails honestly when the element has gone', (tester) async {
      await open(tester, ElevatedButton(onPressed: () {}, child: const Text('Save')));
      final id = idOf('Save');

      await tester.pumpWidget(const MaterialApp(home: Scaffold(body: Text('Elsewhere'))));
      final result = await act(tester, () => manager.clickForAgent(id));

      expect(result, 'Failed: that element is no longer on the screen');
    });

    testWidgets('keeps an id across scans', (tester) async {
      await open(tester, ElevatedButton(onPressed: () {}, child: const Text('Save')));
      final id = idOf('Save');

      await act(tester, () => manager.clickForAgent(id));

      expect(idOf('Save'), id);
    });

    testWidgets('an id still means the same element after the screen shifts', (tester) async {
      var kept = 0;
      var deleted = 0;

      Widget screen({required bool showDelete}) => Column(
            key: const ValueKey('column'),
            mainAxisSize: MainAxisSize.min,
            children: [
              if (showDelete)
                ElevatedButton(
                  key: const ValueKey('delete'),
                  onPressed: () => deleted++,
                  child: const Text('Delete'),
                ),
              ElevatedButton(
                key: const ValueKey('keep'),
                onPressed: () => kept++,
                child: const Text('Keep'),
              ),
            ],
          );

      await open(tester, screen(showDelete: false));
      final keepId = idOf('Keep');

      // A new button ahead of it, so numbering by position would hand it Keep's id
      await tester.pumpWidget(
        MaterialApp(home: Scaffold(body: Center(child: screen(showDelete: true)))),
      );
      await act(tester, () => manager.clickForAgent(keepId));

      expect(deleted, 0);
      expect(kept, 1);
    });
  });

  group('VableNoOp', () {
    testWidgets('keeps a button from the agent and still works for the user', (tester) async {
      var pressed = 0;
      await open(
        tester,
        VableNoOp(child: ElevatedButton(onPressed: () => pressed++, child: const Text('Delete'))),
      );

      final result = await act(tester, () => manager.clickForAgent(idOf('Delete')));
      expect(result, startsWith('Not done'));
      expect(pressed, 0);

      await tester.tap(find.text('Delete'));
      expect(pressed, 1);
    });

    testWidgets('covers a tap that lands on it through a parent', (tester) async {
      var pressed = 0;
      await open(
        tester,
        GestureDetector(
          onTap: () {},
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: VableNoOp(
              child: ElevatedButton(onPressed: () => pressed++, child: const Text('Delete')),
            ),
          ),
        ),
      );

      final parent = manager.lastClickableElements.firstWhere((e) => e.label == 'Delete');
      final result = await act(tester, () => manager.clickForAgent(parent.id));

      expect(result, startsWith('Not done'));
      expect(pressed, 0);
    });

    testWidgets('leaves everything else alone', (tester) async {
      var pressed = 0;
      await open(
        tester,
        Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            VableNoOp(child: ElevatedButton(onPressed: () {}, child: const Text('Delete'))),
            ElevatedButton(onPressed: () => pressed++, child: const Text('Cancel')),
          ],
        ),
      );

      await act(tester, () => manager.clickForAgent(idOf('Cancel')));

      expect(pressed, 1);
    });

    testWidgets('keeps a field from the agent', (tester) async {
      final controller = TextEditingController();
      await open(tester, VableNoOp(child: SizedBox(width: 200, child: TextField(controller: controller))));

      final id = manager.lastInputElements.first.id;
      final result = await act(tester, () => manager.inputForAgent(id, 'hello'));

      expect(result, startsWith('Not done'));
      expect(controller.text, isEmpty);
    });
  });

  group('filling in', () {
    testWidgets('fills a field', (tester) async {
      final controller = TextEditingController();
      await open(tester, SizedBox(width: 200, child: TextField(controller: controller)));

      final id = manager.lastInputElements.first.id;
      final result = await act(tester, () => manager.inputForAgent(id, 'hello'));

      expect(result, startsWith('Filled in.'));
      expect(controller.text, 'hello');
    });

    testWidgets('fails honestly when the field has gone', (tester) async {
      await open(tester, const SizedBox(width: 200, child: TextField()));
      final id = manager.lastInputElements.first.id;

      await tester.pumpWidget(const MaterialApp(home: Scaffold(body: Text('Elsewhere'))));
      final result = await act(tester, () => manager.inputForAgent(id, 'hello'));

      expect(result, 'Failed: that field is no longer on the screen');
    });
  });

  group('what the agent sees', () {
    List<String> labels() => manager.lastClickableElements.map((e) => e.label).toList();

    testWidgets('only the page on top, not the ones under it', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: ElevatedButton(onPressed: () {}, child: const Text('Under'))),
      ));
      tester.state<NavigatorState>(find.byType(Navigator)).push(MaterialPageRoute(
        builder: (_) => Scaffold(body: ElevatedButton(onPressed: () {}, child: const Text('On top'))),
      ));
      await tester.pumpAndSettle();
      await scan(tester);

      expect(labels(), contains('On top'));
      expect(labels(), isNot(contains('Under')));
    });

    testWidgets('only the open tab', (tester) async {
      await open(
        tester,
        IndexedStack(
          index: 1,
          children: [
            ElevatedButton(onPressed: () {}, child: const Text('Hidden tab')),
            ElevatedButton(onPressed: () {}, child: const Text('Open tab')),
          ],
        ),
      );

      expect(labels(), contains('Open tab'));
      expect(labels(), isNot(contains('Hidden tab')));
    });

    testWidgets('only the dialog while one is open', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: ElevatedButton(onPressed: () {}, child: const Text('Behind'))),
      ));
      showDialog<void>(
        context: tester.element(find.text('Behind')),
        builder: (_) => AlertDialog(
          actions: [TextButton(onPressed: () {}, child: const Text('In the dialog'))],
        ),
      );
      await tester.pumpAndSettle();
      await scan(tester);

      expect(labels(), contains('In the dialog'));
      expect(labels(), isNot(contains('Behind')));
    });

    testWidgets("doesn't offer a disabled button", (tester) async {
      await open(tester, const ElevatedButton(onPressed: null, child: Text('Sold out')));

      expect(labels(), isNot(contains('Sold out')));
    });

    testWidgets('says a disabled button is off, not gone', (tester) async {
      await open(tester, const ElevatedButton(onPressed: null, child: Text('Sold out')));
      final context = tester.element(find.byType(Navigator));
      late String id;
      await act(tester, () async {
        final screen = await manager.scanNow(context);
        id = screen!.elements.firstWhere((element) => element.text == 'Sold out').id;
        return '';
      });

      final result = await act(tester, () => manager.clickForAgent(id));

      expect(result, "Failed: that's turned off right now, so it can't be used");
    });

    testWidgets('names an icon button by its tooltip', (tester) async {
      await open(
        tester,
        IconButton(tooltip: 'Add to favourites', onPressed: () {}, icon: const Icon(Icons.favorite)),
      );

      expect(labels(), contains('Add to favourites'));
    });

    testWidgets('names fields by their label or hint', (tester) async {
      await open(
        tester,
        const SizedBox(
          width: 200,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(decoration: InputDecoration(labelText: 'Full name')),
              TextField(decoration: InputDecoration(hintText: 'Email address')),
            ],
          ),
        ),
      );

      expect(manager.lastInputElements.map((e) => e.label), ['Full name', 'Email address']);
    });

    testWidgets('sees that a switch changed', (tester) async {
      await open(tester, const _Toggle());
      final result = await act(tester, () => manager.clickForAgent(idOf('Oat milk (off)')));

      expect(result, 'Clicked. New on the screen: "Oat milk (on)".');
    });
  });

  group('going back', () {
    Future<void> openSecondPage(WidgetTester tester) async {
      await tester.pumpWidget(const MaterialApp(home: Scaffold(body: Text('First page'))));
      tester.state<NavigatorState>(find.byType(Navigator)).push(MaterialPageRoute(
        builder: (_) => const Scaffold(body: Text('Second page')),
      ));
      await tester.pumpAndSettle();
      await scan(tester);
    }

    testWidgets('works with no back button on the screen', (tester) async {
      await openSecondPage(tester);

      final result = await act(tester, () => manager.goBackForAgent());

      expect(result, 'Went back. New on the screen: "First page".');
      expect(find.text('First page'), findsOneWidget);
    });

    testWidgets('is only offered when there is somewhere to go', (tester) async {
      await open(tester, const Text('First page'));
      expect((sentContexts.last['intents'] as List).map((i) => i['name']), isNot(contains('goBack')));

      await openSecondPage(tester);
      expect((sentContexts.last['intents'] as List).map((i) => i['name']), contains('goBack'));
    });

    testWidgets('says when there is nowhere to go', (tester) async {
      await open(tester, const Text('First page'));

      expect(await manager.goBackForAgent(), "Failed: there's nothing to go back to");
    });

    testWidgets('leaves a page that came up empty', (tester) async {
      await tester.pumpWidget(const MaterialApp(home: Scaffold(body: Text('First page'))));
      tester.state<NavigatorState>(find.byType(Navigator)).push(MaterialPageRoute(
        builder: (_) => const Scaffold(body: SizedBox.shrink()),
      ));
      await tester.pumpAndSettle();
      await scan(tester);

      bool? left;
      await act(tester, () async {
        left = await manager.leaveEmptyScreen();
        return '';
      });
      await tester.pumpAndSettle();

      expect(left, isTrue);
      expect(find.text('First page'), findsOneWidget);
    });

    testWidgets('stays on a page with something on it', (tester) async {
      await openSecondPage(tester);

      bool? left;
      await act(tester, () async {
        left = await manager.leaveEmptyScreen();
        return '';
      });

      expect(left, isFalse);
      expect(find.text('Second page'), findsOneWidget);
    });

    testWidgets('closes a dialog', (tester) async {
      await tester.pumpWidget(const MaterialApp(home: Scaffold(body: Text('Page'))));
      showDialog<void>(
        context: tester.element(find.text('Page')),
        builder: (_) => const AlertDialog(title: Text('A dialog')),
      );
      await tester.pumpAndSettle();
      await scan(tester);

      await act(tester, () => manager.goBackForAgent());

      expect(find.text('A dialog'), findsNothing);
    });
  });

  group('scrolling', () {
    testWidgets('finds what is further down a list', (tester) async {
      await open(
        tester,
        ListView.builder(
          itemCount: 100,
          itemBuilder: (_, index) => ListTile(title: Text('Store ${index + 1}'), onTap: () {}),
        ),
      );
      expect(manager.lastClickableElements.map((e) => e.label), isNot(contains('Store 40')));

      for (var i = 0; i < 3; i++) {
        final result = await act(tester, () => manager.scrollForAgent(down: true));
        expect(result, startsWith('Scrolled. New on the screen'));
      }

      expect(manager.lastClickableElements.map((e) => e.label), contains('Store 40'));
    });

    testWidgets('says when there is nothing to scroll', (tester) async {
      await open(tester, const Text('Short'));
      final result = await act(tester, () => manager.scrollForAgent(down: true));

      expect(result, "Failed: there's nothing more to scroll to that way");
    });
  });

  group('custom intents', () {
    late List<Map> results;

    setUp(() {
      results = [];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(_channel, (call) async {
        if (call.method == 'sendToolResult') results.add(call.arguments as Map);
        return true;
      });
    });

    Future<void> call(String name, VableIntentHandler? handler) async {
      await Vable.updateIntents(
        VableContextUpdate(intents: [VableIntent(name: 'addToCart', onIntent: handler)]),
      );
      await Vable.handleIntentEvent(name, {'item': 'Latte'});
    }

    test('run the handler and tell the agent what it returned', () async {
      await call('addToCart', (parameters) => 'Added ${parameters['item']}');

      expect(results.single, containsPair('result', 'Added Latte'));
      expect(results.single, containsPair('toolName', 'addToCart'));
    });

    test('tell the agent when the handler fails', () async {
      await call('addToCart', (_) => throw StateError('out of stock'));

      expect(results.single['result'], 'Failed: Bad state: out of stock');
    });

    test('answer even without a handler, so the agent is not left waiting', () async {
      await call('checkout', (_) => 'Done');

      expect(results.single['result'], "Failed: this app can't do that yet");
    });

    test('can be added and removed one at a time', () async {
      await Vable.updateIntents(const VableContextUpdate());
      await Vable.registerIntent(VableIntent(name: 'addToCart', onIntent: (_) => 'Added'));
      await Vable.registerIntent(VableIntent(name: 'checkout', onIntent: (_) => 'Paid'));
      await Vable.unregisterIntent('addToCart');

      await Vable.handleIntentEvent('checkout', {});
      await Vable.handleIntentEvent('addToCart', {});

      expect(results.map((r) => r['result']), ['Paid', "Failed: this app can't do that yet"]);
    });

    test('app state can be updated one piece at a time', () async {
      final sent = <Map>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(_channel, (call) async {
        if (call.method == 'updateIntents') sent.add(call.arguments['contextUpdate'] as Map);
        return true;
      });

      await Vable.updateIntents(const VableContextUpdate());
      await Vable.updateIntentState(const VableIntentState(name: 'cart', description: 'Cart', value: 1));
      await Vable.updateIntentState(const VableIntentState(name: 'user', description: 'User', value: 'Ada'));
      await Vable.updateIntentState(const VableIntentState(name: 'cart', description: 'Cart', value: 2));

      final states = sent.last['intentStates'] as List;
      expect(states.map((s) => s['name']), ['user', 'cart']);
      expect(states.last['value'], 2);
    });

    test('updates keep the screen tools', () async {
      final sent = <Map>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(_channel, (call) async {
        if (call.method == 'updateIntents') sent.add(call.arguments['contextUpdate'] as Map);
        return true;
      });

      await Vable.updateIntents(const VableContextUpdate(intents: [VableIntent(name: 'addToCart')]));

      expect((sent.single['intents'] as List).map((i) => i['name']), contains('clickElement'));
    });
  });

  group('ending', () {
    testWidgets('stops scanning when the call ends from the native side', (tester) async {
      var ended = 0;
      Vable.onVoiceChatEnded = () => ended++;
      addTearDown(() => Vable.onVoiceChatEnded = null);
      await tester.pumpWidget(const MaterialApp(home: Scaffold(body: Text('Screen'))));
      final context = tester.element(find.byType(Navigator));
      manager.startScanning(context: context, scanInterval: const Duration(minutes: 1));
      await tester.pump();

      Vable.handleVoiceChatEnded();

      expect(manager.isScanning, isFalse);
      expect(ended, 1);
    });
  });

  group('routes', () {
    test('come from nested AutoRoute routes', () {
      Vable.configureRouter(
        library: VableRoutingLibrary.autoRoute,
        router: _FakeRouter([
          _FakeRoute('/', 'Wrapper', [_FakeRoute('home', 'Home'), _FakeRoute('account', 'Account')]),
        ]),
      );

      expect(Vable.routes.map((route) => route.path), ['/home', '/account']);
    });
  });

  group('intent context', () {
    testWidgets('scans keep what the app sent', (tester) async {
      manager.updateHostContext(
        VableContextUpdate(
          intents: [VableIntent(name: 'checkout', description: 'Complete purchase')],
          intentStates: const [VableIntentState(name: 'cart', description: 'Cart', value: 2)],
        ),
      );
      await open(tester, ElevatedButton(onPressed: () {}, child: const Text('Save')));

      final names = (sentContexts.last['intents'] as List).map((intent) => intent['name']);
      expect(names, containsAll(['checkout', 'clickElement']));
      expect((sentContexts.last['intentStates'] as List).single['name'], 'cart');
    });
  });
}

class _FakeRouter {
  _FakeRouter(this.routes);

  final List<_FakeRoute> routes;
}

class _FakeRoute {
  _FakeRoute(this.path, this.name, [this.children]);

  final String path;
  final String name;
  final List<_FakeRoute>? children;
}

class _Toggle extends StatefulWidget {
  const _Toggle();

  @override
  State<_Toggle> createState() => _ToggleState();
}

class _ToggleState extends State<_Toggle> {
  bool _on = false;

  @override
  Widget build(BuildContext context) {
    return SwitchListTile(
      title: const Text('Oat milk'),
      value: _on,
      onChanged: (value) => setState(() => _on = value),
    );
  }
}

class _Saver extends StatefulWidget {
  const _Saver();

  @override
  State<_Saver> createState() => _SaverState();
}

class _SaverState extends State<_Saver> {
  bool _saved = false;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        ElevatedButton(onPressed: () => setState(() => _saved = true), child: const Text('Save')),
        if (_saved) const Text('Saved'),
      ],
    );
  }
}
