--[[
TITLE: VF-143 PUKIN DOGS RANGE TARGET SCORING SCRIPT

Version:      1.0.0
Last Updated: July 29, 2026
Author:       Rinzller

DESCRIPTION:
    Tracks bomb impacts and reports the miss distance from
    the nearest configured range target.
]]--

------------------------------------------------------------
-- Configuration
------------------------------------------------------------

local targets = {
    {
        objectName = "RANGE_TARGET_1",
        displayName = "Range Alpha"
    },
    {
        objectName = "RANGE_TARGET_2",
        displayName = "Range Bravo"
    }
}

-- Maximum distance from a target that will be scored (meters)
local maxScoringDistance = 500

-- Bomb tracking update interval (seconds)
local trackingInterval = 0.05

------------------------------------------------------------
-- Utility Functions
------------------------------------------------------------

local function getObjectByName(name)
    return StaticObject.getByName(name)
        or Unit.getByName(name)
end

local function distance2D(a, b)
    local x = a.x - b.x
    local z = a.z - b.z

    return math.sqrt(x * x + z * z)
end

local function getNearestTarget(point)
    local nearestTarget = nil
    local nearestDistance = math.huge

    for _, target in ipairs(targets) do
        local object = getObjectByName(target.objectName)

        if object and object:isExist() then
            local targetPoint = object:getPoint()
            local distance = distance2D(point, targetPoint)

            if distance < nearestDistance then
                nearestTarget = target
                nearestDistance = distance
            end
        end
    end

    return nearestTarget, nearestDistance
end

local function showResult(playerName, impactPoint)
    local target, distance = getNearestTarget(impactPoint)

    if not target then
        return
    end

    if distance > maxScoringDistance then
        return
    end

    local feet = distance * 3.28084

    trigger.action.outText(
        string.format(
            "%s\n%s\nMiss Distance: %.1f ft / %.1f m",
            playerName or "Unknown Pilot",
            target.displayName,
            feet,
            distance
        ),
        12
    )
end

------------------------------------------------------------
-- Bomb Tracking
------------------------------------------------------------

local function trackBomb(data, time)
    local bomb = data.bomb

    if bomb and bomb:isExist() then
        data.lastPoint = bomb:getPoint()
        return time + trackingInterval
    end

    if data.lastPoint then
        data.lastPoint.y = land.getHeight({
            x = data.lastPoint.x,
            y = data.lastPoint.z
        })

        showResult(
            data.playerName,
            data.lastPoint
        )
    end

    return nil
end

------------------------------------------------------------
-- Event Handler
------------------------------------------------------------

local handler = {}

function handler:onEvent(event)

    if event.id ~= world.event.S_EVENT_SHOT then
        return
    end

    if not event.weapon or not event.initiator then
        return
    end

    local description = event.weapon:getDesc()

    if not description or description.category ~= Weapon.Category.BOMB then
        return
    end

    local playerName = event.initiator:getPlayerName()

    if not playerName then
        return
    end

    local data = {
        bomb = event.weapon,
        playerName = playerName,
        lastPoint = event.weapon:getPoint()
    }

    timer.scheduleFunction(
        trackBomb,
        data,
        timer.getTime() + trackingInterval
    )
end

------------------------------------------------------------
-- Initialize Script
------------------------------------------------------------

world.addEventHandler(handler)

trigger.action.outText(
    "VF-143 Pukin Dogs Range Target Scoring is Active",
    10
)
