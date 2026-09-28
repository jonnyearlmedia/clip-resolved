import SwiftUI

enum ClipResolvedDesign {
    static let compactSpacing: CGFloat = 8
    static let controlSpacing: CGFloat = 12
    static let sectionSpacing: CGFloat = 20
    static let pagePadding: CGFloat = 24
    static let contentMaxWidth: CGFloat = 1_040
    static let readableWidth: CGFloat = 760
    static let inspectorMinWidth: CGFloat = 320
    static let inspectorIdealWidth: CGFloat = 420
    static let inspectorMaxWidth: CGFloat = 600
    static let cornerRadius: CGFloat = 10
}

struct PageHeader: View {
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(.largeTitle.weight(.semibold))
            Text(subtitle)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct ProjectPicker: View {
    @Bindable var store: AppStore

    var body: some View {
        Picker("Project", selection: $store.selectedProjectID) {
            ForEach(store.projects) { project in
                Text(project.name).tag(Optional(project.id))
            }
        }
        .labelsHidden()
        .frame(minWidth: 180, idealWidth: 260, maxWidth: 340)
        .accessibilityLabel("Project")
    }
}
