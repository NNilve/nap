const ReplicatedStorage = game:GetService("ReplicatedStorage")
const DataStoreService = game:GetService("DataStoreService")

const NapLogDataStore = DataStoreService:GetDataStore("NapLog")
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
type CmdData = {
    RequiredGroupRole: {string},
    Run: (Player, ...any) -> string,
    Yields: boolean?
}
const Commands: {[string]: CmdData} = {
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


const function deepcopy<T>(t: T): T
    if type(t) ~= 'table' then
        return t
    end
    const function clone<U>(t: U, visited: {[{[any]: any}]: true?}): U
        if type(t) ~= 'table' or visited[t] then
            return t 
        end
        visited[t] = true

        const new: any = {}
        for k, v in pairs(t) do
            new[clone(k, visited)] = clone(v, visited)
        end
        return new
    end
    return clone(t, {})
end

const function ProcessCommand_LogUpdate(player: Player, cmdName: string, ...)
    -- uses 3 params (length of log, current time, server job id)
    const function generateID(logLen: number, time: DateTime): string
        const EncodingService = game:GetService("EncodingService")
        const now = time.UnixTimestampMillis -- f64 (but it's actually u52), too large to fit in u32
        const jobId = game.JobId -- unique per server

        const buf = buffer.create(8 + 4 + #jobId) -- size of time + log length + jobId
        buffer.writef64(buf, 0, now) -- should use writef64 because there's no 64 bit luau integer
        buffer.writeu32(buf, 8, logLen) 
        buffer.writestring(buf, 12, jobId)

        return buffer.tostring(EncodingService:Base64Encode( -- convert to human readable string
            EncodingService:ComputeBufferHash(buf,Enum.HashAlgorithm.Blake3) -- convert to random characters
        ))

    end
    const function typeData(data: any): (
        {Logs: {any}}, -- The typed, valid value
        {[string]: any} -- Roblox metadata contains information of data's schema change
    )
        const robloxMetadata = {}
        if typeof(data) ~= "table" then
            if data ~= nil then -- data is corrupted
                robloxMetadata.UpdateType = "CorruptionReset" -- add report to metadata
            else -- data is newly created
                robloxMetadata.UpdateType = "Initialize"
            end
            return { -- return new table, since prev data is not table
                Logs = {}
            }, robloxMetadata
        end
        const dataClone = deepcopy(data)
        if typeof(dataClone.Logs) ~= "table" then
            robloxMetadata.LogsTypeError = "expected table, got "..typeof(dataClone.Logs)
            dataClone.Logs = {}
        end 
        return dataClone, robloxMetadata
    end
    const params = table.pack(...)
    const cmdData = assert(Commands[cmdName], "undefined command") -- always return command data
    if cmdData.Yields then -- cannot be executed in UpdateAsync callback
        local id = "No ID" -- will be generated when logging command start
        const calltime = DateTime.now() -- when execution started
        -- Log command start
        const startUpdateOk, startUpdateErr = pcall(NapLogDataStore.UpdateAsync, NapLogDataStore, player.User.DomainId, function(oldValue)
            const value, metadata = typeData(oldValue)
            id = generateID(#value.Logs, calltime) -- generate unique id representing command execution
            table.insert(value.Logs, { -- add log
                Id = id,
                Time = calltime,
                Command = cmdName,
                Params = params 
            })

            return value, {player.UserId}, metadata -- the new value, runner's user domain id, metadata
        end)
        if not startUpdateOk then -- command start log fail; cannot run command
            return { -- early return report
                CmdErr = "CmdStartUpdateAsyncError",
                StartUpdateAsyncError = startUpdateErr,
            }, "Error while logging command start"
        end
        -- Run the command.
        const cmdOk, cmdResult = pcall(cmdData.Run, player, ...) -- protected call command
        -- Log after running the command
        const resultUpdateOk, resultUpdateErr = pcall(NapLogDataStore.UpdateAsync, NapLogDataStore, player.User.DomainId, function(oldValue)
            const value, metadata = typeData(oldValue) -- to get valid type. metadata stores previous data error
            const calltime = DateTime.now()

            local log = {
                Id = id,
                Time = calltime,
                Ok = cmdOk
            }
            if cmdOk then
                log.Result = cmdResult
            else
                log.Error = cmdResult
            end

            table.insert(value.Logs, log)
            return value, {player.UserId}, metadata
        end)

        -- Write report
        const report = {} -- 1st return
        local message = nil -- 2nd return
        if not resultUpdateOk then -- write result logging error information
            report.ResultUpdateAsyncError = resultUpdateErr
        end
        if cmdOk then -- Command execution no error
            report.CmdResult = cmdResult -- add success result
            if resultUpdateOk then -- All Good
                message = nil
            else -- Command success, result log failure
                message = "Failed to log command. No worry, command was successful"
            end
        else -- command errored
            report.CmdError = cmdResult -- add error message 
            if resultUpdateOk then -- Command fail, result log success
                message = "The command errored!"
            else -- Command and result log fail
                message = "The command errored, and Failed to log command!"
            end
        end
        return report, message
    else
        -- will be written after executing command 
        local cmdOk = false -- didn't command errored
        local cmdOkResult = nil
        local cmdErr = nil

        const logOk, logErr = pcall(NapLogDataStore.UpdateAsync, NapLogDataStore, player.User.DomainId, function(oldValue)
            const value, metadata = typeData(oldValue)
            const calltime = DateTime.now()
            const id = generateID(#value.Logs, calltime) -- generate unique id
            -- Run the command
            const ok, result = pcall(cmdData.Run, player, table.unpack(params)) -- protected call inside oldValue
            -- Log the result
            const Log = { -- log base
                Id = id,
                Time = calltime,
                Command = cmdName,
                Params = params,
            }
            if ok then -- no command error
                Log.Result = result
                cmdOk = true
                cmdOkResult = cmdOkResult
            else -- command error
                Log.Error = result
                cmdErr = result
            end

            return value, {player.UserId}, metadata -- newly updated data
        end)
        -- Write report
        const report = {} -- 1st return
        local message = nil -- 2nd return
        if not logOk then -- write command logging error information
            report.LogError = logErr
        end
        if cmdOk then -- Command execution no error
            report.CmdResult = cmdOkResult
            if logOk then -- All Good
                message = nil 
            else -- Command success, result log failure
                message = "Failed to log command. No worry, command was successful"
            end
        else -- command errored
            if cmdErr == nil then -- command function didn't run
                if logOk then -- unexpected condition
                    message = "Didn't run command"
                    warn("Command didn't run while command log is ok") 
                else -- Command and result log fail
                    message = "Didn't run command because command log failure"
                end
            else -- some command error value 
                report.CmdError = cmdErr -- add error message 
                if logOk then -- Command fail, result log success
                    message = "Command errored"
                else -- Command and result log fail
                    message = "The command errored, and Failed to log command!"
                end
            end
        end
        return report, message
    end
end

const function ProcessCommand_CheckPermission(player: Player, cmdName: string, ...)
    const cmdData = assert(Commands[cmdName], "undefined command")
    -- no permission checks yet.
    return ProcessCommand_LogUpdate(player, cmdData, ...)
end

const function ProcessCommand_ValidateCommandType(player: Player, cmd: string, ...)
    if cmd == nil then
        return nil, 'expected a command!'
    end
    if type(cmd) ~= 'string' then
        return nil, `expected a string command, got {typeof(cmd)}`
    end
    const commandData = Commands[cmd]
    if commandData then
        return ProcessCommand_CheckPermission(player, cmd, ...)
    end
    return nil, `unknown commnad '{cmd}'`
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
    return ProcessCommand_ValidateCommandType(player, ...)
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