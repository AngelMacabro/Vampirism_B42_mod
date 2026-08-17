-- VampirismServer.lua
-- Project Zomboid Build 42.20.2
-- Lógica server-side/host de vampirismo.

-- Si tu archivo shared ya se carga automáticamente, puedes quitar esta línea.
-- Si usas require, normalmente la ruta usa "/", no ".".
require("Vampirism/Vampirism")

Vampirism = Vampirism or {}
Vampirism.PlayerState = Vampirism.PlayerState or {}
Vampirism.currentTick = Vampirism.currentTick or 0
Vampirism.lastDamageTick = Vampirism.lastDamageTick or 0

-- UTILIDADES

local function Try(fn)
    if fn == nil then
        return nil
    end

    local ok, result = pcall(fn)
    if ok then
        return result
    end

    return nil
end

local function GetTextSafe(key, fallback)
    if getText then
        local ok, txt = pcall(getText, key)
        if ok and txt and txt ~= "" and txt ~= key then
            return txt
        end
    end

    return fallback or key
end

local function IsDedicatedServerSafe()
    return Try(isDedicatedServer) == true
end

local function ShouldRunServerLogic()
    local client = Try(isClient) == true
    local server = Try(isServer) == true

    -- Si somos cliente puro, no ejecutar lógica de servidor.
    -- Si somos host y además client/server, permitir ejecución.
    if client and not server then
        return false
    end

    return true
end

local function SendToClient(player, command, args)
    if not player or not command then
        return
    end

    if sendServerCommand then
        pcall(sendServerCommand, player, "Vampirism", command, args or {})
    end
end

local function IsLocalNonDedicatedPlayer(player)
    if IsDedicatedServerSafe() then
        return false
    end

    if player and player.isLocalPlayer then
        local ok, isLocal = pcall(player.isLocalPlayer, player)
        if ok then
            return isLocal == true
        end
    end

    return false
end

function Vampirism.SendPlayerMessage(player, text, r, g, b)
    if not player or not text or text == "" then
        return
    end

    r = r or 255
    g = g or 255
    b = b or 255

    -- Mostrar bocadillo de diálogo sobre la cabeza del personaje
    if player.Say then
        pcall(player.Say, player, text)
    end

    -- Texto flotante visual si HaloTextHelper está disponible
    if IsLocalNonDedicatedPlayer(player) then
        if HaloTextHelper and HaloTextHelper.addText then
            pcall(HaloTextHelper.addText, player, text, r, g, b)
        end
    end

    -- Sincronizar comando con cliente para que dibuje el diálogo y overlay
    SendToClient(player, "ShowMessage", {
        text = text,
        r = r,
        g = g,
        b = b
    })
end

-- ESTADO POR JUGADOR

local function GetPlayerKey(player)
    if not player then
        return nil
    end

    -- Username es mejor clave que OnlineID para estados persistentes.
    local username = Try(function()
        return player.getUsername and player:getUsername() or nil
    end)

    if username and username ~= "" then
        return "user_" .. tostring(username)
    end

    local onlineID = Try(function()
        return player.getOnlineID and player:getOnlineID() or nil
    end)

    if onlineID and onlineID ~= -1 then
        return "online_" .. tostring(onlineID)
    end

    local playerNum = Try(function()
        return player.getPlayerNum and player:getPlayerNum() or nil
    end)

    if playerNum ~= nil then
        return "local_" .. tostring(playerNum)
    end

    return "object_" .. tostring(player)
end

local function GetPlayerState(player)
    local key = GetPlayerKey(player)
    if not key then
        return nil
    end

    if not Vampirism.PlayerState[key] then
        Vampirism.PlayerState[key] = {
            burning = false,
            lastWarningTick = 0,
            nightEmpowered = false,
            originalStrength = nil
        }
    end

    return Vampirism.PlayerState[key]
end

-- OBTENER JUGADORES


local function GetAllPlayers()
    local list = {}

    -- Intentar obtener jugadores online.
    local onlinePlayers = Try(getOnlinePlayers)

    if onlinePlayers and onlinePlayers.size and onlinePlayers:size() > 0 then
        for i = 0, onlinePlayers:size() - 1 do
            local player = onlinePlayers:get(i)
            if player then
                table.insert(list, player)
            end
        end

        return list
    end

    -- Fallback para singleplayer/host local.
    local count = Try(getNumActivePlayers)

    if count and count > 0 then
        for i = 0, count - 1 do
            local player = Try(function()
                return getSpecificPlayer(i)
            end)

            if player then
                table.insert(list, player)
            end
        end
    end

    return list
end

-- CONDICIONES

function Vampirism.IsOutdoors(player)
    if not player then
        return false
    end

    -- Si está dentro de un vehículo, por ahora no recibe daño solar.
    local vehicle = Try(function()
        return player.getVehicle and player:getVehicle() or nil
    end)

    if vehicle then
        return false
    end

    local outside = Try(function()
        return player.isOutside and player:isOutside() or nil
    end)

    if outside ~= nil then
        return outside == true
    end

    local square = Try(function()
        return player.getSquare and player:getSquare() or nil
    end)

    if square then
        outside = Try(function()
            return square.isOutside and square:isOutside() or nil
        end)

        if outside ~= nil then
            return outside == true
        end
    end

    return false
end

function Vampirism.GetDawnAndDusk()
    local climate = Try(getClimateManager)
    if climate and climate.getSeason then
        local season = Try(function()
            return climate:getSeason()
        end)
        if season and season.getDawn and season.getDusk then
            local dawn = Try(function() return season:getDawn() end)
            local dusk = Try(function() return season:getDusk() end)
            if dawn and dusk and dawn > 0 and dusk > dawn then
                return dawn, dusk
            end
        end
    end

    local gameTime = Try(getGameTime)
    if gameTime and gameTime.getDawn and gameTime.getDusk then
        local dawn = Try(function() return gameTime:getDawn() end)
        local dusk = Try(function() return gameTime:getDusk() end)
        if dawn and dusk and dawn > 0 and dusk > dawn then
            return dawn, dusk
        end
    end

    local startHour = tonumber(Vampirism.SUN_DAMAGE_START_HOUR) or 6.0
    local endHour = tonumber(Vampirism.SUN_DAMAGE_END_HOUR) or 20.0
    return startHour, endHour
end

function Vampirism.GetCurrentTimeOfDay()
    local gameTime = Try(getGameTime)
    if not gameTime then
        return nil
    end

    if gameTime.getTimeOfDay then
        local tod = Try(function() return gameTime:getTimeOfDay() end)
        if tod ~= nil then
            return tod
        end
    end

    if gameTime.getHour then
        local hour = Try(function() return gameTime:getHour() end) or 0
        local min = Try(function() return gameTime.getMinutes and gameTime:getMinutes() or 0 end) or 0
        return hour + (min / 60)
    end

    return nil
end

function Vampirism.IsDaytime()
    local timeOfDay = Vampirism.GetCurrentTimeOfDay()
    if timeOfDay == nil then
        return false
    end

    local dawn, dusk = Vampirism.GetDawnAndDusk()

    -- Es de día únicamente desde el amanecer hasta el anochecer.
    return timeOfDay >= dawn and timeOfDay < dusk
end

function Vampirism.IsSunBlockedByWeather()
    local climate = Try(getClimateManager)
    if not climate then
        return false
    end

    -- 1. DÍA LLUVIOSO (RAIN)
    if Vampirism.PROTECT_IN_RAIN then
        local isRaining = false
        if climate.isRaining then
            local okRain, resRain = pcall(climate.isRaining, climate)
            if okRain and resRain == true then
                isRaining = true
            end
        end

        local rainThreshold = tonumber(Vampirism.RAIN_PROTECTION_THRESHOLD) or 0.05
        if not isRaining and climate.getPrecipitationIntensity then
            local precip = Try(function() return climate:getPrecipitationIntensity() end) or 0
            if precip >= rainThreshold then
                isRaining = true
            end
        end

        if not isRaining and climate.getRainIntensity then
            local rain = Try(function() return climate:getRainIntensity() end) or 0
            if rain >= rainThreshold then
                isRaining = true
            end
        end

        if not isRaining and RainManager and RainManager.isRaining then
            local okRM, resRM = pcall(RainManager.isRaining)
            if okRM and resRM == true then
                isRaining = true
            end
        end

        if isRaining then
            return true
        end
    end

    -- 2. TORMENTAS (STORM / THUNDERSTORM / BLIZZARD)
    if Vampirism.PROTECT_IN_STORM then
        -- Tormenta eléctrica activa
        if climate.getIsThunderStorming then
            local isThunder = Try(function() return climate:getIsThunderStorming() end)
            if isThunder == true then
                return true
            end
        end

        -- Periodo meteorológico de tormenta activo
        if climate.getWeatherPeriod then
            local wp = Try(function() return climate:getWeatherPeriod() end)
            if wp and wp.isRunning then
                local running = Try(function() return wp:isRunning() end)
                if running == true then
                    local isStorm = Try(function()
                        return (wp.isThunderStorm and wp:isThunderStorm())
                            or (wp.isTropicalStorm and wp:isTropicalStorm())
                            or (wp.isBlizzard and wp:isBlizzard())
                            or (wp.hasStorm and wp:hasStorm())
                    end)
                    if isStorm == true then
                        return true
                    end
                end
            end
        end

        -- Nubes de tormenta activas
        if climate.getThunderStorm then
            local ts = Try(function() return climate:getThunderStorm() end)
            if ts and ts.HasActiveThunderClouds then
                local clouds = Try(function() return ts:HasActiveThunderClouds() end)
                if clouds == true then
                    return true
                end
            end
        end
    end

    -- 3. NIEBLA / NEBLINA (FOG)
    if Vampirism.PROTECT_IN_FOG then
        local fogThreshold = tonumber(Vampirism.FOG_PROTECTION_THRESHOLD) or 0.15
        if climate.getFogIntensity then
            local fog = Try(function() return climate:getFogIntensity() end) or 0
            if fog >= fogThreshold then
                return true
            end
        end
    end

    -- Día despejado o nublado sin lluvia/niebla/tormenta: devuelve false (quema)
    return false
end

-- FUEGO Y EXTINCIÓN

local function IgniteCharacter(player)
    if not player then
        return
    end

    local isOnFire = Try(function()
        return player.isOnFire and player:isOnFire() or false
    end)

    if not isOnFire then
        if player.SetOnFire then
            pcall(player.SetOnFire, player)
        elseif player.setOnFire then
            pcall(player.setOnFire, player, true)
        end
    end
end

local function ExtinguishCharacter(player)
    if not player then
        return
    end

    -- Detener fuego mediante la API global de servidor
    if stopFire then
        pcall(stopFire, player)
    end

    -- Detener fuego en el objeto del personaje
    if player.StopBurning then
        pcall(player.StopBurning, player)
    end

    if player.setOnFire then
        pcall(player.setOnFire, player, false)
    end

    local body = Try(function()
        return player.getBodyDamage and player:getBodyDamage() or nil
    end)

    if body and body.setIsOnFire then
        pcall(body.setIsOnFire, body, false)
    end
end

-- DAÑO SOLAR

function Vampirism.ApplySunDamage(player)
    if not player then
        return
    end

    local dead = Try(function()
        return player.isDead and player:isDead() or false
    end)

    if dead then
        Vampirism.StopSunDamage(player, true)
        return
    end

    local state = GetPlayerState(player)

    if not state then
        return
    end

    if not state.burning then
        state.burning = true
        state.lastWarningTick = Vampirism.currentTick
        SendToClient(player, "SunDamageStart", {})

        -- Notificación y diálogo inmediato al empezar a quemarse
        local startMsg = GetTextSafe(
            "UI_Vampirism_SunWarning",
            "The sunlight burns my skin!"
        )
        Vampirism.SendPlayerMessage(
            player,
            startMsg,
            255,
            100,
            0
        )
    end

    -- PRENDER FUEGO FÍSICO AL PERSONAJE
    if Vampirism.IGNITE_ON_SUN_EXPOSURE then
        IgniteCharacter(player)
    end

    local body = Try(function()
        return player.getBodyDamage and player:getBodyDamage() or nil
    end)

    if not body then
        return
    end

    -- DAÑO GENERAL
    local damageAmount =
        tonumber(Vampirism.SUN_DAMAGE_AMOUNT) or 1

    if body.ReduceGeneralHealth then
        pcall(
            body.ReduceGeneralHealth,
            body,
            damageAmount
        )
    end

    -- DOLOR SOLAR
    local painAmount =
        tonumber(Vampirism.SUN_PAIN_AMOUNT) or 2

    local bodyParts = Try(function()
        return body.getBodyParts and body:getBodyParts() or nil
    end)

    if bodyParts and bodyParts.size and bodyParts:size() > 0 then
        local part = bodyParts:get(0)

        if part and part.setAdditionalPain then
            pcall(
                part.setAdditionalPain,
                part,
                painAmount
            )
        end
    end

    -- MENSAJE PERIÓDICO REPETIDO
    local warningCooldownTicks =
        (tonumber(Vampirism.SUN_WARNING_COOLDOWN) or 30) * 60

    if not state.lastWarningTick
        or (Vampirism.currentTick - state.lastWarningTick)
            >= warningCooldownTicks then

        state.lastWarningTick = Vampirism.currentTick

        local msg = GetTextSafe(
            "UI_Vampirism_SunWarning",
            "The sunlight burns my skin!"
        )

        Vampirism.SendPlayerMessage(
            player,
            msg,
            255,
            100,
            0
        )
    end
end

function Vampirism.StopSunDamage(player, silent)
    if not player then
        return
    end

    local state = GetPlayerState(player)
    if not state or not state.burning then
        -- Asegurar extinción si el jugador aún estuviese en llamas
        if Vampirism.AUTO_EXTINGUISH_IN_SHADE then
            local isOnFire = Try(function()
                return player.isOnFire and player:isOnFire() or false
            end)
            if isOnFire then
                ExtinguishCharacter(player)
            end
        end
        return
    end

    state.burning = false

    -- EXTINGUIR FUEGO AL ENTRAR A LA SOMBRA / INTERIORES
    if Vampirism.AUTO_EXTINGUISH_IN_SHADE then
        ExtinguishCharacter(player)
    end

    SendToClient(player, "SunDamageStop", {})

    if not silent then
        local msg = GetTextSafe(
            "UI_Vampirism_SunProtected",
            "You are safe from the sun."
        )

        Vampirism.SendPlayerMessage(player, msg, 100, 255, 100)
    end
end

-- ============================================================
-- EMPODERAMIENTO NOCTURNO (VELOCIDAD Y FUERZA)
-- ============================================================

function Vampirism.ApplyNightEmpowerment(player)
    if not player or not Vampirism.NIGHT_BUFFS_ENABLED then
        return
    end

    local dead = Try(function()
        return player.isDead and player:isDead() or false
    end)
    if dead then
        return
    end

    local state = GetPlayerState(player)
    if not state then
        return
    end

    if not state.nightEmpowered then
        state.nightEmpowered = true

        local modData = Try(function()
            return player.getModData and player:getModData() or nil
        end)

        local currentStrength = 5
        if Perks and Perks.Strength and player.getPerkLevel then
            local okStr, strLvl = pcall(player.getPerkLevel, player, Perks.Strength)
            if okStr and strLvl then
                currentStrength = strLvl
            end
        end

        if state.originalStrength == nil then
            if modData and modData.vampireOriginalStrength ~= nil then
                state.originalStrength = modData.vampireOriginalStrength
            else
                state.originalStrength = currentStrength
                if modData then
                    modData.vampireOriginalStrength = currentStrength
                end
            end
        end

        local bonusStr = tonumber(Vampirism.NIGHT_STRENGTH_BONUS) or 3
        local targetStrength = math.min(10, state.originalStrength + bonusStr)

        if Perks and Perks.Strength and player.setPerkLevelDebug then
            pcall(player.setPerkLevelDebug, player, Perks.Strength, targetStrength)
        end

        SendToClient(player, "NightEmpowerStart", {})

        local msg = GetTextSafe(
            "UI_Vampirism_NightEmpowerStart",
            "The night empowers your body with speed and strength."
        )
        Vampirism.SendPlayerMessage(player, msg, 150, 100, 255)
    end

    local speedMult = tonumber(Vampirism.NIGHT_SPEED_MULTIPLIER) or 1.25
    if player.setSpeedMod then
        pcall(player.setSpeedMod, player, speedMult)
    end
end

function Vampirism.RemoveNightEmpowerment(player, silent)
    if not player then
        return
    end

    local state = GetPlayerState(player)
    if not state or not state.nightEmpowered then
        if player.setSpeedMod then
            pcall(player.setSpeedMod, player, 1.0)
        end
        return
    end

    state.nightEmpowered = false

    local modData = Try(function()
        return player.getModData and player:getModData() or nil
    end)

    local baseStrength = state.originalStrength or (modData and modData.vampireOriginalStrength) or 5
    if Perks and Perks.Strength and player.setPerkLevelDebug then
        pcall(player.setPerkLevelDebug, player, Perks.Strength, baseStrength)
    end

    if player.setSpeedMod then
        pcall(player.setSpeedMod, player, 1.0)
    end

    SendToClient(player, "NightEmpowerStop", {})

    if not silent then
        local msg = GetTextSafe(
            "UI_Vampirism_NightEmpowerStop",
            "The morning light fades your nocturnal power."
        )
        Vampirism.SendPlayerMessage(player, msg, 200, 200, 150)
    end
end

function Vampirism.EvaluateSunDamageForPlayer(player)
    if not player then
        return
    end

    local dead = Try(function()
        return player.isDead and player:isDead() or false
    end)

    if dead then
        Vampirism.StopSunDamage(player, true)
        Vampirism.RemoveNightEmpowerment(player, true)
        return
    end

    -- Garantizar traits asociados (visión nocturna y damned) si es vampiro
    Vampirism.EnsureVampireTraits(player)

    if not Vampirism.HasVampireTrait(player) then
        Vampirism.StopSunDamage(player, true)
        Vampirism.RemoveNightEmpowerment(player, true)
        return
    end

    -- NOCHE: Empoderar vampiro y apagar daño solar
    if not Vampirism.IsDaytime() then
        Vampirism.StopSunDamage(player)
        Vampirism.ApplyNightEmpowerment(player)
        Vampirism.ManageVampireStats(player)
        return
    end

    -- DÍA: Retirar empoderamiento nocturno
    Vampirism.RemoveNightEmpowerment(player)
    Vampirism.ManageVampireStats(player)

    -- Si no está al aire libre (edificio, vehículo, interiores), está a salvo del sol
    if not Vampirism.IsOutdoors(player) then
        Vampirism.StopSunDamage(player)
        return
    end

    -- Si el clima bloquea los rayos solares (neblina o tormenta), está a salvo
    if Vampirism.IsSunBlockedByWeather() then
        Vampirism.StopSunDamage(player)
        return
    end

    Vampirism.ApplySunDamage(player)
end

function Vampirism.ManageVampireStats(player)
    if not player or player:isDead() then
        return
    end

    if not Vampirism.HasVampireTrait(player) then
        return
    end

    -- Suprimir hambre mortal
    if Vampirism.HUNGER_DISABLED then
        local stats = Try(function()
            return player.getStats and player:getStats() or nil
        end)

        if stats and CharacterStat and CharacterStat.HUNGER then
            local currentHunger = Try(function()
                return stats:get(CharacterStat.HUNGER)
            end) or 0

            if currentHunger > 0.001 then
                stats:set(CharacterStat.HUNGER, 0.0)
            end
        end
    end

    -- Mantener peso corporal estabilizado para evitar inanición
    local nutrition = Try(function()
        return player.getNutrition and player:getNutrition() or nil
    end)
    if nutrition and nutrition.getWeight and nutrition.setWeight then
        local ok, w = pcall(nutrition.getWeight, nutrition)
        if ok and (w == nil or w <= 1) then
            pcall(nutrition.setWeight, nutrition, 80.0)
        end
    end
end

-- ============================================================
-- ALIMENTACIÓN DE JUGADORES VIVOS Y CADÁVERES
-- ============================================================

function Vampirism.HandleFeedOnPlayer(attacker, args)
    if not attacker or not ShouldRunServerLogic() then
        return
    end

    if attacker:isDead() or not Vampirism.HasVampireTrait(attacker) then
        return
    end

    args = args or {}

    local targetPlayer = nil
    if args.targetOnlineID and args.targetOnlineID ~= -1 then
        local onlinePlayers = Try(getOnlinePlayers)
        if onlinePlayers and onlinePlayers.size then
            for i = 0, onlinePlayers:size() - 1 do
                local p = onlinePlayers:get(i)
                if p and p.getOnlineID and p:getOnlineID() == args.targetOnlineID then
                    targetPlayer = p
                    break
                end
            end
        end
    end

    if not targetPlayer and args.targetPlayerNum and args.targetPlayerNum ~= -1 then
        targetPlayer = Try(function()
            return getSpecificPlayer(args.targetPlayerNum)
        end)
    end

    if not targetPlayer and args.targetUsername then
        local all = GetAllPlayers()
        for _, p in ipairs(all) do
            local uName = Try(function()
                return p.getUsername and p:getUsername() or nil
            end)
            if uName == args.targetUsername then
                targetPlayer = p
                break
            end
        end
    end

    if not targetPlayer or targetPlayer == attacker or targetPlayer:isDead() then
        return
    end

    local maxDist = (tonumber(Vampirism.FEED_PLAYER_MAX_DISTANCE) or 1.8) + 1.2
    local dist = attacker:DistTo(targetPlayer)
    if dist > maxDist then
        return
    end

    -- Efectos en el atacante (Vampiro)
    local stats = Try(function()
        return attacker.getStats and attacker:getStats() or nil
    end)

    if stats and CharacterStat then
        if CharacterStat.THIRST then
            local reduction = tonumber(Vampirism.FEED_PLAYER_THIRST_REDUCTION) or 0.8
            stats:remove(CharacterStat.THIRST, reduction)
        end
        if CharacterStat.HUNGER then
            stats:set(CharacterStat.HUNGER, 0.0)
        end
        if CharacterStat.STRESS then
            stats:remove(CharacterStat.STRESS, 0.5)
        end
        if CharacterStat.FATIGUE then
            stats:remove(CharacterStat.FATIGUE, 0.2)
        end
    end

    SendToClient(attacker, "FeedOnPlayerSuccess", {})

    -- Efectos en la víctima
    local body = Try(function()
        return targetPlayer.getBodyDamage and targetPlayer:getBodyDamage() or nil
    end)

    if body then
        local neck = Try(function()
            if BodyPartType and BodyPartType.Neck then
                return body:getBodyPart(BodyPartType.Neck)
            end
            return nil
        end)

        if neck then
            local dmg = tonumber(Vampirism.FEED_PLAYER_DAMAGE) or 25.0
            local bleedTime = tonumber(Vampirism.FEED_PLAYER_BLEED_TIME) or 20.0
            neck:AddDamage(dmg)
            neck:setBleeding(true)
            neck:setBleedingTime(bleedTime)
            neck:setAdditionalPain(35.0)
        else
            body:ReduceGeneralHealth(25.0)
        end

        if sendDamage and isServer() then
            pcall(sendDamage, targetPlayer)
        end
    end

    local victimStats = Try(function()
        return targetPlayer.getStats and targetPlayer:getStats() or nil
    end)

    if victimStats and CharacterStat then
        if CharacterStat.PANIC then
            victimStats:add(CharacterStat.PANIC, 50.0)
        end
        if CharacterStat.STRESS then
            victimStats:add(CharacterStat.STRESS, 0.5)
        end
    end

    SendToClient(targetPlayer, "BittenByVampire", {})
end

function Vampirism.HandleFeedOnCorpse(attacker, args)
    if not attacker or not ShouldRunServerLogic() then
        return
    end

    if attacker:isDead() or not Vampirism.HasVampireTrait(attacker) then
        return
    end

    args = args or {}
    if not args.x or not args.y or not args.z then
        return
    end

    local cell = Try(getCell)
    if not cell then
        return
    end

    local sq = cell:getGridSquare(args.x, args.y, args.z)
    if not sq then
        return
    end

    local corpse = nil
    local deadBodies = sq:getDeadBodys()
    if deadBodies and deadBodies.size and deadBodies:size() > 0 then
        corpse = deadBodies:get(0)
    end
    if not corpse then
        corpse = sq:getDeadBody()
    end

    if not corpse then
        return
    end

    local maxDist = (tonumber(Vampirism.FEED_CORPSE_MAX_DISTANCE) or 1.8) + 1.2
    local dist = attacker:DistTo(args.x, args.y)
    if dist > maxDist then
        return
    end

    local modData = corpse:getModData()
    if not modData then
        return
    end

    if modData.vampireBloodCharges == nil then
        modData.vampireBloodCharges = tonumber(Vampirism.FEED_CORPSE_MAX_CHARGES) or 2
    end

    if modData.vampireBloodCharges <= 0 then
        return
    end

    modData.vampireBloodCharges = modData.vampireBloodCharges - 1

    -- Efectos en el vampiro
    local stats = Try(function()
        return attacker.getStats and attacker:getStats() or nil
    end)

    if stats and CharacterStat then
        if CharacterStat.THIRST then
            local reduction = tonumber(Vampirism.FEED_CORPSE_THIRST_REDUCTION) or 0.4
            stats:remove(CharacterStat.THIRST, reduction)
        end
        if CharacterStat.HUNGER then
            stats:set(CharacterStat.HUNGER, 0.0)
        end

        -- Penalizaciones por sangre fría/coagulada
        if Vampirism.CORPSE_BLOOD_PENALTY_ENABLED then
            if CharacterStat.FOOD_SICKNESS then
                local sickAmount = tonumber(Vampirism.CORPSE_BLOOD_SICKNESS_AMOUNT) or 8.0
                stats:add(CharacterStat.FOOD_SICKNESS, sickAmount)
            end
            if CharacterStat.UNHAPPINESS then
                local unhappAmount = tonumber(Vampirism.CORPSE_BLOOD_UNHAPPINESS) or 10.0
                stats:add(CharacterStat.UNHAPPINESS, unhappAmount)
            end
        end
    end

    SendToClient(attacker, "FeedOnCorpseSuccess", {})
end

function Vampirism.CheckSunDamage()
    local players = GetAllPlayers()

    for _, player in ipairs(players) do
        Vampirism.EvaluateSunDamageForPlayer(player)
    end
end

-- TICK PRINCIPAL

Events.OnTick.Add(function()
    if not ShouldRunServerLogic() then
        return
    end

    Vampirism.currentTick = (Vampirism.currentTick or 0) + 1

    local interval = tonumber(Vampirism.SUN_DAMAGE_INTERVAL) or 2
    local ticksPerCheck = math.max(1, interval * 60)

    if Vampirism.currentTick - (Vampirism.lastDamageTick or 0) < ticksPerCheck then
        return
    end

    Vampirism.lastDamageTick = Vampirism.currentTick
    Vampirism.CheckSunDamage()
end)

-- ACTUALIZACIÓN CONTINUA DE JUGADOR (Mantiene speedMod y stats)

if Events.OnPlayerUpdate then
    Events.OnPlayerUpdate.Add(function(player)
        if not player or not ShouldRunServerLogic() then
            return
        end

        local state = GetPlayerState(player)
        if state and state.nightEmpowered and Vampirism.NIGHT_BUFFS_ENABLED then
            local speedMult = tonumber(Vampirism.NIGHT_SPEED_MULTIPLIER) or 1.25
            if player.setSpeedMod then
                pcall(player.setSpeedMod, player, speedMult)
            end
        end

        if Vampirism.HasVampireTrait(player) then
            Vampirism.ManageVampireStats(player)
        end
    end)
end

-- COMANDOS CLIENTE -> SERVIDOR

if Events.OnClientCommand then
    Events.OnClientCommand.Add(function(module, command, player, args)
        if module ~= "Vampirism" then
            return
        end

        if command == "FeedOnPlayer" then
            Vampirism.HandleFeedOnPlayer(player, args)
        elseif command == "FeedOnCorpse" then
            Vampirism.HandleFeedOnCorpse(player, args)
        end
    end)
end

-- LIMPIEZA DE ESTADO

if Events.OnPlayerDeath then
    Events.OnPlayerDeath.Add(function(player)
        if not player then
            return
        end

        local state = GetPlayerState(player)
        if state then
            state.burning = false
            state.lastWarningTick = 0
        end

        if Vampirism.AUTO_EXTINGUISH_IN_SHADE then
            ExtinguishCharacter(player)
        end

        Vampirism.RemoveNightEmpowerment(player, true)
        SendToClient(player, "SunDamageStop", {})
    end)
end

if Events.OnDisconnect then
    Events.OnDisconnect.Add(function(player)
        if not player then
            return
        end

        local state = GetPlayerState(player)
        if state then
            state.burning = false
            state.lastWarningTick = 0
        end

        if Vampirism.AUTO_EXTINGUISH_IN_SHADE then
            ExtinguishCharacter(player)
        end

        Vampirism.RemoveNightEmpowerment(player, true)
    end)
end

if Events.OnCreatePlayer then
    Events.OnCreatePlayer.Add(function(playerIndex, player)
        if player then
            Vampirism.EnsureVampireTraits(player)
            if Vampirism.HasVampireTrait(player) then
                Vampirism.ManageVampireStats(player)
            end
        end
    end)
end

print("[Vampirism] server Lua loaded successfully.")