//
//  MetalTutorials
//
//  Created by federico forti on 05/03/2021.
//

#include <metal_stdlib>
#include "MT1Vertex.h"

using namespace metal;

namespace MT1 {
    
    /// Vertex shader outputs and fragment shader inputs
    struct RasterizerData
    {
        // The [[position]] attribute of this member indicates that this value
        // is the clip space position of the vertex when this structure is
        // returned from the vertex function.
        float4 position [[position]];
        
        // Since this member does not have a special attribute, the rasterizer
        // interpolates its value with the values of the other triangle vertices
        // and then passes the interpolated value to the fragment shader for each
        // fragment in the triangle.
        float4 color;
    };
    
    /**
     @brief simple vertex shader for small buffers of vertices
     - Parameter vertices: as [[buffer(0)]] ( only for single-use data smaller than 4 KB )
     - Parameter viewportSizePointer: as [[buffer(1)]] passed like vertices but it is only the data for the viewport size
     
     - Returns: output to the fragment shader
     */
    vertex RasterizerData
    VertexShader(uint vertexID [[vertex_id]],
                    constant MT1Vertex *vertices [[buffer(0)]],
                    constant vector_uint2 *viewportSizePointer [[buffer(1)]])
    {
        RasterizerData out;
        
        // Index into the array of positions to get the current vertex.
        // The positions are specified in pixel dimensions (i.e. a value of 100
        // is 100 pixels from the origin).
        float2 pixelSpacePosition = vertices[vertexID].position.xy;
        
        // Get the viewport size and cast to float.
        vector_float2 viewportSize = vector_float2(*viewportSizePointer);
        
        
        // To convert from positions in pixel space to positions in clip-space,
        //  divide the pixel coordinates by half the size of the viewport.
        out.position = vector_float4(0.0, 0.0, 0.0, 1.0);
        out.position.xy = pixelSpacePosition / (viewportSize / 2.0);
        
        // Pass the input color directly to the rasterizer.
        out.color = vertices[vertexID].color;
        
        return out;
    }
    
    /**
     Using the stage_in attribute, the shader can look at the pipeline’s vertex descriptor and
     see what format the input buffer is in, and then match it with the struct as declared in the argument
     */
    fragment float4 FragmentShader(RasterizerData in [[stage_in]])
    {
        // Return the interpolated color.
        return in.color;
    }
    
}

