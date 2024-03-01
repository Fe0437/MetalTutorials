//
//  MT6DeferredRendering.metal
//  MetalTutorials
//
//  Created by federico forti on 14/03/2021.
//

#include <metal_stdlib>
#include "MT6Input.h"
#include "MT6RenderTargets.h"

namespace MT6 {
    
    using namespace metal;
    
    
    struct MaterialArgument {
        texture2d<float> baseColorTexture [[id(MT6BaseColorTexture)]];
        texture2d<float> specularTexture [[id(MT6SpecularTexture)]];
    };
    
    struct ShadowsArgBuffer {
        depth2d<float> shadowTexture [[ id(0) ]] ; // < depth2d not texture
    };
    
    namespace Indirect {
        
        struct CommandArgBuffer {
            command_buffer indirectCommandBuffer [[id(0)]];
        };
        
        struct Mesh {
          constant float *vertexBuffer [[id(MT6VertexBuffer)]];
          constant float *texCoordsBuffer [[id(MT6TextureCoordinatesBuffer)]];
          constant uint  *indexBuffer [[id(MT6IndecesBuffer)]];
          constant MaterialArgument *materialArgBuffer [[id(MT6MaterialArgBuffer)]];
        };
        
        
        /// this is the kernel that will draw the meshes in parallel from the gpu
        /// Parameters:
        ///  - threadId: id of the current thread, used to get the mesh to work in this thread
        ///  - pCommandBuffer: pointer to the indirectCommandBuffer which will encode the draw commands
        ///  - pMeshes: pointer to the array of meshes that we are going to draw
        ///  - pVertexUniformsArray: pointer to the uniforms used for the vertex shader, every mesh has a different uniforms
        ///  - fragmentUniforms: fragment shader uniforms used for all the meshes
        ///  - pDrawArgumentsBuffer: pointer to the metal argument buffer which is used to store the draw arguments necessary to draw each mesh
        kernel void drawKernel(
          uint threadId [[thread_position_in_grid]],
          device CommandArgBuffer *pCommandBuffer [[buffer(MT6IndirectCommandBuffer)]],
          constant Mesh *pMeshes [[buffer(MT6MeshesBuffer)]],
          constant MT6VertexUniforms *pVertexUniformsArray [[buffer(MT6VertexUniformsBuffer)]],
          constant MT6FragmentUniforms &fragmentUniforms [[buffer(MT6FragmentUniformsBuffer)]],
          constant ShadowsArgBuffer *pShadowArgBuffer  [[ buffer(MT6ShadowsArgumentsBuffer) ]],
          constant MTLDrawIndexedPrimitivesIndirectArguments
            *drawArgumentsBuffer [[buffer(MT6DrawArgumentsBuffer)]])
        {
          //take the mesh and the arguments to draw
          const Mesh mesh = pMeshes[threadId];
          MTLDrawIndexedPrimitivesIndirectArguments drawArguments
            = drawArgumentsBuffer[threadId];
            
          // start a new render command using the indirect command buffer
          render_command cmd(pCommandBuffer->indirectCommandBuffer,            threadId);
          //setup the vertex buffer necessary to draw
          cmd.set_vertex_buffer  (mesh.vertexBuffer,                    MT6VertexBuffer);
          cmd.set_vertex_buffer  (mesh.texCoordsBuffer,     MT6TextureCoordinatesBuffer);
          // setup the uniforms for the vertex and fragment shaders
          cmd.set_vertex_buffer(pVertexUniformsArray,           MT6VertexUniformsBuffer);
        
          cmd.set_fragment_buffer(&fragmentUniforms,          MT6FragmentUniformsBuffer);
        
          // set material argument buffer
          cmd.set_fragment_buffer(&mesh.materialArgBuffer[threadId],      MT6MaterialArgBuffer);

          // set shadow arg buffer
          cmd.set_fragment_buffer(pShadowArgBuffer,           MT6ShadowsArgumentsBuffer);
            
          //draw the mesh
          cmd.draw_indexed_primitives(
            primitive_type::triangle,
            drawArguments.indexCount,
            mesh.indexBuffer + drawArguments.indexStart,
            drawArguments.instanceCount,
            drawArguments.baseVertex,
            drawArguments.baseInstance);
        }
    }
    
    struct VertexIn {
        float3 position  [[attribute(MT6Position)]];
        float3 normal    [[attribute(MT6Normal)]];
        float2 texCoords [[attribute(MT6TexCoords)]];
    };
    
    struct VertexOut {
        float4 clipSpacePosition [[position]];
        float3 viewNormal;
        float4 viewPosition;
        float2 texCoords;
        float4 lightViewPosition;
        uint meshIndex [[flat]];
    };
    
    /// [[stage_in]] to signify that it is built for us by loading data according to the vertex descriptor
    /// second parameter is a reference to an instance of the Uniforms struct, which will hold the matrices we use to transform our vertices
    vertex VertexOut vertex_main(
                                 VertexIn vertexIn [[stage_in]],
                                 constant MT6VertexUniforms *pUniforms [[buffer(MT6VertexUniformsBuffer)]],
                                 uint meshIndex [[base_instance]])
    {
        //the array that we get contains the uniforms for all the meshes in the scene
        MT6VertexUniforms uniforms = pUniforms[meshIndex];
        return VertexOut {
            .clipSpacePosition = uniforms.modelViewProjectionMatrix * float4(vertexIn.position, 1),
            .viewNormal = uniforms.modelViewInverseTransposeMatrix * vertexIn.normal,
            .viewPosition = uniforms.modelViewMatrix * float4(vertexIn.position, 1),
            .lightViewPosition = uniforms.shadowModelViewProjectionMatrix * float4(vertexIn.position, 1),
            .texCoords = vertexIn.texCoords,
            .meshIndex = meshIndex
        };
    }
    
    
    struct GBuffer {
        float4 basecolor_specular [[color(MT6RenderTargetBaseColorAndSpecular)]];
        float4 normal_visibility [[color(MT6RenderTargetNormalAndVisibility)]];
        float4 position [[color(MT6RenderTargetPosition)]];
    };
    
    
    fragment GBuffer gbuffer_fragment(
                                     VertexOut fragmentIn [[stage_in]],
                                     constant ShadowsArgBuffer &shadowArgBuffer [[buffer(MT6ShadowsArgumentsBuffer) ]],
                                     constant MT6FragmentUniforms &uniforms [[buffer(MT6FragmentUniformsBuffer)]],
                                     constant MaterialArgument &material [[buffer(MT6MaterialArgBuffer)]]
                                     )
    {
        
        float3 lightCoords = fragmentIn.lightViewPosition.xyz / fragmentIn.lightViewPosition.w;
        float2 lightScreenCoords = lightCoords.xy;
        lightScreenCoords = lightScreenCoords * 0.5 + 0.5;
        lightScreenCoords.y = 1 - lightScreenCoords.y; //invert y
        
        GBuffer out;
        float visibility = 1;
        
        constexpr sampler s(
          coord::normalized, filter::linear,
          address::clamp_to_edge,
          compare_func:: less);
        
        float depthValue = shadowArgBuffer.shadowTexture.sample(s, lightScreenCoords);
        if (lightCoords.z > depthValue + 0.00001f) {
            visibility *= 0.3;
        }

        constexpr sampler shadingTextureSampler;
        float2 texCoords = float2(fragmentIn.texCoords.x,1-fragmentIn.texCoords.y);
        float4 baseColor = material.baseColorTexture.sample(shadingTextureSampler, texCoords);
        float4 specularColor = material.specularTexture.sample(shadingTextureSampler, texCoords);
        
        out.basecolor_specular = float4(baseColor.xyz, specularColor.r);
        out.normal_visibility= float4(normalize(fragmentIn.viewNormal), visibility);
        out.position = normalize(fragmentIn.viewPosition);
        
        if (lightScreenCoords.x < 0.0 || lightScreenCoords.x > 1.0 || lightScreenCoords.y < 0.0 || lightScreenCoords.y > 1.0) {
            //alert shadow map is not covering this area
            out.basecolor_specular = float4(1, 0, 0, 0);
        }
        return out;
    }
    
    // display
    
    struct QuadInOut
    {
        float4 position [[position]];
    };
    
    vertex QuadInOut
    display_vertex(constant MT6ScreenVertex * vertices  [[ buffer(0) ]],
                       uint                        vid       [[ vertex_id ]])
    {
        QuadInOut out;
        
        out.position = float4(vertices[vid].position, 0, 1);
        
        return out;
    }
    
    float rcp(float x)
    {
        return 1/x;
    }
    
    // GGX / Trowbridge-Reitz
    // [Walter et al. 2007, "Microfacet models for refraction through rough surfaces"]
    float D_GGX( float a2, float NoH )
    {
        if(NoH<=0)
        {
            return 0;
        }
        float d = ( NoH * a2 - NoH ) * NoH + 1;    // 2 mad
        return a2 / ( M_PI_F*d*d );                // 4 mul, 1 rcp
    }
    
    // ggx filament
    float D_GGX_f(float roughness, float NoH) {
        float a = NoH * roughness;
        float k = roughness / (1.0 - NoH * NoH + a * a);
        return k * k * (1.0 / M_PI_F);
    }
    
    // Appoximation of joint Smith term for GGX
    // [Heitz 2014, "Understanding the Masking-Shadowing Function in Microfacet-Based BRDFs"]
    float Vis_SmithJointApprox( float a2, float NoV, float NoL )
    {
        NoV = abs(NoV);
        NoL = abs(NoL);
        float a = sqrt(a2);
        float x = 2 * NoV * NoL;
        float y = NoV + NoL;
        return 0.5 * rcp( mix(x,y,a) );
    }
    
    // Smith term for GGX
    // [Smith 1967, "Geometrical shadowing of a random rough surface"]
    float Vis_Smith( float a2, float NoV, float NoL )
    {
        float Vis_SmithV = NoV + sqrt( NoV * (NoV - NoV * a2) + a2 );
        float Vis_SmithL = NoL + sqrt( NoL * (NoL - NoL * a2) + a2 );
        return rcp( Vis_SmithV * Vis_SmithL );
    }
    
    //filmaent
    float V_SmithGGXCorrelated(float NoV, float NoL, float roughness) {
        float a2 = roughness * roughness;
        float GGXV = NoL * sqrt(NoV * NoV * (1.0 - a2) + a2);
        float GGXL = NoV * sqrt(NoL * NoL * (1.0 - a2) + a2);
        return 0.5 / (GGXV + GGXL);
    }
    
    // [Schlick 1994, "An Inexpensive BRDF Model for Physically-Based Rendering"]
    float3 F_Schlick( float3 SpecularColor, float VoH )
    {
        float Fc = pow(( 1 - VoH ),5);                 // 1 sub, 3 mul
        return Fc + (1 - Fc) * SpecularColor;
    }
    
   
    static float4 calculate_out_radiance(float4 base_color_and_spec, float3 L, float3 N, float3 V) {
        
        const float3 specColor = float3(base_color_and_spec.a);
        const float3 LightIntensity = float3(1.0);
        const float  roughness = 1 - clamp(base_color_and_spec.a, 0.2, 0.8);
        const float3 rho(1.0);
        const float  sqrRoughness = roughness*roughness;
        
        //base components
        float3 H = normalize(V+L);
        float NdotL = saturate(dot(N,L));
        float NdotV = saturate(dot(N,V));
        float NdotH = saturate(dot(N,H));
        float VdotH = saturate(dot(V,H));
        
        // D GGX
        float a2 = sqrRoughness*sqrRoughness;
        float Vis = Vis_SmithJointApprox(a2, NdotV, NdotL);
        float D =  D_GGX(a2, NdotH);
        
        // Fresnel term - Schlick's approximation
        float3 F = F_Schlick(specColor, VdotH);
        const float3 f_spec = (D * Vis) * F;
        
        //simplify pi here
        const float3 f_diffuse = base_color_and_spec.xyz * rho / M_PI_F;
        const float3 L_o = M_PI_F * NdotL * LightIntensity * (f_spec + f_diffuse);
        return float4(L_o,1);
    }
    
    fragment float4
    deferred_lighting_fragment(
                                   QuadInOut             in                      [[ stage_in ]],
                                   GBuffer            gBuffer                               ,
                                   constant MT6FragmentUniforms &uniforms [[buffer(MT6FragmentUniformsBuffer)]])
    {
        float4 basecolor_specular_at_pix = gBuffer.basecolor_specular;
        float4 normal_and_vis_at_pix = gBuffer.normal_visibility;
        float4 position_at_pix = gBuffer.position;
        
        const float3 V = normalize(-float3(position_at_pix));
        const float3 N = normalize(normal_and_vis_at_pix.xyz - position_at_pix.xyz);
        const float3 L = normalize(float3(uniforms.viewLightPosition - position_at_pix));
        
        const float visibility = normal_and_vis_at_pix.a;
        // albedo_specular_at_pix.a contains the shadow
        return calculate_out_radiance(basecolor_specular_at_pix, L, N, V) * visibility;
    }
 
    //shadows

    struct ShadowVertexIn {
        float3 position  [[attribute(MT6Position)]];
    };

    vertex float4
      vertex_depth(ShadowVertexIn in  [[ stage_in ]],
                   constant MT6VertexUniforms *pUniforms [[buffer(MT6VertexUniformsBuffer)]],
                   uint meshIndex [[base_instance]])
    {
      return pUniforms[meshIndex].shadowModelViewProjectionMatrix * float4(in.position,1);
    }

    
}
