import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vable_flutter/src/screen_frames.dart';
import 'package:vable_flutter/src/screen_scanner.dart';
import 'package:vable_flutter/vable_flutter.dart';

void main() {
  group('header', () {
    test('encodes every field the engine reads', () {
      const header = VableScreenFrameHeader(
        at: 1762300000000,
        reason: VableFrameReason.actionBefore,
        route: '/checkout',
        width: 360,
        height: 780,
        masked: 3,
        platformViews: true,
        toolId: 'toolu_01',
      );

      expect(jsonDecode(header.encode()), {
        'at': 1762300000000,
        'reason': 'action_before',
        'route': '/checkout',
        'width': 360,
        'height': 780,
        'masked': 3,
        'platformViews': true,
        'toolId': 'toolu_01',
        'format': 'jpeg',
      });
    });

    test('leaves the tool out of frames that are not for one', () {
      const header = VableScreenFrameHeader(
        at: 1,
        reason: VableFrameReason.change,
        route: null,
        width: 10,
        height: 20,
        masked: 0,
        platformViews: false,
      );

      final json = jsonDecode(header.encode()) as Map<String, dynamic>;
      expect(json.containsKey('toolId'), isFalse);
      expect(json['route'], '');
      expect(json['reason'], 'change');
    });

    test('names each reason as the protocol does', () {
      expect(VableFrameReason.values.map((r) => r.wireName),
          ['page', 'action_before', 'action_after', 'change']);
    });
  });

  group('config', () {
    test('is off when the engine sends nothing or says no', () {
      expect(VableScreenFramesConfig.fromMap(null).enabled, isFalse);
      expect(VableScreenFramesConfig.fromMap({}).enabled, isFalse);
      expect(VableScreenFramesConfig.fromMap({'enabled': false, 'maxFrames': 300}).enabled, isFalse);
    });

    test('reads the limits, and keeps defaults for zeros the engine leaves out', () {
      final config = VableScreenFramesConfig.fromMap(
        {'enabled': true, 'maxFrames': 50, 'maxWidth': 0, 'minIntervalMs': 2000},
      );
      expect(config.enabled, isTrue);
      expect(config.maxFrames, 50);
      expect(config.maxWidth, 360);
      expect(config.minIntervalMs, 2000);
    });
  });

  group('masks from semantics', () {
    Future<VableSemanticsMasks> masksOf(WidgetTester tester, Widget body) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: body)));
      final root = tester.renderObject(find.byType(Scaffold)).owner!.semanticsOwner!.rootSemanticsNode!;
      final masks = semanticsMasks(root, tester.view.devicePixelRatio);
      handle.dispose();
      return masks;
    }

    bool covered(VableSemanticsMasks masks, Offset point) =>
        masks.rects.any((rect) => rect.contains(point));

    testWidgets('cover editable, obscured and private fields, and nothing else', (tester) async {
      final masks = await masksOf(
        tester,
        const Column(
          children: [
            TextField(key: Key('name'), decoration: InputDecoration(labelText: 'Name')),
            TextField(key: Key('password'), obscureText: true),
            TextField(key: Key('card'), readOnly: true, decoration: InputDecoration(labelText: 'Card number')),
            TextField(key: Key('notes'), readOnly: true, decoration: InputDecoration(labelText: 'Notes')),
            Text('Hello', key: Key('hello')),
          ],
        ),
      );

      Offset centre(String key) => tester.getRect(find.byKey(Key(key))).center;
      expect(covered(masks, centre('name')), isTrue);
      expect(covered(masks, centre('password')), isTrue);
      expect(covered(masks, centre('card')), isTrue);
      expect(covered(masks, centre('notes')), isFalse);
      expect(covered(masks, centre('hello')), isFalse);
      expect(masks.platformViews, isFalse);
    });

    testWidgets('are in logical pixels', (tester) async {
      final masks = await masksOf(
        tester,
        const Align(
          alignment: Alignment.topLeft,
          child: SizedBox(width: 200, child: TextField(key: Key('field'))),
        ),
      );

      final field = tester.getRect(find.byType(EditableText));
      final mask = masks.rects.firstWhere((rect) => rect.contains(field.center));
      expect(mask.width, lessThanOrEqualTo(200.5));
      expect(mask.left, closeTo(field.left, 20));
    });
  });

  group('marked areas', () {
    Future<VableMarkedAreas> areasOf(WidgetTester tester, Widget body) async {
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: body)));
      var root = tester.renderObject(find.byType(Scaffold));
      while (root.parent != null) {
        root = root.parent!;
      }
      return markedAreas(root);
    }

    testWidgets('cover VableMask and VableNoOp where they are on screen', (tester) async {
      final areas = await areasOf(
        tester,
        const Column(
          children: [
            VableMask(child: SizedBox(key: Key('card'), width: 120, height: 80)),
            VableNoOp(child: SizedBox(key: Key('delete'), width: 60, height: 40)),
            SizedBox(key: Key('plain'), width: 50, height: 50),
          ],
        ),
      );

      expect(areas.rects, [
        tester.getRect(find.byKey(const Key('card'))),
        tester.getRect(find.byKey(const Key('delete'))),
      ]);
      expect(areas.platformViews, isFalse);
    });

    testWidgets('leave out what is hidden', (tester) async {
      final areas = await areasOf(
        tester,
        const Column(
          children: [
            Offstage(child: VableMask(child: SizedBox(width: 100, height: 100))),
            SizedBox(
              height: 100,
              child: IndexedStack(
                index: 0,
                children: [
                  SizedBox(key: Key('shown'), width: 10, height: 10),
                  VableMask(child: SizedBox(width: 100, height: 100)),
                ],
              ),
            ),
          ],
        ),
      );

      expect(areas.rects, isEmpty);
    });

    testWidgets('clip to the scroll view a mask is in', (tester) async {
      final areas = await areasOf(
        tester,
        Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            key: const Key('list'),
            height: 100,
            child: ListView(
              children: const [
                SizedBox(height: 60),
                VableMask(child: SizedBox(height: 100)),
              ],
            ),
          ),
        ),
      );

      final list = tester.getRect(find.byKey(const Key('list')));
      expect(areas.rects, hasLength(1));
      expect(areas.rects.single.top, list.top + 60);
      expect(areas.rects.single.bottom, list.bottom);
    });

    testWidgets('notice platform views', (tester) async {
      final areas = await areasOf(tester, const SizedBox(width: 50, height: 50, child: Texture(textureId: 1)));
      expect(areas.platformViews, isTrue);
    });
  });

  group('recording', () {
    late List<Map<dynamic, dynamic>> sent;

    setUp(() {
      sent = [];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(const MethodChannel('vable_flutter'), (call) async {
        if (call.method == 'sendScreenFrame') sent.add(call.arguments as Map);
        return true;
      });
    });

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(const MethodChannel('vable_flutter'), null);
    });

    Future<(VableScreenFrames, FlutterScreenScanner)> open(WidgetTester tester, Widget body) async {
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: body)));
      final context = tester.element(find.byType(Navigator));
      final scanner = FlutterScreenScanner();
      final scan = scanner.scanScreen(context);
      await tester.pump();
      await scan;
      final frames = VableScreenFrames(
        context: () => context,
        route: () => '/home',
        scanner: scanner,
      );
      return (frames, scanner);
    }

    testWidgets('sends a masked frame at the configured width', (tester) async {
      final (frames, scanner) = await open(
        tester,
        const Align(
          alignment: Alignment.topLeft,
          child: VableMask(child: ColoredBox(color: Colors.red, child: SizedBox(width: 400, height: 300))),
        ),
      );
      frames.start(const VableScreenFramesConfig(enabled: true, minIntervalMs: 60000));
      for (var i = 0; i < 20 && sent.isEmpty; i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
      }
      frames.stop();
      scanner.release();

      expect(sent, hasLength(1));
      final frame = sent.single;
      final header = jsonDecode(frame['header'] as String) as Map<String, dynamic>;
      final logicalWidth = tester.view.physicalSize.width / tester.view.devicePixelRatio;
      expect(frame['width'], 360);
      expect(header['width'], 360);
      expect(header['height'], frame['height']);
      expect(header['reason'], 'page');
      expect(header['route'], '/home');
      expect(header['masked'], 1);

      final rgba = frame['rgba'] as Uint8List;
      expect(rgba.length, 360 * (frame['height'] as int) * 4);
      // Inside the red box, which is masked, so it isn't red
      final scale = 360 / logicalWidth;
      final x = (200 * scale).round();
      final y = (150 * scale).round();
      final i = (y * 360 + x) * 4;
      expect(rgba.sublist(i, i + 3), [0x3C, 0x3C, 0x3C]);
    });

    testWidgets('takes nothing when frames are off', (tester) async {
      final (frames, scanner) = await open(tester, const Text('Hi'));
      frames.start(VableScreenFramesConfig.off);
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
      scanner.release();
      expect(frames.isRecording, isFalse);
      expect(sent, isEmpty);
    });

    testWidgets('takes nothing in the background', (tester) async {
      final (frames, scanner) = await open(tester, const Text('Hi'));
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      frames.start(const VableScreenFramesConfig(enabled: true, minIntervalMs: 60000));
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
      frames.stop();
      scanner.release();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      expect(sent, isEmpty);
    });

    testWidgets('takes nothing without semantics to mask from', (tester) async {
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpWidget(const MaterialApp(home: Text('Hi')));
      final context = tester.element(find.byType(Navigator));
      final frames = VableScreenFrames(
        context: () => context,
        route: () => null,
        scanner: FlutterScreenScanner(),
      );
      frames.start(const VableScreenFramesConfig(enabled: true, minIntervalMs: 60000));
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
      frames.stop();
      expect(sent, isEmpty);
    });
  });

  test('frame hash tells different bytes apart', () {
    expect(frameHash(Uint8List.fromList([1, 2, 3])), isNot(frameHash(Uint8List.fromList([1, 2, 4]))));
    expect(frameHash(Uint8List.fromList([1, 2, 3])), frameHash(Uint8List.fromList([1, 2, 3])));
  });
}
