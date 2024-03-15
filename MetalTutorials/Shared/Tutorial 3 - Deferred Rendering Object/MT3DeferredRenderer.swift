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

/// @group public configurations
struct MT3ModelConfigs
{
    var shouldRotateAroundBBox: Bool = true
}

/// @group public configurations
struct MT3Camera
{
    // identity
    var rotation = simd_quatf(real: 1, imag: SIMD3<Float>(0, 0, 0))
    var fov: Float = Float.pi / 3
    var nearZ: Float = 0.1
    var farZ: Float = 100
}

/// @group tutorial 3 - deferred rendering
/// 🥷: Main class that is managing all the rendering of the view.
///🧩🧩🧩 ⏩️ 🖼️: rendering a .obj and a point light in a deferred rendering pipeline.
class MT3DeferredRenderer : NSObject, MTKViewDelegate, MT3SceneDelegate {
     
    
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
    
     //MARK: class public configurations @{
    
    /// @group public configurations
    func setLightPosition(_ lightPosition: SIMD3<Float>)
    {
        _lightPosition = lightPosition;
    }
    
    /// @group public configurations
    func setModelConfigs(_ modelConfigs: MT3ModelConfigs)
    {
        _modelConfigs = modelConfigs
    }
    
    /// @group public configurations
    func setCamera(camera:MT3Camera)
    {
        _camera = camera
    }
    
    // class public configurations @}

    //MARK: MTKViewDelegate @{
    
    /// @group MTKViewDelegate
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
        
        guard let position = _device.makeTexture(descriptor: gBufferTextureDesc) else {
            fatalError("cannot create position texture")
        }
        position.label = "Albedo position Texture"
        
        _gBuffer = GBuffer(albedoSpecular: albedoSpecular, normal: normal, position: position)
        
        //create pipeline
        
        _gBuffPipelineState = _buildPipeline(
            vertexFunction: "MT3::vertex_main",
            fragmentFunction: "MT3::gbuffer_fragment",
            label: "GBufferPSO"
        ){ descriptor in
            descriptor.colorAttachments[Int(MT3RenderTargetAlbedo.rawValue)]?.pixelFormat = albedoDesc.pixelFormat
            descriptor.colorAttachments[Int(MT3RenderTargetNormal.rawValue)]?.pixelFormat = gBufferTextureDesc.pixelFormat
            descriptor.colorAttachments[Int(MT3RenderTargetPosition.rawValue)]?.pixelFormat = gBufferTextureDesc.pixelFormat
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
    
    /// @group MTKViewDelegate
    ///here you create a command buffer
    ///encode commands that tells to the gpu what to draw
    func draw(in view: MTKView) {
    
        _computeCurrentRotationAngle()
        _render(with: view)
    }

    /// @}


    //MARK: private @{
    
    /// GBuffer textures which are going to used to store the information of the scene
    struct GBuffer {
        let albedoSpecular: MTLTexture
        let normal : MTLTexture
        let position : MTLTexture
    }

    /// main render function
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
            
            descriptor.colorAttachments[Int(MT3RenderTargetPosition.rawValue)].loadAction = .clear
            descriptor.colorAttachments[Int(MT3RenderTargetPosition.rawValue)].storeAction = .store
            descriptor.colorAttachments[Int(MT3RenderTargetPosition.rawValue)].texture = _gBuffer.position
            
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
                renderEncoder.setFragmentTexture(_gBuffer.position, index: Int(MT3RenderTargetPosition.rawValue))
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
    
    /// build the uniforms for the vertex and fragment shaders containing the projection matrix of the camera
    /// and the modelView matrix
    private func _buildUniforms(_ view:MTKView) -> (MT3VertexUniforms, MT3FragmentUniforms)
    {
        let modelMatrix:float4x4? = {
            if(_modelConfigs.shouldRotateAroundBBox)
            {
                let center = (_objboundingBox.maxBounds + _objboundingBox.minBounds)*0.5
                
                //model to world
                return float4x4(rotationAbout: SIMD3<Float>(0, 1, 0), by: Float(_currentAngle)) * float4x4(translationBy: -center)
            }
            return nil
        }()
        
        //world to camera view
        let extent = _objboundingBox.maxBounds - _objboundingBox.minBounds;
        let origin = _camera.rotation.act(SIMD3<Float>(0, 0, (2+extent.z)))
        let target = SIMD3<Float>(0,0,0)
        let viewMatrix = float4x4(origin: origin, target: target, up: SIMD3<Float>(0,1,0))
        let aspectRatio = Float(view.drawableSize.width / view.drawableSize.height)
        let projectionMatrix = float4x4(perspectiveProjectionFov: _camera.fov, aspectRatio: aspectRatio, nearZ: _camera.nearZ, farZ: _camera.farZ)
        let modelView = modelMatrix != nil ? viewMatrix * modelMatrix! : viewMatrix
        let modelViewProjection = projectionMatrix * modelView
        
        // transformations necessary to handle correctly normals
        // @see https://www.scratchapixel.com/lessons/mathematics-physics-for-computer-graphics/geometry/transforming-normals
        let indeces = SIMD3<Int>(0,1,2)
        let modelViewInverseTransposeMatrix = float3x3(
                                    modelView.columns.0[indeces],
                                    modelView.columns.1[indeces],
                                    modelView.columns.2[indeces]).transpose.inverse
        
        let lightPosition = _objboundingBox.maxBounds + _lightPosition
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
    
    /// build a pipeline passing a lambda to customize the descriptor before creating it.
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
    
    /// !without this is gonna render -- but it will not be able to
    /// understand what is behind and what is not
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
    
    
    //tutorial 3 - deferred rendering

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

    private var _library : MTLLibrary! = nil
    /// position of the light from max bounds of the object
    private var _lightPosition = SIMD3<Float>(20,20,10)
    private var _modelConfigs = MT3ModelConfigs()
    private var _camera = MT3Camera()
    private var _objboundingBox:MDLAxisAlignedBoundingBox!
    private var _currentAngle:Double = 0
    private var _currentTime:CFTimeInterval?
    private var _meshes:[MTKMesh]!
    private var _vertexDescriptor: MTLVertexDescriptor!
    private let _depthStencilState: MTLDepthStencilState
    
    //tutorial 1 - Hello

    private let _metalView:MTKView!
    private let _device:MTLDevice!
    private let _commandQueue:MTLCommandQueue!
    private var _gBuffPipelineState:MTLRenderPipelineState!
    private var _displayPipelineState: MTLRenderPipelineState!
    private var _viewportSize = vector_uint2(100,100)

    // @}
    
}
