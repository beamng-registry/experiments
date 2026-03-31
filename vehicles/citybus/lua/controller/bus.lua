-- This Source Code Form is subject to the terms of the bCDDL, v. 1.1.
-- If a copy of the bCDDL was not distributed with this
-- file, You can obtain one at http://beamng.com/bCDDL-1.1.txt

local M = {}

local abs = math.abs
local min = math.min
local max = math.max

local logTag = "bus"
local doorsClosedDelayTime = 0.25

M.type = "auxilliary"
M.relevantDevice = nil
M.defaultOrder = 1000

M.doorsOpen = false
M.doorsClosedDelay = 0
M.frontDoorsMaxPressure = 0
M.rearDoorsMaxPressure = 0
M.isKneeling = false
M.isSupensionRaised = false
M.defaultSuspensionTargetHeight = 0

local doorController = nil
local suspensionController = nil

local hasSafetyInterlock = false
local kneelHeightReduction = 0
local maxRideHeightIncrease = 0
local wheelspeed = 0
local doorLever = 0
local doorLeverSmoother = nil

local hasRegisteredQuickAccess = false

local htmlTexture = require("htmlTexture")
local destScreenName = nil
local destHtmlPath = nil
local NSdisplayScreenName = nil
local NSHtmlPath = nil

local currentLine = {}
local timer = 0
local curWaypoint = 1
local lastApproach = -1

local function toggleDoors()
  if wheelspeed > 2 and hasSafetyInterlock then
    return
  end

  if doorLever > 0 then
    doorLever = 0
  else
    doorLever = 1
  end

  controller.getControllerSafe("doors").toggleBeamGroupsValveState({"frontDoors", "rearDoors"})
end

local function maxRideHeight()
  if M.defaultSuspensionTargetHeight <= 0 then
    return
  end -- Don't know target height (yet); can't do anything

  local airSuspension = controller.getControllerSafe("airSuspension")

  airSuspension.setTargetLength({"leftAxle", "rightAxle"}, M.defaultSuspensionTargetHeight + maxRideHeightIncrease, true)
end

local function normalRideHeight()
  if M.defaultSuspensionTargetHeight <= 0 then
    return
  end -- Don't know target height (yet); can't do anything

  local airSuspension = controller.getControllerSafe("airSuspension")

  airSuspension.setTargetLength({"leftAxle", "rightAxle"}, M.defaultSuspensionTargetHeight, true)
end

local function kneel()
  if M.defaultSuspensionTargetHeight <= 0 then
    return
  end -- Don't know target height (yet); can't do anything

  if wheelspeed >= 2 and hasSafetyInterlock then
    return
  end

  -- Change cross-flow configuration so the right side is detached from the left
  local airbags = controller.getControllerSafe("airbags")

  airbags.setBeamGroupCrossFlowTag("rightAxle", "rightSideKneeling")

  -- Change target heights for kneeling
  local airSuspension = controller.getControllerSafe("airSuspension")

  airSuspension.setTargetLength("leftAxle", M.defaultSuspensionTargetHeight, true)
  airSuspension.setTargetLength("rightAxle", M.defaultSuspensionTargetHeight - kneelHeightReduction, true)
end

local function toggleKneel()
  if M.isKneeling then
    normalRideHeight()
  else
    kneel()
  end
end

local function geCallback(event, data)
  data.event = event
  --transform userdata into table
  data.pos = vec3(obj:getPosition()):toTable()
  data.rot = quat(obj:getRotation()):toTable()
  --obj:queueGameEngineLua("if core_busRouteManager then core_busRouteManager.onBusUpdate(" .. dumps(data) .. ") end")
  obj:queueGameEngineLua("extensions.hook('onBusUpdate'," .. dumps(data) .. ")")
end

local function updateGFX(dt)
  if doorController then
    local frontDoorsPressure = doorController.getAveragePressure("frontDoors")
    local rearDoorsPressure = doorController.getAveragePressure("frontDoors")

    M.frontDoorsMaxPressure = max(M.frontDoorsMaxPressure, frontDoorsPressure)
    M.rearDoorsMaxPressure = max(M.rearDoorsMaxPressure, rearDoorsPressure)

    local frontDoorsMoving = abs(doorController.getAverageFlowRate("frontDoors")) > 1e-4
    local rearDoorsMoving = abs(doorController.getAverageFlowRate("rearDoors")) > 1e-4

    -- If the doors are moving or at less than 85% of their maximum pressure, count them as open
    local frontDoorOpen = frontDoorsPressure < M.frontDoorsMaxPressure * 0.85 or frontDoorsMoving
    local rearDoorOpen = rearDoorsPressure < M.rearDoorsMaxPressure * 0.85 or rearDoorsMoving
    local doorsOpen = frontDoorOpen or rearDoorOpen

    M.doorsOpen = doorsOpen or M.doorsClosedDelay > 0

    if doorsOpen then
      M.doorsClosedDelay = doorsClosedDelayTime
    else
      M.doorsClosedDelay = max(0, M.doorsClosedDelay - dt)
    end
  end

  if suspensionController and not suspensionController.isCalibrating("leftAxle") and not suspensionController.isCalibrating("rightAxle") then
    if M.defaultSuspensionTargetHeight <= 0 then
      -- Suspension got calibrated; learn its new default target height
      M.defaultSuspensionTargetHeight = (suspensionController.getTargetLength("leftAxle") + suspensionController.getTargetLength("rightAxle")) / 2
    end

    local leftAxleTargetHeight = suspensionController.getTargetLength("leftAxle")
    local rightAxleTargetHeight = suspensionController.getTargetLength("rightAxle")
    local rightAxleHeight = suspensionController.getCurrentLength("rightAxle")

    if rightAxleTargetHeight < M.defaultSuspensionTargetHeight - kneelHeightReduction * 0.5 then
      -- target height was reduced; we must be kneeling
      M.isKneeling = true
    elseif rightAxleHeight >= M.defaultSuspensionTargetHeight - kneelHeightReduction * 0.5 then
      -- actual height is less than 15% of kneelHeightReduction below normal height; we stopped kneeling

      if M.isKneeling then
        -- When raising from the kneeling position, we need to re-connect the right side to the left side so they cross flow again
        local airbags = controller.getControllerSafe("airbags")

        airbags.setBeamGroupCrossFlowTag("rightAxle", "common")
      end

      M.isKneeling = false
    end

    if max(leftAxleTargetHeight, rightAxleTargetHeight) > M.defaultSuspensionTargetHeight + maxRideHeightIncrease * 0.5 then
      -- target height was increased; we must have raised the suspension
      M.isSupensionRaised = true
    elseif max(leftAxleTargetHeight, rightAxleTargetHeight) <= M.defaultSuspensionTargetHeight + maxRideHeightIncrease * 0.15 then
      -- actual height is less than 15% of maxRideHeightIncrease above normal height; we stopped raising suspension
      M.isSupensionRaised = false
    end

    if M.isKneeling then
      -- while kneeling, left side is frozen in-place and right side is auto-levelling.
      -- left side needs to return to normal height before being disabled, though (if it was raised)
      suspensionController.setTemporarilyDisabled("leftAxle", not M.isSupensionRaised)
      suspensionController.setTemporarilyDisabled("rightAxle", false)
    else
      -- while not kneeling, right side control is disabled. left side is auto-levelling, and the
      -- cross-flow between left and right keeps the right side level.
      suspensionController.setTemporarilyDisabled("leftAxle", false)
      suspensionController.setTemporarilyDisabled("rightAxle", true)
    end
  end

  wheelspeed = electrics.values.wheelspeed or 0

  if (M.doorsOpen or M.isKneeling) and wheelspeed < 2 and hasSafetyInterlock then
    electrics.values.throttle = min(0.15, electrics.values.throttle or 0)
    electrics.values.brake = 1
  end

  electrics.values.dooropen = M.doorsOpen and 1 or 0
  electrics.values.kneel = M.isKneeling and 1 or 0
  electrics.values.rideheight = M.isSupensionRaised and 1 or 0
  electrics.values.doorLever = doorLeverSmoother:getUncapped(doorLever, dt)

  timer = timer + dt
  if timer > 0.5 then
    timer = timer % 0.5
    if currentLine.tasklist and currentLine.tasklist[curWaypoint] then
      --log("E",logTag,"pos ="..dumps(currentLine.tasklist[cur][3]))
      local dist = vec3(currentLine.tasklist[curWaypoint][3]):distance(vec3(obj:getPosition()))
      -- log("E",logTag,"dist ="..tostring(dist))
      if dist < 75 and curWaypoint ~= lastApproach then
        controller.onGameplayEvent("bus_onApproachStop", {triggerName = currentLine.tasklist[curWaypoint][1]})
        lastApproach = curWaypoint
      end
    end
  end
end

local function reset()
  M.doorsOpen = false
  M.frontDoorsMaxPressure = 0
  M.rearDoorsMaxPressure = 0
  M.isKneeling = false
  M.isSupensionRaised = false
  M.defaultSuspensionTargetHeight = 0

  if suspensionController and not suspensionController.isCalibrating("leftAxle") and not suspensionController.isCalibrating("rightAxle") then
    M.defaultSuspensionTargetHeight = (suspensionController.getTargetLength("leftAxle") + suspensionController.getTargetLength("rightAxle")) / 2
  else
    M.defaultSuspensionTargetHeight = -1
  end

  doorLever = 0
  electrics.values.dooropen = 0
  electrics.values.doorlever = 0
  electrics.values.kneel = 0
  electrics.values.rideheight = 0

  timer = 0
  curWaypoint = 1
  lastApproach = -1
end

local function registerQuickAccess()
  if not hasRegisteredQuickAccess and core_quickAccess ~= nil then
    core_quickAccess.addEntry(
      {
        level = "/root/playerVehicle/vehicleFeatures/",
        generator = function(entries)
          local e = {
            title = "ui.radialmenu2.bus.kneel",
            icon = "busTilted",
            uniqueID = "busKneel",
            onSelect = function()
              toggleKneel()
              return {"reload"}
            end
          }
          if electrics.values.kneel == 1 then
            e.color = "#ff6600"
          end
          table.insert(entries, e)

          e = {
            title = "ui.radialmenu2.bus.doors",
            icon = "vehicleDoorsOpen",
            uniqueID = "busDoors",
            onSelect = function()
              toggleDoors()
              return {"reload"}
            end
          }
          if electrics.values.dooropen == 1 then
            e.color = "#ff6600"
          end
          table.insert(entries, e)
        end
      }
    )

    hasRegisteredQuickAccess = true
  end
end

local function init(jbeamData)
  hasSafetyInterlock = jbeamData.hasSafetyInterlock or false
  kneelHeightReduction = jbeamData.kneelHeightReduction or 0.06 -- 6 cm
  maxRideHeightIncrease = jbeamData.maxRideHeightIncrease or 0.06 -- 6 cm

  M.doorsOpen = false
  M.frontDoorsMaxPressure = 0
  M.rearDoorsMaxPressure = 0
  M.isKneeling = false
  M.isSupensionRaised = false
  M.defaultSuspensionTargetHeight = 0
  electrics.values.dooropen = 0
  electrics.values.doorlever = 0
  electrics.values.kneel = 0
  electrics.values.rideheight = 0

  doorLeverSmoother = newTemporalSmoothing(2, 2)
  doorLever = 0

  registerQuickAccess()

  if jbeamData.nextStopNode and v.data[jbeamData.nextStopNode] then
    local nsData = v.data[jbeamData.nextStopNode]
    NSdisplayScreenName = nsData.NSmaterialName
    NSHtmlPath = nsData.NShtmlPath
    local NSwidth = nsData.NStextureWidth or 512
    local NSheight = nsData.NStextureHeight or 384

    if NSHtmlPath and NSdisplayScreenName then
      htmlTexture.create(NSdisplayScreenName, NSHtmlPath, NSwidth, NSheight, 15, "automatic")
    else
      log("E", logTag, "Got no html or material name path for NextStop, no HTML texture created!!!...")
    end
  end

  if jbeamData.destinationSignNode and v.data[jbeamData.destinationSignNode] then
    local destData = v.data[jbeamData.destinationSignNode]
    destScreenName = destData.destMaterialName or destScreenName
    destHtmlPath = destData.destHtmlPath
    local destWidth = destData.destTextureWidth or 256
    local destHeight = destData.destTextureHeight or 16
    local destText = destData.destText or ""
    local destRoute = destData.destRoute or ""

    if destHtmlPath and destScreenName then
      htmlTexture.create(destScreenName, destHtmlPath, destWidth, destHeight, 4, "automatic")
      htmlTexture.call(destScreenName, "update", {direction = destText, routeID = destRoute})
    else
      log("E", logTag, "Got no html path or material name for destination, no HTML texture created!!!...")
    end
  end
end

local function initSecondStage()
  doorController = controller.getController("doors")
  suspensionController = controller.getController("airSuspension")

  if doorController then
    doorController.setBeamGroupsValveState({"frontDoors", "rearDoors"}, 1) -- apply pressure from the start, keeping doors closed
  end

  if suspensionController and not suspensionController.isCalibrating("leftAxle") and not suspensionController.isCalibrating("rightAxle") then
    M.defaultSuspensionTargetHeight = (suspensionController.getTargetLength("leftAxle") + suspensionController.getTargetLength("rightAxle")) / 2
  else
    M.defaultSuspensionTargetHeight = -1
  end
end

local function recalculateStopList()
  local sl = {}
  for i = curWaypoint, #currentLine.tasklist, 1 do
    table.insert(sl, currentLine.tasklist[i][2])
  end
  return sl
end

--duplicate code at scenario/busdriver.lua:62
local function isTriggerOnBusLine(tasks, tname)
  for _, v in pairs(tasks) do
    if v[1] == tname then
      return true
    end
  end
  return false
end

local function onGameplayEvent(eventName, eventData)
  if eventName == "bus_onRouteChange" then
    --print("CALLED AND IN: " .. dumps(eventData))
    if destScreenName then
      htmlTexture.call(destScreenName, "update", eventData)
    end
    if NSdisplayScreenName then
      htmlTexture.call(NSdisplayScreenName, "updateDisplay", eventData)
    end
    guihooks.trigger("BusDisplayUpdate", eventData)
  elseif eventName == "bus_onDepartedStop" then
    if not currentLine.tasklist or #currentLine.tasklist == 0 then
      log("E", logTag, "No tasklist!")
      return
    end
    if not isTriggerOnBusLine(currentLine.tasklist, eventData.triggerName) then
      return
    end

    --fix spawning the bus in last busstop trigger, you still cannot go through, only exit once
    if currentLine.tasklist[#currentLine.tasklist][1] == eventData.triggerName and curWaypoint < #currentLine.tasklist then
      return
    end

    for i = 1, #currentLine.tasklist, 1 do
      if currentLine.tasklist[i][1] == eventData.triggerName then
        curWaypoint = i
        break
      end
    end
    curWaypoint = curWaypoint + 1

    local stopList = recalculateStopList()

    if NSdisplayScreenName then
      htmlTexture.call(NSdisplayScreenName, "updateDisplay", stopList)
    end
    guihooks.trigger("BusDisplayUpdate", stopList)

    geCallback("onDepartedStop", eventData)
  elseif eventName == "bus_onAtStop" then
    if not currentLine.tasklist or #currentLine.tasklist == 0 then
      log("E", logTag, "No tasklist!")
      return
    end
    if not isTriggerOnBusLine(currentLine.tasklist, eventData.triggerName) then
      return
    end

    for i = 1, #currentLine.tasklist, 1 do
      if currentLine.tasklist[i][1] == eventData.triggerName then
        curWaypoint = i
        break
      end
    end

    geCallback("onAtStop", eventData)
  elseif eventName == "bus_onApproachStop" then
    -- guihooks.trigger('Message', {ttl = 5, msg = 'onApproachStop', icon = 'directions_bus'})

    for i = 1, #currentLine.tasklist, 1 do
      if currentLine.tasklist[i][1] == eventData.triggerName then
        curWaypoint = i
        break
      end
    end

    geCallback("onApproachStop", eventData)
  elseif eventName == "bus_setLineInfo" then
    -- if currentLine.tasklist[1] then
    --   controller.onGameplayEvent("bus_onAtStop",{triggerName=currentLine.tasklist[1][1]})
    -- end
    -- log("I",logTag..".setLineInfo","eventData received in lua veh ="..dumps(eventData))
    reset()
    currentLine = eventData
    controller.onGameplayEvent("bus_onRouteChange", currentLine)
  elseif eventName == "bus_onTriggerTick" then
    eventData.speed = electrics.values.wheelspeed * 3.6
    eventData.bus_dooropen = M.doorsOpen
    eventData.bus_kneel = M.isKneeling
    geCallback("onTriggerTick", eventData)
  elseif eventName == "bus_onSetStopRequest" then
    if eventData then
      guihooks.trigger("SetStopRequest", eventData)
    end
  end
end

M.init = init
M.initSecondStage = initSecondStage
M.reset = reset
M.updateGFX = updateGFX
M.onGameplayEvent = onGameplayEvent

M.maxRideHeight = maxRideHeight
M.normalRideHeight = normalRideHeight
M.toggleDoors = toggleDoors
M.toggleKneel = toggleKneel

return M
