//
//  ContentView.swift
//  Shared
//
//  Created by federico forti on 04/03/2021.
//

import SwiftUI

struct MT4ContentView: View {
    var body: some View {
        MT4DeferredMetalView(objName: "bunny")
            .navigationTitle("Tutorial 4")
    }
}

struct MT4ContentView_Previews: PreviewProvider {
    static var previews: some View {
        MT4ContentView()
    }
}
