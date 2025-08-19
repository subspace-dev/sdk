json = require("json")

Subspace = "RmrKN2lAw5nu9eIQzXXi9DYT-95PqaLURnG9PRsoVuo"

Permissions = {
    SEND_MESSAGES = 1 << 0,    -- 1
    MANAGE_NICKNAMES = 1 << 1, -- 2
    MANAGE_MESSAGES = 1 << 2,  -- 4
    KICK_MEMBERS = 1 << 3,     -- 8
    BAN_MEMBERS = 1 << 4,      -- 16
    MANAGE_CHANNELS = 1 << 5,  -- 32
    MANAGE_SERVER = 1 << 6,    -- 64
    MANAGE_ROLES = 1 << 7,     -- 128
    MANAGE_MEMBERS = 1 << 8,   -- 256
    MENTION_EVERYONE = 1 << 9, -- 512
    ADMINISTRATOR = 1 << 10,   -- 1024
    ATTACHMENTS = 1 << 11,     -- 2048
    MANAGE_BOTS = 1 << 12,     -- 4096
}

Helpers = {
    VarOrNil = function(var)
        return var ~= "" and var or nil
    end,

    ValidateCondition = function(condition, msg, body)
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
    end,

    HasPermission = function(permissions, permission)
        return (permissions & permission) == permission
    end
}

Bot = Bot or {
    Subspace = "RmrKN2lAw5nu9eIQzXXi9DYT-95PqaLURnG9PRsoVuo", -- Readonly
    Version_ = "1.0.0",                                       -- Readonly
    JoinedServers = {},
    Subscriptions = {},
    PossibleEvents = { -- Readonly
        on_message_send = "on_message_send",
        on_message_edit = "on_message_edit",
        on_message_delete = "on_message_delete",

        on_member_join = "on_member_join",
        on_member_leave = "on_member_leave",
        on_member_update = "on_member_update",

        on_channel_create = "on_channel_create",
        on_channel_delete = "on_channel_delete",
        on_channel_update = "on_channel_update",

        on_category_create = "on_category_create",
        on_category_delete = "on_category_delete",
        on_category_update = "on_category_update"
    },
    RequiredEvents = {},
    Listeners = {
        on_message_send = function(e)
            print("on_message_send: " .. e.author.name .. ": " .. e.message.content)
        end,
        on_message_edit = function(e)
            print("on_message_edit: " .. e.author.name .. ": " .. e.message.content)
        end,
        on_message_delete = function(e) print("on_message_delete: " .. e.author.name .. ": " .. e.message.id) end,

        on_member_join = function(e) print("on_member_join: " .. e.member.name) end,
        on_member_leave = function(e) print("on_member_leave: " .. e.member.name) end,
        on_member_update = function(e) print("on_member_update: " .. e.member.name) end,

        on_channel_create = function(e) print("on_channel_create: " .. e.channel.name) end,
        on_channel_delete = function(e) print("on_channel_delete: " .. e.channel.name) end,
        on_channel_update = function(e) print("on_channel_update: " .. e.channel.name) end,

        on_category_create = function(e) print("on_category_create: " .. e.category.name) end,
        on_category_delete = function(e) print("on_category_delete: " .. e.category.name) end,
        on_category_update = function(e) print("on_category_update: " .. e.category.name) end,
    }
}

-- @param events_table table Table of events to subscribe to
function Bot.SetRequiredEvents(events_table)
    for event, value in pairs(events_table) do
        if not Bot.PossibleEvents[event] then
            error("Invalid event name: " .. event)
        end
        if type(value) ~= "boolean" then
            error("Invalid event value: " .. value)
        end
    end
    Bot.RequiredEvents = events_table

    -- Send messages to all joined servers to subscribe to the required events
    for serverId, value in pairs(Bot.JoinedServers) do
        if value then
            Send({
                Target = serverId,
                Action = "Subscribe",
                Events = json.encode(Bot.RequiredEvents)
            })
        end
    end
end

-- Set a listener function for an event
-- @param event string Event name
-- @param listener function Listener function
function Bot.SetListener(event, listener)
    if not Bot.PossibleEvents[event] then
        error("Invalid event name: " .. event)
    end
    Bot.Listeners[event] = listener
end

-- @param serverId string Server ID
-- @param channelId string Channel ID
-- @param content string Content
-- @param replyTo string Reply to message ID
-- @param attachments table Attachments
function Bot.SendMessage(serverId, channelId, content, replyTo, attachments)
    if not Bot.JoinedServers[tostring(serverId)] then
        print("SendMessage: Bot not joined to server " .. serverId)
        return
    end

    if not channelId then
        print("SendMessage: ChannelId is required")
        return
    end

    if content and type(content) ~= "string" then
        print("SendMessage: Content must be a string")
        return
    end

    if not content or #content == 0 then
        print("SendMessage: Content is required")
        return
    end

    local tags = {
        ["Channel-Id"] = tostring(channelId),
    }
    if replyTo then
        tags["Reply-To"] = tostring(replyTo)
    end
    if attachments and type(attachments) == "table" then
        tags["Attachments"] = json.encode(attachments)
    end

    ao.send({
        Target = serverId,
        Action = "Send-Message",
        Tags = tags,
        Data = content
    })
end

Handlers.add("Join-Server", function(msg)
    assert(msg.From == Subspace, "Join-Server: Invalid sender " .. msg.From)

    local serverId = Helpers.VarOrNil(msg.Tags["Server-Id"])

    if Helpers.ValidateCondition(not serverId, msg, {
            Status = "400",
            Data = json.encode({
                error = "ServerId is required"
            })
        }) then
        return
    end

    -- TODO: Server blacklisting can be implemetned here

    -- Reply to Subspace that we're ready to join
    msg.reply({
        Action = "Join-Server-Response",
        Status = "200",
        ["Server-Id"] = serverId,
        ["Events"] = json.encode(Bot.RequiredEvents)
    })
end)

Handlers.add("Join-Server-Result", function(msg)
    assert(msg.From == Subspace, "Join-Server-Result: Invalid sender " .. msg.From)

    local serverId = Helpers.VarOrNil(msg.Tags["Server-Id"])
    local status = Helpers.VarOrNil(msg.Tags["Status"])
    local data = Helpers.VarOrNil(msg.Data)

    if Helpers.ValidateCondition(not serverId, msg, {
            Status = "400",
            Data = json.encode({
                error = "ServerId is required"
            })
        }) then
        return
    end

    if status ~= "200" then
        Bot.JoinedServers[tostring(serverId)] = nil
        print("Join-Server-Result: " .. status .. " " .. data)
        return
    end

    -- Mark as joined
    Bot.JoinedServers[tostring(serverId)] = true

    -- Automatically subscribe to events if we have required events
    if next(Bot.RequiredEvents) then
        ao.send({
            Target = serverId,
            Action = "Subscribe",
            Tags = {
                Events = json.encode(Bot.RequiredEvents)
            }
        })
    end

    ao.send({
        Target = Subspace,
        Action = "Join-Server-Result-Response",
        Tags = { ["Server-Id"] = serverId }
    })
end)


-- Handle subscription response from server
Handlers.add("Subscribe-Response", function(msg)
    local serverId = msg.From
    local status = Helpers.VarOrNil(msg.Tags["Status"])
    local events = Helpers.VarOrNil(msg.Tags["Events"])

    if events then
        events = json.decode(events)
    else
        events = {}
    end

    if status == "200" then
        Bot.Subscriptions[tostring(serverId)] = events
    else
        Bot.Subscriptions[tostring(serverId)] = nil
    end
end)

-- Server has removed the bot: clean up local membership/subscription and unsubscribe
Handlers.add("Remove-Bot", function(msg)
    local serverId = msg.From

    Bot.JoinedServers[tostring(serverId)] = nil
    Bot.Subscriptions[tostring(serverId)] = nil
end)

-----

Handlers.add("Event", function(msg)
    local serverId = msg.From
    local eventType = Helpers.VarOrNil(msg.Tags["Event-Type"])
    local data = Helpers.VarOrNil(msg.Data) -- data is the json encoded data sent from the server

    if not Bot.JoinedServers[tostring(serverId)] then
        print("Event: Bot not joined to server " .. serverId)
        return
    end

    if not Bot.Subscriptions[tostring(serverId)] then
        print("Event: Bot not subscribed to server " .. serverId)
        return
    end

    if not eventType then
        print("Event: No event type")
        return
    end

    -- validate event type is in Bot.PossibleEvents
    if not Bot.PossibleEvents[eventType] then
        print("Event: Invalid event type " .. eventType)
        return
    end

    local listener = Bot.Listeners[eventType]
    if not listener then
        print("Event: No listener for event " .. eventType)
        return
    end

    ListenerProxy(listener, json.decode(data), eventType)
end)

function ListenerProxy(listener, data, eventType)
    if eventType == "on_message_send" or eventType == "on_message_edit" then
        data.message.reply = function(content, attachments)
            Bot.SendMessage(data.server.id, data.channel.id, content, data.message.id, attachments)
        end
    end

    listener(data)
end
