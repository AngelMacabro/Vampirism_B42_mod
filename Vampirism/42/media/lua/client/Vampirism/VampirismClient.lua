require("Vampirism.Vampirism")

-- ESTADO VISUAL DEL CLIENTE
Vampirism.sunDamageOverlayAlpha = 0
Vampirism.sunDamageOverlayActive = false
Vampirism.warningAlpha = 0

-- Estado recibido desde el servidor
Vampirism.isReceivingDamage = false

-- ACTUALIZACIÓN VISUAL (MIGRADO A ONRENDERTICK)
function Vampirism.UpdateSunDamageVisuals()
    if Vampirism.isReceivingDamage then
        Vampirism.sunDamageOverlayActive = true

        -- Incrementar gradualmente la intensidad del efecto (Ajustado para RenderTick)
        Vampirism.sunDamageOverlayAlpha = math.min(0.6, Vampirism.sunDamageOverlayAlpha + 0.01)
        Vampirism.warningAlpha = math.min(1.0, Vampirism.warningAlpha + 0.02)
    else
        Vampirism.sunDamageOverlayActive = false

        -- Reducir gradualmente la intensidad
        Vampirism.sunDamageOverlayAlpha = math.max(0.0, Vampirism.sunDamageOverlayAlpha - 0.005)
        Vampirism.warningAlpha = math.max(0.0, Vampirism.warningAlpha - 0.01)
    end
end

-- Se utiliza OnRenderTick para animaciones visuales fluidas e independientes de los ticks lógicos
Events.OnRenderTick.Add(function()
    Vampirism.UpdateSunDamageVisuals()
end)

-- SINCRONIZACIÓN SERVER -> CLIENT (COMPATIBLE MULTIJUGADOR)
Events.OnServerCommand.Add(function(module, command, args)
    -- Ignorar comandos de otros mods
    if module ~= "Vampirism" then return end
    if not args then return end

    -- Obtener el jugador local de esta instancia del cliente
    local localPlayer = getPlayer()
    if not localPlayer then return end

    -- IMPORTANTE: Validamos que el comando sea específicamente para nuestro ID en línea
    local targetPlayerID = args.playerID
    local myOnlineID = localPlayer.getOnlineID and localPlayer:getOnlineID() or -1

    if targetPlayerID ~= myOnlineID then
        return -- El comando es para otro jugador en el servidor, lo ignoramos.
    end

    -- El servidor indica que comenzó el daño solar
    if command == "SunDamageStart" then
        Vampirism.isReceivingDamage = true
        return
    end

    -- El servidor indica que terminó el daño solar
    if command == "SunDamageStop" then
        Vampirism.isReceivingDamage = false
        return
    end
end)

-- RENDERIZADO DE LA INTERFAZ
local renderEvent = Events.OnPostUIDraw

if renderEvent then
    renderEvent.Add(function()
        -- No dibujar nada si ambos efectos están prácticamente desactivados
        if Vampirism.sunDamageOverlayAlpha <= 0.01 and Vampirism.warningAlpha <= 0.01 then
            return
        end

        local core = getCore()
        if not core then return end

        local width = core:getScreenWidth()
        local height = core:getScreenHeight()

        -- RECTÁNGULO DE DAÑO SOLAR (OVERLAY DE PANTALLA ROJA)
        -- Usamos las variables que inicializaste arriba para pintar la pantalla de rojo translúcido
        if Vampirism.sunDamageOverlayAlpha > 0.01 then
            -- Parámetros: x, y, ancho, alto, r, g, b, a
            ISUIElement.drawRect(
                0, 
                0, 
                width, 
                height, 
                0.5,                             -- Rojo moderado (0.5)
                0.1,                             -- Un toque leve de verde
                0.0,                             -- Sin azul
                Vampirism.sunDamageOverlayAlpha  -- Alpha dinámico
            )
        end

        -- Texto de advertencia centrado
        if Vampirism.warningAlpha > 0.01 then
            local warningText = getText("UI_Vampirism_SunWarning")
            local centerX = width / 2
            local y = height - 150 -- Subido ligeramente para evitar colisiones con hotbars inferiores

            if getTextManager() and getTextManager().DrawStringCentre then
                getTextManager():DrawStringCentre(
                    centerX,
                    y,
                    warningText,
                    1.0,                    -- R
                    0.3,                    -- G (Hacerlo más anaranjado/rojizo)
                    0.1,                    -- B
                    Vampirism.warningAlpha  -- Alpha dinámico
                )
            end
        end
    end)
end

-- INICIALIZACIÓN
print("[Vampirism] client Lua loaded successfully.")