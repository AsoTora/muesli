import Foundation
import Testing
@testable import MuesliNativeApp

@MainActor
@Suite("DetectedMeetingAutoRecordCoordinator")
struct DetectedMeetingAutoRecordCoordinatorTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func candidate() -> MeetingCandidate {
        MeetingCandidate(
            id: "googleMeet:meet.google.com/pwm-txwq-txy",
            platform: .googleMeet,
            appName: "Firefox",
            url: "meet.google.com/pwm-txwq-txy",
            evidence: [.browserURL, .audioInputProcess],
            startedAt: now,
            meetingTitle: "Weekly sync",
            sourceBundleID: "org.mozilla.firefox",
            sourcePID: 4321,
            suppressionID: "browser:org.mozilla.firefox:session:1800000000"
        )
    }

    @Test("stable candidate invokes exactly one recording start")
    func stableCandidateStartsExactlyOnce() {
        var starts: [MeetingCandidate] = []
        var marked: [MeetingCandidate] = []
        let coordinator = DetectedMeetingAutoRecordCoordinator(
            policy: MeetingAutoRecordPolicy(stabilizationInterval: 3, failedStartCooldown: 30),
            startRecording: { starts.append($0.candidate); return true },
            recordingStarted: { marked.append($0) }
        )
        let meeting = candidate()

        coordinator.observe(candidate: meeting, now: now, enabled: true, isRecording: false, isStarting: false)
        coordinator.observe(candidate: meeting, now: now.addingTimeInterval(3), enabled: true, isRecording: false, isStarting: false)
        coordinator.observe(candidate: meeting, now: now.addingTimeInterval(10), enabled: true, isRecording: false, isStarting: false)

        #expect(starts == [meeting])
        #expect(marked.isEmpty)
        coordinator.recordingDidBecomeActive()
        #expect(marked == [meeting])
    }

    @Test("automatic start request never opens or presents the meeting document")
    func automaticStartDoesNotOpenDocument() {
        var requests: [DetectedMeetingAutoRecordStartRequest] = []
        let coordinator = DetectedMeetingAutoRecordCoordinator(
            policy: MeetingAutoRecordPolicy(stabilizationInterval: 0),
            startRecording: { requests.append($0); return true }
        )

        coordinator.observe(candidate: candidate(), now: now, enabled: true, isRecording: false, isStarting: false)

        #expect(requests.count == 1)
        #expect(requests.first?.openDocument == false)
        #expect(requests.first?.startOrigin == .detectedAutoRecord)
    }

    @Test("failed recording start respects cooldown")
    func failedStartRespectsCooldown() {
        var attempts = 0
        let coordinator = DetectedMeetingAutoRecordCoordinator(
            policy: MeetingAutoRecordPolicy(stabilizationInterval: 0, failedStartCooldown: 30),
            startRecording: { _ in attempts += 1; return false }
        )
        let meeting = candidate()

        coordinator.observe(candidate: meeting, now: now, enabled: true, isRecording: false, isStarting: false)
        coordinator.observe(candidate: meeting, now: now.addingTimeInterval(29), enabled: true, isRecording: false, isStarting: false)
        coordinator.observe(candidate: meeting, now: now.addingTimeInterval(30), enabled: true, isRecording: false, isStarting: false)

        #expect(attempts == 2)
    }

    @Test("unsupported source never starts")
    func unsupportedSourceNeverStarts() {
        var starts = 0
        let coordinator = DetectedMeetingAutoRecordCoordinator(
            policy: MeetingAutoRecordPolicy(stabilizationInterval: 0),
            startRecording: { _ in starts += 1; return true }
        )
        let unsupported = MeetingCandidate(
            id: "slack",
            platform: .slack,
            appName: "Slack",
            url: nil,
            evidence: [.audioInputProcess, .dedicatedApp],
            startedAt: now,
            meetingTitle: nil,
            sourceBundleID: "com.tinyspeck.slackmacgap",
            sourcePID: 123
        )

        coordinator.observe(candidate: unsupported, now: now, enabled: true, isRecording: false, isStarting: false)
        #expect(starts == 0)
    }

    @Test("accepted asynchronous start failure enters retry cooldown")
    func acceptedStartFailureEntersCooldown() {
        var attempts = 0
        let coordinator = DetectedMeetingAutoRecordCoordinator(
            policy: MeetingAutoRecordPolicy(stabilizationInterval: 0, failedStartCooldown: 30),
            startRecording: { _ in attempts += 1; return true }
        )
        let meeting = candidate()

        coordinator.observe(candidate: meeting, now: now, enabled: true, isRecording: false, isStarting: false)
        coordinator.startDidFail(now: now)
        coordinator.observe(candidate: meeting, now: now.addingTimeInterval(29), enabled: true, isRecording: false, isStarting: false)
        coordinator.observe(candidate: meeting, now: now.addingTimeInterval(30), enabled: true, isRecording: false, isStarting: false)

        #expect(attempts == 2)
    }

    @Test("browser URL without live media evidence never starts")
    func browserURLWithoutLiveMediaNeverStarts() {
        var starts = 0
        let coordinator = DetectedMeetingAutoRecordCoordinator(
            policy: MeetingAutoRecordPolicy(stabilizationInterval: 0),
            startRecording: { _ in starts += 1; return true }
        )
        let preJoin = MeetingCandidate(
            id: "googleMeet:meet.google.com/pwm-txwq-txy",
            platform: .googleMeet,
            appName: "Chrome",
            url: "meet.google.com/pwm-txwq-txy",
            evidence: [.browserURL, .foregroundApp],
            startedAt: now,
            meetingTitle: nil,
            sourceBundleID: "com.google.Chrome",
            sourcePID: 123
        )

        coordinator.observe(candidate: preJoin, now: now, enabled: true, isRecording: false, isStarting: false)
        #expect(starts == 0)
    }

    @Test("native Teams requires attributed dedicated-app audio")
    func nativeTeamsRequiresAttributedAudio() {
        var starts = 0
        let coordinator = DetectedMeetingAutoRecordCoordinator(
            policy: MeetingAutoRecordPolicy(stabilizationInterval: 0),
            startRecording: { _ in starts += 1; return true }
        )
        let processOnly = MeetingCandidate(
            id: "app:com.microsoft.teams2",
            platform: .teams,
            appName: "Teams",
            url: nil,
            evidence: [.dedicatedApp, .foregroundApp],
            startedAt: now,
            meetingTitle: nil,
            sourceBundleID: "com.microsoft.teams2",
            sourcePID: 456
        )

        coordinator.observe(candidate: processOnly, now: now, enabled: true, isRecording: false, isStarting: false)
        #expect(starts == 0)
    }

    @Test("successful stop finalization emits completion seam")
    func successfulFinalizationEmitsCompletionSeam() {
        var finalized = 0
        let coordinator = DetectedMeetingAutoRecordCoordinator(
            startRecording: { _ in true },
            recordingFinalized: { finalized += 1 }
        )

        coordinator.recordingDidStop()
        #expect(finalized == 0)
        coordinator.recordingDidFinalize()
        #expect(finalized == 1)
    }
}
