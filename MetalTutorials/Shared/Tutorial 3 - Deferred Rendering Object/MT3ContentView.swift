//
//  ContentView.swift
//  Shared
//
//  Created by federico forti on 04/03/2021.
//

import SwiftUI

struct MT3ContentView: View {
    var body: some View {
        MT3DeferredMetalView()
            .navigationTitle("Tutorial 3")
    }
}

struct MT3ContentView_Previews: PreviewProvider {
    static var previews: some View {
        MT3ContentView()
    }
}
