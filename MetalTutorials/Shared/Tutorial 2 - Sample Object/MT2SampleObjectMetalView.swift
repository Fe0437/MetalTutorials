//
//  MetalViewController.swift
//  MetalTutorials
//
//  Created by federico forti on 04/03/2021.
//

import SwiftUI
import MetalKit
import UIKit

/// 👥🖼️: UIViewRepresentable that creates a MTKView and a MT2ObjRenderer to render a 3D object.
struct MT2SampleObjectMetalView: UIViewRepresentable {
    typealias UIViewType = MTKView
    
    /// create the mtkview when you create this view
    /// Parameters:
    /// - objName: the name of the .obj file to load and render
    init(objName: String) {
        self.mtkView = MTKView()
        self.objName = objName

        guard let device = MTLCreateSystemDefaultDevice() else {
            fatalError( "Failed to get the system's default Metal device." )
        }
        
        mtkView.device = device
    }

    func makeUIView(context: UIViewRepresentableContext<MT2SampleObjectMetalView>) -> MTKView {
        mtkView.delegate = context.coordinator
        mtkView.preferredFramesPerSecond = 60
        mtkView.backgroundColor = context.environment.colorScheme == .dark ? UIColor.black : UIColor.white
        mtkView.isOpaque = true
        //in this case we want animation so we have to disable this (default is true)
        mtkView.enableSetNeedsDisplay = false
        return mtkView
    }
    
    func updateUIView(_ uiView: MTKView, context: UIViewRepresentableContext<MT2SampleObjectMetalView>) {
    }
    
    /// the coordinator is our renderer that manages drawing on the metalview
    func makeCoordinator() -> MT2ObjRenderer {
        return MT2ObjRenderer(metalView: mtkView, objName: objName)
    }

    /// tutorial 2 - Sample object

    let objName:String
    
    /// tutorial 1 - Hello
    
    let mtkView:MTKView!
}
