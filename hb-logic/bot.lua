local json = require("json")

--#region configuration

subspace_id = "WSeRkeXPzE_Zckh3w6wghWKGZ_7Lm9U61qXj_JSdujo"

--#endregion

--#region helpers

helpers = helpers or {
    logs = {},
    --- @type table<string, string>
    server_subscriptions = {}, -- {serverId = subscriptionId}
    status = {                 -- read only
        success = 200,
        created = 201,
        accepted = 202,
        no_content = 204,

        bad_request = 400,
        unauthorized = 401,
        payment_required = 402,
        forbidden = 403,
        not_found = 404,
        method_not_allowed = 405,
        not_acceptable = 406,
        content_too_large = 413,
        teapot = 418, -- 🫖
        too_many_requests = 429,

        internal_server_error = 500,
        not_implemented = 501,
    },
    --- @type table<string, Event>
    events = { -- read only
        message_sent = 10,
        message_edited = 20,
        message_deleted = 30,

        member_joined = 40,
        member_left = 50,
        member_updated = 60,
        member_kicked = 70,
        member_banned = 80,

        channel_created = 90,
        channel_deleted = 100,
        channel_updated = 110,

        category_created = 120,
        category_deleted = 130,
        category_updated = 140,

        role_created = 150,
        role_deleted = 160,
        role_updated = 170,
    }
}

--#endregion

--#region initialization

local function get_id()
    return tostring(math.random(10, 99) .. math.floor(os.time()))
end

--- @param err string
--- @return {status: number, error: string}
local function get_status_and_error(err)
    local status, error_text = err:match("^(%d+)|(.*)$")
    status = status or helpers.status.teapot
    error_text = error_text or err
    return {
        status = math.floor(status),
        error = error_text
    }
end

--- @param e table{timestamp: string, status: number, action: string, error: string}
local function pprint(e)
    -- [timestamp] status | action => error
    print(colors.blue .. "[" .. e.timestamp .. colors.reset .. "] " ..
        colors.bg_red .. tostring(e.status) .. colors.reset .. " | " ..
        colors.yellow .. e.action .. colors.reset .. " => " ..
        colors.red .. e.error .. colors.reset)
end

---@class Bot
bot = bot or {
    id = id,
    owner_id = owner,
    name = "",
    description = "",
    pfp = "",
    banner = "",
    public_bot = true,
    servers = {},
    required_events = {}
}

--#endregion

--#region utils

local utils = {
    var_or_nil = function(var)
        return var ~= "" and var or nil
    end,
    handle_run = function(func, msg)
        msg.reply = function(data)
            data.target = msg.from
            if not data["x-status"] then data["x-status"] = helpers.status.success end
            send(data)
        end
        local ok, err = pcall(func, msg)
        if not ok then
            -- error message format "status|error_text"
            local res = get_status_and_error(err)
            local error_item = {
                action = msg.action,
                error = res.error,
                status = res.status,
                timestamp = os.date("%Y-%m-%d %H:%M:%S", os.time() + 12600) -- GMT+5:30
            }
            table.insert(helpers.logs, error_item)
            pprint(error_item)
            send({
                target = msg.from,
                action = "error",
                ["x-status"] = res.status,
                ["x-error"] = res.error,
                ["x-action"] = msg.action,
                timestamp = os.time()
            })
        end
    end,
    get_id = get_id,
    --- @param txid string
    --- @return boolean
    valid_tx_id = function(txid)
        return #txid == 43 and txid:match("^[A-Za-z0-9_-]+$")
    end,
    servers = {
        --- @param serverId string
        --- @return boolean
        is_subscribed = function(serverId)
            return helpers.server_subscriptions[serverId] ~= nil
        end,
        --- @param serverId string
        --- @param subscriptionId string
        subscribe = function(serverId, subscriptionId)
            helpers.server_subscriptions[serverId] = subscriptionId
        end,
        --- @param serverId string
        unsubscribe = function(serverId)
            helpers.server_subscriptions[serverId] = nil
        end
    },
    bot_actions = {} -- Will be populated after bot_utils is defined
}

--#endregion

--#region setup

local function setup(msg)
    assert(msg.from == subspace_id, "403|unauthorized sender")

    local botName = msg["name"]
    local botDescription = msg["description"]
    local botPfp = msg["pfp"]
    local botBanner = msg["banner"]
    local publicBot = msg["public-bot"]
    local requiredEvents = msg["required-events"]

    bot.name = botName or ""
    bot.description = botDescription or ""
    bot.pfp = botPfp or ""
    bot.banner = botBanner or ""
    bot.public_bot = publicBot or true
    bot.required_events = requiredEvents or {}
end

Handlers.once("setup", function(msg)
    utils.handle_run(setup, msg)
end)

--#endregion

--#region event system core

-- Handle incoming events from servers and route to appropriate handlers
local function handle_event(msg)
    local eventType = msg["event-type"]
    local eventData = msg["data"]

    if eventData then
        eventData = json.decode(eventData)
    end

    -- Map numeric event types to handler names
    local event_handler_map = {
        [helpers.events.message_sent] = "message-sent",
        [helpers.events.message_edited] = "message-edited",
        [helpers.events.message_deleted] = "message-deleted",
        [helpers.events.member_joined] = "member-joined",
        [helpers.events.member_left] = "member-left",
        [helpers.events.member_updated] = "member-updated",
        [helpers.events.member_kicked] = "member-kicked",
        [helpers.events.member_banned] = "member-banned",
        [helpers.events.channel_created] = "channel-created",
        [helpers.events.channel_deleted] = "channel-deleted",
        [helpers.events.channel_updated] = "channel-updated",
        [helpers.events.category_created] = "category-created",
        [helpers.events.category_deleted] = "category-deleted",
        [helpers.events.category_updated] = "category-updated",
        [helpers.events.role_created] = "role-created",
        [helpers.events.role_deleted] = "role-deleted",
        [helpers.events.role_updated] = "role-updated"
    }

    local handler_name = event_handler_map[eventType]
    if handler_name then
        -- Create a message object for the handler
        local handler_msg = {
            from = msg.from, -- server ID
            action = handler_name,
            data = eventData,
            timestamp = msg.timestamp or os.time(),
            reply = function(data)
                -- Optional: bots can reply to events if needed
                data.target = msg.from
                send(data)
            end
        }

        -- Call the handler if it exists
        utils.handle_run(function(handler_msg)
            -- This will be handled by user-defined handlers
        end, handler_msg)
    end
end

Handlers.add("event", function(msg)
    utils.handle_run(handle_event, msg)
end)

--#endregion

--#region server interactions

local function join_server(msg)
    local serverId = utils.var_or_nil(msg["server-id"])

    assert(serverId, "400|server-id is required")
    assert(utils.valid_tx_id(serverId), "400|server-id must be a valid arweave tx id")

    -- Check if already in server
    assert(not bot.servers[serverId], "400|bot is already in this server")

    -- Send join request to subspace
    send({
        target = subspace_id,
        action = "join-server",
        ["server-id"] = serverId
    })

    msg.reply({
        action = "join-server-response",
        status = helpers.status.accepted,
    })
end

Handlers.add("join-server", function(msg)
    utils.handle_run(join_server, msg)
end)

local function leave_server(msg)
    local serverId = utils.var_or_nil(msg["server-id"])

    assert(serverId, "400|server-id is required")
    assert(bot.servers[serverId], "404|bot is not in this server")

    -- Unsubscribe from server events first
    if utils.servers.is_subscribed(serverId) then
        send({
            target = serverId,
            action = "unsubscribe"
        })
        utils.servers.unsubscribe(serverId)
    end

    -- Remove from bot's server list
    bot.servers[serverId] = nil

    -- Notify subspace to remove bot from server
    send({
        target = subspace_id,
        action = "remove-member",
        ["user-id"] = bot.id
    })

    msg.reply({
        action = "leave-server-response",
        status = helpers.status.success,
    })
end

Handlers.add("leave-server", function(msg)
    utils.handle_run(leave_server, msg)
end)

-- Handle server membership approval/rejection
local function add_member_response(msg)
    local serverId = msg.from
    local status = utils.var_or_nil(msg["status"])

    assert(status, "400|status is required from the server")

    if status == helpers.status.success then
        -- Bot was approved to join server
        bot.servers[serverId] = { approved = true }

        -- Auto-subscribe to required events if any
        if bot.required_events and #bot.required_events > 0 then
            send({
                target = serverId,
                action = "subscribe",
                events = bot.required_events
            })
        end

        msg.reply({
            action = "add-member-response",
            status = helpers.status.success,
        })
    else
        -- Bot was rejected
        bot.servers[serverId] = nil
        error(tostring(status) .. "|bot was rejected from server")
    end
end

Handlers.add("add-member-response", function(msg)
    utils.handle_run(add_member_response, msg)
end)

--#endregion

--#region message handling

local function send_message(msg)
    local serverId = utils.var_or_nil(msg["server-id"])
    local channelId = utils.var_or_nil(msg["channel-id"])
    local content = utils.var_or_nil(msg["content"])
    local attachments = msg["attachments"]
    local replyTo = utils.var_or_nil(msg["reply-to"])

    assert(serverId, "400|server-id is required")
    assert(channelId, "400|channel-id is required")
    assert(content or (attachments and #attachments > 0), "400|content or attachments required")

    -- Check if bot is in the server
    assert(bot.servers[serverId] and bot.servers[serverId].approved, "403|bot is not approved in this server")

    send({
        target = serverId,
        action = "send-message",
        ["channel-id"] = channelId,
        content = content,
        attachments = attachments or {},
        ["reply-to"] = replyTo
    })

    msg.reply({
        action = "send-message-response",
        status = helpers.status.success,
    })
end

Handlers.add("send-message", function(msg)
    utils.handle_run(send_message, msg)
end)

local function edit_message(msg)
    local serverId = utils.var_or_nil(msg["server-id"])
    local channelId = utils.var_or_nil(msg["channel-id"])
    local messageId = utils.var_or_nil(msg["message-id"])
    local content = utils.var_or_nil(msg["content"])

    assert(serverId, "400|server-id is required")
    assert(channelId, "400|channel-id is required")
    assert(messageId, "400|message-id is required")
    assert(content, "400|content is required")

    -- Check if bot is in the server
    assert(bot.servers[serverId] and bot.servers[serverId].approved, "403|bot is not approved in this server")

    send({
        target = serverId,
        action = "update-message",
        ["channel-id"] = channelId,
        ["message-id"] = messageId,
        content = content
    })

    msg.reply({
        action = "edit-message-response",
        status = helpers.status.success,
    })
end

Handlers.add("edit-message", function(msg)
    utils.handle_run(edit_message, msg)
end)

local function delete_message(msg)
    local serverId = utils.var_or_nil(msg["server-id"])
    local channelId = utils.var_or_nil(msg["channel-id"])
    local messageId = utils.var_or_nil(msg["message-id"])

    assert(serverId, "400|server-id is required")
    assert(channelId, "400|channel-id is required")
    assert(messageId, "400|message-id is required")

    -- Check if bot is in the server
    assert(bot.servers[serverId] and bot.servers[serverId].approved, "403|bot is not approved in this server")

    send({
        target = serverId,
        action = "delete-message",
        ["channel-id"] = channelId,
        ["message-id"] = messageId
    })

    msg.reply({
        action = "delete-message-response",
        status = helpers.status.success,
    })
end

Handlers.add("delete-message", function(msg)
    utils.handle_run(delete_message, msg)
end)

--#endregion

--#region subscriptions

local function subscribe_to_server(msg)
    local serverId = utils.var_or_nil(msg["server-id"])
    local events = msg["events"] or bot.required_events or {}

    assert(serverId, "400|server-id is required")
    assert(bot.servers[serverId] and bot.servers[serverId].approved, "403|bot is not approved in this server")

    send({
        target = serverId,
        action = "subscribe",
        events = events
    })

    msg.reply({
        action = "subscribe-to-server-response",
        status = helpers.status.success,
    })
end

Handlers.add("subscribe-to-server", function(msg)
    utils.handle_run(subscribe_to_server, msg)
end)

local function unsubscribe_from_server(msg)
    local serverId = utils.var_or_nil(msg["server-id"])

    assert(serverId, "400|server-id is required")
    assert(utils.servers.is_subscribed(serverId), "404|not subscribed to this server")

    send({
        target = serverId,
        action = "unsubscribe"
    })

    utils.servers.unsubscribe(serverId)

    msg.reply({
        action = "unsubscribe-from-server-response",
        status = helpers.status.success,
    })
end

Handlers.add("unsubscribe-from-server", function(msg)
    utils.handle_run(unsubscribe_from_server, msg)
end)

-- Handle subscription confirmations from servers
local function subscribe_response(msg)
    local serverId = msg.from
    local subscriberId = utils.var_or_nil(msg["subscriber-id"])
    local events = msg["events"]

    if subscriberId and subscriberId == bot.id then
        utils.servers.subscribe(serverId, subscriberId)

        msg.reply({
            action = "subscribe-response-ack",
            status = helpers.status.success,
        })
    end
end

Handlers.add("subscribe-response", function(msg)
    utils.handle_run(subscribe_response, msg)
end)

--#endregion

--#region bot utilities

-- Utility functions for bot actions
local bot_utils = {
    --- Send a message to a channel
    --- @param serverId string
    --- @param channelId string
    --- @param content string
    --- @param attachments table|nil
    --- @param replyTo string|nil
    sendMessage = function(serverId, channelId, content, attachments, replyTo)
        send({
            target = bot.id,
            action = "send-message",
            ["server-id"] = serverId,
            ["channel-id"] = channelId,
            content = content,
            attachments = attachments or {},
            ["reply-to"] = replyTo
        })
    end,

    --- Edit a message
    --- @param serverId string
    --- @param channelId string
    --- @param messageId string
    --- @param content string
    editMessage = function(serverId, channelId, messageId, content)
        send({
            target = bot.id,
            action = "edit-message",
            ["server-id"] = serverId,
            ["channel-id"] = channelId,
            ["message-id"] = messageId,
            content = content
        })
    end,

    --- Delete a message
    --- @param serverId string
    --- @param channelId string
    --- @param messageId string
    deleteMessage = function(serverId, channelId, messageId)
        send({
            target = bot.id,
            action = "delete-message",
            ["server-id"] = serverId,
            ["channel-id"] = channelId,
            ["message-id"] = messageId
        })
    end,

    --- Join a server
    --- @param serverId string
    joinServer = function(serverId)
        send({
            target = bot.id,
            action = "join-server",
            ["server-id"] = serverId
        })
    end,

    --- Leave a server
    --- @param serverId string
    leaveServer = function(serverId)
        send({
            target = bot.id,
            action = "leave-server",
            ["server-id"] = serverId
        })
    end,

    --- Subscribe to events from a server
    --- @param serverId string
    --- @param events table Array of event names
    subscribeToServer = function(serverId, events)
        send({
            target = bot.id,
            action = "subscribe-to-server",
            ["server-id"] = serverId,
            events = events or bot.required_events
        })
    end,

    --- Unsubscribe from a server
    --- @param serverId string
    unsubscribeFromServer = function(serverId)
        send({
            target = bot.id,
            action = "unsubscribe-from-server",
            ["server-id"] = serverId
        })
    end,

    --- Get bot information
    getBotInfo = function()
        return bot
    end,

    --- Get list of servers the bot is in
    getServers = function()
        return bot.servers
    end,

    --- Check if bot is subscribed to a server
    --- @param serverId string
    isSubscribed = function(serverId)
        return utils.servers.is_subscribed(serverId)
    end
}

-- Populate utils.bot_actions with bot_utils functions
utils.bot_actions = bot_utils

--#endregion

--#region example usage

--[[
Example usage for developers:

Users add handlers directly using the standard Handlers.add() function:

-- Handle message events
Handlers.add("message-sent", function(msg)
    local data = msg.data
    local message = data.message
    local serverId = msg.from

        -- Echo bot example
    if message.content:match("!echo (.+)") then
        local text = message.content:match("!echo (.+)")
        utils.bot_actions.sendMessage(serverId, message.channel_id, text)
    end

    -- Auto-reply example
    if message.content:lower():match("hello") then
        utils.bot_actions.sendMessage(serverId, message.channel_id, "Hello there! 👋", nil, message.id)
    end
end)

-- Handle member join events
Handlers.add("member-joined", function(msg)
    local data = msg.data
    local serverId = msg.from
    local welcomeChannelId = "your-welcome-channel-id"

        utils.bot_actions.sendMessage(serverId, welcomeChannelId,
        "Welcome to the server, <@" .. data.user_id .. ">! 🎉")
end)

-- Handle member leave events
Handlers.add("member-left", function(msg)
    local data = msg.data
    local serverId = msg.from
    local logChannelId = "your-log-channel-id"

        utils.bot_actions.sendMessage(serverId, logChannelId,
        "User " .. data.user_id .. " has left the server.")
end)

-- Handle role updates
Handlers.add("role-updated", function(msg)
    local data = msg.data
    local serverId = msg.from

    -- Log role changes
    print("Role updated in server " .. serverId .. ": " .. data.role.name)
end)

-- Bot initialization
utils.bot_actions.joinServer("server-process-id")
utils.bot_actions.subscribeToServer("server-process-id", {"message_sent", "member_joined", "member_left"})

Available event handlers:
- "message-sent"      - When a message is sent
- "message-edited"    - When a message is edited
- "message-deleted"   - When a message is deleted
- "member-joined"     - When a member joins
- "member-left"       - When a member leaves
- "member-updated"    - When a member is updated
- "member-kicked"     - When a member is kicked
- "member-banned"     - When a member is banned
- "channel-created"   - When a channel is created
- "channel-deleted"   - When a channel is deleted
- "channel-updated"   - When a channel is updated
- "category-created"  - When a category is created
- "category-deleted"  - When a category is deleted
- "category-updated"  - When a category is updated
- "role-created"      - When a role is created
- "role-deleted"      - When a role is deleted
- "role-updated"      - When a role is updated
--]]

--#endregion
