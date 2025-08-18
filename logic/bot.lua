json = require("json")

----------------------------------------------------------------------------
-- Subspace Bot Logic
--
-- Purpose:
-- - Maintain bot metadata (name and public visibility)
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
Description = Description or "{DESCRIPTION}"
Pfp = Pfp or "{PFP}"
PublicBot = PublicBot or ("{PUBLIC}" == "true")
Version_ = Version_ or "1.0.0"

-- Membership and subscriptions are tracked as presence maps keyed by server id
JoinedServers = JoinedServers or {}         -- { [serverId:string] = true }
SubscribedServers = SubscribedServers or {} -- { [serverId:string] = true }

-- Events array to store incoming events from servers
Events = Events or {} -- Array of event objects

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

-- Update bot's public flag and name. Only Subspace can issue this.
Handlers.add("Update-Bot", function(msg)
    assert(msg.From == Subspace, "❌[auth error] sender not authorized to update the bot")

    local publicBot = VarOrNil(msg.Tags["Public-Bot"])
    if publicBot then
        publicBot = (publicBot == "true")
    end

    local name = VarOrNil(msg.Tags.Name)
    local pfp = VarOrNil(msg.Tags.Pfp)
    local description = VarOrNil(msg.Tags.Description)

    -- Update in-memory bot metadata; omit fields that were not provided
    if publicBot ~= nil then PublicBot = publicBot end
    if name then Name = name end
    if pfp then Pfp = pfp end
    if description then Description = description end

    msg.reply({
        Action = "Update-Bot-Response",
        Status = "200",
    })
    SyncProcessState()
end)

----------------------------------------------------------------------------

-- Push current bot state to Hyperbeam's patch cache for fast external reads
function SyncProcessState()
    local state = {
        version = tostring(Version_),
        owner = Owner,
        name = Name,
        pfp = Pfp,
        description = Description,
        publicBot = PublicBot,
        joinedServers = JoinedServers,
        subscribedServers = SubscribedServers,
        events = Events,
        eventCount = #Events
    }

    Send({
        Target = ao.id,
        device = "patch@1.0",
        cache = { bot = state }
    })
end

InitialSync = InitialSync or false
if not InitialSync then
    InitialSync = true
    SyncProcessState()
    print("✅ Bot initial sync complete")
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

    -- Reply to Subspace that we're ready to join
    msg.reply({
        Action = "Join-Server-Response",
        Status = "200",
        Tags = { ["Server-Id"] = serverId }
    })
    SyncProcessState()
end)

-- Handle successful server approval and complete the join process
Handlers.add("Join-Server-Success", function(msg)
    assert(msg.From == Subspace, "You are not allowed to complete server join")

    local serverId = VarOrNil(msg.Tags["Server-Id"])

    if ValidateCondition(not serverId, msg, {
            Status = "400",
            Data = json.encode({
                error = "ServerId is required"
            })
        }) then
        return
    end

    -- Mark as joined
    JoinedServers[tostring(serverId)] = true

    -- Subscribe to server events
    ao.send({
        Target = serverId,
        Action = "Subscribe"
    })
    ao.send({
        Target = Subspace,
        Action = "Join-Server-Success-Response",
        Tags = { ["Server-Id"] = serverId }
    })

    SyncProcessState()
end)

-- Handle subscription response from server
Handlers.add("Subscribe-Response", function(msg)
    local serverId = msg.From
    local status = VarOrNil(msg.Tags["Status"])

    if status == "200" then
        SubscribedServers[tostring(serverId)] = true
        SyncProcessState()
        print("✅ Bot successfully subscribed to server " .. serverId)
    else
        -- If subscription failed, cleanup joined state
        JoinedServers[tostring(serverId)] = nil
        SyncProcessState()
        print("❌ Bot failed to subscribe to server " .. serverId)
    end
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
    local serverIdFromTag = VarOrNil(msg.Tags["X-Server-Id"])
    local eventType = VarOrNil(msg.Tags["X-Event-Type"]) or "MESSAGE_SENT"
    local channelId = VarOrNil(msg.Tags["X-Channel-Id"])
    local authorId = VarOrNil(msg.Tags["X-Author-Id"])
    local messageId = VarOrNil(msg.Tags["X-Message-Id"])
    local fromBot = VarOrNil(msg.Tags["X-From-Bot"]) and msg.Tags["X-From-Bot"] == "true" or false
    local replyTo = VarOrNil(msg.Tags["X-Reply-To"])
    local attachments = VarOrNil(msg.Tags["X-Attachments"])
    local timestamp = VarOrNil(msg.Tags["X-Timestamp"])
    local channelName = VarOrNil(msg.Tags["X-Channel-Name"])
    local serverName = VarOrNil(msg.Tags["X-Server-Name"])
    local authorNickname = VarOrNil(msg.Tags["X-Author-Nickname"])
    local editorId = VarOrNil(msg.Tags["X-Editor-Id"])
    local deleterId = VarOrNil(msg.Tags["X-Deleter-Id"])
    local content = msg.Data

    -- Verify the server ID matches both the sender and the tag
    if ValidateCondition(serverIdFromTag and serverId ~= serverIdFromTag, msg, {
            Status = "400",
            Data = json.encode({
                error = "Server ID mismatch: sender does not match Server-Id tag"
            })
        }) then
        return
    end

    -- Verify bot is joined to this server
    if ValidateCondition(not JoinedServers[serverId], msg, {
            Status = "400",
            Data = json.encode({
                error = "Bot is not in the server"
            })
        }) then
        return
    end

    -- Verify bot is subscribed to this server
    if ValidateCondition(not SubscribedServers[serverId], msg, {
            Status = "400",
            Data = json.encode({
                error = "Bot is not subscribed to the server"
            })
        }) then
        return
    end

    -- Validate required fields for message events
    if ValidateCondition(not channelId, msg, {
            Status = "400",
            Data = json.encode({
                error = "Channel-Id is required for message events"
            })
        }) then
        return
    end

    if ValidateCondition(not authorId, msg, {
            Status = "400",
            Data = json.encode({
                error = "Author-Id is required for message events"
            })
        }) then
        return
    end

    if ValidateCondition(not messageId, msg, {
            Status = "400",
            Data = json.encode({
                error = "Message-Id is required for message events"
            })
        }) then
        return
    end

    -- @param replyContent string
    local function reply(replyContent)
        ao.send({
            Target = serverId,
            Action = "Send-Message",
            Data = replyContent,
            Tags = { ["Channel-Id"] = channelId, ["Reply-To"] = messageId }
        })
    end

    local event = {
        eventType = eventType,
        serverId = serverId,
        channelId = channelId,
        messageId = messageId,
        timestamp = timestamp,
        content = content,
        attachments = attachments,
        replyTo = replyTo,
        authorId = authorId,
        authorNickname = authorNickname or "",
        fromBot = fromBot,
        serverName = serverName,
        channelName = channelName,
        editorId = editorId or "",
        deleterId = deleterId or "",
        raw = msg,
        reply = reply
    }

    -- Call main bot logic with structured event data
    Main(event)

    SyncProcessState()
end)

function Setup()
    -- update subscriptions to receive only specific events
    -- or any other styup that needs to run once
end

---@class BotEvent
---@field eventType string Event type: "MESSAGE_SENT" | "MESSAGE_EDITED" | "MESSAGE_DELETED"
---@field serverId string Server process ID
---@field channelId string Channel ID where the event occurred
---@field messageId string Message ID
---@field timestamp string Message timestamp
---@field content string Message content
---@field attachments string JSON string of attachments
---@field replyTo string|nil Message ID being replied to
---@field authorId string Author's user ID
---@field authorNickname string|nil Author's nickname (if available)
---@field fromBot boolean Whether the author is a bot
---@field serverName string Server name
---@field channelName string Channel name
---@field editorId string|nil User ID who edited the message (MESSAGE_EDITED only)
---@field deleterId string|nil User ID who deleted the message (MESSAGE_DELETED only)
---@field rawMessage table Raw message object from AO
---@field reply function Reply to the message
---@field raw table Raw message object from AO

---Main bot logic handler
---@param event BotEvent
function Main(event)
    local displayName = event.authorNickname ~= "" and event.authorNickname or event.authorId

    -- debug logs for testing
    print(displayName .. ": " .. event.content)

    -- if message is !ping, reply with pong, message can start with !ping and have more text after it
    if event.content:match("^!ping") and event.fromBot == false then
        event.reply("Pong!")
        print("replied to " .. displayName .. " with pong")
    end
end
