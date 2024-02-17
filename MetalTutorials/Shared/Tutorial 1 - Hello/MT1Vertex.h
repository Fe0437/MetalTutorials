//
//  MTVertex.h
//  MetalTutorials
//
//  Created by federico forti on 07/03/2021.
//

#ifndef MTVertex_h
#define MTVertex_h

#include <simd/simd.h>

//  This structure defines the layout of vertices sent to the vertex
//  shader. This header is shared between the .metal shader and C code, to guarantee that
//  the layout of the vertex array in the C code matches the layout that the .metal
//  vertex shader expects.
typedef struct
{
    vector_float2 position;
    vector_float4 color;
} MT1Vertex;

#endif /* MTVertex_h */
