import 'dart:async';

import 'package:flutter/gestures.dart';

import 'models/agent_models.dart';
import 'models/chat_models.dart';
import 'vable_logger.dart';

// What the agent is told when an action is held back
const String declinedResult =
    'Not done: the user declined this. Ask them what they would like instead.';
const String stoppedResult =
    'Not done: the user stopped this task. Don\'t carry on with it unless they ask again.';
const String movedOnResult =
    'Not done: the user was using the screen themselves, then spoke to you, so this was '
    'dropped. Go by what they said and what is on the screen now.';

/// After [VableAgentControl.cancel], actions already on their way are refused
/// for this long.
const Duration _cancelWindow = Duration(seconds: 3);

/// The user is taken to be talking once their level stays this high for
/// [_talkingTime].
const double _talkingLevel = 0.08;
const Duration _talkingTime = Duration(milliseconds: 400);

/// The agent counts as speaking while its level is above this, and for
/// [_speakingHangover] after, so the gaps between words don't flicker.
const double _speakingLevel = 0.04;
const Duration _speakingHangover = Duration(milliseconds: 400);

/// Holds the agent's actions to the app's pace: its gate, pauses, cancelling
/// and the user's own touches. Also derives the events in [Vable.events].
class VableAgentControl {
  VableAgentControl._();

  static final VableAgentControl instance = VableAgentControl._();

  final StreamController<VableEvent> _events = StreamController<VableEvent>.broadcast();

  Stream<VableEvent> get events => _events.stream;

  void emit(VableEvent event) => _events.add(event);

  // MARK: Settings

  VableActionGate? gate;
  VableTyping typing = VableTyping.instant;

  /// With no native call UI, the agent can point at things for the app to
  /// highlight, and the user's touches pause it unless the app says otherwise.
  bool headless = false;

  bool? _pauseOnUserTouch;
  bool get pauseOnUserTouch => _pauseOnUserTouch ?? headless;
  set pauseOnUserTouch(bool value) {
    _pauseOnUserTouch = value;
    _syncTouchRoute();
  }

  /// Finds the label of the control at a position, for telling the agent what
  /// the user touched. Set by the screen scanner.
  String? Function(Offset position)? labelAt;

  /// Whether a position is in the app's own assistant UI, whose touches don't
  /// pause the agent. Set by the screen scanner.
  bool Function(Offset position)? isAssistantUiAt;

  // MARK: Session

  bool _sessionActive = false;
  bool _callActive = false;

  /// A call or the chat opened or closed.
  void setSession({required bool call, required bool chat}) {
    final active = call || chat;
    if (call != _callActive) emit(call ? const VableCallStarted() : const VableCallEnded());
    _callActive = call;
    if (active != _sessionActive) {
      _sessionActive = active;
      // A pause or cancel belongs to the session it was made in
      _paused = false;
      _pausedByTouch = false;
      _resumed?.complete();
      _resumed = null;
      _cancelling?.cancel();
      _cancelling = null;
      _userChanges.clear();
      _syncTouchRoute();
    }
    if (!call) {
      _agentLoudAt = null;
      _voiceReply = '';
      _engineState = null;
    }
    _updateState();
  }

  // MARK: Pausing and cancelling

  bool _paused = false;
  bool _pausedByTouch = false;
  Completer<void>? _resumed;
  Timer? _cancelling;

  /// Bumped when the actions waiting at a pause are stale and must not run.
  int _generation = 0;

  bool get paused => _paused;

  void pause({bool byTouch = false}) {
    if (_paused) {
      _pausedByTouch = _pausedByTouch && byTouch;
      return;
    }
    _paused = true;
    _pausedByTouch = byTouch;
    _resumed = Completer<void>();
    VableLogger.debug('[VableFlutter] Agent actions paused${byTouch ? ' by a touch' : ''}');
    _updateState();
  }

  /// Lets waiting actions run. With [dropWaiting], they're answered as stale
  /// instead, because the user has moved the conversation on.
  void resume({bool dropWaiting = false}) {
    if (dropWaiting) _generation++;
    if (!_paused) return;
    _paused = false;
    _pausedByTouch = false;
    _resumed?.complete();
    _resumed = null;
    VableLogger.debug('[VableFlutter] Agent actions resumed');
    _updateState();
  }

  void cancel() {
    _cancelling?.cancel();
    _cancelling = Timer(_cancelWindow, () => _cancelling = null);
    _generation++;
    resume();
  }

  /// The user spoke or typed to the agent. A pause their touch caused ends, and
  /// what was waiting at it is stale.
  void userTurnStarted() {
    if (_pausedByTouch) resume(dropWaiting: true);
  }

  // MARK: The user's own changes

  final List<String> _userChanges = [];

  void noteUserInteraction(String? label) {
    final name = label?.trim();
    if (name == null || name.isEmpty) {
      if (_userChanges.isEmpty) _userChanges.add('');
    } else if (!_userChanges.contains(name)) {
      _userChanges
        ..remove('')
        ..add(name);
    }
  }

  /// Tells the agent what the user changed since its last action, so it
  /// doesn't overwrite it.
  String _withUserChanges(String result) {
    if (_userChanges.isEmpty) return result;
    final names = _userChanges.where((n) => n.isNotEmpty).map((n) => '"$n"').toList();
    _userChanges.clear();
    final note = names.isEmpty
        ? 'Meanwhile the user used the screen themselves, so check it before carrying on.'
        : 'Meanwhile the user used ${names.join(', ')} themselves, so don\'t undo what '
            'they did there.';
    return '$result $note'.trim();
  }

  bool _touchRouteAdded = false;

  void _syncTouchRoute() {
    final want = _sessionActive && pauseOnUserTouch;
    if (want == _touchRouteAdded) return;
    final router = GestureBinding.instance.pointerRouter;
    if (want) {
      router.addGlobalRoute(_onPointer);
    } else {
      router.removeGlobalRoute(_onPointer);
    }
    _touchRouteAdded = want;
  }

  /// Real touches only: the agent acts through semantics actions, which send
  /// no pointer events.
  void _onPointer(PointerEvent event) {
    if (event is! PointerDownEvent) return;
    if (isAssistantUiAt?.call(event.position) ?? false) return;
    // Only controls the agent can see are worth telling it about
    final label = labelAt?.call(event.position);
    if (label != null) noteUserInteraction(label);
    pause(byTouch: true);
  }

  // MARK: Actions

  int _waiting = 0;
  final Map<String, VableAction> _started = {};
  int _localIds = 0;

  /// An id for an action the native side sent without one.
  String localId() => 'local_${++_localIds}';

  /// Waits until [action] may run: through any pause, and the app's gate.
  /// Returns null to go ahead, or the result to give the agent instead.
  Future<String?> beforeAct(VableAction action) async {
    _waiting++;
    _updateState();
    try {
      final generation = _generation;
      String? heldBack() {
        if (_cancelling != null) return stoppedResult;
        if (generation != _generation) return movedOnResult;
        return null;
      }

      await _whilePaused();
      if (heldBack() case final result?) return result;

      final gate = this.gate;
      if (gate != null) {
        bool allowed;
        try {
          allowed = await gate(action);
        } catch (e) {
          VableLogger.error('[VableFlutter] The action gate failed, so $action was skipped: $e');
          allowed = false;
        }
        if (!allowed) return declinedResult;
        // The user may have touched the screen or cancelled while it was open
        await _whilePaused();
        if (heldBack() case final result?) return result;
      }

      start(action);
      return null;
    } finally {
      _waiting--;
      _updateState();
    }
  }

  Future<void> _whilePaused() async {
    while (_paused && _resumed != null) {
      await _resumed!.future;
    }
  }

  /// Reports an action that needs no permission, such as pointing at a control.
  void start(VableAction action) {
    _started[action.id] = action;
    emit(VableActionStarted(action));
    _updateState();
  }

  /// Reports how the action went and returns the result to send the agent.
  String finish(String actionId, String result) {
    final text = _withUserChanges(result);
    final action = _started.remove(actionId);
    if (action != null) {
      emit(VableActionFinished(action, ok: isSuccess(text), result: text));
    }
    _updateState();
    return text;
  }

  static bool isSuccess(String result) =>
      !result.startsWith('Failed') &&
      !result.startsWith('Not done') &&
      !result.startsWith('Waiting for the user');

  // MARK: Voice

  DateTime? _agentLoudAt;
  DateTime? _userLoudSince;
  String _voiceReply = '';

  void onVoiceLevels(double agent, double user) {
    final now = DateTime.now();
    if (agent > _speakingLevel) _agentLoudAt = now;

    // An engine that says when the user speaks is more reliable than their level
    if (_engineState != null) {
      // Nothing to work out
    } else if (user > _talkingLevel) {
      _userLoudSince ??= now;
      if (now.difference(_userLoudSince!) >= _talkingTime) userTurnStarted();
    } else {
      _userLoudSince = null;
    }

    emit(VableInputLevel(user, agentLevel: agent));
    _updateState();
  }

  // MARK: The engine's view of the call

  /// What the engine says the agent is doing, on engines that send it.
  VableAgentState? _engineState;

  void onEngineState(String state) {
    _engineState = VableAgentState.values.asNameMap()[state];
    _updateState();
  }

  void onUserTranscript(String text, {required bool isFinal}) {
    emit(VableUserTranscript(text, isFinal: isFinal));
  }

  void onUserSpeechStarted() => userTurnStarted();

  /// The user talked over the agent. Like their voice cutting it off, what it
  /// was waiting to do on the screen is dropped.
  void onUserInterrupted() {
    emit(const VableUserInterrupted());
    resume(dropWaiting: true);
  }

  void onAssistantText(String text, {required bool isFinal}) {
    if (text.isEmpty && _voiceReply.isEmpty) return;
    _voiceReply += text;
    emit(VableAssistantText(text, _voiceReply, isStreaming: !isFinal));
    if (isFinal) _voiceReply = '';
  }

  // MARK: Chat

  String? _chatReplyId;
  String _chatReplyText = '';
  bool _chatReplyStreaming = false;
  bool _chatThinking = false;

  void onChatMessages(List<VableChatMessage> messages) {
    final reply = messages.lastWhereOrNull((m) => m.role == VableChatRole.assistant);
    _chatThinking = reply != null && reply.isStreaming && reply.text.isEmpty;
    _chatReplyStreaming = reply?.isStreaming ?? false;
    if (reply != null && reply.text.isNotEmpty) {
      final isNew = reply.id != _chatReplyId;
      final previous = isNew ? '' : _chatReplyText;
      final wasStreaming = !isNew && _chatWasStreaming;
      if (reply.text != previous || (wasStreaming && !reply.isStreaming)) {
        final delta =
            reply.text.startsWith(previous) ? reply.text.substring(previous.length) : reply.text;
        emit(VableAssistantText(delta, reply.text, isStreaming: reply.isStreaming));
      }
      _chatReplyId = reply.id;
      _chatReplyText = reply.text;
    }
    _chatWasStreaming = reply?.isStreaming ?? false;
    _updateState();
  }

  bool _chatWasStreaming = false;

  // MARK: State

  VableAgentState _state = VableAgentState.idle;

  VableAgentState get state => _state;

  void _updateState() {
    final now = DateTime.now();
    final VableAgentState next;
    if (_waiting > 0 || _started.isNotEmpty) {
      next = VableAgentState.acting;
    } else if (_callActive && _engineState != null) {
      next = _engineState!;
    } else if (_callActive &&
        _agentLoudAt != null &&
        now.difference(_agentLoudAt!) < _speakingHangover) {
      next = VableAgentState.speaking;
    } else if (_chatThinking) {
      next = VableAgentState.thinking;
    } else if (_chatReplyStreaming) {
      next = VableAgentState.speaking;
    } else if (_callActive) {
      next = VableAgentState.listening;
    } else {
      next = VableAgentState.idle;
    }
    if (next == _state) return;
    _state = next;
    emit(VableAgentStateChanged(next));
  }
}

extension<T> on List<T> {
  T? lastWhereOrNull(bool Function(T) test) {
    for (var i = length - 1; i >= 0; i--) {
      if (test(this[i])) return this[i];
    }
    return null;
  }
}
