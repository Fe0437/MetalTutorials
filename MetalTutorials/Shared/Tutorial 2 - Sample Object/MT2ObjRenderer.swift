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

/// tutorial 2 - Sample object

/// 🥷: Main class that is managing all the rendering of the view.
/// in the Tutorial1 this class was hidden inside the UIViewRepresentable, now it is a standalone class.
class MT2ObjRenderer : NSObject, MTKViewDelegate {
    
    /**
     init pipeline and load the obj asset
     */
    init(metalView: MTKView, objName:String) {
        _metalView = metalView
        _device = _metalView.device
        
        // create the command queue
        _commandQueue = _device.makeCommandQueue()
        
        // load the asset
        let meshAsset = MT2ObjRenderer._loadObj(
            objName: objName,
            device: _device
        )
        // build the depth stencil state for the pipeline
        _depthStencilState = MT2ObjRenderer._buildDepthStencilState(device: _device)
        
        super.init()
        
        _retrieveDataFromAsset(meshAsset)
        _pipelineState = _buildPipeline(
            vertexFunction: "MT2::vertex_main",
            fragmentFunction: "MT2::fragment_main"
        )
    }
    
    //MARK: class public configurations @{
   
   /// @group public configurations
   struct ModelConfigs
   {
       var shouldRotateAroundBBox: Bool = true
   }
   
   /// @group public configurations
   struct Camera
   {
       // identity
       var rotation = simd_quatf(real: 1, imag: SIMD3<Float>(0, 0, 0))
       var fov: Float = Float.pi / 3
       var nearZ: Float = 0.1
       var farZ: Float = 100
   }

   /// @group public configurations
   func setLightPosition(_ lightPosition: SIMD3<Float>)
   {
       _lightPosition = lightPosition;
   }
   
   /// @group public configurations
   func setModelConfigs(_ modelConfigs: ModelConfigs)
   {
       _modelConfigs = modelConfigs
   }
   
   /// @group public configurations
   func setCamera(camera:Camera)
   {
       _camera = camera
   }
   
   // class public configurations @}

   //MARK: MTKViewDelegate methods @{
    
    ///whenever the size changes or orientation changes
    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        _viewportSize.x = UInt32(size.width)
        _viewportSize.y = UInt32(size.height)
    } 
       
    ///here you create a command buffer
    ///encode commands that tells to the gpu what to draw
    func draw(in view: MTKView) {

        // compute the current rotation angle every frame
        _computeCurrentRotationAngle()
        //print("rotation is \(_currentAngle)")
        
        //check if we want to retrieve the rendered image
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

    //@}

    //MARK: class private @{
    
    /// main function that renders the object
    /// Parameters:
    /// - view: the MTKView to render into
    /// - completedHandler: the handler that will be called when the rendering is completed
    private func _render(with view: MTKView, completedHandler: ((MTLTexture)-> Void)? = nil) {
        /// create the new command buffer for this pass
        let commandBuffer = _commandQueue.makeCommandBuffer()!
        commandBuffer.label = "Tutorial2Commands"
        
        // take the current render pass descriptor, we are going to use that one to render.
        let passDesc = view.currentRenderPassDescriptor!
        let drawable:MTLDrawable! = view.currentDrawable
        let currentTexture = view.currentDrawable!.texture
        
        // now creates a render command encoder to start
        // encoding of rendering commands
        let commandEncoder:MTLRenderCommandEncoder! = commandBuffer.makeRenderCommandEncoder(descriptor: passDesc)
        commandEncoder.label = "Tutorial2RenderCommandEncoder"  

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

    /// take the MTKMeshes from the MDSLAsset
    /// Parameter meshAsset: the asset to take the meshes from
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
    
    /// compute the current rotation angle to rotate the imported object at every rendered frame
    private func _computeCurrentRotationAngle() {
        let time = CACurrentMediaTime()
        
        if _currentTime != nil {
            let elapsed = time - _currentTime!
//            print("elapsed is \(elapsed)")
            _currentAngle -= elapsed
        }
        _currentTime = time
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
    
    /// depth stencil
    /// !without this is gonna render -- but it will not be able to
    /// understand what is behind and what is not
    static private func _buildDepthStencilState(device: MTLDevice) -> MTLDepthStencilState {
        let depthStencilDescriptor = MTLDepthStencilDescriptor()
        // whether a fragment passes the so-called depth test
        depthStencilDescriptor.depthCompareFunction = .less
        depthStencilDescriptor.isDepthWriteEnabled = true
        return device.makeDepthStencilState(descriptor: depthStencilDescriptor)!
    }
        
    
    //tutorial 2 - Sample object
    
    /// position of the light from max bounds of the object
    var _lightPosition = SIMD3<Float>(20,20,10)
    var _modelConfigs = ModelConfigs()
    var _camera = Camera()
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
    var _pipelineState:MTLRenderPipelineState?
    var _viewportSize = vector_uint2(100,100)

    //@}
    
}
