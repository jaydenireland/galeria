import UIKit

public enum ImageItem {
    case image(UIImage?)
    case url(URL, placeholder: UIImage?)
    indirect case video(URL, poster: ImageItem?, muted: Bool)
}
