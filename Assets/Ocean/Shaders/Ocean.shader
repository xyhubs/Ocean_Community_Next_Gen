Shader "Mobile/Ocean" {
	Properties {
	    _SurfaceColor ("SurfaceColor", Color) = (1,1,1,1)
	    _WaterColor ("WaterColor", Color) = (1,1,1,1)

		_Specularity ("Specularity", Range(0.01,1)) = 0.3

		_SunColor ("SunColor", Color) = (1,1,0.901,1)

		_Refraction ("Refraction (RGB)", 2D) = "white" {}
		_Reflection ("Reflection (RGB)", 2D) = "white" {}
		_Bump ("Bump (RGB)", 2D) = "bump" {}
		_Foam("Foam (RGB)", 2D) = "white" {}
		_FoamBump ("Foam B(RGB)", 2D) = "bump" {}
		_FoamFactor("Foam Factor", Range(0,3)) = 1.8
		_Size ("UVSize", Float) = 0.015625//this is the best value (1/64) to have the same uv scales of normal and foam maps on all ocean sizes
		_SunDir ("SunDir", Vector) = (0.3, -0.6, -1, 0)
		_WaveOffset ("Wave speed", Float) = 0

		_FakeUnderwaterColor ("Water Color LOD1", Color) = (0.196, 0.262, 0.196, 1)
		_WaterLod1Alpha ("Water Transparency", Range(0,1)) = 0.95
	}
	
	SubShader {
	    Tags { "RenderType" = "Opaque" "Queue"="Geometry"}
		LOD 4
    	Pass {
			CGPROGRAM
			#pragma vertex vert
			#pragma fragment frag
			#pragma multi_compile_fog

			#include "UnityCG.cginc"

			struct v2f {
    			float4 pos : SV_POSITION;
    			half4  projTexCoord : TEXCOORD0;
    			half3  bumpTexCoord : TEXCOORD1;
    			float3  viewDir : TEXCOORD2;
    			float3  objSpaceNormal : TEXCOORD3;
    			float3  lightDir : TEXCOORD4;
				UNITY_FOG_COORDS(7)
				half4 buv : TEXCOORD5;
				half3 normViewDir : TEXCOORD6;
			};

			float _Size;
			half4 _SunDir;
			half _WaveOffset;

			v2f vert (appdata_tan v) {
    			v2f o;
				UNITY_INITIALIZE_OUTPUT(v2f, o);

    			o.bumpTexCoord.xy = v.vertex.xz*_Size;///64;//float2(_Size.x, _Size.z);

    			o.pos = mul (UNITY_MATRIX_MVP, v.vertex);

				o.bumpTexCoord.z = v.tangent.w;
 
  				half4 projSource = float4(v.vertex.x, 0.0, v.vertex.z, 1.0);
    			half4 tmpProj = mul( UNITY_MATRIX_MVP, projSource);
    			//o.projTexCoord = tmpProj;

				o.projTexCoord.xy = 0.5 * tmpProj.xy * float2(1, _ProjectionParams.x) / tmpProj.w + float2(0.5, 0.5);

    			float3 objSpaceViewDir = ObjSpaceViewDir(v.vertex);
    			float3 binormal = cross( normalize(v.normal), normalize(v.tangent.xyz) );
				float3x3 rotation = float3x3( v.tangent.xyz, binormal, v.normal );
    
    			o.objSpaceNormal = v.normal;
    			o.viewDir = mul(rotation, objSpaceViewDir);
    			o.lightDir = mul(rotation, float3(_SunDir.xyz));

				o.buv = half4(o.bumpTexCoord.x + _WaveOffset * 0.05, o.bumpTexCoord.y + _WaveOffset * 0.03, o.bumpTexCoord.x + _WaveOffset * 0.04, o.bumpTexCoord.y);// - _WaveOffset * 0.02

				o.normViewDir = normalize(o.viewDir);
                
				UNITY_TRANSFER_FOG(o, o.pos);

    			return o;
			}

			sampler2D _Refraction;
			sampler2D _Reflection;
			sampler2D _Bump;
			sampler2D _Foam;
			sampler2D _FoamBump;
			half _FoamFactor;
			half4 _SurfaceColor;
			half4 _WaterColor;
			half _Specularity;
			half4 _SunColor;

			half4 frag (v2f i) : COLOR {
				//half3 normViewDir = normalize(i.viewDir);
				//half4 buv = half4(i.bumpTexCoord.x + _WaveOffset * 0.05, i.bumpTexCoord.y + _WaveOffset * 0.03, i.bumpTexCoord.x + _WaveOffset * 0.04, i.bumpTexCoord.y - _WaveOffset * 0.02);
				//float foamStrength = i.bumpTexCoord.z * _FoamFactor;

				half foam = clamp( tex2D(_Foam, i.bumpTexCoord.xy)*tex2D(_Foam, i.buv.zy) -0.15, 0.0, 1.0) * i.bumpTexCoord.z * _FoamFactor;
								
				half3 tangentNormal0 = (tex2D(_Bump, i.buv.xy) * 2 )+( tex2D(_Bump, i.buv.zw) * 2 ) - 2 + (  tex2D(_FoamBump, i.bumpTexCoord.xy)*4   - 1)*foam; 

				half3 tangentNormal = normalize(tangentNormal0 );


				//float2 projTexCoord = 0.5 * i.projTexCoord.xy * float2(1, _ProjectionParams.x) / i.projTexCoord.w + float2(0.5, 0.5);

				half4 result = half4(0, 0, 0, 1);

				float2 bumpSampleOffset = (i.objSpaceNormal.xz  + tangentNormal.xy) * 0.05  + i.projTexCoord.xy;// + projTexCoord.xy
	
				half3 reflection = tex2D( _Reflection,  bumpSampleOffset) * _SurfaceColor ;
				half3 refraction = tex2D( _Refraction,  bumpSampleOffset ) * _WaterColor ;

				float fresnelLookup = dot(tangentNormal, i.normViewDir);

				//float bias = 0.06;
				//float power = 4.0;
				float fresnelTerm = 0.06 + (1.0 - 0.06)*pow(1.0 - fresnelLookup, 4);

				float3 halfVec = normalize(i.normViewDir - normalize(i.lightDir));

				float specular = pow(max(dot(halfVec,  tangentNormal) , 0.0), 250.0 * _Specularity ) *(1.2-foam);

				//simple
				//result.rgb = lerp(refraction, reflection, fresnelTerm)+ clamp(foam, 0.0, 1.0) + specular;

				//method1
				//result.rgb = lerp(refraction, reflection, fresnelTerm) + clamp(foam, 0.0, 1.0)*_SunColor.b + specular;
				//result.rgb *= _SunColor.rgb;

				//method2
				result.rgb = lerp(refraction, reflection, fresnelTerm)*_SunColor.rgb + clamp(foam, 0.0, 1.0)*_SunColor.b + specular*_SunColor.rgb;

				UNITY_APPLY_FOG(i.fogCoord, result); 

    			return result;
			}

			ENDCG
		}
    }
		

 
 	
	    SubShader {
        Tags { "RenderType" = "Opaque" "Queue"="Geometry"}
        LOD 3
    	Pass {
			CGPROGRAM
			#pragma vertex vert
			#pragma fragment frag
			#pragma multi_compile_fog
			#include "UnityCG.cginc"

			struct v2f {
    			float4 pos : SV_POSITION;
    			half3  bumpTexCoord : TEXCOORD1;
    			float3  viewDir : TEXCOORD2;
    			float3  lightDir : TEXCOORD4;
				UNITY_FOG_COORDS(7)
				half4 buv : TEXCOORD5;
				half3 normViewDir : TEXCOORD6;
				float3 halfVec : TEXCOORD0;
			};

			float _Size;
			half4 _SunDir;
			half4 _FakeUnderwaterColor;
            half _WaveOffset;
            
			v2f vert (appdata_tan v) {
    			v2f o;
				UNITY_INITIALIZE_OUTPUT(v2f, o);

    			o.bumpTexCoord.xy = v.vertex.xz*_Size;///float2(_Size.x, _Size.z)*5;
    			o.pos = mul (UNITY_MATRIX_MVP, v.vertex);
    			o.bumpTexCoord.z = v.tangent.w;

    			float3 objSpaceViewDir = ObjSpaceViewDir(v.vertex);
    			float3 binormal = cross( normalize(v.normal), normalize(v.tangent.xyz) );
				float3x3 rotation = float3x3( v.tangent.xyz, binormal, v.normal );
    
    			o.viewDir = mul(rotation, objSpaceViewDir);
    			o.lightDir = mul(rotation, float3(_SunDir.xyz));

				o.buv = half4(o.bumpTexCoord.x + _WaveOffset * 0.05, o.bumpTexCoord.y + _WaveOffset * 0.03, o.bumpTexCoord.x + _WaveOffset * 0.04, o.bumpTexCoord.y);

				o.normViewDir = normalize(o.viewDir);

				o.halfVec = normalize(o.normViewDir - normalize(o.lightDir));

				UNITY_TRANSFER_FOG(o, o.pos);

    			return o;
			}

			sampler2D _Bump;
			sampler2D _Foam;
			half _FoamFactor;
			half4 _WaterColor;//Lod1;
			half4 _SurfaceColor;
			half _Specularity;
            half4 _SunColor;

			half4 frag (v2f i) : COLOR {
				//half3 normViewDir = normalize(i.viewDir);
			  // half4 buv = half4(i.bumpTexCoord.x + _WaveOffset * 0.05, i.bumpTexCoord.y + _WaveOffset * 0.03, i.bumpTexCoord.x + _WaveOffset * 0.04, i.bumpTexCoord.y - _WaveOffset * 0.02);
                
				half3 tangentNormal0 = (tex2D(_Bump, i.buv.xy) * 2.0) + (tex2D(_Bump, i.buv.zw) * 2.0) - 2;

				half3 tangentNormal = normalize(tangentNormal0);

				half4 result = half4(0, 0, 0, 1);
                
				float fresnelLookup = dot(tangentNormal, i.normViewDir);
				//float bias = 0.06;
				//float power = 4.0;
				float fresnelTerm = 0.06 + (1.0-0.06)*pow(1.0 - fresnelLookup, 4.0);

				half4 foam = clamp(tex2D(_Foam, i.bumpTexCoord.xy * 1.0)  - 0.5, 0.0, 1.0) * i.bumpTexCoord.z * _FoamFactor;

				//float3 halfVec = normalize(i.normViewDir - normalize(i.lightDir));

				float specular = pow(max(dot(i.halfVec,  tangentNormal) , 0.0), 250.0 * _Specularity ) *(1.2-foam);
                
				result.rgb = lerp(_WaterColor*_FakeUnderwaterColor, _SunColor.rgb*_SurfaceColor*0.85, fresnelTerm*0.65) + clamp(foam.r, 0.0, 1.0)*_SunColor.b + specular*_SunColor.rgb;

				UNITY_APPLY_FOG(i.fogCoord, result); 

    			return result;
			}
			ENDCG
			

		}
    }
 
     SubShader {
        Tags { "RenderType" = "Opaque" "Queue"="Geometry"}
        LOD 2
    	Pass {
			CGPROGRAM
			#pragma vertex vert
			#pragma fragment frag
			#pragma multi_compile_fog
			#include "UnityCG.cginc"

			struct v2f {
    			float4 pos : SV_POSITION;
    			half2  bumpTexCoord : TEXCOORD1;
    			float3  viewDir : TEXCOORD2;
    			float3  lightDir : TEXCOORD4;
				UNITY_FOG_COORDS(7)
				half4 buv : TEXCOORD5;
				half3 normViewDir : TEXCOORD6;
				float3 halfVec : TEXCOORD0;
			};

			float _Size;
			half4 _SunDir;
			half4 _FakeUnderwaterColor;
            half _WaveOffset;
            
			v2f vert (appdata_tan v) {
    			v2f o;
				UNITY_INITIALIZE_OUTPUT(v2f, o);

    			o.bumpTexCoord.xy = v.vertex.xz*_Size;///float2(_Size.x, _Size.z)*5;
    			o.pos = mul (UNITY_MATRIX_MVP, v.vertex);
    
    			float3 objSpaceViewDir = ObjSpaceViewDir(v.vertex);
    			float3 binormal = cross( normalize(v.normal), normalize(v.tangent.xyz) );
				float3x3 rotation = float3x3( v.tangent.xyz, binormal, v.normal );
    
    			o.viewDir = mul(rotation, objSpaceViewDir);
    			o.lightDir = mul(rotation, float3(_SunDir.xyz));

				o.buv = half4(o.bumpTexCoord.x + _WaveOffset * 0.05, o.bumpTexCoord.y + _WaveOffset * 0.03, o.bumpTexCoord.x + _WaveOffset * 0.04, o.bumpTexCoord.y);

				o.normViewDir = normalize(o.viewDir);

				o.halfVec = normalize(o.normViewDir - normalize(o.lightDir));

				UNITY_TRANSFER_FOG(o, o.pos);

    			return o;
			}

			sampler2D _Bump;
			sampler2D _Foam;
			half _FoamFactor;
			half4 _WaterColor;
			half4 _SurfaceColor;
			half _Specularity;
            half4 _SunColor;

			half4 frag (v2f i) : COLOR {
				//half3 normViewDir = normalize(i.viewDir);
				//half4 buv = half4(i.bumpTexCoord.x + _WaveOffset * 0.05, i.bumpTexCoord.y + _WaveOffset * 0.03, i.bumpTexCoord.x + _WaveOffset * 0.04, i.bumpTexCoord.y - _WaveOffset * 0.02);
                
				half3 tangentNormal0 = (tex2D(_Bump, i.buv.xy) * 2.0) + (tex2D(_Bump, i.buv.zw) * 2.0) - 2;

				half3 tangentNormal = normalize(tangentNormal0);

				half4 result = half4(0, 0, 0, 1);
                
				float fresnelLookup = dot(tangentNormal,i. normViewDir);
				//float bias = 0.06;
				//float power = 4.0;
				float fresnelTerm = 0.06 + (1.0-0.06)*pow(1.0 - fresnelLookup, 4.0);

				//float3 halfVec = normalize(i.normViewDir - normalize(i.lightDir));

				float specular = pow(max(dot(i.halfVec,  tangentNormal) , 0.0), 250.0 * _Specularity );
                
				result.rgb = lerp(_WaterColor*_FakeUnderwaterColor, _SunColor.rgb*_SurfaceColor*0.85, fresnelTerm*0.65)  + specular*_SunColor.rgb;

				UNITY_APPLY_FOG(i.fogCoord, result); 

    			return result;
			}
			ENDCG
			

		}
    }



    SubShader {
        Tags { "Queue"="Transparent" "RenderType"="Transparent" }
        LOD 1
    	Pass {
		    Blend One OneMinusSrcAlpha
			CGPROGRAM
			#pragma vertex vert
			#pragma fragment frag
			#pragma multi_compile_fog
			#include "UnityCG.cginc"

			struct v2f {
    			float4 pos : SV_POSITION;
    			half3  bumpTexCoord : TEXCOORD1;
    			float3  viewDir : TEXCOORD2;
    			float3  lightDir : TEXCOORD4;
				UNITY_FOG_COORDS(7)
				half4 buv : TEXCOORD5;
				half3 normViewDir : TEXCOORD6;
				float3 halfVec : TEXCOORD0;
			};

			float _Size;
			half4 _SunDir;
			half4 _FakeUnderwaterColor;
            half _WaveOffset;
            
			v2f vert (appdata_tan v) {
    			v2f o;
				UNITY_INITIALIZE_OUTPUT(v2f, o);

    			o.bumpTexCoord.xy = v.vertex.xz*_Size;///float2(_Size.x, _Size.z)*5;
    			o.pos = mul (UNITY_MATRIX_MVP, v.vertex);
    			o.bumpTexCoord.z = v.tangent.w;

    			float3 objSpaceViewDir = ObjSpaceViewDir(v.vertex);
    			float3 binormal = cross( normalize(v.normal), normalize(v.tangent.xyz) );
				float3x3 rotation = float3x3( v.tangent.xyz, binormal, v.normal );
    
    			o.viewDir = mul(rotation, objSpaceViewDir);
    			o.lightDir = mul(rotation, float3(_SunDir.xyz));

				o.buv = half4(o.bumpTexCoord.x + _WaveOffset * 0.05, o.bumpTexCoord.y + _WaveOffset * 0.03, o.bumpTexCoord.x + _WaveOffset * 0.04, o.bumpTexCoord.y);

				o.normViewDir = normalize(o.viewDir);

				o.halfVec = normalize(o.normViewDir - normalize(o.lightDir));

				UNITY_TRANSFER_FOG(o, o.pos);

    			return o;
			}

			sampler2D _Bump;
			sampler2D _Foam;
			half _FoamFactor;
			half4 _WaterColor;//Lod1;
			half4 _SurfaceColor;
            half _WaterLod1Alpha;
			half _Specularity;
            half4 _SunColor;

			half4 frag (v2f i) : COLOR {
				//half3 normViewDir = normalize(i.viewDir);
				//half4 buv = half4(i.bumpTexCoord.x + _WaveOffset * 0.05, i.bumpTexCoord.y + _WaveOffset * 0.03, i.bumpTexCoord.x + _WaveOffset * 0.04, i.bumpTexCoord.y - _WaveOffset * 0.02);
                
				half3 tangentNormal0 = (tex2D(_Bump, i.buv.xy) * 2.0) + (tex2D(_Bump, i.buv.zw) * 2.0) - 2;

				half3 tangentNormal = normalize(tangentNormal0);

				half4 result = half4(0, 0, 0, 1);
                
				float fresnelLookup = dot(tangentNormal, i.normViewDir);
				//float bias = 0.06;
				//float power = 4.0;
				float fresnelTerm = 0.06 + (1.0-0.06)*pow(1.0 - fresnelLookup, 4.0);

				half4 foam = clamp(tex2D(_Foam, i.bumpTexCoord.xy * 1.0)  - 0.5, 0.0, 1.0) * i.bumpTexCoord.z * _FoamFactor;;

				//float3 halfVec = normalize(i.normViewDir - normalize(i.lightDir));

				float specular = pow(max(dot(i.halfVec,  tangentNormal) , 0.0), 250.0 * _Specularity ) *(1.2-foam);
                
                
				result.rgb = lerp(_WaterColor*_FakeUnderwaterColor, _SunColor.rgb*_SurfaceColor*0.85, fresnelTerm*0.65) + clamp(foam.r, 0.0, 1.0)*_SunColor.b + specular*_SunColor.rgb;
                result.a = _WaterLod1Alpha;

				UNITY_APPLY_FOG(i.fogCoord, result); 

    			return result;
			}
			ENDCG
			

		}
    }
 

    
}
