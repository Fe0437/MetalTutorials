//
//  ContentView.swift
//  Shared
//
//  Created by federico forti on 04/03/2021.
//

import SwiftUI

struct MT1ContentView: View {
    var body: some View {
        Text("Hello, Tutorial 1!")
            .padding()
        MT1Simple2DTriangleMetalView()
    }
}

struct MT1ContentView_Previews: PreviewProvider {
    static var previews: some View {
        MT1ContentView()
    }
}
