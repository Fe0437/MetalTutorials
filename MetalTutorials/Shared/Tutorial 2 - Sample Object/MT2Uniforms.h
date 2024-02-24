//
//  MT2Uniforms.h
//  MetalTutorials
//
//  Created by federico forti on 14/03/2021.
//

#ifndef MT2Uniforms_h
#define MT2Uniforms_h

#include <simd/simd.h>

/// tutorial 2 - Sample Object
/// Introducing the uniforms which store the matrices to render the object on the screen
/// and the light position which is used in the fragment shader to calculate the light.

/// The vertex shader will use the modelViewMatrix to transform the vertices from model space to view space.
struct MT2VertexUniforms
{
    matrix_float4x4 modelViewMatrix;
    matrix_float3x3 modelViewInverseTransposeMatrix;
    matrix_float4x4 modelViewProjectionMatrix;
};

/// The fragment shader will use the viewLightPosition to calculate the light.
struct MT2FragmentUniforms
{
    simd_float4 viewLightPosition;
};


#endif /* MT2Uniforms_h */
