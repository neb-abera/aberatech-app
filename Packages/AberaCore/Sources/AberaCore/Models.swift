import Foundation

/// One request, as abera.tech reads it from Neb's Notion Tasks.
public struct RequestItem: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var title: String
    public var details: String?
    /// yyyy-MM-dd.
    public var due: String?
    public var status: Status
    /// Why it is not being done, when it is not.
    public var reason: String?
    public var link: String?
    /// It came in by email.
    public var fromEmail: Bool
    public var editable: Bool
    public var createdAt: String
    public var updatedAt: String

    public enum Status: String, Codable, Sendable, CaseIterable {
        case received
        case inProgress = "in-progress"
        case done
        case notDoing = "not-doing"

        /// What the list says.
        public var label: String {
            switch self {
            case .received: "Received"
            case .inProgress: "In progress"
            case .done: "Done"
            case .notDoing: "Not doing"
            }
        }

        public var isOpen: Bool { self == .received || self == .inProgress }
    }

    public init(
        id: String, title: String, details: String? = nil, due: String? = nil, status: Status = .received,
        reason: String? = nil, link: String? = nil, fromEmail: Bool = false, editable: Bool = true,
        createdAt: String = "", updatedAt: String = ""
    ) {
        self.id = id
        self.title = title
        self.details = details
        self.due = due
        self.status = status
        self.reason = reason
        self.link = link
        self.fromEmail = fromEmail
        self.editable = editable
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

/// What the app sends to add or change a request.
public struct RequestInput: Codable, Equatable, Sendable {
    public var title: String
    public var details: String?
    /// yyyy-MM-dd, or nil for no date.
    public var due: String?
    public var link: String?

    public init(title: String, details: String? = nil, due: String? = nil, link: String? = nil) {
        self.title = title
        self.details = details
        self.due = due
        self.link = link
    }

    public static let maxTitle = 200
    public static let maxDetails = 2000

    /// Trimmed, with empty fields dropped.
    public var cleaned: RequestInput {
        func clean(_ text: String?) -> String? {
            guard let trimmed = text?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else {
                return nil
            }
            return trimmed
        }
        return RequestInput(
            title: title.trimmingCharacters(in: .whitespacesAndNewlines), details: clean(details), due: due,
            link: clean(link))
    }

    /// What is wrong with it, before it is sent; nil when it can go.
    public var problem: String? {
        let input = cleaned
        if input.title.isEmpty { return "Add a title." }
        if input.title.count > Self.maxTitle { return "The title holds at most \(Self.maxTitle) characters." }
        if (input.details?.count ?? 0) > Self.maxDetails {
            return "Details hold at most \(Self.maxDetails) characters."
        }
        if let link = input.link {
            guard let url = URL(string: link), ["http", "https"].contains(url.scheme?.lowercased() ?? "") else {
                return "The link must start with https://."
            }
        }
        return nil
    }
}

public struct WishItem: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var item: String
    public var pick: String?
    public var price: Double?
    public var link: String?
    public var category: String?
    public var buyWindow: String?
    public var deadline: String?
    public var status: String?

    public init(
        id: String, item: String, pick: String? = nil, price: Double? = nil, link: String? = nil,
        category: String? = nil, buyWindow: String? = nil, deadline: String? = nil, status: String? = nil
    ) {
        self.id = id
        self.item = item
        self.pick = pick
        self.price = price
        self.link = link
        self.category = category
        self.buyWindow = buyWindow
        self.deadline = deadline
        self.status = status
    }
}

public struct FitnessSummary: Codable, Equatable, Sendable {
    public var dueOn: String?
    public var sections: [Section]
    public var weight: [WeighIn]

    public init(dueOn: String?, sections: [Section], weight: [WeighIn]) {
        self.dueOn = dueOn
        self.sections = sections
        self.weight = weight
    }

    public struct Section: Codable, Equatable, Sendable, Identifiable {
        public var name: String
        public var goals: [Goal]
        public var id: String { name }

        public init(name: String, goals: [Goal]) {
            self.name = name
            self.goals = goals
        }
    }

    public struct Goal: Codable, Equatable, Sendable, Identifiable {
        public var label: String
        public var unit: String
        public var lowerIsBetter: Bool
        public var current: Double?
        public var currentOn: String?
        public var goal: Double?
        public var met: Bool?
        public var projected: Double?
        public var probability: Double?
        public var id: String { label }

        public init(
            label: String, unit: String, lowerIsBetter: Bool = false, current: Double? = nil, currentOn: String? = nil,
            goal: Double? = nil, met: Bool? = nil, projected: Double? = nil, probability: Double? = nil
        ) {
            self.label = label
            self.unit = unit
            self.lowerIsBetter = lowerIsBetter
            self.current = current
            self.currentOn = currentOn
            self.goal = goal
            self.met = met
            self.projected = projected
            self.probability = probability
        }
    }

    public struct WeighIn: Codable, Equatable, Sendable, Identifiable {
        public var date: String
        public var pounds: Double
        public var id: String { date }

        public init(date: String, pounds: Double) {
            self.date = date
            self.pounds = pounds
        }
    }
}

/// A goal's number in its own unit, as a person reads it.
public enum GoalFormat {
    public static func value(_ value: Double?, unit: String) -> String {
        guard let value else { return "none yet" }
        switch unit {
        case "s": return clock(value)
        case "s/mi": return clock(value) + "/mi"
        case "reps": return "\(Int(value.rounded())) reps"
        case "lb": return "\(Int(value.rounded())) lb"
        case "%": return String(format: "%.1f%%", value)
        case "m": return "\(Int(value.rounded())) m"
        case "xbw": return String(format: "%.2f× bodyweight", value)
        default: return String(format: "%g", value)
        }
    }

    /// m:ss, or h:mm:ss from an hour.
    public static func clock(_ seconds: Double) -> String {
        let total = Int(seconds.rounded())
        let (h, m, s) = (total / 3600, total % 3600 / 60, total % 60)
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%d:%02d", m, s)
    }

    /// "62%" for a probability, nil when there is none.
    public static func chance(_ probability: Double?) -> String? {
        guard let probability else { return nil }
        if probability < 0.01 { return "under 1%" }
        if probability > 0.99 { return "over 99%" }
        return "\(Int((probability * 100).rounded()))%"
    }
}
