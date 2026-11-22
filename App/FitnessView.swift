import AberaCore
import Charts
import SwiftUI

/// Neb's goals from his workbook, where each stands today and where the
/// forecast puts it on the due date, and his weight. Read-only.
struct FitnessView: View {
    @Bindable var model: AppModel

    var body: some View {
        NavigationStack {
            List {
                if let fitness = model.fitness {
                    if !fitness.weight.isEmpty { weight(fitness.weight) }
                    ForEach(fitness.sections) { section in
                        Section(section.name) {
                            ForEach(section.goals) { goal in row(goal, dueOn: fitness.dueOn) }
                        }
                    }
                } else {
                    ContentUnavailableView("Loading", systemImage: "figure.run")
                }
            }
            .navigationTitle("Fitness")
            .refreshable { await model.loadFitness() }
        }
    }

    private func weight(_ points: [FitnessSummary.WeighIn]) -> some View {
        Section("Weight") {
            if let last = points.last {
                LabeledContent(
                    "Latest", value: String(format: "%.1f lb on %@", last.pounds, RequestDates.display(last.date))
                )
                .accessibilityIdentifier("latest-weight")
            }
            Chart(points) { point in
                LineMark(
                    x: .value("Date", RequestDates.wire.date(from: point.date) ?? .now),
                    y: .value("Pounds", point.pounds))
                PointMark(
                    x: .value("Date", RequestDates.wire.date(from: point.date) ?? .now),
                    y: .value("Pounds", point.pounds))
            }
            .chartYScale(domain: .automatic(includesZero: false))
            .frame(height: 160)
        }
    }

    private func row(_ goal: FitnessSummary.Goal, dueOn: String?) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(goal.label).font(.headline)
                Spacer()
                if goal.met == true {
                    Label("Met", systemImage: "checkmark.circle.fill").foregroundStyle(.green).labelStyle(.iconOnly)
                }
            }
            Text(
                "Now \(GoalFormat.value(goal.current, unit: goal.unit)), goal \(GoalFormat.value(goal.goal, unit: goal.unit))"
            )
            .font(.subheadline)
            if let projected = goal.projected {
                let by = dueOn.map { " by \(RequestDates.display($0))" } ?? ""
                let chance = GoalFormat.chance(goal.probability).map { ", \($0) chance" } ?? ""
                Text("Forecast \(GoalFormat.value(projected, unit: goal.unit))\(by)\(chance)")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("goal-\(goal.label)")
    }
}
