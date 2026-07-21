import SwiftUI

/// Shown when no ESV API key has been configured yet.
struct SetupView: View {
    var body: some View {
        VStack(spacing: 32) {
            Image(systemName: "book.closed")
                .font(.system(size: 80))
                .foregroundStyle(.secondary)

            Text("Almost there")
                .font(.largeTitle)

            VStack(alignment: .leading, spacing: 16) {
                Text("This app uses Crossway's free ESV API for scripture text and audio. To finish setup:")
                Text("1. Create a free account and API key at api.esv.org")
                Text("2. Open BibleTV/Support/Secrets.swift in Xcode")
                Text("3. Paste your key into Secrets.esvAPIKey")
                Text("4. Build and run again")
            }
            .font(.title3)
            .frame(maxWidth: 1000, alignment: .leading)
        }
        .padding(64)
    }
}

#Preview {
    SetupView()
}
