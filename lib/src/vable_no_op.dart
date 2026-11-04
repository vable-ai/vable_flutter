import 'package:flutter/widgets.dart';

/// Identifies the render objects that [VableNoOp] creates.
const Object vableNoOpMarker = _VableNoOpMarker();

class _VableNoOpMarker {
  const _VableNoOpMarker();
}

/// Keeps [child] and everything inside it away from the agent, such as a
/// delete confirmation or a payment button. The agent will ask the user to do
/// it themselves. This doesn't change layout or how the user interacts with it.
///
/// ```dart
/// VableNoOp(
///   child: FilledButton(onPressed: deleteAccount, child: Text('Delete')),
/// )
/// ```
class VableNoOp extends StatelessWidget {
  const VableNoOp({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return MetaData(
      metaData: vableNoOpMarker,
      behavior: HitTestBehavior.deferToChild,
      child: child,
    );
  }
}

/// Identifies the render objects that [VableMask] creates.
const Object vableMaskMarker = _VableMaskMarker();

class _VableMaskMarker {
  const _VableMaskMarker();
}

/// Covers [child] with a solid box in the screen frames recorded during a call,
/// such as a card image or a document. The box is drawn on the device, before
/// the frame leaves it. Text fields and anything inside [VableNoOp] are covered
/// already. This doesn't change layout, what the agent can do, or what the
/// user sees.
///
/// Frames are only recorded when the project has turned them on.
///
/// ```dart
/// VableMask(child: Image.network(card.imageUrl))
/// ```
class VableMask extends StatelessWidget {
  const VableMask({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return MetaData(
      metaData: vableMaskMarker,
      behavior: HitTestBehavior.deferToChild,
      child: child,
    );
  }
}
