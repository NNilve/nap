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

const Commands = {
    kill = {
        -- Varargs of usernames, kills everyone if not provided 
        RequiredGroupRole = {"CanKillAll"},
        Run = function(...)
            const Players = game:GetService("Players")
            const killedPlayerNames = {}
            const killFailedPlayerNames = {}
            const function shouldKillPlayer(player: Player, ...): boolean
                const varargc = select("#", ...)
                if varargc == 0 then -- no params: kill everyone
                    return true -- yes, you should kill it
                end
                for i = 1, varargc do -- go and iterate over vararg
                    const username = select(i, ...) -- 
                    if player.Name == username then -- username found
                        return true -- yes, it's requested to kill username
                    end
                end
                return false -- no, you shouldn't
            end
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

            const argc = select("#", ...)
            const p = Players:GetPlayers()
            if argc == 0 then
                -- todo
            end
            for i = 1, argc do
                const name = select(i, ...)
                for _, player in p do
                    if player.Name == name then
                        const err = killPlayer(player)
                        if err then
                            const msg = `{player.DisplayName} (@{player.Name}) - {err}`
                            table.insert(killFailedPlayerNames, msg)
                        else
                            table.insert(killedPlayerNames, `{player.DisplayName} (@{player.Name})`)
                        end
                        continue
                    end
                end
            end
            --[[
            for _, player in Players:GetPlayers() do -- loop over all players
                if not shouldKillPlayer(player, ...) then
                    continue
                end

                const playerName = string.format("%s (%s)", player.DisplayName, player.Name)
                
                
                table.insert(killedPlayerNames, playerName)
            end]]

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