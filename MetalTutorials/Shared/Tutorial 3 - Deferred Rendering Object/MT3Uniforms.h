//
//  MT3Uniforms.h
//  MetalTutorials
//
//  Created by federico forti on 14/03/2021.
//

#ifndef MT3Uniforms_h
#define MT3Uniforms_h

#include <simd/simd.h>

struct MT3VertexUniforms
{
    matrix_float4x4 modelViewMatrix;
    matrix_float3x3 modelViewInverseTransposeMatrix;
    matrix_float4x4 modelViewProjectionMatrix;
};

struct MT3FragmentUniforms
{
    simd_float4 viewLightPosition;
};

// Buffer index values shared between shader and C code to ensure Metal shader buffer inputs match
// Metal API buffer set calls
typedef enum MT3BufferIndices
{
    MT3BufferIndexMeshPositions     = 0

} MT3BufferIndices;

// basic 2d vertex used to render the full screen quad that composes the GBuffer
// lighting happens in this pass but we only to render a full screen quad
struct MT3BasicVertex {
    vector_float2 position;
};

#endif /* MT3Uniforms_h */
