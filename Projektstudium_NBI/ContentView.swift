import SwiftUI

struct ContentView: View {
    @StateObject var manager = MultipeerManager()

    var body: some View {
        VStack(spacing: 20) {
            Text("👥 Peer-Name:")
            Text(manager.receivedPeerName)
                .font(.title2)
                .bold()

            Text("📡 Verbindung:")
            Text(manager.isConnected ? "✅ Verbunden" : "❌ Nicht verbunden")
                .foregroundColor(manager.isConnected ? .green : .red)

            if let distance = manager.distance {
                Text("📏 Entfernung: \(distance, specifier: "%.2f") m")
                    .font(.title)
            } else {
                Text("📏 Entfernung: Nicht verfügbar")
            }
        }
        .padding()
    }
}

