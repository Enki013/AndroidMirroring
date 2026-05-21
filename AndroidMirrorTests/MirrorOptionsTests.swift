import XCTest
@testable import Android_Mirror

/// Tests for MirrorOptions server argument generation.
/// Covers test plan items: 3.4, 3.6, 3.7, 3.8
final class MirrorOptionsTests: XCTestCase {

    func testScidHexFormat() {
        let options = MirrorOptions()
        let args = options.serverArguments(scid: 1)
        let scidArg = args.first { $0.hasPrefix("scid=") }
        XCTAssertNotNil(scidArg)
        let scidValue = scidArg!.replacingOccurrences(of: "scid=", with: "")
        XCTAssertEqual(scidValue.count, 8, "SCID must be 8 hex digits")
        XCTAssertEqual(scidValue, "00000001")
    }

    func testScidHexFormat_largeValue() {
        let args = MirrorOptions().serverArguments(scid: 0x1A2B3C4D)
        let val = args.first { $0.hasPrefix("scid=") }!.replacingOccurrences(of: "scid=", with: "")
        XCTAssertEqual(val, "1a2b3c4d")
    }

    func testBalancedArgs() {
        let args = MirrorOptions(preset: .balanced).serverArguments(scid: 1)
        XCTAssertTrue(args.contains("max_size=1920"))
        XCTAssertTrue(args.contains("max_fps=60"))
        XCTAssertTrue(args.contains("video_codec=h264"))
    }

    func testPerformanceArgs() {
        let args = MirrorOptions(preset: .performance).serverArguments(scid: 1)
        XCTAssertTrue(args.contains("max_size=1024"))
    }

    func testQualityArgs() {
        let args = MirrorOptions(preset: .quality).serverArguments(scid: 1)
        XCTAssertTrue(args.contains("video_bit_rate=16000000"))
        XCTAssertTrue(args.contains("video_codec=h264"))
    }

    func testAudioEnabled() {
        let args = MirrorOptions(audioEnabled: true).serverArguments(scid: 1)
        XCTAssertTrue(args.contains("audio=true"))
        XCTAssertTrue(args.contains("audio_codec=raw"))
        XCTAssertTrue(args.contains("audio_source=output"))
        XCTAssertFalse(args.contains("audio=false"))
    }

    func testAudioDisabled() {
        let args = MirrorOptions(audioEnabled: false).serverArguments(scid: 1)
        XCTAssertTrue(args.contains("audio=false"))
        XCTAssertFalse(args.contains("audio_codec=raw"))
    }

    func testTurnScreenOff() {
        let args = MirrorOptions(turnScreenOff: true).serverArguments(scid: 1)
        XCTAssertTrue(args.contains("power_off_on_close=true"))
    }

    func testStayAwake() {
        let args = MirrorOptions(stayAwake: true).serverArguments(scid: 1)
        XCTAssertTrue(args.contains("stay_awake=true"))
    }

    func testCommonArgs() {
        let args = MirrorOptions().serverArguments(scid: 1)
        XCTAssertTrue(args.contains("tunnel_forward=true"))
        XCTAssertTrue(args.contains("control=true"))
        XCTAssertTrue(args.contains("raw_stream=true"))
    }

    // MARK: - Camera Source

    func testCameraSourceArgs() {
        let args = MirrorOptions(videoSource: .camera).serverArguments(scid: 1)
        XCTAssertTrue(args.contains("video_source=camera"))
    }

    func testCameraFacingFront() {
        let args = MirrorOptions(videoSource: .camera, cameraFacing: .front).serverArguments(scid: 1)
        XCTAssertTrue(args.contains("camera_facing=front"))
    }

    func testCameraFacingBack() {
        let args = MirrorOptions(videoSource: .camera, cameraFacing: .back).serverArguments(scid: 1)
        XCTAssertTrue(args.contains("camera_facing=back"))
    }

    func testCameraFps() {
        let args = MirrorOptions(videoSource: .camera, cameraFps: 60).serverArguments(scid: 1)
        XCTAssertTrue(args.contains("camera_fps=60"))
    }

    func testCameraDisablesControl() {
        let opts = MirrorOptions(videoSource: .camera)
        let args = opts.serverArguments(scid: 1)
        XCTAssertTrue(args.contains("control=false"), "Camera mode must disable control")
        XCTAssertFalse(opts.controlEnabled)
    }

    func testCameraAudioSourceMic() {
        let args = MirrorOptions(audioEnabled: true, videoSource: .camera).serverArguments(scid: 1)
        XCTAssertTrue(args.contains("audio_source=mic"), "Camera mode should use microphone")
        XCTAssertFalse(args.contains("audio_source=output"))
    }

    func testDisplaySourceDefault() {
        let args = MirrorOptions(videoSource: .display).serverArguments(scid: 1)
        XCTAssertFalse(args.contains("video_source=camera"), "Display mode should not send camera source")
        XCTAssertFalse(args.contains("camera_facing"))
        XCTAssertTrue(args.contains("control=true"))
    }

    func testDisplayControlEnabled() {
        let opts = MirrorOptions(videoSource: .display)
        XCTAssertTrue(opts.controlEnabled)
    }
}
