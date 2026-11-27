import Flutter
import UIKit

class SceneDelegate: FlutterSceneDelegate {
  override func scene(_ scene: UIScene, willConnectTo session: UISceneSession,
                      options connectionOptions: UIScene.ConnectionOptions) {
    guard let scene = scene as? UIWindowScene,
          let delegate = UIApplication.shared.delegate as? AppDelegate else { return }
    let window = UIWindow(windowScene: scene)
    window.rootViewController = FlutterViewController(
      engine: delegate.sharedEngine, nibName: nil, bundle: nil)
    self.window = window
    window.makeKeyAndVisible()
    // Edge+: a cold launch from a widget tap carries its URL here.
    for ctx in connectionOptions.urlContexts { SceneDelegate.latchWidgetRoute(ctx.url) }
    super.scene(scene, willConnectTo: session, options: connectionOptions)
  }

  // Edge+: a widget tap while the app is already running.
  override func scene(_ scene: UIScene, openURLContexts URLContexts: Set<UIOpenURLContext>) {
    for ctx in URLContexts { SceneDelegate.latchWidgetRoute(ctx.url) }
    super.scene(scene, openURLContexts: URLContexts)
  }

  /// Edge+: home-screen widgets open `openstrap://route/<path>`
  /// (EdgePlusWidgets.swift). The path goes into the App Group's
  /// `pending_route` — the latch StartBreathingIntent already writes — and
  /// AppState.checkPendingSiriRoute routes it on launch and on resume, so a
  /// widget tap needs no Dart-side path of its own.
  static func latchWidgetRoute(_ url: URL) {
    guard url.scheme == "openstrap", url.host == "route" else { return }
    let path = url.path
    guard path.hasPrefix("/"), path.count > 1 else { return }
    OpenStrapShared.defaults()?.set(path, forKey: "pending_route")
  }

  // Whenever the phone app comes to the foreground, mirror the App Group
  // snapshot to the watch, so the wrist is not waiting on the next derive.
  // This has to live here: once the app opts into scenes UIKit stops calling
  // AppDelegate.applicationDidBecomeActive, and Flutter's scene fallback only
  // forwards it to plugins, so an AppDelegate override never runs.
  //
  // It mirrors whatever is already there — nothing rewrites the group on a mere
  // foreground, only a completed derive does (AppState → WidgetService.refresh).
  // So this can ship yesterday's snapshot, and that is survivable only because
  // the watch ages `updated_at` itself (WatchMetrics.fresh) and shows its
  // no-recent-data state rather than yesterday's numbers.
  override func sceneDidBecomeActive(_ scene: UIScene) {
    super.sceneDidBecomeActive(scene)
    WatchBridge.shared.pushCurrentState()
  }

  /// Re-submit the BGProcessingTask + BGAppRefreshTask requests every time a
  /// scene enters the background so iOS always has pending requests to fire
  /// opportunistically. This is the correct hook in a UISceneDelegate-based app
  /// (scene lifecycle fires reliably; AppDelegate.applicationDidEnterBackground
  /// fires less consistently when UISceneDelegate is in use).
  override func sceneDidEnterBackground(_ scene: UIScene) {
    super.sceneDidEnterBackground(scene)
    BackgroundTaskManager.schedule()
    BackgroundTaskManager.scheduleRefresh()
  }
}
