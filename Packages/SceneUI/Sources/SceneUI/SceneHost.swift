import SwiftUI

public struct SceneHost: View {
    public init() {}

    public var body: some View {
        Color(white: 0.96)
            .overlay(alignment: .topLeading) {
                Text("场景")
                    .font(.headline)
                    .padding(16)
            }
    }
}
