//
//  MT5DeferredRendering.metal
//  MetalTutorials
//
//  Created by federico forti on 14/03/2021.
//

#include <metal_stdlib>
#include "MT5Uniforms.h"
#include "MT5RenderTargets.h"

namespace MT5 {
    
    using namespace metal;
    
    struct VertexIn {
        float3 position  [[attribute(0)]];
        float3 normal    [[attribute(1)]];
        float2 texCoords [[attribute(2)]];
    };
    
    struct VertexOut {
        float4 clipSpacePosition [[position]];
        float3 viewNormal;
        float4 viewPosition;
        float2 texCoords;
        float4 lightViewPosition;
    };
    
    /// [[stage_in]] to signify that it is built for us by loading data according to the vertex descriptor
    /// second parameter is a reference to an instance of the Uniforms struct, which will hold the matrices we use to transform our vertices
    vertex VertexOut vertex_main(VertexIn vertexIn [[stage_in]],
                                        constant MT5VertexUniforms &uniforms [[buffer(1)]])
    {
        VertexOut vertexOut;
        vertexOut.clipSpacePosition = uniforms.modelViewProjectionMatrix * float4(vertexIn.position, 1);
        vertexOut.viewNormal = uniforms.modelViewInverseTransposeMatrix * vertexIn.normal;
        vertexOut.viewPosition = uniforms.modelViewMatrix * float4(vertexIn.position, 1);
        vertexOut.lightViewPosition = uniforms.shadowModelViewProjectionMatrix * float4(vertexIn.position, 1);
        return vertexOut;
    }
    
    
    struct GBuffer {
        float4 albedo [[color(MT5RenderTargetAlbedo)]];
        float4 normal [[color(MT5RenderTargetNormal)]];
        float4 position [[color(MT5RenderTargetDepth)]];
    };
    
    fragment GBuffer gbuffer_fragment(
                                             VertexOut fragmentIn [[stage_in]],
                                             depth2d<float> shadowTexture [[ texture(MT5RenderTargetShadow) ]], // < depth2d not texture
                                             constant MT5FragmentUniforms &uniforms [[buffer(1)]]
                                             )
    {
        
        float3 lightCoords = fragmentIn.lightViewPosition.xyz / fragmentIn.lightViewPosition.w;
        float2 lightScreenCoords = lightCoords.xy;
        lightScreenCoords = lightScreenCoords * 0.5 + 0.5;
        lightScreenCoords.y = 1 - lightScreenCoords.y; //invert y
        
        GBuffer out;

        
        
        if (lightScreenCoords.x < 0.0 || lightScreenCoords.x > 1.0 || lightScreenCoords.y < 0.0 || lightScreenCoords.y > 1.0) {
            out.albedo = float4(1, 0, 0, 1);
        }else{
            
            constexpr sampler s(
              coord::normalized, filter::linear,
              address::clamp_to_edge,
              compare_func:: less);
            
            float4 albedo = float4(1,1,1,1);
            
            float depthValue = shadowTexture.sample(s, lightScreenCoords);
            if (lightCoords.z > depthValue + 0.00001f) {
                albedo *= 0.4;
            }
            out.albedo = albedo;
        }
        out.normal = float4(normalize(fragmentIn.viewNormal),1);
        out.position = normalize(fragmentIn.viewPosition);
        return out;
    }
    
    // display
    
    struct QuadInOut
    {
        float4 position [[position]];
    };
    
    vertex QuadInOut
    display_vertex(constant MT5ScreenVertex * vertices  [[ buffer(MT5BufferIndexMeshPositions) ]],
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
    
    // [Schlick 1994, "An Inexpensive BRDF Model for Physically-Based Rendering"]
    float3 F_Schlick( float3 SpecularColor, float VoH )
    {
        float Fc = pow(( 1 - VoH ),5);                 // 1 sub, 3 mul
        return Fc + (1 - Fc) * SpecularColor;
    }
    
    static float4 calculate_out_radiance(float4 albedo, float3 L, float3 N, float3 V) {
        
        const float3 specColor = float3(1);
        const float3 Lcolor = float3(10);
        const float  roughness = 0.2;
        const float3 rho(0.01);
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
        const float3 f_reflection = (D * Vis) * F;
        
        //simplify pi here
        const float3 f_diffuse = albedo.xyz * rho / M_PI_F;
        const float3 L_o = M_PI_F * NdotL * dot(f_reflection + f_diffuse, Lcolor);
        return float4(L_o,1);
    }
    
    fragment float4
    deferred_lighting_fragment(
                                   QuadInOut             in                      [[ stage_in ]],
                                   GBuffer            gBuffer                               ,
                                   constant MT5FragmentUniforms &uniforms [[buffer(1)]])
    {
        float4 albedo_specular_at_pix = gBuffer.albedo;
        float4 normal_at_pix = gBuffer.normal;
        float4 position_at_pix = gBuffer.position;
        
        const float3 V = normalize(-float3(position_at_pix));
        const float3 N = normalize(normal_at_pix.xyz - position_at_pix.xyz);
        const float3 L = normalize(float3(uniforms.viewLightPosition - position_at_pix));
        
        // albedo_specular_at_pix.a contains the shadow
        return calculate_out_radiance(albedo_specular_at_pix, L, N, V) * albedo_specular_at_pix.a;
    }
 
    //shadows

    struct ShadowVertexIn {
        float3 position  [[attribute(0)]];
    };

    vertex float4
      vertex_depth(ShadowVertexIn in  [[ stage_in ]],
                   constant MT5VertexUniforms &uniforms [[buffer(1)]])
    {
      return uniforms.shadowModelViewProjectionMatrix * float4(in.position,1);
    }

    
}
