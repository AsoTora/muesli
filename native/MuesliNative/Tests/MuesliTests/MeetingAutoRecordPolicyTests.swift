import Foundation
import Testing
@testable import MuesliNativeApp

@Suite("MeetingAutoRecordPolicy")
struct MeetingAutoRecordPolicyTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func candidate(id: String = "room", suppressionID: String = "session") -> MeetingCandidate {
        MeetingCandidate(
            id: id,
            platform: .googleMeet,
            appName: "Firefox",
            url: "meet.google.com/pwm-txwq-txy",
            evidence: [.browserURL, .audioInputProcess],
            startedAt: now,
            meetingTitle: "Weekly sync",
            sourceBundleID: "org.mozilla.firefox",
            sourcePID: 4321,
            suppressionID: suppressionID
        )
    }

    @Test("stable candidate starts once after debounce")
    func stableCandidateStartsOnce() {
        var policy = MeetingAutoRecordPolicy(stabilizationInterval: 3, failedStartCooldown: 30)
        let meeting = candidate()

        #expect(policy.evaluate(candidate: meeting, now: now, enabled: true, isRecording: false, isStarting: false) == .none)
        #expect(policy.evaluate(candidate: meeting, now: now.addingTimeInterval(2.9), enabled: true, isRecording: false, isStarting: false) == .none)
        #expect(policy.evaluate(candidate: meeting, now: now.addingTimeInterval(3), enabled: true, isRecording: false, isStarting: false) == .start(meeting))
        policy.recordingDidStart(meeting)
        policy.recordingDidStop()
        #expect(policy.evaluate(candidate: meeting, now: now.addingTimeInterval(20), enabled: true, isRecording: false, isStarting: false) == .none)
    }

    @Test("failed start is rate limited then retries")
    func failedStartIsRateLimited() {
        var policy = MeetingAutoRecordPolicy(stabilizationInterval: 0, failedStartCooldown: 30)
        let meeting = candidate()

        #expect(policy.evaluate(candidate: meeting, now: now, enabled: true, isRecording: false, isStarting: false) == .start(meeting))
        policy.startDidFail(meeting, now: now)
        #expect(policy.evaluate(candidate: meeting, now: now.addingTimeInterval(29), enabled: true, isRecording: false, isStarting: false) == .none)
        #expect(policy.evaluate(candidate: meeting, now: now.addingTimeInterval(30), enabled: true, isRecording: false, isStarting: false) == .start(meeting))
    }

    @Test("candidate disappearance resets pending debounce")
    func disappearanceResetsPendingDebounce() {
        var policy = MeetingAutoRecordPolicy(stabilizationInterval: 3, failedStartCooldown: 30)
        let meeting = candidate()
        _ = policy.evaluate(candidate: meeting, now: now, enabled: true, isRecording: false, isStarting: false)
        _ = policy.evaluate(candidate: nil, now: now.addingTimeInterval(2), enabled: true, isRecording: false, isStarting: false)
        #expect(policy.evaluate(candidate: meeting, now: now.addingTimeInterval(3), enabled: true, isRecording: false, isStarting: false) == .none)
    }
}
