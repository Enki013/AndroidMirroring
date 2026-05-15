import CoreImage
import MetalKit
import SwiftUI

struct MetalVideoView: NSViewRepresentable {
    @ObservedObject var renderer: ScrcpyMetalRenderer

    func makeNSView(context: Context) -> MTKView {
        let view = MTKView()
        view.device = MTLCreateSystemDefaultDevice()
        view.enableSetNeedsDisplay = true
        view.isPaused = true
        view.framebufferOnly = false
        view.clearColor = MTLClearColor(red: 0.1, green: 0.1, blue: 0.12, alpha: 1)
        context.coordinator.configure(view: view, renderer: renderer)
        return view
    }

    func updateNSView(_ nsView: MTKView, context: Context) {
        context.coordinator.renderer = renderer
        context.coordinator.attach(view: nsView, to: renderer)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    final class Coordinator: NSObject {
        var renderer: ScrcpyMetalRenderer?
        private let ciContext = CIContext(options: nil)

        func configure(view: MTKView, renderer: ScrcpyMetalRenderer) {
            self.renderer = renderer
            view.delegate = self
            attach(view: view, to: renderer)
        }

        func attach(view: MTKView, to renderer: ScrcpyMetalRenderer) {
            Task { @MainActor in
                renderer.metalView = view
            }
        }
    }
}

extension MetalVideoView.Coordinator: MTKViewDelegate {
    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

    func draw(in view: MTKView) {
        guard let drawable = view.currentDrawable else { return }

        if let pixelBuffer = renderer?.latestPixelBuffer {
            let image = CIImage(cvPixelBuffer: pixelBuffer)
            let bounds = CGRect(origin: .zero, size: view.drawableSize)
            ciContext.render(image, to: drawable.texture, commandBuffer: nil, bounds: bounds, colorSpace: CGColorSpaceCreateDeviceRGB())
        } else {
            guard let pass = view.currentRenderPassDescriptor,
                  let commandQueue = view.device?.makeCommandQueue(),
                  let buffer = commandQueue.makeCommandBuffer(),
                  let encoder = buffer.makeRenderCommandEncoder(descriptor: pass) else { return }
            pass.colorAttachments[0]?.loadAction = .clear
            pass.colorAttachments[0]?.clearColor = MTLClearColor(red: 0.1, green: 0.1, blue: 0.12, alpha: 1)
            encoder.endEncoding()
            buffer.present(drawable)
            buffer.commit()
        }
    }
}
