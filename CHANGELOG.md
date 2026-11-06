## 0.0.5

Needs the iOS SDK 0.0.6 and the Android SDK 0.0.1+7.

* Screen frames: when your project turns them on, small pictures of the screen are recorded during calls, so your team can see what the user saw next to what the agent did. Text fields, private fields and anything inside `VableNoOp` or the new `VableMask` are covered before a picture leaves the device. They're off unless the project turns them on.
* Intents registered before routes are sent are no longer lost. `Vable.initialize(routes:)` and `Vable.configureRouter` used to replace the app's own intents, so the agent never saw them.
* Each tool result now names the call it answers, so the agent can tell results apart.
* On iOS, hanging up tells the server the call is over, so the call ends straight away rather than when the server notices the silence.

## 0.0.4

* On iOS, the plugin is now a Swift package, which Flutter uses by default, with the iOS SDK 0.0.5. CocoaPods no longer takes new releases, so 0.0.3 couldn't install the iOS SDK it needed. Apps don't need a `pod 'VableAI'` line any more; remove it if you added one.

## 0.0.3

Needs iOS 15 or later, the iOS SDK 0.0.4 and the Android SDK 0.0.1+6. With Xcode 27, use Flutter 3.47 or later.

* Calls show as a soft glow round the edges of the screen, with a small end button on the edge. `Vable.setGlowColor`, `Vable.setEndButtonVisible` and `Vable.setCallStyle(VableCallStyle.pill)` change it.
* `Vable.setCallPillPosition` moves the pill to the top.
* The agent can go back, move sliders, and is told when an id it used doesn't exist.
* The agent never sees what's typed in fields inside `VableNoOp` or fields labelled like a card number, CVV, PIN, account or ID number.
* `Vable.configureRouter(excludeRoutes:)` leaves out routes that need something passed to them.
* On Android, `Vable.startVoiceChat` returns once the call is connected, as on iOS.
* `Vable.setMicrophoneMuted` tells the agent, so it doesn't end a call for silence.
* Debug builds log the controls the agent can't name.

## 0.0.1

* TODO: Describe initial release.
