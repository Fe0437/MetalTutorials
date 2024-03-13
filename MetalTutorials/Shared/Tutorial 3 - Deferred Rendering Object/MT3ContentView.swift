//
//  ContentView.swift
//  Shared
//
//  Created by federico forti on 04/03/2021.
//

import SwiftUI

/// Welcome ! 🤗
/// In this tutorial we are going to create a deferred renderer for our object
struct MT3ContentView: View {
    var body: some View {
        MT3DeferredMetalView(objName: "bunny")
            .navigationTitle("Tutorial 3!")
    }
}

#Preview {
    MT3ContentView()
}
