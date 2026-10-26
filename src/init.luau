const ReplicatedStorage = game:GetService("ReplicatedStorage")
-- Config
const REQUEST_TIME_RECORDS_COUNT = 8 -- The record buffer size
const EXPIRE_TIME = 10 -- Time for request count to go down
const MAX_REQUEST = 6  -- Max amount of request per EXPIRE_TIME per player
-- Remote Instance
const CommandRequestRemote = Instance.new("RemoteFunction")
CommandRequestRemote.Name = "NapCommand" -- Name for localscripts to use
CommandRequestRemote.Parent = ReplicatedStorage -- Clients can now request command execution

const RequestTimeRecords: {[Player]: buffer?} = {} -- Value is the u32 (time in seconds when request was arrived)

-- Returns s if condition is true, Empty string if condition is false
-- Primarily used for plurals
const function putif(condition: boolean, s: string): string
    if condition then
        return s
    end
    return ""
end

const Commands: {[string]: {
    RequiredGroupRole: {string},
    Run: (Player, ...any) -> string
}} = {
    kill = {
        -- Varargs of usernames, kills everyone if not provided 
    RequiredGroupRole = {"CanKill"},
        Run = function(playerWhoRanCommand: Player, ...)
            const Players = game:GetService("Players")
            const killedPlayerNames = {}
            const killFailedPlayerNames = {}

            -- returns nil if players are killec
            -- returns string with reason if failed to kill player
            const function killPlayer(player: Player): string?
                const character = player.Character -- player's character    
                if not character then -- no player character 
                    return "no character found"
                end

                const humanoid = character:FindFirstChildOfClass("Humanoid") -- humanoid that has health prop
                if not humanoid then -- for type safety
                    return "no humanoid found"
                end

                if humanoid.Health == 0 then
                    return "already dead"
                end

                humanoid.Health = 0 -- kills character
                return nil
            end
            --[[
                call killPlayer() and add report to concat table
            ]]
            const function tryKillPlayer(player: Player)
                const err = killPlayer(player) -- returns string if errored
                if err then -- an error!
                    table.insert(killFailedPlayerNames, `{player.DisplayName} (@{player.Name}): {err}`) -- add err message to concat table
                else
                    table.insert(killedPlayerNames, `{player.DisplayName} (@{player.Name})`) -- add success player to concat table
                end
            end

            const argc = select("#", ...)
            const p = Players:GetPlayers()
            if argc == 0 then -- no args, kill all
                for _, player in p do -- all players
                    tryKillPlayer(player)
                end
            else -- args, kill players specified in arg
                for i = 1, argc do -- arg.
                    const name = select(i, ...) -- get the i-th parameter
                    local match = false -- will be true when player with that name is found
                    for _, player in p do -- all players
                        if string.lower(player.Name) == string.lower(name) then -- found the requested player!
                            match = true -- means do not report no player found error.
                            tryKillPlayer(player)
                            break -- player already found; no need to iterate again
                        end
                    end
                    if not match then -- no player found in the request; report no player found error
                        table.insert(killFailedPlayerNames, `{name}: not found`)
                    end
                end
            end
            
            return `{ -- return format string (i know it's a bit complicated, sorry)
                if #killedPlayerNames > 0 then -- killed at least one player
                    `Killed player{putif(#killedPlayerNames > 1, "s")}: {
                        table.concat(killedPlayerNames) -- list of all players killed
                    }`  
                else -- killed 0 player
                    "No players killed" -- message that not players killed
            }{ -- and next player
                if #killFailedPlayerNames > 0 then -- some players requested have failed to kill
                    `\nFailed to kill player{putif(#killFailedPlayerNames > 1, "s")}: {table.concat(killFailedPlayerNames)}`  
                else -- all requested players successfully killed
                    "" -- do not add more message
            }`
        end
    }
}

const function ProcessCommand_GetCommandType()
end

-- Since ProcessCommand_CheckRateLimit is called before this function,
-- even if exploiters fire remote rapidly, @native has no effect
const function ProcessCommand_WriteRequestRecord(player, ...)
    const buf: buffer? = RequestTimeRecords[player] -- record of player
    if not buf then -- somehow PlayerAdded is not ran yet for this player
        warn("RequestTimeRecord buffer not found in table") -- report error
        return nil, "Server side error!" -- the result to client
    end

    local earliestRecordOffset, earliestRecordTime = 0, buffer.readu32(buf, 0) -- will 
    for recordOffset = 0, (REQUEST_TIME_RECORDS_COUNT-1) * 4, 4 do -- loop over all
        const recordTime = buffer.readu32(buf, recordOffset) -- read the recorded request time in buffer
        if earliestRecordTime > recordTime then
            earliestRecordOffset, earliestRecordTime = recordOffset, recordTime
        end
    end
    -- Write the time when request is made
    const offsetToWriteTime = earliestRecordOffset
    const current = os.time() -- current time in second accuracy
    buffer.writeu32(buf, offsetToWriteTime, current)

    -- TODO: Implement the next step: check the permission
    return nil, "todo: run callback"
end

@native
-- Exploiters can fire this rapidly and lag the server
-- so using native saves resources dealing with it
const function ProcessCommand_CheckRateLimit(player, ...)
    const buf = RequestTimeRecords[player] -- record of player. Can read, but not write
    if not buf then -- somehow PlayerAdded is not ran yet for this player
        warn("RequestTimeRecord buffer not found in table") -- report error
        return nil, "Server side error!" -- the result to client
    end

    local active = 0 -- active request cooldown count

    const current = os.time() -- current time in second accuracy
    const expirationTime = current - EXPIRE_TIME -- past this time will count as active
    for offset = 0, (REQUEST_TIME_RECORDS_COUNT-1) * 4, 4 do
        const requestTime = buffer.readu32(buf, offset)
        if expirationTime < requestTime then
            active += 1
        end
    end

    if active >= MAX_REQUEST then -- rate limit exceeded
        return nil, "Wait before sending another command" -- the result to client
    end

    return ProcessCommand_WriteRequestRecord(player, ...) -- go to next step, without native code generation

end

do -- player add / removing calls
    const Players = game:GetService("Players")

    -- Create request time record buffer per player
    const function PlayerAdded(player: Player)
        RequestTimeRecords[player] = buffer.create(REQUEST_TIME_RECORDS_COUNT * 4) -- no need to set because all bits are set to zero
    end

    for _, player in ipairs(Players:GetPlayers()) do
        task.defer(PlayerAdded, player) -- for players who already in the game now
    end
    Players.PlayerAdded:Connect(PlayerAdded)

    -- Remove no longer used resources
    const function PlayerRemoving(player: Player)
        RequestTimeRecords[player] = nil
    end
    Players.PlayerRemoving:Connect(PlayerRemoving)
end

CommandRequestRemote.OnServerInvoke = ProcessCommand_CheckRateLimit

return table.freeze({
    CommandRequestRemote = CommandRequestRemote
})