//
//  MT1Simple2DTriangleMetalView.swift
//  MetalTutorials
//
//  Created by federico forti on 04/03/2021.
//

import SwiftUI
import MetalKit
import UIKit

/**
This is a simple 2D triangle rendered using Metal.
 - 👥 🖼 : this class is also a UIViewRepresentable which is used to create a SwiftUI view from the MTKView UIKit class.
 - 🥷 : inside the MTKView there is a MTRenderer that is the class that manages the rendering of the triangle, through the MTKViewDelegate interface.
 */
struct MT1Simple2DTriangleMetalView: UIViewRepresentable {
    typealias UIViewType = MTKView
    
    /**
      Main class that is managing all the rendering of the view.
      It is intialized with the parent MetalView that use also to take the mtkview
     */
    class MTRenderer : NSObject, MTKViewDelegate {
            
        /**
            during the initialization the pipeline and the command queue is created
         */
            init(metalView: MTKView) {
                _metalView = metalView
                _device = _metalView.device
                
                let library = _device.makeDefaultLibrary()!
                
                //create the vertex and fragment shaders
                let vertexFunction = library.makeFunction(name: "MT1::VertexShader")
                let fragmentFunction = library.makeFunction(name: "MT1::FragmentShader")
                
                //create the pipeline we will run during draw
                //this pipeline will use the vertex and fragment shader we have defined here
                let rndPipStatDescriptor = MTLRenderPipelineDescriptor()
                rndPipStatDescriptor.label = "Tutorial1 Simple Pipeline"
                rndPipStatDescriptor.vertexFunction = vertexFunction
                rndPipStatDescriptor.fragmentFunction = fragmentFunction
                rndPipStatDescriptor.colorAttachments[0].pixelFormat = _metalView.colorPixelFormat
                do {
                    _pipelineState = try _device.makeRenderPipelineState(descriptor: rndPipStatDescriptor)
                }
                catch
                {
                    _pipelineState = nil
                    print(error)
                }
                
                // create the command queue
                _commandQueue = _device.makeCommandQueue()
                
            }

            ///whenever the size changes or orientation changes
            func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
                _viewportSize.x = UInt32(size.width)
                _viewportSize.y = UInt32(size.height)
            }
            
            ///here you create a command buffer
            ///encode commands that tells to the gpu what to draw
            func draw(in view: MTKView) {
                
                /// triangle definition 2D
                let triangleVertices:[MT1Vertex] = [
                        // 2D positions,                                     RGBA colors
                    MT1Vertex(position:  vector_float2(250,  -250), color: vector_float4(1, 0, 0, 1 )),
                    MT1Vertex(position: vector_float2(-250,  -250), color: vector_float4(0, 1, 0, 1 )),
                    MT1Vertex(position: vector_float2(   0,   250), color: vector_float4(0, 0, 1, 1 ))
                    ]
                
                /// create the new command buffer for this pass
                let commandBuffer = _commandQueue.makeCommandBuffer()!
                commandBuffer.label = "Tutorial1Commands"
                
                if let passDesc = view.currentRenderPassDescriptor {
                    
                    // now creates a render command encoder to start
                    // encoding of rendering commands
                    let commandEncoder:MTLRenderCommandEncoder! = commandBuffer.makeRenderCommandEncoder(descriptor: passDesc)
                    commandEncoder.label = "Tutorial1RenderCommandEncoder"
                    
                    ///here we have start magic
                    
                    // init the MTLViewport from the metal library
                    let viewport = MTLViewport(originX: 0.0, originY: 0.0, width: Double(_viewportSize.x), height: Double(_viewportSize.y), znear: 0.0, zfar: 1.0)
                    commandEncoder.setViewport(viewport)
                    
                    commandEncoder.setRenderPipelineState(_pipelineState!)
                                    
                    commandEncoder.setVertexBytes(triangleVertices, length: MemoryLayout<MT1Vertex>.size*3 , index: 0 )
                    
                    commandEncoder.setVertexBytes(&_viewportSize, length: MemoryLayout<vector_uint2>.size, index: 1)
                    
                    commandEncoder.drawPrimitives(type: MTLPrimitiveType.triangle, vertexStart: 0, vertexCount: 3)
                    
                    ///here we end the magic

                    commandEncoder.endEncoding()
                    
                    let drawable:MTLDrawable! = view.currentDrawable
                    commandBuffer.present(drawable)
                    commandBuffer.commit()
                }
            }

        // tutorial 1 - Hello 

        // passed as input 
        let _metalView:MTKView!
        let _device:MTLDevice!
        
        // the command queue permits tus to create a new command buffer that will be executed by the GPU. 
        let _commandQueue:MTLCommandQueue!
        // pipeline state completely defines the state of the GPU for the next draw. 
        // for example the vertex and fragment shaders, the color attachment, the depth and stencil state...
        let _pipelineState:MTLRenderPipelineState?

        // here we force the size of the viewport
        var _viewportSize = vector_uint2(100,100)
        }
    
    /// create the mtkview when you create this view
    init() {
        mtkView = MTKView()
        
        guard let device = MTLCreateSystemDefaultDevice() else {
            fatalError( "Failed to get the system's default Metal device." )
        }
        
        mtkView.device = device
    }

    /// create the UIView associated with this UIViewRepresentable.
    func makeUIView(context: UIViewRepresentableContext<MT1Simple2DTriangleMetalView>) -> MTKView {
        mtkView.delegate = context.coordinator
        mtkView.preferredFramesPerSecond = 60
        mtkView.backgroundColor = context.environment.colorScheme == .dark ? UIColor.black : UIColor.white
        mtkView.isOpaque = true
        mtkView.enableSetNeedsDisplay = true
        return mtkView
    }
    
    func updateUIView(_ uiView: MTKView, context: UIViewRepresentableContext<MT1Simple2DTriangleMetalView>) {
    }
    
    /// the coordinator is our renderer that manages drawing on the metalview
    func makeCoordinator() -> MTRenderer {
        return MTRenderer(metalView: mtkView)
    }
    
    let mtkView:MTKView!
}
