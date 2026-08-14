import Flutter
import UIKit

class SceneDelegate: FlutterSceneDelegate {
  private var privacyView: UIView?

  override func sceneWillResignActive(_ scene: UIScene) {
    super.sceneWillResignActive(scene)
    installPrivacyOverlay()
  }

  override func sceneDidEnterBackground(_ scene: UIScene) {
    super.sceneDidEnterBackground(scene)
    installPrivacyOverlay()
  }

  override func sceneDidBecomeActive(_ scene: UIScene) {
    super.sceneDidBecomeActive(scene)
    privacyView?.removeFromSuperview()
    privacyView = nil
  }

  private func installPrivacyOverlay() {
    guard let window = window, privacyView == nil else { return }
    let cover = UIView(frame: window.bounds)
    cover.autoresizingMask = [.flexibleWidth, .flexibleHeight]
    cover.backgroundColor = UIColor(
      red: 9 / 255,
      green: 19 / 255,
      blue: 17 / 255,
      alpha: 1
    )
    cover.isAccessibilityElement = true
    cover.accessibilityLabel = "Lar Finance protegido"
    window.addSubview(cover)
    privacyView = cover
  }
}
