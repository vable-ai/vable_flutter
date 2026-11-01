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
