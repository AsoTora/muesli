import Foundation

enum MeetingAutoRecordDecision: Equatable {
    case none
    case start(MeetingCandidate)
}

/// Pure state machine for automatically starting an attended meeting exactly once.
struct MeetingAutoRecordPolicy {
    let stabilizationInterval: TimeInterval
    let failedStartCooldown: TimeInterval

    private var pendingSuppressionID: String?
    private var pendingSince: Date?
    private var completedSuppressionIDs = Set<String>()
    private var failedUntilBySuppressionID: [String: Date] = [:]

    init(stabilizationInterval: TimeInterval = 3, failedStartCooldown: TimeInterval = 30) {
        self.stabilizationInterval = stabilizationInterval
        self.failedStartCooldown = failedStartCooldown
    }

    mutating func evaluate(
        candidate: MeetingCandidate?,
        now: Date,
        enabled: Bool,
        isRecording: Bool,
        isStarting: Bool
    ) -> MeetingAutoRecordDecision {
        guard enabled else {
            pendingSuppressionID = nil
            pendingSince = nil
            return .none
        }
        guard !isRecording, !isStarting, let candidate else {
            if candidate == nil {
                pendingSuppressionID = nil
                pendingSince = nil
                if !isRecording && !isStarting {
                    completedSuppressionIDs.removeAll()
                    failedUntilBySuppressionID.removeAll()
                }
            }
            return .none
        }

        let sessionID = candidate.suppressionID
        guard !completedSuppressionIDs.contains(sessionID) else { return .none }
        if let failedUntil = failedUntilBySuppressionID[sessionID], now < failedUntil {
            return .none
        }
        if pendingSuppressionID != sessionID {
            pendingSuppressionID = sessionID
            pendingSince = now
        }
        guard let pendingSince,
              now.timeIntervalSince(pendingSince) >= stabilizationInterval else {
            return .none
        }
        return .start(candidate)
    }

    mutating func recordingDidStart(_ candidate: MeetingCandidate) {
        completedSuppressionIDs.insert(candidate.suppressionID)
        failedUntilBySuppressionID[candidate.suppressionID] = nil
        pendingSuppressionID = nil
        pendingSince = nil
    }

    mutating func startDidFail(_ candidate: MeetingCandidate, now: Date) {
        failedUntilBySuppressionID[candidate.suppressionID] = now.addingTimeInterval(failedStartCooldown)
        pendingSuppressionID = candidate.suppressionID
        pendingSince = now.addingTimeInterval(failedStartCooldown - stabilizationInterval)
    }

    mutating func recordingDidStop() {
        pendingSuppressionID = nil
        pendingSince = nil
    }
}
