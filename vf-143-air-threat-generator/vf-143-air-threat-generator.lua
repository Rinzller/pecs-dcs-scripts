--[[
TITLE: VF-143 PUKIN DOGS AIR THREAT GENERATOR

Version:      1.0.0
Last Updated: July 29, 2026
Author:       Rinzller

DESCRIPTION:
    A plug-and-play DCS World training script that dynamically generates
    hostile aircraft packages through the F10 radio menu for VF-143
    Pukin Dogs BVR and intercept training.
--]]

local ATG = {}

ATG.config = {
    friendlyCoalition = coalition.side.BLUE,

    minRangeNM = 90,
    maxRangeNM = 110,
    minAltitudeFeet = 24000,
    maxAltitudeFeet = 34000,
    minSpeedKnots = 430,
    maxSpeedKnots = 520,

    skill = "Veteran",
    nightmareSkill = "Veteran",
    messageTime = 18,
    controllerName = "MAGIC",

    -- nil = first active friendly player aircraft found.
    referenceUnitName = nil,

    -- false = report unknown contacts; true = reveal aircraft type.
    reportAircraftType = false,

    -- Tactical line-abreast spacing between aircraft.
    formationSpacingNM = 1,
}

local M_PER_NM = 1852
local M_PER_FT = 0.3048
local MPS_PER_KNOT = 0.514444

local spawnedGroups = {}
local spawnSequence = 0
local selectedRedCountryId = nil

local function log(text)
    env.info("[AirThreatGenerator] " .. tostring(text))
end

local function message(text)
    trigger.action.outTextForCoalition(
        ATG.config.friendlyCoalition,
        text,
        ATG.config.messageTime,
        false
    )
end

local function normalizeBearing(value)
    value = value % 360
    if value < 0 then value = value + 360 end
    return value
end

local function formatBearing(value)
    return string.format("%03d", math.floor(normalizeBearing(value) + 0.5) % 360)
end

local function offsetPoint(origin, bearingDegrees, distanceMeters)
    local radians = math.rad(bearingDegrees)
    return {
        x = origin.x + math.sin(radians) * distanceMeters,
        z = origin.z + math.cos(radians) * distanceMeters,
    }
end

local function bearingAndRange(fromPoint, toPoint)
    local dx = toPoint.x - fromPoint.x
    local dz = toPoint.z - fromPoint.z

    return normalizeBearing(math.deg(math.atan2(dx, dz))),
        math.sqrt(dx * dx + dz * dz) / M_PER_NM
end

local function getReferenceUnit()
    if ATG.config.referenceUnitName then
        local unit = Unit.getByName(ATG.config.referenceUnitName)
        if unit and unit:isExist() and unit:getLife() > 0 then
            return unit
        end
    end

    for _, category in ipairs({ Group.Category.AIRPLANE, Group.Category.HELICOPTER }) do
        for _, group in ipairs(coalition.getGroups(ATG.config.friendlyCoalition, category) or {}) do
            if group and group:isExist() then
                for _, unit in ipairs(group:getUnits() or {}) do
                    if unit and unit:isExist() and unit:getLife() > 0 and unit:getPlayerName() then
                        return unit
                    end
                end
            end
        end
    end

    return nil
end

-- coalition.addGroup requires a COUNTRY ID, not coalition.side.RED.
-- This chooses a country that the current mission already places on RED.
local function getRedCountryId()
    if selectedRedCountryId then
        return selectedRedCountryId
    end

    local redCountries = env.mission
        and env.mission.coalition
        and env.mission.coalition.red
        and env.mission.coalition.red.country

    if not redCountries or #redCountries == 0 then
        return nil
    end

    local preferred = {
        country.id.RUSSIA,
        country.id.CJTF_RED,
        country.id.USSR,
    }

    for _, preferredId in ipairs(preferred) do
        if preferredId then
            for _, missionCountry in ipairs(redCountries) do
                if missionCountry.id == preferredId then
                    selectedRedCountryId = preferredId
                    return selectedRedCountryId
                end
            end
        end
    end

    selectedRedCountryId = redCountries[1].id
    return selectedRedCountryId
end

local function makePayload(fuel, flare, chaff, pylons)
    return {
        fuel = fuel,
        flare = flare,
        chaff = chaff,
        gun = 100,
        pylons = pylons,
    }
end

-- DCS weapon CLSIDs used by the stock Flaming Cliffs aircraft.
local R73       = "{FBC29BFE-3D24-4C64-B81D-941239D12249}"
local R27ER     = "{E8069896-8435-4B90-95C0-01A03AE6E400}"
local R27ET     = "{B79C379A-9E87-4E50-A1EE-7F7E29C2E87A}"
local R77       = "{B4C01D60-A8A3-4237-BD72-CA7655BC0FE9}"
local ECM_LEFT  = "{44EE8698-89F9-48EE-AF36-5FD31896A82F}"
local ECM_RIGHT = "{44EE8698-89F9-48EE-AF36-5FD31896A82A}"
local MIG29_TANK = "{PTB_1500_MIG29A}"

local function su27Payload()
    return makePayload(9400, 96, 96, {
        [1]  = { CLSID = ECM_LEFT },
        [2]  = { CLSID = R73 },
        [3]  = { CLSID = R27ET },
        [4]  = { CLSID = R27ER },
        [5]  = { CLSID = R27ER },
        [6]  = { CLSID = R27ER },
        [7]  = { CLSID = R27ER },
        [8]  = { CLSID = R27ET },
        [9]  = { CLSID = R73 },
        [10] = { CLSID = ECM_RIGHT },
    })
end

local function mig29sPayload()
    return makePayload(3493, 30, 30, {
        [1] = { CLSID = R73 },
        [2] = { CLSID = R77 },
        [3] = { CLSID = R77 },
        [4] = { CLSID = MIG29_TANK },
        [5] = { CLSID = R77 },
        [6] = { CLSID = R77 },
        [7] = { CLSID = R73 },
    })
end

local function su33Payload()
    return makePayload(9500, 48, 48, {
        [1]  = { CLSID = ECM_LEFT },
        [2]  = { CLSID = R73 },
        [3]  = { CLSID = R27ET },
        [4]  = { CLSID = R27ER },
        [5]  = { CLSID = R27ER },
        [8]  = { CLSID = R27ER },
        [9]  = { CLSID = R27ER },
        [10] = { CLSID = R27ET },
        [11] = { CLSID = R73 },
        [12] = { CLSID = ECM_RIGHT },
    })
end

local function emptyPayload(fuel, flare, chaff)
    return makePayload(fuel, flare, chaff, {})
end

local SU27 = { typeName = "Su-27", displayName = "Su-27", payload = su27Payload }
local MIG29S = { typeName = "MiG-29S", displayName = "MiG-29S", payload = mig29sPayload }
local SU33 = { typeName = "Su-33", displayName = "Su-33", payload = su33Payload }
local TU22 = { typeName = "Tu-22M3", displayName = "Tu-22M3", payload = function() return emptyPayload(50000, 72, 72) end, bomber = true }
local TU95 = { typeName = "Tu-95MS", displayName = "Tu-95MS", payload = function() return emptyPayload(87000, 96, 96) end, bomber = true }

local function weightedChoice(entries)
    local total = 0
    for _, entry in ipairs(entries) do total = total + entry.weight end
    local roll = math.random() * total
    local running = 0
    for _, entry in ipairs(entries) do
        running = running + entry.weight
        if roll <= running then return entry.aircraft end
    end
    return entries[1].aircraft
end

local pools = {
    easy = {
        { aircraft = SU27, weight = 70 },
        { aircraft = SU33, weight = 30 },
    },
    medium = {
        { aircraft = SU27, weight = 50 },
        { aircraft = SU33, weight = 40 },
        { aircraft = MIG29S, weight = 10 },
    },
    hard = {
        { aircraft = SU27, weight = 40 },
        { aircraft = SU33, weight = 30 },
        { aircraft = MIG29S, weight = 30 },
    },
    nightmare = {
        { aircraft = SU27, weight = 35 },
        { aircraft = SU33, weight = 25 },
        { aircraft = MIG29S, weight = 40 },
    },
}

local function chooseAircraft(poolName)
    return weightedChoice(pools[poolName or "hard"])
end

local function engageAirTask()
    return {
        id = "ComboTask",
        params = {
            tasks = {
                {
                    enabled = true,
                    auto = false,
                    id = "EngageTargets",
                    number = 1,
                    params = {
                        targetTypes = { "Air" },
                        priority = 0,
                        maxDistEnabled = true,
                        maxDist = 250000,
                    },
                },
            },
        },
    }
end

local function waypoint(point, altitudeMeters, speedMps, task)
    return {
        x = point.x,
        y = point.z,
        alt = altitudeMeters,
        alt_type = "BARO",
        action = "Turning Point",
        type = "Turning Point",
        speed = speedMps,
        speed_locked = true,
        ETA_locked = false,
        task = task or { id = "ComboTask", params = { tasks = {} } },
    }
end

local function buildGroup(aircraft, count, referencePoint, spawnPoint, bearing, altitudeFeet, speedKnots, skill)
    spawnSequence = spawnSequence + 1

    local unique = string.format("%d_%d", math.floor(timer.getTime()), spawnSequence)
    local safeType = aircraft.typeName:gsub("[^%w]", "")
    local groupName = "ATG_" .. safeType .. "_" .. unique

    local altitudeMeters = altitudeFeet * M_PER_FT
    local speedMps = speedKnots * MPS_PER_KNOT
    local inboundBearing = normalizeBearing(bearing + 180)

    -- DCS unit heading is not the same convention as a compass bearing.
    -- Calculate the actual DCS-world heading vector from the spawn point
    -- directly toward the reference aircraft so the group begins nose-hot.
    local headingRadians = math.atan2(
        referencePoint.z - spawnPoint.z,
        referencePoint.x - spawnPoint.x
    )

    local routeEnd = offsetPoint(referencePoint, inboundBearing, 50 * M_PER_NM)

    -- Centered tactical line abreast. Adjacent aircraft are exactly
    -- formationSpacingNM apart, perpendicular to the inbound heading.
    local spacingMeters = ATG.config.formationSpacingNM * M_PER_NM
    local units = {}

    for index = 1, count do
        local rightOffset = (index - ((count + 1) / 2)) * spacingMeters
        local unitPoint = offsetPoint(spawnPoint, inboundBearing + 90, rightOffset)

        local payload = aircraft.payload()

        units[index] = {
            type = aircraft.typeName,
            name = string.format("ATG_%s_%s_%d", safeType, unique, index),
            skill = skill or ATG.config.skill,
            x = unitPoint.x,
            y = unitPoint.z,
            alt = altitudeMeters,
            alt_type = "BARO",
            speed = speedMps,
            heading = headingRadians,
            psi = -headingRadians,
            payload = payload,
            AddPropAircraft = {},
            callsign = {
                [1] = 1,
                [2] = ((spawnSequence - 1) % 9) + 1,
                [3] = index,
            },
            onboard_num = string.format("%03d", (spawnSequence * 10 + index) % 999),
        }
    end

    local task = engageAirTask()

    return groupName, {
        visible = false,
        hidden = false,
        lateActivation = false,
        uncontrolled = false,
        task = "CAP",
        taskSelected = true,
        route = {
            points = {
                waypoint(spawnPoint, altitudeMeters, speedMps, task),
                waypoint(referencePoint, altitudeMeters, speedMps, task),
                waypoint(routeEnd, altitudeMeters, speedMps, task),
            },
        },
        units = units,
        name = groupName,
        communication = true,
        frequency = 124,
        modulation = 0,
    }
end

local function spawnGroup(options)
    local referenceUnit = getReferenceUnit()
    if not referenceUnit then
        return nil, "No active friendly player aircraft found."
    end

    local redCountryId = getRedCountryId()
    if not redCountryId then
        return nil, "No country is assigned to the RED coalition in this mission."
    end

    local referencePoint = referenceUnit:getPoint()
    local aircraft = options.aircraft or chooseAircraft(options.poolName)
    local count = options.count or 1
    local bearing = options.bearing or math.random(0, 359)
    local rangeNM = options.rangeNM or math.random(ATG.config.minRangeNM, ATG.config.maxRangeNM)
    local altitudeFeet = options.altitudeFeet or math.random(ATG.config.minAltitudeFeet, ATG.config.maxAltitudeFeet)
    local speedKnots = options.speedKnots or math.random(ATG.config.minSpeedKnots, ATG.config.maxSpeedKnots)
    local spawnPoint = offsetPoint(referencePoint, bearing, rangeNM * M_PER_NM)

    local groupName, groupData = buildGroup(
        aircraft,
        count,
        referencePoint,
        spawnPoint,
        bearing,
        altitudeFeet,
        speedKnots,
        options.skill
    )

    local ok, spawnedGroup = pcall(
        coalition.addGroup,
        redCountryId,
        Group.Category.AIRPLANE,
        groupData
    )

    if not ok or not spawnedGroup then
        log("Spawn failed: " .. tostring(spawnedGroup))
        return nil, "DCS rejected the dynamically created aircraft group. Check dcs.log."
    end

    spawnedGroups[#spawnedGroups + 1] = groupName

    local reportedBearing, reportedRange = bearingAndRange(referencePoint, spawnPoint)

    -- Delayed diagnostic in dcs.log. This makes weapon-loadout failures
    -- visible without affecting gameplay.
    timer.scheduleFunction(function(args)
        local group = Group.getByName(args.groupName)
        if not group or not group:isExist() then return nil end

        for unitIndex, unit in ipairs(group:getUnits() or {}) do
            local missileCount = 0
            for _, ammo in ipairs(unit:getAmmo() or {}) do
                local category = ammo.desc and ammo.desc.category
                if category == Weapon.Category.MISSILE then
                    missileCount = missileCount + (ammo.count or 0)
                end
            end
            log(string.format("%s unit %d spawned with %d missile(s).", args.groupName, unitIndex, missileCount))
        end
        return nil
    end, { groupName = groupName }, timer.getTime() + 2)

    return {
        group = spawnedGroup,
        groupName = groupName,
        aircraft = aircraft,
        count = count,
        bearing = reportedBearing,
        rangeNM = reportedRange,
        altitudeFeet = altitudeFeet,
    }
end

local function describeContact(result)
    if ATG.config.reportAircraftType then
        return string.format("%dx %s", result.count, result.aircraft.displayName)
    end

    if result.count == 1 then
        return "single contact"
    end

    return string.format("multiple contacts, group of %d", result.count)
end

local function spawnDifficulty(count, label, poolName)
    local result, err = spawnGroup({ count = count, poolName = poolName })

    if not result then
        message("AIR THREAT GENERATOR: " .. err)
        return
    end

    message(string.format(
        "%s: %s threat detected.\n%s, bearing %s, range %.0f nautical miles, angels %d, hot.",
        ATG.config.controllerName,
        label,
        describeContact(result),
        formatBearing(result.bearing),
        result.rangeNM,
        math.floor((result.altitudeFeet / 1000) + 0.5)
    ))
end

function ATG.easy()
    spawnDifficulty(1, "Easy", "easy")
end

function ATG.medium()
    spawnDifficulty(2, "Medium", "medium")
end

function ATG.hard()
    spawnDifficulty(4, "Hard", "hard")
end

local nightmareScenarios = {
    {
        name = "Red Air Sweep",
        weight = 20,
        groups = {
            { count = 8, aircraft = SU27, bearingOffset = 0, rangeOffset = 0, altitudeOffset = 0 },
        },
    },
    {
        name = "Modern Threat",
        weight = 15,
        groups = {
            { count = 4, aircraft = MIG29S, bearingOffset = 0, rangeOffset = 0, altitudeOffset = 0 },
        },
    },
    {
        name = "Carrier CAP",
        weight = 10,
        groups = {
            { count = 4, aircraft = SU33, bearingOffset = 0, rangeOffset = 0, altitudeOffset = 0 },
        },
    },
    {
        name = "Mixed CAP",
        weight = 15,
        groups = {
            { count = 2, aircraft = SU27, bearingOffset = -8, rangeOffset = 0, altitudeOffset = 3000 },
            { count = 2, aircraft = MIG29S, bearingOffset = 8, rangeOffset = 5, altitudeOffset = -3000 },
        },
    },
    {
        name = "Two-Axis Pincer",
        weight = 15,
        groups = {
            { count = 4, aircraft = SU27, bearingOffset = -55, rangeOffset = 0, altitudeOffset = 3000 },
            { count = 4, aircraft = MIG29S, bearingOffset = 55, rangeOffset = 5, altitudeOffset = -3000 },
        },
    },
    {
        name = "Backfire Escort",
        weight = 10,
        groups = {
            { count = 2, aircraft = TU22, bearingOffset = 0, rangeOffset = 0, altitudeOffset = 0, speedKnots = 480 },
            { count = 4, aircraft = SU27, bearingOffset = -5, rangeOffset = -3, altitudeOffset = 3000 },
        },
    },
    {
        name = "Bear Escort",
        weight = 10,
        groups = {
            { count = 2, aircraft = TU95, bearingOffset = 0, rangeOffset = 0, altitudeOffset = 4000, speedKnots = 350 },
            { count = 4, aircraft = MIG29S, bearingOffset = 5, rangeOffset = -5, altitudeOffset = -2000 },
        },
    },
    {
        name = "Massive Raid",
        weight = 5,
        groups = {
            { count = 2, aircraft = TU22, bearingOffset = 0, rangeOffset = 5, altitudeOffset = 0, speedKnots = 480 },
            { count = 4, aircraft = SU27, bearingOffset = -35, rangeOffset = 0, altitudeOffset = 4000 },
            { count = 4, aircraft = MIG29S, bearingOffset = 35, rangeOffset = 0, altitudeOffset = -4000 },
        },
    },
}

local function chooseNightmareScenario()
    local total = 0
    for _, scenario in ipairs(nightmareScenarios) do total = total + scenario.weight end
    local roll = math.random() * total
    local running = 0
    for _, scenario in ipairs(nightmareScenarios) do
        running = running + scenario.weight
        if roll <= running then return scenario end
    end
    return nightmareScenarios[1]
end

function ATG.nightmare()
    local referenceUnit = getReferenceUnit()
    if not referenceUnit then
        message("AIR THREAT GENERATOR: No active friendly player aircraft found.")
        return
    end

    if not getRedCountryId() then
        message("AIR THREAT GENERATOR: No country is assigned to RED.")
        return
    end

    local scenario = chooseNightmareScenario()
    local baseBearing = math.random(0, 359)
    local baseRange = math.random(ATG.config.minRangeNM, ATG.config.maxRangeNM)
    local baseAltitude = math.random(27000, 32000)
    local reports = {}

    for index, definition in ipairs(scenario.groups) do
        local result, err = spawnGroup({
            count = definition.count,
            aircraft = definition.aircraft or chooseAircraft("nightmare"),
            bearing = normalizeBearing(baseBearing + definition.bearingOffset),
            rangeNM = math.max(70, baseRange + definition.rangeOffset),
            altitudeFeet = math.max(15000, baseAltitude + definition.altitudeOffset),
            speedKnots = definition.speedKnots or math.random(470, 540),
            skill = ATG.config.nightmareSkill,
        })

        if not result then
            message("AIR THREAT GENERATOR: Nightmare spawn failed: " .. err)
            return
        end

        reports[#reports + 1] = string.format(
            "Group %d: %s, bearing %s, range %.0f, angels %d, hot",
            index,
            describeContact(result),
            formatBearing(result.bearing),
            result.rangeNM,
            math.floor((result.altitudeFeet / 1000) + 0.5)
        )
    end

    message(string.format(
        "%s: NIGHTMARE package detected - %s.\n%s.",
        ATG.config.controllerName,
        scenario.name,
        table.concat(reports, "\n")
    ))
end

function ATG.removeAll()
    local removed = 0

    for _, groupName in ipairs(spawnedGroups) do
        local group = Group.getByName(groupName)
        if group and group:isExist() then
            group:destroy()
            removed = removed + 1
        end
    end

    spawnedGroups = {}

    message(string.format(
        "AIR THREAT GENERATOR: Removed %d spawned threat group%s.",
        removed,
        removed == 1 and "" or "s"
    ))
end

-- DCS initializes the Lua random-number generator. Do not call
-- math.randomseed() here; some DCS Lua builds reject or omit it.

local rootMenu = missionCommands.addSubMenuForCoalition(
    ATG.config.friendlyCoalition,
    "VF-143 Air Threat Generator"
)

missionCommands.addCommandForCoalition(
    ATG.config.friendlyCoalition,
    "Easy - 1 Fighter",
    rootMenu,
    ATG.easy
)

missionCommands.addCommandForCoalition(
    ATG.config.friendlyCoalition,
    "Medium - 2 Fighters",
    rootMenu,
    ATG.medium
)

missionCommands.addCommandForCoalition(
    ATG.config.friendlyCoalition,
    "Hard - 4 Fighters",
    rootMenu,
    ATG.hard
)

missionCommands.addCommandForCoalition(
    ATG.config.friendlyCoalition,
    "Nightmare - Random Package",
    rootMenu,
    ATG.nightmare
)

missionCommands.addCommandForCoalition(
    ATG.config.friendlyCoalition,
    "Cleanup Spawned Threats",
    rootMenu,
    ATG.removeAll
)

local redCountry = getRedCountryId()
if redCountry then
    log("Initialized. Dynamic enemy country ID: " .. tostring(redCountry))
else
    log("WARNING: No country is currently assigned to RED.")
end

trigger.action.outText(
    "VF-143 Pukin Dogs Air Threat Generator is Active",
    10
)
