import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

/// What the agent is doing, for apps that draw their own call UI.
enum VableAgentState {
  /// No call, and no chat reply on its way
  idle,

  /// On a call, waiting for the user
  listening,

  /// Working on a reply it hasn't started saying yet. Only told apart in the
  /// text chat for now.
  thinking,

  /// The agent's voice can be heard
  speaking,

  /// An action on the screen is running, or waiting for your gate or a pause
  acting,
}

/// The kinds of things the agent does on the screen.
enum VableActionKind {
  /// Taps a button, card, tab or other control
  click,

  /// Types into a field
  inputText,

  /// Scrolls the main list
  scroll,

  /// Goes back, or closes a dialog or sheet
  goBack,

  /// Moves a slider or stepper
  adjust,

  /// Opens a route
  navigate,

  /// Shows the user a control without touching it, for things they must do
  /// themselves. Only offered to the agent with [VableCallStyle.none].
  pointAt,

  /// One of your app's own intents
  intent,
}

/// One thing the agent is about to do, or did, on the screen.
@immutable
class VableAction {
  const VableAction({
    required this.id,
    required this.kind,
    required this.tool,
    this.elementId,
    this.label,
    this.bounds,
    this.args = const {},
  });

  /// The agent's tool call id. [VableActionStarted] and [VableActionFinished]
  /// for one action share it.
  final String id;

  final VableActionKind kind;

  /// The tool's name, such as `clickElement` or your intent's name
  final String tool;

  /// The `s_<n>` id of the element it acts on, when it acts on one
  final String? elementId;

  /// The element's label, as the agent sees it
  final String? label;

  /// Where the element is, in global logical pixels, once it's on screen
  final Rect? bounds;

  /// What the agent passed, such as `{text: 'Lisbon'}` or `{url: '/search'}`
  final Map<String, dynamic> args;

  /// The same action, once its element has been found
  VableAction withElement({String? elementId, String? label, Rect? bounds}) => VableAction(
        id: id,
        kind: kind,
        tool: tool,
        elementId: elementId ?? this.elementId,
        label: label ?? this.label,
        bounds: bounds ?? this.bounds,
        args: args,
      );

  @override
  String toString() =>
      'VableAction($kind, $tool${label == null ? '' : ', "$label"'}${elementId == null ? '' : ', $elementId'})';
}

/// Decides whether the agent may go ahead with [action]. Return false to skip
/// it: the agent is told the user declined. The agent waits for as long as
/// this takes, so it's the place to highlight the target first.
typedef VableActionGate = FutureOr<bool> Function(VableAction action);

/// How the agent's text goes into a field.
@immutable
class VableTyping {
  const VableTyping._(this.perCharacter);

  /// All at once (the default)
  static const VableTyping instant = VableTyping._(null);

  /// One character at a time, [delay] apart, so the user sees it typed
  const factory VableTyping.perCharacter([Duration delay]) = _PerCharacter;

  /// The pause between characters, or null for all at once
  final Duration? perCharacter;
}

class _PerCharacter extends VableTyping {
  const _PerCharacter([Duration super.perCharacter = const Duration(milliseconds: 45)]) : super._();
}

/// Something that happened in a call or chat, from [Vable.events].
sealed class VableEvent {
  const VableEvent();
}

/// A call connected.
class VableCallStarted extends VableEvent {
  const VableCallStarted();
}

/// A call ended, for any reason.
class VableCallEnded extends VableEvent {
  const VableCallEnded();
}

/// The agent's state changed.
class VableAgentStateChanged extends VableEvent {
  const VableAgentStateChanged(this.state);
  final VableAgentState state;

  @override
  String toString() => 'VableAgentStateChanged($state)';
}

/// What the user has said so far.
///
/// Not sent yet: it needs the engine to send the transcript, which is planned.
class VableUserTranscript extends VableEvent {
  const VableUserTranscript(this.text, {required this.isFinal});
  final String text;
  final bool isFinal;
}

/// The user started talking over the agent.
///
/// Not sent yet: it needs the engine to say so, which is planned.
class VableUserInterrupted extends VableEvent {
  const VableUserInterrupted();
}

/// The agent's reply, as it arrives. On a call the text arrives as the model
/// writes it, a little ahead of the voice.
class VableAssistantText extends VableEvent {
  const VableAssistantText(this.delta, this.text, {required this.isStreaming});

  /// What this event adds
  final String delta;

  /// The whole reply so far
  final String text;

  /// False once the reply is complete
  final bool isStreaming;

  @override
  String toString() => 'VableAssistantText("$text", isStreaming: $isStreaming)';
}

/// How loud the user's microphone is, about 10 times a second during a call.
class VableInputLevel extends VableEvent {
  const VableInputLevel(this.level, {this.agentLevel = 0});

  /// The user, from 0 to 1. It's 0 while the mic is muted.
  final double level;

  /// The agent's voice, from 0 to 1
  final double agentLevel;
}

/// The agent is acting on the screen now: your gate allowed it and nothing is
/// paused.
class VableActionStarted extends VableEvent {
  const VableActionStarted(this.action);
  final VableAction action;

  @override
  String toString() => 'VableActionStarted($action)';
}

/// An action finished, with what the agent was told. Every
/// [VableActionStarted] is followed by one of these.
class VableActionFinished extends VableEvent {
  const VableActionFinished(this.action, {required this.ok, required this.result});
  final VableAction action;

  /// False when it failed or was held back
  final bool ok;

  /// The tool result sent to the agent
  final String result;

  @override
  String toString() => 'VableActionFinished($action, ok: $ok)';
}
