-- VampirismClient.lua
-- Project Zomboid Build 42.20.2
-- Cliente visual para el sistema de vampirismo.

-- Si tu shared ya se carga automáticamente, puedes quitar el require.
-- En PZ normalmente se usa ruta con "/", no con ".".
require("Vampirism/Vampirism")
require("Vampirism/VampirismActionsHook")
require("TimedActions/ISFeedOnPlayerAction")
require("TimedActions/ISFeedOnCorpseAction")

Vampirism = Vampirism or {}

------------------------------------------------------------
-- ESTADO VISUAL
------------------------------------------------------------

Vampirism.isReceivingDamage = false

Vampirism.sunDamageOverlayAlpha = 0
Vampirism.warningAlpha = 0

Vampirism.toastText = nil
Vampirism.toastAlpha = 0

Vampirism.lastRenderMs = nil

------------------------------------------------------------
-- UTILIDADES
------------------------------------------------------------

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

local function GetLocalPlayer()
    if getPlayer then
        local ok, player = pcall(getPlayer)
        if ok and player then
            return player
        end
    end

    if getSpecificPlayer then
        local ok, player = pcall(getSpecificPlayer, 0)
        if ok and player then
            return player
        end
    end

    return nil
end

local function GetTimeMs()
    if getTimestampMs then
        local ok, ms = pcall(getTimestampMs)
        if ok and ms then
            return ms
        end
    end

    if os and os.clock then
        local ok, sec = pcall(os.clock)
        if ok and sec then
            return sec * 1000
        end
    end

    return nil
end

------------------------------------------------------------
-- VALIDACIÓN DE COMANDOS
------------------------------------------------------------

local function IsCommandForLocalPlayer(args)
    -- Si el servidor usa sendServerCommand(player, ...),
    -- el comando ya está dirigido a este cliente.
    --
    -- Si args.playerID no existe, se acepta.
    if not args or args.playerID == nil then
        return true
    end

    local localPlayer = GetLocalPlayer()

    -- Si todavía no hay jugador local, aceptamos el estado igualmente.
    -- Puede ocurrir durante carga/conexión.
    if not localPlayer then
        return true
    end

    local myOnlineID = Try(function()
        return localPlayer.getOnlineID and localPlayer:getOnlineID() or nil
    end)

    if myOnlineID == nil then
        return true
    end

    -- Singleplayer/host local suele usar -1.
    if args.playerID == -1 and myOnlineID == -1 then
        return true
    end

    return args.playerID == myOnlineID
end

------------------------------------------------------------
-- ACTUALIZACIÓN VISUAL
------------------------------------------------------------

function Vampirism.UpdateSunDamageVisuals()
    local now = GetTimeMs()
    local dt = 1 / 60

    if now and Vampirism.lastRenderMs then
        local diff = (now - Vampirism.lastRenderMs) / 1000

        -- Limitamos dt para evitar saltos enormes si hubo lag o carga.
        if diff > 0 and diff < 0.25 then
            dt = diff
        end
    end

    if now then
        Vampirism.lastRenderMs = now
    end

    if Vampirism.isReceivingDamage then
        -- Mantener animación de fuego sobre el personaje local
        local localPlayer = GetLocalPlayer()
        if localPlayer then
            local isOnFire = Try(function() return localPlayer.isOnFire and localPlayer:isOnFire() or false end)
            if not isOnFire then
                if localPlayer.SetOnFire then
                    pcall(localPlayer.SetOnFire, localPlayer)
                elseif localPlayer.setOnFire then
                    pcall(localPlayer.setOnFire, localPlayer, true)
                end
            end
        end

        -- Subida gradual.
        -- 0.6 por segundo => tarda ~1 segundo en llegar a 0.6.
        Vampirism.sunDamageOverlayAlpha = math.min(
            0.6,
            Vampirism.sunDamageOverlayAlpha + (0.6 * dt)
        )

        -- 1.2 por segundo => tarda ~0.83 segundos en llegar a 1.0.
        Vampirism.warningAlpha = math.min(
            1.0,
            Vampirism.warningAlpha + (1.2 * dt)
        )
    else
        -- Bajada gradual.
        Vampirism.sunDamageOverlayAlpha = math.max(
            0.0,
            Vampirism.sunDamageOverlayAlpha - (0.4 * dt)
        )

        Vampirism.warningAlpha = math.max(
            0.0,
            Vampirism.warningAlpha - (0.8 * dt)
        )
    end

    -- Fade out de mensajes toast.
    if Vampirism.toastAlpha > 0 then
        Vampirism.toastAlpha = math.max(
            0.0,
            Vampirism.toastAlpha - (0.5 * dt)
        )
    end
end

Events.OnRenderTick.Add(function()
    Vampirism.UpdateSunDamageVisuals()
end)

------------------------------------------------------------
-- COMANDOS SERVER -> CLIENT
------------------------------------------------------------

Events.OnServerCommand.Add(function(module, command, args)
    if module ~= "Vampirism" then
        return
    end

    args = args or {}

    if not IsCommandForLocalPlayer(args) then
        return
    end

    if command == "SunDamageStart" then
        Vampirism.isReceivingDamage = true
        local localPlayer = GetLocalPlayer()
        if localPlayer then
            if localPlayer.SetOnFire then
                pcall(localPlayer.SetOnFire, localPlayer)
            elseif localPlayer.setOnFire then
                pcall(localPlayer.setOnFire, localPlayer, true)
            end
        end
        return
    end

    if command == "SunDamageStop" then
        Vampirism.isReceivingDamage = false
        local localPlayer = GetLocalPlayer()
        if localPlayer then
            if localPlayer.StopBurning then
                pcall(localPlayer.StopBurning, localPlayer)
            end
            if localPlayer.setOnFire then
                pcall(localPlayer.setOnFire, localPlayer, false)
            end
        end
        return
    end

    if command == "NightEmpowerStart" then
        local localPlayer = GetLocalPlayer()
        local msg = GetTextSafe(
            "UI_Vampirism_NightEmpowerStart",
            "The night empowers your body with speed and strength."
        )

        if localPlayer then
            local busy = false
            if ISTimedActionQueue and ISTimedActionQueue.isPlayerDoingAction then
                local okBusy, resBusy = pcall(ISTimedActionQueue.isPlayerDoingAction, ISTimedActionQueue, localPlayer)
                if okBusy then
                    busy = resBusy == true
                end
            end
            if not busy and localPlayer.setVariable and localPlayer.reportEvent then
                pcall(localPlayer.setVariable, localPlayer, "Ext", "TiredStretch")
                pcall(localPlayer.reportEvent, localPlayer, "EventDoExt")
            end
        end

        if localPlayer and HaloTextHelper and HaloTextHelper.addText then
            pcall(HaloTextHelper.addText, localPlayer, msg, 150, 100, 255)
        else
            Vampirism.toastText = msg
            Vampirism.toastAlpha = 1.0
        end
        return
    end

    if command == "NightEmpowerStop" then
        local localPlayer = GetLocalPlayer()
        local msg = GetTextSafe(
            "UI_Vampirism_NightEmpowerStop",
            "The morning light fades your nocturnal power."
        )

        if localPlayer and HaloTextHelper and HaloTextHelper.addText then
            pcall(HaloTextHelper.addText, localPlayer, msg, 200, 200, 150)
        else
            Vampirism.toastText = msg
            Vampirism.toastAlpha = 1.0
        end
        return
    end

    if command == "FeedOnPlayerSuccess" then
        local localPlayer = GetLocalPlayer()
        local msg = GetTextSafe(
            "UI_Vampirism_FeedPlayerSuccess",
            "You satisfy your thirst with warm, living blood."
        )

        if localPlayer and HaloTextHelper and HaloTextHelper.addText then
            pcall(HaloTextHelper.addText, localPlayer, msg, 220, 30, 30)
        else
            Vampirism.toastText = msg
            Vampirism.toastAlpha = 1.0
        end
        return
    end

    if command == "BittenByVampire" then
        local localPlayer = GetLocalPlayer()
        local msg = GetTextSafe(
            "UI_Vampirism_BittenByVampire",
            "A vampire is tearing into your neck!"
        )

        if localPlayer then
            if localPlayer.setVariable and localPlayer.reportEvent then
                pcall(localPlayer.setVariable, localPlayer, "Ext", "PainHead1")
                pcall(localPlayer.reportEvent, localPlayer, "EventDoExt")
            end
            if localPlayer.playSound then
                local isFemale = false
                if localPlayer.isFemale then
                    local okFemale, female = pcall(localPlayer.isFemale, localPlayer)
                    if okFemale then
                        isFemale = female == true
                    end
                end
                local soundName = isFemale and "VoiceFemalePain" or "VoiceMalePain"
                pcall(localPlayer.playSound, localPlayer, soundName)
            end
        end

        if localPlayer and HaloTextHelper and HaloTextHelper.addText then
            pcall(HaloTextHelper.addText, localPlayer, msg, 255, 20, 20)
        else
            Vampirism.toastText = msg
            Vampirism.toastAlpha = 1.0
        end
        return
    end

    if command == "FeedOnCorpseSuccess" then
        local localPlayer = GetLocalPlayer()
        local msg = GetTextSafe(
            "UI_Vampirism_FeedCorpseSuccess",
            "The cold, stagnant blood quenches your thirst, but sickens your stomach."
        )

        if localPlayer and HaloTextHelper and HaloTextHelper.addText then
            pcall(HaloTextHelper.addText, localPlayer, msg, 180, 100, 100)
        else
            Vampirism.toastText = msg
            Vampirism.toastAlpha = 1.0
        end
        return
    end

    if command == "WaterRejected" then
        local localPlayer = GetLocalPlayer()
        local msg = GetTextSafe(
            "UI_Vampirism_WaterRejected",
            "It feels like sand in my throat, I can't drink this..."
        )

        if localPlayer then
            if localPlayer.Say then
                pcall(localPlayer.Say, localPlayer, msg)
            end

            if HaloTextHelper and HaloTextHelper.addText then
                pcall(HaloTextHelper.addText, localPlayer, msg, 100, 180, 255)
            else
                Vampirism.toastText = msg
                Vampirism.toastAlpha = 1.0
            end
        end
        return
    end

    if command == "ShowMessage" then
        local localPlayer = GetLocalPlayer()

        if args.text and args.text ~= "" and localPlayer then
            -- Bocadillo de diálogo sobre la cabeza del personaje
            if localPlayer.Say then
                pcall(localPlayer.Say, localPlayer, args.text)
            end

            -- Si HaloTextHelper funciona en esta build, úsalo.
            if HaloTextHelper and HaloTextHelper.addText then
                pcall(
                    HaloTextHelper.addText,
                    localPlayer,
                    args.text,
                    args.r or 255,
                    args.g or 255,
                    args.b or 255
                )
            else
                -- Fallback: mensaje simple dibujado por este mismo cliente.
                Vampirism.toastText = args.text
                Vampirism.toastAlpha = 1.0
            end
        end

        return
    end
end)

------------------------------------------------------------
-- INTERACCIÓN DE ALIMENTACIÓN Y MENÚ CONTEXTUAL
------------------------------------------------------------

function Vampirism.StartFeedOnPlayer(targetPlayer, localPlayer)
    if not targetPlayer or not localPlayer then
        return
    end

    if luautils and luautils.walkAdj then
        pcall(luautils.walkAdj, localPlayer, targetPlayer:getSquare())
    end

    if ISTimedActionQueue and ISTimedActionQueue.add then
        ISTimedActionQueue.add(ISFeedOnPlayerAction:new(localPlayer, targetPlayer))
    end
end

function Vampirism.StartFeedOnCorpse(corpse, localPlayer)
    if not corpse or not localPlayer then
        return
    end

    local sq = corpse:getSquare()
    if sq and luautils and luautils.walkAdj then
        pcall(luautils.walkAdj, localPlayer, sq)
    end

    if ISTimedActionQueue and ISTimedActionQueue.add then
        ISTimedActionQueue.add(ISFeedOnCorpseAction:new(localPlayer, corpse))
    end
end

function Vampirism.OnFillWorldObjectContextMenu(playerNum, context, worldobjects, test)
    if test then
        return
    end

    local localPlayer = Try(function()
        return getSpecificPlayer(playerNum)
    end)

    if not localPlayer or not Vampirism.HasVampireTrait(localPlayer) then
        return
    end

    if localPlayer:isDead() then
        return
    end

    local foundPlayers = {}
    local foundCorpses = {}

    -- 1. Detección directa de cadáver mediante IsoObjectPicker
    local pickedCorpse = nil
    if IsoObjectPicker and IsoObjectPicker.Instance and IsoObjectPicker.Instance.PickCorpse then
        local mx = (getMouseXScaled and getMouseXScaled()) or (getMouseX and getMouseX()) or 0
        local my = (getMouseYScaled and getMouseYScaled()) or (getMouseY and getMouseY()) or 0
        local okPick, corpse = pcall(IsoObjectPicker.Instance.PickCorpse, IsoObjectPicker.Instance, mx, my)
        if okPick and corpse then
            foundCorpses[corpse] = true
        end
    end

    -- 2. Recorrer worldobjects y sus casillas asociadas
    if worldobjects then
        for _, obj in ipairs(worldobjects) do
            if obj then
                if instanceof(obj, "IsoDeadBody") then
                    foundCorpses[obj] = true
                end

                local sq = (obj.getSquare and obj:getSquare()) or nil
                if sq then
                    -- Buscar jugadores vivos en la casilla
                    local movingObjs = sq:getMovingObjects()
                    if movingObjs and movingObjs.size then
                        for i = 0, movingObjs:size() - 1 do
                            local mObj = movingObjs:get(i)
                            if mObj and instanceof(mObj, "IsoPlayer") and mObj ~= localPlayer and not mObj:isDead() then
                                foundPlayers[mObj] = true
                            end
                        end
                    end

                    -- Buscar cadáveres en la casilla
                    local deadBodies = sq:getDeadBodys()
                    if deadBodies and deadBodies.size then
                        for i = 0, deadBodies:size() - 1 do
                            local body = deadBodies:get(i)
                            if body then
                                foundCorpses[body] = true
                            end
                        end
                    end
                    
                    local singleBody = sq:getDeadBody()
                    if singleBody then
                        foundCorpses[singleBody] = true
                    end
                end
            end
        end
    end

    -- 3. Búsqueda en casillas adyacentes al jugador local
    local pSq = localPlayer:getSquare()
    if pSq then
        local cell = pSq:getCell()
        local px, py, pz = pSq:getX(), pSq:getY(), pSq:getZ()
        if cell then
            for dx = -1, 1 do
                for dy = -1, 1 do
                    local sq = cell:getGridSquare(px + dx, py + dy, pz)
                    if sq then
                        local deadBodies = sq:getDeadBodys()
                        if deadBodies and deadBodies.size then
                            for i = 0, deadBodies:size() - 1 do
                                local body = deadBodies:get(i)
                                if body then
                                    foundCorpses[body] = true
                                end
                            end
                        end
                        local singleBody = sq:getDeadBody()
                        if singleBody then
                            foundCorpses[singleBody] = true
                        end
                    end
                end
            end
        end
    end

    -- Opción de alimentarse de jugador vivo (Mecánica principal)
    if Vampirism.FEED_PLAYER_ENABLED ~= false then
        for targetPlayer, _ in pairs(foundPlayers) do
            local name = targetPlayer:getUsername() or "Survivor"
            local menuText = GetTextSafe("ContextMenu_VampireFeedOnPlayer", "Feed on Player") .. " (" .. name .. ")"
            context:addOption(menuText, targetPlayer, Vampirism.StartFeedOnPlayer, localPlayer)
        end
    end

    -- Opción de alimentarse de cadáver (Mecánica provisional)
    if Vampirism.FEED_CORPSE_ENABLED ~= false then
        for corpse, _ in pairs(foundCorpses) do
            local modData = corpse:getModData()
            local charges = modData and modData.vampireBloodCharges
            
            if charges ~= nil and charges <= 0 then
                local drainedText = GetTextSafe("ContextMenu_VampireCorpseDrained", "Corpse Drained of Blood")
                local opt = context:addOption(drainedText, nil, nil)
                opt.notAvailable = true
            else
                local corpseText = GetTextSafe("ContextMenu_VampireFeedOnCorpse", "Feed on Corpse")
                context:addOption(corpseText, corpse, Vampirism.StartFeedOnCorpse, localPlayer)
            end
        end
    end
end

if Events.OnFillWorldObjectContextMenu then
    Events.OnFillWorldObjectContextMenu.Add(Vampirism.OnFillWorldObjectContextMenu)
end

-- Desactivar auto-drink para evitar que el vampiro beba agua automáticamente
if Events.OnPlayerUpdate then
    Events.OnPlayerUpdate.Add(function(player)
        if not player then
            return
        end

        local isLocal = Try(function()
            return player.isLocalPlayer and player:isLocalPlayer() or false
        end)

        if isLocal and Vampirism.HasVampireTrait(player) then
            if player.setAutoDrink then
                pcall(player.setAutoDrink, player, false)
            end
        end
    end)
end

------------------------------------------------------------
-- RENDERIZADO DE INTERFAZ
------------------------------------------------------------

if Events.OnPostUIDraw then
    Events.OnPostUIDraw.Add(function()
        local shouldDrawOverlay = Vampirism.sunDamageOverlayAlpha > 0.01
        local shouldDrawWarning = Vampirism.warningAlpha > 0.01
        local shouldDrawToast = Vampirism.toastAlpha > 0.01 and Vampirism.toastText ~= nil

        if not shouldDrawOverlay and not shouldDrawWarning and not shouldDrawToast then
            return
        end

        local core = Try(getCore)

        if not core or not core.getScreenWidth or not core.getScreenHeight then
            return
        end

        local width = core:getScreenWidth()
        local height = core:getScreenHeight()

        ------------------------------------------------------
        -- OVERLAY ROJO
        ------------------------------------------------------

        if shouldDrawOverlay and ISUIElement and ISUIElement.drawRect then
            ISUIElement.drawRect(
                0,
                0,
                width,
                height,
                0.55,                           -- R
                0.05,                           -- G
                0.0,                            -- B
                Vampirism.sunDamageOverlayAlpha -- A
            )
        end

        ------------------------------------------------------
        -- TEXTOS
        ------------------------------------------------------

        local textManager = Try(getTextManager)

        if shouldDrawWarning and textManager and textManager.DrawStringCentre then
            local warningText = GetTextSafe(
                "UI_Vampirism_SunWarning",
                "The sun is burning you!"
            )

            textManager:DrawStringCentre(
                math.floor(width / 2),
                height - 150,
                warningText,
                1.0,
                0.35,
                0.1,
                Vampirism.warningAlpha
            )
        end

        if shouldDrawToast and textManager and textManager.DrawStringCentre then
            textManager:DrawStringCentre(
                math.floor(width / 2),
                height - 190,
                Vampirism.toastText,
                1.0,
                1.0,
                1.0,
                Vampirism.toastAlpha
            )
        end
    end)
else
    print("[Vampirism] WARNING: Events.OnPostUIDraw is not available.")
end

print("[Vampirism] client Lua loaded successfully.")