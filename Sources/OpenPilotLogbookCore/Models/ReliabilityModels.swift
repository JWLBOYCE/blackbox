import Foundation

public struct FlightQuery: Equatable, Codable {
    public var text: String
    public var startDate: Date?
    public var endDate: Date?
    public var aircraftIDs: Set<String>
    public var aircraftTypes: Set<String>
    public var pilotFunctions: Set<String>
    public var operations: Set<String>
    public var entryKinds: Set<String>
    public var recordStates: Set<FlightRecordState>

    public init(
        text: String = "",
        startDate: Date? = nil,
        endDate: Date? = nil,
        aircraftIDs: Set<String> = [],
        aircraftTypes: Set<String> = [],
        pilotFunctions: Set<String> = [],
        operations: Set<String> = [],
        entryKinds: Set<String> = [],
        recordStates: Set<FlightRecordState> = [.draft, .finalised]
    ) {
        self.text = text
        self.startDate = startDate
        self.endDate = endDate
        self.aircraftIDs = aircraftIDs
        self.aircraftTypes = aircraftTypes
        self.pilotFunctions = pilotFunctions
        self.operations = operations
        self.entryKinds = entryKinds
        self.recordStates = recordStates
    }
}

public struct SavedAnalysisGroup: Identifiable, Equatable, Codable {
    public var id: UUID
    public var name: String
    public var query: FlightQuery
    public var landingLimit: Int?
    public var lookbackDays: Int?

    public init(id: UUID = UUID(), name: String, query: FlightQuery, landingLimit: Int? = nil, lookbackDays: Int? = nil) {
        self.id = id
        self.name = name
        self.query = query
        self.landingLimit = landingLimit
        self.lookbackDays = lookbackDays
    }
}

public enum MigrationFailurePoint: String, Codable {
    case beforeTransaction
    case duringTransaction
    case afterTransaction
}

public enum FlightValidationSeverity: String, Codable {
    case warning
    case error
}

public struct FlightValidationIssue: Identifiable, Equatable, Codable {
    public var id: String { "\(field)-\(message)" }
    public var field: String
    public var message: String
    public var guidance: String
    public var severity: FlightValidationSeverity

    public init(field: String, message: String, guidance: String, severity: FlightValidationSeverity = .warning) {
        self.field = field
        self.message = message
        self.guidance = guidance
        self.severity = severity
    }
}

public struct FlightValidationReport: Equatable, Codable {
    public var issues: [FlightValidationIssue]

    public init(issues: [FlightValidationIssue] = []) {
        self.issues = issues
    }

    public var hasErrors: Bool { issues.contains { $0.severity == .error } }
    public var isClear: Bool { issues.isEmpty }
}

public enum FlightSuggestionField: String, Codable {
    case distanceNM
    case departureCoordinates
    case arrivalCoordinates
    case nightMinutes
    case picMinutes
    case picusMinutes
    case copilotMinutes
    case dualMinutes
    case instructorMinutes
    case fstdMinutes
    case totalTakeoffs
    case totalLandings
}

public struct FlightSuggestion: Identifiable, Equatable, Codable {
    public var id: String { "\(field.rawValue)-\(proposedValue)" }
    public var field: FlightSuggestionField
    public var title: String
    public var explanation: String
    public var currentValue: String
    public var proposedValue: String
    public var numericValue: Double?
    public var latitude: Double?
    public var longitude: Double?
    public var inputs: [String]
    public var method: String
    public var confidence: String
    public var unavailableReason: String?
    public var isActionable: Bool { unavailableReason == nil }

    public init(
        field: FlightSuggestionField,
        title: String,
        explanation: String,
        currentValue: String,
        proposedValue: String,
        numericValue: Double? = nil,
        latitude: Double? = nil,
        longitude: Double? = nil,
        inputs: [String] = [],
        method: String = "",
        confidence: String = "High",
        unavailableReason: String? = nil
    ) {
        self.field = field
        self.title = title
        self.explanation = explanation
        self.currentValue = currentValue
        self.proposedValue = proposedValue
        self.numericValue = numericValue
        self.latitude = latitude
        self.longitude = longitude
        self.inputs = inputs
        self.method = method
        self.confidence = confidence
        self.unavailableReason = unavailableReason
    }
}

public struct SuggestionBatch: Identifiable, Equatable, Codable {
    public var id: UUID
    public var flightID: Int64?
    public var suggestions: [FlightSuggestion]
    public var selectedSuggestionIDs: Set<String>
    public var preparedAt: Date

    public init(id: UUID = UUID(), flightID: Int64? = nil, suggestions: [FlightSuggestion], selectedSuggestionIDs: Set<String> = [], preparedAt: Date = Date()) {
        self.id = id
        self.flightID = flightID
        self.suggestions = suggestions
        self.selectedSuggestionIDs = selectedSuggestionIDs
        self.preparedAt = preparedAt
    }
}

public struct FlightRevisionDiff: Identifiable, Equatable, Codable {
    public var id: String { field }
    public var field: String
    public var beforeValue: String?
    public var afterValue: String?

    public init(field: String, beforeValue: String?, afterValue: String?) {
        self.field = field
        self.beforeValue = beforeValue
        self.afterValue = afterValue
    }
}

public struct HistoryQuery: Equatable, Codable {
    public var text: String
    public var flightID: Int64?
    public var operationKinds: Set<String>
    public var statuses: Set<String>

    public init(text: String = "", flightID: Int64? = nil, operationKinds: Set<String> = [], statuses: Set<String> = []) {
        self.text = text
        self.flightID = flightID
        self.operationKinds = operationKinds
        self.statuses = statuses
    }
}

public struct TrashItem: Identifiable, Equatable, Codable {
    public var id: Int64
    public var flight: FlightEntry
    public var trashedAt: Date?
    public var origin: String

    public init(id: Int64, flight: FlightEntry, trashedAt: Date? = nil, origin: String = "") {
        self.id = id
        self.flight = flight
        self.trashedAt = trashedAt
        self.origin = origin
    }
}

public struct OperationVerification: Equatable, Codable {
    public var integrityCheck: String
    public var schemaVersion: Int
    public var expectedSchemaVersion: Int?
    public var expectedFlightCount: Int
    public var actualFlightCount: Int
    public var expectedTotalMinutes: Int
    public var actualTotalMinutes: Int
    public var revisionCoverageComplete: Bool
    public var expectedRevisionCount: Int?
    public var actualRevisionCount: Int?
    public var expectedFlightDigest: String?
    public var actualFlightDigest: String?
    /// Nil is retained for backward compatibility with operation-history JSON
    /// written before schema v4 verification metadata was expanded.
    public var foreignKeyIssues: [String]?
    /// Logical relationship checks are separate from SQLite foreign keys so a
    /// structurally invalid amendment chain cannot pass a vacuous FK check.
    public var amendmentIssues: [String]?
    public var verifiedAt: Date

    public init(
        integrityCheck: String = "",
        schemaVersion: Int = 0,
        expectedSchemaVersion: Int? = nil,
        expectedFlightCount: Int = 0,
        actualFlightCount: Int = 0,
        expectedTotalMinutes: Int = 0,
        actualTotalMinutes: Int = 0,
        revisionCoverageComplete: Bool = false,
        expectedRevisionCount: Int? = nil,
        actualRevisionCount: Int? = nil,
        expectedFlightDigest: String? = nil,
        actualFlightDigest: String? = nil,
        foreignKeyIssues: [String]? = nil,
        amendmentIssues: [String]? = nil,
        verifiedAt: Date = Date()
    ) {
        self.integrityCheck = integrityCheck
        self.schemaVersion = schemaVersion
        self.expectedSchemaVersion = expectedSchemaVersion
        self.expectedFlightCount = expectedFlightCount
        self.actualFlightCount = actualFlightCount
        self.expectedTotalMinutes = expectedTotalMinutes
        self.actualTotalMinutes = actualTotalMinutes
        self.revisionCoverageComplete = revisionCoverageComplete
        self.expectedRevisionCount = expectedRevisionCount
        self.actualRevisionCount = actualRevisionCount
        self.expectedFlightDigest = expectedFlightDigest
        self.actualFlightDigest = actualFlightDigest
        self.foreignKeyIssues = foreignKeyIssues
        self.amendmentIssues = amendmentIssues
        self.verifiedAt = verifiedAt
    }

    public var passed: Bool {
        integrityCheck.lowercased() == "ok" &&
        expectedSchemaVersion.map { $0 == schemaVersion } != false &&
        expectedFlightCount == actualFlightCount &&
        expectedTotalMinutes == actualTotalMinutes &&
        revisionCoverageComplete &&
        expectedRevisionCount.map { $0 == actualRevisionCount } != false &&
        expectedFlightDigest.map { $0 == actualFlightDigest } != false &&
        foreignKeyIssues.map(\.isEmpty) != false &&
        amendmentIssues.map(\.isEmpty) != false
    }
}

public struct FlightRevision: Identifiable, Equatable, Codable {
    public var id: Int64?
    public var flightID: Int64
    public var action: String
    public var origin: String
    public var operationBatchID: String?
    public var beforeJSON: String?
    public var afterJSON: String?
    public var createdAt: Date

    public init(id: Int64? = nil, flightID: Int64, action: String, origin: String, operationBatchID: String? = nil, beforeJSON: String? = nil, afterJSON: String? = nil, createdAt: Date = Date()) {
        self.id = id
        self.flightID = flightID
        self.action = action
        self.origin = origin
        self.operationBatchID = operationBatchID
        self.beforeJSON = beforeJSON
        self.afterJSON = afterJSON
        self.createdAt = createdAt
    }
}

public struct OperationBatch: Identifiable, Equatable, Codable {
    public var id: String
    public var kind: String
    public var source: String
    public var status: String
    public var summary: String
    public var backupPath: String?
    public var createdAt: Date
    public var completedAt: Date?
    public var affectedCount: Int
    public var beforeTotalMinutes: Int
    public var afterTotalMinutes: Int
    public var verification: OperationVerification?
    public var failureStage: String?
    public var recoveryOutcome: String?
    public var artifactURLs: [URL]

    public init(id: String = UUID().uuidString, kind: String, source: String = "", status: String = "planned", summary: String = "", backupPath: String? = nil, createdAt: Date = Date(), completedAt: Date? = nil, affectedCount: Int = 0, beforeTotalMinutes: Int = 0, afterTotalMinutes: Int = 0, verification: OperationVerification? = nil, failureStage: String? = nil, recoveryOutcome: String? = nil, artifactURLs: [URL] = []) {
        self.id = id
        self.kind = kind
        self.source = source
        self.status = status
        self.summary = summary
        self.backupPath = backupPath
        self.createdAt = createdAt
        self.completedAt = completedAt
        self.affectedCount = affectedCount
        self.beforeTotalMinutes = beforeTotalMinutes
        self.afterTotalMinutes = afterTotalMinutes
        self.verification = verification
        self.failureStage = failureStage
        self.recoveryOutcome = recoveryOutcome
        self.artifactURLs = artifactURLs
    }
}

public enum ImportDecision: String, Codable, CaseIterable {
    case include
    case exclude
}

public enum ImportResultingAction: String, Codable {
    case createDraft
    /// Keep the already-linked Blackbox record and import no new row.
    case linkAndSkip
    /// Import this source record as a separate draft despite a likely match.
    case importSeparateDraft
    case updateDraft
    case createAmendment
    case ignore
}

public enum ImportSourceKind: String, Codable {
    case logTen
    case document

    public var revisionOrigin: String {
        switch self {
        case .logTen: return "LogTen"
        case .document: return "document_import"
        }
    }

    public var operationKind: String {
        switch self {
        case .logTen: return "logten_import"
        case .document: return "document_import"
        }
    }
}

public struct ImportFieldSelection: Identifiable, Equatable, Codable {
    public var id: String { "\(sourcePK)-\(field)" }
    public var sourcePK: Int64
    public var field: String
    public var blackboxValue: String
    public var sourceValue: String
    public var decision: ImportDecision

    public init(sourcePK: Int64, field: String, blackboxValue: String, sourceValue: String, decision: ImportDecision = .include) {
        self.sourcePK = sourcePK
        self.field = field
        self.blackboxValue = blackboxValue
        self.sourceValue = sourceValue
        self.decision = decision
    }
}

/// A stable, read-only identity used by import previews for rows that will not
/// be changed. It deliberately contains display metadata only, never an action
/// that could turn an omission into a deletion.
public struct ImportRecordIdentity: Identifiable, Equatable, Codable {
    public var id: String {
        if let flightID { return "flight-\(flightID)" }
        if let sourcePK { return "source-\(sourcePK)" }
        return "\(LogbookFormatters.isoFormatter.string(from: date))-\(route)-\(aircraftID)-\(flightNumber)"
    }

    public var flightID: Int64?
    public var sourcePK: Int64?
    public var date: Date
    public var route: String
    public var aircraftID: String
    public var flightNumber: String
    public var recordState: FlightRecordState

    public init(
        flightID: Int64? = nil,
        sourcePK: Int64? = nil,
        date: Date,
        route: String,
        aircraftID: String,
        flightNumber: String,
        recordState: FlightRecordState
    ) {
        self.flightID = flightID
        self.sourcePK = sourcePK
        self.date = date
        self.route = route
        self.aircraftID = aircraftID
        self.flightNumber = flightNumber
        self.recordState = recordState
    }
}

public struct ImportPlan: Identifiable, Equatable {
    public var id: String
    public var sourceURL: URL
    /// A private, self-contained copy captured while the selected source's
    /// security scope is active. Applying a plan never reopens sourceURL.
    public var sourceSnapshotURL: URL?
    public var additions: [FlightEntry]
    public var changes: [ImportChange]
    public var unchangedCount: Int
    public private(set) var unchangedRecords: [ImportRecordIdentity]
    public var duplicateSourceIDs: [Int64]
    public var conflicts: [String]
    public var conflictSourceIDs: [Int64]
    public var missingFromSourceCount: Int
    /// Existing Blackbox rows whose source identifier is absent from the
    /// selected source. This list is informational; imports never remove them.
    public private(set) var sourceOnlyOmissions: [ImportRecordIdentity]
    public var createdAt: Date
    public var fieldSelections: [ImportFieldSelection]
    public var duplicateDecisions: [Int64: ImportDecision]
    /// Per-source choices for duplicate or conflict records. This uses the same
    /// action vocabulary as normal matches, so preview and staged apply cannot
    /// silently substitute a different outcome.
    public var resolutionActions: [Int64: ImportResultingAction]
    public var resultingActions: [Int64: ImportResultingAction]
    public var sourceKind: ImportSourceKind
    public var baselineFlightDigest: String
    public var sourceSnapshotDigest: String
    // Only OpenPilotLogbookCore can mint these values. Publicly constructed or
    // copied plans cannot nominate a filesystem location for recursive cleanup.
    var artifactToken: UUID?
    var candidateSnapshotURL: URL?
    var candidateSnapshotFileDigest: String
    var sealedPlanDigest: String

    public init(id: String = UUID().uuidString, sourceURL: URL, sourceSnapshotURL: URL? = nil, additions: [FlightEntry] = [], changes: [ImportChange] = [], unchangedCount: Int = 0, unchangedRecords: [ImportRecordIdentity] = [], duplicateSourceIDs: [Int64] = [], conflicts: [String] = [], conflictSourceIDs: [Int64] = [], missingFromSourceCount: Int = 0, sourceOnlyOmissions: [ImportRecordIdentity] = [], createdAt: Date = Date(), fieldSelections: [ImportFieldSelection] = [], duplicateDecisions: [Int64: ImportDecision] = [:], resolutionActions: [Int64: ImportResultingAction] = [:], resultingActions: [Int64: ImportResultingAction] = [:], sourceKind: ImportSourceKind = .logTen, baselineFlightDigest: String = "", sourceSnapshotDigest: String = "") {
        self.id = id
        self.sourceURL = sourceURL
        self.sourceSnapshotURL = sourceSnapshotURL
        self.additions = additions
        self.changes = changes
        self.unchangedCount = unchangedCount
        self.unchangedRecords = unchangedRecords
        self.duplicateSourceIDs = duplicateSourceIDs
        self.conflicts = conflicts
        self.conflictSourceIDs = conflictSourceIDs
        self.missingFromSourceCount = missingFromSourceCount
        self.sourceOnlyOmissions = sourceOnlyOmissions
        self.createdAt = createdAt
        self.fieldSelections = fieldSelections
        self.duplicateDecisions = duplicateDecisions
        self.resolutionActions = resolutionActions
        self.resultingActions = resultingActions
        self.sourceKind = sourceKind
        self.baselineFlightDigest = baselineFlightDigest
        self.sourceSnapshotDigest = sourceSnapshotDigest
        self.artifactToken = nil
        self.candidateSnapshotURL = nil
        self.candidateSnapshotFileDigest = ""
        self.sealedPlanDigest = ""
    }

    public var isApplicable: Bool {
        duplicateSourceIDs.allSatisfy { duplicateDecisions[$0] != nil || resolutionActions[$0] != nil } &&
        conflictSourceIDs.allSatisfy { resolutionActions[$0] != nil }
    }
}

public enum TransactionFailureStage: String, Codable, CaseIterable {
    case backupCreation
    case transaction
    case postTransactionVerification
    case staging
    case beforeAtomicSwap
    case afterAtomicSwap
    /// Backward-compatible spelling retained for existing fixtures. It is
    /// injected at the same boundary as beforeAtomicSwap.
    case atomicSwap
}

public struct ImportChange: Identifiable, Equatable {
    public var id: Int64 { sourcePK }
    public var sourcePK: Int64
    public var existing: FlightEntry
    public var proposed: FlightEntry
    public var changedFields: [String]

    public init(sourcePK: Int64, existing: FlightEntry, proposed: FlightEntry, changedFields: [String]) {
        self.sourcePK = sourcePK
        self.existing = existing
        self.proposed = proposed
        self.changedFields = changedFields
    }
}

public struct RestorePlan: Identifiable, Equatable {
    public var id: String
    public var encryptedBackupURL: URL
    public var inspectedDatabaseURL: URL
    public var currentFlightCount: Int
    public var restoredFlightCount: Int
    public var currentTotalMinutes: Int
    public var restoredTotalMinutes: Int
    public var schemaVersion: Int
    public var integrityMessage: String
    public var inspectedDigest: String
    public var currentFlightDigest: String
    public var restoredFlightDigest: String
    // Set only by LogbookRepository for a repository-owned temporary root.
    var artifactToken: UUID?
    var sealedPlanDigest: String

    public init(id: String = UUID().uuidString, encryptedBackupURL: URL, inspectedDatabaseURL: URL, currentFlightCount: Int, restoredFlightCount: Int, currentTotalMinutes: Int, restoredTotalMinutes: Int, schemaVersion: Int, integrityMessage: String, inspectedDigest: String = "", currentFlightDigest: String = "", restoredFlightDigest: String = "") {
        self.id = id
        self.encryptedBackupURL = encryptedBackupURL
        self.inspectedDatabaseURL = inspectedDatabaseURL
        self.currentFlightCount = currentFlightCount
        self.restoredFlightCount = restoredFlightCount
        self.currentTotalMinutes = currentTotalMinutes
        self.restoredTotalMinutes = restoredTotalMinutes
        self.schemaVersion = schemaVersion
        self.integrityMessage = integrityMessage
        self.inspectedDigest = inspectedDigest
        self.currentFlightDigest = currentFlightDigest
        self.restoredFlightDigest = restoredFlightDigest
        self.artifactToken = nil
        self.sealedPlanDigest = ""
    }
}

public enum LogTenComparisonState: Equatable {
    case idle
    case loading
    case loaded(LogTenComparisonSnapshot)
    case empty(String)
    case unavailable(String)
    case failed(String)
}

public struct UpgradePreflight: Equatable {
    public var requiresUpgrade: Bool
    public var currentSchemaVersion: Int
    public var targetSchemaVersion: Int
    public var flightCount: Int
    public var legacyDigest: String
    public var proposedBackupURL: URL
    public var amendmentIssues: [String]

    public init(requiresUpgrade: Bool, currentSchemaVersion: Int, targetSchemaVersion: Int, flightCount: Int, legacyDigest: String, proposedBackupURL: URL, amendmentIssues: [String] = []) {
        self.requiresUpgrade = requiresUpgrade
        self.currentSchemaVersion = currentSchemaVersion
        self.targetSchemaVersion = targetSchemaVersion
        self.flightCount = flightCount
        self.legacyDigest = legacyDigest
        self.proposedBackupURL = proposedBackupURL
        self.amendmentIssues = amendmentIssues
    }
}

public enum LogbookRepositoryError: LocalizedError {
    case upgradeRequired(UpgradePreflight)
    case immutableRecord
    case invalidState(String)
    case warningsRequireAcknowledgement(FlightValidationReport)
    case integrityCheckFailed(String)
    case stalePlan
    case emptyComparisonSource(String)
    case operationFailedWithVerifiedRecovery(operation: String, operationMessage: String, recoveryOutcome: String)
    case recoveryFailed(operation: String, operationMessage: String, recoveryMessage: String)

    public var errorDescription: String? {
        switch self {
        case .upgradeRequired: return "This logbook requires a reviewed backup and schema upgrade before it can be opened."
        case .immutableRecord: return "Finalised and superseded records cannot be edited. Create an amendment instead."
        case .invalidState(let message): return message
        case .warningsRequireAcknowledgement: return "Review and acknowledge the logbook warnings before finalising."
        case .integrityCheckFailed(let message): return "Database integrity verification failed: \(message)"
        case .stalePlan: return "This preview is no longer current. Create a new preview before applying it."
        case .emptyComparisonSource(let message): return message
        case .operationFailedWithVerifiedRecovery(let operation, let operationMessage, let recoveryOutcome):
            return "\(operation) failed (\(operationMessage)). \(recoveryOutcome)."
        case .recoveryFailed(let operation, let operationMessage, let recoveryMessage):
            return "\(operation) failed (\(operationMessage)) and the recovery point could not be verified (\(recoveryMessage)). Stop using this database and preserve the diagnostic artifact."
        }
    }
}
