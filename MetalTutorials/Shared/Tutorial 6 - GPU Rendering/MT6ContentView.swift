//
//  MT6ContentView.swift
//  Shared
//
//  Created by federico forti on 04/03/2021.
//

import SwiftUI

/// Welcome ! 🤗
/// in this tutorial we are going to move all the rendering on the GPU, in this way we are going to leverage or the parallel computing power of the modern GPUs.
struct MT6ContentView: View {
    var body: some View {
        MT6DeferredMetalView(filename: "toy_biplane_idle.usdz")
            .navigationTitle("Tutorial 6")
    }
}

#Preview {
    MT6ContentView()
}
