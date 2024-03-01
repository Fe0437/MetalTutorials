//
//  MT6Uniforms.h
//  MetalTutorials
//
//

#ifndef MT6Uniforms_h
#define MT6Uniforms_h

#include <simd/simd.h>

struct MT6VertexUniforms
{
    matrix_float4x4 modelViewMatrix;
    matrix_float3x3 modelViewInverseTransposeMatrix;
    matrix_float4x4 modelViewProjectionMatrix;
    
    //tutorial 4 - shadows
    matrix_float4x4 shadowModelViewProjectionMatrix;
};

struct MT6FragmentUniforms
{
    simd_float4 viewLightPosition;
};

// Buffer index values shared between shader and C code to ensure Metal shader buffer inputs match
//   Metal API buffer set calls
typedef enum MT6BufferIndices
{
    MT6BufferIndexMeshPositions     = 10,
    MT6VertexUniformsBuffer         = 11,
    MT6FragmentUniformsBuffer       = 12,
    
    // gpu drawing
    MT6IndirectCommandBuffer        = 13,
    MT6MeshesBuffer                 = 14,
    MT6DrawArgumentsBuffer          = 15,
    MT6ShadowsArgumentsBuffer       = 16
} MT6BufferIndices;

typedef enum MT6VertexBufferIndeces {
    MT6VertexBuffer                 = 0,
    MT6TextureCoordinatesBuffer     = 1,
    MT6IndecesBuffer                = 2,
    MT6MaterialArgBuffer            = 3
} MT6VertexBufferIndeces;

struct MT6ScreenVertex {
    vector_float2 position;
};

typedef enum {
  MT6BaseColor = 0,
  MT6BaseColorTexture = 1,
  MT6SpecularColor = 2,
  MT6SpecularTexture = 3,
} MaterialParameters;

typedef enum {
  MT6Position = 0,
  MT6Normal = 1,
  MT6TexCoords = 2,
} Attributes;

#endif /* MT6Uniforms_h */
