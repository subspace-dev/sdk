local json = require("json")

--#region configuration

subspace_id = "<<SUBSPACE>>"
version_ = version_ or "1.0.0"

--#endregion

--#region helpers

helpers = helpers or {
    logs = {},
    status = { -- read only
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

-- Common logging utility for informative logs
local function log(tag, message, data)
    local log_msg = string.format("[%s] %s", tag, message)
    if data then
        log_msg = log_msg .. " | " .. json.encode(data)
    end
    print(log_msg)
end

--- @type table<string, table<string, Message>>
conversations = {}      -- {[friend_id]: {[message_id]: Message}}
temp_conversations = {} -- {[user_id]: {[message_id]: Message}} -- temporary conversations for users who are not friends yet

--- @type table<string, number> - Rotating list of recent user IDs with timestamps
recents = {}

dm = dm or {
    id = id,
    owner_id = owner,
    version = version_,
    --- @type table<string, boolean>
    friends = {},
    --- @type table<string, boolean>
    blocked_users = {},
    message_count = 0,
    conversation_count = 0
}

--#endregion

--#region utils


local utils = {
    log = log,
    var_or_nil = function(var)
        return var ~= "" and var or nil
    end,
    --- @param msg table
    --- @return string|nil
    get_message_id_from_commitments = function(msg)
        if not msg.commitments then
            return nil
        end

        for commitment_id, commitment in pairs(msg.commitments) do
            -- Look for RSA PSS SHA512 commitment
            if commitment.type == "rsa-pss-sha512" then
                return commitment_id
            end
        end

        return nil
    end,
    handle_run = function(func, msg)
        msg.reply = function(data)
            -- data.target = msg.from
            data.target = id -- temporary
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
                -- target = msg.from,
                target = id, -- temporary
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
    conversations = {
        --- @param friendId string
        --- @return table<string, Message> | nil
        get = function(friendId)
            return conversations[friendId]
        end,
        --- @param friendId string
        --- @param messages table<string, Message>
        set = function(friendId, messages)
            conversations[friendId] = messages
        end,
        --- @param friendId string
        delete = function(friendId)
            conversations[friendId] = nil
        end,
        --- @param friendId string
        --- @param messageId string
        --- @return Message | nil
        get_message = function(friendId, messageId)
            local conv = conversations[friendId]
            return conv and conv[messageId] or nil
        end,
        --- @param friendId string
        --- @param messageId string
        --- @param message Message
        set_message = function(friendId, messageId, message)
            if not conversations[friendId] then
                conversations[friendId] = {}
            end
            conversations[friendId][messageId] = message
        end,
        --- @param friendId string
        --- @param messageId string
        delete_message = function(friendId, messageId)
            if conversations[friendId] then
                conversations[friendId][messageId] = nil
            end
        end
    },
    temp_conversations = {
        --- @param userId string
        --- @return table<string, Message> | nil
        get = function(userId)
            return temp_conversations[userId]
        end,
        --- @param userId string
        --- @param messages table<string, Message>
        set = function(userId, messages)
            temp_conversations[userId] = messages
        end,
        --- @param userId string
        delete = function(userId)
            temp_conversations[userId] = nil
        end,
        --- @param userId string
        --- @param messageId string
        --- @return Message | nil
        get_message = function(userId, messageId)
            local conv = temp_conversations[userId]
            return conv and conv[messageId] or nil
        end,
        --- @param userId string
        --- @param messageId string
        --- @param message Message
        set_message = function(userId, messageId, message)
            if not temp_conversations[userId] then
                temp_conversations[userId] = {}
            end
            temp_conversations[userId][messageId] = message
        end,
        --- @param userId string
        --- @param messageId string
        delete_message = function(userId, messageId)
            if temp_conversations[userId] then
                temp_conversations[userId][messageId] = nil
            end
        end,
        --- @param userId string
        --- @return boolean
        has_conversation = function(userId)
            return temp_conversations[userId] ~= nil
        end,
        --- @param userId string
        --- @return number
        get_message_count = function(userId)
            local conv = temp_conversations[userId]
            if not conv then return 0 end
            local count = 0
            for _ in pairs(conv) do
                count = count + 1
            end
            return count
        end
    },
    friends = {
        --- @param userId string
        --- @return boolean
        is_friend = function(userId)
            return dm.friends[userId] == true
        end,
        --- @param userId string
        add = function(userId)
            dm.friends[userId] = true
        end,
        --- @param userId string
        remove = function(userId)
            dm.friends[userId] = nil
        end
    },
    blocked = {
        --- @param userId string
        --- @return boolean
        is_blocked = function(userId)
            return dm.blocked_users[userId] == true
        end,
        --- @param userId string
        block = function(userId)
            dm.blocked_users[userId] = true
        end,
        --- @param userId string
        unblock = function(userId)
            dm.blocked_users[userId] = nil
        end
    },
    recents = {
        --- @param userId string
        add = function(userId)
            local currentTime = os.time()

            -- Remove user if already exists to update timestamp
            recents[userId] = nil

            -- Add user with current timestamp
            recents[userId] = currentTime
        end,
        --- @param userId string
        remove = function(userId)
            recents[userId] = nil
        end,
        --- @param limit number|nil - Maximum number of recent users to return (default: 20)
        --- @return table<string, number>
        get = function(limit)
            limit = limit or 20
            local sortedUsers = {}

            for userId, timestamp in pairs(recents) do
                table.insert(sortedUsers, { id = userId, timestamp = timestamp })
            end

            -- Sort by timestamp (most recent first)
            table.sort(sortedUsers, function(a, b)
                return a.timestamp > b.timestamp
            end)

            local result = {}
            local count = 0
            for _, user in ipairs(sortedUsers) do
                if count >= limit then break end
                result[user.id] = user.timestamp
                count = count + 1
            end

            return result
        end,
        --- @param userId string
        --- @return boolean
        has = function(userId)
            return recents[userId] ~= nil
        end,
        --- @return number
        count = function()
            local count = 0
            for _ in pairs(recents) do
                count = count + 1
            end
            return count
        end
    }
}

--#endregion

--#region setup

local function setup(msg)
    -- Initialize DM process configuration from subspace
end

Handlers.once("setup", function(msg)
    utils.handle_run(setup, msg)
end)

-- Since HB doesnot know yet if a target is a wallet or process and errors out
-- Instead of sending reply to wallet, dump it to self, to make sure it is still readable in frontend
Handlers.add("dump", function(msg)
    local action = msg.action
    local function ends_with(str, suffix)
        -- Handle edge cases
        if not str or not suffix then
            return false
        end

        -- Convert to strings if they aren't already
        str = tostring(str)
        suffix = tostring(suffix)

        -- Check if suffix is longer than the string
        if #suffix > #str then
            return false
        end

        -- Compare the end of the string with the suffix
        return str:sub(- #suffix) == suffix
    end
    return msg.from == id and ends_with(action, "response")
end, function(msg)

end)

-- Dump for errors
Handlers.add("error", function(msg) end)

--#endregion

--#region message operations

local function receive_message(msg)
    -- Receive a direct message (called from subspace)
    local friendId = utils.var_or_nil(msg["friend-id"])
    local messageId = utils.get_message_id_from_commitments(msg) or utils.var_or_nil(msg["message-id"])
    local content = utils.var_or_nil(msg["content"])
    local authorId = utils.var_or_nil(msg["author-id"])
    local timestamp = utils.var_or_nil(msg["timestamp"])
    local isFriendConversation = utils.var_or_nil(msg["is-friend-conversation"])

    assert(friendId, "400|friend-id is required")
    assert(messageId, "400|message-id is required")
    assert(content, "400|content is required")
    assert(authorId, "400|author-id is required")
    assert(timestamp, "400|timestamp is required")

    utils.log("DM_RECEIVED", "Message received", {
        author_id = authorId,
        conversation_with = friendId,
        conversation_type = isFriendConversation and "friend" or "temp"
    })

    --- @type Message
    local message = {
        id = messageId,
        content = content,
        author_id = authorId,
        channel_id = friendId, -- Using friend ID as channel ID for DMs
        timestamp = timestamp,
        edited = false,
        attachments = {},
        mentions = {}
    }

    -- Check if the user is a friend
    if utils.friends.is_friend(friendId) or isFriendConversation then
        -- Store in regular conversations
        utils.conversations.set_message(friendId, messageId, message)
        dm.message_count = dm.message_count + 1
    else
        -- Store in temporary conversations
        utils.temp_conversations.set_message(friendId, messageId, message)
        dm.message_count = dm.message_count + 1
    end

    utils.recents.add(friendId)

    msg.reply({
        action = "receive-message-response",
        status = helpers.status.success
    })
end

Handlers.add("receive-message", function(msg)
    utils.handle_run(receive_message, msg)
end)

local function edit_message(msg)
    -- Edit a direct message (called from subspace)
    local friendId = utils.var_or_nil(msg["friend-id"])
    local messageId = utils.get_message_id_from_commitments(msg) or utils.var_or_nil(msg["message-id"])
    local content = utils.var_or_nil(msg["content"])

    assert(friendId, "400|friend-id is required")
    assert(messageId, "400|message-id is required")
    assert(content, "400|content is required")

    utils.log("DM_EDIT", "Editing DM", {
        conversation_with = friendId,
        message_id = messageId
    })

    local message = nil

    -- Check if the user is a friend first
    if utils.friends.is_friend(friendId) then
        message = utils.conversations.get_message(friendId, messageId)
    else
        message = utils.temp_conversations.get_message(friendId, messageId)
    end

    assert(message, "404|message not found")

    message.content = content
    message.edited = true

    -- Store back in the appropriate conversation type
    if utils.friends.is_friend(friendId) then
        utils.conversations.set_message(friendId, messageId, message)
    else
        utils.temp_conversations.set_message(friendId, messageId, message)
    end

    msg.reply({
        action = "edit-message-response",
        status = helpers.status.success
    })
end

Handlers.add("edit-message", function(msg)
    utils.handle_run(edit_message, msg)
end)

local function delete_message(msg)
    -- Delete a direct message (called from subspace)
    local friendId = utils.var_or_nil(msg["friend-id"])
    local messageId = utils.var_or_nil(msg["message-id"])

    assert(friendId, "400|friend-id is required")
    assert(messageId, "400|message-id is required")

    utils.log("DM_DELETE", "Deleting DM", {
        conversation_with = friendId,
        message_id = messageId
    })

    local message = nil

    -- Check if the user is a friend first
    if utils.friends.is_friend(friendId) then
        message = utils.conversations.get_message(friendId, messageId)
        if message then
            utils.conversations.delete_message(friendId, messageId)
        end
    else
        message = utils.temp_conversations.get_message(friendId, messageId)
        if message then
            utils.temp_conversations.delete_message(friendId, messageId)
        end
    end

    assert(message, "404|message not found")

    dm.message_count = dm.message_count - 1

    msg.reply({
        action = "delete-message-response",
        status = helpers.status.success
    })
end

Handlers.add("delete-message", function(msg)
    utils.handle_run(delete_message, msg)
end)

--#endregion

--#region temporary conversation management

local function convert_temp_to_permanent(msg)
    -- Convert temporary conversation to permanent when users become friends
    local friendId = utils.var_or_nil(msg["friend-id"])

    assert(friendId, "400|friend-id is required")
    assert(utils.friends.is_friend(friendId), "400|user is not a friend")

    local tempConv = utils.temp_conversations.get(friendId)
    if tempConv then
        -- Move all messages from temporary to permanent conversation
        for messageId, message in pairs(tempConv) do
            utils.conversations.set_message(friendId, messageId, message)
        end

        -- Clear temporary conversation
        utils.temp_conversations.delete(friendId)

        msg.reply({
            action = "convert-temp-to-permanent-response",
            status = helpers.status.success,
            data = json.encode({
                friend_id = friendId,
                messages_moved = utils.temp_conversations.get_message_count(friendId)
            })
        })
    else
        msg.reply({
            action = "convert-temp-to-permanent-response",
            status = helpers.status.success,
            data = json.encode({
                friend_id = friendId,
                messages_moved = 0
            })
        })
    end
end

Handlers.add("convert-temp-to-permanent", function(msg)
    utils.handle_run(convert_temp_to_permanent, msg)
end)

--#endregion

--#region friend management

local function add_friend(msg)
    -- Add a friend (called from subspace)
    local friendId = utils.var_or_nil(msg["friend-id"])

    assert(friendId, "400|friend-id is required")

    utils.log("FRIEND_ADDED", "Friend added", {
        friend_id = friendId
    })

    -- Add friend to the friends list
    utils.friends.add(friendId)

    -- Check if there's a temporary conversation to convert
    local tempConv = utils.temp_conversations.get(friendId)
    if tempConv then
        local msgCount = 0
        -- Move all messages from temporary to permanent conversation
        for messageId, message in pairs(tempConv) do
            utils.conversations.set_message(friendId, messageId, message)
            msgCount = msgCount + 1
        end

        -- Clear temporary conversation
        utils.temp_conversations.delete(friendId)
        utils.log("CONV_CONVERTED", "Temporary conversation converted", {
            friend_id = friendId,
            message_count = msgCount
        })
    else
        -- Initialize empty conversation for this friend if it doesn't exist
        if not utils.conversations.get(friendId) then
            utils.conversations.set(friendId, {})
        end
    end

    msg.reply({
        action = "add-friend-response",
        status = helpers.status.success
    })
end

Handlers.add("add-friend", function(msg)
    utils.handle_run(add_friend, msg)
end)

local function remove_friend(msg)
    -- Remove a friend (called from subspace)
    local friendId = utils.var_or_nil(msg["friend-id"])

    assert(friendId, "400|friend-id is required")

    utils.log("FRIEND_REMOVED", "Friend removed", {
        friend_id = friendId
    })

    -- Remove friend from the friends list
    utils.friends.remove(friendId)

    -- Optionally keep conversation history or delete it
    -- For now, we'll keep the conversation history
    -- utils.conversations.delete(friendId)

    msg.reply({
        action = "remove-friend-response",
        status = helpers.status.success
    })
end

Handlers.add("remove-friend", function(msg)
    utils.handle_run(remove_friend, msg)
end)

local function get_friends(msg)
    -- Get list of friends
end

Handlers.add("get-friends", function(msg)
    utils.handle_run(get_friends, msg)
end)

local function get_recents(msg)
    -- Get list of recent DM users
    local limit = tonumber(msg["limit"]) or 20

    local recentUsers = utils.recents.get(limit)

    msg.reply({
        action = "get-recents-response",
        status = helpers.status.success,
        data = json.encode({
            recents = recentUsers,
            count = utils.recents.count()
        })
    })
end

Handlers.add("get-recents", function(msg)
    utils.handle_run(get_recents, msg)
end)

--#endregion

--#region blocking/privacy

local function block_user(msg)
    -- Block a user
end

Handlers.add("block-user", function(msg)
    utils.handle_run(block_user, msg)
end)

local function unblock_user(msg)
    -- Unblock a user
end

Handlers.add("unblock-user", function(msg)
    utils.handle_run(unblock_user, msg)
end)

local function get_blocked_users(msg)
    -- Get list of blocked users
end

Handlers.add("get-blocked-users", function(msg)
    utils.handle_run(get_blocked_users, msg)
end)

local function check_privacy(msg)
    -- Check if user can send DM to another user
end

Handlers.add("check-privacy", function(msg)
    utils.handle_run(check_privacy, msg)
end)

--#endregion

--#region message reactions

local function add_reaction(msg)
    -- Add reaction to a message
end

Handlers.add("add-reaction", function(msg)
    utils.handle_run(add_reaction, msg)
end)

local function remove_reaction(msg)
    -- Remove reaction from a message
end

Handlers.add("remove-reaction", function(msg)
    utils.handle_run(remove_reaction, msg)
end)

local function get_reactions(msg)
    -- Get reactions for a message
end

Handlers.add("get-reactions", function(msg)
    utils.handle_run(get_reactions, msg)
end)

--#endregion

--#region message status

local function mark_as_read(msg)
    -- Mark messages as read
end

Handlers.add("mark-as-read", function(msg)
    utils.handle_run(mark_as_read, msg)
end)

local function get_unread_count(msg)
    -- Get unread message count
end

Handlers.add("get-unread-count", function(msg)
    utils.handle_run(get_unread_count, msg)
end)

local function typing_indicator(msg)
    -- Handle typing indicators
end

Handlers.add("typing-indicator", function(msg)
    utils.handle_run(typing_indicator, msg)
end)

--#endregion

--#region attachments

local function upload_attachment(msg)
    -- Handle file/media uploads
end

Handlers.add("upload-attachment", function(msg)
    utils.handle_run(upload_attachment, msg)
end)

local function get_attachment(msg)
    -- Get attachment details
end

Handlers.add("get-attachment", function(msg)
    utils.handle_run(get_attachment, msg)
end)

local function delete_attachment(msg)
    -- Delete an attachment
end

Handlers.add("delete-attachment", function(msg)
    utils.handle_run(delete_attachment, msg)
end)

--#endregion

--#region search and history

local function search_messages(msg)
    -- Search messages in conversations
end

Handlers.add("search-messages", function(msg)
    utils.handle_run(search_messages, msg)
end)

local function export_conversation(msg)
    -- Export conversation history
end

Handlers.add("export-conversation", function(msg)
    utils.handle_run(export_conversation, msg)
end)

local function clear_history(msg)
    -- Clear conversation history
end

Handlers.add("clear-history", function(msg)
    utils.handle_run(clear_history, msg)
end)

--#endregion

--#region notifications

local function send_notification(msg)
    -- Send notification for new message
end

Handlers.add("send-notification", function(msg)
    utils.handle_run(send_notification, msg)
end)

local function update_notification_settings(msg)
    -- Update notification preferences
end

Handlers.add("update-notification-settings", function(msg)
    utils.handle_run(update_notification_settings, msg)
end)

--#endregion
