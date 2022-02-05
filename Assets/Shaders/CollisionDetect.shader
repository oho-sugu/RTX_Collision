Shader "Unlit/RayTracing/CollisionDetect"
{
    Properties
    {
        _Color("Main Color", Color) = (1, 1, 1, 1)
        _RefractiveIndex("Refractive Index", Range(1.0, 2.0)) = 1.55
		_MagicValue("Magic Value", Range(0.0, 1.0)) = 0
        _MainTex("Albedo (RGB)", 2D) = "white" {}
    }

    SubShader
    {
        Tags { "RenderType" = "Opaque" }
        LOD 100

        Pass
        {
            CGPROGRAM
            #pragma vertex vert
            #pragma fragment frag

            #include "UnityCG.cginc"

            float4 _Color;

            struct appdata
            {
                float4 vertex : POSITION;
            };

            struct v2f
            {
                float4 vertex : SV_POSITION;
            };

            v2f vert (appdata v)
            {
                v2f o;
                o.vertex = UnityObjectToClipPos(v.vertex);
                return o;
            }

            fixed4 frag (v2f i) : SV_Target
            {
                fixed4 col = _Color * 2;
                return col;
            }
            ENDCG
        }
    }

    SubShader
    {
        Pass
        {
            Name "Test"
            Tags{ "LightMode" = "RayTracing" }

            HLSLPROGRAM

            #include "UnityShaderVariables.cginc"
            #include "UnityRaytracingMeshUtils.cginc"
            #include "Light.hlsl"
            #include "RayPayload.hlsl"

            #pragma raytracing test

            float4 _Color;            
			
			float _MagicValue;

            RaytracingAccelerationStructure g_SceneAccelStruct;

            float _RefractiveIndex;

            Texture2D _MainTex;
            float4 _MainTex_ST;

            SamplerState sampler_linear_repeat;

            struct AttributeData
            {
                float2 barycentrics;
            };
         
            struct Vertex
            {
                float3 position;
                float3 normal;
				float2 uv;
            };

            Vertex FetchVertex(uint vertexIndex)
            {
                Vertex v;
                v.position = UnityRayTracingFetchVertexAttribute3(vertexIndex, kVertexAttributePosition);
                v.normal = UnityRayTracingFetchVertexAttribute3(vertexIndex, kVertexAttributeNormal);
				v.uv = UnityRayTracingFetchVertexAttribute2(vertexIndex, kVertexAttributeTexCoord0);
                return v;
            }

            Vertex InterpolateVertices(Vertex v0, Vertex v1, Vertex v2, float3 barycentrics)
            {
                Vertex v;
                #define INTERPOLATE_ATTRIBUTE(attr) v.attr = v0.attr * barycentrics.x + v1.attr * barycentrics.y + v2.attr * barycentrics.z
                INTERPOLATE_ATTRIBUTE(position);
                INTERPOLATE_ATTRIBUTE(normal);
				INTERPOLATE_ATTRIBUTE(uv);
                return v;
            }

            void fresnel(in float3 I, in float3 N, in float ior, out float kr)
            {
                float cosi = clamp(-1, 1, dot(I, N));
                float etai = 1, etat = ior;
                if (cosi > 0) 
                { 
                    float temp = etai;
                    etai = etat;
                    etat = temp;
                }
                // Compute sini using Snell's law
                float sint = etai / etat * sqrt(max(0.f, 1 - cosi * cosi));
                // Total internal reflection
                if (sint >= 1) 
                {
                    kr = 1;
                }
                else 
                {
                    float cost = sqrt(max(0, 1 - sint * sint));
                    cosi = abs(cosi);
                    float Rs = ((etat * cosi) - (etai * cost)) / ((etat * cosi) + (etai * cost));
                    float Rp = ((etai * cosi) - (etat * cost)) / ((etai * cosi) + (etat * cost));
                    kr = (Rs * Rs + Rp * Rp) / 2;
                }
                // As a consequence of the conservation of energy, transmittance is given by:
                // kt = 1 - kr;
            }
          
            [shader("closesthit")]
            void ClosestHitMain(inout RayPayload payload : SV_RayPayload, AttributeData attribs : SV_IntersectionAttributes)
            {
                uint3 triangleIndices = UnityRayTracingFetchTriangleIndices(PrimitiveIndex());

                Vertex v0, v1, v2;
                v0 = FetchVertex(triangleIndices.x);
                v1 = FetchVertex(triangleIndices.y);
                v2 = FetchVertex(triangleIndices.z);

                float3 barycentricCoords = float3(1.0 - attribs.barycentrics.x - attribs.barycentrics.y, attribs.barycentrics.x, attribs.barycentrics.y);
                Vertex v = InterpolateVertices(v0, v1, v2, barycentricCoords);
                
                float3 worldPosition = mul(ObjectToWorld(), float4(v.position, 1));		

				if (payload.bounceIndex < 5)
				{
                    bool isFrontFace = (HitKind() == HIT_KIND_TRIANGLE_FRONT_FACE);

                    RayDesc ray;
                    ray.Origin = worldPosition + 0.001f * WorldRayDirection();
                    ray.Direction = WorldRayDirection();
                    ray.TMin = 0;
                    ray.TMax = 1e20f;

                    RayPayload refrRayPayload;
                    refrRayPayload.color = payload.color;
                    refrRayPayload.worldPos = float4(worldPosition, 1);
                    refrRayPayload.bounceIndex = payload.bounceIndex + 1;
    
                    TraceRay(g_SceneAccelStruct, 0, 0xFF, 0, 1, 0, ray, refrRayPayload);

                    if (isFrontFace) {
                        payload.color = float4(
                            refrRayPayload.color.r,
                            1,
                            refrRayPayload.color.b - refrRayPayload.color.r*2,
                            refrRayPayload.color.a
                            );
                    }
                    else {
                        payload.color = float4(
                            refrRayPayload.color.r,
                            refrRayPayload.color.g*2,
                            refrRayPayload.color.b + refrRayPayload.color.g * 2,
                            refrRayPayload.color.a
                            );
                    }

                    if (payload.bounceIndex == 0)
                    {
                        payload.worldPos = float4(worldPosition, 1);
                    }
				}
                else
                {
                    payload.color = float4(0,0,0, 1);
                    payload.worldPos = float4(worldPosition, 1);
                }                
            }

            ENDHLSL
        }
    }
}
