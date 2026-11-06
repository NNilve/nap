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
    const textbox = Instance.new("TextBox") -- textbox to input command
    const inputContext = Instance.new("InputContext") -- context to contain InputAction
    const toggleCommandAction = Instance.new("InputAction") -- activate to toggle visiblity
    const buttonBinding = Instance.new("InputBinding") -- press button to activate bind
    const keyboardBinding = Instance.new("InputBinding") -- press keybaord bind
    const toggleCommandButton = Instance.new("TextButton") -- the button that press to activate
    -- names in datamodel
    textbox.Name = "CommandBox"
    inputContext.Name = "NapInputContext"
    toggleCommandAction.Name = "CommandBarToggle"
    buttonBinding.Name = "Button"
    keyboardBinding.Name = "Keyboard"
    toggleCommandButton.Name = "CommandBarToggle"
    -- Set parent so that gui and controls do
    textbox.Parent = screenGui
    inputContext.Parent = screenGui
    toggleCommandAction.Parent = inputContext -- group the action to manage them all with it
    buttonBinding.Parent = toggleCommandAction -- must be child of action to trigger the action
    keyboardBinding.Parent= toggleCommandAction -- must be child of action to trigger the action
    toggleCommandButton.Parent = screenGui
    -- Button GUI props change
    toggleCommandButton.Position = UDim2.new(1,0,0.2,0)
    toggleCommandButton.AnchorPoint = Vector2.new(1, 0.5) -- prevent overflowing bounds
    toggleCommandButton.Size = UDim2.new(0.1,0,0.1,0)
    -- Make toggleCommandButton square
    const aspectRatioConstraint = Instance.new("UIAspectRatioConstraint")
    aspectRatioConstraint.AspectRatio = 1 -- x, y equal size
    aspectRatioConstraint.Parent = toggleCommandButton -- parent button
    -- textbox
    textbox.ClearTextOnFocus = false -- focus does not reset the 

    toggleCommandAction.Type = Enum.InputActionType.Bool -- press and release command
    toggleCommandAction.Pressed:Connect(function() -- call when keyboard or button pressed
        textbox.Visible = not textbox.Visible -- negate textbox.Visible
    end) -- toggle visibility callback
    
    buttonBinding.UIButton = toggleCommandButton -- make button binding for action
    keyboardBinding.KeyCode = Enum.KeyCode.F3 -- make keyboard press binding for action

    textbox.ReturnPressedFromOnScreenKeyboard:Connect(function() -- press enter to send command
        print("should send the command:")
        print(textbox.Text)
    end)

    return true, "gui initialized"
end

return NapClient