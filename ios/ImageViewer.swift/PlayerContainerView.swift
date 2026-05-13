import AVFoundation
import UIKit

/// A `UIView` whose backing layer is an `AVPlayerLayer`.
///
/// Using a layer-backed view (vs. adding `AVPlayerLayer` as a sublayer of a
/// regular `UIView` and manually setting its frame) guarantees the player
/// always matches the view's bounds — Auto Layout updates `bounds`, the
/// layer follows automatically, and we never get stuck with a 0-sized
/// player frame from a stale `viewWillLayoutSubviews` pass.
final class PlayerContainerView: UIView {

    override class var layerClass: AnyClass {
        return AVPlayerLayer.self
    }

    var playerLayer: AVPlayerLayer {
        // swiftlint:disable:next force_cast
        return layer as! AVPlayerLayer
    }

    var player: AVPlayer? {
        get { playerLayer.player }
        set { playerLayer.player = newValue }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        playerLayer.videoGravity = .resizeAspect
        backgroundColor = .black
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
