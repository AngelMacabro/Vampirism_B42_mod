-- VampirismClient.lua
-- Project Zomboid Build 42.20.2
-- Cliente visual para el sistema de vampirismo.

-- Si tu shared ya se carga automáticamente, puedes quitar el require.
-- En PZ normalmente se usa ruta con "/", no con ".".
require("Vampirism/Vampirism")

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
        return
    end

    if command == "SunDamageStop" then
        Vampirism.isReceivingDamage = false
        return
    end

    if command == "ShowMessage" then
        local localPlayer = GetLocalPlayer()

        if args.text and args.text ~= "" then
            -- Si HaloTextHelper funciona en esta build, úsalo.
            if localPlayer and HaloTextHelper and HaloTextHelper.addText then
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