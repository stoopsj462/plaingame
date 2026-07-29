//
//  ContentView.swift
//  plaingame
//
//  Hosts the SpriteKit game scene.
//

import SwiftUI
import SpriteKit

struct ContentView: View {
    // Create the scene once. `.resizeFill` lets it adapt to any view size
    // (rotation, window resize) without being recreated.
    @State private var scene: GameScene = {
        let scene = GameScene(size: CGSize(width: 1024, height: 768))
        scene.scaleMode = .resizeFill
        return scene
    }()

    var body: some View {
        SpriteView(scene: scene)
            .ignoresSafeArea()
    }
}

#Preview {
    ContentView()
}
