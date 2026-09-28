import SwiftUI

struct ActivityView: View {
    let store: AppStore

    var body: some View {
        List(store.activity) { entry in
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: entry.isError ? "exclamationmark.triangle.fill" : "checkmark.circle")
                    .foregroundStyle(entry.isError ? .orange : .secondary)
                VStack(alignment: .leading, spacing: 3) {
                    Text(entry.message)
                    Text(entry.date, style: .time)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 4)
        }
        .overlay {
            if store.activity.isEmpty {
                ContentUnavailableView("No activity yet", systemImage: "list.bullet.rectangle")
            }
        }
        .navigationTitle("Activity")
    }
}
