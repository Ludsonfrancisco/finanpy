import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private var privacyView: UIView?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
  }

  override func applicationDidEnterBackground(_ application: UIApplication) {
    super.applicationDidEnterBackground(application)
    guard let window = window else { return }
    let cover = UIView(frame: window.bounds)
    cover.backgroundColor = UIColor(
      red: 9 / 255,
      green: 19 / 255,
      blue: 17 / 255,
      alpha: 1
    )
    cover.accessibilityLabel = "Lar Finance protegido"
    window.addSubview(cover)
    privacyView = cover
  }

  override func applicationWillEnterForeground(_ application: UIApplication) {
    privacyView?.removeFromSuperview()
    privacyView = nil
    super.applicationWillEnterForeground(application)
  }
}
