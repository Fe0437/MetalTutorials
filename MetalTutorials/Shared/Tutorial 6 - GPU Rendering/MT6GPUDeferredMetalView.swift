////
////  MetalViewController.swift
////  MetalTutorials
////
////  Created by federico forti on 04/03/2021.
////
//
//import SwiftUI
//import MetalKit
//import UIKit
//
///**
// 
// */
//struct MT6DeferredMetalView: UIViewRepresentable {
//    typealias UIViewType = MTKView
//    
//    /// create the mtkview when you create this view
//    init() {
//        mtkView = MTKView()
//
//        guard let device = MTLCreateSystemDefaultDevice() else {
//            fatalError( "Failed to get the system's default Metal device." )
//        }
//        
//        mtkView.device = device
//    }
//
//    func makeUIView(context: UIViewRepresentableContext<MT6DeferredMetalView>) -> MTKView {
//        mtkView.delegate = context.coordinator
//        mtkView.preferredFramesPerSecond = 60
//        mtkView.backgroundColor = context.environment.colorScheme == .dark ? UIColor.black : UIColor.white
//        mtkView.isOpaque = true
//        //in this case we want animation so we have to disable this (default is true)
//        mtkView.enableSetNeedsDisplay = false
//        return mtkView
//    }
//    
//    func updateUIView(_ uiView: MTKView, context: UIViewRepresentableContext<MT6DeferredMetalView>) {
//    }
//    
//    /// the coordinator is our renderer that manages drawing on the metalview
//    func makeCoordinator() -> MT6GPUDeferredRenderer {
//        return MT6GPUDeferredRenderer(metalView: mtkView, objName: "bunny")
//    }
//    
//    let mtkView:MTKView!
//}
