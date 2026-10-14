#if os(iOS)
import SwiftUI
import UIKit

/// Full-screen look at a body image: pinch or double-tap to zoom, drag to
/// pan, pull down (or ✕) to close, share (which includes Save Image).
struct NoteImageViewer: View {
    let data: Data
    /// How to close it. The text editor presents this from UIKit, where
    /// SwiftUI's `dismiss` does nothing — which is why ✕ didn't close it.
    var onClose: (() -> Void)? = nil
    @Environment(\.dismiss) private var dismiss

    private func close() {
        if let onClose { onClose() } else { dismiss() }
    }

    var body: some View {
        let image = UIImage(data: data)
        ZStack(alignment: .top) {
            Color.black.ignoresSafeArea()
            if let image {
                ZoomableImage(image: image, onPullDown: close).ignoresSafeArea()
            }
            HStack {
                if let image {
                    ShareLink(item: Image(uiImage: image),
                              preview: SharePreview(L("Image", "图片"), image: Image(uiImage: image))) {
                        Image(systemName: "square.and.arrow.up").frame(width: 44, height: 44)
                    }
                }
                Spacer()
                Button(action: close) {
                    Image(systemName: "xmark")
                        .frame(width: 44, height: 44)
                        .background(Circle().fill(.black.opacity(0.35)).frame(width: 34, height: 34))
                        .contentShape(Rectangle())
                }
                    .accessibilityLabel(L("Close", "关闭"))
            }
            .font(.system(size: 17, weight: .semibold))
            .foregroundStyle(.white)
            .buttonStyle(.plain)
            .padding(.horizontal, 8)
        }
        .preferredColorScheme(.dark)
        .statusBarHidden()
    }
}

/// UIScrollView-backed zoom: the native pinch, pan, bounce and
/// double-tap feel, which SwiftUI gestures only approximate.
private struct ZoomableImage: UIViewRepresentable {
    let image: UIImage
    var onPullDown: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onPullDown: onPullDown) }

    func makeUIView(context: Context) -> CenteringScrollView {
        let scroll = CenteringScrollView()
        scroll.backgroundColor = .clear
        scroll.minimumZoomScale = 1
        scroll.maximumZoomScale = 5
        scroll.showsVerticalScrollIndicator = false
        scroll.showsHorizontalScrollIndicator = false
        scroll.contentInsetAdjustmentBehavior = .never
        scroll.alwaysBounceVertical = true   // so a pull down can close it
        scroll.delegate = context.coordinator
        let iv = UIImageView(image: image)
        iv.contentMode = .scaleAspectFit
        scroll.addSubview(iv)
        scroll.imageView = iv
        context.coordinator.scroll = scroll
        let doubleTap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.doubleTapped(_:)))
        doubleTap.numberOfTapsRequired = 2
        scroll.addGestureRecognizer(doubleTap)
        return scroll
    }

    func updateUIView(_ scroll: CenteringScrollView, context: Context) {}

    final class Coordinator: NSObject, UIScrollViewDelegate {
        weak var scroll: CenteringScrollView?
        let onPullDown: () -> Void

        init(onPullDown: @escaping () -> Void) { self.onPullDown = onPullDown }

        /// Pulled down far enough at normal size → close, like Photos.
        func scrollViewWillEndDragging(_ scrollView: UIScrollView, withVelocity velocity: CGPoint,
                                       targetContentOffset: UnsafeMutablePointer<CGPoint>) {
            guard scrollView.zoomScale <= 1.01 else { return }
            let pulled = -(scrollView.contentOffset.y + scrollView.contentInset.top)
            if pulled > 90 || (pulled > 30 && velocity.y < -1.2) { onPullDown() }
        }

        func viewForZooming(in scrollView: UIScrollView) -> UIView? { (scrollView as? CenteringScrollView)?.imageView }

        @objc func doubleTapped(_ g: UITapGestureRecognizer) {
            guard let scroll, let iv = scroll.imageView else { return }
            if scroll.zoomScale > 1.01 {
                scroll.setZoomScale(1, animated: true)
            } else {
                let p = g.location(in: iv)
                let scale: CGFloat = 2.5
                let size = CGSize(width: scroll.bounds.width / scale, height: scroll.bounds.height / scale)
                scroll.zoom(to: CGRect(x: p.x - size.width / 2, y: p.y - size.height / 2,
                                       width: size.width, height: size.height), animated: true)
            }
        }
    }
}

/// Fits the image to the screen at zoom 1 and keeps it centred while it's
/// smaller than the screen.
private final class CenteringScrollView: UIScrollView {
    weak var imageView: UIImageView?
    private var fittedFor: CGSize = .zero

    override func layoutSubviews() {
        super.layoutSubviews()
        guard let iv = imageView, let image = iv.image, bounds.width > 0 else { return }
        if fittedFor != bounds.size {
            fittedFor = bounds.size
            zoomScale = 1
            let fit = min(bounds.width / image.size.width, bounds.height / image.size.height)
            iv.frame = CGRect(x: 0, y: 0, width: image.size.width * fit, height: image.size.height * fit)
            contentSize = iv.frame.size
        }
        let dx = max(0, (bounds.width - iv.frame.width) / 2)
        let dy = max(0, (bounds.height - iv.frame.height) / 2)
        contentInset = UIEdgeInsets(top: dy, left: dx, bottom: dy, right: dx)
    }
}
#endif
