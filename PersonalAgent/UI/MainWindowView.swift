import SwiftUI

struct MainWindowView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("app.title")
                .font(.largeTitle)
                .fontWeight(.semibold)

            Text("app.stage")
                .font(.headline)
                .foregroundStyle(.secondary)

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                Text("app.next_step")
                    .font(.title3)
                    .fontWeight(.medium)

                Text("app.scope")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(28)
        .frame(minWidth: 520, minHeight: 320)
    }
}
