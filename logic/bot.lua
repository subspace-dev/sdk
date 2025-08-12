json = require("json")

----------------------------------------------------------------------------
-- Subspace Bot Logic
--
-- Purpose:
-- - Maintain bot metadata (name, pfp, public visibility)
-- - Join/leave servers when instructed by the Subspace coordinator
-- - Track which servers the bot has joined/subscribed to
-- - Relay/handle server-originated events (hook points for future logic)
--
-- Notes:
-- - Storage is in-memory Lua tables to keep runtime simple and fast
-- - External persistence and caching is handled by Hyperbeam via SyncProcessState
----------------------------------------------------------------------------

----------------------------------------------------------------------------
--- VARIABLES

Subspace = "RmrKN2lAw5nu9eIQzXXi9DYT-95PqaLURnG9PRsoVuo"
Name = Name or "{NAME}"
Pfp = Pfp or "{PFP}"
PublicBot = PublicBot or ("{PUBLIC}" == "true")
Version = Version or "1.0.0"

-- Membership and subscriptions are tracked as presence maps keyed by server id
JoinedServers = JoinedServers or {}         -- { [serverId:string] = true }
SubscribedServers = SubscribedServers or {} -- { [serverId:string] = true }

----------------------------------------------------------------------------

-- Storage policy: in-memory tables only

-- Return nil for empty-string inputs so that tag lookups can be optional
function VarOrNil(var)
    return var ~= "" and var or nil
end

-- Guard helper: if 'condition' is true, immediately reply with an error envelope
-- and return true to signal that the caller should stop further processing
function ValidateCondition(condition, msg, body)
    if condition then
        body = body or {}
        body.Action = body.Action or msg.Action .. "-Response"
        body.Status = body.Status or "500"
        body.Data = body.Data or json.encode({
            error = "Internal server error"
        })
        msg.reply(body)
        return true
    else
        return false
    end
end

----------------------------------------------------------------------------

-- Update bot’s public flag, name and pfp. Only Subspace can issue this.
Handlers.add("Update-Bot", function(msg)
    assert(msg.From == Subspace, "❌[auth error] sender not authorized to update the bot")

    local publicBot = VarOrNil(msg.Tags["Public-Bot"])
    if publicBot then
        publicBot = (publicBot == "true")
    end

    local name = VarOrNil(msg.Tags.Name)
    local pfp = VarOrNil(msg.Tags.Pfp)

    -- Update in-memory bot metadata; omit fields that were not provided
    if publicBot ~= nil then PublicBot = publicBot end
    if name then Name = name end
    if pfp then Pfp = pfp end

    msg.reply({
        Action = "Update-Bot-Response",
        Status = "200",
    })
end)

----------------------------------------------------------------------------

-- Push current bot state to Hyperbeam’s patch cache for fast external reads
function SyncProcessState()
    local state = {
        version = tostring(Version),
        owner = Owner,
        name = Name,
        pfp = Pfp,
        publicBot = PublicBot,
        joinedServers = JoinedServers,
        subscribedServers = SubscribedServers,
    }

    Send({
        Target = ao.id,
        device = "patch@1.0",
        cache = { bot = state }
    })
end

----------------------------------------------------------------------------

-- Request to join a server and subscribe to its updates. Only Subspace can issue this.
Handlers.add("Join-Server", function(msg)
    assert(msg.From == Subspace, "You are not allowed to join servers")

    local serverId = VarOrNil(msg.Tags["Server-Id"])

    if ValidateCondition(not serverId, msg, {
            Status = "400",
            Data = json.encode({
                error = "ServerId is required"
            })
        }) then
        return
    end

    -- Hook: black/allow list checks could be added here if needed
    msg.reply({
        Action = "Join-Server-Response",
        Status = "200",
    })
    local joinResponse = Receive({ Action = "Join-Server-Success", From = serverId })
    if ValidateCondition(joinResponse.Status ~= "200", msg, {
            Status = "500",
            Data = json.encode(joinResponse.Data)
        }) then
        return
    end

    JoinedServers[tostring(serverId)] = true

    -- Subscribe to server events after a successful join
    ao.send({
        Target = serverId,
        Action = "Subscribe",
    })
    local subscribeResponse = Receive({ Action = "Subscribe-Response", From = serverId })
    if ValidateCondition(subscribeResponse.Status ~= "200", msg, {
            Status = "500",
            Data = json.encode(subscribeResponse.Data)
        }) then
        return
    end

    SubscribedServers[tostring(serverId)] = true
    SyncProcessState()
end)

-- Server has removed the bot: clean up local membership/subscription and unsubscribe
Handlers.add("Remove-Bot", function(msg)
    local serverId = msg.From

    JoinedServers[tostring(serverId)] = nil
    SubscribedServers[tostring(serverId)] = nil

    -- send unsubscription messages
    ao.send({
        Target = serverId,
        Action = "Unsubscribe",
    })
    SyncProcessState()
end)


----------------------------------------------------------------------------

-- Events sent from servers (hook points)

Handlers.add("Event-Message", function(msg)
    local serverId = msg.From

    if ValidateCondition(not JoinedServers[serverId], msg, {
            Status = "400",
            Data = json.encode({
                error = "Bot is not in the server"
            })
        }) then
        return
    end

    if ValidateCondition(not SubscribedServers[serverId], msg, {
            Status = "400",
            Data = json.encode({
                error = "Bot is not subscribed to the server"
            })
        }) then
        return
    end

    -- Hook: implement bot behavior in response to server messages here
end)
