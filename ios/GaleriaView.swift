import AVFoundation
import AVKit
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

    let myIndex = initialIndex ?? 0
    if isVideoTrigger(at: myIndex) {
      // Video triggers open `AVPlayerViewController` modally instead of the
      // image pager. We deliberately bypass the iielse-style pager for these
      // triggers — its image-only pipeline can't play video.
      attachVideoTapHandler(to: childImage, index: myIndex)
    } else if let urls = self.urls, let initialIndex = self.initialIndex {
      setupImageViewerWithUrls(
        childImage, urls: urls, initialIndex: initialIndex, viewerTheme: viewerTheme)
    } else {
      setupImageViewerWithSingleImage(childImage, viewerTheme: viewerTheme)
    }

    attachLongPressRecognizer(to: childImage)
  }

  private func isVideoTrigger(at index: Int) -> Bool {
    guard let types = mediaTypes, types.indices.contains(index) else { return false }
    return types[index] == "video"
  }

  private func attachVideoTapHandler(to imageView: UIImageView, index: Int) {
    let tap = UITapGestureRecognizer(
      target: self, action: #selector(handleVideoTap(_:)))
    tap.numberOfTapsRequired = 1
    imageView.addGestureRecognizer(tap)
    imageView.isUserInteractionEnabled = true
  }

  @objc private func handleVideoTap(_ recognizer: UITapGestureRecognizer) {
    let myIndex = initialIndex ?? 0
    onVideoError(["index": myIndex, "message": "DEBUG: video tap fired"])

    guard let urls = self.urls,
          urls.indices.contains(myIndex),
          let url = makeURL(from: urls[myIndex]) else {
      onVideoError(["index": myIndex, "message": "Invalid video URL"])
      return
    }

    activateAudioSession()

    let muted = (mutedFlags?.indices.contains(myIndex) == true) ? (mutedFlags?[myIndex] ?? true) : true

    let playerVC = AVPlayerViewController()
    let item = AVPlayerItem(url: url)
    let player = AVPlayer(playerItem: item)
    player.isMuted = muted
    playerVC.player = player
    playerVC.allowsPictureInPicturePlayback = false
    playerVC.modalPresentationStyle = .fullScreen

    // Surface playback failures to JS — `onVideoError` is a React event so it
    // shows up in the JS console, which is where the developer is looking.
    let observer = item.observe(\.status, options: [.new]) { [weak self] item, _ in
      DispatchQueue.main.async {
        switch item.status {
        case .failed:
          let message = item.error?.localizedDescription ?? "Unknown playback error"
          self?.onVideoError(["index": myIndex, "message": message])
        case .readyToPlay:
          self?.onVideoError(["index": myIndex, "message": "DEBUG: readyToPlay"])
        default:
          break
        }
      }
    }
    objc_setAssociatedObject(
      playerVC, &GaleriaView.observerKey, observer,
      .OBJC_ASSOCIATION_RETAIN_NONATOMIC)

    guard let topVC = findTopViewController() else {
      onVideoError(["index": myIndex, "message": "No top view controller to present from"])
      return
    }

    topVC.present(playerVC, animated: true) { [weak self] in
      player.play()
      self?.onVideoError(["index": myIndex, "message": "DEBUG: presented + play()"])
    }
  }

  private static var observerKey: UInt8 = 0

  private func findTopViewController() -> UIViewController? {
    let keyWindow = UIApplication.shared.connectedScenes
      .compactMap { $0 as? UIWindowScene }
      .flatMap { $0.windows }
      .first { $0.isKeyWindow }
    var top = keyWindow?.rootViewController
    while let presented = top?.presentedViewController {
      top = presented
    }
    return top
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
    childImage.setupImageViewer(items: items, initialIndex: initialIndex, options: options)
  }

  private func buildImageItems(urls: [String]) -> [ImageItem] {
    return urls.enumerated().map { index, urlString in
      let isVideo = (mediaTypes?.indices.contains(index) == true) && mediaTypes?[index] == "video"
      // For video entries we render the poster (if any) in the image-only
      // swipe pager — actual playback happens by tapping the video trigger
      // directly, which opens `AVPlayerViewController` modally.
      let imageURLString = isVideo
        ? (posters?.indices.contains(index) == true ? (posters?[index] ?? "") : "")
        : urlString
      if let url = makeURL(from: imageURLString) {
        return ImageItem.url(url, placeholder: nil)
      }
      return ImageItem.image(nil)
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
