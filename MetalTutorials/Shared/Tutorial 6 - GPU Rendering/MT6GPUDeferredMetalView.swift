//
//  MT6DeferredMetalView.swift
//  MetalTutorials
//

import SwiftUI
import MetalKit
import UIKit
 
/// 👥🖼️: UIViewRepresentable that creates a MTKView and a MT6GPUDeferredRenderer to render a 3D object.
struct MT6DeferredMetalView: UIViewRepresentable {
    typealias UIViewType = MTKView
    
    /// create the mtkview when you create this view
    /// Parameters:
    /// - objName: the name of the .obj file to load and render
    init(filename: String) {
        self.mtkView = MTKView()
        self.filename = filename

        guard let device = MTLCreateSystemDefaultDevice() else {
            fatalError( "Failed to get the system's default Metal device." )
        }
        
        mtkView.device = device
    }

    func makeUIView(context: UIViewRepresentableContext<MT6DeferredMetalView>) -> MTKView {
        mtkView.delegate = context.coordinator
        mtkView.preferredFramesPerSecond = 60
        mtkView.backgroundColor = context.environment.colorScheme == .dark ? UIColor.black : UIColor.white
        mtkView.isOpaque = true
        //in this case we want animation so we have to disable this (default is true)
        mtkView.enableSetNeedsDisplay = false
        return mtkView
    }
    
    func updateUIView(_ uiView: MTKView, context: UIViewRepresentableContext<MT6DeferredMetalView>) {
    }
    
    /// the coordinator is our renderer that manages drawing on the metalview
    func makeCoordinator() -> MT6GPUDeferredRenderer {
        let device = mtkView.device!
        let commandQueue = device.makeCommandQueue()!
        let scene = MT6Scene(device: device, commandQueue: commandQueue, assetFileName: filename)
        return MT6GPUDeferredRenderer(metalView: mtkView, commandQueue: commandQueue, scene: scene)
    }
    
    /// tutorial 2 - Sample object

    let filename:String
    
    /// tutorial 1 - Hello
    
    let mtkView:MTKView!
}
