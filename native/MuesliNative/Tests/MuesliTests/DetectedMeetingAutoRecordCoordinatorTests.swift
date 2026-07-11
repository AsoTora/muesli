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
            startRecording: { starts.append($0); return true },
            recordingStarted: { marked.append($0) }
        )
        let meeting = candidate()

        coordinator.observe(candidate: meeting, now: now, enabled: true, isRecording: false, isStarting: false)
        coordinator.observe(candidate: meeting, now: now.addingTimeInterval(3), enabled: true, isRecording: false, isStarting: false)
        coordinator.observe(candidate: meeting, now: now.addingTimeInterval(10), enabled: true, isRecording: false, isStarting: false)

        #expect(starts == [meeting])
        #expect(marked == [meeting])
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
}
