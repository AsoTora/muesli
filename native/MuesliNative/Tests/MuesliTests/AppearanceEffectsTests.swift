import Testing
import AppKit
@testable import MuesliNativeApp

@Suite("SoundController")
@MainActor
struct SoundControllerTests {

    @Test("playDictationStart with enabled=false does not throw")
    func playStartDisabled() {
        // NSSound.play() is a no-op in the test runner (no audio device required)
        SoundController.playDictationStart(enabled: false)
    }

    @Test("playDictationInsert with enabled=false does not throw")
    func playInsertDisabled() {
        SoundController.playDictationInsert(enabled: false)
    }

    @Test("playDictationStart with enabled=true does not throw")
    func playStartEnabled() {
        SoundController.playDictationStart(enabled: true)
    }

    @Test("playDictationInsert with enabled=true does not throw")
    func playInsertEnabled() {
        SoundController.playDictationInsert(enabled: true)
    }
}

@Suite("MenuBarIconRenderer")
struct MenuBarIconRendererTests {

    @Test("recorder status resolves disabled and monitoring states")
    func recorderStatusIdleStates() {
        #expect(MenuBarRecorderStatus.resolve(calendarAutoRecordEnabled: false, detectedAutoRecordEnabled: false, isRecording: false, isPaused: false) == .disabled)
        #expect(MenuBarRecorderStatus.resolve(calendarAutoRecordEnabled: true, detectedAutoRecordEnabled: false, isRecording: false, isPaused: false) == .monitoring)
        #expect(MenuBarRecorderStatus.resolve(calendarAutoRecordEnabled: false, detectedAutoRecordEnabled: true, isRecording: false, isPaused: false) == .monitoring)
        #expect(MenuBarRecorderStatus.resolve(calendarAutoRecordEnabled: true, detectedAutoRecordEnabled: true, isRecording: false, isPaused: false) == .monitoring)
    }

    @Test("active recording takes priority over automation setting")
    func recorderStatusActiveStates() {
        #expect(MenuBarRecorderStatus.resolve(calendarAutoRecordEnabled: false, detectedAutoRecordEnabled: false, isRecording: true, isPaused: false) == .recording)
        #expect(MenuBarRecorderStatus.resolve(calendarAutoRecordEnabled: true, detectedAutoRecordEnabled: true, isRecording: true, isPaused: true) == .paused)
    }

    @Test("recorder status has concise menu labels")
    func recorderStatusLabels() {
        #expect(MenuBarRecorderStatus.disabled.label == "Off")
        #expect(MenuBarRecorderStatus.monitoring.label == "Monitoring")
        #expect(MenuBarRecorderStatus.recording.label == "Recording")
        #expect(MenuBarRecorderStatus.paused.label == "Paused")
    }

    @Test("recorder status maps to distinct badge colors")
    func recorderStatusBadgeColors() {
        #expect(MenuBarRecorderStatus.disabled.badge == .gray)
        #expect(MenuBarRecorderStatus.monitoring.badge == .green)
        #expect(MenuBarRecorderStatus.recording.badge == .red)
        #expect(MenuBarRecorderStatus.paused.badge == .orange)
    }

    @Test("menu bar title always includes the status dot")
    func recorderStatusAttributedTitle() {
        let emptyTitle = MenuBarRecorderStatus.disabled.attributedMenuBarTitle(trailingText: "")
        let nextMeetingTitle = MenuBarRecorderStatus.monitoring.attributedMenuBarTitle(trailingText: " Next meeting")
        let countdownTitle = MenuBarRecorderStatus.recording.attributedMenuBarTitle(trailingText: " 00:42")
        let color = nextMeetingTitle.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor

        #expect(emptyTitle.string == "●")
        #expect(nextMeetingTitle.string == "● Next meeting")
        #expect(countdownTitle.string == "● 00:42")
        #expect(color == NSColor.systemGreen)
    }

    @Test("make(choice:) returns a non-nil image for SF Symbol")
    func makeReturnsImage() {
        let image = MenuBarIconRenderer.make(choice: "mic.fill")
        #expect(image != nil)
    }

    @Test("make(choice:) returns a template image for menu bar adaptation")
    func makeIsTemplate() {
        let image = MenuBarIconRenderer.make(choice: "mic.fill")
        #expect(image?.isTemplate == true)
    }

    @Test("make(choice:) returns a non-zero size image")
    func makeHasSize() {
        let image = MenuBarIconRenderer.make(choice: "mic.fill")
        #expect((image?.size.width ?? 0) > 0)
        #expect((image?.size.height ?? 0) > 0)
    }

}
