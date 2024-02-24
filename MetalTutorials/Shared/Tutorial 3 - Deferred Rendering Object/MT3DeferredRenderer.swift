//
//  MT3Renderer.swift
//  MetalTutorials
//
//  Created by federico forti on 14/03/2021.
//

import MetalKit
import ModelIO

//use for future and promises
import Combine
import simd

/// tutorial 3 - deferred rendering

/// 🥷: Main class that is managing all the rendering of the view.
///🧩🧩🧩 ⏩️ 🖼️: rendering a .obj and a point light in a deferred rendering pipeline.
class MT3DeferredRenderer : NSObject, MTKViewDelegate {
     
    
    /// initialize the renderer with the metal view and the obj name
    init(metalView: MTKView, objName:String) {
        
        _metalView = metalView
        // Set the pixel formats of the render destination.
        _metalView.depthStencilPixelFormat = .depth32Float
        _metalView.colorPixelFormat = .bgra8Unorm_srgb
        
        _device = _metalView.device
        
        // create the command queue
        _commandQueue = _device.makeCommandQueue()
        
        let meshAsset = MT3DeferredRenderer._loadObj(
            objName: objName,
            device: _device
        )
        // depth stencil
        _depthStencilState = Self._buildDepthStencilState(device: _device)
        
        // Create quad for fullscreen composition drawing
        // this is going to be used in the last stage
        let quadVertices: [MT3BasicVertex] = [
            .init(position: .init(x: -1, y: -1)),
            .init(position: .init(x: -1, y:  1)),
            .init(position: .init(x:  1, y: -1)),
            
            .init(position: .init(x:  1, y: -1)),
            .init(position: .init(x: -1, y:  1)),
            .init(position: .init(x:  1, y:  1))
        ]
        
        quadVertexBuffer = .init(device: _device, array: quadVertices)
        
        super.init()
        
        _library = _device.makeDefaultLibrary()
        _retrieveDataFromAsset(meshAsset)
    }
    
     /// class public configurations \{
    
    struct ModelConfigs
    {
        var shouldRotateAroundBBox: Bool = true
    }
    
    struct Camera
    {
        var lookAt: (origin:SIMD3<Float>, target:SIMD3<Float>)
        var fov: Float
        var aspectRatio: Float
        var nearZ: Float
        var farZ: Float
    }


    func setLightPosition(_ lightPosition: SIMD3<Float>)
    {
        _optionalLightPosition = lightPosition;
    }
    
    func setModelConfigs(_ modelConfigs: ModelConfigs)
    {
        _modelConfigs = modelConfigs
    }
    
    func setCamera(camera:Camera)
    {
        _optionalCamera = camera
    }

    /// \}

    /// MTKViewDelegate \{
    
    ///whenever the size changes or orientation changes build the pipelines and store the new size
    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        
        _viewportSize.x = UInt32(size.width)
        _viewportSize.y = UInt32(size.height)
                
        //create gBuffer textures
        let albedoDesc = MTLTextureDescriptor
            .texture2DDescriptor(pixelFormat: .bgra8Unorm,
                                 width: Int(size.width),
                                 height: Int(size.height),
                                 mipmapped: false)
        albedoDesc.textureType = .type2D
        albedoDesc.usage = [.shaderRead, .renderTarget]
        albedoDesc.storageMode = .private
        
        guard let albedoSpecular = _device.makeTexture(descriptor: albedoDesc) else {
            fatalError("cannot create albedo texture")
        }
        albedoSpecular.label = "Albedo GBuffer Texture"
        
        let gBufferTextureDesc = MTLTextureDescriptor
            .texture2DDescriptor(pixelFormat: .rgba16Float,
                                 width: Int(size.width),
                                 height: Int(size.height),
                                 mipmapped: false)
        gBufferTextureDesc.textureType = .type2D
        gBufferTextureDesc.usage = [.shaderRead, .renderTarget]
        gBufferTextureDesc.storageMode = .private
        
        guard let normal = _device.makeTexture(descriptor: gBufferTextureDesc) else {
            fatalError("cannot create normal texture")
        }
        normal.label = "Normal GBuffer Texture"
        
        guard let depthPosition = _device.makeTexture(descriptor: gBufferTextureDesc) else {
            fatalError("cannot create depthPosition texture")
        }
        depthPosition.label = "Albedo depthPosition Texture"
        
        _gBuffer = GBuffer(albedoSpecular: albedoSpecular, normal: normal, depth: depthPosition)
        
        //create pipeline
        
        _gBuffPipelineState = _buildPipeline(
            vertexFunction: "MT3::vertex_main",
            fragmentFunction: "MT3::gbuffer_fragment",
            label: "GBufferPSO"
        ){ descriptor in
            descriptor.colorAttachments[Int(MT3RenderTargetAlbedo.rawValue)]?.pixelFormat = albedoDesc.pixelFormat
            descriptor.colorAttachments[Int(MT3RenderTargetNormal.rawValue)]?.pixelFormat = gBufferTextureDesc.pixelFormat
            descriptor.colorAttachments[Int(MT3RenderTargetDepth.rawValue)]?.pixelFormat = gBufferTextureDesc.pixelFormat
            descriptor.depthAttachmentPixelFormat = _metalView.depthStencilPixelFormat
        }
        
        _displayPipelineState = _buildPipeline(
            vertexFunction: "MT3::display_vertex",
            fragmentFunction: "MT3::deferred_lighting_fragment",
            label: "DeferredLightingPSO"
        ){ descriptor in
            
            //they have to match
            descriptor.colorAttachments[0].pixelFormat = _metalView.colorPixelFormat
                        
            //they have to match
            descriptor.depthAttachmentPixelFormat = _metalView.depthStencilPixelFormat
        }
    }
    
    ///here you create a command buffer
    ///encode commands that tells to the gpu what to draw
    func draw(in view: MTKView) {
    
        _computeCurrentRotationAngle()
        _render(with: view)
    }

    /// \}


    /// private \{
    
    /// GBuffer textures which are going to used to store the information of the scene
    struct GBuffer {
        let albedoSpecular: MTLTexture
        let normal : MTLTexture
        let depth : MTLTexture
    }

    private func _render(with view: MTKView) {
        /// create the new command buffer for this pass

        let commandBuffer = _commandQueue.makeCommandBuffer()!
        commandBuffer.label = "Tutorial3Commands"
        
        let gBufferPassDescriptor: MTLRenderPassDescriptor = {
            let descriptor = MTLRenderPassDescriptor()
            descriptor.colorAttachments[Int(MT3RenderTargetAlbedo.rawValue)].loadAction = .clear
            descriptor.colorAttachments[Int(MT3RenderTargetAlbedo.rawValue)].storeAction = .store
            descriptor.colorAttachments[Int(MT3RenderTargetAlbedo.rawValue)].texture = _gBuffer.albedoSpecular
            
            descriptor.colorAttachments[Int(MT3RenderTargetNormal.rawValue)].loadAction = .clear
            descriptor.colorAttachments[Int(MT3RenderTargetNormal.rawValue)].storeAction = .store
            descriptor.colorAttachments[Int(MT3RenderTargetNormal.rawValue)].texture = _gBuffer.normal
            
            descriptor.colorAttachments[Int(MT3RenderTargetDepth.rawValue)].loadAction = .clear
            descriptor.colorAttachments[Int(MT3RenderTargetDepth.rawValue)].storeAction = .store
            descriptor.colorAttachments[Int(MT3RenderTargetDepth.rawValue)].texture = _gBuffer.depth
            
            descriptor.depthAttachment.loadAction = .clear
            descriptor.depthAttachment.texture = view.depthStencilTexture
            descriptor.depthAttachment.storeAction = .dontCare
            return descriptor
        }()
        
        var uniforms = _buildUniforms(view)

        _encodePass(into: commandBuffer, using: gBufferPassDescriptor, label: "GBuffer Pass")
        { commandEncoder in
            
            commandEncoder.setVertexBytes(&uniforms.0, length: MemoryLayout<MT3VertexUniforms>.size, index: 1)
            commandEncoder.setFragmentBytes(&uniforms.1, length: MemoryLayout<MT3FragmentUniforms>.size, index: 1)
            
            // init the MTLViewport from the metal library
            let viewport = _buildViewport()
            commandEncoder.setViewport(viewport)
            commandEncoder.setRenderPipelineState(_gBuffPipelineState)
            commandEncoder.setDepthStencilState(_depthStencilState)
            
            // real drawing of the primitive
            for mesh in _meshes {
                let vertexBuffer = mesh.vertexBuffers.first!
                //[[attribute(0)]]
                commandEncoder.setVertexBuffer(vertexBuffer.buffer, offset: vertexBuffer.offset, index: 0)
                
                for submesh in mesh.submeshes {
                    let indexBuffer = submesh.indexBuffer
                    commandEncoder.drawIndexedPrimitives(type: submesh.primitiveType,
                                                         indexCount: submesh.indexCount,
                                                         indexType: submesh.indexType,
                                                         indexBuffer: indexBuffer.buffer,
                                                         indexBufferOffset: indexBuffer.offset)
                }
            }
        }
        
        //lets use the same command buffer for now
        
        if let drawable = view.currentDrawable {
            
            let viewPassDesc = view.currentRenderPassDescriptor!
            
            _encodePass(into: commandBuffer, using: viewPassDesc, label: "Deferred Lighting Pass")
            { renderEncoder in
                
                renderEncoder.setRenderPipelineState(_displayPipelineState)
                renderEncoder.setDepthStencilState(_displayDepthStencilState)
                
                //set g buffer textures
                renderEncoder.setFragmentTexture(_gBuffer.albedoSpecular, index: Int(MT3RenderTargetAlbedo.rawValue))
                renderEncoder.setFragmentTexture(_gBuffer.normal, index: Int(MT3RenderTargetNormal.rawValue))
                renderEncoder.setFragmentTexture(_gBuffer.depth, index: Int(MT3RenderTargetDepth.rawValue))
                renderEncoder.setFragmentBytes(&uniforms.1, length: MemoryLayout<MT3FragmentUniforms>.size, index: 1)

                renderEncoder.setCullMode(.back)
                renderEncoder.setStencilReferenceValue(128)
                
                renderEncoder.setVertexBuffer(quadVertexBuffer,
                                              offset: 0,
                                              index: Int(MT3BufferIndexMeshPositions.rawValue))
                // Draw full screen quad
                renderEncoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 6)
            }
            
            commandBuffer.present(drawable)
        }
        
        commandBuffer.commit()
    }

    
    private func _retrieveDataFromAsset(_ meshAsset: MDLAsset) {
        do {
            (_, _meshes) = try MTKMesh.newMeshes(asset: meshAsset, device: _device)
        } catch {
            fatalError("Could not extract meshes from Model I/O asset")
        }
        
        /// Model I/O’s vertex descriptor type and Metal’s vertex descriptor type
        _vertexDescriptor = MTKMetalVertexDescriptorFromModelIO(meshAsset.vertexDescriptor!)
        _objboundingBox = meshAsset.boundingBox
    }
    
    private func _computeCurrentRotationAngle() {
        let time = CACurrentMediaTime()
        
        if _currentTime != nil {
            let elapsed = time - _currentTime!
            _currentAngle -= elapsed
        }
        _currentTime = time
    }

    
    private class func _loadObj(objName :String, device: MTLDevice) -> MDLAsset
    {
        let modelURL = Bundle.main.url(forResource: objName, withExtension: "obj")!
        
        //setup vertex position, normal and uv
        let vertexDescriptor = MDLVertexDescriptor()
        vertexDescriptor.attributes[0] = MDLVertexAttribute(name: MDLVertexAttributePosition, format: .float3, offset: 0, bufferIndex: 0)
        vertexDescriptor.attributes[1] = MDLVertexAttribute(name: MDLVertexAttributeNormal, format: .float3, offset: MemoryLayout<Float>.size * 3, bufferIndex: 0)
        vertexDescriptor.attributes[2] = MDLVertexAttribute(name: MDLVertexAttributeTextureCoordinate, format: .float2, offset: MemoryLayout<Float>.size * 6, bufferIndex: 0)
        vertexDescriptor.layouts[0] = MDLVertexBufferLayout(stride: MemoryLayout<Float>.size * 8)
        
        let bufferAllocator = MTKMeshBufferAllocator(device: device)
        
        /*
         An asset can contain many things, including lights, cameras, and meshes. For now, we just care about the meshes
         */
        let meshAsset = MDLAsset(url: modelURL, vertexDescriptor: vertexDescriptor, bufferAllocator: bufferAllocator)
        
        return meshAsset
        
    }
    
    private func _buildUniforms(_ view:MTKView) -> (MT3VertexUniforms, MT3FragmentUniforms)
    {
        var modelMatrix:float4x4?
        if(_modelConfigs.shouldRotateAroundBBox)
        {
            let center = (_objboundingBox.maxBounds + _objboundingBox.minBounds)*0.5
            
            //model to world
            modelMatrix =
                float4x4(rotationAbout: SIMD3<Float>(0, 1, 0), by: Float(_currentAngle)) * float4x4(translationBy: -center)
        }
        
        //world to camera view
        var viewMatrix:float4x4!
        var projectionMatrix: float4x4!
        var aspectRatio: Float!
        if let camera = _optionalCamera
        {
            viewMatrix = float4x4(origin: camera.lookAt.origin, target: camera.lookAt.target, up: SIMD3<Float>(0,1,0))
            aspectRatio = camera.aspectRatio
            projectionMatrix = float4x4(perspectiveProjectionFov: camera.fov, aspectRatio: aspectRatio, nearZ: camera.nearZ, farZ: camera.farZ)
        }
        else
        {
            //default construction
            let extent = _objboundingBox.maxBounds - _objboundingBox.minBounds;
            viewMatrix = float4x4(translationBy: SIMD3<Float>(0, 0, -(2+extent.z)))
            aspectRatio = Float(view.drawableSize.width / view.drawableSize.height)
            projectionMatrix = float4x4(perspectiveProjectionFov: Float.pi / 3, aspectRatio: aspectRatio, nearZ: 0.1, farZ: 100)
        }
        
        
        let modelView = modelMatrix != nil ? viewMatrix! * modelMatrix! : viewMatrix!
        let modelViewProjection = projectionMatrix * modelView
        
        // transformations necessary to handle correctly normals
        // @see https://www.scratchapixel.com/lessons/mathematics-physics-for-computer-graphics/geometry/transforming-normals
        let indeces = SIMD3<Int>(0,1,2)
        let modelViewInverseTransposeMatrix = float3x3(
                                    modelView.columns.0[indeces],
                                    modelView.columns.1[indeces],
                                    modelView.columns.2[indeces]).transpose.inverse
        
        let lightPosition = _optionalLightPosition ?? _objboundingBox.maxBounds + SIMD3<Float>(100,0,30)
        
        let viewLightPosition =  viewMatrix * SIMD4<Float>(lightPosition, 1);
        
        let vertexUniforms = MT3VertexUniforms(
            modelViewMatrix: modelView,
            modelViewInverseTransposeMatrix: modelViewInverseTransposeMatrix,
            modelViewProjectionMatrix: modelViewProjection
        )
        
        let fragmentUniforms = MT3FragmentUniforms(viewLightPosition: viewLightPosition)
        
        return (vertexUniforms, fragmentUniforms)
    }
    
    private func _buildViewport() -> MTLViewport {
        return MTLViewport(originX: 0.0, originY: 0.0, width: Double(_viewportSize.x), height: Double(_viewportSize.y), znear: 0.0, zfar: 1.0)
    }
    
    
    private func _buildPipeline(
        vertexFunction:String, fragmentFunction:String, label: String, customize: (MTLRenderPipelineDescriptor) -> Void) -> MTLRenderPipelineState  {
        
        //create the vertex and fragment shaders_
        let vertexFunction = _library.makeFunction(name: vertexFunction)
        let fragmentFunction = _library.makeFunction(name: fragmentFunction)
        
        //create the pipeline we will run during draw
        //this pipeline will use the vertex and fragment shader we have defined here
        let rndPipStatDescriptor = MTLRenderPipelineDescriptor()
        rndPipStatDescriptor.label = label
        rndPipStatDescriptor.vertexFunction = vertexFunction
        rndPipStatDescriptor.fragmentFunction = fragmentFunction
        
        //this time we need this otherwise
        rndPipStatDescriptor.vertexDescriptor = _vertexDescriptor
            
        customize(rndPipStatDescriptor)
        
        do {
            return try _device.makeRenderPipelineState(descriptor: rndPipStatDescriptor)
        }
        catch
        {
            fatalError("Could not create render pipeline state object: \(error)")
        }
    }
    
    // !without this is gonna render -- but it will not be able to
    // understand what is behind and what is not
    static private func _buildDepthStencilState(device: MTLDevice) -> MTLDepthStencilState {
        let depthStencilDescriptor = MTLDepthStencilDescriptor()
        // whether a fragment passes the so-called depth test
        depthStencilDescriptor.depthCompareFunction = .less
        depthStencilDescriptor.isDepthWriteEnabled = true
        depthStencilDescriptor.frontFaceStencil = nil
        depthStencilDescriptor.backFaceStencil = nil
        return device.makeDepthStencilState(descriptor: depthStencilDescriptor)!
    }
    
    /// Encoding pass wrapper
    /// - Parameters:
    ///   - commandBuffer: buffer used to create the render command encoder through the descriptor
    ///   - descriptor: render pass descriptor to create the render command encoder
    ///   - label: encoder label
    ///   - encodingBlock: use the encoder to create the pass
    func _encodePass(into commandBuffer: MTLCommandBuffer,
                    using descriptor: MTLRenderPassDescriptor,
                    label: String,
                    _ encodingBlock: (MTLRenderCommandEncoder) -> Void) {
        guard let renderEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: descriptor) else {
            fatalError("Failed to make render command encoder with: \(descriptor.description)")
        }
        renderEncoder.label = label
        encodingBlock(renderEncoder)
        renderEncoder.endEncoding()
    }
    
    /// encode a stage in the pass, useful for debugging
    /// - Parameters:
    ///   - renderEncoder: encoder which we are currently using
    ///   - label:label of the stage
    ///   - encodingBlock:create the stage
    func _encodeStage(using renderEncoder: MTLRenderCommandEncoder,
                     label: String,
                     _ encodingBlock: () -> Void) {
        renderEncoder.pushDebugGroup(label)
        encodingBlock()
        renderEncoder.popDebugGroup()
    }
    
    
    ///tutorial 3 - deferred rendering

    private var _gBuffer : GBuffer!
    
    // Mesh buffer for simple Quad
    let quadVertexBuffer: BufferView<MT3BasicVertex>

    lazy var _displayDepthStencilState = {
        let descriptor = MTLDepthStencilDescriptor()
        descriptor.label = "display depth stencil"
        if let depthStencilState = self._device.makeDepthStencilState(descriptor: descriptor) {
            return depthStencilState
        } else {
            fatalError("Failed to create depth-stencil state.")
        }
    }()

    
    //tutorial2 - Sample object

    var _library : MTLLibrary! = nil
    var _optionalLightPosition: SIMD3<Float>?
    var _modelConfigs:ModelConfigs = ModelConfigs()
    var _optionalCamera:Camera?
    var _objboundingBox:MDLAxisAlignedBoundingBox!
    var _currentAngle:Double = 0
    var _currentTime:CFTimeInterval?
    var _meshes:[MTKMesh]!
    var _vertexDescriptor: MTLVertexDescriptor!
    let _depthStencilState: MTLDepthStencilState
    
    //tutorial 1 - Hello

    let _metalView:MTKView!
    let _device:MTLDevice!
    let _commandQueue:MTLCommandQueue!
    var _gBuffPipelineState:MTLRenderPipelineState!
    var _displayPipelineState: MTLRenderPipelineState!
    var _viewportSize = vector_uint2(100,100)

    /// \}
    
}
