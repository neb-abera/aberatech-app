import AberaCore
import SwiftUI

/// The requests that name the person signed in: open ones first, with
/// their status, then ones finished in the last 30 days.
struct RequestsView: View {
    @Bindable var model: AppModel
    @State private var editing: RequestItem?
    @State private var adding = false

    private var open: [RequestItem] { model.requests.filter(\.status.isOpen) }
    private var finished: [RequestItem] { model.requests.filter { !$0.status.isOpen } }

    var body: some View {
        NavigationStack {
            List {
                if let error = model.error {
                    Text(error).foregroundStyle(.red).accessibilityIdentifier("requests-error")
                }
                if model.requests.isEmpty {
                    ContentUnavailableView(
                        "No requests", systemImage: "tray",
                        description: Text(
                            "Tap + to ask for something, or email it. Emails show up here within the hour."))
                }
                if !open.isEmpty {
                    Section("Open") {
                        ForEach(open) { item in
                            row(item)
                                .swipeActions {
                                    Button("Remove", role: .destructive) { Task { await model.remove(item.id) } }
                                }
                        }
                    }
                }
                if !finished.isEmpty {
                    Section("Finished") {
                        ForEach(finished) { item in row(item) }
                    }
                }
            }
            .navigationTitle("Requests")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button("Add request", systemImage: "plus") { adding = true }
                        .accessibilityIdentifier("add-request")
                }
            }
            .refreshable { await model.loadRequests() }
            .sheet(isPresented: $adding) { RequestEditor(model: model, item: nil) }
            .sheet(item: $editing) { item in RequestEditor(model: model, item: item) }
        }
    }

    private func row(_ item: RequestItem) -> some View {
        Button {
            editing = item
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                Text(item.title).font(.body).foregroundStyle(.primary)
                HStack(spacing: 8) {
                    StatusBadge(status: item.status)
                    if let due = item.due { Text("Due \(RequestDates.display(due))").foregroundStyle(.secondary) }
                    if item.fromEmail {
                        Label("Email", systemImage: "envelope").labelStyle(.iconOnly).foregroundStyle(.secondary)
                    }
                }
                .font(.footnote)
                if item.status == .notDoing, let reason = item.reason {
                    Text(reason).font(.footnote).foregroundStyle(.secondary)
                }
            }
        }
        .accessibilityIdentifier("request-\(item.title)")
    }
}

struct StatusBadge: View {
    let status: RequestItem.Status

    var body: some View {
        Text(status.label)
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .background(color.opacity(0.18), in: Capsule())
            .foregroundStyle(color)
    }

    private var color: Color {
        switch status {
        case .received: .blue
        case .inProgress: .orange
        case .done: .green
        case .notDoing: .gray
        }
    }
}

enum RequestDates {
    static let wire: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    /// "Sun 15 Nov" from "2026-11-15".
    static func display(_ wireDate: String) -> String {
        guard let date = wire.date(from: wireDate) else { return wireDate }
        return date.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated))
    }
}

/// Adds a request, or shows one: its status, and for an open one its
/// fields to change and Remove.
struct RequestEditor: View {
    @Bindable var model: AppModel
    let item: RequestItem?
    @Environment(\.dismiss) private var dismiss
    @State private var title: String
    @State private var details: String
    @State private var hasDue: Bool
    @State private var due: Date
    @State private var link: String

    init(model: AppModel, item: RequestItem?) {
        self.model = model
        self.item = item
        _title = State(initialValue: item?.title ?? "")
        _details = State(initialValue: item?.details ?? "")
        let parsed = item?.due.flatMap(RequestDates.wire.date(from:))
        _hasDue = State(initialValue: parsed != nil)
        _due = State(initialValue: parsed ?? Calendar.current.date(byAdding: .day, value: 7, to: .now) ?? .now)
        _link = State(initialValue: item?.link ?? "")
    }

    private var editable: Bool { item?.editable ?? true }

    private var input: RequestInput {
        RequestInput(
            title: title, details: details, due: hasDue ? RequestDates.wire.string(from: due) : nil, link: link)
    }

    var body: some View {
        NavigationStack {
            Form {
                if let item {
                    Section {
                        StatusBadge(status: item.status).accessibilityIdentifier("request-status")
                        if let reason = item.reason { Text(reason) }
                        if item.fromEmail { Label("Sent by email", systemImage: "envelope") }
                    }
                }
                Section {
                    TextField("What needs doing", text: $title, axis: .vertical)
                        .accessibilityIdentifier("request-title")
                    TextField("Details", text: $details, axis: .vertical)
                        .lineLimit(3...8)
                        .accessibilityIdentifier("request-details")
                }
                .disabled(!editable)
                Section {
                    Toggle("Due date", isOn: $hasDue.animation()).accessibilityIdentifier("request-has-due")
                    if hasDue {
                        DatePicker("Due", selection: $due, displayedComponents: .date)
                    }
                    TextField("Link", text: $link)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .accessibilityIdentifier("request-link")
                }
                .disabled(!editable)
                if let error = model.error {
                    Text(error).foregroundStyle(.red).accessibilityIdentifier("request-error")
                }
                if let item, editable {
                    Section {
                        Button("Remove request", role: .destructive) {
                            Task {
                                await model.remove(item.id)
                                if model.error == nil { dismiss() }
                            }
                        }
                        .accessibilityIdentifier("remove-request")
                    } footer: {
                        Text("It leaves your list. Neb's task list keeps it, marked removed by you.")
                    }
                }
            }
            .navigationTitle(item == nil ? "New request" : "Request")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(editable ? "Cancel" : "Close") {
                        model.clearError()
                        dismiss()
                    }
                }
                if editable {
                    ToolbarItem(placement: .confirmationAction) {
                        Button(item == nil ? "Add" : "Save") {
                            Task {
                                let saved =
                                    if let item { await model.edit(item.id, input) } else { await model.add(input) }
                                if saved { dismiss() }
                            }
                        }
                        .disabled(model.busy)
                        .accessibilityIdentifier("save-request")
                    }
                }
            }
        }
    }
}
