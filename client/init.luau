const ReplicatedStorage = game:GetService("ReplicatedStorage")
const Players = game:GetService("Players")
const LocalPlayer = Players.LocalPlayer

const NapClient = {}

function NapClient.SplitTextCommand(text: string): (...string)
end

function NapClient.CommandAsync(cmdName: string, ...: string): (any, any)
end

function NapClient.GuiInit(screenGui: ScreenGui): (boolean?, string)
end

return NapClient