//
//  MT3GBuffer.h
//  MetalTutorials
//
//  Created by federico forti on 08/02/24.
//

#ifndef MT3GBuffer_h
#define MT3GBuffer_h

/// Render Target Indices used to bind the textures between metal and the render pass descriptor
typedef enum MT3RenderTargetIndices
{
    MT3RenderTargetAlbedo    = 1,
    MT3RenderTargetNormal    = 2,
    MT3RenderTargetDepth     = 3
} MT3RenderTargetIndices;

#endif /* MT3GBuffer_h */
