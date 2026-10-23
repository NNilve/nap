-- Config
const REQUEST_TIME_RECORDS_COUNT = 8 -- The record buffer size
const EXPIRE_TIME = 10 -- Time for request count to go down
const MAX_REQUEST = 6  -- Max amount of request per EXPIRE_TIME per player
-- Remote Instance
const CommandRequestRemote = Instance.new("RemoteFunction")
CommandRequestRemote.Name = "NapCommand" -- Name for localscripts to use
CommandRequestRemote.Parent = require("./SharedFolder") -- Clients can now request command execution

const RequestTimeRecords: {[Player]: buffer?} = {} -- Value is the u32 (time in seconds when request was arrived)

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