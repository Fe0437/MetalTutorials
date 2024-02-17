//
//  MT2Uniforms.h
//  MetalTutorials
//
//  Created by federico forti on 14/03/2021.
//

#ifndef MT2Uniforms_h
#define MT2Uniforms_h

#include <simd/simd.h>

struct MT2VertexUniforms
{
    matrix_float4x4 modelViewMatrix;
    matrix_float3x3 modelViewInverseTransposeMatrix;
    matrix_float4x4 modelViewProjectionMatrix;
};

struct MT2FragmentUniforms
{
    simd_float4 viewLightPosition;
};


#endif /* MT2Uniforms_h */
