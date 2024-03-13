//
//  ContentView.swift
//  Shared
//
//  Created by federico forti on 04/03/2021.
//

import SwiftUI

/// Welcome ! 🤗
/// In this tutorial we are going to use tile rendering for our deferred renderer.
/// Using tile rendering we can avoid creating multiple passes to create the textures necessary for deferred rendering because those textures are going to be computed per tile.
struct MT5ContentView: View {
    var body: some View {
        MT5DeferredMetalView(objName: "bunny")
            .navigationTitle("Tutorial 5")
    }
}

#Preview {
    MT5ContentView()
}

