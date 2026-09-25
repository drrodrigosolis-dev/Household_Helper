import SwiftUI

struct ContentView: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "house.fill")
                .font(.system(size: 48))
                .foregroundStyle(.tint)
            Text("Household Helper")
                .font(.title2)
                .bold()
        }
        .padding()
    }
}

#Preview {
    ContentView()
}
