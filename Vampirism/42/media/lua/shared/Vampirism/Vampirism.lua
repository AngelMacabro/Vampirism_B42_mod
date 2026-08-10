Vampirism = Vampirism or {}

Vampirism.ID = "Vampirism"
Vampirism.VAMPIRE_TRAIT = "vampirism:vampire"

-- Configuración de daño solar
Vampirism.SUN_DAMAGE_ENABLED = true
Vampirism.SUN_DAMAGE_INTERVAL = 5 -- segundos entre comprobaciones
Vampirism.SUN_DAMAGE_AMOUNT = 0.3 -- cantidad de daño por intervalo
Vampirism.SUN_DAMAGE_START_HOUR = 6 -- hora a la que empieza el daño
Vampirism.SUN_DAMAGE_END_HOUR = 20 -- hora a la que termina el daño
Vampirism.SUN_WARNING_COOLDOWN = 30 -- segundos entre advertencias de texto flotante

-- Internos
Vampirism.lastDamageTick = 0
Vampirism.currentTick = 0
Vampirism.isReceivingDamage = false

print("[Vampirism] shared Lua loaded")
