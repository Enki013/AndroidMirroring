import CoreImage
import MetalKit
import SwiftUI

struct MetalVideoView: NSViewRepresentable {
    @ObservedObject var renderer: ScrcpyMetalRenderer

    func makeNSView(context: Context) -> InteractiveMTKView {
        guard let device = MTLCreateSystemDefaultDevice() else {
            return InteractiveMTKView()
        }
        let view = InteractiveMTKView()
        view.device = device
        view.framebufferOnly = false
        view.clearColor = MTLClearColor(red: 0.1, green: 0.1, blue: 0.12, alpha: 1)

        // Use continuous rendering at display refresh rate for smooth video
        view.isPaused = false
        view.enableSetNeedsDisplay = false
        view.preferredFramesPerSecond = 60

        context.coordinator.configure(view: view, device: device, renderer: renderer)
        return view
    }

    func updateNSView(_ nsView: InteractiveMTKView, context: Context) {
        context.coordinator.renderer = renderer
        nsView.controlChannel = renderer.controlChannel
        Task { @MainActor in
            renderer.metalView = nsView
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    final class Coordinator: NSObject {
        var renderer: ScrcpyMetalRenderer?
        private var ciContext: CIContext?
        private var commandQueue: MTLCommandQueue?

        func configure(view: InteractiveMTKView, device: MTLDevice, renderer: ScrcpyMetalRenderer) {
            self.renderer = renderer
            self.commandQueue = device.makeCommandQueue()
            self.ciContext = CIContext(mtlDevice: device)
            view.delegate = self
            view.controlChannel = renderer.controlChannel
            Task { @MainActor in
                renderer.metalView = view
            }
        }
    }
}

// MARK: - Interactive MTKView (handles mouse/touch events)

/// Custom MTKView subclass that captures mouse events and forwards them
/// to the scrcpy control channel as touch events on the Android device.
class InteractiveMTKView: MTKView {
    weak var controlChannel: ScrcpyControlChannel?

    override var acceptsFirstResponder: Bool { true }

    /// Convert an NSView point to scrcpy device coordinates.
    /// Takes into account the aspect-ratio-fit scaling and centering done during rendering.
    private func deviceCoordinates(for event: NSEvent) -> (x: Float, y: Float)? {
        guard let controlChannel,
              controlChannel.videoWidth > 0,
              controlChannel.videoHeight > 0 else { return nil }

        let point = convert(event.locationInWindow, from: nil)
        let viewW = bounds.width
        let viewH = bounds.height

        let videoW = CGFloat(controlChannel.videoWidth)
        let videoH = CGFloat(controlChannel.videoHeight)

        // Calculate the same scaling/centering as the renderer
        let scaleX = viewW / videoW
        let scaleY = viewH / videoH
        let scale = min(scaleX, scaleY)

        let renderedW = videoW * scale
        let renderedH = videoH * scale
        let offsetX = (viewW - renderedW) / 2
        let offsetY = (viewH - renderedH) / 2

        // Map view coordinates to video coordinates
        let vx = (point.x - offsetX) / scale
        // Flip Y: NSView has origin at bottom-left, Android has origin at top-left
        let vy = videoH - (point.y - offsetY) / scale

        // Clamp to valid range
        let cx = max(0, min(Float(vx), Float(videoW)))
        let cy = max(0, min(Float(vy), Float(videoH)))

        return (cx, cy)
    }

    override func mouseDown(with event: NSEvent) {
        guard let (x, y) = deviceCoordinates(for: event) else { return }
        controlChannel?.sendTouch(action: .down, x: x, y: y)
    }

    override func mouseDragged(with event: NSEvent) {
        guard let (x, y) = deviceCoordinates(for: event) else { return }
        controlChannel?.sendTouch(action: .move, x: x, y: y)
    }

    override func mouseUp(with event: NSEvent) {
        guard let (x, y) = deviceCoordinates(for: event) else { return }
        controlChannel?.sendTouch(action: .up, x: x, y: y)
    }

    override func scrollWheel(with event: NSEvent) {
        guard let (x, y) = deviceCoordinates(for: event) else { return }

        // Map scroll deltas. NSEvent scroll values are in points;
        // scrcpy expects values in the range approx [-16, 16].
        let vScroll = Float(-event.scrollingDeltaY) * 0.1
        let hScroll = Float(event.scrollingDeltaX) * 0.1

        if abs(vScroll) > 0.01 || abs(hScroll) > 0.01 {
            controlChannel?.sendScroll(x: x, y: y, hScroll: hScroll, vScroll: vScroll)
        }
    }

    override func rightMouseDown(with event: NSEvent) {
        // Right-click = Back button
        controlChannel?.sendBackOrScreenOn(action: .down)
    }

    override func rightMouseUp(with event: NSEvent) {
        controlChannel?.sendBackOrScreenOn(action: .up)
    }
}

// MARK: - MTKViewDelegate

extension MetalVideoView.Coordinator: MTKViewDelegate {
    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

    func draw(in view: MTKView) {
        guard let drawable = view.currentDrawable,
              let commandQueue,
              let ciContext else { return }

        let commandBuffer = commandQueue.makeCommandBuffer()

        if let pixelBuffer = renderer?.latestPixelBuffer {
            let image = CIImage(cvPixelBuffer: pixelBuffer)
            let drawableSize = view.drawableSize
            let bounds = CGRect(origin: .zero, size: drawableSize)

            // Scale the image to fit the drawable
            let imageExtent = image.extent
            let scaleX = drawableSize.width / imageExtent.width
            let scaleY = drawableSize.height / imageExtent.height
            let scale = min(scaleX, scaleY)

            let scaledImage = image
                .transformed(by: CGAffineTransform(scaleX: scale, y: scale))

            // Center the image
            let scaledExtent = scaledImage.extent
            let offsetX = (drawableSize.width - scaledExtent.width) / 2 - scaledExtent.origin.x
            let offsetY = (drawableSize.height - scaledExtent.height) / 2 - scaledExtent.origin.y
            let centeredImage = scaledImage
                .transformed(by: CGAffineTransform(translationX: offsetX, y: offsetY))

            ciContext.render(
                centeredImage,
                to: drawable.texture,
                commandBuffer: commandBuffer,
                bounds: bounds,
                colorSpace: CGColorSpaceCreateDeviceRGB()
            )
        } else {
            // Clear to dark background when no frame is available
            guard let pass = view.currentRenderPassDescriptor,
                  let encoder = commandBuffer?.makeRenderCommandEncoder(descriptor: pass) else {
                commandBuffer?.commit()
                return
            }
            encoder.endEncoding()
        }

        commandBuffer?.present(drawable)
        commandBuffer?.commit()
    }
}
