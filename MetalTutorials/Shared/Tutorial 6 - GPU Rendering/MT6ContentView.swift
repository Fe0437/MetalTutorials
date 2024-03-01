//
//  MT6ContentView.swift
//  Shared
//
//  Created by federico forti on 04/03/2021.
//

import SwiftUI

struct MT6ContentView: View {
    var body: some View {
        MT6DeferredMetalView(filename: "toy_biplane_idle.usdz")
            .navigationTitle("Tutorial 6")
    }
}

struct MT6ContentView_Previews: PreviewProvider {
    static var previews: some View {
        MT6ContentView()
    }
}
