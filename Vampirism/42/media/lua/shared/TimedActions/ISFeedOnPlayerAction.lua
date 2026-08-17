-- ISFeedOnPlayerAction.lua
-- Timed Action: Vampiro alimentándose de un jugador vivo.

require "TimedActions/ISBaseTimedAction"
require "Vampirism/Vampirism"

ISFeedOnPlayerAction = ISBaseTimedAction:derive("ISFeedOnPlayerAction")

function ISFeedOnPlayerAction:isValid()
    if not self.character or not self.target then
        return false
    end

    local isVampire = Vampirism.HasVampireTrait and Vampirism.HasVampireTrait(self.character)
    if not isVampire then
        return false
    end

    if self.character:isDead() or self.target:isDead() then
        return false
    end

    local maxDist = tonumber(Vampirism.FEED_PLAYER_MAX_DISTANCE) or 1.8
    local dist = self.character:DistTo(self.target)
    if dist > maxDist then
        return false
    end

    return true
end

function ISFeedOnPlayerAction:waitToStart()
    if self.target then
        self.character:faceThisObject(self.target)
    end
    return self.character:shouldBeTurning()
end

function ISFeedOnPlayerAction:update()
    if self.target then
        self.character:faceThisObject(self.target)
    end
end

function ISFeedOnPlayerAction:start()
    if self.target then
        self.character:faceThisObject(self.target)
    end

    self:setActionAnim("MedicalCheck")
    self:setOverrideHandModels(nil, nil)

    local emitter = self.character:getEmitter()
    if emitter then
        self.sound = emitter:playSound("ZombieBite")
    else
        self.sound = self.character:playSound("ZombieBite")
    end
end

function ISFeedOnPlayerAction:stopSound()
    if self.sound and self.character:getEmitter():isPlaying(self.sound) then
        self.character:stopOrTriggerSound(self.sound)
    end
end

function ISFeedOnPlayerAction:stop()
    self:stopSound()
    ISBaseTimedAction.stop(self)
end

function ISFeedOnPlayerAction:perform()
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

    local targetOnlineID = -1
    if self.target.getOnlineID then
        targetOnlineID = self.target:getOnlineID()
    end

    local targetPlayerNum = -1
    if self.target.getPlayerNum then
        targetPlayerNum = self.target:getPlayerNum()
    end

    local targetUsername = nil
    if self.target.getUsername then
        targetUsername = self.target:getUsername()
    end

    local args = {
        targetOnlineID = targetOnlineID,
        targetPlayerNum = targetPlayerNum,
        targetUsername = targetUsername
    }

    if sendClientCommand then
        sendClientCommand(self.character, "Vampirism", "FeedOnPlayer", args)
    end

    ISBaseTimedAction.perform(self)
end

function ISFeedOnPlayerAction:new(character, target)
    local o = ISBaseTimedAction.new(self, character)
    o.target = target
    o.stopOnWalk = true
    o.stopOnRun = true
    o.stopOnAim = true
    o.maxTime = 200
    if character:isTimedActionInstant() then
        o.maxTime = 1
    end
    return o
end
