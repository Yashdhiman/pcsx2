//#version 420 // Keep it for text editor detection

// note lerp => mix

#define FMT_32 0
#define FMT_24 1
#define FMT_16 2
#define FMT_PAL 4 /* flag bit */

// APITRACE_DEBUG allows to force pixel output to easily detect
// the fragment computed by primitive
#define APITRACE_DEBUG 0
// TEX_COORD_DEBUG output the uv coordinate as color. It is useful
// to detect bad sampling due to upscaling
//#define TEX_COORD_DEBUG

// Not sure we have same issue on opengl. Doesn't work anyway on ATI card
// And I say this as an ATI user.
#define ATI_SUCKS 0

#ifndef PS_FST
#define PS_FST 0
#define PS_WMS 0
#define PS_WMT 0
#define PS_FMT FMT_32
#define PS_AEM 0
#define PS_TFX 0
#define PS_TCC 1
#define PS_ATST 1
#define PS_FOG 0
#define PS_CLR1 0
#define PS_FBA 0
#define PS_AOUT 0
#define PS_LTF 1
#define PS_COLCLIP 0
#define PS_DATE 0
#define PS_SPRITEHACK 0
#define PS_POINT_SAMPLER 0
#define PS_TCOFFSETHACK 0
#define PS_IIP 1
#define PS_SPRITE 0
#endif

#ifdef FRAGMENT_SHADER

in SHADER
{
	vec4 t;
	vec4 c;
	flat vec4 fc;
#if PS_SPRITE == 1
	flat vec4 flat_T;
	flat vec2 flat_P;
	vec2 alpha;
#endif
} PSin;

#define PSin_t (PSin.t)
#define PSin_c (PSin.c)
#define PSin_fc (PSin.fc)

// Same buffer but 2 colors for dual source blending
#if pGL_ES
layout(location = 0) out vec4 SV_Target0;
#else
layout(location = 0, index = 0) out vec4 SV_Target0;
layout(location = 0, index = 1) out vec4 SV_Target1;
#endif

#ifdef ENABLE_BINDLESS_TEX
layout(bindless_sampler, location = 0) uniform sampler2D TextureSampler;
layout(bindless_sampler, location = 1) uniform sampler2D PaletteSampler;
#else
layout(binding = 0) uniform sampler2D TextureSampler;
layout(binding = 1) uniform sampler2D PaletteSampler;
layout(binding = 3) uniform sampler2D RtSampler; // note 2 already use by the image below
#endif

#ifndef DISABLE_GL42_image
#if PS_DATE > 0
// FIXME how to declare memory access
layout(r32i, binding = 2) coherent uniform iimage2D img_prim_min;
layout(early_fragment_tests) in;
// origin_upper_left
layout(pixel_center_integer) in vec4 gl_FragCoord;
#endif
#else
// use basic stencil
#endif


layout(std140, binding = 21) uniform cb21
{
	vec3 FogColor;
	float AREF;
	vec4 WH;
	vec2 MinF;
	vec2 TA;
	uvec4 MskFix;
	vec4 HalfTexel;
	vec4 MinMax;
	vec4 TC_OffsetHack;
};

#ifdef SUBROUTINE_GL40
// Function pointer type + the functionn pointer variable
subroutine void AlphaTestType(vec4 c);
layout(location = 0) subroutine uniform AlphaTestType atst;

subroutine vec4 TfxType(vec4 t, vec4 c);
layout(location = 2) subroutine uniform TfxType tfx;

subroutine void ColClipType(inout vec4 c);
layout(location = 1) subroutine uniform ColClipType colclip;
#endif


vec4 sample_c(vec2 uv)
{
	// FIXME: check the issue on openGL
#if (ATI_SUCKS == 1) && (PS_POINT_SAMPLER == 1)
	// Weird issue with ATI cards (happens on at least HD 4xxx and 5xxx),
	// it looks like they add 127/128 of a texel to sampling coordinates
	// occasionally causing point sampling to erroneously round up.
	// I'm manually adjusting coordinates to the centre of texels here,
	// though the centre is just paranoia, the top left corner works fine.
	uv = (trunc(uv * WH.zw) + vec2(0.5, 0.5)) / WH.zw;
#endif

	return texture(TextureSampler, uv);
}

vec4 sample_p(float u)
{
	//FIXME do we need a 1D sampler. Big impact on opengl to find 1 dim
	// So for the moment cheat with 0.0f dunno if it work
	return texture(PaletteSampler, vec2(u, 0.0f));
}

vec4 wrapuv(vec4 uv)
{
	vec4 uv_out = uv;

#if PS_WMS == PS_WMT

#if PS_WMS == 2
	uv_out = clamp(uv, MinMax.xyxy, MinMax.zwzw);
#elif PS_WMS == 3
	uv_out = vec4((ivec4(uv * WH.xyxy) & ivec4(MskFix.xyxy)) | ivec4(MskFix.zwzw)) / WH.xyxy;
#endif

#else // PS_WMS != PS_WMT

#if PS_WMS == 2
	uv_out.xz = clamp(uv.xz, MinMax.xx, MinMax.zz);

#elif PS_WMS == 3
	uv_out.xz = vec2((ivec2(uv.xz * WH.xx) & ivec2(MskFix.xx)) | ivec2(MskFix.zz)) / WH.xx;

#endif

#if PS_WMT == 2
	uv_out.yw = clamp(uv.yw, MinMax.yy, MinMax.ww);

#elif PS_WMT == 3

	uv_out.yw = vec2((ivec2(uv.yw * WH.yy) & ivec2(MskFix.yy)) | ivec2(MskFix.ww)) / WH.yy;
#endif

#endif

	return uv_out;
}

vec2 clampuv(vec2 uv)
{
	vec2 uv_out = uv;

#if (PS_WMS == 2) && (PS_WMT == 2)
	uv_out = clamp(uv, MinF, MinMax.zw);
#elif PS_WMS == 2
	uv_out.x = clamp(uv.x, MinF.x, MinMax.z);
#elif PS_WMT == 2
	uv_out.y = clamp(uv.y, MinF.y, MinMax.w);
#endif

	return uv_out;
}

mat4 sample_4c(vec4 uv)
{
	mat4 c;

	c[0] = sample_c(uv.xy);
	c[1] = sample_c(uv.zy);
	c[2] = sample_c(uv.xw);
	c[3] = sample_c(uv.zw);

	return c;
}

vec4 sample_4a(vec4 uv)
{
	vec4 c;

	// Dx used the alpha channel.
	// Opengl is only 8 bits on red channel.
	c.x = sample_c(uv.xy).r;
	c.y = sample_c(uv.zy).r;
	c.z = sample_c(uv.xw).r;
	c.w = sample_c(uv.zw).r;

	return c * 255.0/256.0 + 0.5/256.0;
}

mat4 sample_4p(vec4 u)
{
	mat4 c;

	c[0] = sample_p(u.x);
	c[1] = sample_p(u.y);
	c[2] = sample_p(u.z);
	c[3] = sample_p(u.w);

	return c;
}

vec4 sample_color(vec2 st, float q)
{
#if (PS_FST == 0)
	st /= q;
#endif

#if (PS_TCOFFSETHACK == 1)
	st += TC_OffsetHack.xy;
#endif

	vec4 t;
	mat4 c;
	vec2 dd;

#if (PS_LTF == 0 && PS_FMT <= FMT_16 && PS_WMS < 3 && PS_WMT < 3)
	c[0] = sample_c(clampuv(st));
#ifdef TEX_COORD_DEBUG
	c[0].rg = clampuv(st).xy;
#endif

#else
	vec4 uv;

	if(PS_LTF != 0)
	{
		uv = st.xyxy + HalfTexel;
		dd = fract(uv.xy * WH.zw);
	}
	else
	{
		uv = st.xyxy;
	}

	uv = wrapuv(uv);

	if((PS_FMT & FMT_PAL) != 0)
	{
		c = sample_4p(sample_4a(uv));
	}
	else
	{
		c = sample_4c(uv);
	}
#ifdef TEX_COORD_DEBUG
	c[0].rg = uv.xy;
	c[1].rg = uv.xy;
	c[2].rg = uv.xy;
	c[3].rg = uv.xy;
#endif

#endif

	// PERF: see the impact of the exansion before/after the interpolation
	for (int i = 0; i < 4; i++)
	{
#if ((PS_FMT & ~FMT_PAL) == FMT_24)
		c[i].a = ( (PS_AEM == 0) || any(bvec3(c[i].rgb))  ) ? TA.x : 0.0f;
#elif ((PS_FMT & ~FMT_PAL) == FMT_16)
		c[i].a = c[i].a >= 0.5 ? TA.y : ( (PS_AEM == 0) || any(bvec3(c[i].rgb)) ) ? TA.x : 0.0f;
#endif
	}

#if(PS_LTF != 0)
	t = mix(mix(c[0], c[1], dd.x), mix(c[2], c[3], dd.x), dd.y);
#else
	t = c[0];
#endif

	return t;
}

#ifndef SUBROUTINE_GL40
vec4 tfx(vec4 t, vec4 c)
{
	vec4 c_out = c;
#if (PS_TFX == 0)
	if(PS_TCC != 0)
		c_out = c * t * 255.0f / 128.0f;
	else
		c_out.rgb = c.rgb * t.rgb * 255.0f / 128.0f;
#elif (PS_TFX == 1)
	if(PS_TCC != 0)
		c_out = t;
	else
		c_out.rgb = t.rgb;
#elif (PS_TFX == 2)
	c_out.rgb = c.rgb * t.rgb * 255.0f / 128.0f + c.a;

	if(PS_TCC != 0)
		c_out.a += t.a;
#elif (PS_TFX == 3)
	c_out.rgb = c.rgb * t.rgb * 255.0f / 128.0f + c.a;

	if(PS_TCC != 0)
		c_out.a = t.a;
#endif

	return c_out;
}
#endif

#ifndef SUBROUTINE_GL40
void atst(vec4 c)
{
	float a = trunc(c.a * 255.0 + 0.01);

#if (PS_ATST == 0) // never
	discard;
#elif (PS_ATST == 1) // always
	// nothing to do
#elif (PS_ATST == 2) && (PS_SPRITEHACK == 0) // l
	if ((AREF - a - 0.5f) < 0.0f)
		discard;
#elif (PS_ATST == 3 ) // le
	if ((AREF - a + 0.5f) < 0.0f)
		discard;
#elif (PS_ATST == 4) // e
	if ((0.5f - abs(a - AREF)) < 0.0f)
		discard;
#elif (PS_ATST == 5) // ge
	if ((a-AREF + 0.5f) < 0.0f)
		discard;
#elif (PS_ATST == 6) // g
	if ((a-AREF - 0.5f) < 0.0f)
		discard;
#elif (PS_ATST == 7) // ne
	if ((abs(a - AREF) - 0.5f) < 0.0f)
		discard;
#endif
}
#endif

// Note layout stuff might require gl4.3
#ifndef SUBROUTINE_GL40
void colclip(inout vec4 c)
{
#if (PS_COLCLIP == 2)
	c.rgb = 256.0f/255.0f - c.rgb;
#elif (PS_COLCLIP > 0)
	// FIXME !!!!
	//c.rgb *= c.rgb < 128./255;
	bvec3 factor = bvec3(128.0f/255.0f, 128.0f/255.0f, 128.0f/255.0f);
	c.rgb *= vec3(factor);
#endif
}
#endif

void fog(inout vec4 c, float f)
{
#if PS_FOG != 0
	c.rgb = mix(FogColor, c.rgb, f);
#endif
}

vec4 ps_color()
{
#if PS_SPRITE == 1
	// Reinterpolate manually the texture coordinate.
	// trunc => native resolution. Maybe we can add an option to choose a value between
	// trunc and current.
	vec2 factor = vec2(trunc(PSin.alpha.x), floor(PSin.alpha.y));
	//vec2 factor = trunc(PSin.alpha);
	factor *= PSin.flat_P;
	vec2 txy;
	txy.x = mix(PSin.flat_T.x, PSin.flat_T.y, factor.x);
	txy.y = mix(PSin.flat_T.z, PSin.flat_T.w, factor.y);

#else
	vec2 txy = PSin_t.xy;
#endif
	vec4 t = sample_color(txy, PSin_t.w);

	vec4 zero = vec4(0.0f, 0.0f, 0.0f, 0.0f);
	vec4 one = vec4(1.0f, 1.0f, 1.0f, 1.0f);
#ifdef TEX_COORD_DEBUG
	vec4 c = clamp(t, zero, one);
#else
#if PS_IIP == 1
	vec4 c = clamp(tfx(t, PSin_c), zero, one);
#else
	vec4 c = clamp(tfx(t, PSin_fc), zero, one);
#endif
#endif

	atst(c);

	fog(c, PSin_t.z);

	colclip(c);

#if (PS_CLR1 != 0) // needed for Cd * (As/Ad/F + 1) blending modes
	c.rgb = vec3(1.0f, 1.0f, 1.0f);
#endif

	return c;
}

#if pGL_ES
void ps_main()
{
	vec4 c = ps_color();
	c.a *= 2.0;
	SV_Target0 = c;
}
#endif

#if !pGL_ES
void ps_main()
{
#if (PS_DATE & 3) == 1 && !defined(DISABLE_GL42_image)
	// DATM == 0
	// Pixel with alpha equal to 1 will failed
	float rt_a = texelFetch(RtSampler, ivec2(gl_FragCoord.xy), 0).a;
	if ((127.5f / 255.0f) < rt_a) { // < 0x80 pass (== 0x80 should not pass)
		discard;
	}
#elif (PS_DATE & 3) == 2 && !defined(DISABLE_GL42_image)
	// DATM == 1
	// Pixel with alpha equal to 0 will failed
	float rt_a = texelFetch(RtSampler, ivec2(gl_FragCoord.xy), 0).a;
	if(rt_a < (127.5f / 255.0f)) { // >= 0x80 pass
		discard;
	}
#endif

#if PS_DATE == 3 && !defined(DISABLE_GL42_image)
	int stencil_ceil = imageLoad(img_prim_min, ivec2(gl_FragCoord.xy));
	// Note gl_PrimitiveID == stencil_ceil will be the primitive that will update
	// the bad alpha value so we must keep it.

	if (gl_PrimitiveID > stencil_ceil) {
		discard;
	}
#endif

	vec4 c = ps_color();
#if (APITRACE_DEBUG & 1) == 1
	c.r = 1.0f;
#endif
#if (APITRACE_DEBUG & 2) == 2
	c.g = 1.0f;
#endif
#if (APITRACE_DEBUG & 4) == 4
	c.b = 1.0f;
#endif
#if (APITRACE_DEBUG & 8) == 8
	c.a = 0.5f;
#endif

	float alpha = c.a * 2.0;

#if (PS_AOUT != 0) // 16 bit output
	float a = 128.0f / 255.0; // alpha output will be 0x80

	c.a = (PS_FBA != 0) ? a : step(0.5, c.a) * a;
#elif (PS_FBA != 0)
	if(c.a < 0.5) c.a += 0.5;
#endif

	// Get first primitive that will write a failling alpha value
#if PS_DATE == 1 && !defined(DISABLE_GL42_image)
	// DATM == 0
	// Pixel with alpha equal to 1 will failed (128-255)
	if (c.a > 127.5f / 255.0f) {
		imageAtomicMin(img_prim_min, ivec2(gl_FragCoord.xy), gl_PrimitiveID);
	}
#elif PS_DATE == 2 && !defined(DISABLE_GL42_image)
	// DATM == 1
	// Pixel with alpha equal to 0 will failed (0-127)
	if (c.a < 127.5f / 255.0f) {
		imageAtomicMin(img_prim_min, ivec2(gl_FragCoord.xy), gl_PrimitiveID);
	}
#endif


#if (PS_DATE == 2 || PS_DATE == 1) && !defined(DISABLE_GL42_image)
	// Don't write anything on the framebuffer
	// Note: you can't use discard because it will also drop
	// image operation
#else
	SV_Target0 = c;
	SV_Target1 = vec4(alpha, alpha, alpha, alpha);
#endif

}
#endif // !pGL_ES

#endif
