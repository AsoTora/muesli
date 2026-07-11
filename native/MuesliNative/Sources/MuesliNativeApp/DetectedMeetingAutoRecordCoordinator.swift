import Foundation

/// Testable seam between stabilized meeting detection and the existing recorder.
@MainActor
final class DetectedMeetingAutoRecordCoordinator {
    static let supportedSourceBundleIDs: Set<String> = [
        "com.google.Chrome",
        "org.mozilla.firefox",
        "com.microsoft.teams2",
        "com.microsoft.teams",
    ]

    private var policy: MeetingAutoRecordPolicy
    private let startRecording: (MeetingCandidate) -> Bool
    private let recordingStarted: (MeetingCandidate) -> Void

    init(
        policy: MeetingAutoRecordPolicy = MeetingAutoRecordPolicy(),
        startRecording: @escaping (MeetingCandidate) -> Bool,
        recordingStarted: @escaping (MeetingCandidate) -> Void = { _ in }
    ) {
        self.policy = policy
        self.startRecording = startRecording
        self.recordingStarted = recordingStarted
    }

    func observe(
        candidate: MeetingCandidate?,
        now: Date = Date(),
        enabled: Bool,
        isRecording: Bool,
        isStarting: Bool
    ) {
        let eligibleCandidate: MeetingCandidate? = candidate.flatMap { candidate in
            guard let bundleID = candidate.sourceBundleID,
                  Self.supportedSourceBundleIDs.contains(bundleID) else { return nil }
            return candidate
        }
        guard case .start(let candidate) = policy.evaluate(
            candidate: eligibleCandidate,
            now: now,
            enabled: enabled,
            isRecording: isRecording,
            isStarting: isStarting
        ) else { return }

        if startRecording(candidate) {
            policy.recordingDidStart(candidate)
            recordingStarted(candidate)
        } else {
            policy.startDidFail(candidate, now: now)
        }
    }

    func recordingDidStop() {
        policy.recordingDidStop()
    }
}
