//
//  ContentView.swift
//  Shared
//
//  Created by federico forti on 04/03/2021.
//

import SwiftUI

/// Welcome ! 🤗
/// In this tutorial we are going to render a sample object stored in Resources as obj.
/// the default object to render is the standard Standford Bunny
struct MT2ContentView: View {
    var body: some View {
        MT2SampleObjectMetalView(objName: "bunny")
            .navigationTitle("Tutorial 2!")
    }
}


#Preview {
    MT2ContentView()
}
