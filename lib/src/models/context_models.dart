/// Represents a Flutter route in the application
class VableRoute {
  /// The route path (e.g., "/home", "/profile")
  final String path;

  /// The route name if available (optional)
  final String? name;

  const VableRoute({
    required this.path,
    this.name,
  });

  Map<String, dynamic> toJson() {
    return {
      'path': path,
      if (name != null) 'name': name,
    };
  }

  factory VableRoute.fromJson(Map<String, dynamic> json) {
    return VableRoute(
      path: json['path'] as String,
      name: json['name'] as String?,
    );
  }
}

class IntentParameter {
  final String description;
  final String type;
  final bool? required;
  final List<ToolParameterOption>? options;

  IntentParameter({
    required this.description,
    required this.type,
    this.required,
    this.options,
  });

  factory IntentParameter.fromJson(Map<String, dynamic> json) {
    return IntentParameter(
      description: json['description'] as String,
      type: json['type'] as String,
      required: json['required'] as bool?,
      options: (json['options'] as List<dynamic>?)
          ?.map((e) => ToolParameterOption.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'description': description,
      'type': type,
      if (required != null) 'required': required,
      if (options != null) 'options': options!.map((e) => e.toJson()).toList(),
    };
  }
}

class ToolParameterOption {
  final String label;
  final dynamic value;

  ToolParameterOption({
    required this.label,
    required this.value,
  });

  factory ToolParameterOption.fromJson(Map<String, dynamic> json) {
    return ToolParameterOption(
      label: json['label'] as String,
      value: json['value'],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'label': label,
      'value': value,
    };
  }
}


/// Represents an intent in the application.
///
/// [name] is the unique identifier for the intent and is used by the AI agent
/// to match user requests and invoke the correct handler.
class VableIntent {
  /// Unique name for the intent — used by the AI to identify and invoke it
  final String name;

  /// Optional description of what the intent does
  final String? description;

  /// Parameters the AI should extract from the conversation before invoking this intent
  final Map<String, IntentParameter>? parameters;

  const VableIntent({
    required this.name,
    this.description,
    this.parameters,
  });

  Map<String, dynamic> toJson() {
    return {
      'name': name,
      if (description != null) 'description': description,
      if (parameters != null)
        'parameters': parameters!.map((k, v) => MapEntry(k, v.toJson())),
    };
  }
}

/// A named piece of app state exposed to the AI agent as context.
///
/// Intent states are not tied to a specific intent — they describe what is
/// currently happening in the app (e.g. the list of products in view, the
/// current user session, cart contents). The AI reads these to make better
/// decisions during a conversation.
class VableIntentState {
  /// Unique name identifying this piece of state
  final String name;

  /// Human-readable description of what the value contains
  final String description;

  /// The current state data (Map, List, String, number, etc.)
  final dynamic value;

  const VableIntentState({
    required this.name,
    required this.description,
    required this.value,
  });

  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'description': description,
      'value': value,
    };
  }
}

/// Represents a prompt associated with an intent
class VableIntentPrompt {
  /// The intent ID this prompt belongs to
  final String intentId;

  /// The prompt text
  final String prompt;

  /// Optional context for the prompt
  final String? context;

  const VableIntentPrompt({
    required this.intentId,
    required this.prompt,
    this.context,
  });

  Map<String, dynamic> toJson() {
    return {
      'intentId': intentId,
      'prompt': prompt,
      if (context != null) 'context': context,
    };
  }
}

/// Context update containing intents, intent states, intent prompts, and routes
/// This is sent to the AI agent via NATS to provide application context
class VableContextUpdate {
  /// List of application intents
  final List<VableIntent> intents;

  /// List of intent states
  final List<VableIntentState> intentStates;

  /// List of intent prompts
  final List<VableIntentPrompt> intentPrompts;

  /// List of application routes
  final List<VableRoute> routes;

  const VableContextUpdate({
    this.intents = const [],
    this.intentStates = const [],
    this.intentPrompts = const [],
    this.routes = const [],
  });

  Map<String, dynamic> toJson() {
    return {
      'intents': intents.map((i) => i.toJson()).toList(),
      'intentStates': intentStates.map((s) => s.toJson()).toList(),
      'intentPrompts': intentPrompts.map((p) => p.toJson()).toList(),
      'routes': routes.map((r) => r.toJson()).toList(),
    };
  }
}
