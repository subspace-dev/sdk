--[[
Bot Developer Package
A developer-friendly wrapper for creating Subspace bots with easy event handling

Usage:
local Bot = require("bot.dev")

Bot.onMessage(function(message, server)
    if message.content == "!hello" then
        Bot.sendMessage(server.id, message.channel_id, "Hello there!")
    end
end)

Bot.onMemberJoin(function(member, server)
    Bot.sendMessage(server.id, "welcome-channel", "Welcome " .. member.id .. "!")
end)

Bot.start("server-id", {"message_sent", "member_joined"})
--]]

local json = require("json")

-- Bot Developer API
local BotDev = {}

-- Internal state
local event_listeners = {}
local bot_config = {
    auto_join_servers = {},
    default_events = {},
    initialized = false
}

--#region Event Listener Registration

--- Register a message event listener
--- @param handler function Function that receives (message, server_info)
function BotDev.onMessage(handler)
    BotDev.addEventListener("message-sent", function(msg)
        local data = msg.data
        if data and data.message then
            local server_info = {
                id = msg.from,
                timestamp = msg.timestamp
            }
            handler(data.message, server_info)
        end
    end)
end

--- Register a message edit event listener
--- @param handler function Function that receives (message, server_info)
function BotDev.onMessageEdit(handler)
    BotDev.addEventListener("message-edited", function(msg)
        local data = msg.data
        if data and data.message then
            local server_info = {
                id = msg.from,
                timestamp = msg.timestamp
            }
            handler(data.message, server_info)
        end
    end)
end

--- Register a message delete event listener
--- @param handler function Function that receives (message_info, server_info)
function BotDev.onMessageDelete(handler)
    BotDev.addEventListener("message-deleted", function(msg)
        local data = msg.data
        if data then
            local server_info = {
                id = msg.from,
                timestamp = msg.timestamp
            }
            handler(data, server_info)
        end
    end)
end

--- Register a member join event listener
--- @param handler function Function that receives (member, server_info)
function BotDev.onMemberJoin(handler)
    BotDev.addEventListener("member-joined", function(msg)
        local data = msg.data
        if data then
            local server_info = {
                id = msg.from,
                timestamp = msg.timestamp
            }
            handler(data, server_info)
        end
    end)
end

--- Register a member leave event listener
--- @param handler function Function that receives (member, server_info)
function BotDev.onMemberLeave(handler)
    BotDev.addEventListener("member-left", function(msg)
        local data = msg.data
        if data then
            local server_info = {
                id = msg.from,
                timestamp = msg.timestamp
            }
            handler(data, server_info)
        end
    end)
end

--- Register a member update event listener
--- @param handler function Function that receives (member, server_info)
function BotDev.onMemberUpdate(handler)
    BotDev.addEventListener("member-updated", function(msg)
        local data = msg.data
        if data then
            local server_info = {
                id = msg.from,
                timestamp = msg.timestamp
            }
            handler(data, server_info)
        end
    end)
end

--- Register a member kick event listener
--- @param handler function Function that receives (member, server_info)
function BotDev.onMemberKick(handler)
    BotDev.addEventListener("member-kicked", function(msg)
        local data = msg.data
        if data then
            local server_info = {
                id = msg.from,
                timestamp = msg.timestamp
            }
            handler(data, server_info)
        end
    end)
end

--- Register a member ban event listener
--- @param handler function Function that receives (member, server_info)
function BotDev.onMemberBan(handler)
    BotDev.addEventListener("member-banned", function(msg)
        local data = msg.data
        if data then
            local server_info = {
                id = msg.from,
                timestamp = msg.timestamp
            }
            handler(data, server_info)
        end
    end)
end

--- Register a channel create event listener
--- @param handler function Function that receives (channel, server_info)
function BotDev.onChannelCreate(handler)
    BotDev.addEventListener("channel-created", function(msg)
        local data = msg.data
        if data then
            local server_info = {
                id = msg.from,
                timestamp = msg.timestamp
            }
            handler(data, server_info)
        end
    end)
end

--- Register a channel delete event listener
--- @param handler function Function that receives (channel, server_info)
function BotDev.onChannelDelete(handler)
    BotDev.addEventListener("channel-deleted", function(msg)
        local data = msg.data
        if data then
            local server_info = {
                id = msg.from,
                timestamp = msg.timestamp
            }
            handler(data, server_info)
        end
    end)
end

--- Register a channel update event listener
--- @param handler function Function that receives (channel, server_info)
function BotDev.onChannelUpdate(handler)
    BotDev.addEventListener("channel-updated", function(msg)
        local data = msg.data
        if data then
            local server_info = {
                id = msg.from,
                timestamp = msg.timestamp
            }
            handler(data, server_info)
        end
    end)
end

--- Register a role create event listener
--- @param handler function Function that receives (role, server_info)
function BotDev.onRoleCreate(handler)
    BotDev.addEventListener("role-created", function(msg)
        local data = msg.data
        if data then
            local server_info = {
                id = msg.from,
                timestamp = msg.timestamp
            }
            handler(data, server_info)
        end
    end)
end

--- Register a role delete event listener
--- @param handler function Function that receives (role, server_info)
function BotDev.onRoleDelete(handler)
    BotDev.addEventListener("role-deleted", function(msg)
        local data = msg.data
        if data then
            local server_info = {
                id = msg.from,
                timestamp = msg.timestamp
            }
            handler(data, server_info)
        end
    end)
end

--- Register a role update event listener
--- @param handler function Function that receives (role, server_info)
function BotDev.onRoleUpdate(handler)
    BotDev.addEventListener("role-updated", function(msg)
        local data = msg.data
        if data then
            local server_info = {
                id = msg.from,
                timestamp = msg.timestamp
            }
            handler(data, server_info)
        end
    end)
end

--- Register a generic event listener
--- @param event_name string The event name (e.g., "message-sent")
--- @param handler function The handler function
function BotDev.addEventListener(event_name, handler)
    if not event_listeners[event_name] then
        event_listeners[event_name] = {}

        -- Register the actual handler with the core system
        Handlers.add(event_name, function(msg)
            local listeners = event_listeners[event_name]
            if listeners then
                for _, listener in ipairs(listeners) do
                    local ok, err = pcall(listener, msg)
                    if not ok then
                        print("Error in " .. event_name .. " listener: " .. tostring(err))
                    end
                end
            end
        end)
    end

    table.insert(event_listeners[event_name], handler)
end

--- Remove an event listener
--- @param event_name string The event name
--- @param handler function The handler function to remove
function BotDev.removeEventListener(event_name, handler)
    local listeners = event_listeners[event_name]
    if listeners then
        for i, listener in ipairs(listeners) do
            if listener == handler then
                table.remove(listeners, i)
                break
            end
        end
    end
end

--#endregion

--#region Bot Actions

--- Send a message to a channel
--- @param server_id string
--- @param channel_id string
--- @param content string
--- @param options table|nil Optional parameters {attachments, reply_to}
function BotDev.sendMessage(server_id, channel_id, content, options)
    options = options or {}

    if utils and utils.bot_actions then
        utils.bot_actions.sendMessage(
            server_id,
            channel_id,
            content,
            options.attachments,
            options.reply_to
        )
    else
        -- Fallback: send directly
        send({
            target = bot.id,
            action = "send-message",
            ["server-id"] = server_id,
            ["channel-id"] = channel_id,
            content = content,
            attachments = options.attachments or {},
            ["reply-to"] = options.reply_to
        })
    end
end

--- Edit a message
--- @param server_id string
--- @param channel_id string
--- @param message_id string
--- @param content string
function BotDev.editMessage(server_id, channel_id, message_id, content)
    if utils and utils.bot_actions then
        utils.bot_actions.editMessage(server_id, channel_id, message_id, content)
    else
        send({
            target = bot.id,
            action = "edit-message",
            ["server-id"] = server_id,
            ["channel-id"] = channel_id,
            ["message-id"] = message_id,
            content = content
        })
    end
end

--- Delete a message
--- @param server_id string
--- @param channel_id string
--- @param message_id string
function BotDev.deleteMessage(server_id, channel_id, message_id)
    if utils and utils.bot_actions then
        utils.bot_actions.deleteMessage(server_id, channel_id, message_id)
    else
        send({
            target = bot.id,
            action = "delete-message",
            ["server-id"] = server_id,
            ["channel-id"] = channel_id,
            ["message-id"] = message_id
        })
    end
end

--- Join a server
--- @param server_id string
function BotDev.joinServer(server_id)
    if utils and utils.bot_actions then
        utils.bot_actions.joinServer(server_id)
    else
        send({
            target = bot.id,
            action = "join-server",
            ["server-id"] = server_id
        })
    end
end

--- Leave a server
--- @param server_id string
function BotDev.leaveServer(server_id)
    if utils and utils.bot_actions then
        utils.bot_actions.leaveServer(server_id)
    else
        send({
            target = bot.id,
            action = "leave-server",
            ["server-id"] = server_id
        })
    end
end

--- Subscribe to server events
--- @param server_id string
--- @param events table Array of event names
function BotDev.subscribeToServer(server_id, events)
    if utils and utils.bot_actions then
        utils.bot_actions.subscribeToServer(server_id, events)
    else
        send({
            target = bot.id,
            action = "subscribe-to-server",
            ["server-id"] = server_id,
            events = events
        })
    end
end

--#endregion

--#region Utility Functions

--- Check if a message mentions the bot
--- @param message table The message object
--- @return boolean
function BotDev.isMentioned(message)
    if not message.content then return false end
    local bot_info = BotDev.getBotInfo()
    if not bot_info then return false end

    return message.content:find("<@" .. bot_info.id .. ">") ~= nil
end

--- Extract command from message content
--- @param message table The message object
--- @param prefix string Command prefix (default: "!")
--- @return string|nil command, string|nil args
function BotDev.parseCommand(message, prefix)
    prefix = prefix or "!"
    if not message.content or message.content:sub(1, #prefix) ~= prefix then
        return nil, nil
    end

    local content = message.content:sub(#prefix + 1)
    local space_pos = content:find(" ")

    if space_pos then
        local command = content:sub(1, space_pos - 1):lower()
        local args = content:sub(space_pos + 1)
        return command, args
    else
        return content:lower(), ""
    end
end

--- Get bot information
--- @return table|nil
function BotDev.getBotInfo()
    if utils and utils.bot_actions then
        return utils.bot_actions.getBotInfo()
    elseif bot then
        return bot
    end
    return nil
end

--- Get servers the bot is in
--- @return table
function BotDev.getServers()
    if utils and utils.bot_actions then
        return utils.bot_actions.getServers()
    elseif bot then
        return bot.servers or {}
    end
    return {}
end

--- Check if bot is subscribed to a server
--- @param server_id string
--- @return boolean
function BotDev.isSubscribed(server_id)
    if utils and utils.bot_actions then
        return utils.bot_actions.isSubscribed(server_id)
    end
    return false
end

--#endregion

--#region Configuration and Initialization

--- Configure the bot with default settings
--- @param config table Configuration options
function BotDev.configure(config)
    config = config or {}

    if config.auto_join_servers then
        bot_config.auto_join_servers = config.auto_join_servers
    end

    if config.default_events then
        bot_config.default_events = config.default_events
    end

    if config.command_prefix then
        bot_config.command_prefix = config.command_prefix
    end
end

--- Start the bot and join configured servers
--- @param server_ids table|string Server ID(s) to join
--- @param events table|nil Events to subscribe to
function BotDev.start(server_ids, events)
    if bot_config.initialized then
        print("Bot already initialized")
        return
    end

    -- Normalize server_ids to table
    if type(server_ids) == "string" then
        server_ids = { server_ids }
    end

    -- Use provided events or defaults
    events = events or bot_config.default_events or { "message_sent" }

    -- Join servers and subscribe to events
    for _, server_id in ipairs(server_ids) do
        BotDev.joinServer(server_id)

        -- Add a small delay before subscribing
        -- In a real implementation, you'd want to wait for join confirmation
        BotDev.subscribeToServer(server_id, events)
    end

    bot_config.initialized = true
    print("Bot started and joined " .. #server_ids .. " server(s)")
end

--- Create a command handler with automatic parsing
--- @param command string The command name (without prefix)
--- @param handler function Function that receives (args, message, server)
--- @param options table|nil Options {prefix, description, usage}
function BotDev.command(command, handler, options)
    options = options or {}
    local prefix = options.prefix or bot_config.command_prefix or "!"

    BotDev.onMessage(function(message, server)
        local cmd, args = BotDev.parseCommand(message, prefix)
        if cmd == command:lower() then
            handler(args, message, server)
        end
    end)
end

--#endregion

--#region Helper Extensions

--- Add string extensions for easier usage
local function string_startswith(str, prefix)
    return str:sub(1, #prefix) == prefix
end

local function string_split(str, delimiter)
    local result = {}
    local pattern = "([^" .. delimiter .. "]+)"
    for match in str:gmatch(pattern) do
        table.insert(result, match)
    end
    return result
end

-- Add to string metatable if not already present
local string_mt = getmetatable("")
if string_mt and not string_mt.__index.startswith then
    string_mt.__index.startswith = string_startswith
end
if string_mt and not string_mt.__index.split then
    string_mt.__index.split = string_split
end

--#endregion

--#region Example Usage

--[[
Example Bot Implementation:

local Bot = require("bot.dev")

-- Configure the bot
Bot.configure({
    command_prefix = "!",
    default_events = {"message_sent", "member_joined", "member_left"},
    auto_join_servers = {"server-id-1", "server-id-2"}
})

-- Simple message handler
Bot.onMessage(function(message, server)
    if message.content == "ping" then
        Bot.sendMessage(server.id, message.channel_id, "pong!")
    end
end)

-- Command handler using the command helper
Bot.command("hello", function(args, message, server)
    local name = args ~= "" and args or "there"
    Bot.sendMessage(server.id, message.channel_id, "Hello " .. name .. "! 👋")
end)

Bot.command("echo", function(args, message, server)
    if args ~= "" then
        Bot.sendMessage(server.id, message.channel_id, args)
    else
        Bot.sendMessage(server.id, message.channel_id, "Usage: !echo <message>")
    end
end)

-- Welcome new members
Bot.onMemberJoin(function(member, server)
    local welcome_channel = "welcome-channel-id"
    Bot.sendMessage(server.id, welcome_channel,
        "Welcome to the server, <@" .. member.user_id .. ">! 🎉\n" ..
        "Please read the rules and introduce yourself!")
end)

-- Log member departures
Bot.onMemberLeave(function(member, server)
    local log_channel = "log-channel-id"
    Bot.sendMessage(server.id, log_channel,
        "📤 " .. member.user_id .. " has left the server.")
end)

-- Moderation: Auto-delete messages with bad words
Bot.onMessage(function(message, server)
    local bad_words = {"spam", "badword1", "badword2"}
    local content_lower = message.content:lower()

    for _, word in ipairs(bad_words) do
        if content_lower:find(word) then
            Bot.deleteMessage(server.id, message.channel_id, message.id)
            Bot.sendMessage(server.id, message.channel_id,
                "⚠️ Message deleted: inappropriate content",
                {reply_to = message.id})
            break
        end
    end
end)

-- React to mentions
Bot.onMessage(function(message, server)
    if Bot.isMentioned(message) then
        Bot.sendMessage(server.id, message.channel_id,
            "You mentioned me! How can I help? 🤖",
            {reply_to = message.id})
    end
end)

-- Advanced: Role management command
Bot.command("role", function(args, message, server)
    local parts = args:split(" ")
    local action = parts[1]
    local role_name = parts[2]

    if action == "list" then
        Bot.sendMessage(server.id, message.channel_id,
            "Available roles: Member, Helper, Moderator")
    elseif action == "assign" and role_name then
        Bot.sendMessage(server.id, message.channel_id,
            "Role assignment feature coming soon!")
    else
        Bot.sendMessage(server.id, message.channel_id,
            "Usage: !role list | !role assign <role_name>")
    end
end)

-- Start the bot
Bot.start({"server-id-1", "server-id-2"}, {"message_sent", "member_joined", "member_left"})

print("🤖 Bot is now running!")
--]]

--#endregion

return BotDev
