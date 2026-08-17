-- ISFeedOnCorpseAction.lua
-- Timed Action: Vampiro alimentándose de un cadáver en el suelo.

require "TimedActions/ISBaseTimedAction"
require "Vampirism/Vampirism"

ISFeedOnCorpseAction = ISBaseTimedAction:derive("ISFeedOnCorpseAction")

function ISFeedOnCorpseAction:isValid()
    if not self.character or not self.corpse then
        return false
    end

    local isVampire = Vampirism.HasVampireTrait and Vampirism.HasVampireTrait(self.character)
    if not isVampire then
        return false
    end

    if self.character:isDead() then
        return false
    end

    local sq = self.corpse:getSquare()
    if not sq then
        return false
    end

    local maxDist = tonumber(Vampirism.FEED_CORPSE_MAX_DISTANCE) or 1.8
    local dist = self.character:DistTo(self.corpse:getX(), self.corpse:getY())
    if dist > maxDist then
        return false
    end

    local modData = self.corpse:getModData()
    if modData and modData.vampireBloodCharges ~= nil and modData.vampireBloodCharges <= 0 then
        return false
    end

    return true
end

function ISFeedOnCorpseAction:waitToStart()
    if self.corpse then
        self.character:faceThisObject(self.corpse)
    end
    return self.character:shouldBeTurning()
end

function ISFeedOnCorpseAction:update()
    if self.corpse then
        self.character:faceThisObject(self.corpse)
    end
end

function ISFeedOnCorpseAction:start()
    if self.corpse then
        self.character:faceThisObject(self.corpse)
    end

    self:setActionAnim("Loot")
    self.character:SetVariable("LootPosition", "Low")
    self.character:reportEvent("EventLootItem")
    self:setOverrideHandModels(nil, nil)

    local emitter = self.character:getEmitter()
    if emitter then
        self.sound = emitter:playSound("ZombieBite")
    else
        self.sound = self.character:playSound("ZombieBite")
    end
end

function ISFeedOnCorpseAction:stopSound()
    if self.sound and self.character:getEmitter():isPlaying(self.sound) then
        self.character:stopOrTriggerSound(self.sound)
    end
end

function ISFeedOnCorpseAction:stop()
    self:stopSound()
    ISBaseTimedAction.stop(self)
end

function ISFeedOnCorpseAction:perform()
    self:stopSound()

    -- Efecto visual: manchas de sangre en el rostro tras alimentarse
    if self.character and self.character.addBlood and BloodBodyPartType and BloodBodyPartType.Head then
        pcall(self.character.addBlood, self.character, BloodBodyPartType.Head, true, false, false)
        if syncVisuals then
            pcall(syncVisuals, self.character)
        end
        if sendHumanVisual then
            pcall(sendHumanVisual, self.character)
        end
    end

    local sq = self.corpse:getSquare()
    local x = sq and sq:getX() or self.corpse:getX()
    local y = sq and sq:getY() or self.corpse:getY()
    local z = sq and sq:getZ() or self.corpse:getZ()

    local corpseId = nil
    if self.corpse.getObjectID then
        corpseId = self.corpse:getObjectID()
    elseif self.corpse.getCharacterOnlineID then
        corpseId = self.corpse:getCharacterOnlineID()
    end

    local args = {
        x = x,
        y = y,
        z = z,
        corpseId = corpseId
    }

    if sendClientCommand then
        sendClientCommand(self.character, "Vampirism", "FeedOnCorpse", args)
    end

    ISBaseTimedAction.perform(self)
end

function ISFeedOnCorpseAction:new(character, corpse)
    local o = ISBaseTimedAction.new(self, character)
    o.corpse = corpse
    o.stopOnWalk = true
    o.stopOnRun = true
    o.stopOnAim = true
    o.maxTime = 180
    if character:isTimedActionInstant() then
        o.maxTime = 1
    end
    return o
end
