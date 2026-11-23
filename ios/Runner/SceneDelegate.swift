import Flutter
import UIKit

class SceneDelegate: FlutterSceneDelegate {}

final class DonglgewiViewController: FlutterViewController {
  private(set) var roomToolbarVisible = false
  private lazy var roomItems = [
    roomItem("care", title: "돌보기", symbol: "heart"),
    roomItem("talk", title: "말 걸기", symbol: "bubble.left"),
    roomItem("bag", title: "가방", symbol: "archivebox"),
    roomItem("album", title: "앨범·도감", symbol: "photo.on.rectangle"),
    roomItem("settings", title: "설정", symbol: "gearshape"),
  ]

  override func viewDidLoad() {
    super.viewDidLoad()
    if #available(iOS 27.1, *) {
      navigationItem.trailingItemGroups = roomItems.map {
        UIBarButtonItemGroup(barButtonItems: [$0.item], representativeItem: nil)
      }
      registerForTraitChanges(UITraitCollection.systemTraitsAffectingVerticalBarEdge) {
        (controller: DonglgewiViewController, _: UITraitCollection) in
        controller.updateRoomToolbar()
      }
    }
  }

  override func viewDidLayoutSubviews() {
    super.viewDidLayoutSubviews()
    updateRoomToolbar()
  }

  override func viewSafeAreaInsetsDidChange() {
    super.viewSafeAreaInsetsDidChange()
    updateRoomToolbar()
  }

  private func roomItem(_ id: String, title: String, symbol: String) -> (id: String, item: UIBarButtonItem) {
    let action = UIAction(title: title, image: UIImage(systemName: symbol)) { _ in
      let delegate = UIApplication.shared.delegate as? AppDelegate
      guard delegate?.roomToolbarActions[id] == true else { return }
      delegate?.layoutChannel?.invokeMethod("roomToolbarAction", arguments: id)
    }
    let item = UIBarButtonItem(primaryAction: action)
    item.accessibilityLabel = title
    item.isEnabled = false
    return (id, item)
  }

  func updateRoomToolbar() {
    guard #available(iOS 27.1, *), viewIfLoaded?.window != nil,
          let navigation = navigationController,
          let delegate = UIApplication.shared.delegate as? AppDelegate else { return }
    for entry in roomItems {
      entry.item.isEnabled = delegate.roomToolbarActions[entry.id] == true
    }
    let rightEdge = view.effectiveUserInterfaceLayoutDirection == .leftToRight
      ? traitCollection.verticalBarEdge == .trailing
      : traitCollection.verticalBarEdge == .leading
    let visible = rightEdge && navigation.view.bounds.width < 620
    guard roomToolbarVisible != visible else { return }
    roomToolbarVisible = visible
    navigation.setNavigationBarHidden(!visible, animated: false)
    delegate.layoutChannel?.invokeMethod("roomToolbarVisibleChanged", arguments: visible)
  }
}
