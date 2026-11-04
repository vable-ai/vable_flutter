import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import 'screen_scanner.dart';
import 'vable_logger.dart';
import 'vable_no_op.dart';

/// Whether the project records screen frames during calls, and how. It comes
/// from the call's CreateRoom response, through the native SDK.
class VableScreenFramesConfig {
  const VableScreenFramesConfig({
    required this.enabled,
    this.maxFrames = 300,
    this.maxWidth = 360,
    this.minIntervalMs = 1000,
  });

  /// Frames are off, as they are when the engine doesn't send the setting.
  static const off = VableScreenFramesConfig(enabled: false);

  /// Reads `{enabled, maxFrames, maxWidth, minIntervalMs}`. Numbers that are
  /// missing or not positive keep their defaults, since the engine leaves zeros out.
  factory VableScreenFramesConfig.fromMap(Map<dynamic, dynamic>? map) {
    if (map == null || map['enabled'] != true) return off;
    int positive(Object? value, int fallback) =>
        value is num && value > 0 ? value.toInt() : fallback;
    return VableScreenFramesConfig(
      enabled: true,
      maxFrames: positive(map['maxFrames'], 300),
      maxWidth: positive(map['maxWidth'], 360),
      minIntervalMs: positive(map['minIntervalMs'], 1000),
    );
  }

  final bool enabled;
  final int maxFrames;
  final int maxWidth;
  final int minIntervalMs;
}

/// Why a frame was taken.
enum VableFrameReason {
  /// The element snapshot was sent
  page('page'),

  /// Right before the agent's action ran
  actionBefore('action_before'),

  /// About half a second after the agent's action finished
  actionAfter('action_after'),

  /// The screen changed between snapshots
  change('change');

  const VableFrameReason(this.wireName);

  /// The name the engine knows it by
  final String wireName;
}

/// The JSON header sent before each frame's JPEG.
class VableScreenFrameHeader {
  const VableScreenFrameHeader({
    required this.at,
    required this.reason,
    required this.route,
    required this.width,
    required this.height,
    required this.masked,
    required this.platformViews,
    this.toolId,
  });

  /// Unix ms when captured
  final int at;
  final VableFrameReason reason;

  /// The page on screen, or empty when it isn't known
  final String? route;
  final int width;
  final int height;

  /// How many boxes were drawn over the frame
  final int masked;

  /// Whether a platform view was on screen, which can come out blank
  final bool platformViews;

  /// The agent's tool call, on action frames
  final String? toolId;

  Map<String, Object> toJson() => {
    'at': at,
    'reason': reason.wireName,
    'route': route ?? '',
    'width': width,
    'height': height,
    'masked': masked,
    'platformViews': platformViews,
    if (toolId != null && toolId!.isNotEmpty) 'toolId': toolId!,
    'format': 'jpeg',
  };

  /// The header as the native side sends it: UTF-8 JSON.
  String encode() => jsonEncode(toJson());
}

/// Areas covered because of the widgets around them, in logical pixels.
typedef VableMarkedAreas = ({List<Rect> rects, bool platformViews});

/// Finds what [VableNoOp] and [VableMask] cover under [root], and whether a
/// platform view is on screen. It walks what's on screen the way semantics
/// does, so pages under the top one and hidden tabs are left out, and clips each
/// area to the scroll views and clips around it.
VableMarkedAreas markedAreas(RenderObject root) {
  final rects = <Rect>[];
  var platformViews = false;

  void visit(RenderObject node, Rect clip) {
    if (node is RenderMetaData &&
        (node.metaData == vableNoOpMarker || node.metaData == vableMaskMarker)) {
      if (!node.hasSize) return;
      final area = MatrixUtils.transformRect(node.getTransformTo(null), node.paintBounds)
          .intersect(clip);
      if (!area.isEmpty) rects.add(area);
      // Everything under it is covered already
      return;
    }
    if (node is PlatformViewRenderBox ||
        node is RenderDarwinPlatformView ||
        node is TextureBox) {
      platformViews = true;
    }
    node.visitChildrenForSemantics((child) {
      var childClip = clip;
      final local = node.describeApproximatePaintClip(child);
      if (local != null) {
        childClip = clip.intersect(MatrixUtils.transformRect(node.getTransformTo(null), local));
      }
      if (!childClip.isEmpty) visit(child, childClip);
    });
  }

  visit(root, Rect.largest);
  return (rects: rects, platformViews: platformViews);
}

/// Covers [masks], given in logical pixels, with solid boxes on [image], which
/// is [scale] image pixels to a logical one. Disposes [image].
Future<ui.Image> drawMasks(ui.Image image, List<Rect> masks, double scale) async {
  if (masks.isEmpty) return image;
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  canvas.drawImage(image, Offset.zero, Paint());
  final paint = Paint()..color = const Color(0xFF3C3C3C);
  for (final mask in masks) {
    // Rounded outwards, so no edge of what's under it shows
    canvas.drawRect(
      Rect.fromLTRB(
        (mask.left * scale).floorToDouble(),
        (mask.top * scale).floorToDouble(),
        (mask.right * scale).ceilToDouble(),
        (mask.bottom * scale).ceilToDouble(),
      ),
      paint,
    );
  }
  final picture = recorder.endRecording();
  try {
    return await picture.toImage(image.width, image.height);
  } finally {
    picture.dispose();
    image.dispose();
  }
}

/// A 32-bit FNV-1a hash, for telling whether a thumbnail changed.
int frameHash(Uint8List bytes) {
  var hash = 0x811c9dc5;
  for (final byte in bytes) {
    hash = ((hash ^ byte) * 0x01000193) & 0xFFFFFFFF;
  }
  return hash;
}

/// A picture of the screen whose scene is built, waiting to be rasterised.
class _Shot {
  _Shot(this.image, this.masks, this.platformViews, this.logicalWidth);

  final Future<ui.Image> image;
  final List<Rect> masks;
  final bool platformViews;
  final double logicalWidth;
}

/// Records what the user saw during a call, when the project has turned it on.
///
/// Frames are taken when the snapshot is sent, around each agent action, and
/// when the screen changes. Text fields, private fields, [VableNoOp] and
/// [VableMask] are covered before a frame leaves Dart. A frame never holds up an
/// action: one is taken at a time, and any that come while one is in flight are
/// dropped.
class VableScreenFrames {
  VableScreenFrames({
    required BuildContext? Function() context,
    required String? Function() route,
    required FlutterScreenScanner scanner,
    MethodChannel channel = const MethodChannel('vable_flutter'),
  })  : _context = context,
        _route = route,
        _scanner = scanner,
        _channel = channel;

  /// How long after an action finishes its second frame is taken
  static const Duration actionAfterDelay = Duration(milliseconds: 500);

  /// The thumbnail's width, for spotting changes
  static const int _thumbnailWidth = 32;

  final BuildContext? Function() _context;
  final String? Function() _route;
  final FlutterScreenScanner _scanner;
  final MethodChannel _channel;

  VableScreenFramesConfig _config = VableScreenFramesConfig.off;
  Timer? _changeTimer;
  final Set<Timer> _afterTimers = {};
  bool _busy = false;
  int _sent = 0;
  int? _lastHash;

  /// Counts sessions, so a frame from an ended call isn't sent in the next one
  int _session = 0;

  /// Whether frames are being recorded.
  bool get isRecording => _config.enabled;

  /// How many frames this call has sent.
  int get sentCount => _sent;

  /// Starts recording for a call, if [config] allows it, with a first frame of
  /// the page the agent already has.
  void start(VableScreenFramesConfig config) {
    stop();
    if (!config.enabled) return;
    _config = config;
    VableLogger.debug('[VableFlutter] Recording screen frames, at most ${config.maxFrames}');
    _changeTimer = Timer.periodic(
      Duration(milliseconds: config.minIntervalMs),
      (_) => _checkForChange(),
    );
    capture(VableFrameReason.page);
  }

  /// Stops recording. Frames already in flight are dropped.
  void stop() {
    _session++;
    _config = VableScreenFramesConfig.off;
    _changeTimer?.cancel();
    _changeTimer = null;
    for (final timer in _afterTimers) {
      timer.cancel();
    }
    _afterTimers.clear();
    _sent = 0;
    _lastHash = null;
    _busy = false;
  }

  /// The element snapshot was just sent.
  void onPage() => capture(VableFrameReason.page);

  /// The agent's action [toolId] is about to run. The picture is taken before
  /// this returns, and sent afterwards.
  void actionBefore(String? toolId) => capture(VableFrameReason.actionBefore, toolId: toolId);

  /// The agent's action [toolId] finished. Its frame follows shortly, once the
  /// screen has had a moment to show the result.
  void actionAfter(String? toolId) {
    if (!isRecording) return;
    late final Timer timer;
    timer = Timer(actionAfterDelay, () {
      _afterTimers.remove(timer);
      capture(VableFrameReason.actionAfter, toolId: toolId);
    });
    _afterTimers.add(timer);
  }

  /// Takes a frame now if one can be taken, and sends it. The picture is taken
  /// synchronously; only rasterising, encoding and sending wait.
  Future<void> capture(VableFrameReason reason, {String? toolId}) async {
    if (!_canCapture) return;
    final at = DateTime.now().millisecondsSinceEpoch;
    final shot = _shoot(_config.maxWidth.toDouble());
    if (shot == null) return;

    final session = _session;
    _busy = true;
    try {
      await _send(shot, reason, toolId, at, session);
      if (session != _session) return;
      // So a change check doesn't send the same screen again
      final thumbnail = _shoot(_thumbnailWidth.toDouble());
      if (thumbnail != null) _lastHash = await _hashOf(thumbnail);
    } catch (e) {
      VableLogger.error('[VableFlutter] Screen frame failed: $e');
    } finally {
      if (session == _session) _busy = false;
    }
  }

  Future<void> _checkForChange() async {
    if (!_canCapture) return;
    final thumbnail = _shoot(_thumbnailWidth.toDouble());
    if (thumbnail == null) return;

    final session = _session;
    _busy = true;
    try {
      final hash = await _hashOf(thumbnail);
      if (session != _session) return;
      final changed = _lastHash != null && hash != _lastHash;
      _lastHash = hash;
      if (!changed) return;

      final at = DateTime.now().millisecondsSinceEpoch;
      final shot = _shoot(_config.maxWidth.toDouble());
      if (shot != null) await _send(shot, VableFrameReason.change, null, at, session);
    } catch (e) {
      VableLogger.error('[VableFlutter] Screen change check failed: $e');
    } finally {
      if (session == _session) _busy = false;
    }
  }

  bool get _canCapture =>
      isRecording &&
      !_busy &&
      _sent < _config.maxFrames &&
      WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;

  /// Builds the picture and finds what to cover, both from the same frame.
  /// Null when the screen can't be read or masked, so nothing unmasked is sent.
  _Shot? _shoot(double width) {
    final context = _context();
    if (context == null || !context.mounted) return null;
    final view = View.maybeOf(context);
    final renderObject = context.findRenderObject();
    if (view == null || renderObject == null) return null;

    var root = renderObject;
    while (root.parent != null) {
      root = root.parent!;
    }
    // The root is a repaint boundary, so its layer is an OffsetLayer
    // ignore: invalid_use_of_protected_member
    final layer = root.layer;
    if (layer is! OffsetLayer) return null;

    final semantics = _scanner.masksNow(context);
    if (semantics == null) return null;
    final marked = markedAreas(root);

    final physical = view.physicalSize;
    if (physical.isEmpty) return null;
    final logical = physical / view.devicePixelRatio;
    final screen = Offset.zero & logical;
    final masks = [...semantics.rects, ...marked.rects]
        .map((rect) => rect.intersect(screen))
        .where((rect) => !rect.isEmpty)
        .toList();

    // The root layer scales logical pixels to physical ones, so its bounds are physical
    final pixelRatio = math.min(1.0, width / physical.width);
    final image = layer.toImage(Offset.zero & physical, pixelRatio: pixelRatio);
    return _Shot(image, masks, semantics.platformViews || marked.platformViews, logical.width);
  }

  Future<ui.Image> _maskedImage(_Shot shot) async {
    final image = await shot.image;
    return drawMasks(image, shot.masks, image.width / shot.logicalWidth);
  }

  Future<int?> _hashOf(_Shot shot) async {
    final image = await _maskedImage(shot);
    try {
      final bytes = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      return bytes == null ? null : frameHash(bytes.buffer.asUint8List());
    } finally {
      image.dispose();
    }
  }

  Future<void> _send(
    _Shot shot,
    VableFrameReason reason,
    String? toolId,
    int at,
    int session,
  ) async {
    final image = await _maskedImage(shot);
    final width = image.width;
    final height = image.height;
    final ByteData? bytes;
    try {
      bytes = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    } finally {
      image.dispose();
    }
    if (bytes == null || session != _session) return;

    final header = VableScreenFrameHeader(
      at: at,
      reason: reason,
      route: _route(),
      width: width,
      height: height,
      masked: shot.masks.length,
      platformViews: shot.platformViews,
      toolId: toolId,
    );
    final sent = await _channel.invokeMethod<bool>('sendScreenFrame', {
      'rgba': bytes.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes),
      'width': width,
      'height': height,
      'header': header.encode(),
    });
    if (sent == true && session == _session) _sent++;
  }
}
