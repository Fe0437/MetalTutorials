//
//  MT6DeferredMetalView.swift
//  MetalTutorials
//

import SwiftUI
import MetalKit
import UIKit

/// 🌎 protocol that manages public configuration of the scene
protocol MT6SceneDelegate {
    func setLightPosition(_ lightPosition: SIMD3<Float>)
    func setModelConfigs(_ modelConfigs: MT6ModelConfigs)
    func setCamera(camera: MT6Camera)
}
 
/// 👥🖼️: UIViewRepresentable that creates a MTKView and a MT6GPUDeferredRenderer to render a 3D object.
struct MT6DeferredMetalView: UIViewRepresentable {
    
    class SceneView: MTKView {
        var sceneDelegate: MT6SceneDelegate? = nil
    }
    typealias UIViewType = SceneView
    
    @Binding var camera : MT6Camera
    
    /// create the mtkview when you create this view
    /// Parameters:
    /// - filename: name of the file to load in the renderer
    /// - camera: binding to position the camera on the metal renderer
    init(filename: String, camera : Binding<MT6Camera> = .constant(MT6Camera())) {
        self._camera = camera
        self.sceneView = SceneView()
        self.filename = filename

        guard let device = MTLCreateSystemDefaultDevice() else {
            fatalError( "Failed to get the system's default Metal device." )
        }
        
        sceneView.device = device
    }

    func makeUIView(context: UIViewRepresentableContext<MT6DeferredMetalView>) -> SceneView {
        sceneView.delegate = context.coordinator
        sceneView.sceneDelegate = context.coordinator.scene
        sceneView.preferredFramesPerSecond = 60
        sceneView.backgroundColor = context.environment.colorScheme == .dark ? UIColor.black : UIColor.white
        sceneView.isOpaque = true
        //in this case we want animation so we have to disable this (default is true)
        sceneView.enableSetNeedsDisplay = false
        return sceneView
    }
    
    func updateUIView(_ uiView: SceneView, context: UIViewRepresentableContext<MT6DeferredMetalView>) {
        uiView.sceneDelegate?.setCamera(camera: camera)
    }
    
    /// the coordinator is our renderer that manages drawing on the metalview
    func makeCoordinator() -> MT6GPUDeferredRenderer {
        let device = sceneView.device!
        let commandQueue = device.makeCommandQueue()!
        let scene = MT6Scene(device: device, commandQueue: commandQueue, assetFileName: filename)
        return MT6GPUDeferredRenderer(metalView: sceneView, commandQueue: commandQueue, scene: scene)
    }
    
    /// tutorial 2 - Sample object

    let filename:String
    
    /// tutorial 1 - Hello
    
    let sceneView: SceneView!
}
