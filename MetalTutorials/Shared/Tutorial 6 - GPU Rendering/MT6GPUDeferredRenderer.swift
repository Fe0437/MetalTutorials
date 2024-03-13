//
//  MT6Renderer.swift
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
/// ⚡️: this is a version that renders everything directly from the GPU
class MT6GPUDeferredRenderer : NSObject, MTKViewDelegate {
    
    private var _drawKernel : MTLFunction!
    private var _drawKernelPSO : MTLComputePipelineState!

    
    /**
     init pipeline and load the obj asset
     */
    init(metalView: MTKView, commandQueue: MTLCommandQueue, scene: MT6Scene) {
        
        _metalView = metalView
        _scene = scene

        // Set the pixel formats of the render destination.
        _metalView.depthStencilPixelFormat = .depth32Float_stencil8
        _metalView.colorPixelFormat = .bgra8Unorm_srgb
        
        _device = _metalView.device
        
        // setup
        _commandQueue = commandQueue
        _library = _device.makeDefaultLibrary()
        _depthStencilState = Self._buildDepthStencilState(device: _device)
        
        // Create quad for fullscreen composition drawing
        let quadVertices: [MT6ScreenVertex] = [
            .init(position: .init(x: -1, y: -1)),
            .init(position: .init(x: -1, y:  1)),
            .init(position: .init(x:  1, y: -1)),
            
            .init(position: .init(x:  1, y: -1)),
            .init(position: .init(x: -1, y:  1)),
            .init(position: .init(x:  1, y:  1))
        ]
        _quadVertexBuffer = .init(device: _device, array: quadVertices)
        
        super.init()
        
        // tutorial 6 - GPU Rendering @{
        
        // 1 - create draw kernel
        _drawKernel =
        _library.makeFunction(name: "MT6::Indirect::drawKernel")!
        do {
            _drawKernelPSO = try _device.makeComputePipelineState(function: _drawKernel)
        } catch {
            fatalError(error.localizedDescription)
        }
        
        // 2 - build uniforms for the vertex and fragment shaders
        (_vertexUniformsArray, _fragmentUniforms) = _buildUniforms(metalView, scene: scene)
        _initUniformBuffers(_vertexUniformsArray, _fragmentUniforms)
        _updateUniforms()
        
        // 3 - setup the draw kernel that is going to draw using an indirect command buffer
        self._indirectCommandB = _buildIndirectCommandBuffer(_scene)
        _setupICBOnDrawKernel(self._indirectCommandB, with: _drawKernel)
        _sendSceneToDrawKernel(_scene)
        
        
        // @}
    }
    
    func _updateUniforms() {
        
     (_vertexUniformsArray, _fragmentUniforms) = _buildUniforms(_metalView, scene: _scene)
      
    _vertexUniformsBuffer.contents().copyMemory(
        from: &_vertexUniformsArray,
        byteCount: MemoryLayout<MT6VertexUniforms>.stride * _vertexUniformsArray.count)
        
    _fragmentUniformsBuffer.contents().copyMemory(
      from: &_fragmentUniformsBuffer,
      byteCount: MemoryLayout<MT6FragmentUniforms>.stride)
          
    }
    
    private func _setupICBOnDrawKernel(_ icb: MTLIndirectCommandBuffer, with kernel: MTLFunction)
    {
        //create an argument encoder for our kernel function
        let argumentEncoder = kernel.makeArgumentEncoder(
            bufferIndex: Int(MT6IndirectCommandBuffer.rawValue))
        
        _computeKernelIndirectCommandBuffer = _device.makeBuffer(
          length: argumentEncoder.encodedLength,
          options: [.storageModeShared])
        argumentEncoder.setArgumentBuffer(_computeKernelIndirectCommandBuffer, offset: 0)
        argumentEncoder.setIndirectCommandBuffer(icb, index: 0)
    }
    
    private var _sceneBuffer: MTLBuffer!
    private var _drawArgumentsBuffer: MTLBuffer!
    private var _materialArgBuffer: MTLBuffer!
    private var _shadowArgBuffer: MTLBuffer!
    private var _shadowArgumentEncoder: MTLArgumentEncoder!

    
    
    private func _sendSceneToDrawKernel(_ scene: MT6Scene)
    {
        let nSubmeshes = scene.computedNSubmeshes
        
        //argument encoder for the buffer MT6MeshesBuffer @{
        let meshArgumentEncoder = _drawKernel.makeArgumentEncoder(
            bufferIndex: Int(MT6MeshesBuffer.rawValue))
        meshArgumentEncoder.label = "Mesh Buffer Encoder"
        _sceneBuffer = _device.makeBuffer(
            length: meshArgumentEncoder.encodedLength * nSubmeshes, options: [])
        _sceneBuffer.label = "Mesh Buffer"
        //@}
        
        // material arguments @{
        guard let gBufferFragment = _library.makeFunction(name: "MT6::gbuffer_fragment")
        else {
            fatalError("missing MT6::gbuffer_fragment")
        }
        //create the argument encoder
        let materialArgumentEncoder = gBufferFragment.makeArgumentEncoder(
          bufferIndex: Int(MT6MaterialArgBuffer.rawValue))
        //the encoder knows the necessary length
        _materialArgBuffer = _device.makeBuffer(
          length: materialArgumentEncoder.encodedLength * nSubmeshes,
          options: [])
        _materialArgBuffer.label = "Material Arg Buffer"
        //@}
        
        // shadows arguments @{
        _shadowArgumentEncoder = gBufferFragment.makeArgumentEncoder(
          bufferIndex: Int(MT6ShadowsArgumentsBuffer.rawValue))
        //the encoder knows the necessary length
        _shadowArgBuffer = _device.makeBuffer(
          length: _shadowArgumentEncoder.encodedLength,
          options: [])
        _shadowArgBuffer.label = "Shadow Arg Buffer"
        _shadowArgumentEncoder.setArgumentBuffer(_shadowArgBuffer, offset: 0)
        //@}
        
        // draw arguments @{
        let drawLength = nSubmeshes *
          MemoryLayout<MTLDrawIndexedPrimitivesIndirectArguments>.stride
        _drawArgumentsBuffer = _device.makeBuffer(
        length: drawLength, options: [])
        _drawArgumentsBuffer.label = "Draw Arguments Buffer"
       
        //get pointer
        var drawArgumentPtr =
        _drawArgumentsBuffer!.contents().bindMemory(
            to: MTLDrawIndexedPrimitivesIndirectArguments.self,
            capacity: nSubmeshes)
        // @}
        
        
        var index = 0
        for mesh in scene.mtkMeshes {
            for submesh in mesh.submeshes{
                
                //we first set the argument buffer that we are going to use
                meshArgumentEncoder.setArgumentBuffer(
                    _sceneBuffer, startOffset: 0, arrayElement: index)
                
                // set the buffers for the MT6MeshesBuffer argument
                // it has 3 buffers for vertex, texturecoords and indeces.
                meshArgumentEncoder.setBuffer(
                    mesh.vertexBuffers[0].buffer, 
                    offset: mesh.vertexBuffers[0].offset,
                    index: Int(MT6VertexBuffer.rawValue))
                
                meshArgumentEncoder.setBuffer(
                    mesh.vertexBuffers[1].buffer,
                    offset: mesh.vertexBuffers[1].offset,
                    index: Int(MT6TextureCoordinatesBuffer.rawValue))
                
                meshArgumentEncoder.setBuffer(
                    submesh.indexBuffer.buffer,
                    offset: submesh.indexBuffer.offset,
                    index: Int(MT6IndecesBuffer.rawValue))
                
                //setup material arg buffer
                materialArgumentEncoder.setArgumentBuffer(_materialArgBuffer , startOffset: 0, arrayElement: index)
                
                //set all the textures for the argument buffer
                guard let mdlSubmesh = _scene.mapMTKSubmeshToMDLMesh[submesh] else {
                    fatalError("the mesh has not been mapped")
                }
                
                if mdlSubmesh.material != nil {
                    for property in mdlSubmesh.material!.properties(with: .baseColor)
                    {
                        if let texture = MT6Scene.getTexture(for: submesh, andProperty: property)
                        {
                            //set the texture buffer, the index is the id inside the argument struct
                            materialArgumentEncoder.setTexture(texture, index: Int(MT6BaseColorTexture.rawValue))
                        }
                    }
                    
                    for property in mdlSubmesh.material!.properties(with: .specular)
                    {
                        if let texture = MT6Scene.getTexture(for: submesh, andProperty: property)
                        {
                            //set the texture buffer, the index is the id inside the argument struct
                            materialArgumentEncoder.setTexture(texture, index: Int(MT6SpecularTexture.rawValue))
                        }
                    }
                }
                
                //set the material argument buffer as a parameter for the compute
                meshArgumentEncoder.setBuffer(
                    _materialArgBuffer,
                    offset: 0,
                    index: Int(MT6MaterialArgBuffer.rawValue))
                
                
                // setup the draw for this submesh
                var drawArgument = MTLDrawIndexedPrimitivesIndirectArguments()
                drawArgument.indexCount = UInt32(submesh.indexCount)
                drawArgument.indexStart = UInt32(submesh.indexBuffer.offset)
                drawArgument.instanceCount = 1
                drawArgument.baseVertex = 0
                drawArgument.baseInstance = UInt32(index)
                
                //set the value for the current pointer
                drawArgumentPtr.pointee = drawArgument
                
                //next
                drawArgumentPtr = drawArgumentPtr.advanced(by: 1)
                index += 1
            }
        }
    }
    
    //MARK: MTKViewDelegate interface @{
    
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
        
        _gBuffer = GBuffer(albedo_specular: albedoSpecular, normal_shadow: normal, position: position)
        
        //create pipeline
        _shadowPSO = _buildPipeline(
            vertexFunctionName: "MT6::vertex_depth",
            fragmentFunctionName: nil,
            label: "ShadowPSO"
        ){ descriptor in
            // we want only the depth and not the color or stencil
            descriptor.colorAttachments[0]?.pixelFormat = .invalid
            descriptor.depthAttachmentPixelFormat = .depth32Float
            descriptor.stencilAttachmentPixelFormat = .invalid
            descriptor.supportIndirectCommandBuffers = true
            descriptor.vertexDescriptor = _scene.vertexDescriptor
        }
        
        _gBufferPSO = _buildPipeline(
            vertexFunctionName: "MT6::vertex_main",
            fragmentFunctionName: "MT6::gbuffer_fragment",
            label: "GBufferPSO"
        ){ descriptor in
            descriptor.colorAttachments[0].pixelFormat = _metalView.colorPixelFormat
            descriptor.colorAttachments[Int(MT6RenderTargetBaseColorAndSpecular.rawValue)]?.pixelFormat = albedoDesc.pixelFormat
            descriptor.colorAttachments[Int(MT6RenderTargetNormalAndVisibility.rawValue)]?.pixelFormat = gBufferTextureDesc.pixelFormat
            descriptor.colorAttachments[Int(MT6RenderTargetPosition.rawValue)]?.pixelFormat = gBufferTextureDesc.pixelFormat
            descriptor.depthAttachmentPixelFormat = _metalView.depthStencilPixelFormat
            descriptor.stencilAttachmentPixelFormat = _metalView.depthStencilPixelFormat
            descriptor.supportIndirectCommandBuffers = true
            descriptor.vertexDescriptor = _scene.vertexDescriptor
        }
        
        _displayPipelineState = _buildPipeline(
            vertexFunctionName: "MT6::display_vertex",
            fragmentFunctionName: "MT6::deferred_lighting_fragment",
            label: "DeferredLightingPSO"
        ){ descriptor in
            descriptor.colorAttachments[0].pixelFormat = _metalView.colorPixelFormat
            descriptor.colorAttachments[Int(MT6RenderTargetBaseColorAndSpecular.rawValue)]?.pixelFormat = albedoDesc.pixelFormat
            descriptor.colorAttachments[Int(MT6RenderTargetNormalAndVisibility.rawValue)]?.pixelFormat = gBufferTextureDesc.pixelFormat
            descriptor.colorAttachments[Int(MT6RenderTargetPosition.rawValue)]?.pixelFormat = gBufferTextureDesc.pixelFormat
            descriptor.depthAttachmentPixelFormat = _metalView.depthStencilPixelFormat
            descriptor.stencilAttachmentPixelFormat = _metalView.depthStencilPixelFormat
            
            let vertexDescriptor = MDLVertexDescriptor()
            vertexDescriptor.attributes[0] = MDLVertexAttribute(name: MDLVertexAttributePosition, format: .float2, offset: 0, bufferIndex: 0)
            vertexDescriptor.layouts[0] = MDLVertexBufferLayout(stride: MemoryLayout<Float>.size * 2)
            descriptor.vertexDescriptor = MTKMetalVertexDescriptorFromModelIO(vertexDescriptor)
        }
    }
    
    ///here you create a command buffer
    ///encode commands that tells to the gpu what to draw
    func draw(in view: MTKView) {
        _scene.computeNewFrame()
        _updateUniforms()
        _render(scene: _scene, with: view)
    }
    
    // @}
    
    //MARK: private  @{
    
    struct GBuffer {
        let albedo_specular: MTLTexture
        let normal_shadow : MTLTexture
        let position : MTLTexture
    }
    
    private func _render(scene: MT6Scene, with view: MTKView) {
        /// create the new command buffer for this pass
        
        guard let drawable = view.currentDrawable else {return}
        
        let commandBuffer = _commandQueue.makeCommandBuffer()!
        commandBuffer.label = "TutorialCommands"
        
        let shadowPassDescriptor: MTLRenderPassDescriptor = {
            let descriptor = MTLRenderPassDescriptor()
            descriptor.depthAttachment.loadAction = .clear
            descriptor.depthAttachment.storeAction = .store
            descriptor.depthAttachment.texture = _shadowTexture
            return descriptor
        }()
        
        
        _encodeGPUPass(into: commandBuffer, using: shadowPassDescriptor, label: "Shadow Pass"
        ,compute:
        { [weak self] (encoder : MTLComputeCommandEncoder) in
            guard let self = self else {return}
            encoder.setComputePipelineState(self._drawKernelPSO)
            
            encoder.setBuffer(
                (self._computeKernelIndirectCommandBuffer), offset: 0, index: Int(MT6IndirectCommandBuffer.rawValue))
            encoder.setBuffer(
                (self._fragmentUniformsBuffer), offset: 0, index: Int(MT6FragmentUniformsBuffer.rawValue))
            encoder.setBuffer(
                self._sceneBuffer, offset: 0, index: Int(MT6MeshesBuffer.rawValue))
            encoder.setBuffer(
                (self._vertexUniformsBuffer), offset: 0, index: Int(MT6VertexUniformsBuffer.rawValue))
            encoder.setBuffer(
                self._drawArgumentsBuffer, offset: 0, index: Int(MT6DrawArgumentsBuffer.rawValue))
            encoder.setBuffer(
                self._shadowArgBuffer, offset: 0, index: Int(MT6ShadowsArgumentsBuffer.rawValue))
            
            encoder.useResource(_indirectCommandB, usage: .write)
            encoder.useResource(_fragmentUniformsBuffer, usage: .read)
            encoder.useResource(_sceneBuffer, usage: .read)
            encoder.useHeap(MT6Scene.staticGPUHeap)
            encoder.useResource(
                _shadowArgBuffer, usage: .read)
            
            for mesh in _scene.mtkMeshes {
                for submesh in mesh.submeshes {
                    encoder.useResource(
                        mesh.vertexBuffers[Int(MT6VertexBuffer.rawValue)].buffer,
                        usage: .read)
                    encoder.useResource(
                        mesh.vertexBuffers[Int(MT6TextureCoordinatesBuffer.rawValue)].buffer,
                        usage: .read)
                    encoder.useResource(
                        submesh.indexBuffer.buffer, usage: .read)
                    encoder.useResource(
                        _materialArgBuffer, usage: .read)
                }
            }
            
            let threadExecutionWidth = _drawKernelPSO.threadExecutionWidth
            let threads = MTLSize(width: _scene.computedNSubmeshes, height: 1, depth: 1)
            encoder.dispatchThreads(
              threads,
              threadsPerThreadgroup:
                MTLSize(width: threadExecutionWidth, height: 1, depth: 1))
        }, render:
        { renderEncoder in
            renderEncoder.setRenderPipelineState(_shadowPSO)
            renderEncoder.setDepthStencilState(_depthStencilState)
            renderEncoder.executeCommandsInBuffer(
                _indirectCommandB, range: 0..<_scene.computedNSubmeshes)
        })
        
        _indirectCommandB.reset(0..<_scene.computedNSubmeshes)
        
        let tiledDeferredRenderPassDescriptor: MTLRenderPassDescriptor = {
            //tutorial 5 - without passing the metal view render pass descriptor is not going to work with the texture [0]
            let descriptor = _metalView.currentRenderPassDescriptor!
            descriptor.colorAttachments[Int(MT6RenderTargetBaseColorAndSpecular.rawValue)].loadAction = .clear
            // tutorial 5 - tiled rendering
            descriptor.colorAttachments[Int(MT6RenderTargetBaseColorAndSpecular.rawValue)].storeAction = .dontCare
            descriptor.colorAttachments[Int(MT6RenderTargetBaseColorAndSpecular.rawValue)].texture = _gBuffer.albedo_specular
            
            descriptor.colorAttachments[Int(MT6RenderTargetNormalAndVisibility.rawValue)].loadAction = .clear
            descriptor.colorAttachments[Int(MT6RenderTargetNormalAndVisibility.rawValue)].storeAction = .dontCare
            descriptor.colorAttachments[Int(MT6RenderTargetNormalAndVisibility.rawValue)].texture = _gBuffer.normal_shadow
            
            descriptor.colorAttachments[Int(MT6RenderTargetPosition.rawValue)].loadAction = .clear
            descriptor.colorAttachments[Int(MT6RenderTargetPosition.rawValue)].storeAction = .dontCare
            descriptor.colorAttachments[Int(MT6RenderTargetPosition.rawValue)].texture = _gBuffer.position
            
            descriptor.depthAttachment.loadAction = .clear
            descriptor.stencilAttachment.loadAction = .clear
            descriptor.depthAttachment.texture = view.depthStencilTexture
            descriptor.stencilAttachment.texture = view.depthStencilTexture

            // Depth and Stencil attachments are needed in next pass, so need to store them (since the default is .dontCare).
            descriptor.depthAttachment.storeAction = .dontCare
            descriptor.stencilAttachment.storeAction = .dontCare
            return descriptor
        }()
        
        _encodeGPUPass(into: commandBuffer, using: tiledDeferredRenderPassDescriptor, label: "Tiled Render Pass",
        compute:
        { [weak self] (encoder : MTLComputeCommandEncoder) in
            guard let self = self else {return}
            encoder.setComputePipelineState(self._drawKernelPSO)
            
            encoder.setBuffer(
                (self._computeKernelIndirectCommandBuffer), offset: 0, index: Int(MT6IndirectCommandBuffer.rawValue))
            encoder.setBuffer(
                (self._fragmentUniformsBuffer), offset: 0, index: Int(MT6FragmentUniformsBuffer.rawValue))
            encoder.setBuffer(
                self._sceneBuffer, offset: 0, index: Int(MT6MeshesBuffer.rawValue))
            encoder.setBuffer(
                (self._vertexUniformsBuffer), offset: 0, index: Int(MT6VertexUniformsBuffer.rawValue))
            encoder.setBuffer(
                self._drawArgumentsBuffer, offset: 0, index: Int(MT6DrawArgumentsBuffer.rawValue))
            encoder.setBuffer(
                self._shadowArgBuffer, offset: 0, index: Int(MT6ShadowsArgumentsBuffer.rawValue))
            
            encoder.useResource(_indirectCommandB, usage: .write)
            encoder.useResource(_fragmentUniformsBuffer, usage: .read)
            encoder.useResource(_sceneBuffer, usage: .read)
            encoder.useHeap(MT6Scene.staticGPUHeap)
            encoder.useResource(
                _shadowArgBuffer, usage: .read)
            
            // shadow arguments @{
            _shadowArgumentEncoder.setTexture(_shadowTexture, index: 0)
            //@}
            
            for mesh in _scene.mtkMeshes {
                for submesh in mesh.submeshes {
                    encoder.useResource(
                        mesh.vertexBuffers[Int(MT6VertexBuffer.rawValue)].buffer,
                        usage: .read)
                    encoder.useResource(
                        mesh.vertexBuffers[Int(MT6TextureCoordinatesBuffer.rawValue)].buffer,
                        usage: .read)
                    encoder.useResource(
                        submesh.indexBuffer.buffer, usage: .read)
                    encoder.useResource(
                        _materialArgBuffer, usage: .read)
                }
            }
            
            let threadExecutionWidth = _drawKernelPSO.threadExecutionWidth
            let threads = MTLSize(width: _scene.computedNSubmeshes, height: 1, depth: 1)
            encoder.dispatchThreads(
              threads,
              threadsPerThreadgroup: 
                MTLSize(width: threadExecutionWidth, height: 1, depth: 1))
        },
        render:
        { renderEncoder in
            
            _encodeStage(using: renderEncoder, label: "GBuffer")
            {
                renderEncoder.setRenderPipelineState(_gBufferPSO)
                renderEncoder.setDepthStencilState(_depthStencilState)
                renderEncoder.executeCommandsInBuffer(
                    _indirectCommandB, range: 0..<_scene.computedNSubmeshes)
            }
            
            _encodeStage(using: renderEncoder, label: "Compose")
            {
                renderEncoder.setRenderPipelineState(_displayPipelineState)
                renderEncoder.setDepthStencilState(_displayDepthStencilState)
                
                renderEncoder.setCullMode(.back)
                renderEncoder.setStencilReferenceValue(128)
                
                
                //set g buffer textures
                renderEncoder.setFragmentBytes(&_fragmentUniforms, length: MemoryLayout<MT6FragmentUniforms>.size, index: Int(MT6FragmentUniformsBuffer.rawValue))
                
                renderEncoder.setVertexBuffer(_quadVertexBuffer,
                                               offset: 0,
                                               index: 0)
                // Draw full screen quad
                renderEncoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 6)
            }
            
            commandBuffer.present(drawable)
        })
        
        commandBuffer.commit()
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
                    
        customize(rndPipStatDescriptor)
        
        do {
            return try _device.makeRenderPipelineState(descriptor: rndPipStatDescriptor)
        }
        catch
        {
            fatalError("Could not create render pipeline state object: \(error)")
        }
    }
    
    private func _buildUniforms(_ view:MTKView, scene: MT6Scene) -> ([MT6VertexUniforms], MT6FragmentUniforms)
    {
        let lightPosition = scene.optionalLightPosition ?? scene.bbox.maxBounds + SIMD3<Float>(30,30,20)
        let center = (scene.bbox.maxBounds + scene.bbox.minBounds)*0.5
        let extent = scene.bbox.maxBounds - scene.bbox.minBounds;

        // tutorial 4 - shadows
        let shadowViewMatrix = float4x4(origin: lightPosition, target: center, up: SIMD3<Float>(0,1,0))
        let shadowProjectionMatrix = float4x4(perspectiveProjectionFov:  45/180 * Float.pi, aspectRatio: 1, nearZ: 0.1, farZ: 10000)
        
        //world to camera view
        var viewMatrix:float4x4!
        var projectionMatrix: float4x4!
        var aspectRatio: Float!
        if let camera = scene.optionalCamera
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
        
        var vertexUniformsArray = [MT6VertexUniforms]()
        for instanceMatrix in scene.instancesMatrices {
        
            let modelView = instanceMatrix != nil ? viewMatrix! * instanceMatrix! : viewMatrix!
            let modelViewProjection = projectionMatrix * modelView
            
            let shadowModelView = instanceMatrix != nil ? shadowViewMatrix * instanceMatrix! : shadowViewMatrix
            let shadowModelViewProjection = shadowProjectionMatrix * shadowModelView

            // transformations necessary to handle correctly normals
            // \see https://www.scratchapixel.com/lessons/mathematics-physics-for-computer-graphics/geometry/transforming-normals
            let indeces = SIMD3<Int>(0,1,2)
            let modelViewInverseTransposeMatrix = float3x3(
                                        modelView.columns.0[indeces],
                                        modelView.columns.1[indeces],
                                        modelView.columns.2[indeces]).transpose.inverse
            
            let vertexUniforms = MT6VertexUniforms(
                modelViewMatrix: modelView,
                modelViewInverseTransposeMatrix: modelViewInverseTransposeMatrix,
                modelViewProjectionMatrix: modelViewProjection,
                shadowModelViewProjectionMatrix: shadowModelViewProjection
            )
            vertexUniformsArray.append(vertexUniforms)
        }
        
        let viewLightPosition =  viewMatrix * SIMD4<Float>(lightPosition, 1);
        let fragmentUniforms = MT6FragmentUniforms(viewLightPosition: viewLightPosition)

        return (vertexUniformsArray, fragmentUniforms)
    }
    
    private func _initUniformBuffers(_ vertexUniformsArray: [MT6VertexUniforms], _ fragmentUniforms: MT6FragmentUniforms) {
        let vertexBufferLength = MemoryLayout<MT6VertexUniforms>.stride
        _vertexUniformsBuffer = _device.makeBuffer(length: vertexBufferLength * vertexUniformsArray.count, options: [])
        _vertexUniformsBuffer.label = "Vertex Uniforms Array"

        let fragmentBufferLength = MemoryLayout<MT6FragmentUniforms>.stride
        _fragmentUniformsBuffer = _device.makeBuffer(length: fragmentBufferLength, options: [])
        _fragmentUniformsBuffer.label = "Fragment Uniforms"
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
    private func _encodeGPUPass(into commandBuffer: MTLCommandBuffer,
                    using descriptor: MTLRenderPassDescriptor,
                    label: String,
                    compute computeEncodingBlock: (MTLComputeCommandEncoder) -> Void,
                    render renderEncodingBlock: (MTLRenderCommandEncoder) -> Void) {
        
        guard let computeEncoder = commandBuffer.makeComputeCommandEncoder() else {
            fatalError("Failed to make compute command encoder")
        }
        computeEncoder.label = "\(label)-compute"
        computeEncodingBlock(computeEncoder)
        computeEncoder.endEncoding()
        
        guard let renderEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: descriptor) else {
            fatalError("Failed to make render command encoder with: \(descriptor.description)")
        }
        renderEncoder.label = "\(label)-render"
        renderEncodingBlock(renderEncoder)
        renderEncoder.endEncoding()
    }
    
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
    
    func _buildIndirectCommandBuffer(_ scene: MT6Scene) -> MTLIndirectCommandBuffer {
      let desc = MTLIndirectCommandBufferDescriptor()
        desc.commandTypes = [.drawIndexed]
        desc.inheritBuffers = false
        //can't bind more than that
        desc.maxVertexBufferBindCount = 25
        desc.maxFragmentBufferBindCount = 25
        //< in this way you can avoid resetting the pso
        desc.inheritPipelineState = true

        // ( you need to knwo in advance the number of draw calls )
        guard let indirectBuffer = _device.makeIndirectCommandBuffer(
          descriptor: desc,
          maxCommandCount: _scene.computedNSubmeshes,
          options: []) else { fatalError("Failed to create ICB") }

        return indirectBuffer
    }
    
    
    //tutorial 6 - GPU Rendering
    private var _scene: MT6Scene
    private var _indirectCommandB: MTLIndirectCommandBuffer! = nil
    private var _computeKernelIndirectCommandBuffer: MTLBuffer! = nil
    private var _vertexUniformsArray = [MT6VertexUniforms]()
    private var _vertexUniformsBuffer: MTLBuffer!
    private var _fragmentUniforms : MT6FragmentUniforms!
    private var _fragmentUniformsBuffer : MTLBuffer!
    
    //tutorial 4 - Shadows
    private var _shadowPSO :MTLRenderPipelineState!
    private var _shadowTexture: MTLTexture!
    
    //tutorial 3 - Deferred Rendering
    private var _gBuffer : GBuffer!
    private var _gBufferPSO:MTLRenderPipelineState!
    // Mesh buffer for simple Quad
    private let _quadVertexBuffer: BufferView<MT6ScreenVertex>
    
    private lazy var _displayDepthStencilState = {
        let descriptor = MTLDepthStencilDescriptor()
        descriptor.label = "display depth stencil"
        if let depthStencilState = self._device.makeDepthStencilState(descriptor: descriptor) {
            return depthStencilState
        } else {
            fatalError("Failed to create depth-stencil state.")
        }
    }()
    
    // depth stencil
    private let _depthStencilState: MTLDepthStencilState
    
    //tutorial 1 - basic
    private let _metalView:MTKView!
    private let _device:MTLDevice!
    private let _commandQueue:MTLCommandQueue!
    private var _displayPipelineState: MTLRenderPipelineState!
    private var _viewportSize = vector_uint2(100,100)
    private var _library : MTLLibrary! = nil
    
    //@}
    
}
