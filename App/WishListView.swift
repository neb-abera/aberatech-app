import AberaCore
import SwiftUI

/// Neb's wish list: what is still wanted, best first. Read-only.
struct WishListView: View {
    @Bindable var model: AppModel

    var body: some View {
        NavigationStack {
            List {
                if model.wishList.isEmpty {
                    ContentUnavailableView("Nothing wanted right now", systemImage: "gift")
                }
                ForEach(model.wishList) { item in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(item.item).font(.headline)
                        if let pick = item.pick { Text(pick).font(.subheadline) }
                        HStack(spacing: 8) {
                            if let price = item.price {
                                Text(price, format: .currency(code: "USD").precision(.fractionLength(0)))
                            }
                            if let window = item.buyWindow { Text(window) }
                            if let deadline = item.deadline { Text("by \(RequestDates.display(deadline))") }
                        }
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        if let link = item.link, let url = URL(string: link) {
                            Link("Where to buy", destination: url).font(.footnote)
                        }
                    }
                    .accessibilityIdentifier("wish-\(item.item)")
                }
            }
            .navigationTitle("Wish list")
            .refreshable { await model.loadWishList() }
        }
    }
}
