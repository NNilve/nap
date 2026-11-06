const ReplicatedStorage = game:GetService("ReplicatedStorage")
const Players = game:GetService("Players")
const LocalPlayer = Players.LocalPlayer

const NapClient = {}

function NapClient.SplitTextCommand(text: string): (...string)
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