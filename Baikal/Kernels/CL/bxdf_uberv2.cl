// Diffuse layer
float3 UberV2_Lambert_Evaluate(
    // Geometry
    DifferentialGeometry const* dg,
    // Incoming direction
    float3 wi,
    // Outgoing direction
    float3 wo,
    // Texture args
    TEXTURE_ARG_LIST
)
{
    const float3 kd = Texture_GetValue3f(dg->mat.uberv2.diffuse_color.xyz, dg->uv, TEXTURE_ARGS_IDX(dg->mat.uberv2.diffuse_color_idx));

    return kd / PI;
}

float UberV2_Lambert_GetPdf(
    // Geometry
    DifferentialGeometry const* dg,
    // Incoming direction
    float3 wi,
    // Outgoing direction
    float3 wo,
    // Texture args
    TEXTURE_ARG_LIST
    )
{
    return fabs(wo.y) / PI;
}

/// Lambert BRDF sampling
float3 UberV2_Lambert_Sample(
    // Geometry
    DifferentialGeometry const* dg,
    // Incoming direction
    float3 wi,
    // Texture args
    TEXTURE_ARG_LIST,
    // Sample
    float2 sample,
    // Outgoing  direction
    float3* wo,
    // PDF at wo
    float* pdf
)
{
    const float3 kd = UberV2_Lambert_Evaluate(dg, wi, *wo, TEXTURE_ARGS);

    *wo = Sample_MapToHemisphere(sample, make_float3(0.f, 1.f, 0.f), 1.f);

    *pdf = fabs((*wo).y) / PI;

    return kd;
}

// Reflection/Coating
/*
Microfacet GGX
*/
// Distribution fucntion
float UberV2_MicrofacetDistribution_GGX_D(float roughness, float3 m)
{
    float ndotm = fabs(m.y);
    float ndotm2 = ndotm * ndotm;
    float sinmn = native_sqrt(1.f - clamp(ndotm * ndotm, 0.f, 1.f));
    float tanmn = ndotm > DENOM_EPS ? sinmn / ndotm : 0.f;
    float a2 = roughness * roughness;
    float denom = (PI * ndotm2 * ndotm2 * (a2 + tanmn * tanmn) * (a2 + tanmn * tanmn));
    return denom > DENOM_EPS ? (a2 / denom) : 1.f;
}

// PDF of the given direction
float UberV2_MicrofacetDistribution_GGX_GetPdf(
    // Halfway vector
    float3 m,
    // Rougness
    float roughness,
    // Geometry
    DifferentialGeometry const* dg,
    // Incoming direction
    float3 wi,
    // Outgoing direction
    float3 wo,
    // Texture args
    TEXTURE_ARG_LIST
)
{
    float mpdf = UberV2_MicrofacetDistribution_GGX_D(roughness, m) * fabs(m.y);
    // See Humphreys and Pharr for derivation
    float denom = (4.f * fabs(dot(wo, m)));

    return denom > DENOM_EPS ? mpdf / denom : 0.f;
}

// Sample the distribution
void UberV2_MicrofacetDistribution_GGX_SampleNormal(
    // Roughness
    float roughness,
    // Differential geometry
    DifferentialGeometry const* dg,
    // Texture args
    TEXTURE_ARG_LIST,
    // Sample
    float2 sample,
    // Outgoing  direction
    float3* wh
)
{
    float r1 = sample.x;
    float r2 = sample.y;

    // Sample halfway vector first, then reflect wi around that
    float theta = atan2(roughness * native_sqrt(r1), native_sqrt(1.f - r1));
    float costheta = native_cos(theta);
    float sintheta = native_sin(theta);

    // phi = 2*PI*ksi2
    float phi = 2.f * PI * r2;
    float cosphi = native_cos(phi);
    float sinphi = native_sin(phi);

    // Calculate wh
    *wh = make_float3(sintheta * cosphi, costheta, sintheta * sinphi);
}

//
float UberV2_MicrofacetDistribution_GGX_G1(float roughness, float3 v, float3 m)
{
    float ndotv = fabs(v.y);
    float mdotv = fabs(dot(m, v));

    float sinnv = native_sqrt(1.f - clamp(ndotv * ndotv, 0.f, 1.f));
    float tannv = ndotv > DENOM_EPS ? sinnv / ndotv : 0.f;
    float a2 = roughness * roughness;
    return 2.f / (1.f + native_sqrt(1.f + a2 * tannv * tannv));
}

// Shadowing function also depends on microfacet distribution
float UberV2_MicrofacetDistribution_GGX_G(float roughness, float3 wi, float3 wo, float3 wh)
{
    return UberV2_MicrofacetDistribution_GGX_G1(roughness, wi, wh) * UberV2_MicrofacetDistribution_GGX_G1(roughness, wo, wh);
}

float3 UberV2_MicrofacetGGX_Evaluate(
    // Geometry
    DifferentialGeometry const* dg,
    // Incoming direction
    float3 wi,
    // Outgoing direction
    float3 wo,
    // Texture args
    TEXTURE_ARG_LIST
)
{
    const float3 ks = Texture_GetValue3f(dg->mat.uberv2.reflection_color.xyz, dg->uv, TEXTURE_ARGS_IDX(dg->mat.uberv2.reflection_color_idx));
    const float roughness = Texture_GetValue1f(dg->mat.uberv2.reflection_roughness, dg->uv, TEXTURE_ARGS_IDX(dg->mat.uberv2.reflection_roughness_idx));

    // Incident and reflected zenith angles
    float costhetao = fabs(wo.y);
    float costhetai = fabs(wi.y);

    // Calc halfway vector
    float3 wh = normalize(wi + wo);

    float denom = (4.f * costhetao * costhetai);

    return denom > DENOM_EPS ? ks * UberV2_MicrofacetDistribution_GGX_G(roughness, wi, wo, wh) * UberV2_MicrofacetDistribution_GGX_D(roughness, wh) / denom : 0.f;
}


float UberV2_MicrofacetGGX_GetPdf(
    // Geometry
    DifferentialGeometry const* dg,
    // Incoming direction
    float3 wi,
    // Outgoing direction
    float3 wo,
    // Texture args
    TEXTURE_ARG_LIST
)
{
    const float roughness = Texture_GetValue1f(dg->mat.uberv2.reflection_roughness, dg->uv, TEXTURE_ARGS_IDX(dg->mat.uberv2.reflection_roughness_idx));

    float3 wh = normalize(wo + wi);

    return UberV2_MicrofacetDistribution_GGX_GetPdf(wh, roughness, dg, wi, wo, TEXTURE_ARGS);
}

float3 UberV2_MicrofacetGGX_Sample(
    // Geometry
    DifferentialGeometry const* dg,
    // Incoming direction
    float3 wi,
    // Texture args
    TEXTURE_ARG_LIST,
    // Sample
    float2 sample,
    // Outgoing  direction
    float3* wo,
    // PDF at wo
    float* pdf
)
{
    const float roughness = Texture_GetValue1f(dg->mat.uberv2.reflection_roughness, dg->uv, TEXTURE_ARGS_IDX(dg->mat.uberv2.reflection_roughness_idx));

    float3 wh;
    UberV2_MicrofacetDistribution_GGX_SampleNormal(roughness, dg, TEXTURE_ARGS, sample, &wh);

    *wo = -wi + 2.f*fabs(dot(wi, wh)) * wh;

    *pdf = UberV2_MicrofacetDistribution_GGX_GetPdf(wh, roughness, dg, wi, *wo, TEXTURE_ARGS);

    return UberV2_MicrofacetGGX_Evaluate(dg, wi, *wo, TEXTURE_ARGS);
}

/*
Ideal reflection BRDF
*/
float3 UberV2_IdealReflect_Evaluate(
    // Geometry
    DifferentialGeometry const* dg,
    // Incoming direction
    float3 wi,
    // Outgoing direction
    float3 wo,
    // Texture args
    TEXTURE_ARG_LIST
)
{
    return 0.f;
}

float UberV2_IdealReflect_GetPdf(
    // Geometry
    DifferentialGeometry const* dg,
    // Incoming direction
    float3 wi,
    // Outgoing direction
    float3 wo,
    // Texture args
    TEXTURE_ARG_LIST
)
{
    return 0.f;
}

float3 UberV2_IdealReflect_Sample(
    // Geometry
    DifferentialGeometry const* dg,
    // Incoming direction
    float3 wi,
    // Texture args
    TEXTURE_ARG_LIST,
    // Outgoing  direction
    float3* wo,
    // PDF at wo
    float* pdf,
    float3 ks)
{
    // Mirror reflect wi
    *wo = normalize(make_float3(-wi.x, wi.y, -wi.z));

    // PDF is infinite at that point, but deltas are going to cancel out while evaluating
    // so set it to 1.f
    *pdf = 1.f;

    float coswo = fabs((*wo).y);

    // Return reflectance value
    return coswo > DENOM_EPS ? (ks * (1.f / coswo)) : 0.f;
}

// Refraction
/*
Ideal refraction BTDF
*/

float3 UberV2_IdealRefract_Evaluate(
    // Geometry
    DifferentialGeometry const* dg,
    // Incoming direction
    float3 wi,
    // Outgoing direction
    float3 wo,
    // Texture args
    TEXTURE_ARG_LIST
)
{
    return 0.f;
}

float UberV2_IdealRefract_GetPdf(
    // Geometry
    DifferentialGeometry const* dg,
    // Incoming direction
    float3 wi,
    // Outgoing direction
    float3 wo,
    // Texture args
    TEXTURE_ARG_LIST
)
{
    return 0.f;
}

float3 UberV2_IdealRefract_Sample(
    // Geometry
    DifferentialGeometry const* dg,
    // Incoming direction
    float3 wi,
    // Texture args
    TEXTURE_ARG_LIST,
    // Sample
    float2 sample,
    // Outgoing  direction
    float3* wo,
    // PDF at wo
    float* pdf
)
{
    const float3 ks = Texture_GetValue3f(dg->mat.uberv2.refraction_color.xyz, dg->uv, TEXTURE_ARGS_IDX(dg->mat.uberv2.refraction_color_idx));

    float etai = 1.f;
    float etat = dg->mat.uberv2.refraction_ior;
    float cosi = wi.y;

    bool entering = cosi > 0.f;

    // Revert normal and eta if needed
    if (!entering)
    {
        float tmp = etai;
        etai = etat;
        etat = tmp;
    }

    float eta = etai / etat;
    float sini2 = 1.f - cosi * cosi;
    float sint2 = eta * eta * sini2;

    if (sint2 >= 1.f)
    {
        *pdf = 0.f;
        return 0.f;
    }

    float cost = native_sqrt(max(0.f, 1.f - sint2));

    // Transmitted ray
    *wo = normalize(make_float3(eta * -wi.x, entering ? -cost : cost, eta * -wi.z));

    *pdf = 1.f;

    return cost > DENOM_EPS ? (eta * eta * ks / cost) : 0.f;
}


float3 UberV2_MicrofacetRefractionGGX_Evaluate(
    // Geometry
    DifferentialGeometry const* dg,
    // Incoming direction
    float3 wi,
    // Outgoing direction
    float3 wo,
    // Texture args
    TEXTURE_ARG_LIST
)
{
    const float3 ks = Texture_GetValue3f(dg->mat.uberv2.refraction_color.xyz, dg->uv, TEXTURE_ARGS_IDX(dg->mat.uberv2.refraction_color_idx));
    const float roughness = max(Texture_GetValue1f(dg->mat.uberv2.refraction_roughness, dg->uv, TEXTURE_ARGS_IDX(dg->mat.uberv2.refraction_roughness_idx)), ROUGHNESS_EPS);

    float ndotwi = wi.y;
    float ndotwo = wo.y;

    if (ndotwi * ndotwo >= 0.f)
    {
        return 0.f;
    }

    float etai = 1.f;
    float etat = dg->mat.uberv2.refraction_ior;

    // Revert normal and eta if needed
    if (ndotwi < 0.f)
    {
        float tmp = etai;
        etai = etat;
        etat = tmp;
    }

    // Calc halfway vector
    float3 ht = -(etai * wi + etat * wo);
    float3 wh = normalize(ht);

    float widotwh = fabs(dot(wh, wi));
    float wodotwh = fabs(dot(wh, wo));

    float denom = dot(ht, ht);
    denom *= (fabs(ndotwi) * fabs(ndotwo));

    return denom > DENOM_EPS ? (ks * (widotwh * wodotwh)  * (etat)* (etat)*
        UberV2_MicrofacetDistribution_GGX_G(roughness, wi, wo, wh) * UberV2_MicrofacetDistribution_GGX_D(roughness, wh) / denom) : 0.f;
}

float UberV2_MicrofacetRefractionGGX_GetPdf(
    // Geometry
    DifferentialGeometry const* dg,
    // Incoming direction
    float3 wi,
    // Outgoing direction
    float3 wo,
    // Texture args
    TEXTURE_ARG_LIST
)
{
    const float roughness = max(Texture_GetValue1f(dg->mat.uberv2.refraction_roughness, dg->uv, TEXTURE_ARGS_IDX(dg->mat.uberv2.refraction_roughness_idx)), ROUGHNESS_EPS);
    
    float ndotwi = wi.y;
    float ndotwo = wo.y;
    
    if (ndotwi * ndotwo >= 0.f)
    {
        return 0.f;
    }

    float etai = 1.f;
    float etat = dg->mat.uberv2.refraction_ior;

    // Revert normal and eta if needed
    if (ndotwi < 0.f)
    {
        float tmp = etai;
        etai = etat;
        etat = tmp;
    }

    // Calc halfway vector
    float3 ht = -(etai * wi + etat * wo);

    float3 wh = normalize(ht);

    float wodotwh = fabs(dot(wo, wh));

    float whpdf = UberV2_MicrofacetDistribution_GGX_D(roughness, wh) * fabs(wh.y);

    float whwo = wodotwh * etat * etat;

    float denom = dot(ht, ht);

    return denom > DENOM_EPS ? whpdf * whwo / denom : 0.f;
}

float3 UberV2_MicrofacetRefractionGGX_Sample(
    // Geometry
    DifferentialGeometry const* dg,
    // Incoming direction
    float3 wi,
    // Texture args
    TEXTURE_ARG_LIST,
    // Sample
    float2 sample,
    // Outgoing  direction
    float3* wo,
    // PDF at wo
    float* pdf
)
{
    const float3 ks = Texture_GetValue3f(dg->mat.uberv2.refraction_color.xyz, dg->uv, TEXTURE_ARGS_IDX(dg->mat.uberv2.refraction_color_idx));
    const float roughness = max(Texture_GetValue1f(dg->mat.uberv2.refraction_roughness, dg->uv, TEXTURE_ARGS_IDX(dg->mat.uberv2.refraction_roughness_idx)), ROUGHNESS_EPS);

    float ndotwi = wi.y;

    if (ndotwi == 0.f)
    {
        *pdf = 0.f;
        return 0.f;
    }

    float etai = 1.f;
    float etat = dg->mat.uberv2.refraction_ior;
    float s = 1.f;

    // Revert normal and eta if needed
    if (ndotwi < 0.f)
    {
        float tmp = etai;
        etai = etat;
        etat = tmp;
        s = -s;
    }

    float3 wh;
    UberV2_MicrofacetDistribution_GGX_SampleNormal(roughness, dg, TEXTURE_ARGS, sample, &wh);

    float c = dot(wi, wh);
    float eta = etai / etat;

    float d = 1 + eta * (c * c - 1);

    if (d <= 0.f)
    {
        *pdf = 0.f;
        return 0.f;
    }

    *wo = normalize((eta * c - s * native_sqrt(d)) * wh - eta * wi);

    *pdf = UberV2_MicrofacetRefractionGGX_GetPdf(dg, wi, *wo, TEXTURE_ARGS);

    return UberV2_MicrofacetRefractionGGX_Evaluate(dg, wi, *wo, TEXTURE_ARGS);
}

float CalculateFresnel(
    float ndotwi,
    // Incoming direction
    float3 wi,
    // Geometry
    DifferentialGeometry const* dg,
    float top_ior,
    float bottom_ior
)
{
    if (ndotwi < 0.f && dg->mat.thin)
    {
        ndotwi = -ndotwi;
    }

    float etai =  top_ior;
    float etat =  bottom_ior;
    float cosi = ndotwi;

    // Revert normal and eta if needed
    if (cosi < 0.f)
    {
        float tmp = etai;
        etai = etat;
        etat = tmp;
        cosi = -cosi;
    }

    float eta = etai / etat;
    float sini2 = 1.f - cosi * cosi;
    float sint2 = eta * eta * sini2;
    float fresnel = 1.f;

    if (sint2 < 1.f)
    {
        float cost = native_sqrt(max(0.f, 1.f - sint2));
        fresnel = FresnelDielectric(etai, etat, cosi, cost);
    }

    return fresnel;
}

void GetMaterialBxDFType(
    // Incoming direction
    float3 wi,
    // RNG
    float2 sample,
    // Geometry
    DifferentialGeometry* dg
)
{
    dg->mat.bxdf_flags = 0;
    if ((dg->mat.uberv2.layers & kEmissionLayer) == kEmissionLayer) dg->mat.bxdf_flags = kBxdfEmissive;
    if ((dg->mat.uberv2.layers & kTransparencyLayer) == kTransparencyLayer) dg->mat.bxdf_flags |= kBxdfTransparency;
    if ((dg->mat.uberv2.layers & (kCoatingLayer | kReflectionLayer)) > 0)
    {
        if (((dg->mat.uberv2.layers & kReflectionLayer) == kReflectionLayer))
        {
            if ((dg->mat.uberv2.reflection_roughness_idx == -1) && (dg->mat.uberv2.reflection_roughness < ROUGHNESS_EPS))
            {
                dg->mat.bxdf_flags |= kBxdfSingular;
            }
        }
        else
        {
            dg->mat.bxdf_flags |= kBxdfSingular;
        }
    }
    
    int bxdf_type = (dg->mat.uberv2.layers & (kCoatingLayer | kReflectionLayer | kRefractionLayer));
    
    if ((bxdf_type & kRefractionLayer) != kRefractionLayer)
    {
        dg->mat.bxdf_flags |= kBxdfBrdf;
    }
    else
    {
        //We have refraction
        float ndotwi = dot(dg->n, wi);
        if ((bxdf_type & kCoatingLayer) > 0)
        {
            float fresnel = CalculateFresnel(ndotwi, wi, dg, 1.0f, dg->mat.uberv2.coating_ior);
            
            if (sample.x < fresnel)
            {
                dg->mat.bxdf_flags |= kBxdfBrdf;
                return;
            }
            else if ((bxdf_type & kReflectionLayer) > 0)
            {
                float fresnel = CalculateFresnel(ndotwi, wi, dg, dg->mat.uberv2.coating_ior, dg->mat.uberv2.reflection_ior);

                if (sample.y < fresnel)
                {
                    dg->mat.bxdf_flags |= kBxdfBrdf;
                    return;
                }
            }
        }
        else
        {
            float fresnel = CalculateFresnel(ndotwi, wi, dg, 1.0f, dg->mat.uberv2.reflection_ior);

            if (sample.x < fresnel)
            {
                dg->mat.bxdf_flags |= kBxdfBrdf;
                return;
            }
        }
    }
}


float3 UberV2_Evaluate(
    // Geometry
    DifferentialGeometry const* dg,
    // Incoming direction
    float3 wi,
    // Outgoing direction
    float3 wo,
    // Texture args
    TEXTURE_ARG_LIST
)
{
    int layers = dg->mat.uberv2.layers;
    //All 3 layers
    if ((layers & (kCoatingLayer | kReflectionLayer | kDiffuseLayer)) == (kCoatingLayer | kReflectionLayer | kDiffuseLayer))
    {
        float coating_fresnel = CalculateFresnel(wi.y, wi, dg, 1.0f, dg->mat.uberv2.coating_ior);
        float reflection_fresnel = CalculateFresnel(wi.y, wi, dg, dg->mat.uberv2.coating_ior, dg->mat.uberv2.reflection_ior);

        float3 coating = UberV2_IdealReflect_Evaluate(dg, wi, wo, TEXTURE_ARGS);
        float3 reflection = (dg->mat.bxdf_flags & kBxdfSingular) ? UberV2_IdealReflect_Evaluate(dg, wi, wo, TEXTURE_ARGS) :
            UberV2_MicrofacetGGX_Evaluate(dg, wi, wo, TEXTURE_ARGS);
        float3 diffuse = UberV2_Lambert_Evaluate(dg, wi, wo, TEXTURE_ARGS);

        return coating_fresnel * coating + (1.0f - coating_fresnel) *
            (reflection_fresnel * reflection + (1.0f - reflection_fresnel) * diffuse);
    }
    else if ((layers & (kCoatingLayer | kDiffuseLayer)) == (kCoatingLayer | kDiffuseLayer))
    {
        float coating_fresnel = CalculateFresnel(wi.y, wi, dg, 1.0f, dg->mat.uberv2.coating_ior);
        float3 coating = UberV2_IdealReflect_Evaluate(dg, wi, wo, TEXTURE_ARGS);
        float3 diffuse = UberV2_Lambert_Evaluate(dg, wi, wo, TEXTURE_ARGS);

        return coating_fresnel * coating + (1.0f - coating_fresnel) * diffuse;
    }
    else if ((layers & (kReflectionLayer | kDiffuseLayer)) == (kReflectionLayer | kDiffuseLayer))
    {
        float reflection_fresnel = CalculateFresnel(wi.y, wi, dg, dg->mat.uberv2.coating_ior, dg->mat.uberv2.reflection_ior);
        float3 reflection = (dg->mat.bxdf_flags & kBxdfSingular) ? UberV2_IdealReflect_Evaluate(dg, wi, wo, TEXTURE_ARGS) :
            UberV2_MicrofacetGGX_Evaluate(dg, wi, wo, TEXTURE_ARGS);
        float3 diffuse = UberV2_Lambert_Evaluate(dg, wi, wo, TEXTURE_ARGS);

        return reflection_fresnel * reflection + (1.0f - reflection_fresnel) * diffuse;
    }

    return UberV2_Lambert_Evaluate(dg, wi, wo, TEXTURE_ARGS);
}

/// Lambert BRDF PDF
float UberV2_GetPdf(
    // Geometry
    DifferentialGeometry const* dg,
    // Incoming direction
    float3 wi,
    // Outgoing direction
    float3 wo,
    // Texture args
    TEXTURE_ARG_LIST
)
{
    int layers = dg->mat.uberv2.layers;
    
    if ((layers & (kCoatingLayer | kReflectionLayer | kDiffuseLayer)) == (kCoatingLayer | kReflectionLayer | kDiffuseLayer))
    {
        float coating_fresnel = CalculateFresnel(wi.y, wi, dg, 1.0f, dg->mat.uberv2.coating_ior);
        float reflection_fresnel = CalculateFresnel(wi.y, wi, dg, dg->mat.uberv2.coating_ior, dg->mat.uberv2.reflection_ior);

        float coating = UberV2_IdealReflect_GetPdf(dg, wi, wo, TEXTURE_ARGS);
        float reflection = (dg->mat.bxdf_flags & kBxdfSingular) ? UberV2_IdealReflect_GetPdf(dg, wi, wo, TEXTURE_ARGS) :
            UberV2_MicrofacetGGX_GetPdf(dg, wi, wo, TEXTURE_ARGS);
        float diffuse = UberV2_Lambert_GetPdf(dg, wi, wo, TEXTURE_ARGS);

        return coating_fresnel * coating + (1.0f - coating_fresnel) *
            (reflection_fresnel * reflection + (1.0f - reflection_fresnel) * diffuse);
    }
    else if ((layers & (kCoatingLayer | kDiffuseLayer)) == (kCoatingLayer | kDiffuseLayer))
    {
        float coating_fresnel = CalculateFresnel(wi.y, wi, dg, 1.0f, dg->mat.uberv2.coating_ior);
        float coating = UberV2_IdealReflect_GetPdf(dg, wi, wo, TEXTURE_ARGS);
        float diffuse = UberV2_Lambert_GetPdf(dg, wi, wo, TEXTURE_ARGS);

        return coating_fresnel * coating + (1.0f - coating_fresnel) * diffuse;
    }
    else if ((layers & (kReflectionLayer | kDiffuseLayer)) == (kReflectionLayer | kDiffuseLayer))
    {
        float reflection_fresnel = CalculateFresnel(wi.y, wi, dg, dg->mat.uberv2.coating_ior, dg->mat.uberv2.reflection_ior);
        float reflection = (dg->mat.bxdf_flags & kBxdfSingular) ? UberV2_IdealReflect_GetPdf(dg, wi, wo, TEXTURE_ARGS) :
            UberV2_MicrofacetGGX_GetPdf(dg, wi, wo, TEXTURE_ARGS);
        float diffuse = UberV2_Lambert_GetPdf(dg, wi, wo, TEXTURE_ARGS);

        return reflection_fresnel * reflection + (1.0f - reflection_fresnel) * diffuse;
    }
    
    return UberV2_Lambert_GetPdf(dg, wi, wo, TEXTURE_ARGS);
}

/// Lambert BRDF sampling
float3 UberV2_Sample(
    // Geometry
    DifferentialGeometry const* dg,
    // Incoming direction
    float3 wi,
    // Texture args
    TEXTURE_ARG_LIST,
    // Sample
    float2 sample,
    // Outgoing  direction
    float3* wo,
    // PDF at wo
    float* pdf
)
{
    int layers = dg->mat.uberv2.layers;
    float3 result;
    //All 3 layers
    if ((layers & (kCoatingLayer | kReflectionLayer | kDiffuseLayer)) == (kCoatingLayer | kReflectionLayer | kDiffuseLayer))
    {
        float coating_fresnel = CalculateFresnel(wi.y, wi, dg, 1.0f, dg->mat.uberv2.coating_ior);

        if (sample.x < coating_fresnel)
        {
            float3 ks = Texture_GetValue3f(dg->mat.uberv2.coating_color.xyz, dg->uv, TEXTURE_ARGS_IDX(dg->mat.uberv2.coating_color_idx));

            sample.x /= coating_fresnel;
            result = UberV2_IdealReflect_Sample(dg, wi, TEXTURE_ARGS, wo, pdf, ks);
        }
        else
        {
            sample.x /= (1.f - coating_fresnel);

            float reflection_fresnel = CalculateFresnel(wi.y, wi, dg, dg->mat.uberv2.coating_ior, dg->mat.uberv2.reflection_ior);
            if (sample.y < reflection_fresnel)
            {
                sample.y /= coating_fresnel;
                if (dg->mat.bxdf_flags & kBxdfSingular)
                {
                    float3 ks = Texture_GetValue3f(dg->mat.uberv2.reflection_color.xyz, dg->uv, TEXTURE_ARGS_IDX(dg->mat.uberv2.reflection_color_idx));
                    result = UberV2_IdealReflect_Sample(dg, wi, TEXTURE_ARGS, wo, pdf, ks);
                }
                else
                {
                    result = UberV2_MicrofacetGGX_Sample(dg, wi, TEXTURE_ARGS, sample, wo, pdf);
                }
            }
            else
            {
                sample.y /= (1.f - coating_fresnel);
                result = UberV2_Lambert_Sample(dg, wi, TEXTURE_ARGS, sample, wo, pdf);
            }
        }
    }
    else if ((layers & (kCoatingLayer | kDiffuseLayer)) == (kCoatingLayer | kDiffuseLayer))
    {
        float coating_fresnel = CalculateFresnel(wi.y, wi, dg, 1.0f, dg->mat.uberv2.coating_ior);
        if (sample.x < coating_fresnel)
        {
            sample.x /= coating_fresnel;
            float3 ks = Texture_GetValue3f(dg->mat.uberv2.coating_color.xyz, dg->uv, TEXTURE_ARGS_IDX(dg->mat.uberv2.coating_color_idx));
            result = UberV2_IdealReflect_Sample(dg, wi, TEXTURE_ARGS, wo, pdf, ks);
        }
        else
        {
            sample.x /= (1.f - coating_fresnel);

            result = UberV2_Lambert_Sample(dg, wi, TEXTURE_ARGS, sample, wo, pdf);
        }
    }
    else if ((layers & (kReflectionLayer | kDiffuseLayer)) == (kReflectionLayer | kDiffuseLayer))
    {
        float reflection_fresnel = CalculateFresnel(wi.y, wi, dg, 1.0f, dg->mat.uberv2.reflection_ior);

        if (sample.x < reflection_fresnel)
        {
            sample.x /= reflection_fresnel;
            if (dg->mat.bxdf_flags & kBxdfSingular)
            {
                float3 ks = Texture_GetValue3f(dg->mat.uberv2.reflection_color.xyz, dg->uv, TEXTURE_ARGS_IDX(dg->mat.uberv2.reflection_color_idx));
                result = UberV2_IdealReflect_Sample(dg, wi, TEXTURE_ARGS, wo, pdf, ks);
            }
            else
            {
                result = UberV2_MicrofacetGGX_Sample(dg, wi, TEXTURE_ARGS, sample, wo, pdf);
            }
        }
        else
        {
            sample.x /= (1.f - reflection_fresnel);

            result = UberV2_Lambert_Sample(dg, wi, TEXTURE_ARGS, sample, wo, pdf);
        }
    }
    else
    {
        result = UberV2_Lambert_Sample(dg, wi, TEXTURE_ARGS, sample, wo, pdf);
    }

    return result;// UberV2_Lambert_Sample(dg, wi, TEXTURE_ARGS, sample, wo, pdf);
}
