import ExpoModulesCore

public class GaleriaModule: Module {
  public func definition() -> ModuleDefinition {
    Name("Galeria")

    View(GaleriaView.self) {
      Events("onIndexChange", "onLongPress")
      Events("onIndexChange", "onPressRightNavItemIcon")
      Events("onIndexChange", "onDismiss")
      Events("onVideoError")

      OnViewDidUpdateProps { (view) in
        view.setupImageView()
      }

      Prop("urls") { (view, urls: [String]?) in
        view.urls = urls
      }

      Prop("mediaTypes") { (view, mediaTypes: [String]?) in
        view.mediaTypes = mediaTypes
      }

      Prop("posters") { (view, posters: [String]?) in
        view.posters = posters
      }

      Prop("mutedFlags") { (view, mutedFlags: [Bool]?) in
        view.mutedFlags = mutedFlags
      }

      Prop("index") { (view, index: Int?) in
        view.initialIndex = index
      }

      Prop("theme") { (view, theme: Theme?) in
        view.theme = theme ?? .dark
      }
      Prop("closeIconName") { (view, closeIconName: String?) in
        view.closeIconName = closeIconName
      }
      Prop("rightNavItemIconName") { (view, rightNavItemIconName: String) in
        view.rightNavItemIconName = rightNavItemIconName
      }

      Prop("hideBlurOverlay") { (view, hideBlurOverlay: Bool?) in
        view.hideBlurOverlay = hideBlurOverlay ?? false
      }

      Prop("hidePageIndicators") { (view, hidePageIndicators: Bool?) in
        view.hidePageIndicators = hidePageIndicators ?? false
      }

    }
  }

  func onIndexChange(index: Int) {
    sendEvent("onIndexChange", ["currentIndex": index])
  }
}
