//
//  MT4Uniforms.h
//  MetalTutorials
//
//  Created by federico forti on 14/03/2021.
//

#ifndef MT4Uniforms_h
#define MT4Uniforms_h

#include <simd/simd.h>

struct MT4VertexUniforms
{
    matrix_float4x4 modelViewMatrix;
    matrix_float3x3 modelViewInverseTransposeMatrix;
    matrix_float4x4 modelViewProjectionMatrix;
    
    //tutorial 4 - shadows
    matrix_float4x4 shadowModelViewProjectionMatrix;

};

struct MT4FragmentUniforms
{
    simd_float4 viewLightPosition;
};

// Buffer index values shared between shader and C code to ensure Metal shader buffer inputs match
//   Metal API buffer set calls
typedef enum MT4BufferIndices
{
    MT4BufferIndexMeshPositions     = 0

} MT4BufferIndices;

typedef struct {
    vector_float2 position;
} MT4ScreenVertex;

#endif /* MT4Uniforms_h */
