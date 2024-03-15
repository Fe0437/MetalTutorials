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
    
    ///edit this property to modify the camera of the deferred renderer
    @State var camera = MT3Camera()
    ///velocity of the camera
    let velocity = 0.1

    var body: some View {
        GeometryReader{ proxy in
            MT3DeferredMetalView(objName: "bunny", camera: $camera)
                .navigationTitle("Tutorial 3!")
                .gesture(
                    DragGesture()
                        .onChanged { gesture in
                            camera.rotation *= simd_quatf(angle: Float(velocity * gesture.translation.width/proxy.size.width), axis: SIMD3<Float>(0,1,0))
                            camera.rotation *= simd_quatf(angle: Float(velocity * gesture.translation.height/proxy.size.height), axis: SIMD3<Float>(1,0,0))
                        }
                )
        }
    }
}

#Preview {
    MT3ContentView()
}
