-- VampirismActionsHook.lua
-- Intercepción y penalizaciones para vampiros al intentar beber agua o comer comida sólida.

require "TimedActions/ISBaseTimedAction"
require "TimedActions/ISTakeWaterAction"
require "TimedActions/ISDrinkFluidAction"
require "TimedActions/ISDrinkFromBottle"
require "TimedActions/ISEatFoodAction"
require "Vampirism/Vampirism"

-- ============================================================
-- UTILIDADES DE RECHAZO (ANIMACIONES Y SONIDOS NATIVOS)
-- ============================================================

local function PlayWaterRejectionEffects(character)
    if not character then
        return
    end

    if character.setVariable and character.reportEvent then
        pcall(character.setVariable, character, "Ext", "Cough")
        pcall(character.reportEvent, character, "EventDoExt")
    end

    if character.playSound then
        local isFemale = false
        if character.isFemale then
            local ok, female = pcall(character.isFemale, character)
            if ok then
                isFemale = female == true
            end
        end

        local soundName = isFemale and "VoiceFemaleCough" or "VoiceMaleCough"
        pcall(character.playSound, character, soundName)
    end
end

local function PlayFoodRejectionEffects(character)
    if not character then
        return
    end

    if character.setVariable and character.reportEvent then
        pcall(character.setVariable, character, "Ext", "PainStomach1")
        pcall(character.reportEvent, character, "EventDoExt")
    end

    if character.playSound then
        local isFemale = false
        if character.isFemale then
            local ok, female = pcall(character.isFemale, character)
            if ok then
                isFemale = female == true
            end
        end

        local soundName = isFemale and "VoiceFemaleVomit" or "VoiceMaleVomit"
        pcall(character.playSound, character, soundName)
    end
end

-- ============================================================
-- 1. BEBER AGUA DIRECTA DE GRIFOS / FUENTES / CHARCOS (ISTakeWaterAction)
-- ============================================================

local old_ISTakeWaterAction_isValid = ISTakeWaterAction.isValid
function ISTakeWaterAction:isValid()
    if self.item == nil and Vampirism.BLOCK_WATER and Vampirism.HasVampireTrait and Vampirism.HasVampireTrait(self.character) then
        return false
    end
    return old_ISTakeWaterAction_isValid(self)
end

local old_ISTakeWaterAction_start = ISTakeWaterAction.start
function ISTakeWaterAction:start()
    if self.item == nil and Vampirism.BLOCK_WATER and Vampirism.HasVampireTrait and Vampirism.HasVampireTrait(self.character) then
        if self.character and HaloTextHelper and HaloTextHelper.addText then
            local msg = (getText and getText("UI_Vampirism_WaterRejected")) or "Your vampiric body rejects pure water."
            pcall(HaloTextHelper.addText, self.character, msg, 100, 180, 255)
        end
        PlayWaterRejectionEffects(self.character)
        local stats = self.character:getStats()
        if stats and CharacterStat and CharacterStat.FOOD_SICKNESS and Vampirism.WATER_PENALTY_ENABLED then
            stats:add(CharacterStat.FOOD_SICKNESS, tonumber(Vampirism.WATER_SICKNESS_AMOUNT) or 15.0)
        end
        self:forceStop()
        return
    end
    old_ISTakeWaterAction_start(self)
end

local old_ISTakeWaterAction_transferFluid = ISTakeWaterAction.transferFluid
function ISTakeWaterAction:transferFluid(_amount)
    if self.item == nil and Vampirism.BLOCK_WATER and Vampirism.HasVampireTrait and Vampirism.HasVampireTrait(self.character) then
        return
    end
    old_ISTakeWaterAction_transferFluid(self, _amount)
end

local old_ISTakeWaterAction_complete = ISTakeWaterAction.complete
function ISTakeWaterAction:complete()
    if self.item == nil and Vampirism.BLOCK_WATER and Vampirism.HasVampireTrait and Vampirism.HasVampireTrait(self.character) then
        local stats = self.character:getStats()
        if stats and CharacterStat and CharacterStat.FOOD_SICKNESS and Vampirism.WATER_PENALTY_ENABLED then
            stats:add(CharacterStat.FOOD_SICKNESS, tonumber(Vampirism.WATER_SICKNESS_AMOUNT) or 15.0)
        end
        return true
    end
    return old_ISTakeWaterAction_complete(self)
end

-- ============================================================
-- 2. BEBER FLUIDOS DE RECIPIENTES (ISDrinkFluidAction)
-- ============================================================

local old_ISDrinkFluidAction_start = ISDrinkFluidAction.start
function ISDrinkFluidAction:start()
    if Vampirism.BLOCK_WATER and Vampirism.HasVampireTrait and Vampirism.HasVampireTrait(self.character) then
        local isBlood = false
        if self.fluidContainer and Fluid and Fluid.Blood then
            isBlood = self.fluidContainer:contains(Fluid.Blood) or (Fluid.AnimalBlood and self.fluidContainer:contains(Fluid.AnimalBlood))
        end

        if not isBlood then
            if self.character and HaloTextHelper and HaloTextHelper.addText then
                local msg = (getText and getText("UI_Vampirism_WaterRejected")) or "Your vampiric body rejects pure water."
                pcall(HaloTextHelper.addText, self.character, msg, 100, 180, 255)
            end
            PlayWaterRejectionEffects(self.character)
            local stats = self.character:getStats()
            if stats and CharacterStat and CharacterStat.FOOD_SICKNESS and Vampirism.WATER_PENALTY_ENABLED then
                stats:add(CharacterStat.FOOD_SICKNESS, tonumber(Vampirism.WATER_SICKNESS_AMOUNT) or 15.0)
            end
            self:forceStop()
            return
        end
    end
    old_ISDrinkFluidAction_start(self)
end

local old_ISDrinkFluidAction_complete = ISDrinkFluidAction.complete
function ISDrinkFluidAction:complete()
    if Vampirism.BLOCK_WATER and Vampirism.HasVampireTrait and Vampirism.HasVampireTrait(self.character) then
        local isBlood = false
        if self.fluidContainer and Fluid and Fluid.Blood then
            isBlood = self.fluidContainer:contains(Fluid.Blood) or (Fluid.AnimalBlood and self.fluidContainer:contains(Fluid.AnimalBlood))
        end
        if not isBlood then
            local stats = self.character:getStats()
            if stats and CharacterStat and CharacterStat.FOOD_SICKNESS and Vampirism.WATER_PENALTY_ENABLED then
                stats:add(CharacterStat.FOOD_SICKNESS, tonumber(Vampirism.WATER_SICKNESS_AMOUNT) or 15.0)
            end
            return true
        end
    end
    return old_ISDrinkFluidAction_complete(self)
end

-- ============================================================
-- 3. BEBER DE BOTELLAS (ISDrinkFromBottle)
-- ============================================================

local old_ISDrinkFromBottle_start = ISDrinkFromBottle.start
function ISDrinkFromBottle:start()
    if Vampirism.BLOCK_WATER and Vampirism.HasVampireTrait and Vampirism.HasVampireTrait(self.character) then
        local isBlood = false
        if self.item and self.item.getFluidContainer and self.item:getFluidContainer() and Fluid and Fluid.Blood then
            local fc = self.item:getFluidContainer()
            isBlood = fc:contains(Fluid.Blood) or (Fluid.AnimalBlood and fc:contains(Fluid.AnimalBlood))
        end

        if not isBlood then
            if self.character and HaloTextHelper and HaloTextHelper.addText then
                local msg = (getText and getText("UI_Vampirism_WaterRejected")) or "Your vampiric body rejects pure water."
                pcall(HaloTextHelper.addText, self.character, msg, 100, 180, 255)
            end
            PlayWaterRejectionEffects(self.character)
            local stats = self.character:getStats()
            if stats and CharacterStat and CharacterStat.FOOD_SICKNESS and Vampirism.WATER_PENALTY_ENABLED then
                stats:add(CharacterStat.FOOD_SICKNESS, tonumber(Vampirism.WATER_SICKNESS_AMOUNT) or 15.0)
            end
            self:forceStop()
            return
        end
    end
    old_ISDrinkFromBottle_start(self)
end

-- ============================================================
-- 4. COMER COMIDA SÓLIDA MORTAL (ISEatFoodAction)
-- ============================================================

local old_ISEatFoodAction_start = ISEatFoodAction.start
function ISEatFoodAction:start()
    if Vampirism.HasVampireTrait and Vampirism.HasVampireTrait(self.character) then
        if self.character and HaloTextHelper and HaloTextHelper.addText then
            local msg = (getText and getText("UI_Vampirism_FoodRejected")) or "Your body cannot digest mortal food."
            pcall(HaloTextHelper.addText, self.character, msg, 200, 100, 100)
        end
        PlayFoodRejectionEffects(self.character)
        local stats = self.character:getStats()
        if stats and CharacterStat then
            if CharacterStat.FOOD_SICKNESS then
                stats:add(CharacterStat.FOOD_SICKNESS, 20.0)
            end
            if CharacterStat.UNHAPPINESS then
                stats:add(CharacterStat.UNHAPPINESS, 15.0)
            end
            if CharacterStat.HUNGER then
                stats:set(CharacterStat.HUNGER, 0.0)
            end
        end
        self:forceStop()
        return
    end
    old_ISEatFoodAction_start(self)
end

local old_ISEatFoodAction_eat = ISEatFoodAction.eat
function ISEatFoodAction:eat(food, percentage)
    if Vampirism.HasVampireTrait and Vampirism.HasVampireTrait(self.character) then
        local stats = self.character:getStats()
        if stats and CharacterStat then
            if CharacterStat.FOOD_SICKNESS then
                stats:add(CharacterStat.FOOD_SICKNESS, 20.0)
            end
            if CharacterStat.UNHAPPINESS then
                stats:add(CharacterStat.UNHAPPINESS, 15.0)
            end
            if CharacterStat.HUNGER then
                stats:set(CharacterStat.HUNGER, 0.0)
            end
        end
        return
    end
    old_ISEatFoodAction_eat(self, food, percentage)
end

local old_ISEatFoodAction_complete = ISEatFoodAction.complete
function ISEatFoodAction:complete()
    if Vampirism.HasVampireTrait and Vampirism.HasVampireTrait(self.character) then
        local stats = self.character:getStats()
        if stats and CharacterStat then
            if CharacterStat.FOOD_SICKNESS then
                stats:add(CharacterStat.FOOD_SICKNESS, 20.0)
            end
            if CharacterStat.UNHAPPINESS then
                stats:add(CharacterStat.UNHAPPINESS, 15.0)
            end
            if CharacterStat.HUNGER then
                stats:set(CharacterStat.HUNGER, 0.0)
            end
        end
        return true
    end
    return old_ISEatFoodAction_complete(self)
end
