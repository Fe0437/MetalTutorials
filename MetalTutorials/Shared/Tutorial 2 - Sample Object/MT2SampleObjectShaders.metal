//
//  MT2SampleObjectShaders.metal
//  MetalTutorials
//
//  Created by federico forti on 14/03/2021.
//

#include <metal_stdlib>
#include "MT2Uniforms.h"

namespace MT2 {
    using namespace metal;
    
    /// vertex data taken by the vertex shader
    /// TODO: attribute meaning
    struct VertexIn {
        float3 position  [[attribute(0)]];
        float3 normal    [[attribute(1)]];
        float2 texCoords [[attribute(2)]];
    };
    
    /// vertex shader output data
    /// TODO: position attribute meaning
    struct VertexOut {
        float4 clipSpacePosition [[position]];
        float3 viewNormal;
        float4 viewPosition;
        float2 texCoords;
    };
    
    /// vertex shader transforming the vertex data passed
    /// - Parameter vertexIn: [[stage_in]] to signify that it is built for us by loading data according to the vertex descriptor
    /// - parameter uniforms: second parameter is a reference to an instance of the Uniforms struct, which will hold the matrices we use to transform our vertices
    vertex VertexOut vertex_main(VertexIn vertexIn [[stage_in]],
                                     constant MT2VertexUniforms &uniforms [[buffer(1)]])
    {
        VertexOut vertexOut;
        vertexOut.clipSpacePosition = uniforms.modelViewProjectionMatrix * float4(vertexIn.position, 1);
        vertexOut.viewNormal = uniforms.modelViewInverseTransposeMatrix * vertexIn.normal;
        vertexOut.viewPosition = uniforms.modelViewMatrix * float4(vertexIn.position, 1);
        return vertexOut;
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
    
    /// fragment shader that computes the lighting using the GGX BRDF 
    /// Parameter fragmentIn: takes the output from the vertex shader after the rasterization
    /// Parameter uniforms: contains the light position used to render the object
    fragment float4 fragment_main(VertexOut fragmentIn [[stage_in]],
                                      constant MT2FragmentUniforms &uniforms [[buffer(1)]]) {
        
        const float3 V = normalize(-float3(fragmentIn.viewPosition));
        const float3 N = normalize(fragmentIn.viewNormal);
        const float3 L = normalize(float3(uniforms.viewLightPosition));
        
        //we could parametrize that, but not important
        //for this tutorial
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
        const float3 f_diffuse = rho / M_PI_F;
        const float3 L_o = M_PI_F * NdotL * Lcolor * (f_reflection + f_diffuse);
        return float4(L_o,1);
    }
    
}
