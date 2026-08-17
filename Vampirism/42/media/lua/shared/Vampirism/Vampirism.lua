-- Vampirism.lua
-- Shared configuration for Vampirism mod.

Vampirism = Vampirism or {}

Vampirism.ID = "Vampirism"

-- ID exacto del trait vampiro.
-- Asegúrate de que este ID coincida con el trait registrado en Build 42.
Vampirism.VAMPIRE_TRAIT = "vampirism:vampire"
Vampirism.DAMNED_TRAIT = "vampirism:damned"

------------------------------------------------------------
-- CONFIGURACIÓN DE DAÑO SOLAR
------------------------------------------------------------

Vampirism.SUN_DAMAGE_ENABLED = true

-- Prender fuego físico/visual al personaje al exponerse a la luz solar directa.
Vampirism.IGNITE_ON_SUN_EXPOSURE = true

-- Extinguir el fuego automáticamente al entrar a la sombra o interiores.
Vampirism.AUTO_EXTINGUISH_IN_SHADE = true

-- Verificar también el trait 'damned' además de 'vampire'.
Vampirism.CHECK_DAMNED_TRAIT = true

-- Segundos aproximados entre comprobaciones/ticks de daño.
Vampirism.SUN_DAMAGE_INTERVAL = 5

-- Cantidad de daño por intervalo.
-- 0.3 es muy leve; para pruebas puedes subirlo a 1.0 o 5.0.
Vampirism.SUN_DAMAGE_AMOUNT = 5.0

-- Cantidad de dolor por intervalo.
-- Si el daño es bajo, el dolor debería ser bajo también.
Vampirism.SUN_PAIN_AMOUNT = 2.0

-- Horario de daño solar por defecto (usado si el gestor de clima no está disponible).
Vampirism.SUN_DAMAGE_START_HOUR = 6
Vampirism.SUN_DAMAGE_END_HOUR = 20

-- Cooldown para mensajes repetidos de advertencia.
Vampirism.SUN_WARNING_COOLDOWN = 30

------------------------------------------------------------
-- CONFIGURACIÓN DE PROTECCIÓN POR CLIMA (LLUVIA, TORMENTA Y NIEBLA)
------------------------------------------------------------

-- Día lluvioso: la lluvia protege de la quemadura solar
Vampirism.PROTECT_IN_RAIN = true
-- Umbral mínimo de intensidad de lluvia para proteger (0.05 = llovizna/lluvia)
Vampirism.RAIN_PROTECTION_THRESHOLD = 0.05

-- Tormentas (eléctrica, tropical, ventisca, tempestad)
Vampirism.PROTECT_IN_STORM = true

-- Niebla / Neblina
Vampirism.PROTECT_IN_FOG = true
-- Intensidad mínima de niebla para bloquear los rayos solares (0.0 a 1.0)
Vampirism.FOG_PROTECTION_THRESHOLD = 0.15

------------------------------------------------------------
-- CONFIGURACIÓN DE BONIFICACIONES NOCTURNAS
------------------------------------------------------------

Vampirism.NIGHT_BUFFS_ENABLED = true

-- Multiplicador de velocidad de movimiento en la noche (1.25 = +25% de velocidad).
Vampirism.NIGHT_SPEED_MULTIPLIER = 1.25

-- Bonificación de niveles a la habilidad Fuerza durante la noche.
-- Nota: La fuerza aumenta automáticamente la capacidad de carga y daño del personaje.
Vampirism.NIGHT_STRENGTH_BONUS = 3

------------------------------------------------------------
-- CONFIGURACIÓN DE HAMBRE Y SED DE SANGRE
------------------------------------------------------------

-- Los vampiros no padecen hambre mortal
Vampirism.HUNGER_DISABLED = true

-- Rechazo al agua corriente
Vampirism.BLOCK_WATER = true
Vampirism.WATER_PENALTY_ENABLED = true
Vampirism.WATER_SICKNESS_AMOUNT = 15.0

-- Alimentación de jugadores vivos (Mecánica principal)
Vampirism.FEED_PLAYER_ENABLED = true
Vampirism.FEED_PLAYER_THIRST_REDUCTION = 0.8
Vampirism.FEED_PLAYER_DAMAGE = 25.0
Vampirism.FEED_PLAYER_BLEED_TIME = 20.0
Vampirism.FEED_PLAYER_MAX_DISTANCE = 1.8

-- Alimentación de cadáveres (Mecánica provisional)
Vampirism.FEED_CORPSE_ENABLED = true
Vampirism.FEED_CORPSE_THIRST_REDUCTION = 0.4
Vampirism.FEED_CORPSE_MAX_CHARGES = 2
Vampirism.CORPSE_BLOOD_PENALTY_ENABLED = true
Vampirism.CORPSE_BLOOD_SICKNESS_AMOUNT = 8.0
Vampirism.CORPSE_BLOOD_UNHAPPINESS = 10.0
Vampirism.FEED_CORPSE_MAX_DISTANCE = 1.8

------------------------------------------------------------
-- DEBUG
------------------------------------------------------------

Vampirism.DEBUG = false

------------------------------------------------------------
-- ESTADO INTERNO
------------------------------------------------------------

-- Estos valores pueden inicializarse aquí por seguridad,
-- pero el estado real por jugador se maneja en servidor.
Vampirism.currentTick = Vampirism.currentTick or 0
Vampirism.lastDamageTick = Vampirism.lastDamageTick or 0

-- No se recomienda tener isReceivingDamage aquí.
-- Ese es un estado visual del cliente.
-- Vampirism.isReceivingDamage = false

------------------------------------------------------------
-- TRAITS Y UTILIDADES COMPARTIDAS
------------------------------------------------------------

function Vampirism.HasSpecificTrait(player, traitId)
    if not player or not traitId then
        return false
    end

    if not ResourceLocation or not ResourceLocation.of then
        return false
    end

    if not CharacterTrait or not CharacterTrait.get then
        return false
    end

    local okLocation, resourceLocation = pcall(ResourceLocation.of, traitId)
    if not okLocation or not resourceLocation then
        return false
    end

    local okTrait, traitObj = pcall(CharacterTrait.get, resourceLocation)
    if not okTrait or not traitObj then
        return false
    end

    if not player.hasTrait then
        return false
    end

    local okHasTrait, hasTrait = pcall(function()
        return player:hasTrait(traitObj)
    end)

    return okHasTrait and hasTrait == true
end

function Vampirism.HasDamnedOrVampireTrait(player)
    if not player then
        return false
    end

    -- Comprobar trait maldito (damned)
    if Vampirism.CHECK_DAMNED_TRAIT and Vampirism.DAMNED_TRAIT then
        if Vampirism.HasSpecificTrait(player, Vampirism.DAMNED_TRAIT) then
            return true
        end
    end

    -- Comprobar trait de vampiro
    if Vampirism.VAMPIRE_TRAIT then
        if Vampirism.HasSpecificTrait(player, Vampirism.VAMPIRE_TRAIT) then
            return true
        end
    end

    return false
end

function Vampirism.HasVampireTrait(player)
    return Vampirism.HasDamnedOrVampireTrait(player)
end

function Vampirism.GrantTrait(player, traitId)
    if not player or not traitId then
        return false
    end

    if not ResourceLocation or not ResourceLocation.of then
        return false
    end

    if not CharacterTrait or not CharacterTrait.get then
        return false
    end

    local okLocation, resourceLocation = pcall(ResourceLocation.of, traitId)
    if not okLocation or not resourceLocation then
        return false
    end

    local okTrait, traitObj = pcall(CharacterTrait.get, resourceLocation)
    if not okTrait or not traitObj then
        return false
    end

    if not player.hasTrait then
        return false
    end

    local okHasTrait, hasTrait = pcall(function()
        return player:hasTrait(traitObj)
    end)

    if okHasTrait and not hasTrait then
        local traits = nil
        if player.getCharacterTraits then
            traits = player:getCharacterTraits()
        end

        if traits then
            if traits.add then
                pcall(traits.add, traits, traitObj)
            elseif traits.set then
                pcall(traits.set, traits, traitObj, true)
            end
        end
        return true
    end

    return false
end

function Vampirism.EnsureVampireTraits(player)
    if not player then
        return
    end

    -- Si el personaje es vampiro, garantizar nightvision y damned
    if Vampirism.HasSpecificTrait(player, Vampirism.VAMPIRE_TRAIT) then
        Vampirism.GrantTrait(player, "base:nightvision")
        if Vampirism.DAMNED_TRAIT then
            Vampirism.GrantTrait(player, Vampirism.DAMNED_TRAIT)
        end
    end

    -- Reparar maxWeightDelta si hubiese quedado en 0
    if player.getMaxWeightDelta and player.setMaxWeightDelta then
        local ok, delta = pcall(player.getMaxWeightDelta, player)
        if ok and delta == 0 then
            pcall(player.setMaxWeightDelta, player, 1.0)
        end
    end

    -- Reparar peso nutricional del personaje si estuviese en 0
    local nutrition = nil
    if player.getNutrition then
        nutrition = player:getNutrition()
    end
    if nutrition and nutrition.getWeight and nutrition.setWeight then
        local ok, w = pcall(nutrition.getWeight, nutrition)
        if ok and (w == nil or w <= 1) then
            pcall(nutrition.setWeight, nutrition, 80.0)
        end
    end
end

require("Vampirism/VampirismActionsHook")

print("[Vampirism] shared Lua loaded")