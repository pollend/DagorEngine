#include <math/dag_TMatrix.h>
#include "render.h"

#include <vecmath/dag_vecMath_common.h>
#include "textureloader.h"

#include <3d/dag_drv3d.h>
#include <3d/dag_tex3d.h>
#include <AvailabilityMacros.h>

#include <osApiWrappers/dag_miscApi.h>
#include "pools.h"
#include <util/dag_string.h>
#include <generic/dag_sort.h>
#include "statStr.h"
#include <basetexture.h>
#include <validateUpdateSubRegion.h>

typedef drv3d_generic::ObjectProxyPtr<drv3d_metal::Texture::ApiTexture> TextureProxyPtr;

static drv3d_generic::ObjectPoolWithLock<TextureProxyPtr> g_textures("textures");

namespace drv3d_metal
{
  void clear_textures_pool_garbage() { g_textures.clearGarbage(); }
  static bool add_texture_to_list(drv3d_metal::Texture::ApiTexture *t)
  {
    TextureProxyPtr e;
    e.obj = t;
    t->tid = g_textures.safeAllocAndSet(e);
    return t->tid != drv3d_generic::BAD_HANDLE;
  }

  MTLSamplerDescriptor* Texture::samplerDescriptor = NULL;
  Tab<Texture::SamplerState> Texture::states;

  MTLPixelFormat Texture::format2Metal(uint32_t fmt)
  {
    switch (fmt)
    {
      case TEXFMT_A8R8G8B8:     return MTLPixelFormatBGRA8Unorm;
      case TEXFMT_A2R10G10B10:  return MTLPixelFormatRGB10A2Unorm;
      case TEXFMT_A2B10G10R10:  return MTLPixelFormatRGB10A2Unorm;
      case TEXFMT_A16B16G16R16:   return MTLPixelFormatRGBA16Unorm;
      case TEXFMT_A16B16G16R16F:  return MTLPixelFormatRGBA16Float;
      case TEXFMT_A32B32G32R32F:  return MTLPixelFormatRGBA32Float;
      case TEXFMT_G16R16:     return MTLPixelFormatRG16Unorm;
      case TEXFMT_G16R16F:    return MTLPixelFormatRG16Float;
      case TEXFMT_G32R32F:    return MTLPixelFormatRG32Float;
      case TEXFMT_R16F:       return MTLPixelFormatR16Float;
      case TEXFMT_R32F:       return MTLPixelFormatR32Float;
#if _TARGET_PC_MACOSX
      case TEXFMT_DXT1:       return MTLPixelFormatBC1_RGBA;
      case TEXFMT_DXT3:       return MTLPixelFormatBC2_RGBA;
      case TEXFMT_DXT5:       return MTLPixelFormatBC3_RGBA;
      case TEXFMT_ATI1N:      return MTLPixelFormatBC4_RUnorm;
      case TEXFMT_ATI2N:      return MTLPixelFormatBC5_RGUnorm;
      case TEXFMT_BC6H:       return MTLPixelFormatBC6H_RGBFloat;
      case TEXFMT_BC7:      return MTLPixelFormatBC7_RGBAUnorm;
#else
      case TEXFMT_PVRTC2X:        return MTLPixelFormatPVRTC_RGB_2BPP;
      case TEXFMT_PVRTC2A:        return MTLPixelFormatPVRTC_RGBA_2BPP;
      case TEXFMT_PVRTC4X:        return MTLPixelFormatPVRTC_RGB_4BPP;
      case TEXFMT_PVRTC4A:        return MTLPixelFormatPVRTC_RGBA_4BPP;
      case TEXFMT_ASTC4:          return MTLPixelFormatASTC_4x4_LDR;
      case TEXFMT_ASTC8:          return MTLPixelFormatASTC_8x8_LDR;
      case TEXFMT_ASTC12:         return MTLPixelFormatASTC_12x12_LDR;
#endif
      case TEXFMT_R32G32UI: return MTLPixelFormatRG32Uint;
      case TEXFMT_ETC2_RGBA:
        if (@available(iOS 13, macOS 11.0, *))
        {
          return MTLPixelFormatEAC_RGBA8;
        }
        else
        {
          return MTLPixelFormatInvalid;
        }
      case TEXFMT_ETC2_RG:
        if (@available(iOS 13, macOS 11.0, *))
        {
          return MTLPixelFormatEAC_RG11Unorm;
        }
        else
        {
          return MTLPixelFormatInvalid;
        }

      //case TEXFMT_V16U16:     return MTLPixelFormatBC1_RGBA;
      case TEXFMT_L16:      return MTLPixelFormatR16Unorm;
      case TEXFMT_A8:       return MTLPixelFormatA8Unorm;
      case TEXFMT_L8:       return MTLPixelFormatR8Unorm;
#if _TARGET_PC_MACOSX
      case TEXFMT_A1R5G5B5:  return MTLPixelFormatBGRA8Unorm;
      case TEXFMT_A4R4G4B4:     return MTLPixelFormatBGRA8Unorm;
      case TEXFMT_R5G6B5:     return MTLPixelFormatBGRA8Unorm;
#else
      case TEXFMT_A1R5G5B5:  return MTLPixelFormatBGR5A1Unorm;
      case TEXFMT_A4R4G4B4:     return MTLPixelFormatABGR4Unorm;
      case TEXFMT_R5G6B5:     return MTLPixelFormatB5G6R5Unorm;
#endif
      case TEXFMT_A8L8:       return MTLPixelFormatRG8Unorm;
      case TEXFMT_A16B16G16R16S:  return MTLPixelFormatRGBA16Snorm;
      case TEXFMT_A16B16G16R16UI: return MTLPixelFormatRGBA16Uint;
      case TEXFMT_A32B32G32R32UI: return MTLPixelFormatRGBA32Uint;
      case TEXFMT_R8G8B8A8:     return MTLPixelFormatRGBA8Unorm;
      case TEXFMT_R32UI:      return MTLPixelFormatR32Uint;
      case TEXFMT_R8UI:       return MTLPixelFormatR8Uint;
      case TEXFMT_R11G11B10F:   return MTLPixelFormatRG11B10Float;
      case TEXFMT_R9G9B9E5:   return MTLPixelFormatRGB9E5Float;
      case TEXFMT_R8G8:       return MTLPixelFormatRG8Unorm;
      case TEXFMT_R8G8S:      return MTLPixelFormatRG8Snorm;
      case TEXFMT_DEPTH24:    return MTLPixelFormatDepth32Float_Stencil8;// MTLPixelFormatDepth24Unorm_Stencil8;
      case TEXFMT_DEPTH16:
        if (@available(iOS 13, macOS 10.12, *))
        {
          return MTLPixelFormatDepth16Unorm;
        }
        else
        {
          return MTLPixelFormatDepth32Float;
        }
      case TEXFMT_DEPTH32:    return MTLPixelFormatDepth32Float;
      case TEXFMT_DEPTH32_S8:   return MTLPixelFormatDepth32Float_Stencil8;
    }

    fatal("format2Metal unimplemented for format %i", fmt);

    return MTLPixelFormatInvalid;
  }

  MTLPixelFormat Texture::format2MetalsRGB(uint32_t fmt)
  {
    switch (fmt)
    {
#if _TARGET_PC_MACOSX
      case TEXFMT_DXT1:      return MTLPixelFormatBC1_RGBA_sRGB;
      case TEXFMT_DXT3:      return MTLPixelFormatBC2_RGBA_sRGB;
      case TEXFMT_DXT5:      return MTLPixelFormatBC3_RGBA_sRGB;
      case TEXFMT_BC7:       return MTLPixelFormatBC7_RGBAUnorm_sRGB;
      case TEXFMT_A8R8G8B8:  return MTLPixelFormatBGRA8Unorm_sRGB;
      case TEXFMT_A4R4G4B4:  return MTLPixelFormatBGRA8Unorm_sRGB;
#else
      case TEXFMT_ASTC4:     return MTLPixelFormatASTC_4x4_sRGB;
      case TEXFMT_ASTC8:     return MTLPixelFormatASTC_8x8_sRGB;
      case TEXFMT_ASTC12:    return MTLPixelFormatASTC_12x12_sRGB;
      case TEXFMT_A8R8G8B8:  return MTLPixelFormatBGRA8Unorm_sRGB;
      case TEXFMT_A4R4G4B4:  return MTLPixelFormatABGR4Unorm;
      case TEXFMT_PVRTC2X:   return MTLPixelFormatPVRTC_RGB_2BPP_sRGB;
      case TEXFMT_PVRTC2A:   return MTLPixelFormatPVRTC_RGBA_2BPP_sRGB;
      case TEXFMT_PVRTC4X:   return MTLPixelFormatPVRTC_RGB_4BPP_sRGB;
      case TEXFMT_PVRTC4A:   return MTLPixelFormatPVRTC_RGBA_4BPP_sRGB;
#endif
      case TEXFMT_ETC2_RGBA:
        if (@available(iOS 13, macOS 11.0, *))
        {
          return MTLPixelFormatEAC_RGBA8_sRGB;
        }
        else
        {
          return MTLPixelFormatInvalid;
        }
    }

    return format2Metal(fmt);
  }

  int Texture::getMaxLevels(int width, int height)
  {
    int levels = 1;

    int wdt = width;
    int hgt = height;

    while (wdt != 1 || hgt != 1)
    {
      if (wdt > 1)
      {
        wdt = wdt >> 1;
      }

      if (hgt > 1)
      {
        hgt = hgt >> 1;
      }

      levels++;
    }

    return levels;
  }

  void Texture::getStride(uint32_t fmt, int width, int height, int level, int& widBytes, int& nBytes)
  {
    width = max(width >> level, 1);
    height = max(height >> level, 1);

    bool is_copmressed = false;
    int  block_size = 1;

    if (fmt == TEXFMT_ASTC4 || fmt == TEXFMT_ASTC8 ||
        fmt == TEXFMT_PVRTC2X || fmt == TEXFMT_PVRTC2A ||
        fmt == TEXFMT_PVRTC4X || fmt == TEXFMT_PVRTC4A)
    {
      int block_width, block_height;
      int block_byte_count = 8;

      if (fmt == TEXFMT_PVRTC4X || fmt == TEXFMT_PVRTC4A)
      {
        block_width = block_height = 4;
      }
      else
      if (fmt == TEXFMT_ASTC4)
      {
        block_width = block_height = 4;
        block_byte_count = 16;
      }
      else
      if (fmt == TEXFMT_ASTC8)
      {
        block_width = block_height = 8;
        block_byte_count = 16;
      }
      else
      if (fmt == TEXFMT_ASTC12)
      {
        block_width = block_height = 12;
        block_byte_count = 16;
      }
      else
      {
        block_width = 8;
        block_height = 4;
      }

      widBytes = block_byte_count * ((width + block_width - 1) / block_width);
      nBytes = widBytes * ((height + block_height - 1) / block_height);

      if (fmt == TEXFMT_ASTC4 || fmt == TEXFMT_ASTC8 || fmt == TEXFMT_ASTC12)
      {
        if (nBytes < 16)
        {
          nBytes = 16;
        }
      }
      else
      if (nBytes < 32)
      {
        nBytes = 32;
      }

      return;
    }

    switch (fmt)
    {
      case TEXFMT_R8G8:
      case TEXFMT_R8G8S:
      case TEXFMT_A8L8:
      case TEXFMT_R16F:
      case TEXFMT_L16:
      {
          block_size = 2;
          break;
      }
      case TEXFMT_A8R8G8B8:
      case TEXFMT_A4R4G4B4:
      case TEXFMT_R8G8B8A8:
      case TEXFMT_A2R10G10B10:
      case TEXFMT_A2B10G10R10:
      case TEXFMT_G16R16:
      case TEXFMT_G16R16F:
      case TEXFMT_R32F:
      case TEXFMT_R32UI:
      case TEXFMT_R11G11B10F:
      case TEXFMT_R9G9B9E5:
      {
          block_size = 4;
          break;
      }
      case TEXFMT_A16B16G16R16:
      case TEXFMT_A16B16G16R16F:
      case TEXFMT_A16B16G16R16S:
      case TEXFMT_A16B16G16R16UI:
      case TEXFMT_R32G32UI:
      case TEXFMT_G32R32F:
      {
          block_size = 8;
          break;
      }
      case TEXFMT_A32B32G32R32F:
      case TEXFMT_A32B32G32R32UI:
      {
          block_size = 16;
          break;
      }
      case TEXFMT_DXT1:
      case TEXFMT_ATI1N:
      {
          is_copmressed = true;
          block_size = 8;
          break;
      }
      case TEXFMT_DXT3:
      case TEXFMT_DXT5:
      case TEXFMT_BC7:
      case TEXFMT_ATI2N:
      case TEXFMT_ETC2_RGBA:
      case TEXFMT_ETC2_RG:
      {
          is_copmressed = true;
          block_size = 16;
          break;
      }
      case TEXFMT_A8:
      case TEXFMT_L8:
      {
          break;
      }
      case TEXFMT_R8UI:
      {
        block_size = 1;
        break;
      }
      case TEXFMT_DEPTH16:
      {
          block_size = 2;
          break;
      }
      case TEXFMT_DEPTH24:
      case TEXFMT_DEPTH32:
      {
          block_size = 4;
          break;
      }
      default:
          fatal("getStride unimplemented for format %i", fmt);
    }

    if (!is_copmressed)
    {
      widBytes = width * block_size;
      nBytes = widBytes * height;
    }
    else
    {
      width = max(width, 4);
      height = max(height, 4);

      widBytes = ((width + 3) / 4) * block_size;
      nBytes = ((width + 3) / 4)*((height + 3) / 4) * block_size;
    }
  }

  MTLSamplerAddressMode Texture::getAddressMode(int mode)
  {
    switch (mode)
    {
      case TEXADDR_WRAP:     return MTLSamplerAddressModeRepeat;
      case TEXADDR_MIRROR:   return MTLSamplerAddressModeMirrorRepeat;
      case TEXADDR_CLAMP:    return MTLSamplerAddressModeClampToEdge;
      case TEXADDR_MIRRORONCE: return MTLSamplerAddressModeMirrorClampToEdge;
#if !_TARGET_IOS
      case TEXADDR_BORDER:   return MTLSamplerAddressModeClampToBorderColor;
#else
      case TEXADDR_BORDER:   return MTLSamplerAddressModeClampToZero;
#endif
    }

    return MTLSamplerAddressModeRepeat;
  }

  bool Texture::isSameFormat(int cflg1, int cflg2)
  {
    if ((cflg1 & (TEXCF_SRGBREAD | TEXCF_SRGBWRITE)) == (cflg2 & (TEXCF_SRGBREAD | TEXCF_SRGBWRITE)) &&
       (cflg1 & TEXFMT_MASK) == (cflg2 & TEXFMT_MASK))
    {
      return true;
    }
    return false;
  }

  static void setTexName(id<MTLTexture> tex, const char* name)
  {
#if DAGOR_DBGLEVEL > 0
    if (tex)
      tex.label = [NSString stringWithFormat:@"%s %llu", name, render.frame];
#endif
  }

  Texture::ApiTexture::ApiTexture(Texture* base) : base(base)
  {
    MTLTextureDescriptor *pTexDesc = [MTLTextureDescriptor texture2DDescriptorWithPixelFormat : base->metal_format
          width : base->width
          height : base->height
          mipmapped : NO];

    if (base->metal_format == MTLPixelFormatDepth32Float ||
        base->metal_format == MTLPixelFormatDepth32Float_Stencil8)
    {
      pTexDesc.storageMode = MTLStorageModePrivate;
      pTexDesc.resourceOptions = MTLResourceStorageModePrivate;
      pTexDesc.usage = MTLTextureUsageShaderRead | MTLTextureUsageRenderTarget;
    }
    else if (base->cflg & TEXCF_UNORDERED)
    {
      pTexDesc.storageMode = MTLStorageModePrivate;
      pTexDesc.usage = MTLTextureUsageShaderRead | MTLTextureUsageRenderTarget | MTLTextureUsageShaderWrite;
    }
    else if (base->cflg & TEXCF_RTARGET)
    {
      pTexDesc.storageMode = MTLStorageModePrivate;
      pTexDesc.usage = MTLTextureUsageShaderRead | MTLTextureUsageRenderTarget;
    }

    if (base->use_upload_buffer && !(base->cflg & TEXCF_READABLE))
      pTexDesc.storageMode = MTLStorageModePrivate;

#if _TARGET_IOS || _TARGET_TVOS
    if (base->memoryless)
    {
      pTexDesc.storageMode = MTLStorageModeMemoryless;
      pTexDesc.resourceOptions = MTLResourceStorageModeMemoryless;
    }
    else
      pTexDesc.usage |= MTLTextureUsageShaderRead;
#endif

    if (base->metal_format == MTLPixelFormatDepth32Float_Stencil8 || base->metal_format != base->metal_rt_format)
      pTexDesc.usage |= MTLTextureUsagePixelFormatView;

    pTexDesc.mipmapLevelCount = base->mipLevels;
    pTexDesc.textureType = base->metal_type;

    if (base->type == RES3D_ARRTEX || base->type == RES3D_CUBEARRTEX)
    {
      pTexDesc.arrayLength = base->depth;
      pTexDesc.depth = 1;
    }
    else
    {
      pTexDesc.depth = base->depth;
    }

    pTexDesc.sampleCount = base->samples;

    texture = [render.device newTextureWithDescriptor : pTexDesc];
    setTexName(texture, base->getResName());

    sub_texture = texture;

    int slises = 1;
    if (base->type == RES3D_ARRTEX || base->type == RES3D_VOLTEX)
      slises = base->depth;
    else if (base->type == RES3D_CUBETEX)
      slises = 6;
    else if (base->type == RES3D_CUBEARRTEX)
      slises = 6 * base->depth;

    if (base->metal_format != base->metal_rt_format)
    {
      rt_texture = [texture newTextureViewWithPixelFormat : base->metal_rt_format
                                              textureType : base->metal_type
                                                   levels : NSMakeRange(0, base->mipLevels)
                                                   slices : NSMakeRange(0, slises)];

      setTexName(rt_texture, base->getResName());
    }
    else
    {
      rt_texture = texture;
    }

    if (base->metal_format == MTLPixelFormatDepth32Float_Stencil8 && !base->memoryless)
    {
      G_ASSERT(base->type != RES3D_ARRTEX && base->type != RES3D_CUBETEX && base->type != RES3D_CUBEARRTEX);
      stencil_read_texture = [texture newTextureViewWithPixelFormat : MTLPixelFormatX32_Stencil8
                                                        textureType : base->metal_type
                                                             levels : NSMakeRange(0, base->mipLevels)
                                                             slices : NSMakeRange(0, 1)];
    }

    for (int level = 0; level < base->mipLevels; ++level)
    {
      int row_pitch = 0, slice_pitch = 0;
      getStride(base->base_format, base->width, base->height, level, row_pitch, slice_pitch);
      texture_size += slice_pitch * slises;
    }

    SubMip sub_mip;

    sub_mip.minLevel = 0;
    sub_mip.maxLevel = base->mipLevels;
    sub_mip.tex = texture;

    sub_mip_textures.push_back(sub_mip);

    add_texture_to_list(this);
  }

  Texture::ApiTexture::ApiTexture(id<MTLTexture> tex, const char* name)
  {
    texture = tex;
    rt_texture = tex;
    sub_texture = texture;

    if (name)
      setTexName(texture, name);
  }

  void Texture::ApiTexture::release(bool immediate)
  {
    if (immediate)
    {
      if (rt_texture != texture)
        [rt_texture release];
      for (size_t i = 1; i < sub_mip_textures.size(); i++)
      {
        id<MTLTexture>& tex = sub_mip_textures[i].tex;
        [tex release];
      }
      sub_mip_textures.clear();

      if (texture)
        [texture release];
    }
    else
    {
      if (rt_texture != texture)
        render.queueTextureForDeletion(rt_texture);
      for (size_t i = 1; i < sub_mip_textures.size(); i++)
      {
        id<MTLTexture>& tex = sub_mip_textures[i].tex;
        render.queueTextureForDeletion(tex);
      }
      sub_mip_textures.clear();

      render.queueTextureForDeletion(texture);
    }

    if (base && !base->waiting2delete)
      TEXQL_ON_RELEASE(base);

    g_textures.lock();
    if (g_textures.isIndexValid(tid))
      g_textures.safeReleaseEntry(tid);
    g_textures.unlock();
    tid = drv3d_generic::BAD_HANDLE;

    delete this;
  }

  Texture::Texture(int w, int h, int l, int d, int tp, int flg, int fmt, const char* name, bool is_memoryless, bool alloc)
    : memoryless(is_memoryless)
  {
    setResName(name);

#if _TARGET_IOS | _TARGET_TVOS
    switch(fmt)
    {
      case TEXFMT_DXT1:
      case TEXFMT_DXT3:
      case TEXFMT_ATI1N:
            logerr("unsupported texture format %d is used for texture %s", fmt, getResName());
            fmt = TEXFMT_PVRTC4X;
            break;
      case TEXFMT_DXT5:
      case TEXFMT_ATI2N:
      case TEXFMT_BC6H:
      case TEXFMT_BC7:
            logerr("unsupported texture format %d is used for texture %s", fmt, getResName());
            fmt = TEXFMT_ASTC4;
            break;
    }
#endif

    cflg = flg;
    type = tp;

    width = w;
    height = h;

    if (fmt & TEXCF_SAMPLECOUNT_MASK)
    {
      memoryless = true;
      samples = get_sample_count(fmt);
    }

    if (l < 1)
    {
      mipLevels = getMaxLevels(width, height);
    }
    else
    {
      mipLevels = l;

      if (l > getMaxLevels(width, height))
      {
        mipLevels = getMaxLevels(width, height);
      }
    }

    depth = d;

    start_level = 0;

    cflg = flg | (fmt & TEXFMT_MASK);

    if (depth == 0)
    {
      depth = 1;
    }

    base_format = fmt;

    if (cflg & TEXCF_SRGBREAD)
    {
      metal_format = format2MetalsRGB(fmt);
    }
    else
    {
      metal_format = format2Metal(fmt);
    }

    if (cflg & TEXCF_SRGBWRITE)
    {
      metal_rt_format = format2MetalsRGB(fmt);
    }
    else
    {
      metal_rt_format = format2Metal(fmt);
    }

    lockFlags = 0;

    metal_type = samples == 1 ? MTLTextureType2D : MTLTextureType2DMultisample;

    if (type == RES3D_CUBETEX)
    {
      G_ASSERT(samples == 1);
      metal_type = MTLTextureTypeCube;
    }
    else
    if (type == RES3D_VOLTEX)
    {
      G_ASSERT(samples == 1);
      metal_type = MTLTextureType3D;
    }
    else
    if (type == RES3D_ARRTEX)
    {
      G_ASSERT(samples == 1);
      metal_type = MTLTextureType2DArray;
    }
#if !_TARGET_TVOS
    else
    if (type == RES3D_CUBEARRTEX)
    {
      G_ASSERT(samples == 1);
      metal_type = MTLTextureTypeCubeArray;
    }
#endif

    use_dxt = 0;

    if (base_format == TEXFMT_DXT1 || base_format == TEXFMT_DXT3 || base_format == TEXFMT_DXT5 ||
      base_format == TEXFMT_ATI1N || base_format == TEXFMT_ATI2N ||
      base_format == TEXFMT_BC6H || base_format == TEXFMT_BC7)
    {
      use_dxt = 1;
    }

    if (fmt == TEXFMT_PVRTC2X || fmt == TEXFMT_PVRTC2A ||
        fmt == TEXFMT_PVRTC4X || fmt == TEXFMT_PVRTC4A || (cflg & TEXCF_READABLE))
      use_upload_buffer = false;
    else
      use_upload_buffer = true;

#if !(_TARGET_IOS || _TARGET_TVOS)
    memoryless = false;
#endif

    waiting2delete = false;

    sampler_dirty = true;
    sampler = NULL;

    if (alloc)
      allocate();

    G_ASSERT(!(flg & TEXCF_CLEAR_ON_CREATE) || alloc);
    bool clearOnCreate = flg & TEXCF_CLEAR_ON_CREATE ||
                         (alloc && render.forceClearOnCreate && (fmt < TEXFMT_FIRST_DEPTH || fmt > TEXFMT_LAST_DEPTH));
    if (clearOnCreate)
    {
      G_ASSERT(fmt < TEXFMT_FIRST_DEPTH || fmt > TEXFMT_LAST_DEPTH);
      render.clearTexture(this);
    }
  }

  Texture::Texture(id<MTLTexture> tex, int fmt, const char* name)
  {
    waiting2delete = false;

    type = RES3D_TEX;
    cflg = 0;
    sampler_dirty = false;
    sampler = NULL;

    base_format = fmt;
    metal_format = Texture::format2Metal(fmt);
    metal_rt_format = Texture::format2Metal(fmt);

    setResName(name);

    apiTex = new ApiTexture(tex, name);
  }

  Texture::~Texture()
  {
  }

  void Texture::allocate()
  {
    G_ASSERT(apiTex == nullptr);
    apiTex = new ApiTexture(this);
    TEXQL_ON_ALLOC(this);
    if (start_level)
      setMinMipLevel(start_level);
  }

  int Texture::ressize() const
  {
    return apiTex ? apiTex->texture_size : 0;
  }

  void Texture::releaseTex(bool recreate_after)
  {
    G_ASSERT(lockFlags == 0); //locked?
    if (isStub())
      apiTex = NULL;
    if (apiTex != NULL)
    {
      apiTex->release(false);
      apiTex = NULL;
    }
  }

  void Texture::discardTex()
  {
    if (stubTexIdx >= 0)
    {
      RCAutoLock texLock;

      if (lockFlags & TEXLOCK_BUSY_WAITING_IN_QUEUE)
        return;

      releaseTex(true);
      apiTex = getStubTex()->apiTex;
    }
  }

  BaseTexture *Texture::makeTmpTexResCopy(int w, int h, int d, int l, bool staging_tex)
  {
    if (type != RES3D_ARRTEX && type != RES3D_VOLTEX && type != RES3D_CUBEARRTEX)
      d = 1;
    Texture *clonedTex = new Texture(w, h, l, d, type, cflg, (cflg & TEXFMT_MASK),
      String::mk_str_cat("tmp:", getTexName()), memoryless, false);
    if (!staging_tex)
      clonedTex->tidXored = tidXored, clonedTex->stubTexIdx = stubTexIdx;
    if (!clonedTex->allocateTex())
      del_d3dres(clonedTex);
    return clonedTex;
  }
  void Texture::replaceTexResObject(BaseTexture *&other_tex)
  {
    // swap important fields of TQL, can't delay this
    RCAutoLock texLock;

    Texture* other = getbasetex(other_tex);
    G_ASSERT_RETURN(other, );

    G_ASSERT(lockFlags == 0 && other->lockFlags == 0);
    lockFlags = other->lockFlags = TEXLOCK_BUSY_WAITING_IN_QUEUE;

    render.swapTextures(this, other_tex);
    other_tex = nullptr;
  }
  void Texture::replaceTexResObjectImpl(BaseTexture *&other_tex)
  {
    {
    RCAutoLock texLock;
    Texture* other = getbasetex(other_tex);
    G_ASSERT_RETURN(other, );

    // swap texture objects
    std::swap(apiTex, other->apiTex);
    std::swap(width, other->width);
    std::swap(height, other->height);
    std::swap(mipLevels, other->mipLevels);
    std::swap(depth, other->depth);
    std::swap(minMipLevel, other->minMipLevel);
    std::swap(maxMipLevel, other->maxMipLevel);
    if (apiTex && !tql::isTexStub(apiTex->base))
      apiTex->base = this;
    if (other->apiTex && !tql::isTexStub(other->apiTex->base))
      other->apiTex->base = other;

    G_ASSERT(lockFlags == TEXLOCK_BUSY_WAITING_IN_QUEUE && other->lockFlags == TEXLOCK_BUSY_WAITING_IN_QUEUE);
    lockFlags = other->lockFlags = 0;
    }
    del_d3dres(other_tex);
  }
  void Texture::waitSwapTexDone() const
  {
    if (is_main_thread())
      render.flush(false, false);
    else
      for (unsigned fe = dagor_frame_no()+120; (lockFlags & TEXLOCK_BUSY_WAITING_IN_QUEUE) && dagor_frame_no() < fe; )
        sleep_msec(1);
  }

  int Texture::getWidth()
  {
    return width;
  }

  int Texture::getHeight()
  {
    return height;
  }

  int Texture::getinfo(TextureInfo &ti, int level) const
  {
    ensureSwapTexDone();
    if (level >= mipLevels)
      level = mipLevels - 1;

    ti.w = max<uint32_t>(1u, width >> level);
    ti.h = max<uint32_t>(1u, height >> level);
    switch (type)
    {
      case RES3D_CUBETEX:    ti.d = 1; ti.a = 6; break;
      case RES3D_ARRTEX:     ti.d = 1; ti.a = depth; break;
      case RES3D_CUBEARRTEX: ti.d = 1; ti.a = 6*depth; break;
      case RES3D_VOLTEX:     ti.d = max<uint32_t>(1u, depth >> level); ti.a = 1; break;
      default:               ti.d = 1; ti.a = 1; break;
    }

    ti.mipLevels = mipLevels;
    ti.resType = type;
    ti.cflg = cflg;
    return 1;
  }

  int Texture::level_count() const
  {
    return mipLevels;
  }

  int Texture::texaddr(int addrmode)
  {
    return render.setTextureAddr(this, addrmode, addrmode, addrmode);
  }

  int Texture::texaddru(int addrmode)
  {
    return render.setTextureAddr(this, addrmode, -1, -1);
  };

  int Texture::texaddrv(int addrmode)
  {
    return render.setTextureAddr(this, -1, addrmode, -1);
  }

  int Texture::texaddrw(int addrmode)
  {
    return render.setTextureAddr(this, -1, -1, addrmode);
  }

  int Texture::texbordercolor(E3DCOLOR color)
  {
    return render.setTextureBorder(this, color);
  }

  int Texture::texfilter(int filtermode)
  {
    return render.setTextureFilter(this, filtermode);
  }

  int Texture::texmipmap(int mipmapmode)
  {
    return render.setTextureMipmapFilter(this, mipmapmode);
  }

  int Texture::texlod(float mipmaplod)
  {
    //sampler_state.lod = mipmaplod;
    //sampler_dirty = true;
    return 1;
  }

  int Texture::texmiplevel(int set_minlevel, int set_maxlevel)
  {
    set_minlevel = (set_minlevel >= 0) ? set_minlevel : 0;
    set_maxlevel = (set_maxlevel >= 0) ? set_maxlevel : mipLevels - 1;
    render.setTextureMipLevel(this, set_minlevel, set_maxlevel + 1);
    return 1;
  }

  int Texture::setAnisotropy(int level)
  {
#if _TARGET_IOS
    level = mipLevels > 1 ? level : 1;
#endif
    return render.setTextureAnisotropy(this, clamp(level, 1, 16));
  }

  void Texture::doSetAddressing(int u, int v, int w)
  {
    if (u > 0 && sampler_state.addrU != u)
      sampler_state.addrU = u, sampler_dirty = true;
    if (v > 0 && sampler_state.addrV != v)
      sampler_state.addrV = v, sampler_dirty = true;
    if (w > 0 && sampler_state.addrW != w)
      sampler_state.addrW = w, sampler_dirty = true;
  }

  void Texture::doSetBorder(E3DCOLOR color)
  {
    sampler_dirty |= color != sampler_state.border_color;
    sampler_state.border_color = color;
  }

  void Texture::doSetFilter(int filter, int mipfilter)
  {
    if (filter >= 0 && filter != sampler_state.texFilter)
      sampler_state.texFilter = filter, sampler_dirty = true;
    if (filter >= 0 && mipfilter != sampler_state.mipmap)
      sampler_state.mipmap = mipfilter, sampler_dirty = true;
  }

  void Texture::doSetAnisotropy(int level)
  {
    sampler_dirty |= level != sampler_state.anisotropy;
    sampler_state.anisotropy = level;
  }

  id<MTLTexture> Texture::ApiTexture::allocateOrCreateSubmip(int set_minlevel, int set_maxlevel)
  {
    G_ASSERT(base);
    for (auto & sub_mip : sub_mip_textures)
    {
      if (sub_mip.minLevel == set_minlevel &&
          sub_mip.maxLevel == set_maxlevel)
      {
        return sub_mip.tex;
      }
    }

    SubMip sub_mip;

    sub_mip.minLevel = set_minlevel;
    sub_mip.maxLevel = set_maxlevel;

    int slises = 1;

    if (base->type == RES3D_ARRTEX)
    {
      slises = base->depth;
    }

    if (base->type == RES3D_CUBETEX)
    {
      slises = 6;
    }

    if (base->type == RES3D_CUBEARRTEX)
    {
      slises = 6 * base->depth;
    }

    sub_mip.tex = [texture newTextureViewWithPixelFormat : base->metal_format
                                             textureType : base->metal_type
                                                  levels : NSMakeRange(set_minlevel, set_maxlevel - set_minlevel)
                                                  slices : NSMakeRange(0, slises)];

    if (base->getResName()[0])
    {
      setTexName(sub_mip.tex, base->getResName());
    }

    sub_mip_textures.push_back(sub_mip);

    return sub_mip.tex;
  }

  void Texture::setMiplevelImpl(int set_minlevel, int set_maxlevel)
  {
    G_ASSERT(apiTex);
    G_ASSERT(isStub() || apiTex->base == this);
    if (!isStub())
    {
      G_ASSERT(mipLevels >= 1);
      set_minlevel = min(set_minlevel, (int)mipLevels-1);
      set_maxlevel = min(set_maxlevel, (int)mipLevels);
      apiTex->sub_texture = apiTex->allocateOrCreateSubmip(set_minlevel, set_maxlevel);
    }
  }

  void Texture::applySampler(id<MTLSamplerState>& out_smp)
  {
    if (sampler_dirty)
    {
      sampler = NULL;

      for (int i = 0; i < states.size(); i++)
      {
        if (states[i] == sampler_state)
        {
          sampler = states[i].sampler;
          break;
        }
      }

      if (!sampler)
      {
        if (!samplerDescriptor)
        {
          samplerDescriptor = [[MTLSamplerDescriptor alloc] init];
        }

        samplerDescriptor.sAddressMode = getAddressMode(sampler_state.addrU);
        samplerDescriptor.tAddressMode = getAddressMode(sampler_state.addrV);
        samplerDescriptor.rAddressMode = getAddressMode(sampler_state.addrW);

        if (sampler_state.texFilter == TEXFILTER_POINT)
        {
          samplerDescriptor.minFilter = MTLSamplerMinMagFilterNearest;
          samplerDescriptor.magFilter = MTLSamplerMinMagFilterNearest;
        }
        else
        {
          samplerDescriptor.minFilter = MTLSamplerMinMagFilterLinear;
          samplerDescriptor.magFilter = MTLSamplerMinMagFilterLinear;
        }

        if (sampler_state.mipmap == TEXFILTER_POINT)
        {
          samplerDescriptor.mipFilter = MTLSamplerMipFilterNearest;
        }
        else
        {
          samplerDescriptor.mipFilter = MTLSamplerMipFilterLinear;
        }

        samplerDescriptor.lodMinClamp = 0;
        samplerDescriptor.lodMaxClamp = sampler_state.max_level;

        samplerDescriptor.maxAnisotropy = sampler_state.anisotropy;

  #if !_TARGET_IOS
        if (sampler_state.border_color.r > 0 ||
            sampler_state.border_color.g > 0 ||
            sampler_state.border_color.b > 0)
        {
          samplerDescriptor.borderColor = MTLSamplerBorderColorOpaqueWhite;
        }
        else
        {
          samplerDescriptor.borderColor = MTLSamplerBorderColorTransparentBlack;
        }
  #endif

        if (render.caps.samplerHaveCmprFun)
        {
          samplerDescriptor.compareFunction = MTLCompareFunctionLessEqual;
        }

        sampler = [render.device newSamplerStateWithDescriptor : samplerDescriptor];

        sampler_state.sampler = sampler;

        append_items(states, 1, &sampler_state);
      }

      sampler_dirty = false;
    }
    out_smp = sampler;
  }

  void Texture::apply(id<MTLTexture>& out_tex, bool is_read_stencil, int mip_level)
  {
    G_ASSERT(apiTex);
    G_ASSERT(isStub() || apiTex->base == this || apiTex->base == nullptr);
    auto tex = is_read_stencil && apiTex->stencil_read_texture ? apiTex->stencil_read_texture : apiTex->sub_texture;
    if (mip_level)
    {
      G_ASSERT(!(is_read_stencil && apiTex->stencil_read_texture));
      tex = apiTex->allocateOrCreateSubmip(mip_level, mip_level+1);
    }

    out_tex = tex;
  }

  int Texture::lockimg(void **data, int &row_pitch, int level, unsigned flags)
  {
    int slice_pitch = 0;
    void* d = lock(row_pitch, slice_pitch, level, 0, flags, !data);

    if (data)
    {
      *data = d;
    }

    return 1;
  }

  int Texture::lockimg(void **data, int &row_pitch, int face, int level, unsigned flags)
  {
    int slice_pitch = 0;
    void* d = lock(row_pitch, slice_pitch, level, face, flags, !data);

    if (data)
    {
      *data = d;
    }

    return 1;
  }

  int Texture::unlockimg()
  {
    unlock();
    return 1;
  }

  int Texture::lockbox(void **data, int &row_pitch, int &slice_pitch, int level, unsigned flags)
  {
    void* d = lock(row_pitch, slice_pitch, level, 0, flags, !data);

    if (data)
    {
      *data = d;
    }

    return 1;
  }

  int Texture::unlockbox()
  {
    unlock();
    return 1;
  }

  int Texture::generateMips()
  {
    if (mipLevels == 1)
    {
      return 1;
    }

    render.generateMips(this);
    return 1;
  }

  int Texture::calcBaseLevel(int w, int h)
  {
    int base_level = 0;

    int wdt = width;
    int hgt = height;

    while (wdt != w && hgt != h)
    {
      wdt = wdt >> 1;
      hgt = hgt >> 1;
      base_level++;
    }

    return base_level;
  }

  void Texture::setBaseLevel(int base_level)
  {
    if (start_level != base_level)
    {
      start_level = base_level;
      setMinMipLevel(start_level);
    }
  }

  void Texture::setMinMipLevel(int min_mip_level)
  {
    if (!isStub())
      setMiplevelImpl(min_mip_level, mipLevels);
  }

  void* Texture::lock(int &row_pitch, int &slice_pitch, int level, int face, unsigned flags, bool readback)
  {
    ensureSwapTexDone();
    G_ASSERT(!(lockFlags & TEXLOCK_BUSY_WAITING_IN_QUEUE));

    if (level >= mipLevels)
    {
      level = mipLevels - 1;
    }

    lockFlags = flags;

    getStride(base_format, width, height, level, row_pitch, slice_pitch);

    SysImage* sys_image = NULL;

    for (int i = 0; i < sys_images.size(); i++)
    {
      if (sys_images[i].lock_level == level &&
          sys_images[i].lock_face == face)
      {
        sys_image = &sys_images[i];
      }
    }

    bool force_readback = last_render_frame == render.frame;
    if (!sys_image)
    {
      sys_images.push_back(SysImage());

      sys_image = &sys_images.back();

      sys_image->lock_level = level;
      sys_image->lock_face = face;
      sys_image->widBytes = row_pitch;
      sys_image->nBytes = slice_pitch;

      int d = type == RES3D_VOLTEX ? max(depth >> sys_image->lock_level, 1) : 1;
      sys_image->guard_offest = sys_image->nBytes * d;

      if (((lockFlags & TEXLOCK_READ) || use_upload_buffer) && !(cflg & TEXCF_READABLE))
      {
        @autoreleasepool
        {
          sys_image->buffer = [render.device newBufferWithLength : slice_pitch * d options : MTLResourceStorageModeShared];
#if DAGOR_DBGLEVEL > 0
          sys_image->buffer.label = [NSString stringWithFormat:@"upload for %s %llu", getResName(), render.frame];
#endif
          sys_image->image = (char*)sys_image->buffer.contents;
        }
      }
      else
      {
        sys_image->image = (char*)malloc(sys_image->guard_offest + 4);

        for (int i = 0; i < 4; i++)
        {
          sys_image->image[sys_image->guard_offest + i] = 7 * i;
        }
      }

      if (base_format == TEXFMT_PVRTC2X || base_format == TEXFMT_PVRTC2A ||
          base_format == TEXFMT_PVRTC4X || base_format == TEXFMT_PVRTC4A)
      {
        sys_image->widBytes = 0;
        sys_image->nBytes = 0;
      }
      force_readback = true;
    }

    if ((lockFlags & TEXLOCK_READ) && !(cflg & TEXCF_READABLE))
    {
      G_ASSERT(!(lockFlags & TEXLOCK_UPDATEFROMSYSTEX) && !(lockFlags & TEXLOCK_SYSTEXLOCK)
               && !(lockFlags & TEXLOCK_DONOTUPDATEON9EXBYDEFAULT));
      render.aquareOwnerShip();
      if (readback || force_readback)
      {
        int mins = use_dxt ? 4 : 1;
        int w = max(width >> (sys_image->lock_level), mins);
        int h = max(height >> (sys_image->lock_level), mins);
        int d = max(depth >> sys_image->lock_level, 1);

        G_ASSERT(apiTex);
        render.readbackTexture(apiTex->texture, sys_image->lock_level, sys_image->lock_face, w, h, d,
          sys_image->buffer, 0, sys_image->widBytes, sys_image->nBytes);
        sys_image->frame = render.frame;
      }
      if (!readback && (render.frame - sys_image->frame < Render::MAX_FRAMES_TO_RENDER))
      {
        @autoreleasepool
        {
          render.flush(true);
        }
      }
      render.releaseOwnerShip();
    }

    return sys_image->image;
  }

  void Texture::unlock()
  {
    ensureSwapTexDone();
    G_ASSERT(!(lockFlags & TEXLOCK_BUSY_WAITING_IN_QUEUE));

    if (lockFlags == 0)
    {
      return;
    }

    if (lockFlags & TEXLOCK_DONOTUPDATEON9EXBYDEFAULT)
    {
      lockFlags = 0;
      return;
    }

    if (type == RES3D_ARRTEX && isStub())
    {
      if (sys_images.size() != mipLevels*depth)
      {
        lockFlags = 0;
        return;
      }
      apiTex = nullptr;
      allocate();
    }

    for (int i=0; i<sys_images.size();i++)
    {
      SysImage& sys_image = sys_images[i];

      if (!sys_image.buffer)
      {
        for (int j = 0; j < 4; j++)
        {
          if (sys_image.image[sys_image.guard_offest + j] != 7 * j)
          {
            fatal("Someone are corrupted temporary texture data");
          }
        }
      }

      if ((lockFlags & TEXLOCK_WRITE) || (lockFlags & TEXLOCK_UPDATEFROMSYSTEX))
      {
        int w = max(width >> (sys_image.lock_level), 1);
        int h = max(height >> (sys_image.lock_level), 1);
        int d = type == RES3D_VOLTEX ? max(depth >> sys_image.lock_level, 1) : 1;

        G_ASSERT(apiTex);
        if (sys_image.buffer)
        {
          render.uploadTexture(apiTex->texture, sys_image.lock_level, sys_image.lock_face, w, h, d,
                                 sys_image.buffer, sys_image.widBytes, sys_image.nBytes);
        }
        else
        {
          if (use_dxt)
          {
            w = max(w, 4);
            h = max(h, 4);
          }
          [apiTex->texture replaceRegion : MTLRegionMake3D(0, 0, 0, w, h, d)
                     mipmapLevel : sys_image.lock_level
                           slice : sys_image.lock_face
                       withBytes : sys_image.image
                     bytesPerRow : sys_image.widBytes
                   bytesPerImage : sys_image.nBytes];
        }
      }

      if (!(lockFlags & TEXLOCK_READ))
      {
        if (sys_image.buffer)
        {
          render.queueBufferForDeletion(sys_image.buffer);
          sys_image.buffer = nil;
        }
        else if (sys_image.image)
          free(sys_image.image);
        sys_image.image = nullptr;
      }
    }

    if (!(lockFlags & TEXLOCK_READ))
    {
      sys_images.clear();
    }

    lockFlags = 0;
  }

  int Texture::update(BaseTexture* src)
  {
    render.copyTex((Texture*)src, this);
    return 1;
  }

  int Texture::updateSubRegion(BaseTexture* src,
                          int src_subres_idx, int src_x, int src_y, int src_z, int src_w, int src_h, int src_d,
                          int dest_subres_idx, int dest_x, int dest_y, int dest_z)
  {
    ensureSwapTexDone();
    static_cast<Texture*>(src)->ensureSwapTexDone();
    G_ASSERT(!isStub());

    if (!validate_update_sub_region_params(src, src_subres_idx, src_x, src_y, src_z, src_w, src_h, src_d,
           this, dest_subres_idx, dest_x, dest_y, dest_z))
      return 0;

    render.copyTexRegion((Texture*)src, src_subres_idx, src_x, src_y, src_z, src_w, src_h, src_d,
                         this, dest_subres_idx, dest_x, dest_y, dest_z);
    return 1;
  }

  void Texture::destroy()
  {
    waiting2delete = true;
    TEXQL_ON_RELEASE(this);
    render.deleteTexture(this);
  }

  void Texture::release()
  {
    for (int i = 0; i<sys_images.size(); i++)
    {
      if (!sys_images[i].buffer)
        free(sys_images[i].image);
      else
        [sys_images[i].buffer release];
    }

    if (apiTex && !isStub())
      apiTex->release(true);
    apiTex = nullptr;

    delete this;
  }

  void Texture::cleanup()
  {
    Tab<Texture::ApiTexture*> textures;
    g_textures.lock();
    ITERATE_OVER_OBJECT_POOL(g_textures, textureNo)
      if (g_textures[textureNo].obj != NULL)
        textures.push_back(g_textures[textureNo].obj);
    ITERATE_OVER_OBJECT_POOL_RESTORE(g_textures);
    g_textures.unlock();
    for (int i = 0; i < textures.size(); ++i)
      textures[i]->release(true);
  }
}

#define FULL_TEX_STAT_LOG (DAGOR_DBGLEVEL > 0 || (_TARGET_64BIT && DAGOR_FORCE_LOGS))
struct MetalBtSortRec
{
  drv3d_metal::Texture *t;
  int szKb, lfu;

  MetalBtSortRec(drv3d_metal::Texture *_t): t(_t), szKb(tql::sizeInKb(_t->ressize())), lfu(tql::get_tex_lfu(_t->getTID())) {}
  drv3d_metal::Texture* operator->() { return t; }
};
static int sort_textures_by_size(const MetalBtSortRec *left, const MetalBtSortRec *right)
{
  if (int diff = left->szKb - right->szKb)
    return -diff;
  if (int diff = left->t->type - right->t->type)
    return diff;
  if (int diff = strcmp(left->t->getResName(), right->t->getResName()))
    return diff;
  return right->lfu - left->lfu;
}

static int get_ib_vb_mem_used(String *, int &){return 0;}

static const char *tex_mipfilter_string(uint32_t mipFilter)
{
  static const char* filterMode[5] =
  {
    "default", "point", "linear", "unknown"
  };
  return filterMode[min(mipFilter, (uint32_t)4)];
}
static const char *tex_filter_string(uint32_t filter)
{
  static const char* filterMode[6] =
  {
    "default", "point", "smooth", "best", "none", "unknown"
  };
  return filterMode[min(filter, (uint32_t)5)];
}

static const char* format2String(uint32_t fmt)
  {
    switch (fmt)
    {
      case TEXFMT_A8R8G8B8:     return "A8R8G8B8";
      case TEXFMT_A2R10G10B10:  return "A2R10G10B10";
      case TEXFMT_A2B10G10R10:  return "A2B10G10R10";
      case TEXFMT_A16B16G16R16:   return "A16B16G16R16";
      case TEXFMT_A16B16G16R16F:  return "A16B16G16R16F";
      case TEXFMT_A32B32G32R32F:  return "A32B32G32R32F";
      case TEXFMT_G16R16:     return "G16R16";
      case TEXFMT_G16R16F:    return "G16R16F";
      case TEXFMT_G32R32F:    return "G32R32F";
      case TEXFMT_R16F:       return "R16F";
      case TEXFMT_R32F:       return "R32F";
      case TEXFMT_DXT1:       return "DXT1";
      case TEXFMT_DXT3:       return "DXT3";
      case TEXFMT_DXT5:       return "DXT5";
      case TEXFMT_ATI1N:      return "ATI1N";
      case TEXFMT_ATI2N:      return "ATI2N";
      case TEXFMT_BC6H:       return "BC6H";
      case TEXFMT_BC7:      return "BC7";
      case TEXFMT_PVRTC2X:        return "PVRTC2X";
      case TEXFMT_PVRTC2A:        return "PVRTC2A";
      case TEXFMT_PVRTC4X:        return "PVRTC4X";
      case TEXFMT_PVRTC4A:        return "PVRTC4A";
      case TEXFMT_ASTC4:          return "ASTC4";
      case TEXFMT_ASTC8:          return "ASTC8";
      case TEXFMT_ASTC12:         return "ASTC12";
      case TEXFMT_R32G32UI: return "R32G32UI";
      case TEXFMT_L16:      return "L16";
      case TEXFMT_A8:       return "A8";
      case TEXFMT_L8:       return "L8";
      case TEXFMT_A1R5G5B5:  return "A1R5G5B5";
      case TEXFMT_A4R4G4B4:     return "A4R4G4B4";
      case TEXFMT_R5G6B5:     return "R5G6B5";
      case TEXFMT_A8L8:       return "A8L8";
      case TEXFMT_A16B16G16R16S:  return "A16B16G16R16S";
      case TEXFMT_A16B16G16R16UI: return "A16B16G16R16UI";
      case TEXFMT_A32B32G32R32UI: return "A32B32G32R32UI";
      case TEXFMT_R8G8B8A8:     return "R8G8B8A8";
      case TEXFMT_R32UI:      return "R32UI";
      case TEXFMT_R11G11B10F:   return "R11G11B10F";
      case TEXFMT_R8G8:       return "R8G8";
      case TEXFMT_R8G8S:      return "R8G8S";
      case TEXFMT_DEPTH24:    return "DEPTH24";
      case TEXFMT_DEPTH16:    return "DEPTH16";
      case TEXFMT_DEPTH32:    return "DEPTH32";
      case TEXFMT_DEPTH32_S8:   return "DEPTH32_S8";
    }

    return "Unknown";
  }

void d3d::get_texture_statistics(uint32_t *num_textures, uint64_t *total_mem, String *out_dump)
{
  g_textures.lock();

  int totalTextures = g_textures.totalUsed();
  if (num_textures)
    *num_textures = totalTextures;
  if (total_mem)
    *total_mem = 0;

  Tab<MetalBtSortRec> sortedTexturesList(tmpmem); sortedTexturesList.reserve(totalTextures);

  ITERATE_OVER_OBJECT_POOL(g_textures, textureNo)
    if (g_textures[textureNo].obj != NULL)
      sortedTexturesList.push_back(g_textures[textureNo].obj->base);
  ITERATE_OVER_OBJECT_POOL_RESTORE(g_textures);

  sort(sortedTexturesList, &sort_textures_by_size);

  uint64_t totalSize2d = 0;
  uint64_t totalSizeCube = 0;
  uint64_t totalSizeVol = 0;
  uint64_t totalSizeArr = 0;
  uint32_t numUnknownSize = 0;
  String tmpStor;
  for (unsigned int textureNo = 0; textureNo < sortedTexturesList.size(); textureNo++)
  {
    uint64_t sz = (uint64_t)sortedTexturesList[textureNo]->ressize();
    if (sz == 0)
    {
      numUnknownSize++;
    }
    else
    {
      if (sortedTexturesList[textureNo]->type == RES3D_TEX)
        totalSize2d += sz;
      else if (sortedTexturesList[textureNo]->type == RES3D_CUBETEX)
        totalSizeCube += sz;
      else if (sortedTexturesList[textureNo]->type == RES3D_VOLTEX)
        totalSizeVol += sz;
      else if (sortedTexturesList[textureNo]->type == RES3D_ARRTEX)
        totalSizeArr += sz;
    }
  }

  uint64_t texturesMem = totalSize2d + totalSizeCube + totalSizeVol + totalSizeArr;
  int vb_sysmem = 0;
#if FULL_TEX_STAT_LOG
  String vbibmem;
  uint64_t vb_ib_mem = get_ib_vb_mem_used(&vbibmem, vb_sysmem);
#else
  uint64_t vb_ib_mem = get_ib_vb_mem_used(NULL, vb_sysmem);
#endif

  if (total_mem)
    *total_mem = totalSize2d + totalSizeCube + totalSizeVol;

  if (out_dump)
  {
    *out_dump += String(200,
        "TOTAL: %dM\n"
        "%d textures: %dM (%llu), 2d: %dM (%llu), cube: %dM (%llu), vol: %dM (%llu), arr: %dM (%llu), %d stubs/unknown\n"
        "sysmem for drvReset: %dM (%dK)\n"
        "vb/ib mem: %dM\n",
        (vb_ib_mem >> 20) + texturesMem / 1024 / 1024,
        totalTextures,
        texturesMem / 1024 / 1024,
        texturesMem,
        totalSize2d / 1024 / 1024,
        totalSize2d,
        totalSizeCube / 1024 / 1024,
        totalSizeCube,
        totalSizeVol / 1024 / 1024,
        totalSizeVol,
        totalSizeArr / 1024 / 1024,
        totalSizeArr,
        numUnknownSize,
        vb_sysmem >> 20, vb_sysmem >> 10,
        vb_ib_mem >> 20);

    *out_dump += String(0, "\n");

#if FULL_TEX_STAT_LOG
    STAT_STR_BEGIN(add);
    for (unsigned int textureNo = 0; textureNo < sortedTexturesList.size(); textureNo++)
    {
      auto *tex = (drv3d_metal::Texture*)sortedTexturesList[textureNo].t;
      uint64_t sz = tql::sizeInKb(tex->ressize());
      int ql = tql::get_tex_cur_ql(tex->getTID());
      if (tex->type == RES3D_TEX)
      {
        add.printf(0, "%5dK q%d  2d  %4dx%-4d, m%2d, aniso=%-2d filter=%7s mip=%s, %s - '%s'",
            sz, ql,
            tex->width,
            tex->height,
            tex->mipLevels,
            tex->anisotropyLevel,
            tex_filter_string(tex->texFilter), tex_mipfilter_string(tex->mipFilter),
            format2String(tex->base_format),
            tex->getResName());
      }
      else if (tex->type == RES3D_CUBETEX)
      {
        add.printf(0, "%5dK q%d cube %4d, m%2d, %s - '%s'",
            sz, ql,
            tex->width,
            tex->mipLevels,
            format2String(tex->base_format),
            tex->getResName());
      }
      else
      {
        add.printf(0, "%5dK q%d  %s %4dx%-4dx%3d, m%2d, aniso=%-2d filter=%7s mip=%s, %s - '%s'",
            sz, ql, (tex->type == RES3D_VOLTEX) ? "vol" : ((tex->type == RES3D_ARRTEX) ? "arr" : " ? "),
            tex->width,
            tex->height,
            tex->depth,
            tex->mipLevels,
            tex->anisotropyLevel,
            tex_filter_string(tex->texFilter), tex_mipfilter_string(tex->mipFilter),
            format2String(tex->base_format),
            tex->getResName());
      }

      add += num_textures ? "\n" : String(0, "%s\n", tql::get_tex_info(tex->getTID(), false, tmpStor)).str();

      STAT_STR_APPEND(add, *out_dump);
    }
    STAT_STR_END(*out_dump);
    *out_dump += vbibmem;

    // get_shaders_mem_used(vbibmem);
    // *out_dump += vbibmem;
    // get_states_mem_used(vbibmem);
    // *out_dump += vbibmem;
#endif
  }

  g_textures.unlock();
}
