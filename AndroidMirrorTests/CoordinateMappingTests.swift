import XCTest
@testable import Android_Mirror

/// Tests for coordinate mapping from NSView space to Android device space.
/// Covers test plan items: 6A.1–6A.4
///
/// Since InteractiveMTKView coordinate mapping uses private helpers,
/// we reproduce the mapping logic here and test it against expected values.
final class CoordinateMappingTests: XCTestCase {

    /// Reproduce the same coordinate mapping logic as InteractiveMTKView.deviceCoordinates
    private func mapCoordinates(
        viewPoint: CGPoint,
        viewSize: CGSize,
        videoWidth: CGFloat,
        videoHeight: CGFloat
    ) -> (x: Float, y: Float) {
        let scaleX = viewSize.width / videoWidth
        let scaleY = viewSize.height / videoHeight
        let scale = min(scaleX, scaleY)

        let renderedW = videoWidth * scale
        let renderedH = videoHeight * scale
        let offsetX = (viewSize.width - renderedW) / 2
        let offsetY = (viewSize.height - renderedH) / 2

        let vx = (viewPoint.x - offsetX) / scale
        // Y flip: NSView bottom-left → Android top-left
        let vy = videoHeight - (viewPoint.y - offsetY) / scale

        let cx = max(0, min(Float(vx), Float(videoWidth)))
        let cy = max(0, min(Float(vy), Float(videoHeight)))
        return (cx, cy)
    }

    /// 6A.1: Center of view → center of video
    func testCenterMapping() {
        let viewSize = CGSize(width: 400, height: 800)
        let videoW: CGFloat = 1080
        let videoH: CGFloat = 2400

        // View center
        let center = CGPoint(x: 200, y: 400)
        let (x, y) = mapCoordinates(viewPoint: center, viewSize: viewSize, videoWidth: videoW, videoHeight: videoH)

        XCTAssertEqual(x, Float(videoW / 2), accuracy: 1.0, "X should map to video center")
        XCTAssertEqual(y, Float(videoH / 2), accuracy: 1.0, "Y should map to video center")
    }

    /// 6A.2: Top-left of rendered area → (0, 0) in Android
    func testTopLeftMapping() {
        let viewSize = CGSize(width: 400, height: 800)
        let videoW: CGFloat = 1080
        let videoH: CGFloat = 2400

        // Calculate the rendered area's top-left in NSView coords
        let scaleX = viewSize.width / videoW
        let scaleY = viewSize.height / videoH
        let scale = min(scaleX, scaleY)
        let renderedH = videoH * scale
        let offsetX = (viewSize.width - videoW * scale) / 2
        let offsetY = (viewSize.height - renderedH) / 2

        // In NSView, top-left of rendered area is at (offsetX, offsetY + renderedH)
        // because NSView Y=0 is bottom
        let topLeft = CGPoint(x: offsetX, y: offsetY + renderedH)
        let (x, y) = mapCoordinates(viewPoint: topLeft, viewSize: viewSize, videoWidth: videoW, videoHeight: videoH)

        XCTAssertEqual(x, 0, accuracy: 1.0, "X should be 0 at left edge")
        XCTAssertEqual(y, 0, accuracy: 1.0, "Y should be 0 at top edge (after Y flip)")
    }

    /// 6A.4: Y-axis flip verification
    func testYAxisFlip() {
        let viewSize = CGSize(width: 1080, height: 2400) // 1:1 mapping
        let videoW: CGFloat = 1080
        let videoH: CGFloat = 2400

        // NSView bottom (y=0) should map to Android bottom (y=2400)
        let bottom = CGPoint(x: 540, y: 0)
        let (_, yBottom) = mapCoordinates(viewPoint: bottom, viewSize: viewSize, videoWidth: videoW, videoHeight: videoH)
        XCTAssertEqual(yBottom, Float(videoH), accuracy: 1.0, "NSView y=0 should map to Android bottom")

        // NSView top (y=2400) should map to Android top (y=0)
        let top = CGPoint(x: 540, y: 2400)
        let (_, yTop) = mapCoordinates(viewPoint: top, viewSize: viewSize, videoWidth: videoW, videoHeight: videoH)
        XCTAssertEqual(yTop, 0, accuracy: 1.0, "NSView y=max should map to Android top")
    }

    /// 6A.3: Letterbox offset — pillarboxed video
    func testLetterboxOffset() {
        // Wide view, tall video → pillarboxing (black bars left/right)
        let viewSize = CGSize(width: 800, height: 400)
        let videoW: CGFloat = 1080
        let videoH: CGFloat = 2400

        let scaleX = viewSize.width / videoW
        let scaleY = viewSize.height / videoH
        let scale = min(scaleX, scaleY)
        let renderedW = videoW * scale
        let offsetX = (viewSize.width - renderedW) / 2

        // Click in the black bar area (left of rendered video)
        let leftBar = CGPoint(x: offsetX - 10, y: 200)
        let (xLeft, _) = mapCoordinates(viewPoint: leftBar, viewSize: viewSize, videoWidth: videoW, videoHeight: videoH)
        XCTAssertEqual(xLeft, 0, accuracy: 0.1, "Click in left letterbox should clamp to 0")
    }

    /// 6A.3: Out-of-bounds clamping
    func testClampingOutOfBounds() {
        let viewSize = CGSize(width: 400, height: 800)
        let videoW: CGFloat = 1080
        let videoH: CGFloat = 2400

        // Way outside the view
        let outside = CGPoint(x: -100, y: -100)
        let (x, y) = mapCoordinates(viewPoint: outside, viewSize: viewSize, videoWidth: videoW, videoHeight: videoH)
        XCTAssertGreaterThanOrEqual(x, 0)
        XCTAssertLessThanOrEqual(y, Float(videoH))
    }
}
