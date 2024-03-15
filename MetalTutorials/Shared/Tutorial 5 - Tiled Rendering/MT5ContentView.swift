//
//  ContentView.swift
//  Shared
//
//  Created by federico forti on 04/03/2021.
//

import SwiftUI

/// Welcome ! 🤗
/// In this tutorial we are going to use tile rendering for our deferred renderer.
/// Using tile rendering we can avoid creating multiple passes to create the textures necessary for deferred rendering because those textures are going to be computed per tile.
struct MT5ContentView: View {
    ///edit this property to modify the camera of the deferred renderer
    @State var camera = MT5Camera()
    ///velocity of the camera
    let velocity = 0.1

    var body: some View {
        GeometryReader{ proxy in
            MT5DeferredMetalView(objName: "bunny", camera: $camera)
                .navigationTitle("Tutorial 5!")
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
    MT5ContentView()
}

