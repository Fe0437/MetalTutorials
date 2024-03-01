//
//  MT5TiledDeferredRenderer.swift
//  MetalTutorials
//
//  Created by federico forti on 14/03/2021.
//

import MetalKit
import ModelIO

//use for future and promises
import Combine
import simd

/// 🥷: Main class that is managing all the rendering of the view.
/// ⚡️: this is a version of the deferred renderer that is using the tiled Rendering
/// this tupe of rendering permits to use the GBuffer without 
/// explicitely writing on textures and then reading from them with the CPU
class MT5TiledDeferredRenderer : NSObject, MTKViewDelegate {
        
    /**
     init pipeline and load the obj asset
     */
    init(metalView: MTKView, objName:String) {
        
        _metalView = metalView
        // Set the pixel formats of the render destination.
        _metalView.depthStencilPixelFormat = .depth32Float
        _metalView.colorPixelFormat = .bgra8Unorm_srgb
        
        _device = _metalView.device
        
        // create the command queue
        _commandQueue = _device.makeCommandQueue()
        
        let meshAsset = Self._loadObj(
            objName: objName,
            device: _device
        )

        // depth stencil
        _depthStencilState = Self._buildDepthStencilState(device: _device)
        
        // Create quad for fullscreen composition drawing
        let quadVertices: [MT5ScreenVertex] = [
            .init(position: .init(x: -1, y: -1)),
            .init(position: .init(x: -1, y:  1)),
            .init(position: .init(x:  1, y: -1)),
            
            .init(position: .init(x:  1, y: -1)),
            .init(position: .init(x: -1, y:  1)),
            .init(position: .init(x:  1, y:  1))
        ]
        
        _quadVertexBuffer = .init(device: _device, array: quadVertices)
        
        let plane = Self._buildPlane(device: _device)
        do {
            (_, _basePlaneMesh) = try MTKMesh.newMeshes(asset: plane, device: _device)
        } catch {
            fatalError("Could not extract meshes from Model I/O asset")
        }
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

    ///MTKViewDelegate \{

    ///whenever the size changes or orientation changes
    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        
        _viewportSize.x = UInt32(size.width)
        _viewportSize.y = UInt32(size.height)
        
        
        //create shadow texture
        let shadowextureDesc = MTLTextureDescriptor
            .texture2DDescriptor(pixelFormat: .depth32Float,
                                 width: Int(size.width),
                                 height: Int(size.height),
                                 mipmapped: false)
        shadowextureDesc.textureType = .type2D
        shadowextureDesc.usage = [.shaderRead, .renderTarget]
        shadowextureDesc.storageMode = .private
        guard let shadowTexture = _device.makeTexture(descriptor: shadowextureDesc)
        else {
            fatalError("cannot create shadow texture")
        }
        shadowTexture.label = "Shadow Depth Texture"
        _shadowTexture = shadowTexture
                
        //create gBuffer textures
        let albedoDesc = MTLTextureDescriptor
            .texture2DDescriptor(pixelFormat: .bgra8Unorm,
                                 width: Int(size.width),
                                 height: Int(size.height),
                                 mipmapped: false)
        albedoDesc.textureType = .type2D
        albedoDesc.usage = [.shaderRead, .renderTarget]
        // tutorial 5 - tiled rendering
        albedoDesc.storageMode = .memoryless
        
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
        // tutorial 5 - tiled rendering
        gBufferTextureDesc.storageMode = .memoryless
        
        guard let normal = _device.makeTexture(descriptor: gBufferTextureDesc) else {
            fatalError("cannot create normal texture")
        }
        normal.label = "Normal GBuffer Texture"
        
        guard let position = _device.makeTexture(descriptor: gBufferTextureDesc) else {
            fatalError("cannot create position texture")
        }
        position.label = "Albedo position Texture"
        
        _gBuffer = GBuffer(albedoSpecular: albedoSpecular, normal: normal, position: position)
        
        //create pipeline
        
        _shadowPSO = _buildPipeline(
            vertexFunctionName: "MT5::vertex_depth",
            fragmentFunctionName: nil,
            label: "ShadowPSO"
        ){ descriptor in
            // we want only the depth and not the color or stencil
            descriptor.colorAttachments[0]?.pixelFormat = .invalid
            descriptor.depthAttachmentPixelFormat = .depth32Float
            descriptor.stencilAttachmentPixelFormat = .invalid
        }
        
        _gBufferPSO = _buildPipeline(
            vertexFunctionName: "MT5::vertex_main",
            fragmentFunctionName: "MT5::gbuffer_fragment",
            label: "GBufferPSO"
        ){ descriptor in
            descriptor.colorAttachments[0].pixelFormat = _metalView.colorPixelFormat
            descriptor.colorAttachments[Int(MT5RenderTargetAlbedo.rawValue)]?.pixelFormat = albedoDesc.pixelFormat
            descriptor.colorAttachments[Int(MT5RenderTargetNormal.rawValue)]?.pixelFormat = gBufferTextureDesc.pixelFormat
            descriptor.colorAttachments[Int(MT5RenderTargetPosition.rawValue)]?.pixelFormat = gBufferTextureDesc.pixelFormat
            descriptor.depthAttachmentPixelFormat = _metalView.depthStencilPixelFormat
        }
        
        _displayPipelineState = _buildPipeline(
            vertexFunctionName: "MT5::display_vertex",
            fragmentFunctionName: "MT5::deferred_lighting_fragment",
            label: "DeferredLightingPSO"
        ){ descriptor in
            descriptor.colorAttachments[0].pixelFormat = _metalView.colorPixelFormat
            descriptor.colorAttachments[Int(MT5RenderTargetAlbedo.rawValue)]?.pixelFormat = albedoDesc.pixelFormat
            descriptor.colorAttachments[Int(MT5RenderTargetNormal.rawValue)]?.pixelFormat = gBufferTextureDesc.pixelFormat
            descriptor.colorAttachments[Int(MT5RenderTargetPosition.rawValue)]?.pixelFormat = gBufferTextureDesc.pixelFormat
            descriptor.depthAttachmentPixelFormat = _metalView.depthStencilPixelFormat
        }
    }
    
    ///here you create a command buffer
    ///encode commands that tells to the gpu what to draw
    func draw(in view: MTKView) {
        _render(with: view)
    }

    /// \}

    ///private \{

    struct GBuffer {
        let albedoSpecular: MTLTexture
        let normal : MTLTexture
        let position : MTLTexture
    }
    
    private func _render(with view: MTKView) {
        /// create the new command buffer for this pass
        _computeCurrentRotationAngle()
        
        guard let drawable = view.currentDrawable else {return}
        
        let commandBuffer = _commandQueue.makeCommandBuffer()!
        commandBuffer.label = "Tutorial4Commands"
        
        var modelMatrix:float4x4?
        let center = (_objboundingBox.maxBounds + _objboundingBox.minBounds)*0.5
        if(_modelConfigs.shouldRotateAroundBBox)
        {
            //model to world
            modelMatrix =
                float4x4(rotationAbout: SIMD3<Float>(0, 1, 0), by: Float(_currentAngle)) * float4x4(translationBy: -center)
        }
        
        //the position of the light for the shadow map is inside the uniforms
        var uniforms = _buildUniforms(view, modelMatrix: modelMatrix)
        var planeUniforms = _buildUniforms(view, modelMatrix:  float4x4(translationBy: -center) * float4x4(rotationAbout: SIMD3<Float>(0, 0, 1), by: Float.pi * -0.5))
        
        let shadowPassDescriptor: MTLRenderPassDescriptor = {
            let descriptor = MTLRenderPassDescriptor()
            descriptor.depthAttachment.loadAction = .clear
            descriptor.depthAttachment.storeAction = .store
            descriptor.depthAttachment.texture = _shadowTexture
            return descriptor
        }()
        
        _encodePass(into: commandBuffer, using: shadowPassDescriptor, label: "Shadow Pass")
        { commandEncoder in
            // init the MTLViewport from the metal library
            let viewport = _buildViewport()
            commandEncoder.setViewport(viewport)
            
            commandEncoder.setRenderPipelineState(_shadowPSO)
            commandEncoder.setDepthStencilState(_depthStencilState)
            
            commandEncoder.setVertexBytes(&uniforms.0, length: MemoryLayout<MT5VertexUniforms>.size, index: 1)
            _renderMeshes(commandEncoder)
            
        }
        
        let tiledDeferredRenderPassDescriptor: MTLRenderPassDescriptor = {
            //tutorial 5 - without passing the metal view render pass descriptor is not going to work with the texture [0]
            let descriptor = _metalView.currentRenderPassDescriptor!
            descriptor.colorAttachments[Int(MT5RenderTargetAlbedo.rawValue)].loadAction = .clear
            // tutorial 5 - tiled rendering
            descriptor.colorAttachments[Int(MT5RenderTargetAlbedo.rawValue)].storeAction = .dontCare
            descriptor.colorAttachments[Int(MT5RenderTargetAlbedo.rawValue)].texture = _gBuffer.albedoSpecular
            
            descriptor.colorAttachments[Int(MT5RenderTargetNormal.rawValue)].loadAction = .clear
            descriptor.colorAttachments[Int(MT5RenderTargetNormal.rawValue)].storeAction = .dontCare
            descriptor.colorAttachments[Int(MT5RenderTargetNormal.rawValue)].texture = _gBuffer.normal
            
            descriptor.colorAttachments[Int(MT5RenderTargetPosition.rawValue)].loadAction = .clear
            descriptor.colorAttachments[Int(MT5RenderTargetPosition.rawValue)].storeAction = .dontCare
            descriptor.colorAttachments[Int(MT5RenderTargetPosition.rawValue)].texture = _gBuffer.position
            
            descriptor.depthAttachment.loadAction = .clear
            descriptor.depthAttachment.texture = view.depthStencilTexture
            
            descriptor.depthAttachment.storeAction = .dontCare
            return descriptor
        }()
        
        _encodePass(into: commandBuffer, using: tiledDeferredRenderPassDescriptor, label: "Tiled Render Pass")
        { commandEncoder in
            
            _encodeStage(using: commandEncoder, label: "GBuffer")
            {
                // init the MTLViewport from the metal library
                let viewport = _buildViewport()
                commandEncoder.setViewport(viewport)
                
                commandEncoder.setVertexBytes(&uniforms.0, length: MemoryLayout<MT5VertexUniforms>.size, index: 1)
                commandEncoder.setFragmentBytes(&uniforms.1, length: MemoryLayout<MT5FragmentUniforms>.size, index: 1)
                commandEncoder.setFragmentTexture(_shadowTexture, index: Int(MT5RenderTargetShadow.rawValue))
                
                commandEncoder.setRenderPipelineState(_gBufferPSO)
                commandEncoder.setDepthStencilState(_depthStencilState)
                
                _renderMeshes(commandEncoder)
                
                commandEncoder.setVertexBytes(&planeUniforms.0, length: MemoryLayout<MT5VertexUniforms>.size, index: 1)
                commandEncoder.setFragmentBytes(&planeUniforms.1, length: MemoryLayout<MT5FragmentUniforms>.size, index: 1)
                
                _renderPlane(commandEncoder)
            }
            
            _encodeStage(using: commandEncoder, label: "Compose")
            {
                commandEncoder.setRenderPipelineState(_displayPipelineState)
                commandEncoder.setDepthStencilState(_displayDepthStencilState)
                
                //set g buffer textures
                commandEncoder.setFragmentBytes(&uniforms.1, length: MemoryLayout<MT5FragmentUniforms>.size, index: 1)
                
                commandEncoder.setCullMode(.back)
                commandEncoder.setStencilReferenceValue(128)
                
                commandEncoder.setVertexBuffer(_quadVertexBuffer,
                                               offset: 0,
                                               index: Int(MT5BufferIndexMeshPositions.rawValue))
                // Draw full screen quad
                commandEncoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 6)
            }
            
            commandBuffer.present(drawable)
        }
        
        commandBuffer.commit()
    }

    
    private func _renderPlane(_ commandEncoder: MTLRenderCommandEncoder){
        //render base plane
        let basePlaneBuffer = _basePlaneMesh.first!.vertexBuffers.first!
        commandEncoder.setVertexBuffer(basePlaneBuffer.buffer,
                                      offset: 0,
                                      index: 0)
        let psubmesh = _basePlaneMesh.first!.submeshes.first!
        let pindexBuffer = psubmesh.indexBuffer
        commandEncoder.drawIndexedPrimitives(type: psubmesh.primitiveType,
                                             indexCount: psubmesh.indexCount,
                                             indexType: psubmesh.indexType,
                                             indexBuffer: pindexBuffer.buffer,
                                             indexBufferOffset: pindexBuffer.offset)
    }
    
    private func _renderMeshes(_ commandEncoder: MTLRenderCommandEncoder) {
        
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
    
    private class func _buildPlane(device: MTLDevice) -> MDLAsset
    {
        let bufferAllocator = MTKMeshBufferAllocator(device: device)

        let mdlMesh = MDLMesh(
            planeWithExtent: vector_float3(repeating: 100), segments: vector_uint2(x: 10, y: 10), geometryType: .triangles, allocator: bufferAllocator)
        
        let meshAsset = MDLAsset()
        meshAsset.add(mdlMesh)
        
        return meshAsset
        
    }
    
    private func _buildUniforms(_ view:MTKView, modelMatrix : float4x4?) -> (MT5VertexUniforms, MT5FragmentUniforms)
    {
        let lightPosition = _optionalLightPosition ?? _objboundingBox.maxBounds + SIMD3<Float>(20,20,10)
        let center = (_objboundingBox.maxBounds + _objboundingBox.minBounds)*0.5
        let extent = _objboundingBox.maxBounds - _objboundingBox.minBounds;

        // tutorial 4 - shadows
        let shadowViewMatrix = float4x4(origin: lightPosition, target: center, up: SIMD3<Float>(0,1,0))
        let shadowProjectionMatrix = float4x4(perspectiveProjectionFov:  Float.pi / 16, aspectRatio: 1, nearZ: 0.1, farZ: 10000)
        
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
            viewMatrix = float4x4(translationBy: SIMD3<Float>(0, 0, -(2+extent.z)))
            aspectRatio = Float(view.drawableSize.width / view.drawableSize.height)
            projectionMatrix = float4x4(perspectiveProjectionFov: Float.pi / 3, aspectRatio: aspectRatio, nearZ: 0.1, farZ: 100)
        }
        
        let modelView = modelMatrix != nil ? viewMatrix! * modelMatrix! : viewMatrix!
        let modelViewProjection = projectionMatrix * modelView
        
        let shadowModelView = modelMatrix != nil ? shadowViewMatrix * modelMatrix! : shadowViewMatrix
        let shadowModelViewProjection = shadowProjectionMatrix * shadowModelView

        // transformations necessary to handle correctly normals
        // @see https://www.scratchapixel.com/lessons/mathematics-physics-for-computer-graphics/geometry/transforming-normals
        let indeces = SIMD3<Int>(0,1,2)
        let modelViewInverseTransposeMatrix = float3x3(
                                    modelView.columns.0[indeces],
                                    modelView.columns.1[indeces],
                                    modelView.columns.2[indeces]).transpose.inverse
        
        let vertexUniforms = MT5VertexUniforms(
            modelViewMatrix: modelView,
            modelViewInverseTransposeMatrix: modelViewInverseTransposeMatrix,
            modelViewProjectionMatrix: modelViewProjection,
            shadowModelViewProjectionMatrix: shadowModelViewProjection
        )
        
        let viewLightPosition =  viewMatrix * SIMD4<Float>(lightPosition, 1);
        let fragmentUniforms = MT5FragmentUniforms(viewLightPosition: viewLightPosition)
        
        return (vertexUniforms, fragmentUniforms)
    }
    
    private func _buildViewport() -> MTLViewport {
        return MTLViewport(originX: 0.0, originY: 0.0, width: Double(_viewportSize.x), height: Double(_viewportSize.y), znear: 0.0, zfar: 1.0)
    }
    
    
    private func _buildPipeline(
        vertexFunctionName:String, fragmentFunctionName:String?, label: String, customize: (MTLRenderPipelineDescriptor) -> Void) -> MTLRenderPipelineState  {
        
        //create the vertex and fragment shaders_
        let vertexFunction = _library.makeFunction(name: vertexFunctionName)
        
        
        //create the pipeline we will run during draw
        //this pipeline will use the vertex and fragment shader we have defined here
        let rndPipStatDescriptor = MTLRenderPipelineDescriptor()
        rndPipStatDescriptor.label = label
        rndPipStatDescriptor.vertexFunction = vertexFunction
            
        if let fragmentFunctionName = fragmentFunctionName {
            let fragmentFunction = _library.makeFunction(name: fragmentFunctionName)
            rndPipStatDescriptor.fragmentFunction = fragmentFunction
        }
        
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
    
    // depth stencil @{
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
    // @}
    
    /// Encoding pass wrapper
    /// - Parameters:
    ///   - commandBuffer: buffer used to create the render command encoder through the descriptor
    ///   - descriptor: render pass descriptor to create the render command encoder
    ///   - label: encoder label
    ///   - encodingBlock: use the encoder to create the pass
    private func _encodePass(into commandBuffer: MTLCommandBuffer,
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
    private func _encodeStage(using renderEncoder: MTLRenderCommandEncoder,
                     label: String,
                     _ encodingBlock: () -> Void) {
        renderEncoder.pushDebugGroup(label)
        encodingBlock()
        renderEncoder.popDebugGroup()
    }
    
    //tutorial 4 - Shadows

    private var _shadowPSO :MTLRenderPipelineState!
    private var _shadowTexture: MTLTexture!
    private let _basePlaneMesh: [MTKMesh]

    
    //tutorial 3 - Deferred Rendering

    private var _gBuffer : GBuffer!
    private var _gBufferPSO:MTLRenderPipelineState!
    // Mesh buffer for simple Quad
    private let _quadVertexBuffer: BufferView<MT5ScreenVertex>
    
    private lazy var _displayDepthStencilState = {
        let descriptor = MTLDepthStencilDescriptor()
        descriptor.label = "display depth stencil"
        if let depthStencilState = self._device.makeDepthStencilState(descriptor: descriptor) {
            return depthStencilState
        } else {
            fatalError("Failed to create depth-stencil state.")
        }
    }()
    
    //tutorial2 - Sample Object

    private var _optionalLightPosition: SIMD3<Float>?
    private var _modelConfigs:ModelConfigs = ModelConfigs()
    private var _optionalCamera:Camera?
    private var _objboundingBox:MDLAxisAlignedBoundingBox!
    private var _currentAngle:Double = 0
    private var _currentTime:CFTimeInterval?
    private var _meshes:[MTKMesh]!
    private var _vertexDescriptor: MTLVertexDescriptor!
    private let _depthStencilState: MTLDepthStencilState
    
    //tutorial 1 - basic

    private let _metalView:MTKView!
    private let _device:MTLDevice!
    private let _commandQueue:MTLCommandQueue!
    private var _displayPipelineState: MTLRenderPipelineState!
    private var _viewportSize = vector_uint2(100,100)
    private var _library : MTLLibrary! = nil
    
}
