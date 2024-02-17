//
//  ContentView.swift
//  Shared
//
//  Created by federico forti on 04/03/2021.
//

import SwiftUI

struct MT5ContentView: View {
    var body: some View {
        MT5DeferredMetalView()
            .navigationTitle("Tutorial 5")
    }
}

struct MT5ContentView_Previews: PreviewProvider {
    static var previews: some View {
        MT5ContentView()
    }
}
