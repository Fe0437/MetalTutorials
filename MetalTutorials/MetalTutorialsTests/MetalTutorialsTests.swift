//
//  MetalTutorialsTests.swift
//  MetalTutorialsTests
//
//  Created by federico forti on 20/07/2021.
//

import XCTest
import MetalKit
import CoreImageExtensions

@testable import MetalTutorials

extension CGImage {
    subscript (x: Int, y: Int) -> CGColor? {
        guard x >= 0 && x < Int(width) && y >= 0 && y < Int(height),
            let provider = self.dataProvider,
            let providerData = provider.data,
            let data = CFDataGetBytePtr(providerData) else {
            return nil
        }

        let numberOfComponents = 4
        let pixelData = ((Int(width) * y) + x) * numberOfComponents

        let r = CGFloat(data[pixelData]) / 255.0
        let g = CGFloat(data[pixelData + 1]) / 255.0
        let b = CGFloat(data[pixelData + 2]) / 255.0
        let a = CGFloat(data[pixelData + 3]) / 255.0

        return CGColor(red: r, green: g, blue: b, alpha: a)
    }
}

class MetalTutorialsTests: XCTestCase {
    
    private let context:CIContext = CIContext()

    override func setUpWithError() throws {
        // Put setup code here. This method is called before the invocation of each test method in the class.
    }

    override func tearDownWithError() throws {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
    }

    func testMT2RenderingOfABunny() throws {
        let mtkView = MTKView(frame: CGRect(x: 0, y: 0, width: 512, height: 512))
        guard let device = MTLCreateSystemDefaultDevice() else {
            fatalError( "Failed to get the system's default Metal device." )
        }
        
        mtkView.device = device
        mtkView.isPaused = true
        mtkView.enableSetNeedsDisplay = false
        mtkView.clearColor = MTLClearColorMake(0.0, 0.0, 0.0, 1.0);

        // This is an example of a functional test case.
        // Use XCTAssert and related functions to verify your tests produce the correct results.
        
        let renderer = MT2ObjRenderer(metalView: mtkView, objName: "bunny")
        mtkView.delegate = renderer
        
        renderer.setLightPosition(SIMD3<Float>(100,0,30))
        let camera = MT2ObjRenderer.Camera()
        renderer.setCamera(camera: camera)
        renderer.setModelConfigs(MT2ObjRenderer.ModelConfigs(shouldRotateAroundBBox: false))
        renderer.shouldRetrieveRenderedUIImage(true)
        mtkView.draw()
        
        let renderedImage = renderer.getRenderedImage(in: mtkView)
        let bundle = Bundle(for: MetalTutorialsTests.self)
        let testImage = CIImage(named: "MT2BunnyTest", in: bundle)!

        let differenceImage = CIBlendKernel.difference.apply(foreground: renderedImage, background: testImage)!
        let squaredImage = CIBlendKernel.multiply.apply(foreground: differenceImage, background: differenceImage)!
        let averageColorImage = squaredImage.applyingFilter("CIAreaAverage")
        let averageColorCGImage = CIContext().createCGImage(averageColorImage, from: CGRect(origin: CGPoint.zero, size: CGSize(width: 512,height: 512)))!
        let averageColor = averageColorCGImage[0,0]!.components!
        let RMSE = ((averageColor[0]+averageColor[1]+averageColor[2])*0.333).squareRoot()
        XCTAssertLessThan(  RMSE  , 0.1)
    }

    func testPerformanceExample() throws {
        // This is an example of a performance test case.
        measure {
            // Put the code you want to measure the time of here.
        }
    }

}
