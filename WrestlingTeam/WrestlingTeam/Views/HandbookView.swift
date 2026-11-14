import SwiftUI

struct HandbookView: View {
    @EnvironmentObject var store: PortalStore
    @State private var info: HandbookInfo?
    @State private var typed = ""
    @State private var working = false
    @State private var message: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    Card(title: "Team Handbook") {
                        if let info {
                            Text("Read the \(info.season) \(AppConfig.teamName) Handbook, then sign below.").foregroundStyle(Theme.gray)
                            if let url = URL(string: info.url) {
                                Link(destination: url) {
                                    Label("Open the Handbook (PDF)", systemImage: "doc.richtext").frame(maxWidth: .infinity).padding(.vertical, 6)
                                }
                                .buttonStyle(.bordered)
                            }
                            Divider()
                            if info.isSigned {
                                Label("Signed \(info.signed)", systemImage: "checkmark.seal.fill").foregroundStyle(Theme.ok).font(.headline)
                                if !info.typed.isEmpty { Text("Signature: \(info.typed)").font(.subheadline).foregroundStyle(Theme.gray) }
                            } else {
                                Text("I have read the \(info.season) \(AppConfig.teamName) Handbook and agree to follow it.").font(.subheadline)
                                TextField("Type your full name", text: $typed)
                                    .textContentType(.name).textInputAutocapitalization(.words)
                                    .padding(12).background(Theme.soft, in: RoundedRectangle(cornerRadius: 10))
                                Button { Task { await sign() } } label: {
                                    HStack { if working { ProgressView().tint(.white) }; Text("Sign Off") }.frame(maxWidth: .infinity)
                                }
                                .buttonStyle(.borderedProminent).tint(Theme.red).controlSize(.large)
                                .disabled(typed.trimmingCharacters(in: .whitespaces).count < 3 || working)
                            }
                            if let message { Text(message).font(.footnote).foregroundStyle(Theme.red) }
                        } else if let message {
                            Text(message).foregroundStyle(Theme.red)
                        } else {
                            ProgressView()
                        }
                    }
                }
                .padding()
                .readableWidth()
            }
            .screenBackground()
            .navigationTitle("Handbook")
            .teamLogo()
            .navigationBarTitleDisplayMode(.inline)
            .task { await load() }
            .refreshable { await load() }
        }
    }

    private func load() async {
        do { info = try await store.api.handbook(); message = nil }
        catch { message = error.localizedDescription }
    }

    private func sign() async {
        working = true
        defer { working = false }
        do {
            _ = try await store.api.signHandbook(typed: typed)
            await load()
            await store.load()   // unlocks the descent plan
        } catch {
            message = error.localizedDescription
        }
    }
}
