
include "shader_global.sh"

texture velocity_density_tex;
texture next_velocity_density_tex;

texture solid_boundaries_tex;

float simulation_time = 0;
float simulation_dt = 0;
float simulation_dx = 1;

float standard_density = 1.225;
float4 standard_velocity = float4(10, 10, 0, 0);

texture initial_velocity_density_tex;

int4 tex_size;

hlsl {
  float calc_P(float rho)
  {
    const float M = 0.0289644f; // molar mass of air
    const float R = 8.314462618f; // universal gas constant
    const float T = 300.0f; // temperature in Kelvin
    return rho * R * T / M;
  }

  #define x_ofs uint2(1, 0)
  #define y_ofs uint2(0, 1)

  struct ValueCross
  {
    float left;
    float right;
    float top;
    float bottom;
  };

  struct ValueCross4
  {
    float4 left;
    float4 right;
    float4 top;
    float4 bottom;
  };

  // Central difference derivative approximations
  inline float dval_dx(ValueCross val, float h)
  {
    return (val.right - val.left) / (2 * h);
  }
  inline float dval_dy(ValueCross val, float h)
  {
    return (val.bottom - val.top) / (2 * h);
  }
}

shader fill_initial_conditions
{
  ENABLE_ASSERT(cs)

  (cs) {
    velocity_density@uav = velocity_density_tex hlsl {
      RWTexture2D<float4> velocity_density@uav;
    };

    standard_density@f1 = (standard_density, 0, 0, 0);
    standard_velocity@f2 = (standard_velocity.x, standard_velocity.y, 0, 0);

    texSize@i2 = (tex_size.x, tex_size.y, 0, 0);
  }

  hlsl(cs) {
    [numthreads(8, 8, 1)]
    void cs_main(uint3 tid : SV_DispatchThreadID)
    {
      uint2 size = texSize;
      if (tid.x >= size.x || tid.y >= size.y)
        return;

      uint2 coord = uint2(tid.x, tid.y);

      velocity_density[coord] = float4(standard_velocity, 0, standard_density);
    }
  }

  compile("cs_5_0", "cs_main")
}

shader fill_initial_conditions_from_tex
{
  ENABLE_ASSERT(cs)

  (cs) {
    velocity_density@uav = velocity_density_tex hlsl {
      RWTexture2D<float4> velocity_density@uav;
    };

    initial_velocity_density@smp2d = initial_velocity_density_tex;

    texSize@i2 = (tex_size.x, tex_size.y, 0, 0);
  }

  hlsl(cs) {
    [numthreads(8, 8, 1)]
    void cs_main(uint3 tid : SV_DispatchThreadID)
    {
      uint2 size = texSize;
      if (tid.x >= size.x || tid.y >= size.y)
        return;

      uint2 coord = uint2(tid.x, tid.y);

      velocity_density[coord] = tex2Dlod(initial_velocity_density, float4(float2(coord) / float2(size), 0, 0));
    }
  }

  compile("cs_5_0", "cs_main")
}

shader euler_simulation_cs
{
  ENABLE_ASSERT(cs)

  (cs) {
    tex_size@i2 = (tex_size.x, tex_size.y, 0, 0);

    simulation_time@f1 = (simulation_time, 0, 0, 0);
    dt@f1 = (simulation_dt, 0, 0, 0);
    h@f1 = (simulation_dx, 0, 0, 0);

    standard_density@f1 = (standard_density, 0, 0, 0);
    standard_velocity@f2 = (standard_velocity.x, standard_velocity.y, 0, 0);

    velocity_density@smp2d = velocity_density_tex;
    next_velocity_density@uav = next_velocity_density_tex hlsl {
      RWTexture2D<float4> next_velocity_density@uav;
    };

    solidBoundaries@smp2d = solid_boundaries_tex;
  }

  hlsl(cs) {
    float2 frictionForce(uint2 coord, float2 v)
    {
      float boundaryData = tex2Dlod(solidBoundaries, float4(float2(coord) / float2(tex_size), 0, 0)).w;

      if (boundaryData > 0)
        return -v * 10000.0;

      return 0;
    }

    void solver(uint2 coord, float t)
    {
      float4 nextVelDensity = 0;

      float4 velDensity = texelFetch(velocity_density, coord, 0);
      float rho = velDensity.w;
      float v_x = velDensity.x;
      float v_y = velDensity.y;

      ValueCross4 velDensityCross =
      {
        texelFetch(velocity_density, coord - x_ofs, 0),
        texelFetch(velocity_density, coord + x_ofs, 0),
        texelFetch(velocity_density, coord - y_ofs, 0),
        texelFetch(velocity_density, coord + y_ofs, 0)
      };

      // Boundary conditions are set through derivatives
      ValueCross rhoCross =
      {
        coord.x != 0 ? velDensityCross.left.w : standard_density,
        coord.x != tex_size.x - 1 ? velDensityCross.right.w : standard_density,
        coord.y != 0 ? velDensityCross.top.w : standard_density,
        coord.y != tex_size.y - 1 ? velDensityCross.bottom.w : standard_density
      };
      ValueCross v_xCross =
      {
        coord.x != 0 ? velDensityCross.left.x : standard_velocity.x,
        coord.x != tex_size.x - 1 ? velDensityCross.right.x : standard_velocity.x,
        coord.y != 0 ? velDensityCross.top.x : standard_velocity.x,
        coord.y != tex_size.y - 1 ? velDensityCross.bottom.x : standard_velocity.x
      };
      ValueCross v_yCross =
      {
        coord.x != 0 ? velDensityCross.left.y : standard_velocity.y,
        coord.x != tex_size.x - 1 ? velDensityCross.right.y : standard_velocity.y,
        coord.y != 0 ? velDensityCross.top.y : standard_velocity.y,
        coord.y != tex_size.y - 1 ? velDensityCross.bottom.y : standard_velocity.y
      };
      ValueCross PCross =
      {
        calc_P(rhoCross.left),
        calc_P(rhoCross.right),
        calc_P(rhoCross.top),
        calc_P(rhoCross.bottom)
      };

      float dvx_dx_dvy_dy = (dval_dx(v_xCross, h) + dval_dy(v_yCross, h));

      // calculate rho
      nextVelDensity.w = rho + dt * (0 - rho * dvx_dx_dvy_dy - v_x * dval_dx(rhoCross, h) - v_y * dval_dy(rhoCross, h));
      nextVelDensity.w = max(0, nextVelDensity.w);

      // calculate v
      float2 force = frictionForce(coord, float2(v_x, v_y));
      nextVelDensity.x = v_x + dt * ((force.x - dval_dx(PCross, h)) / (rho + 0.0001) - v_x * dval_dx(v_xCross, h) - v_y * dval_dy(v_xCross, h));
      nextVelDensity.y = v_y + dt * ((force.y - dval_dy(PCross, h)) / (rho + 0.0001) - v_x * dval_dx(v_yCross, h) - v_y * dval_dy(v_yCross, h));

      next_velocity_density[coord] = nextVelDensity;
    }

    [numthreads(8, 8, 1)]
    void cs_main(uint3 tid : SV_DispatchThreadID)
    {
      if (tid.x >= tex_size.x || tid.y >= tex_size.y)
        return;

      solver(tid.xy, simulation_time);
    }
  }
  compile("cs_5_0", "cs_main")
}

int euler_cascade_no = 0;
interval euler_cascade_no: c128<1, c256<2, c512;

int euler_implicit_mode = 0;
interval euler_implicit_mode: hor<1, vert;

shader euler_simulation_explicit_implicit_cs
{
  ENABLE_ASSERT(cs)

  (cs) {
    tex_size@i2 = (tex_size.x, tex_size.y, 0, 0);

    simulation_time@f1 = (simulation_time, 0, 0, 0);
    dt@f1 = (simulation_dt, 0, 0, 0);
    h@f1 = (simulation_dx, 0, 0, 0);

    standard_density@f1 = (standard_density, 0, 0, 0);
    standard_velocity@f2 = (standard_velocity.x, standard_velocity.y, 0, 0);

    velocity_density@smp2d = velocity_density_tex;
    next_velocity_density@uav = next_velocity_density_tex hlsl {
      RWTexture2D<float4> next_velocity_density@uav;
    };

    solidBoundaries@smp2d = solid_boundaries_tex;
  }

  hlsl(cs) {

    //#define ROW_SIZE 512
    #define ROW_SIZE 64

    groupshared float equation[ROW_SIZE];
    groupshared float rightPart[3][ROW_SIZE];
    groupshared float solution[3][ROW_SIZE];

    float2 frictionForce(uint2 coord, float2 v)
    {
      float boundaryData = tex2Dlod(solidBoundaries, float4(float2(coord) / float2(tex_size), 0, 0)).w;

      if (boundaryData > 0)
        return -v * 10000.0;

      return 0;
    }

    void solver(uint2 coord, float t)
    {
      float4 nextVelDensity = 0;

      float4 velDensity = texelFetch(velocity_density, coord, 0);
      float rho = velDensity.w;
      float v_x = velDensity.x;
      float v_y = velDensity.y;

      ValueCross4 velDensityCross =
      {
        texelFetch(velocity_density, coord - x_ofs, 0),
        texelFetch(velocity_density, coord + x_ofs, 0),
        texelFetch(velocity_density, coord - y_ofs, 0),
        texelFetch(velocity_density, coord + y_ofs, 0)
      };

      // Boundary conditions are set through derivatives
      ValueCross rhoCross =
      {
        coord.x != 0 ? velDensityCross.left.w : standard_density,
        coord.x != tex_size.x - 1 ? velDensityCross.right.w : standard_density,
        coord.y != 0 ? velDensityCross.top.w : standard_density,
        coord.y != tex_size.y - 1 ? velDensityCross.bottom.w : standard_density
      };
      ValueCross v_xCross =
      {
        coord.x != 0 ? velDensityCross.left.x : standard_velocity.x,
        coord.x != tex_size.x - 1 ? velDensityCross.right.x : standard_velocity.x,
        coord.y != 0 ? velDensityCross.top.x : standard_velocity.x,
        coord.y != tex_size.y - 1 ? velDensityCross.bottom.x : standard_velocity.x
      };
      ValueCross v_yCross =
      {
        coord.x != 0 ? velDensityCross.left.y : standard_velocity.y,
        coord.x != tex_size.x - 1 ? velDensityCross.right.y : standard_velocity.y,
        coord.y != 0 ? velDensityCross.top.y : standard_velocity.y,
        coord.y != tex_size.y - 1 ? velDensityCross.bottom.y : standard_velocity.y
      };
      ValueCross PCross =
      {
        calc_P(rhoCross.left),
        calc_P(rhoCross.right),
        calc_P(rhoCross.top),
        calc_P(rhoCross.bottom)
      };

      float dvx_dx_dvy_dy = (dval_dx(v_xCross, h) + dval_dy(v_yCross, h));

      float2 force = frictionForce(coord, float2(v_x, v_y));

      ##if euler_implicit_mode == hor
        uint threadCoord = coord.x % ROW_SIZE;
      ##else
        uint threadCoord = coord.y % ROW_SIZE;
      ##endif

      // on scheme borders we use explicit method for calculations, inside - implicit calculations
      float2 derivWeights = (threadCoord == 0 || threadCoord == ROW_SIZE-1) ? float2(0, 1) : float2(0.25, 0.5);

      ##if euler_implicit_mode == hor // impliicit fox x derivative
        // v
        rightPart[0][threadCoord] = v_x / dt - v_y * dval_dx(v_xCross, h) + (force.x - dval_dx(PCross, h)) / (rho + 0.0001) - derivWeights.y * v_x * dval_dx(v_xCross, h);
        rightPart[1][threadCoord] = v_y / dt - v_y * dval_dx(v_yCross, h) + (force.y - dval_dy(PCross, h)) / (rho + 0.0001) - derivWeights.y * v_x * dval_dx(v_yCross, h);
        // rho
        rightPart[2][threadCoord] = rho * (1.0f / dt - dvx_dx_dvy_dy) - v_y * dval_dy(rhoCross, h) - derivWeights.y * v_x * dval_dx(rhoCross, h);

        // equation params (we need only one value of 3 per matrix row)
        // and for all v_x, v_y and rho equation is the same!
        equation[threadCoord] = - derivWeights.x * v_x / h;
      ##else                          // impliicit fox y derivavtive
        // v
        rightPart[0][threadCoord] = v_x / dt - v_x * dval_dx(v_xCross, h) + (force.x - dval_dx(PCross, h)) / (rho + 0.0001) - derivWeights.y * v_y * dval_dx(v_xCross, h);
        rightPart[1][threadCoord] = v_y / dt - v_x * dval_dx(v_yCross, h) + (force.y - dval_dy(PCross, h)) / (rho + 0.0001) - derivWeights.y * v_y * dval_dx(v_yCross, h);
        // rho
        rightPart[2][threadCoord] = rho * (1.0f / dt - dvx_dx_dvy_dy) - v_x * dval_dx(rhoCross, h) - derivWeights.y * v_y * dval_dy(rhoCross, h);

        // equation params (we need only one value of 3 per matrix row)
        // and for all v_x, v_y and rho equation is the same!
        equation[threadCoord] = - derivWeights.x * v_y / h;
      ##endif

      GroupMemoryBarrierWithGroupSync();

      // sweep method
      // https://pro-prof.com/forums/topic/sweep-method-for-solving-systems-of-linear-algebraic-equations
      if (threadCoord <= 2) // 0 for v_x, 1 for v_y, 2 for rho
      {
        derivWeights =  float2(0.25, 0.5);

        float equation_y = 1.0f / dt;

        float gamma;

        float alpha[ROW_SIZE];
        float beta[ROW_SIZE];

        gamma = equation_y;
        alpha[0] = equation[0] / gamma;
        beta[0] = rightPart[threadCoord][0] / gamma;

        // forward sweep
        for (int i = 1; i< ROW_SIZE; i++)
        {
          gamma = equation_y + equation[i] * alpha[i - 1];
          alpha[i] = equation[i] / gamma;
          beta[i] = (rightPart[threadCoord][i] - equation[i] * beta[i-1]) / gamma;
        }

        int j = ROW_SIZE - 1;
        solution[threadCoord][j] = beta[j];

        // back sweep
        for (int k = ROW_SIZE - 2; k >= 0; k--)
        {
          solution[threadCoord][k] = alpha[k] * solution[threadCoord][k+1] + beta[k];
        }
      }
      GroupMemoryBarrierWithGroupSync();

      nextVelDensity.x = solution[0][threadCoord];
      nextVelDensity.y = solution[1][threadCoord];
      nextVelDensity.w = solution[2][threadCoord];

      next_velocity_density[coord] = nextVelDensity;
    }

  ##if euler_implicit_mode == hor
    [numthreads(ROW_SIZE, 1, 1)]
  ##else
    [numthreads(1, ROW_SIZE, 1)]
  ##endif
    void cs_main(uint3 tid : SV_DispatchThreadID)
    {

      solver(tid.xy, simulation_time);
    }
  }
  compile("cs_5_0", "cs_main")
}


float euler_centralBlurWeight = 1000.0;

// Blurs the solution textures to avoid aliasing caused by the derivative approximations
// TODO: fix this issue inside solver
shader blur_result_cs
{
  ENABLE_ASSERT(cs)

  (cs) {
    tex_size@i2 = (tex_size.x, tex_size.y, 0, 0);
    simulation_time@f1 = (simulation_time, 0, 0, 0)
    blurWeights@f2 = (euler_centralBlurWeight, 1.0/(euler_centralBlurWeight + 4.0), 0, 0);
    velocity_density@smp2d = velocity_density_tex;
    next_velocity_density@uav = next_velocity_density_tex hlsl {
      RWTexture2D<float4> next_velocity_density@uav;
    };

    standard_density@f1 = (standard_density, 0, 0, 0);
    standard_velocity@f2 = (standard_velocity.x, standard_velocity.y, 0, 0);
  }

  hlsl(cs) {
    void blurer(int2 coord, float t)
    {
      float4 blurredVelDensity = 0;

      float4 velDensityCenter = texelFetch(velocity_density, coord, 0);
      float4 velDensityLeft = coord.x != 0 ? texelFetch(velocity_density, coord - x_ofs, 0) : float4(standard_velocity, 0, standard_density);
      float4 velDensityRight = coord.x != tex_size.x - 1 ? texelFetch(velocity_density, coord + x_ofs, 0) : float4(standard_velocity, 0, standard_density);
      float4 velDensityTop = coord.y != 0 ? texelFetch(velocity_density, coord - y_ofs, 0) : float4(standard_velocity, 0, standard_density);
      float4 velDensityBottom = coord.y != tex_size.y - 1 ? texelFetch(velocity_density, coord + y_ofs, 0) : float4(standard_velocity, 0, standard_density);

      float v_x = blurWeights.y*(blurWeights.x*velDensityCenter.x + velDensityRight.x +
                                                                  + velDensityLeft.x +
                                                                  + velDensityBottom.x +
                                                                  + velDensityTop.x);
      float v_y = blurWeights.y*(blurWeights.x*velDensityCenter.y + velDensityRight.y +
                                                                  + velDensityLeft.y +
                                                                  + velDensityBottom.y +
                                                                  + velDensityTop.y);

      float blurredDensity = 0.001f*(996*velDensityCenter.w + velDensityRight.w +
                                                            + velDensityLeft.w +
                                                            + velDensityBottom.w +
                                                            + velDensityTop.w);
      blurredVelDensity = float4(v_x, v_y, 0, blurredDensity);

      next_velocity_density[coord] = blurredVelDensity;
    }

    [numthreads(8, 8, 1)]
    void cs_main(uint3 tid : SV_DispatchThreadID)
    {
      if (tid.x >= tex_size.x || tid.y >= tex_size.y)
        return;

      blurer(tid.xy, simulation_time);
    }
  }
  compile("cs_5_0", "cs_main")
}