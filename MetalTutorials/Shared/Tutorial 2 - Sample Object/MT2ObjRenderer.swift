//
//  MT2Renderer.swift
//  MetalTutorials
//
//  Created by federico forti on 14/03/2021.
//

import MetalKit
import ModelIO

//use for future and promises
import Combine
import simd

/**
 Main class that is managing all the rendering of the view.
 It is intialized with the parent MetalView that use also to take the mtkview
 */
class MT2ObjRenderer : NSObject, MTKViewDelegate {
    
    /**
     init pipeline and load the obj asset
     */
    init(metalView: MTKView, objName:String) {
        _metalView = metalView
        _device = _metalView.device
        
        // create the command queue
        _commandQueue = _device.makeCommandQueue()
        
        let meshAsset = MT2ObjRenderer._loadObj(
            objName: objName,
            device: _device
        )
        // depth stencil
        _depthStencilState = MT2ObjRenderer._buildDepthStencilState(device: _device)
        
        super.init()
        
        _retrieveDataFromAsset(meshAsset)
        _pipelineState = _buildPipeline(
            vertexFunction: "MT2::vertex_main",
            fragmentFunction: "MT2::fragment_main"
        )
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
    
    ///whenever the size changes or orientation changes
    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        _viewportSize.x = UInt32(size.width)
        _viewportSize.y = UInt32(size.height)
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
            print("elapsed is \(elapsed)")
            _currentAngle -= elapsed
        }
        _currentTime = time
    }
    
    private func _render(with view: MTKView, completedHandler: ((MTLTexture)-> Void)? = nil) {
        /// create the new command buffer for this pass
        let commandBuffer = _commandQueue.makeCommandBuffer()!
        commandBuffer.label = "Tutorial2Commands"
        
        let passDesc = view.currentRenderPassDescriptor!
        let drawable:MTLDrawable! = view.currentDrawable
        let currentTexture = view.currentDrawable!.texture
        
        // now creates a render command encoder to start
        // encoding of rendering commands
        let commandEncoder:MTLRenderCommandEncoder! = commandBuffer.makeRenderCommandEncoder(descriptor: passDesc)
        commandEncoder.label = "Tutorial2RenderCommandEncoder"
        
        _computeCurrentRotationAngle()
        
        print("rotation is \(_currentAngle)")
        var uniforms = _buildUniforms(view)
        
        // The uniform values will now be available inside the vertex function as the parameter attributed with [[buffer(1)]].
        commandEncoder.setVertexBytes(&uniforms.0, length: MemoryLayout<MT2VertexUniforms>.size, index: 1)
        
        // The uniform values will now be available inside the fragment function as the parameter attributed with [[buffer(1)]].
        commandEncoder.setFragmentBytes(&uniforms.1, length: MemoryLayout<MT2FragmentUniforms>.size, index: 1)
        
        // init the MTLViewport from the metal library
        let viewport = _buildViewport()
        commandEncoder.setViewport(viewport)
        commandEncoder.setRenderPipelineState(_pipelineState!)
        commandEncoder.setDepthStencilState(_depthStencilState)
        
        // real drawing of the primitive
        for mesh in _meshes {
            let vertexBuffer = mesh.vertexBuffers.first!
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
        
        if let completedHandlerCallable = completedHandler {
            commandBuffer.addCompletedHandler
            {
                _ in
                completedHandlerCallable(currentTexture)
            }
        }

        commandEncoder.endEncoding()
        commandBuffer.present(drawable)
        commandBuffer.commit()
        
    }
    
    ///here you create a command buffer
    ///encode commands that tells to the gpu what to draw
    func draw(in view: MTKView) {
        if let retrieveImageDelegate = _retrieveImageDelegate
        {
            
            view.framebufferOnly = false
            (view.layer as! CAMetalLayer).allowsNextDrawableTimeout = false
            view.colorPixelFormat = MTLPixelFormat.bgra8Unorm;
            
            _render(with: view, completedHandler: retrieveImageDelegate)
        }
        else{
            _render(with: view)
        }
    }
        
    /// method to retrieve the uiimage from a mtl texture without passing through a CIImage (not reccomended)
    private static func _retrieveUIImageWithoutCIImage(_ texture: MTLTexture) -> UIImage {
        let pixelFormat = texture.pixelFormat;
        
        assert(
            pixelFormat == MTLPixelFormat.bgra8Unorm ||
                pixelFormat == MTLPixelFormat.r32Uint, "Unsupported pixel format: \(pixelFormat)")
        
        let bytesPerPixel = 4
        let bytesPerRow   = texture.width * bytesPerPixel;
        let bytesPerImage = texture.height * bytesPerRow;
        
        // An empty buffer that will contain the image
        var pixelBytes = [UInt8](repeating: 0, count: Int(bytesPerImage))
        texture.getBytes(&pixelBytes, bytesPerRow: bytesPerRow, from: MTLRegionMake2D(0, 0, texture.width, texture.height), mipmapLevel: 0)
        
        // Creates an image context
        let bitmapInfo = CGBitmapInfo(rawValue: (CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue))
        let bitsPerComponent = 8
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let context = CGContext(data: &pixelBytes, width: texture.width, height: texture.height, bitsPerComponent: bitsPerComponent, bytesPerRow: bytesPerRow, space: colorSpace, bitmapInfo: bitmapInfo.rawValue)
        
        // Creates the image from the graphics context
        let dstImage = context!.makeImage()
        
        // Creates the final UIImage
        return UIImage(cgImage: dstImage!, scale: 0.0, orientation: .up)
    }
    
    func getRenderedImage(in view: MTKView) -> CIImage
    {
        _imageRenderedCondition.wait()
        return _imageRendered!
    }
    
    private var _imageRenderedCondition:NSCondition = NSCondition()
    private var _retrieveImageDelegate:((_ texture:MTLTexture)->Void )?
    private var _imageRendered:CIImage?
    
    func shouldRetrieveRenderedUIImage(_ should:Bool)
    {
        if should
        {
            _retrieveImageDelegate =
            { (texture) in
                //self._imageRendered = CIImage(mtlTexture: texture)
                self._imageRendered = MT2ObjRenderer._retrieveUIImageWithoutCIImage(texture).ciImage
                self._imageRenderedCondition.signal()
            }
        }
        else
        {
            _retrieveImageDelegate = nil
        }
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
    
    private func _buildUniforms(_ view:MTKView) -> (MT2VertexUniforms, MT2FragmentUniforms)
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
        
        let vertexUniforms = MT2VertexUniforms(
            modelViewMatrix: modelView,
            modelViewInverseTransposeMatrix: modelViewInverseTransposeMatrix,
            modelViewProjectionMatrix: modelViewProjection
        )
        
        let fragmentUniforms = MT2FragmentUniforms(viewLightPosition: viewLightPosition)
        
        return (vertexUniforms, fragmentUniforms)
    }
    
    private func _buildViewport() -> MTLViewport {
        return MTLViewport(originX: 0.0, originY: 0.0, width: Double(_viewportSize.x), height: Double(_viewportSize.y), znear: 0.0, zfar: 1.0)
    }
    
    private func _buildPipeline(vertexFunction:String, fragmentFunction:String) -> MTLRenderPipelineState?  {
        let library = _device.makeDefaultLibrary()!
        
        //create the vertex and fragment shaders_
        let vertexFunction = library.makeFunction(name: vertexFunction)
        let fragmentFunction = library.makeFunction(name: fragmentFunction)
        
        //create the pipeline we will run during draw
        //this pipeline will use the vertex and fragment shader we have defined here
        let rndPipStatDescriptor = MTLRenderPipelineDescriptor()
        rndPipStatDescriptor.label = "Tutorial2"
        rndPipStatDescriptor.vertexFunction = vertexFunction
        rndPipStatDescriptor.fragmentFunction = fragmentFunction
        
        //they have to match
        _metalView.colorPixelFormat = .bgra8Unorm_srgb
        rndPipStatDescriptor.colorAttachments[0].pixelFormat = .bgra8Unorm_srgb
        
        // depth stencil @{
        
        //they have to match
        _metalView.depthStencilPixelFormat = .depth32Float
        rndPipStatDescriptor.depthAttachmentPixelFormat = .depth32Float
        // @}
        
        //this time we need this otherwise
        rndPipStatDescriptor.vertexDescriptor = _vertexDescriptor
        
        var pipelineState:MTLRenderPipelineState? = nil
        do {
            pipelineState = try _device.makeRenderPipelineState(descriptor: rndPipStatDescriptor)
        }
        catch
        {
            fatalError("Could not create render pipeline state object: \(error)")
        }
        
        return pipelineState
    }
    
    // depth stencil @{
    // !without this is gonna render -- but it will not be able to
    // understand what is behind and what is not
    static private func _buildDepthStencilState(device: MTLDevice) -> MTLDepthStencilState {
        let depthStencilDescriptor = MTLDepthStencilDescriptor()
        // whether a fragment passes the so-called depth test
        depthStencilDescriptor.depthCompareFunction = .less
        depthStencilDescriptor.isDepthWriteEnabled = true
        return device.makeDepthStencilState(descriptor: depthStencilDescriptor)!
    }
    // @}
    
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
    
    //tutorial2 - scene setup
    var _optionalLightPosition: SIMD3<Float>?
    var _modelConfigs:ModelConfigs = ModelConfigs()
    var _optionalCamera:Camera?
    
    //tutorial2 - obj render
    var _objboundingBox:MDLAxisAlignedBoundingBox!
    var _currentAngle:Double = 0
    var _currentTime:CFTimeInterval?
    var _meshes:[MTKMesh]!
    var _vertexDescriptor: MTLVertexDescriptor!
    // depth stencil
    let _depthStencilState: MTLDepthStencilState
    
    //tutorial 1 - basic
    let _metalView:MTKView!
    let _device:MTLDevice!
    let _commandQueue:MTLCommandQueue!
    var _pipelineState:MTLRenderPipelineState?
    var _viewportSize = vector_uint2(100,100)
    
}
