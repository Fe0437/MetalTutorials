//
//  ContentView.swift
//  Shared
//
//  Created by federico forti on 04/03/2021.
//

import SwiftUI

struct MT2ContentView: View {
    var body: some View {
        MT2SampleObjectMetalView(objName: "bunny")
            .navigationTitle("Tutorial 2!")
    }
}

struct MT2ContentView_Previews: PreviewProvider {
    static var previews: some View {
        MT2ContentView()
    }
}
