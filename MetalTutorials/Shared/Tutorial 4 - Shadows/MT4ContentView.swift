//
//  ContentView.swift
//  Shared
//
//  Created by federico forti on 04/03/2021.
//

import SwiftUI

/// Welcome ! 🤗
/// In this tutorial we are going to add a shadow with the shadow map
/// to our deferred renderer.
/// This pass is going to be done before the other passes of the deferred renderer
struct MT4ContentView: View {
    var body: some View {
        MT4DeferredMetalView(objName: "bunny")
            .navigationTitle("Tutorial 4")
    }
}

#Preview {
    MT4ContentView()
}
