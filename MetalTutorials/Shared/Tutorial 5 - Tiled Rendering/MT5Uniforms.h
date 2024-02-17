//
//  MT5Uniforms.h
//  MetalTutorials
//
//  Created by federico forti on 14/03/2021.
//

#ifndef MT5Uniforms_h
#define MT5Uniforms_h

#include <simd/simd.h>

struct MT5VertexUniforms
{
    matrix_float4x4 modelViewMatrix;
    matrix_float3x3 modelViewInverseTransposeMatrix;
    matrix_float4x4 modelViewProjectionMatrix;
    
    //tutorial 4 - shadows
    matrix_float4x4 shadowModelViewProjectionMatrix;

};

struct MT5FragmentUniforms
{
    simd_float4 viewLightPosition;
};

// Buffer index values shared between shader and C code to ensure Metal shader buffer inputs match
//   Metal API buffer set calls
typedef enum MT5BufferIndices
{
    MT5BufferIndexMeshPositions     = 0

} MT5BufferIndices;

typedef struct {
    vector_float2 position;
} MT5ScreenVertex;

#endif /* MT5Uniforms_h */
