//
//  MT6Scene.swift
//  MetalTutorials
//
//  Created by federico forti on 24/02/24.
//

import Foundation
import MetalKit
import ModelIO
import OSLog

/// @group public configurations
struct MT6ModelConfigs
{
    var shouldRotateAroundBBox: Bool = true
}

/// @group public configurations
struct MT6Camera
{
    // identity
    var rotation = simd_quatf(real: 1, imag: SIMD3<Float>(0, 0, 0))
    var fov: Float = Float.pi / 3
    var nearZ: Float = 0.1
    var farZ: Float = 100
}

/// 🌆: Scene to render
/// here are grouped all the methods and properties of the scene we want to render.
class MT6Scene : MT6SceneDelegate {
    
    let basePlaneAssetFile = "base-plane.usdz"
        
    init(device: MTLDevice, commandQueue: MTLCommandQueue, assetFileName: String)
    {
        Self._device = device
        Self._commandQueue = commandQueue

        let mainAsset = Self._loadMDLAsset(assetName: assetFileName, device: device)
        _retrieveDataFromAsset(mainAsset)
        bbox = mainAsset.boundingBox
        instancesMatrices.append(contentsOf: repeatElement(computeModelMatrix(), count: computedNSubmeshes))
        
        let plane = Self._loadMDLAsset(assetName: basePlaneAssetFile, device: device)
        _retrieveDataFromAsset(plane)
        instancesMatrices.append(computePlaneMatrix())
        
        mapMTKSubmeshToMDLMesh = [MTKSubmesh: MDLSubmesh](uniqueKeysWithValues: zip(mtkMeshes.flatMap({$0.submeshes}), (_mdlMeshes.flatMap({$0.submeshes ?? []}) as! [MDLSubmesh])))
        
        MT6Scene.loopThroughMaterialProperties(in: mapMTKSubmeshToMDLMesh, with: [.baseColor, .specular, .tangentSpaceNormal]){ submesh, property in
            
            if property.type == .texture {
                if property.textureSamplerValue != nil {
                    _ = Self._textureIndexing(propertyName: Self.getUniqueTexName(submesh, property), textureSampler: property.textureSamplerValue!)
                }
            }
        }
        
        guard let heap = Self._buildHeap(commandQueue: commandQueue) else {
            fatalError("cannot initialize heap")
        }
        Self.staticGPUHeap = heap
    }
    
    static func getUniqueTexName(_ submesh: MTKSubmesh, _ property: MDLMaterialProperty) -> String {
        return "\(submesh.mesh!.name.split(separator: "-")[0])-\(property.name)"
    }
    
    /// class public configurations @{
    ///
    func setLightPosition(_ lightPosition: SIMD3<Float>)
    {
        _lightPosition = lightPosition;
    }
    
    func setModelConfigs(_ modelConfigs: MT6ModelConfigs)
    {
        _modelConfigs = modelConfigs
    }
    
    func setCamera(camera: MT6Camera)
    {
        _camera = camera
    }
    
    private var _lightPosition = SIMD3<Float>(20,20,10)
    var worldLightPosition : SIMD3<Float> {
        bbox.maxBounds + _lightPosition
    }
    private var _modelConfigs = MT6ModelConfigs()
    private var _camera = MT6Camera()
    /// @}

    
    private(set) var mtkMeshes = [MTKMesh]()
    private(set) var mapMTKSubmeshToMDLMesh = [MTKSubmesh: MDLSubmesh]()
    private(set) static var texNameToIndex = [String: Int]()

    private(set) lazy var vertexDescriptor: MTLVertexDescriptor! =  {MTKMetalVertexDescriptorFromModelIO(MT6Scene._mdlVertexDescriptor)}()
    private(set) var bbox: MDLAxisAlignedBoundingBox! = nil
    private(set) var instancesMatrices = [float4x4?]()
    private(set) static var staticGPUHeap: MTLHeap!
    
    var center : SIMD3<Float>{
        (bbox.maxBounds + bbox.minBounds)*0.5
    }
    
    var extent : SIMD3<Float> {
        bbox.maxBounds - bbox.minBounds;
    }
    
    var shadowViewMatrix : float4x4 {float4x4(origin: worldLightPosition, target: center, up: SIMD3<Float>(0,1,0))}
    var shadowProjectionMatrix : float4x4 { float4x4(perspectiveProjectionFov:  45/180 * Float.pi, aspectRatio: 1, nearZ: 0.1, farZ: 10000) }
    
    //world to camera view
    var viewMatrix : float4x4 { 
        let origin = _camera.rotation.act(SIMD3<Float>(0, 0, (2+extent.z)))
        return float4x4(origin: origin, target: SIMD3<Float>(0,0,0), up: SIMD3<Float>(0,1,0)) }
    
    func projectionMatrix(to size: CGSize) -> float4x4 {
        let aspectRatio = Float(size.width / size.height)
        return float4x4(perspectiveProjectionFov: _camera.fov, aspectRatio: aspectRatio, nearZ: _camera.nearZ, farZ: _camera.farZ)
    }
    
    static func getTexture(for submesh: MTKSubmesh, andProperty property: MDLMaterialProperty) -> MTLTexture? {
        guard let index = texNameToIndex[getUniqueTexName(submesh, property)] else {return nil}
        return _orderedMTLTextures[index]
    }

    var computedNSubmeshes : Int {
        mtkMeshes.reduce(0, {$0 + $1.submeshes.count})
    }
    
    func computeNewFrame(){
        if(_modelConfigs.shouldRotateAroundBBox){
            _computeCurrentRotationAngle()
        }else{
            //we could change configuration during rendering
            //thus we must reset the current time because we are
            //not tracking it anymore
            _currentTime = nil
        }
        instancesMatrices.removeAll(keepingCapacity: true)
        instancesMatrices.append(contentsOf: repeatElement(computeModelMatrix(), count: computedNSubmeshes-1))
        instancesMatrices.append(computePlaneMatrix())
    }
    
    func computeModelMatrix() -> float4x4? {
        let center = (bbox.maxBounds + bbox.minBounds)*0.5
        var modelMatrix = float4x4(translationBy: -center)
        //model to world
        modelMatrix =
            float4x4(rotationAbout: SIMD3<Float>(0, 1, 0), by: Float(_currentAngle)) * modelMatrix
    
        return modelMatrix
    }
    
    func computePlaneMatrix() -> float4x4? {
        let center = (bbox.maxBounds + bbox.minBounds)*0.5
        return float4x4(translationBy: -center) * float4x4(scaleBy: 100) * float4x4(rotationAbout: SIMD3<Float>(1, 0, 0), by: Float.pi * -0.5)
    }
    
    private func _retrieveDataFromAsset(_ mdlAsset: MDLAsset) {
        mdlAsset.loadTextures()

        guard
            let meshes = try? MTKMesh.newMeshes(asset: mdlAsset, device: MT6Scene._device)
         else {
            fatalError("Could not extract meshes from Model I/O asset")
        }
        
        meshes.metalKitMeshes.forEach({$0.name = "\(mdlAsset.hash)-\($0.name)"})
        _mdlMeshes.append(contentsOf: meshes.modelIOMeshes)
        mtkMeshes.append(contentsOf: meshes.metalKitMeshes)
    }
    
    private func _computeCurrentRotationAngle() {
        let time = CACurrentMediaTime()
        
        if _currentTime != nil {
            let elapsed = time - _currentTime!
            _currentAngle -= elapsed
        }
        _currentTime = time
    }
    
    private static func loopThroughMaterialProperties(in meshes: [MTKSubmesh : MDLSubmesh], with semantics: [MDLMaterialSemantic], _ body: (MTKSubmesh, MDLMaterialProperty) -> Void) {
        
        // Each mesh can have multiple submeshes, each with its own material
        for submesh in meshes {
            guard let material = submesh.value.material else {continue}
                for semantic in semantics {
                    // Materials have properties that could be textures
                    for property in material.properties(with: semantic) {
                        body(submesh.key, property)
                    }
                }
        }
    }
    
    static func _buildDescriptor(for texture: MTLTexture) -> MTLTextureDescriptor {
          let descriptor = MTLTextureDescriptor()
        descriptor.textureType = texture.textureType
        descriptor.pixelFormat = texture.pixelFormat
        descriptor.width = texture.width
        descriptor.height = texture.height
        descriptor.depth = texture.depth
        descriptor.mipmapLevelCount = texture.mipmapLevelCount
        descriptor.arrayLength = texture.arrayLength
        descriptor.sampleCount = texture.sampleCount
        descriptor.cpuCacheMode = texture.cpuCacheMode
        descriptor.usage = texture.usage
        descriptor.storageMode = texture.storageMode
        return descriptor
    }
    
    static func _textureIndexing(propertyName: String, textureSampler: MDLTextureSampler) -> Int?{
      guard let texture = textureSampler.texture else {
            fatalError("no texture in the sampler")
      }
        
      //first check if we have already loaded the texture
      if let index = texNameToIndex[propertyName] {
        return index
      }
        
      let textureLoader = MTKTextureLoader(device: _device)
    
      if let texture = try? textureLoader.newTexture(
        texture: texture)
      {
          _orderedMTLTextures.append(texture)
          texNameToIndex[propertyName] = _orderedMTLTextures.count - 1
          return texNameToIndex[propertyName]
      }
        
      return nil
    }
    
    static private var _mdlVertexDescriptor : MDLVertexDescriptor = {
        let mdlVertexDescriptor = MDLVertexDescriptor()
        var offset = 0
        mdlVertexDescriptor.attributes[Int(MT6Position.rawValue)]
        = MDLVertexAttribute(
            name: MDLVertexAttributePosition,
            format: .float3,
            offset: offset,
            bufferIndex:Int(MT6VertexBuffer.rawValue))
        
        offset += MemoryLayout<SIMD3<Float>>.stride
        
        mdlVertexDescriptor.attributes[Int(MT6Normal.rawValue)] =
        MDLVertexAttribute(
            name: MDLVertexAttributeNormal,
            format: .float3,
            offset: offset,
            bufferIndex: Int(MT6VertexBuffer.rawValue))
        
        offset += MemoryLayout<SIMD3<Float>>.stride
        
        mdlVertexDescriptor.attributes[Int(MT6Tangent.rawValue)] =
        MDLVertexAttribute(
            name: MDLVertexAttributeTangent,
            format: .float3,
            offset: offset,
            bufferIndex: Int(MT6VertexBuffer.rawValue))
        
        offset += MemoryLayout<SIMD3<Float>>.stride
        
        mdlVertexDescriptor.attributes[Int(MT6Bitanget.rawValue)] =
        MDLVertexAttribute(
            name: MDLVertexAttributeBitangent,
            format: .float3,
            offset: offset,
            bufferIndex: Int(MT6VertexBuffer.rawValue))
        
        offset += MemoryLayout<SIMD3<Float>>.stride
        
        mdlVertexDescriptor.layouts[Int(MT6VertexBuffer.rawValue)]
        = MDLVertexBufferLayout(stride: offset)
        
        // UVs
        mdlVertexDescriptor.attributes[Int(MT6TexCoords.rawValue)] =
        MDLVertexAttribute(
            name: MDLVertexAttributeTextureCoordinate,
            format: .float2,
            offset: 0,
            bufferIndex: Int(MT6TextureCoordinatesBuffer.rawValue))
        mdlVertexDescriptor.layouts[Int(MT6TextureCoordinatesBuffer.rawValue)]
        = MDLVertexBufferLayout(stride: MemoryLayout<SIMD2<Float>>.stride)
        
        return mdlVertexDescriptor
    }()
    
    private static func _loadMDLAsset(assetName: String, device: MTLDevice) -> MDLAsset
    {
        let modelURL = Bundle.main.url(forResource: assetName, withExtension: nil)!
        let bufferAllocator = MTKMeshBufferAllocator(device: device)
        let mdlAsset = MDLAsset(url: modelURL, vertexDescriptor: _mdlVertexDescriptor, bufferAllocator: bufferAllocator)
        return mdlAsset
    }
    
    private static func _buildPlane(device: MTLDevice) -> MDLAsset
    {
        let bufferAllocator = MTKMeshBufferAllocator(device: device)

        let mdlMesh = MDLMesh(
            planeWithExtent: vector_float3(repeating: 10), segments: vector_uint2(x: 2, y: 2), geometryType: .triangles, allocator: bufferAllocator)
        
        //this is also restructuring the mesh !!
        mdlMesh.vertexDescriptor = _mdlVertexDescriptor
        
        mdlMesh.addNormals(withAttributeNamed: MDLVertexAttributeNormal, creaseThreshold: 0)
        mdlMesh.addUnwrappedTextureCoordinates(forAttributeNamed: MDLVertexAttributeTextureCoordinate)
        try? mdlMesh.makeVerticesUniqueAndReturnError()
        
        let meshAsset = MDLAsset()
        meshAsset.add(mdlMesh)
        return meshAsset
    }
    

    static private func _buildHeap(commandQueue: MTLCommandQueue) -> MTLHeap? {
      let heapDescriptor = MTLHeapDescriptor()

      let descriptors = _orderedMTLTextures.map { texture in
          _buildDescriptor(for: texture)
      }
      let sizeAndAligns = descriptors.map { descriptor in
        _device.heapTextureSizeAndAlign(descriptor: descriptor)
      }
      heapDescriptor.size = sizeAndAligns.reduce(0) { total, sizeAndAlign in
        let size = sizeAndAlign.size
        let align = sizeAndAlign.align
        return total + size - (size & (align - 1)) + align
      }
      if heapDescriptor.size == 0 {
        return nil
      }

      guard let heap =
        _device.makeHeap(descriptor: heapDescriptor)
        else { return nil }

      let heapTextures = descriptors.map { descriptor -> MTLTexture in
        descriptor.storageMode = heapDescriptor.storageMode
        descriptor.cpuCacheMode = heapDescriptor.cpuCacheMode
        guard let texture = heap.makeTexture(descriptor: descriptor) else {
          fatalError("Failed to create heap textures")
        }
        return texture
      }

      guard
        let commandBuffer = commandQueue.makeCommandBuffer(),
        let blitEncoder = commandBuffer.makeBlitCommandEncoder()
      else { return nil }
        
      zip(_orderedMTLTextures, heapTextures)
        .forEach { texture, heapTexture in
          heapTexture.label = texture.label
          var region =
            MTLRegionMake2D(0, 0, texture.width, texture.height)
          for level in 0..<texture.mipmapLevelCount {
            for slice in 0..<texture.arrayLength {
              blitEncoder.copy(
                from: texture,
                sourceSlice: slice,
                sourceLevel: level,
                sourceOrigin: region.origin,
                sourceSize: region.size,
                to: heapTexture,
                destinationSlice: slice,
                destinationLevel: level,
                destinationOrigin: region.origin)
            }
            region.size.width /= 2
            region.size.height /= 2
          }
        }
      blitEncoder.endEncoding()
      commandBuffer.commit()
      //the new textures stored are the heap textures
      Self._orderedMTLTextures = heapTextures
      return heap
    }
    
    private static var _orderedMTLTextures = [MTLTexture]()
    static private var _device: MTLDevice!
    private var _mdlMeshes = [MDLMesh]()
    private var _currentAngle:Double = 0
    private var _currentTime:CFTimeInterval? = nil
    static var _commandQueue: MTLCommandQueue!
    
}
