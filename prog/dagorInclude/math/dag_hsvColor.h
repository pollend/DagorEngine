//
// Dagor Engine 6.5
// Copyright (C) 2023  Gaijin Games KFT.  All rights reserved
// (for conditions of use see prog/license.txt)
//
#pragma once

#include "dag_color.h"
#include <algorithm>

struct HsvColor
{
public:
  float h; // [0..360]
  float s; // [0..1]
  float v; // [0..1]

  HsvColor() = default;
  explicit HsvColor(float h, float s, float v) : h(h), s(s), v(v) {}
  explicit HsvColor(const Color3 &rgb) { 
    float imax = std::max<float>(rgb.r, std::max<float>(rgb.g, rgb.b));
    float imin = std::min<float>(rgb.r, std::min<float>(rgb.g, rgb.b));
    h = 0;
    s = 0;
    v = imax;
    
    if (imax != 0)
    {
      s = (imax - imin) / imax;
    }

    if (s != 0)
    {
      float rc = (imax - rgb.r) / (imax - imin);
      float gc = (imax - rgb.g) / (imax - imin);
      float bc = (imax - rgb.b) / (imax - imin);
      if (rgb.r == imax) 
      {
        h = bc - gc;
      }
      else if (rgb.g == imax)
      {
        h = 2.0f + rc - bc;
      }
      else
      {
        h = 4.0f + gc - rc;
      }
      h *= 60.0f;
      if (h < 0.0) {
        h += 360.0f;
      }
    }
  }
  explicit HsvColor(const Color4 &rgba): HsvaColor(Color3(rgba.r,rgba.g,rgba.b)) { }

  Color3 toRGB() const
  {
    if (s == 0) 
    {
      return Color3(v,v,v);
    } 
    const float seg = fmodf(h, 360.0) / 60;
    const int i = static_cast<int>(seg);
    const double f = seg - i;
    const double p = v * (1.0 - s);
    const double q = v * (1.0 - (s * f));
    const double t = v * (1.0 - (s * (1.0 - f)));
    G_ASSERT(i >= 0 && i <= 5);
    switch (i)
    {
      case 0:
        return Color3(v,t,p);
      case 1:
        return Color3(q,v,p);
      case 2:
        return Color3(p,v,t);
      case 3:
        return Color3(p,q,v);
      case 4:
        return Color3(t,p,v);
      case 5:
        return Color3(v,p,q);
    }
    return Color3(0,0,0);
  }
};

struct HsvaColor
{
public:
  float h; // [0..360]
  float s; // [0..1]
  float v; // [0..1]
  float a; // [0..1]

  HsvaColor() = default;
  explicit HsvaColor(float h, float s, float v, float a) : h(h), s(s), v(v), a(a) {}
  explicit HsvaColor(const HsvColor &hsv, float a = 1) : h(hsv.h), s(hsv.s), v(hsv.v), a(a) {}
  explicit HsvaColor(const Color3 &rgb, float a = 1) : a(a)
  {
    HsvColor hsv(rgb);
    h = hsv.h;
    s = hsv.s;
    v = hsv.v;
  }
  HsvaColor(const Color4 &rgba)
  {
    HsvColor hsv(rgba);
    h = hsv.h;
    s = hsv.s;
    v = hsv.v;
    a = rgba.a;
  }

  Color4 toRGBA() const { return color4(HsvColor(h, s, v).toRGB(), a); }
};
