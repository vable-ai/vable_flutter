## 0.0.10

Needs the iOS SDK 0.0.11 and the Android SDK 0.0.1+12.

* Every call is greeted, a reopened conversation too, as the web widget does. 0.0.9 only greeted a new conversation, so most calls stayed silent until the user spoke.
* With the engine on dev and prod since 12 November, calls connect about a second sooner and the welcome starts once the user can hear it, so its first words are no longer lost.

## 0.0.9

Needs the iOS SDK 0.0.10 and the Android SDK 0.0.1+11.

* The welcome is spoken over the call: a new call asks for the project's welcome once the call can hear the user, so on iOS it's no longer cut off when the microphone comes on, and the user can talk over it. A resumed conversation isn't greeted.
* The plugin's own log lines go to the native SDK, which can send them to Vable with its own when the project's client log level asks for them. `VableLogger` takes an optional `tag` and `fields`, and has `warn`.

## 0.0.8

Needs the iOS SDK 0.0.9 and the Android SDK 0.0.1+10. The agent's state, what the user says, `say` and cancelling also need the engine that sends them, which dev and prod have.

* Draw the call yourself: `Vable.setCallStyle(VableCallStyle.none)` shows nothing native, and `Vable.events` reports the agent's state, its reply as it arrives, mic levels, and each action it takes on the screen.
* Pace the agent: `Vable.setActionGate` runs before each action so you can show what's coming or skip it, `Vable.setTyping` types a character at a time, and `Vable.pauseActions`, `resumeActions` and `cancelCurrentTask` hold or stop it. With no native UI, the user's touches pause it, and it hears what they changed.
* `VableRequiresUser` keeps a control for the user while the agent can still see it and point it out.
* `VableAssistantUi` marks your own assistant UI: the agent can't see it, and touching it doesn't pause the agent.
* What the user says arrives as `VableUserTranscript`, and talking over the agent as `VableUserInterrupted`, which drops what it was waiting to do on the screen. The agent's state comes from the server on a call.
* `Vable.say` has the agent say your text word for word, and `cancelCurrentTask` now also stops what it's saying and the reply it's working on.

## 0.0.7

Needs the iOS SDK 0.0.8 and the Android SDK 0.0.1+9.

* Text chat, for users who would rather type: `Vable.openChat(context)` opens a chat panel that shares one conversation with calls. Its mic button carries the conversation on as a call, and calls get a keyboard button to switch back to the chat. Replies stream in, and the agent can run your intents from the chat as it does on a call.
* Apps that draw their own chat can use `Vable.sendMessage` and the `Vable.chatMessages` stream instead. `Vable.onChatOpened`, `onChatClosed`, `onChatError` and `onVoiceChatStarted` report what happens.
* `Vable.setChatButtonVisible(false)` hides the chat button on calls.

## 0.0.6

Needs the iOS SDK 0.0.7 and the Android SDK 0.0.1+8.

* Signed-in users: `Vable.initialize(accessToken:)` and `Vable.setAccessToken` pass the user's access token, as the web widget's `accessToken` does. It's sent when each call starts, so the agent knows who the user is.

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
