-- This Source Code Form is subject to the terms of the bCDDL, v. 1.1.
-- If a copy of the bCDDL was not distributed with this
-- file, You can obtain one at http://beamng.com/bCDDL-1.1.txt

local M = {}
M.type = "auxilliary"
M.relevantDevice = nil
M.defaultOrder = 1200

local max = math.max
local min = math.min
local minSpeed = 55 / 3.6
local timer = 42

local function updateGFX(dt)
  if electrics.values.airspeed > minSpeed then
    electrics.values.bomblights = 1
  else
    electrics.values.bomblights = 0
  end
end

local function reset()
  electrics.values.bomblights = 0
  electrics.values.busbomb_d1 = 0
  electrics.values.busbomb_u1 = 0
  electrics.values.busbomb_u2 = 0
  electrics.values.busbomb_u3 = 0
  electrics.values.busbomb_u4 = 0
  electrics.values.busbomb_u5 = 0
  electrics.values.busbomb_u6 = 0
  electrics.values.busbomb_u7 = 0
  electrics.values.busbomb_u8 = 0
  electrics.values.busbomb_u9 = 0
  electrics.values.busbomb_u0 = 0
end

local function init(jbeamData)
  electrics.values.bomblights = 0
  electrics.values.busbomb_d1 = 0
  electrics.values.busbomb_u1 = 0
  electrics.values.busbomb_u2 = 0
  electrics.values.busbomb_u3 = 0
  electrics.values.busbomb_u4 = 0
  electrics.values.busbomb_u5 = 0
  electrics.values.busbomb_u6 = 0
  electrics.values.busbomb_u7 = 0
  electrics.values.busbomb_u8 = 0
  electrics.values.busbomb_u9 = 0
  electrics.values.busbomb_u0 = 0
end

local function setTimer(tim)
  timer = math.floor(tim)
  electrics.values.busbomb_d1 = (timer>= 10) and 1 or 0

  for i=0,9,1 do
    electrics.values["busbomb_u"..tostring(i)] = 0
  end

  electrics.values["busbomb_u"..tostring(timer%10)] = 1
end

M.init = init
M.reset = reset
M.updateGFX = updateGFX
M.setTimer = setTimer

return M