import Foundation

struct DetectedMeetingAutoRecordStartRequest: Equatable {
    let candidate: MeetingCandidate
    let title: String
    let autoStopSource: MeetingAutoStopSource
    let startOrigin: MeetingRecordingStartOrigin
    let openDocument: Bool

    init(candidate: MeetingCandidate) {
        self.candidate = candidate
        self.title = candidate.subtitle
        self.autoStopSource = MeetingAutoStopSource(candidate: candidate)
        self.startOrigin = .detectedAutoRecord
        self.openDocument = false
    }
}

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
    private let startRecording: (DetectedMeetingAutoRecordStartRequest) -> Bool
    private let recordingStarted: (MeetingCandidate) -> Void
    private let recordingFinalized: () -> Void
    private var acceptedCandidate: MeetingCandidate?

    init(
        policy: MeetingAutoRecordPolicy = MeetingAutoRecordPolicy(),
        startRecording: @escaping (DetectedMeetingAutoRecordStartRequest) -> Bool,
        recordingStarted: @escaping (MeetingCandidate) -> Void = { _ in },
        recordingFinalized: @escaping () -> Void = {}
    ) {
        self.policy = policy
        self.startRecording = startRecording
        self.recordingStarted = recordingStarted
        self.recordingFinalized = recordingFinalized
    }

    func observe(
        candidate: MeetingCandidate?,
        now: Date = Date(),
        enabled: Bool,
        isRecording: Bool,
        isStarting: Bool
    ) {
        guard acceptedCandidate == nil else { return }
        let eligibleCandidate = candidate.flatMap(Self.attendedCandidate)
        guard case .start(let candidate) = policy.evaluate(
            candidate: eligibleCandidate,
            now: now,
            enabled: enabled,
            isRecording: isRecording,
            isStarting: isStarting
        ) else { return }

        if startRecording(DetectedMeetingAutoRecordStartRequest(candidate: candidate)) {
            // The controller accepted an asynchronous start. Do not mark this
            // session complete until MeetingSession.start() actually succeeds.
            acceptedCandidate = candidate
        } else {
            policy.startDidFail(candidate, now: now)
        }
    }

    func recordingDidBecomeActive() {
        guard let candidate = acceptedCandidate else { return }
        acceptedCandidate = nil
        policy.recordingDidStart(candidate)
        recordingStarted(candidate)
    }

    func startDidFail(now: Date = Date()) {
        guard let candidate = acceptedCandidate else { return }
        acceptedCandidate = nil
        policy.startDidFail(candidate, now: now)
    }

    func recordingDidStop() {
        policy.recordingDidStop()
    }

    func recordingDidFinalize() {
        recordingFinalized()
    }

    private static func attendedCandidate(_ candidate: MeetingCandidate) -> MeetingCandidate? {
        guard let bundleID = candidate.sourceBundleID,
              supportedSourceBundleIDs.contains(bundleID) else { return nil }
        if bundleID == "com.microsoft.teams2" || bundleID == "com.microsoft.teams" {
            return candidate.evidence.contains(.dedicatedApp)
                && candidate.evidence.contains(.audioInputProcess) ? candidate : nil
        }
        let hasLiveMediaEvidence = candidate.evidence.contains(.audioInputProcess)
            || candidate.evidence.contains(.micActive)
            || candidate.evidence.contains(.cameraActive)
        return candidate.evidence.contains(.browserURL) && hasLiveMediaEvidence ? candidate : nil
    }
}
