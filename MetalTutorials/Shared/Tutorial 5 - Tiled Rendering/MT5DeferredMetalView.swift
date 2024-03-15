//
//  MT5DeferredMetalView.swift
//  MetalTutorials
//
//  Created by federico forti on 04/03/2021.
//

import SwiftUI
import MetalKit
import UIKit
 
/// 🌎 protocol that manages public configuration of the scene
protocol MT5SceneDelegate {
    func setLightPosition(_ lightPosition: SIMD3<Float>)
    func setModelConfigs(_ modelConfigs: MT5ModelConfigs)
    func setCamera(camera: MT5Camera)
}

/// 👥🖼️: UIViewRepresentable that creates a MTKView and a MT5DeferredRenderer to render a 3D object.
struct MT5DeferredMetalView: UIViewRepresentable {
    
    class SceneView: MTKView {
        var sceneDelegate: MT5SceneDelegate? = nil
    }
    typealias UIViewType = SceneView
    
    @Binding var camera : MT5Camera
    
    /// create the mtkview when you create this view
    /// Parameters:
    /// - objName: the name of the .obj file to load and render
    /// - camera: the camera binding, when this is edit the renderer is going to update the uniform matrices
    init(objName: String, camera : Binding<MT5Camera> = .constant(MT5Camera())) {
        self.sceneView = SceneView()
        self.objName = objName
        self._camera = camera
        guard let device = MTLCreateSystemDefaultDevice() else {
            fatalError( "Failed to get the system's default Metal device." )
        }
        
        sceneView.device = device
    }

    func makeUIView(context: UIViewRepresentableContext<MT5DeferredMetalView>) -> SceneView {
        sceneView.delegate = context.coordinator
        sceneView.sceneDelegate = context.coordinator
        sceneView.preferredFramesPerSecond = 60
        sceneView.backgroundColor = context.environment.colorScheme == .dark ? UIColor.black : UIColor.white
        sceneView.isOpaque = true
        //in this case we want animation so we have to disable this (default is true)
        sceneView.enableSetNeedsDisplay = false
        return sceneView
    }
    
    func updateUIView(_ uiView: SceneView, context: UIViewRepresentableContext<MT5DeferredMetalView>) {
        sceneView.sceneDelegate?.setCamera(camera: camera)
    }
    
    /// the coordinator is our renderer that manages drawing on the metalview
    func makeCoordinator() -> MT5TiledDeferredRenderer {
        return MT5TiledDeferredRenderer(metalView: sceneView, objName: objName)
    }
    
    /// tutorial 2 - Sample object

    let objName:String
    
    /// tutorial 1 - Hello
    
    let sceneView: SceneView
}
