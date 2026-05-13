import AVFoundation
import AVKit
import UIKit

class VideoViewerController: UIViewController {

    let imageLoader: ImageLoader

    var index: Int = 0
    var imageItem: ImageItem!

    var initialPlaceholder: UIImage?
    var onVideoError: ((Int, String) -> Void)?

    private(set) var scrollView: UIScrollView!
    let containerView = UIView()
    let posterImageView = UIImageView()
    private let playerViewController = AVPlayerViewController()
    private(set) var player: AVPlayer?
    private var playerItemStatusObservation: NSKeyValueObservation?
    private var playerItemErrorObservation: NSKeyValueObservation?
    private var didReachReadyToPlay = false

    private var top: NSLayoutConstraint!
    private var leading: NSLayoutConstraint!
    private var trailing: NSLayoutConstraint!
    private var bottom: NSLayoutConstraint!

    private var maxZoomScale: CGFloat = 1.0
    private var intrinsicSize: CGSize = CGSize(width: 16, height: 9)

    private let url: URL
    private let muted: Bool
    private let posterItem: ImageItem?

    init(
        index: Int,
        imageItem: ImageItem,
        imageLoader: ImageLoader
    ) {
        self.index = index
        self.imageItem = imageItem
        self.imageLoader = imageLoader

        switch imageItem {
        case .video(let url, let poster, let muted):
            self.url = url
            self.muted = muted
            self.posterItem = poster
        default:
            fatalError("VideoViewerController initialized with non-video ImageItem")
        }

        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        playerItemStatusObservation?.invalidate()
        playerItemErrorObservation?.invalidate()
        NotificationCenter.default.removeObserver(self)
        player?.pause()
        playerViewController.player = nil
    }

    override func loadView() {
        let view = UIView()
        view.backgroundColor = .clear
        self.view = view

        scrollView = UIScrollView()
        scrollView.delegate = self
        scrollView.showsVerticalScrollIndicator = false
        scrollView.contentInsetAdjustmentBehavior = .never

        view.addSubview(scrollView)
        scrollView.bindFrameToSuperview()
        scrollView.backgroundColor = .clear

        containerView.translatesAutoresizingMaskIntoConstraints = false
        containerView.backgroundColor = .black
        scrollView.addSubview(containerView)

        top = containerView.topAnchor.constraint(equalTo: scrollView.topAnchor)
        leading = containerView.leadingAnchor.constraint(equalTo: scrollView.leadingAnchor)
        trailing = scrollView.trailingAnchor.constraint(equalTo: containerView.trailingAnchor)
        bottom = scrollView.bottomAnchor.constraint(equalTo: containerView.bottomAnchor)

        top.isActive = true
        leading.isActive = true
        trailing.isActive = true
        bottom.isActive = true
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        NSLog("[Galeria] VideoViewerController viewDidLoad index=\(index)")

        // Child view-controller containment is set up here rather than in
        // loadView so the parent's view hierarchy is fully realised first.
        addChild(playerViewController)
        playerViewController.view.translatesAutoresizingMaskIntoConstraints = true
        playerViewController.view.frame = containerView.bounds
        playerViewController.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        playerViewController.videoGravity = .resizeAspect
        playerViewController.showsPlaybackControls = true
        playerViewController.allowsPictureInPicturePlayback = false
        playerViewController.view.backgroundColor = .black
        containerView.addSubview(playerViewController.view)
        playerViewController.didMove(toParent: self)

        posterImageView.contentMode = .scaleAspectFit
        posterImageView.frame = containerView.bounds
        posterImageView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        posterImageView.isUserInteractionEnabled = false
        containerView.addSubview(posterImageView)

        loadPoster()
        preparePlayer()
        addGestureRecognizers()

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleAudioInterruption(_:)),
            name: AVAudioSession.interruptionNotification,
            object: AVAudioSession.sharedInstance()
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleWillResignActive),
            name: UIApplication.willResignActiveNotification,
            object: nil
        )
    }

    @objc private func handleWillResignActive() {
        player?.pause()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        // Page-change autoplay is wired in ImageViewerRootView. Initial open
        // also routes through that path on the first didFinishAnimating —
        // but in case the controller is being shown without that callback
        // (e.g. setViewControllers initial), kick off playback here too.
        play()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        // Keep poster visible for the dismiss transition.
        posterImageView.alpha = 1
        pause()
    }

    override func viewWillLayoutSubviews() {
        super.viewWillLayoutSubviews()
        layout()
        playerViewController.view.frame = containerView.bounds
    }

    private func loadPoster() {
        let initial = initialPlaceholder
        switch posterItem {
        case .image(let img):
            posterImageView.image = img ?? initial
        case .url(let url, let placeholder):
            let effectivePlaceholder = placeholder ?? initial
            posterImageView.image = effectivePlaceholder
            imageLoader.loadImage(url, placeholder: effectivePlaceholder, imageView: posterImageView) { [weak self] image in
                guard let self = self else { return }
                DispatchQueue.main.async {
                    if let image = image {
                        self.intrinsicSize = image.size
                        self.layout()
                    }
                }
            }
        case .video, .none:
            posterImageView.image = initial
        }
        if let initial = initial, intrinsicSize == CGSize(width: 16, height: 9) {
            intrinsicSize = initial.size
        }
    }

    private func preparePlayer() {
        NSLog("[Galeria] VideoViewerController.preparePlayer url=\(url.absoluteString) muted=\(muted)")
        let item = AVPlayerItem(url: url)
        let p = AVPlayer(playerItem: item)
        p.isMuted = muted
        p.automaticallyWaitsToMinimizeStalling = true
        player = p
        playerViewController.player = p

        playerItemStatusObservation = item.observe(\.status, options: [.new]) { [weak self] item, _ in
            guard let self = self else { return }
            DispatchQueue.main.async {
                switch item.status {
                case .readyToPlay:
                    NSLog("[Galeria] VideoViewerController player ready (index=\(self.index))")
                    self.handleReadyToPlay()
                case .failed:
                    let message = item.error?.localizedDescription ?? "Unknown playback error"
                    NSLog("[Galeria] VideoViewerController player failed (index=\(self.index)): \(message)")
                    self.onVideoError?(self.index, message)
                default:
                    break
                }
            }
        }
    }

    private func handleReadyToPlay() {
        guard !didReachReadyToPlay else { return }
        didReachReadyToPlay = true
        if let track = player?.currentItem?.asset.tracks(withMediaType: .video).first {
            let size = track.naturalSize.applying(track.preferredTransform)
            let resolved = CGSize(width: abs(size.width), height: abs(size.height))
            if resolved.width > 0 && resolved.height > 0 {
                intrinsicSize = resolved
                layout()
            }
        }
        UIView.animate(withDuration: 0.12, delay: 0.05, options: [.curveEaseOut]) { [weak self] in
            self?.posterImageView.alpha = 0
        }
    }

    @objc private func handleAudioInterruption(_ notification: Notification) {
        guard let info = notification.userInfo,
              let typeValue = info[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: typeValue) else { return }
        if type == .began {
            player?.pause()
        }
    }

    func play() {
        player?.play()
    }

    func pause() {
        player?.pause()
    }

    func tearDown() {
        pause()
        playerItemStatusObservation?.invalidate()
        playerItemStatusObservation = nil
        playerViewController.player = nil
        player = nil
    }

    private func layout() {
        updateConstraintsForSize(view.bounds.size)
        updateMinMaxZoomScaleForSize(view.bounds.size)
    }

    private func addGestureRecognizers() {
        let pinchRecognizer = UITapGestureRecognizer(
            target: self,
            action: #selector(didPinch(_:))
        )
        pinchRecognizer.numberOfTapsRequired = 1
        pinchRecognizer.numberOfTouchesRequired = 2
        scrollView.addGestureRecognizer(pinchRecognizer)

        let doubleTapRecognizer = UITapGestureRecognizer(
            target: self,
            action: #selector(didDoubleTap(_:))
        )
        doubleTapRecognizer.numberOfTapsRequired = 2
        doubleTapRecognizer.numberOfTouchesRequired = 1
        scrollView.addGestureRecognizer(doubleTapRecognizer)
    }

    @objc
    private func didPinch(_ recognizer: UITapGestureRecognizer) {
        var newZoomScale = scrollView.zoomScale / 1.5
        newZoomScale = max(newZoomScale, scrollView.minimumZoomScale)
        scrollView.setZoomScale(newZoomScale, animated: true)
    }

    @objc
    private func didDoubleTap(_ recognizer: UITapGestureRecognizer) {
        let pointInView = recognizer.location(in: containerView)
        zoomInOrOut(at: pointInView)
    }
}

extension VideoViewerController {

    override func viewSafeAreaInsetsDidChange() {
        super.viewSafeAreaInsetsDidChange()
        layout()
    }

    func updateMinMaxZoomScaleForSize(_ size: CGSize) {
        guard intrinsicSize.width > 0, intrinsicSize.height > 0 else { return }

        let safeAreaInsets = view.safeAreaInsets
        let availableWidth = size.width - safeAreaInsets.left - safeAreaInsets.right
        let availableHeight = size.height - safeAreaInsets.top - safeAreaInsets.bottom

        let minScale = min(
            availableWidth / intrinsicSize.width,
            availableHeight / intrinsicSize.height
        )

        let maxScale = max(
            (availableWidth + 1.0) / intrinsicSize.width,
            (availableHeight + 1.0) / intrinsicSize.height
        )

        scrollView.minimumZoomScale = minScale
        scrollView.zoomScale = minScale
        maxZoomScale = maxScale

        scrollView.maximumZoomScale = maxZoomScale * 1.1
    }

    func zoomInOrOut(at point: CGPoint) {
        let newZoomScale = scrollView.zoomScale == scrollView.minimumZoomScale
            ? maxZoomScale : scrollView.minimumZoomScale
        let size = scrollView.bounds.size
        let w = size.width / newZoomScale
        let h = size.height / newZoomScale
        let x = point.x - (w * 0.5)
        let y = point.y - (h * 0.5)
        let rect = CGRect(x: x, y: y, width: w, height: h)
        scrollView.zoom(to: rect, animated: true)
    }

    func updateConstraintsForSize(_ size: CGSize) {
        guard intrinsicSize.width > 0, intrinsicSize.height > 0 else { return }

        let safeAreaInsets = view.safeAreaInsets
        let availableWidth = size.width - safeAreaInsets.left - safeAreaInsets.right
        let availableHeight = size.height - safeAreaInsets.top - safeAreaInsets.bottom

        let scaledWidth = intrinsicSize.width * scrollView.zoomScale
        let scaledHeight = intrinsicSize.height * scrollView.zoomScale

        let verticalPadding = max(0, (availableHeight - scaledHeight) / 2)
        top.constant = verticalPadding + safeAreaInsets.top
        bottom.constant = verticalPadding + safeAreaInsets.bottom

        let horizontalPadding = max(0, (availableWidth - scaledWidth) / 2)
        leading.constant = horizontalPadding + safeAreaInsets.left
        trailing.constant = horizontalPadding + safeAreaInsets.right
        view.layoutIfNeeded()
    }
}

extension VideoViewerController: UIScrollViewDelegate {

    func viewForZooming(in scrollView: UIScrollView) -> UIView? {
        return containerView
    }

    func scrollViewDidZoom(_ scrollView: UIScrollView) {
        updateConstraintsForSize(view.bounds.size)
        playerViewController.view.frame = containerView.bounds
    }
}
