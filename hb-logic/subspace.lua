local json = require("json")

--#region configuration

sources = sources or {
    bot = {
        id = "0yFR8HCG_4y9eS0S6-hbrFZIgaM-97gMNB-WWiwOogQ",
        version = "1.0.0"
    },
    dm = {
        id = "RRFdbQy-ApzRIKdyI2GDIMi7Tmkgqsz7Ee4eNiYWY9k",
        version = "1.0.0"
    },
    server = {
        id = "Tq5ZJlO4xAS7QtXlSZyGeBUOI6vkKvQGTzsn8_gqmdM",
        version = "1.0.0"
    },
}

subspace = subspace or {
    ---@type table<string, Profile>
    profiles = {},
    ---@type table<string, Server>
    servers = {},
    ---@type table<string, Bot>
    bots = {},
    ----------------------------
}

--#endregion

--#region helpers

helpers = helpers or {
    ---@type table<string, string>
    dm_to_user_id = {},
    logs = {},
    status = {
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

--#region utils

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

local utils = {
    var_or_nil = function(var)
        return var ~= "" and var or nil
    end,
    get_id = get_id,
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
    --- @param func function
    --- @param msg table
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
    --- @param txid string
    --- @return boolean
    valid_tx_id = function(txid)
        return #txid == 43 and txid:match("^[A-Za-z0-9_-]+$")
    end,
    profiles = {
        --- @param userId string
        --- @return Profile|nil
        get = function(userId)
            return subspace.profiles[userId]
        end,
        --- @param userId string
        --- @param profile Profile|nil -- if nil, the profile will be deleted
        set = function(userId, profile)
            subspace.profiles[userId] = profile
        end,
        --- @param dmProcessId string
        --- @return string|nil
        dm_process_to_user_id = function(dmProcessId)
            return helpers.dm_to_user_id[dmProcessId]
        end,
        --- @param sender Profile
        --- @param receiver Profile
        send_friend_request = function(sender, receiver)
            -- 1. user has not already sent fr
            -- 2. user is not already friends
            -- 3. user is not the receiver
            -- 4. if receiver has already sent a friend request, then accept it
            assert(not sender.friends.sent[receiver.id], "400|friend request already sent")
            assert(not sender.friends.accepted[receiver.id], "400|already friends")
            assert(sender.id ~= receiver.id, "400|cannot send friend request to yourself")

            -- Check if receiver has already sent a friend request to sender
            if receiver.friends.sent[sender.id] then
                -- Accept the existing friend request automatically
                sender.friends.accepted[receiver.id] = true
                receiver.friends.accepted[sender.id] = true

                -- Remove from sent/received lists
                receiver.friends.sent[sender.id] = nil
                sender.friends.received[receiver.id] = nil

                -- Update both profiles
                subspace.profiles[sender.id] = sender
                subspace.profiles[receiver.id] = receiver

                -- Notify DM processes about new friendship
                if sender.dm_process and receiver.dm_process then
                    send({
                        target = sender.dm_process,
                        action = "add-friend",
                        ["friend-id"] = receiver.id
                    })
                    send({
                        target = receiver.dm_process,
                        action = "add-friend",
                        ["friend-id"] = sender.id
                    })
                end

                return "accepted" -- Return status to indicate auto-acceptance
            else
                -- Send new friend request
                sender.friends.sent[receiver.id] = true
                receiver.friends.received[sender.id] = true

                -- Update both profiles
                subspace.profiles[sender.id] = sender
                subspace.profiles[receiver.id] = receiver

                return "sent" -- Return status to indicate request sent
            end
        end,
        --- @param sender Profile
        --- @param receiver Profile
        accept_friend_request = function(sender, receiver)
            -- Sender is the one accepting the request
            -- Receiver is the one who originally sent the request
            assert(sender.friends.received[receiver.id], "400|no friend request from this user")
            assert(not sender.friends.accepted[receiver.id], "400|already friends")

            -- Add to accepted friends for both users
            sender.friends.accepted[receiver.id] = true
            receiver.friends.accepted[sender.id] = true

            -- Remove from sent/received lists
            sender.friends.received[receiver.id] = nil
            receiver.friends.sent[sender.id] = nil

            -- Update both profiles
            subspace.profiles[sender.id] = sender
            subspace.profiles[receiver.id] = receiver

            -- Notify DM processes about new friendship
            if sender.dm_process and receiver.dm_process then
                send({
                    target = sender.dm_process,
                    action = "add-friend",
                    ["friend-id"] = receiver.id
                })
                send({
                    target = receiver.dm_process,
                    action = "add-friend",
                    ["friend-id"] = sender.id
                })
            end
        end,
        --- @param sender Profile
        --- @param receiver Profile
        reject_friend_request = function(sender, receiver)
            -- Sender is the one rejecting the request
            -- Receiver is the one who originally sent the request
            assert(sender.friends.received[receiver.id], "400|no friend request from this user")

            -- Remove from sent/received lists (no need to add to accepted)
            sender.friends.received[receiver.id] = nil
            receiver.friends.sent[sender.id] = nil

            -- Update both profiles
            subspace.profiles[sender.id] = sender
            subspace.profiles[receiver.id] = receiver
        end,
        --- @param user1 Profile
        --- @param user2 Profile
        remove_friendship = function(user1, user2)
            -- Remove friendship between two users
            assert(user1.friends.accepted[user2.id], "400|not friends with this user")

            -- Remove from accepted friends for both users
            user1.friends.accepted[user2.id] = nil
            user2.friends.accepted[user1.id] = nil

            -- Update both profiles
            subspace.profiles[user1.id] = user1
            subspace.profiles[user2.id] = user2

            -- Notify DM processes about friendship removal
            if user1.dm_process and user2.dm_process then
                send({
                    target = user1.dm_process,
                    action = "remove-friend",
                    ["friend-id"] = user2.id
                })
                send({
                    target = user2.dm_process,
                    action = "remove-friend",
                    ["friend-id"] = user1.id
                })
            end
        end,
        is_bot = function(userId)
            local in_bots_table = subspace.bots[userId] and true or false
            local in_profiles_table = subspace.profiles[userId] and true or false
            if in_bots_table and not in_profiles_table then
                return true
            elseif in_profiles_table and not in_bots_table then
                return false
            end
            error("404|user not found")
        end,
    },
    servers = {
        --- @param serverId string
        --- @return Server|nil
        get = function(serverId)
            return subspace.servers[serverId]
        end,
        --- @param serverId string
        --- @param server {owner_id: string, public_server: boolean}|nil -- if nil, the server will be deleted
        set = function(serverId, server)
            subspace.servers[serverId] = server
        end,
        --- @param user Profile
        --- @return number
        get_next_order_id = function(user)
            local servers = user.servers
            local max_order_id = -1
            for _, server in pairs(servers) do
                if server.order_id > max_order_id then
                    max_order_id = server.order_id
                end
            end
            return max_order_id + 1
        end,
        --- @param user Profile
        reorder_servers = function(user)
            local servers = user.servers
            --- @type table<string, {order_id: number, approved: boolean}>
            local new_servers = {}
            local idx = 1
            for serverId, server in pairs(servers) do
                new_servers[serverId] = {
                    order_id = idx,
                    approved = server.approved
                }
                idx = idx + 1
            end
            user.servers = new_servers
            subspace.profiles[user.id] = user
        end
    },
    bots = {
        --- @param botId string
        --- @return Bot|nil
        get = function(botId)
            return subspace.bots[botId]
        end,
        --- @param botId string
        --- @param bot Bot|nil -- if nil, the bot will be deleted
        set = function(botId, bot)
            subspace.bots[botId] = bot
        end
    },
    notifications = {
        --- @param userId string
        --- @param notificationId string
        --- @return Notification|nil
        get = function(userId, notificationId)
            local user = subspace.profiles[userId]
            return user and user.notifications[notificationId] or nil
        end,
        --- @param userId string
        --- @param notification Notification
        --- @param read boolean -- if true, the notification will be marked as read
        --- @return string|nil -- the id of the notification or nil if it is deleted
        set = function(userId, notification, read)
            local user = subspace.profiles[userId]
            if not user then
                return nil
            end
            if read then
                local id = notification.id
                user.notifications[id] = nil -- delete the notification coz read
            else
                local id = get_id()
                notification.id = id -- set the id
                user.notifications[id] = notification
            end
            subspace.profiles[userId] = user
            return notification.id
        end
    }
}

--#endregion

--#region profile

local function create_profile(msg)
    local userId = msg.from
    local dmProcess = utils.var_or_nil(msg["dm-process"])
    local pfp = utils.var_or_nil(msg["pfp"])
    local banner = utils.var_or_nil(msg["banner"])

    -- Get the existing profile for this user (if any)
    local profile = utils.profiles.get(userId)

    -- Check if a profile already exists for this user
    local profileExists = profile and true or false

    -- Check if the existing profile has a valid DM process (43 characters long)
    local profileHasDmProcess = profile and profile.dm_process and #profile.dm_process == 43 and true or false

    -- Only allow profile creation if:
    -- 1. No profile exists yet, OR
    -- 2. Profile exists but doesn't have a valid DM process (incomplete profile)
    -- This prevents overwriting complete profiles while allowing completion of incomplete ones
    assert(not profileExists or not profileHasDmProcess, "400|profile already exists")

    -- make sure that the dmProcess is not nil
    assert(dmProcess, "400|dm process is required")
    -- make sure that the dmProcess is 43 characters long
    assert(utils.valid_tx_id(dmProcess), "400|dm process must be a valid arweave tx id")

    -- make sure that this dmProcess is not already in the database or used by another user
    assert(not utils.profiles.dm_process_to_user_id(dmProcess), "400|dm process already in use by another user")

    -- Check if dmProcess is already used as a bot process
    assert(not utils.bots.get(dmProcess), "400|dm process conflicts with existing bot process")

    -- make sure that the pfp is a valid arweave tx id
    if pfp then
        assert(utils.valid_tx_id(pfp), "400|pfp must be a valid arweave tx id")
    end

    -- make sure that the banner is a valid arweave tx id
    if banner then
        assert(utils.valid_tx_id(banner), "400|banner must be a valid arweave tx id")
    end

    profile = {
        id = userId,
        dm_process = tostring(dmProcess),
        pfp = pfp or "",
        banner = banner or "",
        servers = {},
        friends = {
            accepted = {},
            sent = {},
            received = {}
        },
        notifications = {}
    }

    -- create the profile and store the dm process mapping
    utils.profiles.set(userId, profile)
    helpers.dm_to_user_id[dmProcess] = userId

    msg.reply({
        action = "create-profile-response",
        status = helpers.status.success,
        data = json.encode(profile)
    })
end

Handlers.add("create-profile", function(msg)
    utils.handle_run(create_profile, msg)
end)

local function update_profile(msg)
    local userId = msg.from
    local pfp = utils.var_or_nil(msg["pfp"])
    local banner = utils.var_or_nil(msg["banner"])

    local profile = utils.profiles.get(userId)
    assert(profile, "404|profile not found")

    if pfp then
        assert(utils.valid_tx_id(pfp), "400|pfp must be a valid arweave tx id")
        profile.pfp = pfp
    end

    if banner then
        assert(utils.valid_tx_id(banner), "400|banner must be a valid arweave tx id")
        profile.banner = banner
    end

    utils.profiles.set(userId, profile)

    msg.reply({
        action = "update-profile-response",
        status = helpers.status.success,
        data = json.encode(profile)
    })
end

Handlers.add("update-profile", function(msg)
    utils.handle_run(update_profile, msg)
end)

--#endregion

--#region server

local function create_server(msg)
    local userId = msg.from
    local serverProcess = utils.var_or_nil(msg["server-process"])
    local serverName = utils.var_or_nil(msg["server-name"])
    local serverDescription = utils.var_or_nil(msg["server-description"])
    local serverPfp = utils.var_or_nil(msg["server-pfp"])
    local serverBanner = utils.var_or_nil(msg["server-banner"])
    local serverPublic = utils.var_or_nil(msg["server-public"]) or true

    -- get the profile
    local profile = utils.profiles.get(userId)
    assert(profile, "404|profile not found")

    assert(serverProcess, "400|server process is required")
    assert(utils.valid_tx_id(serverProcess), "400|server process must be a valid arweave tx id")

    -- make sure that the server process is not already in the database
    assert(not utils.servers.get(serverProcess), "400|server already exists")

    if serverName then
        assert(type(serverName) == "string", "400|server name must be a string")
    end
    if serverDescription then
        assert(type(serverDescription) == "string", "400|server description must be a string")
    end
    if serverPfp then
        assert(utils.valid_tx_id(serverPfp), "400|server pfp must be a valid arweave tx id")
    end
    if serverBanner then
        assert(utils.valid_tx_id(serverBanner), "400|server banner must be a valid arweave tx id")
    end

    local server = {
        id = serverProcess,
        owner = userId,
        name = serverName or "",
        description = serverDescription or "",
        pfp = serverPfp or "",
        banner = serverBanner or "",
        public_server = serverPublic
    }
    utils.servers.set(serverProcess, server)

    send({
        target = serverProcess,
        action = "setup",
        ["server-name"] = serverName,
        ["server-description"] = serverDescription,
        ["server-pfp"] = serverPfp,
        ["server-banner"] = serverBanner,
        ["server-public"] = serverPublic
    })

    msg.reply({
        action = "create-server-response",
        status = helpers.status.success,
        data = json.encode(server)
    })
end

Handlers.add("create-server", function(msg)
    utils.handle_run(create_server, msg)
end)

local function update_server(msg)
    local serverId = msg.from
    local serverPublic = utils.var_or_nil(msg["server-public"])
    local serverName = utils.var_or_nil(msg["server-name"])
    local serverDescription = utils.var_or_nil(msg["server-description"])
    local serverPfp = utils.var_or_nil(msg["server-pfp"])
    local serverBanner = utils.var_or_nil(msg["server-banner"])

    local server = utils.servers.get(serverId)
    assert(server, "404|server not found")

    if serverPublic then
        assert(type(serverPublic) == "boolean", "400|server public must be a boolean")
    end
    if serverName then
        assert(type(serverName) == "string", "400|server name must be a string")
    end
    if serverDescription then
        assert(type(serverDescription) == "string", "400|server description must be a string")
    end
    if serverPfp then
        assert(utils.valid_tx_id(serverPfp), "400|server pfp must be a valid arweave tx id")
    end
    if serverBanner then
        assert(utils.valid_tx_id(serverBanner), "400|server banner must be a valid arweave tx id")
    end
    if serverPublic then
        assert(type(serverPublic) == "boolean", "400|server public must be a boolean")
    end

    server.public_server = serverPublic or true
    server.name = serverName or ""
    server.description = serverDescription or ""
    server.pfp = serverPfp or ""
    server.banner = serverBanner or ""
    utils.servers.set(serverId, server)

    msg.reply({
        action = "update-server-response",
        status = helpers.status.success,
        data = json.encode(server)
    })
end

Handlers.add("update-server", function(msg)
    utils.handle_run(update_server, msg)
end)

local function join_server(msg)
    local userId = msg.from
    local serverId = utils.var_or_nil(msg["server-id"])

    local entity
    local isBot = utils.profiles.is_bot(userId)
    if isBot then
        entity = utils.bots.get(userId)
    else
        entity = utils.profiles.get(userId)
    end
    assert(entity, "404|" .. (isBot and "bot" or "profile") .. " not found")

    assert(serverId, "400|server id is required")

    local server = utils.servers.get(serverId)
    assert(server, "404|server not found")

    if isBot then
        local bot = utils.bots.get(userId)
        assert(bot, "404|bot not found")
        bot.servers[serverId] = { approved = false }
        utils.bots.set(userId, bot)
    else
        local profile = utils.profiles.get(userId)
        assert(profile, "404|profile not found")
        profile.servers[serverId] = {
            order_id = utils.servers.get_next_order_id(profile),
            approved = false
        }
        utils.profiles.set(userId, profile)
        utils.servers.reorder_servers(profile)
    end

    send({
        target      = serverId,
        action      = "add-member",
        ["user-id"] = userId,
        ["is-bot"]  = isBot,
    })
    msg.reply({
        action = "join-server-response",
        status = helpers.status.accepted,
    })
end

Handlers.add("join-server", function(msg)
    utils.handle_run(join_server, msg)
end)

local function add_member_response(msg)
    local serverId = msg.from
    local userId = utils.var_or_nil(msg["user-id"])
    local status = utils.var_or_nil(msg["status"])
    local isBot = utils.profiles.is_bot(userId)

    local server = utils.servers.get(serverId)
    assert(server, "404|server not found")

    assert(userId, "400|user id is required from the server")
    assert(status, "400|status is required from the server")

    if status == helpers.status.success then
        if isBot then
            local bot = utils.bots.get(userId)
            assert(bot, "404|bot not found")
            assert(bot.servers[serverId], "404|bot did not trigger the join server request")
            bot.servers[serverId].approved = true
            utils.bots.set(userId, bot)
        else
            local profile = utils.profiles.get(userId)
            assert(profile, "404|profile not found")
            assert(profile.servers[serverId], "404|profile did not trigger the join server request")
            profile.servers[serverId].approved = true
            utils.profiles.set(userId, profile)
            utils.servers.reorder_servers(profile)
        end
        msg.reply({
            action = "add-member-response",
            status = helpers.status.success,
        })
    else
        error(tostring(status) .. "|check server logs /" .. serverId .. "/now/helpers/logs")
    end
end

Handlers.add("add-member-response", function(msg)
    utils.handle_run(add_member_response, msg)
end)

---#region server
local function remove_member(msg)
    local serverId = msg.from
    local userId = utils.var_or_nil(msg["user-id"])
    local isBot = utils.profiles.is_bot(userId)

    assert(userId, "400|user id is required")

    local server = utils.servers.get(serverId)
    assert(server, "404|server not found")

    if isBot then
        local bot = utils.bots.get(userId)
        assert(bot, "404|bot not found")
        bot.servers[serverId] = nil
        utils.bots.set(userId, bot)
    else
        local profile = utils.profiles.get(userId)
        assert(profile, "404|profile not found")

        profile.servers[serverId] = nil
        utils.profiles.set(userId, profile)

        utils.servers.reorder_servers(profile)
    end

    msg.reply({
        action = "remove-member-response",
        status = helpers.status.success,
    })
end

Handlers.add("remove-member", function(msg)
    utils.handle_run(remove_member, msg)
end)

local function update_server_order(msg)
    local userId = msg.from
    local serverId = utils.var_or_nil(msg["server-id"])
    local orderId = utils.var_or_nil(msg["order-id"])

    assert(serverId, "400|server id is required")
    assert(orderId, "400|order id is required")

    local server = utils.servers.get(serverId)
    assert(server, "404|server not found")

    local profile = utils.profiles.get(userId)
    assert(profile, "404|profile not found")

    local entry = profile.servers[serverId]
    assert(entry, "404|server not found")

    entry.order_id = orderId
    profile.servers[serverId] = entry
    utils.profiles.set(userId, profile)

    utils.servers.reorder_servers(profile)

    msg.reply({
        action = "update-server-order-response",
        status = helpers.status.success,
    })
end

Handlers.add("update-server-order", function(msg)
    utils.handle_run(update_server_order, msg)
end)

--#endregion

--#region friends

local function add_friend(msg)
    local senderId = msg.from
    local receiverId = utils.var_or_nil(msg["friend-id"])

    local senderProfile = utils.profiles.get(senderId)
    assert(senderProfile, "404|sender profile not found")

    assert(receiverId, "400|friend-id is required")

    local receiverProfile = utils.profiles.get(receiverId)
    assert(receiverProfile, "404|receiver profile not found")

    -- Use the send_friend_request utility function
    utils.profiles.send_friend_request(senderProfile, receiverProfile)

    msg.reply({
        action = "add-friend-response",
        status = helpers.status.success,
    })
end

Handlers.add("add-friend", function(msg)
    utils.handle_run(add_friend, msg)
end)

local function accept_friend(msg)
    local senderId = msg.from
    local receiverId = utils.var_or_nil(msg["friend-id"])

    local senderProfile = utils.profiles.get(senderId)
    assert(senderProfile, "404|sender profile not found")

    assert(receiverId, "400|friend-id is required")

    local receiverProfile = utils.profiles.get(receiverId)
    assert(receiverProfile, "404|receiver profile not found")

    -- Use the accept_friend_request utility function
    utils.profiles.accept_friend_request(senderProfile, receiverProfile)

    msg.reply({
        action = "accept-friend-response",
        status = helpers.status.success,
    })
end

Handlers.add("accept-friend", function(msg)
    utils.handle_run(accept_friend, msg)
end)

local function reject_friend(msg)
    local senderId = msg.from
    local receiverId = utils.var_or_nil(msg["friend-id"])

    local senderProfile = utils.profiles.get(senderId)
    assert(senderProfile, "404|sender profile not found")

    assert(receiverId, "400|friend-id is required")

    local receiverProfile = utils.profiles.get(receiverId)
    assert(receiverProfile, "404|receiver profile not found")

    -- Use the reject_friend_request utility function
    utils.profiles.reject_friend_request(senderProfile, receiverProfile)

    msg.reply({
        action = "reject-friend-response",
        status = helpers.status.success,
    })
end

Handlers.add("reject-friend", function(msg)
    utils.handle_run(reject_friend, msg)
end)

local function remove_friend(msg)
    local senderId = msg.from
    local receiverId = utils.var_or_nil(msg["friend-id"])

    local senderProfile = utils.profiles.get(senderId)
    assert(senderProfile, "404|sender profile not found")

    assert(receiverId, "400|friend-id is required")

    local receiverProfile = utils.profiles.get(receiverId)
    assert(receiverProfile, "404|receiver profile not found")

    -- Use the remove_friendship utility function
    utils.profiles.remove_friendship(senderProfile, receiverProfile)

    msg.reply({
        action = "remove-friend-response",
        status = helpers.status.success,
    })
end

Handlers.add("remove-friend", function(msg)
    utils.handle_run(remove_friend, msg)
end)

--#endregion

--#region direct_messages

-- both people should be friends to send dms
local function send_dm(msg)
    local senderId = msg.from
    local receiverId = utils.var_or_nil(msg["receiver-id"])
    local content = utils.var_or_nil(msg["content"])
    local messageId = utils.get_message_id_from_commitments(msg) or utils.var_or_nil(msg["message-id"]) or utils.get_id()
    local timestamp = utils.var_or_nil(msg["timestamp"]) or tostring(os.time())

    assert(receiverId, "400|receiver-id is required")
    assert(content, "400|content is required")

    local senderProfile = utils.profiles.get(senderId)
    assert(senderProfile, "404|sender profile not found")

    local receiverProfile = utils.profiles.get(receiverId)
    assert(receiverProfile, "404|receiver profile not found")

    -- Verify both users are friends
    assert(senderProfile.friends.accepted[receiverId], "403|not friends with receiver")
    assert(receiverProfile.friends.accepted[senderId], "403|receiver not friends with sender")

    -- Verify both users have DM processes
    assert(senderProfile.dm_process and #senderProfile.dm_process == 43, "400|sender has no valid dm process")
    assert(receiverProfile.dm_process and #receiverProfile.dm_process == 43, "400|receiver has no valid dm process")

    -- Forward message to both DM processes
    local messageData = {
        action = "receive-message",
        ["message-id"] = messageId,
        ["content"] = content,
        ["author-id"] = senderId,
        ["timestamp"] = timestamp
    }

    -- Send to sender's DM process (so they can see their own message)
    send({
        target = senderProfile.dm_process,
        ["friend-id"] = receiverId,
        action = messageData.action,
        ["message-id"] = messageData["message-id"],
        ["content"] = messageData["content"],
        ["author-id"] = messageData["author-id"],
        ["timestamp"] = messageData["timestamp"]
    })

    -- Send to receiver's DM process
    send({
        target = receiverProfile.dm_process,
        ["friend-id"] = senderId,
        action = messageData.action,
        ["message-id"] = messageData["message-id"],
        ["content"] = messageData["content"],
        ["author-id"] = messageData["author-id"],
        ["timestamp"] = messageData["timestamp"]
    })

    msg.reply({
        action = "send-dm-response",
        status = helpers.status.success,
        data = json.encode({
            message_id = messageId,
            timestamp = timestamp
        })
    })
end

Handlers.add("send-dm", function(msg)
    utils.handle_run(send_dm, msg)
end)

local function edit_dm(msg)
    local senderId = msg.from
    local receiverId = utils.var_or_nil(msg["receiver-id"])
    local messageId = utils.get_message_id_from_commitments(msg) or utils.var_or_nil(msg["message-id"])
    local content = utils.var_or_nil(msg["content"])

    assert(receiverId, "400|receiver-id is required")
    assert(messageId, "400|message-id is required")
    assert(content, "400|content is required")

    local senderProfile = utils.profiles.get(senderId)
    assert(senderProfile, "404|sender profile not found")

    local receiverProfile = utils.profiles.get(receiverId)
    assert(receiverProfile, "404|receiver profile not found")

    -- Verify both users are friends
    assert(senderProfile.friends.accepted[receiverId], "403|not friends with receiver")
    assert(receiverProfile.friends.accepted[senderId], "403|receiver not friends with sender")

    -- Verify both users have DM processes
    assert(senderProfile.dm_process and #senderProfile.dm_process == 43, "400|sender has no valid dm process")
    assert(receiverProfile.dm_process and #receiverProfile.dm_process == 43, "400|receiver has no valid dm process")

    -- Forward edit to both DM processes
    local editData = {
        action = "edit-message",
        ["message-id"] = messageId,
        ["content"] = content
    }

    -- Send to sender's DM process
    send({
        target = senderProfile.dm_process,
        ["friend-id"] = receiverId,
        action = editData.action,
        ["message-id"] = editData["message-id"],
        ["content"] = editData["content"]
    })

    -- Send to receiver's DM process
    send({
        target = receiverProfile.dm_process,
        ["friend-id"] = senderId,
        action = editData.action,
        ["message-id"] = editData["message-id"],
        ["content"] = editData["content"]
    })

    msg.reply({
        action = "edit-dm-response",
        status = helpers.status.success
    })
end

Handlers.add("edit-dm", function(msg)
    utils.handle_run(edit_dm, msg)
end)

local function delete_dm(msg)
    local senderId = msg.from
    local receiverId = utils.var_or_nil(msg["receiver-id"])
    local messageId = utils.get_message_id_from_commitments(msg) or utils.var_or_nil(msg["message-id"])

    assert(receiverId, "400|receiver-id is required")
    assert(messageId, "400|message-id is required")

    local senderProfile = utils.profiles.get(senderId)
    assert(senderProfile, "404|sender profile not found")

    local receiverProfile = utils.profiles.get(receiverId)
    assert(receiverProfile, "404|receiver profile not found")

    -- Verify both users are friends
    assert(senderProfile.friends.accepted[receiverId], "403|not friends with receiver")
    assert(receiverProfile.friends.accepted[senderId], "403|receiver not friends with sender")

    -- Verify both users have DM processes
    assert(senderProfile.dm_process and #senderProfile.dm_process == 43, "400|sender has no valid dm process")
    assert(receiverProfile.dm_process and #receiverProfile.dm_process == 43, "400|receiver has no valid dm process")

    -- Forward delete to both DM processes
    local deleteData = {
        action = "delete-message",
        ["message-id"] = messageId
    }

    -- Send to sender's DM process
    send({
        target = senderProfile.dm_process,
        ["friend-id"] = receiverId,
        action = deleteData.action,
        ["message-id"] = deleteData["message-id"]
    })

    -- Send to receiver's DM process
    send({
        target = receiverProfile.dm_process,
        ["friend-id"] = senderId,
        action = deleteData.action,
        ["message-id"] = deleteData["message-id"]
    })

    msg.reply({
        action = "delete-dm-response",
        status = helpers.status.success
    })
end

Handlers.add("delete-dm", function(msg)
    utils.handle_run(delete_dm, msg)
end)

--#endregion

--#region notifications

local function add_notification(msg)
    error("501|not implemented")
end

Handlers.add("add-notification", function(msg)
    utils.handle_run(add_notification, msg)
end)

local function mark_notification_read(msg)
    error("501|not implemented")
end

Handlers.add("mark-notification-read", function(msg)
    utils.handle_run(mark_notification_read, msg)
end)

--#endregion

--#region bots

local function create_bot(msg)
    local userId = msg.from
    local botProcess = utils.var_or_nil(msg["bot-process"])
    local public = utils.var_or_nil(msg["public-bot"])
    local name = utils.var_or_nil(msg["name"])
    local pfp = utils.var_or_nil(msg["pfp"])
    local banner = utils.var_or_nil(msg["banner"])
    local description = utils.var_or_nil(msg["description"])
    local requiredEvents = utils.var_or_nil(msg["required-events"])

    local profile = utils.profiles.get(userId)
    assert(profile, "404|profile not found")

    assert(botProcess, "400|bot process is required")
    assert(utils.valid_tx_id(botProcess), "400|bot process must be a valid arweave tx id")

    assert(not utils.bots.get(botProcess), "400|bot already exists")

    -- Check if botProcess conflicts with existing profiles or DM processes
    assert(not utils.profiles.get(botProcess), "400|bot process conflicts with existing profile")
    assert(not utils.profiles.dm_process_to_user_id(botProcess), "400|bot process conflicts with existing dm process")

    assert(name, "400|name is required")
    assert(type(name) == "string", "400|name must be a string")

    assert(pfp, "400|pfp is required")
    assert(utils.valid_tx_id(pfp), "400|pfp must be a valid arweave tx id")

    if banner then
        assert(utils.valid_tx_id(banner), "400|banner must be a valid arweave tx id")
    end
    if description then
        assert(type(description) == "string", "400|description must be a string")
    end

    -- Validate public bot parameter
    if public ~= nil then
        assert(type(public) == "boolean", "400|public-bot must be a boolean")
    end

    assert(requiredEvents, "400|required events table is required")
    assert(type(requiredEvents) == "table", "400|required events must be a table")
    for _, event in ipairs(requiredEvents) do
        -- Fix: Check if event exists in helpers.events (numeric values, not boolean)
        assert(helpers.events[event] ~= nil, "400|invalid event: " .. tostring(event))
    end

    --- @type Bot
    local bot = {
        id = botProcess,
        owner_id = userId,
        public_bot = public or false,
        name = name,
        pfp = pfp,
        banner = banner or "",
        description = description or "",
        servers = {},
        required_events = requiredEvents
    }

    utils.bots.set(botProcess, bot)

    msg.reply({
        action = "create-bot-response",
        status = helpers.status.success,
        data = json.encode(bot)
    })
end

Handlers.add("create-bot", function(msg)
    utils.handle_run(create_bot, msg)
end)

local function update_bot(msg)
    local userId = msg.from
    local botProcess = utils.var_or_nil(msg["bot-process"])
    local name = utils.var_or_nil(msg["name"])
    local pfp = utils.var_or_nil(msg["pfp"])
    local banner = utils.var_or_nil(msg["banner"])
    local description = utils.var_or_nil(msg["description"])
    local requiredEvents = utils.var_or_nil(msg["required-events"])

    local profile = utils.profiles.get(userId)
    assert(profile, "404|profile not found")

    assert(botProcess, "400|bot process is required")
    assert(utils.valid_tx_id(botProcess), "400|bot process must be a valid arweave tx id")

    local bot = utils.bots.get(botProcess)
    assert(bot, "404|bot not found")

    assert(bot.owner_id == userId, "401|unauthorized")

    if pfp then
        assert(utils.valid_tx_id(pfp), "400|pfp must be a valid arweave tx id")
    end
    if banner then
        assert(utils.valid_tx_id(banner), "400|banner must be a valid arweave tx id")
    end

    if requiredEvents then
        assert(type(requiredEvents) == "table", "400|required events must be a table")
        for _, event in ipairs(requiredEvents) do
            -- Fix: Check if event exists in helpers.events (numeric values, not boolean)
            assert(helpers.events[event] ~= nil, "400|invalid event: " .. tostring(event))
        end
    end


    bot.name = name and name or bot.name
    bot.pfp = pfp and pfp or bot.pfp
    bot.banner = banner and banner or bot.banner
    bot.description = description and description or bot.description
    bot.required_events = requiredEvents and requiredEvents or bot.required_events

    utils.bots.set(botProcess, bot)

    msg.reply({
        action = "update-bot-response",
        status = helpers.status.success,
    })
end

Handlers.add("update-bot", function(msg)
    utils.handle_run(update_bot, msg)
end)


local function remove_bot(msg)
    local userId = msg.from
    local botProcess = utils.var_or_nil(msg["bot-process"])

    local profile = utils.profiles.get(userId)
    assert(profile, "404|profile not found")

    assert(botProcess, "400|bot process is required")
    assert(utils.valid_tx_id(botProcess), "400|bot process must be a valid arweave tx id")

    local bot = utils.bots.get(botProcess)
    assert(bot, "404|bot not found")

    assert(bot.owner_id == userId, "401|unauthorized")

    -- make the bot unsubscribe from all servers

    utils.bots.set(botProcess, nil)

    msg.reply({
        action = "remove-bot-response",
        status = helpers.status.success,
    })
end

Handlers.add("remove-bot", function(msg)
    utils.handle_run(remove_bot, msg)
end)

--#endregion
