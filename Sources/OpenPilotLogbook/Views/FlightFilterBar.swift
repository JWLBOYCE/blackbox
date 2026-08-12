import SwiftUI
import OpenPilotLogbookCore

struct FlightFilterBar: View {
    var query: FlightQuery
    var resultCount: Int
    var reset: () -> Void

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) { content }
            VStack(alignment: .leading, spacing: 8) { content }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Active flight filters")
    }

    @ViewBuilder private var content: some View {
        if query.activeFilterLabels.isEmpty {
            Label("No active filters", systemImage: "line.3.horizontal.decrease.circle")
                .font(.caption)
                .foregroundStyle(.secondary)
        } else {
            ForEach(query.activeFilterLabels, id: \.self) { label in
                Text(label)
                    .font(.caption.weight(.medium))
                    .lineLimit(1)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .background(.quaternary, in: Capsule())
                    .overlay { Capsule().stroke(Color(nsColor: .separatorColor).opacity(0.45), lineWidth: 1) }
                    .accessibilityLabel("Filter: \(label)")
                    .accessibilityIdentifier("filters.chip.\(label.filterAccessibilityIdentifierComponent)")
            }
        }
        Text("\(resultCount.formatted()) record\(resultCount == 1 ? "" : "s")")
            .font(.caption.monospacedDigit())
            .foregroundStyle(.secondary)
            .accessibilityIdentifier("filters.resultCount")
        if !query.activeFilterLabels.isEmpty {
            Button("Reset Filters", action: reset)
                .buttonStyle(.bordered)
                .controlSize(.small)
                .accessibilityIdentifier("filters.reset")
        }
    }
}

struct FlightQueryEditor: View {
    var query: FlightQuery
    var aircraftIDs: [String]
    var aircraftTypes: [String]
    var pilotFunctions: [String]
    var operations: [String]
    var entryKinds: [String]
    var apply: (FlightQuery) -> Void

    var body: some View {
        Menu {
            Menu("Date range") {
                Button("All time") { updateQuery { $0.startDate = nil; $0.endDate = nil } }
                    .accessibilityIdentifier("filters.value.date-range.all")
                Button("Last 90 days") {
                    updateQuery {
                        $0.startDate = Calendar.current.date(byAdding: .day, value: -90, to: Date())
                        $0.endDate = Date()
                    }
                }
                .accessibilityIdentifier("filters.value.date-range.90-days")
                Button("Last 12 months") {
                    updateQuery {
                        $0.startDate = Calendar.current.date(byAdding: .year, value: -1, to: Date())
                        $0.endDate = Date()
                    }
                }
                .accessibilityIdentifier("filters.value.date-range.12-months")
            }
            .accessibilityIdentifier("filters.dimension.date-range")
            filterSection("Aircraft", identifier: "aircraft", values: aircraftIDs, selected: query.aircraftIDs) { value in updateQuery { $0.aircraftIDs = value } }
            filterSection("Aircraft type", identifier: "aircraft-type", values: aircraftTypes, selected: query.aircraftTypes) { value in updateQuery { $0.aircraftTypes = value } }
            filterSection("Pilot function", identifier: "pilot-function", values: pilotFunctions, selected: query.pilotFunctions) { value in updateQuery { $0.pilotFunctions = value } }
            filterSection("Operation", identifier: "operation", values: operations, selected: query.operations) { value in updateQuery { $0.operations = value } }
            filterSection("Entry type", identifier: "entry-type", values: entryKinds, selected: query.entryKinds) { value in updateQuery { $0.entryKinds = value } }
            Divider()
            Menu("Record state") {
                ForEach(FlightRecordState.allCases, id: \.self) { state in
                    Toggle(state.displayName, isOn: setBinding(state, in: query.recordStates) { value in updateQuery { $0.recordStates = value } })
                        .accessibilityIdentifier("filters.value.record-state.\(state.rawValue)")
                }
            }
            .accessibilityIdentifier("filters.dimension.record-state")
        } label: {
            Label("All Filters", systemImage: "line.3.horizontal.decrease.circle")
        }
        .accessibilityIdentifier("filters.editor")
    }

    @ViewBuilder
    private func filterSection(_ title: String, identifier: String, values: [String], selected: Set<String>, update: @escaping (Set<String>) -> Void) -> some View {
        Menu(title) {
            if values.isEmpty {
                Text("No values")
            } else {
                ForEach(values.filter { !$0.isEmpty }, id: \.self) { value in
                    Toggle(value, isOn: setBinding(value, in: selected, update: update))
                        .accessibilityIdentifier("filters.value.\(identifier).\(value.filterAccessibilityIdentifierComponent)")
                }
            }
        }
        .accessibilityIdentifier("filters.dimension.\(identifier)")
    }

    private func setBinding<Value: Hashable>(_ value: Value, in set: Set<Value>, update: @escaping (Set<Value>) -> Void) -> Binding<Bool> {
        Binding(
            get: { set.contains(value) },
            set: { enabled in
                var next = set
                if enabled { next.insert(value) }
                else { next.remove(value) }
                update(next)
            }
        )
    }

    private func updateQuery(_ change: (inout FlightQuery) -> Void) {
        var next = query
        change(&next)
        apply(next)
    }
}

private extension String {
    var filterAccessibilityIdentifierComponent: String {
        lowercased()
            .replacingOccurrences(of: "[^a-z0-9]+", with: "-", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
    }
}

private extension FlightQuery {
    var activeFilterLabels: [String] {
        var labels: [String] = []
        if !text.isEmpty { labels.append("Text: \(text)") }
        if let startDate { labels.append("From \(Self.filterDate.string(from: startDate))") }
        if let endDate { labels.append("To \(Self.filterDate.string(from: endDate))") }
        if !aircraftIDs.isEmpty { labels.append("Aircraft: \(aircraftIDs.sorted().joined(separator: ", "))") }
        if !aircraftTypes.isEmpty { labels.append("Type: \(aircraftTypes.sorted().joined(separator: ", "))") }
        if !pilotFunctions.isEmpty { labels.append("Function: \(pilotFunctions.sorted().joined(separator: ", "))") }
        if !operations.isEmpty { labels.append("Operation: \(operations.sorted().joined(separator: ", "))") }
        if !entryKinds.isEmpty { labels.append("Type: \(entryKinds.sorted().joined(separator: ", "))") }
        let defaultStates: Set<FlightRecordState> = [.draft, .finalised]
        if recordStates != defaultStates {
            labels.append("States: \(recordStates.map(\.displayName).sorted().joined(separator: ", "))")
        }
        return labels
    }

    static let filterDate: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_GB")
        formatter.dateStyle = .medium
        return formatter
    }()
}
