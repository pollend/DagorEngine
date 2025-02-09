#pragma once

#include "rayCar.h"
#include <gameRes/dag_gameResSystem.h>
#include <gameRes/dag_stdGameResId.h>
#include <render/dag_cur_view.h>

#ifndef NO_3D_GFX
#include <vehiclePhys/tireTracks.h>
#endif

class LegacyRenderableRayCar : public RayCar, public IPhysCarLegacyRender
{
public:
  LegacyRenderableRayCar(const char *car_name, SimplePhysObject *body_, const TMatrix &phys_to_logic_tm, const BBox3 &bbox_,
    const BSphere3 &bsphere_, bool simple_phys, bool /*allow_deform*/, const PhysCarSuspensionParams &frontSusp,
    const PhysCarSuspensionParams &rearSusp, DynamicRenderableSceneLodsResource *frontWm, DynamicRenderableSceneLodsResource *rearWm) :
    RayCar(car_name, body_->getBody(), phys_to_logic_tm, bbox_, bsphere_, simple_phys, frontSusp, rearSusp),
    body(body_),
    nodeTree(body_->getNodeTree())
  {
#ifndef NO_3D_GFX
    if (nodeTree)
      nodeMap.init(*nodeTree, body->getModel()->getLodsResource()->getNames().node);
    lighting.getDirLt().clear();
    lighting.getDirLt().shAmb[SPHHARM_00] = Color3(1, 1, 1) * 1;
    // lighting.getDirLt().sh[SPHHARM_1m1]=Color3(1,1,1)*.5f;

    TMatrix logicTm;
    getTm(logicTm);
    tmLogic2Render = inverse(logicTm) * body->getModel()->getNodeWtm(0);

    if (frontWm)
    {
      wheels[0].setupModel(frontWm);
      wheels[1].setupModel(frontWm);
    }
    if (frontWm || rearWm)
    {
      wheels[2].setupModel(rearWm ? rearWm : frontWm);
      wheels[3].setupModel(rearWm ? rearWm : frontWm);
    }

    if (!isSimpleCar)
      for (int i = 0; i < wheels.size(); i++)
        wheels[i].tireEmitter = tires0::create_emitter();

    if (vinyls_tex_var_id < 0)
      vinyls_tex_var_id = get_shader_variable_id("vinyl_tex", true);

    if (planar_vinyls_tex_var_id < 0)
      planar_vinyls_tex_var_id = get_shader_variable_id("planar_vinyl_tex", true);

    if (planar_norm_var_id < 0)
      planar_norm_var_id = get_shader_variable_id("planar_norm", true);
#endif
    recalcWtms();
  }
  virtual ~LegacyRenderableRayCar()
  {
    destroy_it(getLtCb);
#ifndef NO_3D_GFX
    for (int i = 0; i < wheels.size(); i++)
    {
      del_it(wheels[i].rendObj);

      if (wheels[i].tireEmitter)
        tires0::delete_emitter(wheels[i].tireEmitter);
    }
#endif
    del_it(body);
  }

  IPhysCarLegacyRender *getLegacyRender() override { return this; }
  void updateAfterSimulate(float dt, float at_time) override
  {
    RayCar::updateAfterSimulate(dt, at_time);
    if (carPhysMode == CPM_ACTIVE_PHYS)
      if (!idle)
        if (getLtCb)
          getLtCb->setPos(getPos());
  }
  void getLogicToRender(TMatrix &tm) const override { tm = tmLogic2Render; }
  void setTm(const TMatrix &tm) override
  {
    RayCar::setTm(tm);
    if (getLtCb)
      getLtCb->setPos(tm.getcol(3), true);
  }

#ifndef NO_3D_GFX
  bool getIsVisible() const override { return isVisible; }
  void setWheelsModel(const char *model_res_name) override
  {
    DynamicRenderableSceneLodsResource *model =
      (DynamicRenderableSceneLodsResource *)::get_game_resource_ex(GAMERES_HANDLE_FROM_STRING(model_res_name), DynModelGameResClassId);

    if (!model)
    {
      logerr_ctx("Wheels model '%s' was not found", model_res_name);
      return;
    }

    for (int i = 0; i < wheels.size(); ++i)
    {
      del_it(wheels[i].rendObj);
      wheels[i].rendObj = new DynamicRenderableSceneInstance(model);
      wheels[i].brakeId = wheels[i].rendObj->getNodeId("suspension");
    }

    release_game_resource((GameResource *)model);
  }
  void resetLastLodNo() override { lastLodNo = -1; }
  bool beforeRender() override
  {
    if (carPhysMode == CPM_DISABLED)
      return false;

    if (visibility_finder)
      isVisible = visibility_finder->isVisible(getBoundBox(), getBoundingSphere(), getVisibilityRange());
    else
      isVisible = true;

    if (!isVisible)
    {
      if (body && nodeTree)
      {
        TMatrix bodyTm = cachedTm * tmLogic2Render;
        nodeTree->setRootTmScalar(bodyTm);
        nodeTree->invalidateWtm();
        nodeTree->calcWtm();
      }
      return false;
    }

#ifndef NO_3D_GFX
    if (getLtCb)
    {
      lighting.getDirLt() = getLtCb->getLighting();
      if (lightingK != 1.0)
      {
        for (int i = 0; i < 4; i++)
          lighting.getDirLt().shAmb[i] *= lightingK;
        lighting.getDirLt().col1 *= lightingK;
        lighting.getDirLt().col2 *= lightingK;
      }
      // debug ("car1 %g %g %g", lighting.col1.r, lighting.col1.g, lighting.col1.b);
      // debug ("amb %g %g %g", lighting.shAmb[0].r, lighting.shAmb[0].g, lighting.shAmb[0].b);
    }
#endif

    setMatrices();
    return true;
  }
  void render(int parts_flags) override
  {
    if (!isVisible || !parts_flags)
      return;

    if (parts_flags & RP_DEBUG)
    {
#if DAGOR_DBGLEVEL > 0
      renderDebug();
#endif
      return;
    }

    if (parts_flags & RP_BODY)
    {
      if (vinylTexId != BAD_TEXTUREID)
        ShaderGlobal::set_texture(vinyls_tex_var_id, vinylTexId);
      if (planarVinylTexId != BAD_TEXTUREID)
        ShaderGlobal::set_texture(planar_vinyls_tex_var_id, planarVinylTexId);

      ShaderGlobal::set_color4(planar_norm_var_id, planarNorm);

      body->getModel()->render();

      if (vinylTexId != BAD_TEXTUREID)
        ShaderGlobal::set_texture(vinyls_tex_var_id, BAD_TEXTUREID);
      if (planarVinylTexId != BAD_TEXTUREID)
        ShaderGlobal::set_texture(planar_vinyls_tex_var_id, BAD_TEXTUREID);
    }

    if (parts_flags & RP_WHEELS)
    {
      if (lastLodNo < 1)
        for (int i = 0; i < wheels.size(); i++)
        {
          if (!wheels[i].rendObj)
            continue;
          if (wheels[i].visible)
            wheels[i].rendObj->render();
        }
    }
  }
  void renderTrans(int parts_flags) override
  {
    if (!isVisible || !parts_flags)
      return;

    if (parts_flags & RP_BODY)
      body->getModel()->renderTrans();

    if ((parts_flags & RP_WHEELS) && lastLodNo < 1)
      for (int i = 0; i < wheels.size(); i++)
        if (wheels[i].rendObj && wheels[i].visible)
          wheels[i].rendObj->renderTrans();
  }
  bool getRenderWtms(TMatrix &wtm_body, TMatrix *wtm_wheels) override
  {
    if (carPhysMode == CPM_DISABLED)
      return false;

    if (visibility_finder)
      isVisible = visibility_finder->isVisible(getBoundBox(), getBoundingSphere(), getVisibilityRange());
    else
      isVisible = true;

    if (!isVisible)
      return false;

    TMatrix &visualTm = externalDraw ? externalTm : cachedTm;

    wtm_body = visualTm * tmLogic2Render;
    for (int i = 0; i < wheels.size(); i++)
      calcWheelRenderTm(wtm_wheels[i], i, visualTm);
    return true;
  }
  DynamicRenderableSceneInstance *getModel() override { return body->getModel(); }
  DynamicRenderableSceneInstance *getWheelModel(int id) override
  {
    return (id >= 0 && id < wheels.size()) ? wheels[id].rendObj : nullptr;
  }

  void setLightingCb(ILightingCB *cb) override
  {
    destroy_it(getLtCb);
    getLtCb = cb;
  }
  ILightingCB *getLightingCb() const override { return getLtCb; }
  void setLightingK(real k) override { lightingK = k; }
  GeomNodeTree *getCarBodyNodeTree() const override { return nodeTree; }

  bool isVisibleInMainCamera() { return isVisible; }
  void getLighting(SH3Lighting &light_sh) const { light_sh = lighting.getSH3(); }
  void renderForShadow()
  {
    bool lastLod = true;
    if (!isVisible)
      setMatrices();
    if (lastLod)
      body->getModel()->setLod(body->getModel()->getLodsCount() - 1);
    body->getModel()->render();
    body->getModel()->renderTrans();

    if (lastLod)
      body->getModel()->setLod(-1);

    for (int i = 0; i < wheels.size(); i++)
    {
      if (!wheels[i].rendObj)
        continue;
      wheels[i].rendObj->render();
      wheels[i].rendObj->renderTrans();
    }
  }
#endif

private:
#ifndef NO_3D_GFX
  GeomTreeIdxMap nodeMap;
  SHUnifiedLighting lighting;
  TMatrix tmLogic2Render;
  int lastLodNo = -1;
  bool isVisible = false;

  ILightingCB *getLtCb = nullptr;
#endif
  SimplePhysObject *body = nullptr;
  GeomNodeTree *nodeTree = nullptr;
  real lightingK = 1;
  int vinyls_tex_var_id = -1, planar_vinyls_tex_var_id = -1, planar_norm_var_id = -1;

#ifndef NO_3D_GFX
  void beforeRenderGhost(const TMatrix &vtm)
  {
    DynamicRenderableSceneInstance *model = body->getModel();

    TMatrix bodyTm = vtm * tmLogic2Render;

    model->setNodeWtm(0, bodyTm);
    if (nodeTree)
    {
      nodeTree->setRootTmScalar(bodyTm);
      nodeTree->invalidateWtm();
      nodeTree->calcWtm();
      for (int i = 0; i < nodeMap.size(); i++)
        model->setNodeWtm(nodeMap[i].id, nodeTree->getNodeWtmRel(nodeMap[i].nodeIdx));
    }
    model->beforeRender(::grs_cur_view.pos);
    lastLodNo = model->getCurrentLodNo();

    for (int i = 0; i < wheels.size(); i++)
    {
      if (!wheels[i].rendObj)
        continue;
      setWheelRenderTm(i, vtm);
      wheels[i].rendObj->beforeRender(::grs_cur_view.pos);
    }
  }

  void setMatrices()
  {
    if (fakeShakeTm)
    {
      if (carPhysMode == CPM_ACTIVE_PHYS && fakeBodyEngineFeedbackAngle > 1e-3f)
      {
        *fakeShakeTm = cachedTm * tmLogic2Phys * rotzTM(-fakeBodyEngineFeedbackAngle);
        body->setExternalRenderBodyTmPtr(fakeShakeTm);
      }
      else
        body->setExternalRenderBodyTmPtr(NULL);
    }

    if (externalDraw)
      beforeRenderGhost(externalTm);
    else if (carPhysMode == CPM_GHOST)
      beforeRenderGhost(virtualCarTm);
    else
    {
      body->updateModelTms();
      body->getModel()->beforeRender(::grs_cur_view.pos);
    }

    lastLodNo = body->getModel()->getCurrentLodNo();

    if (carPhysMode == CPM_GHOST)
      return;

    // TMatrix visualTm;
    // getVisualTm(visualTm);
    TMatrix visualTm = externalDraw ? externalTm : cachedTm;

    for (int i = 0; i < wheels.size(); i++)
    {
      if (!wheels[i].rendObj)
        continue;
      setWheelRenderTm(i, visualTm);
      wheels[i].rendObj->beforeRender(::grs_cur_view.pos);
    }
  }
  float getVisibilityRange() const
  {
#ifndef NO_3D_GFX
    DynamicRenderableSceneInstance *rendObj = body->getModel();
    DynamicRenderableSceneLodsResource *lodsRes = rendObj->getLodsResource();
    return lodsRes->getMaxDist();
#else
    return -1;
#endif
  }

#endif
  void recalcWtms()
  {
    if (carPhysMode == CPM_DISABLED)
      return;

    calcCached();
#ifndef NO_3D_GFX
    if (externalDraw)
      beforeRenderGhost(externalTm);
    else if (carPhysMode != CPM_GHOST)
    {
      body->updateModelTms();
      body->getModel()->beforeRender(::grs_cur_view.pos);
    }
    else
      beforeRenderGhost(virtualCarTm);
#endif
  }
};
