import Flutter
import UIKit

class SceneDelegate: FlutterSceneDelegate {}

final class DonglgewiViewController: FlutterViewController {
  private var publishedSide: String?

  override func viewDidLoad() {
    super.viewDidLoad()
    if #available(iOS 27.1, *) {
      registerForTraitChanges(UITraitCollection.systemTraitsAffectingVerticalBarEdge) {
        (controller: DonglgewiViewController, _: UITraitCollection) in
        controller.publishToolbarSide()
      }
    }
  }

  override func viewDidLayoutSubviews() {
    super.viewDidLayoutSubviews()
    publishToolbarSide()
  }

  override func viewSafeAreaInsetsDidChange() {
    super.viewSafeAreaInsetsDidChange()
    publishToolbarSide()
  }

  var toolbarSide: String? {
    guard #available(iOS 27.1, *) else { return nil }
    let leftToRight = view.effectiveUserInterfaceLayoutDirection == .leftToRight
    switch traitCollection.verticalBarEdge {
    case .leading: return leftToRight ? "left" : "right"
    case .trailing: return leftToRight ? "right" : "left"
    default: return nil
    }
  }

  private func publishToolbarSide() {
    guard view.window != nil,
          let delegate = UIApplication.shared.delegate as? AppDelegate else { return }
    let side = toolbarSide
    guard publishedSide != side else { return }
    publishedSide = side
    delegate.layoutChannel?.invokeMethod("toolbarSideChanged", arguments: side)
  }
}
