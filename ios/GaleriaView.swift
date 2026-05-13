import AVFoundation
import ExpoModulesCore
import UIKit

class GaleriaView: ExpoView {
  private var childImageView: UIImageView?
  private weak var currentNavigationView: NavigationView?
  private weak var previousFirstResponder: UIResponder?
  private var isRegistered = false
  
  var groupId: String? {
    guard let urls = urls, !urls.isEmpty else { return nil }
    return String(urls.joined(separator: ",").hashValue)
  }
  
  deinit {
    unregisterFromRegistry()
  }
  
  private func registerWithRegistry() {
    guard let groupId = groupId, let index = initialIndex else { return }
    GaleriaViewRegistry.shared.register(view: self, groupId: groupId, index: index)
    isRegistered = true
  }
  
  private func unregisterFromRegistry() {
    guard isRegistered, let groupId = groupId, let index = initialIndex else { return }
    GaleriaViewRegistry.shared.unregister(groupId: groupId, index: index)
    isRegistered = false
  }
  
  class func findView(groupId: String, index: Int) -> GaleriaView? {
    return GaleriaViewRegistry.shared.view(forGroupId: groupId, index: index)
  }

  func getChildImageView() -> UIImageView? {
    for reactSubview in self.subviews {
      for subview in reactSubview.subviews {
        if let imageView = subview as? UIImageView {
          childImageView = imageView
          return imageView
        }
      }
    }

    return nil
  }

  var theme: Theme = .dark
  var urls: [String]?
  var mediaTypes: [String]?
  var posters: [String]?
  var mutedFlags: [Bool]?
  var initialIndex: Int?
  var closeIconName: String?
  var rightNavItemIconName: String?
  var hideBlurOverlay: Bool = false
  var hidePageIndicators: Bool = false
  let onPressRightNavItemIcon = EventDispatcher()
  let onIndexChange = EventDispatcher()
  let onLongPress = EventDispatcher()
  let onDismiss = EventDispatcher()
  let onVideoError = EventDispatcher()

  private var didActivateAudioSession = false

  public func setupImageView() {
    // Clean up previous state for Fabric view recycling (see #19)
    childImageView?.gestureRecognizers?.removeAll()
    childImageView = nil
    unregisterFromRegistry()

    let viewerTheme = theme.toImageViewerTheme()
    guard let childImage = getChildImageView() else {
      return
    }

    registerWithRegistry()

    if let urls = self.urls, let initialIndex = self.initialIndex {
      setupImageViewerWithUrls(
        childImage, urls: urls, initialIndex: initialIndex, viewerTheme: viewerTheme)
    } else {
      setupImageViewerWithSingleImage(childImage, viewerTheme: viewerTheme)
    }

    attachLongPressRecognizer(to: childImage)
  }

  private func attachLongPressRecognizer(to imageView: UIImageView) {
    let longPress = UILongPressGestureRecognizer(
      target: self, action: #selector(handleLongPress(_:)))
    longPress.minimumPressDuration = 0.5
    imageView.addGestureRecognizer(longPress)
    imageView.isUserInteractionEnabled = true
  }

  @objc private func handleLongPress(_ recognizer: UILongPressGestureRecognizer) {
    if recognizer.state == .began {
      onLongPress()
    }
  }

  private func setupImageViewerWithUrls(
    _ childImage: UIImageView,
    urls: [String],
    initialIndex: Int,
    viewerTheme: ImageViewerTheme
  ) {
    let options = buildImageViewerOptions()
    let items = buildImageItems(urls: urls)
    let hasVideo = items.contains { if case .video = $0 { return true } else { return false } }
    if hasVideo {
      activateAudioSession()
    }
    childImage.setupImageViewer(items: items, initialIndex: initialIndex, options: options)
  }

  private func buildImageItems(urls: [String]) -> [ImageItem] {
    return urls.enumerated().map { index, urlString in
      let url = makeURL(from: urlString)
      let isVideo = (mediaTypes?.indices.contains(index) == true) && mediaTypes?[index] == "video"
      if isVideo, let url = url {
        let muted = (mutedFlags?.indices.contains(index) == true) ? (mutedFlags?[index] ?? true) : true
        let posterString = (posters?.indices.contains(index) == true) ? posters?[index] : nil
        let posterItem: ImageItem?
        if let posterString = posterString, !posterString.isEmpty, let posterURL = makeURL(from: posterString) {
          posterItem = .url(posterURL, placeholder: nil)
        } else {
          posterItem = nil
        }
        return ImageItem.video(url, poster: posterItem, muted: muted)
      } else if let url = url {
        return ImageItem.url(url, placeholder: nil)
      } else {
        return ImageItem.image(nil)
      }
    }
  }

  private func makeURL(from string: String) -> URL? {
    if string.isEmpty { return nil }
    if string.hasPrefix("http://") || string.hasPrefix("https://") || string.hasPrefix("file://") {
      return URL(string: string)
    }
    return URL(fileURLWithPath: string)
  }

  private func activateAudioSession() {
    guard !didActivateAudioSession else { return }
    let session = AVAudioSession.sharedInstance()
    do {
      try session.setCategory(.playback, mode: .moviePlayback, options: [.duckOthers])
      try session.setActive(true)
      didActivateAudioSession = true
    } catch {
      // Non-fatal: video will still play silently if the session can't activate.
    }
  }

  private func deactivateAudioSession() {
    guard didActivateAudioSession else { return }
    try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    didActivateAudioSession = false
  }

  private func setupImageViewerWithSingleImage(
    _ childImage: UIImageView, viewerTheme: ImageViewerTheme
  ) {
    guard let img = childImage.image else {
      print("Missing image in childImage: \(childImage)")
      return
    }
    let options = buildImageViewerOptions()

    childImage.setupImageViewer(images: [img], options: options)
  }

  private func buildImageViewerOptions() -> [ImageViewerOption] {
    let viewerTheme = theme.toImageViewerTheme()
    var options: [ImageViewerOption] = [.theme(viewerTheme)]
    let iconColor = theme.iconColor()

    if let closeIconName = closeIconName,
      let closeIconImage = UIImage(systemName: closeIconName)?.withTintColor(
        iconColor, renderingMode: .alwaysOriginal)
    {
      options.append(ImageViewerOption.closeIcon(closeIconImage))

    }

    if let rightIconName = rightNavItemIconName,
      let rightIconImage = UIImage(systemName: rightIconName)?.withTintColor(
        iconColor, renderingMode: .alwaysOriginal)
    {
      let rightNavItemOption = ImageViewerOption.rightNavItemIcon(
        rightIconImage,
        onTap: { index in
          self.onPressRightNavItemIcon(["index": index])
        })
      options.append(rightNavItemOption)
    }

    options.append(
      .onIndexChange { [weak self] index in
        self?.onIndexChange(["currentIndex": index])
      })

      options.append(
        .onDismiss { [weak self] in
            self?.restoreKeyboard()
            self?.deactivateAudioSession()
            self?.onDismiss()
        })

    options.append(
      .onVideoError { [weak self] index, message in
        self?.onVideoError(["index": index, "message": message])
      })

    options.append(.hideBlurOverlay(hideBlurOverlay))
    options.append(.hidePageIndicators(hidePageIndicators))

    return options
  }
}

enum Theme: String, Enumerable {
  case dark
  case light

  func toImageViewerTheme() -> ImageViewerTheme {
    switch self {
    case .dark:
      return .dark
    case .light:
      return .light
    }
  }
  func iconColor() -> UIColor {
    return UIColor.label
  }
}

extension GaleriaView: MatchTransitionDelegate {
  func matchedViewFor(transition: MatchTransition, otherView: UIView) -> UIView? {
    guard let imageView = childImageView else { return nil }

    if let parentCornerRadius = findCornerRadius(for: imageView), parentCornerRadius > 0 {
      imageView.layer.cornerRadius = parentCornerRadius
      imageView.clipsToBounds = true
    }

    return imageView
  }

    func matchTransitionWillBegin(transition: MatchTransition) {
        guard previousFirstResponder == nil else { return }
        
        previousFirstResponder = UIResponder.currentFirstResponder
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }
    
    func restoreKeyboard() {
        previousFirstResponder?.becomeFirstResponder()
        previousFirstResponder = nil
    }

  private func findCornerRadius(for view: UIView) -> CGFloat? {
    var current: UIView? = view.superview
    while let parent = current {
      if parent.layer.cornerRadius > 0 {
        return parent.layer.cornerRadius
      }
      if parent === self {
        break
      }
      current = parent.superview
    }
    return nil
  }
}

extension UIResponder {
    private static weak var _currentFirstResponder: UIResponder?
    
    static var currentFirstResponder: UIResponder? {
        _currentFirstResponder = nil
        UIApplication.shared.sendAction(#selector(findFirstResponder(_:)), to: nil, from: nil, for: nil)
        return _currentFirstResponder
    }
    
    @objc private func findFirstResponder(_ sender: Any) {
        UIResponder._currentFirstResponder = self
    }
}
