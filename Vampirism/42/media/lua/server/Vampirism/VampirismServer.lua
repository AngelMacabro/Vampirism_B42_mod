require("Vampirism.Vampirism")

-- ESTADO POR JUGADOR
Vampirism.PlayerState = Vampirism.PlayerState or {}

local function GetPlayerKey(player)
    if not player then return nil end

    if player.getOnlineID then
        local onlineID = player:getOnlineID()
        if onlineID ~= -1 and onlineID ~= nil then
            return "online_" .. tostring(onlineID)
        end
    end

    if player.getPlayerNum then
        return "local_" .. tostring(player:getPlayerNum())
    end

    return tostring(player)
end

local function GetPlayerState(player)
    local key = GetPlayerKey(player)
    if not key then return nil end

    if not Vampirism.PlayerState[key] then
        Vampirism.PlayerState[key] = {
            receivingDamage = false
        }
    end

    return Vampirism.PlayerState[key]
end

-- COMPROBACIÓN PERIÓDICA (SÓLO EJECUTADA POR EL SERVIDOR/HOST)
Events.OnTick.Add(function()
    -- Asegurar que solo el servidor/host ejecute la lógica global
    -- isServer() funciona tanto en singleplayer como en servidor dedicado
    if not isServer() then return end

    Vampirism.currentTick = Vampirism.currentTick + 1

    local interval = Vampirism.SUN_DAMAGE_INTERVAL or 2
    local ticksPerCheck = interval * 60

    if Vampirism.currentTick - Vampirism.lastDamageTick < ticksPerCheck then
        return
    end

    Vampirism.lastDamageTick = Vampirism.currentTick
    Vampirism.CheckSunDamage()
end)

-- COMPROBAR DAÑO SOLAR
function Vampirism.CheckSunDamage()
    if not Vampirism.SUN_DAMAGE_ENABLED then
        return
    end

    -- Si es una partida local / singleplayer / host cooperativo
    if not isServer() then
        local playerCount = getNumActivePlayers()
        for i = 0, playerCount - 1 do
            local player = getSpecificPlayer(i)
            if player and not player:isDead() then
                Vampirism.EvaluateSunDamageForPlayer(player)
            end
        end
    else
        -- Servidor Dedicado puro
        local players = getOnlinePlayers()
        if players then
            for i = 0, players:size() - 1 do
                local player = players:get(i)
                if player and not player:isDead() then
                    Vampirism.EvaluateSunDamageForPlayer(player)
                end
            end
        end
    end
end

-- EVALUAR JUGADOR
function Vampirism.EvaluateSunDamageForPlayer(player)
    if not player then return end

    -- 1. Trait vampiro
    if not Vampirism.HasVampireTrait(player) then
        Vampirism.StopSunDamage(player)
        return
    end

    -- 2. Exterior
    if not Vampirism.IsOutdoors(player) then
        Vampirism.StopSunDamage(player)
        return
    end

    -- 3. Día
    if not Vampirism.IsDaytime() then
        Vampirism.StopSunDamage(player)
        return
    end

    -- 4. Aplicar daño
    Vampirism.ApplySunDamage(player)
end

-- DETECTAR TRAIT VAMPIRO (B42 READY)
function Vampirism.HasVampireTrait(player)
    if not player then return false end

    if player.hasTrait and CharacterTrait then
        local vampireTrait = nil

        if CharacterTrait.get then
            if ResourceLocation and ResourceLocation.FromString then
                local resLocation = ResourceLocation.FromString(Vampirism.VAMPIRE_TRAIT)
                vampireTrait = CharacterTrait.get(resLocation)
            else
                vampireTrait = CharacterTrait.get(Vampirism.VAMPIRE_TRAIT)
            end
        end

        if vampireTrait then
            return player:hasTrait(vampireTrait)
        end
    end

    if player.getTraits then
        local traits = player:getTraits()
        for i = 0, traits:size() - 1 do
            if traits:get(i) == Vampirism.VAMPIRE_TRAIT then
                return true
            end
        end
    end
    return false
end

-- COMPROBAR SI ESTÁ AL AIRE LIBRE
function Vampirism.IsOutdoors(player)
    if not player then return false end

    if player.getVehicle then
        if player:getVehicle() ~= nil then
            return false
        end
    end

    if player.isOutside then
        return player:isOutside()
    end

    local square = player:getSquare()
    if square and square.isOutside then
        return square:isOutside()
    end

    return false
end

-- COMPROBAR SI ES DE DÍA
function Vampirism.IsDaytime()
    local climate = getClimateManager()

    if climate and climate.getDayLightStrength then
        return climate:getDayLightStrength() > 0.1
    end

    local gameTime = getGameTime()
    if not gameTime then return false end

    local hour = gameTime:getHour()
    local startHour = Vampirism.SUN_DAMAGE_START_HOUR or 6
    local endHour = Vampirism.SUN_DAMAGE_END_HOUR or 20

    return hour >= startHour and hour < endHour
end

-- APLICAR DAÑO SOLAR (AÑADIDA RED MULTIJUGADOR)
function Vampirism.ApplySunDamage(player)
    if not player or player:isDead() then return end

    local state = GetPlayerState(player)
    local wasAlreadyDamage = false
    if state then
        wasAlreadyDamage = state.receivingDamage
        state.receivingDamage = true
    end

    -- Protección: Si ya estaba recibiendo daño, no volver a aplicar
    if wasAlreadyDamage then
        return
    end

    -- Sincronización por Red (Enviar comando al Cliente)
    if isServer() then
        local onlineID = player.getOnlineID and player:getOnlineID() or -1
        local args = { playerID = onlineID }
        -- Envía la señal al cliente específico para activar los efectos visuales
        sendServerCommand(player, "Vampirism", "SunDamageStart", args)
    end

    -- Salud
    local bodyDamage = player:getBodyDamage()
    if bodyDamage then
        local damageAmount = Vampirism.SUN_DAMAGE_AMOUNT or 1
        bodyDamage:AddGeneralHealth(-damageAmount)
    end

    -- Dolor
    local stats = player:getStats()
    if stats then
        local currentPain = stats:getPain()
        stats:setPain(math.min(100, currentPain + 5))
    end

    -- Feedback local/texto flotante (con cooldown)
    if not Vampirism.lastWarningTime then
        Vampirism.lastWarningTime = {}
    end
    
    local playerKey = GetPlayerKey(player)
    local currentTime = getGameTime() and getGameTime():getWorldAge() or 0
    local warningCooldown = Vampirism.SUN_WARNING_COOLDOWN or 30 -- segundos
    
    if not Vampirism.lastWarningTime[playerKey] or 
       (currentTime - Vampirism.lastWarningTime[playerKey]) > warningCooldown then
        Vampirism.lastWarningTime[playerKey] = currentTime
        
        if HaloTextHelper and HaloTextHelper.addText then
            HaloTextHelper.addText(player, getText("UI_Vampirism_SunWarning"), 255, 100, 0)
        elseif player.Say then
            player:Say(getText("UI_Vampirism_SunWarning"))
        end
    end
end

-- DETENER DAÑO SOLAR (AÑADIDA RED MULTIJUGADOR)
function Vampirism.StopSunDamage(player)
    if not player then return end

    local state = GetPlayerState(player)
    if not state or not state.receivingDamage then
        return
    end

    state.receivingDamage = false

    -- Sincronización por Red (Enviar comando al Cliente)
    if isServer() then
        local onlineID = player.getOnlineID and player:getOnlineID() or -1
        local args = { playerID = onlineID }
        -- Envía la señal al cliente para apagar los efectos visuales
        sendServerCommand(player, "Vampirism", "SunDamageStop", args)
    end

    -- Feedback local/texto flotante
    if HaloTextHelper and HaloTextHelper.addText then
        HaloTextHelper.addText(player, getText("UI_Vampirism_SunProtected"), 100, 255, 100)
    elseif player.Say then
        player:Say(getText("UI_Vampirism_SunProtected"))
    end
end

-- INICIALIZACIÓN
print("[Vampirism] server Lua loaded successfully.")
