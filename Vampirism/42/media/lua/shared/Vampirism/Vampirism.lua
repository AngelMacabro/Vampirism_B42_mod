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

-- Horario de daño solar.
Vampirism.SUN_DAMAGE_START_HOUR = 6
Vampirism.SUN_DAMAGE_END_HOUR = 20

-- Cooldown para mensajes repetidos de advertencia.
Vampirism.SUN_WARNING_COOLDOWN = 30

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

print("[Vampirism] shared Lua loaded")