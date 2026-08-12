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

    -- Si es el jugador local en host/singleplayer, podemos intentar mostrarlo directamente.
    if IsLocalNonDedicatedPlayer(player) then
        if HaloTextHelper and HaloTextHelper.addText then
            local ok = pcall(HaloTextHelper.addText, player, text, r, g, b)
            if ok then
                return
            end
        end

        if player.Say then
            local ok = pcall(player.Say, player, text)
            if ok then
                return
            end
        end
    end

    -- Para clientes remotos, enviar comando.
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
            lastWarningTick = 0
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

-- ============================================================
-- TRAITS
-- Build 42.20.x
-- ============================================================

function Vampirism.HasVampireTrait(player)
    if not player then
        return false
    end

    local traitId = Vampirism.VAMPIRE_TRAIT

    if not traitId then
        return false
    end

    if not ResourceLocation or not ResourceLocation.of then
        print("[Vampirism] ERROR: ResourceLocation.of is unavailable")
        return false
    end

    if not CharacterTrait or not CharacterTrait.get then
        print("[Vampirism] ERROR: CharacterTrait.get is unavailable")
        return false
    end

    -- Build 42.20.2:
    -- CharacterTrait.get() requiere un ResourceLocation.
    local resourceLocation = nil

    local okLocation, resultLocation = pcall(function()
        return ResourceLocation.of(traitId)
    end)

    if not okLocation or not resultLocation then
        print(
            "[Vampirism] ERROR: Could not create ResourceLocation: " ..
            tostring(traitId)
        )
        return false
    end

    resourceLocation = resultLocation

    -- Obtener el CharacterTrait registrado.
    local traitObj = nil

    local okTrait, resultTrait = pcall(function()
        return CharacterTrait.get(resourceLocation)
    end)

    if not okTrait then
        print(
            "[Vampirism] ERROR: CharacterTrait.get failed: " ..
            tostring(traitId)
        )
        return false
    end

    traitObj = resultTrait

    if not traitObj then
        print(
            "[Vampirism] ERROR: CharacterTrait not registered: " ..
            tostring(traitId)
        )
        return false
    end

    -- Build 42: hasTrait() utiliza CharacterTrait.
    if not player.hasTrait then
        print("[Vampirism] ERROR: player.hasTrait is unavailable")
        return false
    end

    local okHasTrait, hasTrait = pcall(function()
        return player:hasTrait(traitObj)
    end)

    if not okHasTrait then
        print(
            "[Vampirism] ERROR: player:hasTrait() failed for " ..
            tostring(traitId)
        )
        return false
    end
    print(
        "[Vampirism DEBUG] Vampire trait = " ..
        tostring(hasTrait)
    )
    return hasTrait == true
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

function Vampirism.IsDaytime()
    local climate = Try(getClimateManager)

    if climate and climate.getDayLightStrength then
        local light = Try(function()
            return climate:getDayLightStrength()
        end)

        if light ~= nil then
            return light > 0.1
        end
    end

    local gameTime = Try(getGameTime)

    if gameTime and gameTime.getHour then
        local hour = Try(function()
            return gameTime:getHour()
        end) or 0

        local minute = Try(function()
            return gameTime.getMinutes and gameTime:getMinutes() or 0
        end) or 0

        local h = hour + (minute / 60)

        local startHour = tonumber(Vampirism.SUN_DAMAGE_START_HOUR) or 6
        local endHour = tonumber(Vampirism.SUN_DAMAGE_END_HOUR) or 20

        return h >= startHour and h < endHour
    end

    return false
end

-- DAÑO SOLAR

function Vampirism.ApplySunDamage(player)
    print("[Vampirism DEBUG] >>> APPLY SUN DAMAGE <<<")
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

    -- Solo avisamos al cliente una vez cuando empieza el quemado.
    if not state.burning then
        state.burning = true
        SendToClient(player, "SunDamageStart", {})
    end

    -- Salud.
    local body = Try(function()
        return player.getBodyDamage and player:getBodyDamage() or nil
    end)

    local damageAmount = tonumber(Vampirism.SUN_DAMAGE_AMOUNT) or 1
    print("[Vampirism DEBUG] BodyDamage = " .. tostring(body))
    print("[Vampirism DEBUG] Damage amount = " .. tostring(damageAmount))

    if body then
        if body.AddGeneralHealth then
            pcall(body.AddGeneralHealth, body, -damageAmount)
        elseif body.addGeneralHealth then
            pcall(body.addGeneralHealth, body, -damageAmount)
        end
    end

    -- Dolor.
    local painAmount = tonumber(Vampirism.SUN_PAIN_AMOUNT) or 5
    local painChanged = false

    if body and body.getPain and body.setPain then
        local pain = Try(function()
            return body:getPain()
        end)

        if pain ~= nil then
            pcall(body.setPain, body, math.min(100, pain + painAmount))
            painChanged = true
        end
    end

    if not painChanged then
        local stats = Try(function()
            return player.getStats and player:getStats() or nil
        end)

        if stats and stats.getPain and stats.setPain then
            local pain = Try(function()
                return stats:getPain()
            end)

            if pain ~= nil then
                pcall(stats.setPain, stats, math.min(100, pain + painAmount))
            end
        end
    end

    -- Aviso periódico con cooldown.
    local warningCooldownTicks = (tonumber(Vampirism.SUN_WARNING_COOLDOWN) or 30) * 60

    if not state.lastWarningTick or (Vampirism.currentTick - state.lastWarningTick) >= warningCooldownTicks then
        state.lastWarningTick = Vampirism.currentTick

        local msg = GetTextSafe(
            "UI_Vampirism_SunWarning",
            "The sun is burning you!"
        )

        Vampirism.SendPlayerMessage(player, msg, 255, 100, 0)
    end
end

function Vampirism.StopSunDamage(player, silent)
    if not player then
        return
    end

    local state = GetPlayerState(player)
    if not state or not state.burning then
        return
    end

    state.burning = false

    SendToClient(player, "SunDamageStop", {})

    if not silent then
        local msg = GetTextSafe(
            "UI_Vampirism_SunProtected",
            "You are safe from the sun."
        )

        Vampirism.SendPlayerMessage(player, msg, 100, 255, 100)
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
        return
    end

    print("[Vampirism DEBUG] Trait = " .. tostring(Vampirism.HasVampireTrait(player)))
    print("[Vampirism DEBUG] Outdoors = " .. tostring(Vampirism.IsOutdoors(player)))
    print("[Vampirism DEBUG] Daytime = " .. tostring(Vampirism.IsDaytime()))

    if not Vampirism.HasVampireTrait(player) then
        Vampirism.StopSunDamage(player)
        return
    end

    if not Vampirism.IsOutdoors(player) then
        Vampirism.StopSunDamage(player)
        return
    end

    if not Vampirism.IsDaytime() then
        Vampirism.StopSunDamage(player)
        return
    end

    Vampirism.ApplySunDamage(player)
end

function Vampirism.CheckSunDamage()
    local players = GetAllPlayers()

    if not Vampirism.SUN_DAMAGE_ENABLED then
        for _, player in ipairs(players) do
            Vampirism.StopSunDamage(player, true)
        end
        return
    end

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

        SendToClient(player, "SunDamageStop", {})
    end)
end

if Events.OnPlayerDisconnect then
    Events.OnPlayerDisconnect.Add(function(player)
        if not player then
            return
        end

        local state = GetPlayerState(player)
        if state then
            state.burning = false
            state.lastWarningTick = 0
        end
    end)
end

print("[Vampirism] server Lua loaded successfully.")