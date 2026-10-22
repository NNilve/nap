const ReplicatedStorage = game:GetService("ReplicatedStorage")
-- Remote Instance
const CommandRequestRemote = Instance.new("RemoteFunction")
CommandRequestRemote.Name = "NapCommand" -- Name for localscripts to use
CommandRequestRemote.Parent = ReplicatedStorage -- Clients can now request command execution

return table.freeze({
    CommandRequestRemote = CommandRequestRemote
})