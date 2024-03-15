//
//  ContentView.swift
//  Shared
//
//  Created by federico forti on 04/03/2021.
//

import SwiftUI

/// Welcome ! 🤗
/// In this tutorial we are going to add a shadow with the shadow map
/// to our deferred renderer.
/// This pass is going to be done before the other passes of the deferred renderer
struct MT4ContentView: View {
    
    ///edit this property to modify the camera of the deferred renderer
    @State var camera = MT4Camera()
    ///velocity of the camera
    let velocity = 0.1

    var body: some View {
        GeometryReader{ proxy in
            MT4DeferredMetalView(objName: "bunny", camera: $camera)
                .navigationTitle("Tutorial 4!")
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
    MT4ContentView()
}
