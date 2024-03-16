//
//  MT6ContentView.swift
//  Shared
//
//  Created by federico forti on 04/03/2021.
//

import SwiftUI

/// Welcome ! 🤗
/// in this tutorial we are going to move all the rendering on the GPU, in this way we are going to leverage or the parallel computing power of the modern GPUs.
struct MT6ContentView: View {
    
    ///edit this property to modify the camera of the deferred renderer
    @State var camera = MT6Camera()
    ///velocity of the camera
    let velocity = 0.1
    
    @State var configs = MT6ModelConfigs()

    var body: some View {
        GeometryReader{ proxy in
            MT6DeferredMetalView(
                filename: "toy_biplane_idle.usdz",
                camera: $camera,
                configs: $configs)
                .navigationTitle("Tutorial 6!")
                .gesture(
                    DragGesture()
                        .onChanged { gesture in
                            camera.rotation *= simd_quatf(angle: Float(velocity * gesture.translation.width/proxy.size.width), axis: SIMD3<Float>(0,1,0))
                            camera.rotation *= simd_quatf(angle: Float(velocity * gesture.translation.height/proxy.size.height), axis: SIMD3<Float>(1,0,0))
                        }
                )
                .onTapGesture(count: 2, perform: {
                    configs.shouldRotateAroundBBox.toggle()
                })
        }
    }
}

#Preview {
    MT6ContentView()
}
