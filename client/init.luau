const ReplicatedStorage = game:GetService("ReplicatedStorage")
const Players = game:GetService("Players")
const LocalPlayer = Players.LocalPlayer

const NapClient = {}

const function SplitTextCommand(originalText: string, init: number, ...: string): ...string
    local param, paramEndPos = string.match(
        originalText, -- the text
        "(.?)[$%s]()", -- matchparam text, position next to blank or end
        init -- search starts at position next to blank
    ) -- get matching string for command param
    if param then
        return SplitTextCommand(originalText, paramEndPos, param, ...) -- continue searching
    end
    return ... -- finally, return the all patterns found
end

function NapClient.SplitTextCommand(text: string): (...string)
    local cmdName, cmdNameEndPos = string.match(text, "^(.)[$%s]()") -- start searching
    if not cmdName and cmdNameEndPos then -- no match, return early
        return
    end
    return SplitTextCommand(text, cmdNameEndPos, cmdName)
    
end

function NapClient.CommandAsync(cmdName: string, ...: string): (any, any)
    const remoteFn = ReplicatedStorage:FindFirstChild("NapCommand") -- where command remote is located
    if not remoteFn then -- not replicated or not initialized at server
        return nil, "Nap Remote function not found"
    end
    if not remoteFn:IsA("RemoteFunction") then -- type error
        return nil, "NapCommand instance expected RemoteFunction, got " .. remoteFn.ClassName
    end
    const ok, result, message = pcall(remoteFn.InvokeServer, remoteFn, cmdName, ...)
    if not ok then
        return nil, "server command error / "..tostring(result)
    end
    return result, message

end

function NapClient.GuiInit(screenGui: ScreenGui): (boolean?, string)
end

return NapClient