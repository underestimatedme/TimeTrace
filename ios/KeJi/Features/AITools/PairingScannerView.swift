import AVFoundation
import SwiftUI

/// 扫码绑定：扫描电脑上 `keji cloud login` 打印的二维码。只认 keji://pair 链接，
/// 扫到后交给调用方走和手输授权码一样的「核对 → 确认」流程。
/// 没有相机（模拟器）或没有权限时给出说明，并提示改用 8 位授权码。
struct PairingScannerView: View {
    @Environment(\.theme) private var theme
    @Environment(\.dismiss) private var dismiss
    var onFound: (PairingLink) -> Void

    private enum Phase: Equatable {
        case checking
        case scanning
        case unavailable(String)
    }

    @State private var phase: Phase = .checking
    @State private var hint = "把电脑屏幕上的二维码放进取景框"

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                switch phase {
                case .checking:
                    ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
                case .scanning:
                    QRCameraPreview { scanned in handle(scanned) }
                        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                        .aspectRatio(1, contentMode: .fit)
                        .accessibilityLabel("相机取景框")
                    message(hint)
                    Spacer(minLength: 0)
                case .unavailable(let text):
                    Image(systemName: "camera.fill")
                        .font(.system(size: 34)).foregroundStyle(theme.textMuted)
                        .padding(.top, 40)
                        .accessibilityHidden(true)
                    message(text)
                    Spacer(minLength: 0)
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(theme.bg)
            .navigationTitle("扫码绑定")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }.accessibilityIdentifier("pairing.scanner.close")
                }
            }
        }
        .task { phase = await Self.cameraPhase() }
    }

    private func message(_ text: String) -> some View {
        Text(text)
            .font(Typo.sans(Typo.sm)).foregroundStyle(theme.textSecondary)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            .accessibilityIdentifier("pairing.scanner.message")
    }

    private func handle(_ scanned: String) {
        guard let link = PairingLink.parse(scanned: scanned) else {
            hint = "这不是刻迹的绑定二维码。请扫描电脑上运行 keji cloud login 后显示的二维码。"
            return
        }
        onFound(link)
        dismiss()
    }

    private static func cameraPhase() async -> Phase {
        let fallback = "可以在「绑定新电脑」里手动输入电脑上显示的 8 位授权码。"
        guard AVCaptureDevice.default(for: .video) != nil else {
            return .unavailable("这台设备没有可用的相机。\(fallback)")
        }
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            return .scanning
        case .notDetermined:
            let granted = await AVCaptureDevice.requestAccess(for: .video)
            return granted ? .scanning : .unavailable("没有相机权限。\(fallback)")
        default:
            return .unavailable("没有相机权限，请在系统「设置 → 刻迹」中允许使用相机。\(fallback)")
        }
    }
}

/// AVCaptureSession + AVCaptureMetadataOutput（仅 QR），把读到的字符串回调到主线程。
private struct QRCameraPreview: UIViewRepresentable {
    var onScan: (String) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onScan: onScan) }

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.previewLayer.videoGravity = .resizeAspectFill
        context.coordinator.attach(to: view)
        return view
    }

    func updateUIView(_ uiView: PreviewView, context: Context) {
        context.coordinator.onScan = onScan
    }

    static func dismantleUIView(_ uiView: PreviewView, coordinator: Coordinator) {
        coordinator.stop()
    }

    final class PreviewView: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
    }

    final class Coordinator: NSObject, AVCaptureMetadataOutputObjectsDelegate {
        var onScan: (String) -> Void
        private let session = AVCaptureSession()
        private let queue = DispatchQueue(label: "com.atlaspaces.keji.qr-scanner")
        private var lastValue: String?

        init(onScan: @escaping (String) -> Void) { self.onScan = onScan }

        func attach(to view: PreviewView) {
            view.previewLayer.session = session
            guard let device = AVCaptureDevice.default(for: .video),
                  let input = try? AVCaptureDeviceInput(device: device),
                  session.canAddInput(input) else { return }
            session.addInput(input)
            let output = AVCaptureMetadataOutput()
            guard session.canAddOutput(output) else { return }
            session.addOutput(output)
            output.setMetadataObjectsDelegate(self, queue: .main)
            if output.availableMetadataObjectTypes.contains(.qr) {
                output.metadataObjectTypes = [.qr]
            }
            let session = self.session
            queue.async { session.startRunning() }
        }

        func stop() {
            let session = self.session
            queue.async { if session.isRunning { session.stopRunning() } }
        }

        func metadataOutput(_ output: AVCaptureMetadataOutput, didOutput metadataObjects: [AVMetadataObject],
                            from connection: AVCaptureConnection) {
            guard let value = metadataObjects.compactMap({ ($0 as? AVMetadataMachineReadableCodeObject)?.stringValue }).first,
                  value != lastValue else { return }
            // 同一个码会被连续识别很多帧：只回调一次，换了码再回调。
            lastValue = value
            onScan(value)
        }
    }
}
