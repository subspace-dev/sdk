local json = require("json")

--#region configuration

subspace_id = subspace_id or "<<SUBSPACE>>"
version_ = version_ or "1.0.0"

--#endregion

--#region helpers

helpers = helpers or {
    logs = {},
    --- @type table<string, table<string, boolean>>
    role_to_member = {},            -- {roleId = {memberId=true, memberId=true, ...}}
    --- @type table<string, boolean>
    bans = {},                      -- {userId = true...}
    --- @type table<string, string>
    channel_to_category = {},       -- {channelId = categoryId}
    -- - @type table<string, Permission>
    permissions = {                 -- read only
        send_messages    = 1 << 0,  -- 1
        manage_nicknames = 1 << 1,  -- 2
        manage_messages  = 1 << 2,  -- 4
        kick_members     = 1 << 3,  -- 8
        ban_members      = 1 << 4,  -- 16
        manage_channels  = 1 << 5,  -- 32
        manage_server    = 1 << 6,  -- 64
        manage_roles     = 1 << 7,  -- 128
        manage_members   = 1 << 8,  -- 256
        mention_everyone = 1 << 9,  -- 512
        administrator    = 1 << 10, -- 1024
        attachments      = 1 << 11, -- 2048
        manage_bots      = 1 << 12, -- 4096
    },
    status = {                      -- read only
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
    --- @type table<string, ServerEvent>
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
    -- Handle both error format and log format
    if e.timestamp and e.status and e.action and e.error then
        -- [timestamp] status | action => error
        print(colors.blue .. "[" .. tostring(e.timestamp) .. colors.reset .. "] " ..
            colors.bg_red .. tostring(e.status) .. colors.reset .. " | " ..
            colors.yellow .. tostring(e.action) .. colors.reset .. " => " ..
            colors.red .. tostring(e.error) .. colors.reset)
    else
        -- Generic log format - just print the table
        print(json.encode(e))
    end
end

-- Define log function early so it can be used by permission_utils
local function log_message(context, message, data)
    -- Safely handle nil values
    local safe_context = context or "unknown"
    local safe_message = message or "no message"
    local safe_data = data or {}

    local log_entry = {
        context = safe_context,
        message = safe_message,
        data = safe_data,
        timestamp = os.date("%Y-%m-%d %H:%M:%S", os.time() + 12600) -- GMT+5:30
    }
    table.insert(helpers.logs, log_entry)
    -- Also print to console for debugging
    pprint({
        ["[" .. safe_context .. "]"] = safe_message,
        data = safe_data
    })
end

-- Common logging utility for informative logs
local function log(tag, message, data)
    local log_msg = string.format("[%s] %s", tag, message)
    if data then
        log_msg = log_msg .. " | " .. json.encode(data)
    end
    print(log_msg)
end

local category_id = get_id()
local uncategorised_channel_id = get_id()
local categorised_channel_id = get_id()

--- @type table<string, Member>
members = members or {}

--- @type table<string, Member>
bots = bots or {}

--- @type table<string, table<string, Message>> -- channelId -> messageId -> message
messages = messages or {}

server = server or {
    version = version_,
    --- @type Server
    profile = {
        id = id,
        owner = owner,
        name = "",
        description = "",
        pfp = "",
        banner = "",
        -- public_server field removed
    },
    member_count = 0,
    --- @type table<string, Category>
    categories = {
        [category_id] = {
            id = category_id,
            name = "Welcome",
            order = 1,
        }
    },
    --- @type table<string, Channel>
    channels = {
        [uncategorised_channel_id] = {
            id = uncategorised_channel_id,
            name = "gm",
            order = 1,
            category_id = nil, -- uncategorised,
            allow_messaging = nil,
            allow_attachments = nil,
        },
        [categorised_channel_id] = {
            id = categorised_channel_id,
            name = "general",
            order = 1,
            category_id = category_id, -- categorised
            allow_messaging = nil,
            allow_attachments = nil,
        },
    },
    --- @type table<string, Role>
    roles = {
        ["@"] = {
            id = "@",
            name = "everyone",
            order = 1,                                       -- larger number = role is above
            color = "#99AAB5",
            permissions = helpers.permissions.send_messages, -- SEND_MESSAGES
            mentionable = false,
            hoist = true,
        }
    },
}

--#endregion

--#region utils

local function is_bot(memberId)
    return bots[memberId] ~= nil
end

local role_utils = {
    --- @param roleId string
    --- @return Role | nil
    get = function(roleId)
        return server.roles[roleId]
    end,
    --- @param roleId string
    --- @param role Role
    set = function(roleId, role)
        server.roles[roleId] = role
    end,
    --- @param roleId string
    --- @param memberId string
    assign = function(roleId, memberId)
        -- Get member from appropriate table (members or bots)
        local member = members[memberId] or bots[memberId]
        if member then
            member.roles[roleId] = roleId
            if member.is_bot then
                bots[memberId] = member
            else
                members[memberId] = member
            end
            helpers.role_to_member[roleId] = helpers.role_to_member[roleId] or {}
            helpers.role_to_member[roleId][memberId] = true
        end
    end,
    --- @param roleId string
    --- @param memberId string
    unassign = function(roleId, memberId)
        -- Get member from appropriate table (members or bots)
        local member = members[memberId] or bots[memberId]
        if member then
            member.roles[roleId] = nil
            if member.is_bot then
                bots[memberId] = member
            else
                members[memberId] = member
            end
            helpers.role_to_member[roleId] = helpers.role_to_member[roleId] or {}
            helpers.role_to_member[roleId][memberId] = nil
        end
    end,
}


local member_utils = {
    --- @param memberId string
    --- @return Member | nil
    get = function(memberId)
        -- Check both members and bots tables
        local m = members[memberId] or bots[memberId]
        if not m then return nil end

        -- Create a copy to avoid modifying stored data
        local member_copy = {}
        for k, v in pairs(m) do
            if k == "roles" then
                -- Copy roles table without modification
                member_copy.roles = {}
                for roleId, roleData in pairs(v) do
                    member_copy.roles[roleId] = roleData
                end
            else
                member_copy[k] = v
            end
        end

        -- Ensure is_bot flag is set correctly
        member_copy.is_bot = bots[memberId] ~= nil
        return member_copy
    end,
    --- @param memberId string
    --- @param member Member|nil
    set = function(memberId, member)
        if member and member.is_bot then
            bots[memberId] = member
            -- Remove from members table if it exists there
            members[memberId] = nil
        else
            members[memberId] = member
            -- Remove from bots table if it exists there
            bots[memberId] = nil
        end
    end,
    is_bot = is_bot,
}


local bot_utils = {
    --- @param botId string
    --- @return Member | nil
    get = function(botId)
        return member_utils.get(botId)
    end,
    --- @param botId string
    --- @param bot Member|nil
    set = function(botId, bot)
        bot.is_bot = true
        member_utils.set(botId, bot)
    end,
}


local permission_utils = {
    --- @param member Member
    --- @return number -- Returns the highest role order for the member
    get_highest_role_order = function(member)
        local highest_order = 0
        for roleId, _ in pairs(member.roles) do
            local role = role_utils.get(roleId)
            if role and type(role.order) == "number" and role.order > highest_order then
                highest_order = role.order
            end
        end
        return highest_order
    end,
    --- @param member Member
    --- @param permission number
    --- @return boolean
    member_has = function(member, permission)
        -- Convert permission to number if it's a string number
        local perm_num
        if type(permission) == "string" then
            perm_num = tonumber(permission)
        else
            perm_num = permission
        end
        -- Ensure permission is a number
        if type(perm_num) ~= "number" then
            log_message("member_has", "Invalid permission type", {
                member_id = member.id,
                permission_type = type(permission)
            })
            return false
        end
        permission = perm_num

        local perm_int = 0
        local role_perms = {}
        for roleId, _ in pairs(member.roles) do
            local role = role_utils.get(roleId)
            local role_perm = role and role.permissions
            -- Convert role permission to number if it's a string number
            if type(role_perm) == "string" then
                role_perm = tonumber(role_perm)
            end
            if role_perm and type(role_perm) == "number" then
                perm_int = perm_int | role_perm
                role_perms[roleId] = role_perm
            end
        end

        -- Check for owner or administrator permission
        if member.id == owner then
            log_message("member_has", "Owner bypass", {
                member_id = member.id,
                permission = permission,
                result = true
            })
            return true
        end

        -- Check for administrator permission (administrator has all permissions)
        if perm_int & helpers.permissions.administrator == helpers.permissions.administrator then
            log_message("member_has", "Administrator bypass", {
                member_id = member.id,
                permission = permission,
                combined_perms = perm_int,
                result = true
            })
            return true
        end

        local result = perm_int & permission == permission
        -- Count roles manually to avoid circular dependency
        local role_count = 0
        for _ in pairs(member.roles) do
            role_count = role_count + 1
        end
        log_message("member_has", "Permission check", {
            member_id = member.id,
            permission = permission,
            combined_perms = perm_int,
            role_count = role_count,
            result = result
        })

        return result
    end,

    --- @param role Role
    --- @param permission number
    --- @return boolean
    role_has = function(role, permission)
        -- Convert permission to number if it's a string number
        local perm_num
        if type(permission) == "string" then
            perm_num = tonumber(permission)
        else
            perm_num = permission
        end
        -- Ensure permission is a number
        if type(perm_num) ~= "number" then return false end
        permission = perm_num

        local role_perm = role.permissions or 0
        -- Convert role permission to number if it's a string number
        if type(role_perm) == "string" then
            role_perm = tonumber(role_perm) or 0
        end

        return role_perm & permission == permission
    end,
    --- @param member Member
    --- @param permissions table<number> -- Array of permissions to check (OR logic)
    --- @return boolean
    member_has_any = function(member, permissions)
        local perm_int = 0
        for roleId, _ in pairs(member.roles) do
            local role = role_utils.get(roleId)
            local role_perm = role and role.permissions
            -- Convert role permission to number if it's a string number
            if type(role_perm) == "string" then
                role_perm = tonumber(role_perm)
            end
            if role_perm and type(role_perm) == "number" then
                perm_int = perm_int | role_perm
            end
        end

        -- Check for owner or administrator permission
        if member.id == owner then
            log_message("member_has_any", "Owner bypass", {
                member_id = member.id,
                permissions_count = #permissions,
                result = true
            })
            return true
        end

        -- Check for administrator permission (administrator has all permissions)
        if perm_int & helpers.permissions.administrator == helpers.permissions.administrator then
            log_message("member_has_any", "Administrator bypass", {
                member_id = member.id,
                permissions_count = #permissions,
                combined_perms = perm_int,
                result = true
            })
            return true
        end

        -- Check if member has any of the specified permissions
        local matched_permission = nil
        for _, permission in ipairs(permissions) do
            -- Convert permission to number if it's a string number
            if type(permission) == "string" then
                permission = tonumber(permission)
            end
            -- Ensure each permission is a number before comparing
            if type(permission) == "number" and perm_int & permission == permission then
                matched_permission = permission
                log_message("member_has_any", "Permission matched", {
                    member_id = member.id,
                    matched_permission = permission,
                    combined_perms = perm_int,
                    result = true
                })
                return true
            end
        end

        log_message("member_has_any", "No permissions matched", {
            member_id = member.id,
            permissions_checked = #permissions,
            combined_perms = perm_int,
            result = false
        })
        return false
    end,

}

--- @param event table
local function push_event(event)
    -- Push event data to bot subscribers only
    -- Only bots can subscribe to events, so all subscribers are bots

    if not server.subscribers then
        return -- No subscribers
    end

    local eventType = event.event_type
    assert(eventType, "event_type is required")

    -- Iterate through all bot subscribers
    for subscriberId, subscription in pairs(server.subscribers) do
        -- Check if bot is interested in this event type
        local isInterestedInEvent = false
        for _, subscribedEvent in ipairs(subscription.events) do
            if subscribedEvent == eventType then
                isInterestedInEvent = true
                break
            end
        end

        if isInterestedInEvent then
            -- Send event to bot subscriber
            send({
                target = subscriberId,
                action = "event",
                ["event-type"] = eventType,
                data = json.encode(event),
                timestamp = os.time()
            })
        end
    end
end

local utils = {
    var_or_nil = function(var)
        return var ~= "" and var or nil
    end,
    count_keys = function(tbl)
        local count = 0
        for _ in pairs(tbl) do
            count = count + 1
        end
        return count
    end,
    log = log_message,
    info_log = log,
    handle_run = function(func, msg)
        msg.reply = function(data)
            local target = msg.from
            if not msg['from-process'] then
                target = id
            end
            data.target = target
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
            local target = msg.from
            if not msg['from-process'] then
                target = id
            end
            send({
                target = target,
                action = "error",
                ["x-status"] = res.status,
                ["x-error"] = res.error,
                ["x-action"] = msg.action,
                timestamp = os.time()
            })
        end
    end,
    get_id = get_id,
    members = member_utils,
    roles = role_utils,
    bots = bot_utils,
    categories = {
        --- @param categoryId string
        --- @return Category | nil
        get = function(categoryId)
            return server.categories[categoryId]
        end,
        --- @param categoryId string
        --- @param category Category
        set = function(categoryId, category)
            server.categories[categoryId] = category
        end,
    },
    channels = {
        --- @param channelId string
        --- @return Channel | nil
        get = function(channelId)
            return server.channels[channelId]
        end,
        --- @param channelId string
        --- @param channel Channel
        set = function(channelId, channel)
            server.channels[channelId] = channel
            if channel.category_id then
                helpers.channel_to_category[channelId] = channel.category_id
            else
                helpers.channel_to_category[channelId] = nil
            end
        end,
        --- @param channel Channel
        --- @param member Member
        --- @return boolean
        can_send = function(channel, member)
            -- Rule 1: If channel.allowMessaging is nil, fallback to permission check
            if channel.allow_messaging == nil then
                local has_perm = permission_utils.member_has(member, helpers.permissions.send_messages)
                log_message("can_send", "Rule 1: Default permission check", {
                    member_id = member.id,
                    has_send_messages_perm = has_perm
                })
                return has_perm
            end
            -- Rule 2: If channel.allowMessaging is 1, allow everyone to message
            if channel.allow_messaging == 1 then
                log_message("can_send", "Rule 2: Open channel - everyone can send", {
                    member_id = member.id,
                    result = true
                })
                return true
            end
            -- Rule 3: If channel.allowMessaging is 0, only allow members with manage channel permissions and above
            if channel.allow_messaging == 0 then
                local is_owner = member.id == owner
                local has_manage_channels = permission_utils.member_has(member, helpers.permissions.manage_channels)
                local has_admin = permission_utils.member_has(member, helpers.permissions.administrator)
                local result = is_owner or has_manage_channels or has_admin

                log_message("can_send", "Rule 3: Restricted channel", {
                    member_id = member.id,
                    is_owner = is_owner,
                    has_manage_channels = has_manage_channels,
                    has_administrator = has_admin,
                    result = result
                })
                return result
            end
            -- Default fallback (shouldn't reach here normally)
            log_message("can_send", "Default fallback - denying access", {
                member_id = member.id,
                allow_messaging = channel.allow_messaging
            })
            return false
        end
    },
    messages = {
        --- @param messageId string
        --- @param message Message
        set = function(messageId, message)
            messages[message.channel_id] = messages[message.channel_id] or {}
            messages[message.channel_id][messageId] = message
        end,
    },
    permissions = permission_utils,
}

--#endregion

--#region setup

local function setup(msg)
    assert(msg.from == subspace_id, "403|unauthorized sender")

    local serverName = msg["server-name"]
    local serverDescription = msg["server-description"]
    local serverPfp = msg["server-pfp"]
    local serverBanner = msg["server-banner"]
    -- serverPublic parameter removed

    server.profile.name = serverName or ""
    server.profile.description = serverDescription or ""
    server.profile.pfp = serverPfp or ""
    server.profile.banner = serverBanner or ""
    -- server.profile.public_server field removed
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

local function update_server(msg)
    local senderId = msg.from

    -- serverPublic parameter removed
    local serverName = utils.var_or_nil(msg["server-name"])
    local serverDescription = utils.var_or_nil(msg["server-description"])
    local serverPfp = utils.var_or_nil(msg["server-pfp"])
    local serverBanner = utils.var_or_nil(msg["server-banner"])

    utils.info_log("UPDATE_SERVER", "Updating server settings", {
        sender_id = senderId,
        updating_name = serverName ~= nil
    })

    -- validate senderId permissions
    local senderMember = utils.members.get(senderId)
    assert(senderMember, "404|sender not found")
    assert(utils.permissions.member_has(senderMember, helpers.permissions.manage_server),
        "403|insufficient permissions to update server")

    local profile = server.profile
    -- profile.public_server field removed
    profile.name = serverName or profile.name
    profile.description = serverDescription or profile.description
    profile.pfp = serverPfp or profile.pfp
    profile.banner = serverBanner or profile.banner

    server.profile = profile

    -- send updates to subspace as well
    send({
        target = subspace_id,
        action = "update-server",
        -- server-public parameter removed
        ["server-name"] = serverName,
        ["server-description"] = serverDescription,
        ["server-pfp"] = serverPfp,
        ["server-banner"] = serverBanner
    })

    msg.reply({
        action = "update-server-response",
        status = helpers.status.success,
        data = json.encode(server)
    })
end

Handlers.add("update-server", function(msg)
    utils.handle_run(update_server, msg)
end)

--#endregion

--#region members

local function add_member(msg)
    local senderId = msg.from
    local userId = msg["user-id"]
    local isBot = msg["is-bot"]

    assert(senderId == subspace_id, "403|unauthorized sender")
    assert(userId, "400|user-id is required")

    utils.info_log("ADD_MEMBER", "Processing join request", {
        user_id = userId,
        user_type = isBot and "bot" or "user"
    })

    -- Check if user is banned
    if helpers.bans[userId] then
        error("403|user is banned from this server")
    end

    -- Check if user is already a member
    local existingMember = utils.members.get(userId)
    if existingMember then
        -- Update existing member data instead of creating new one
        existingMember.nickname = existingMember.nickname or ""
        existingMember.joined_at = existingMember.joined_at or os.time()
        existingMember.is_bot = isBot or false
        utils.members.set(userId, existingMember)
    else
        local memberData = {
            id = userId,
            nickname = "",
            joined_at = os.time(),
            roles = {
                ["@"] = "@",
            },
            is_bot = isBot or false,
        }

        -- Use utils.members.set to properly update the members table
        utils.members.set(userId, memberData)
    end

    -- Assign the @everyone role using role_utils
    role_utils.assign("@", userId)

    -- Only increment member count if this is a new member
    if not existingMember then
        server.member_count = math.max(server.member_count + 1, 0)
        utils.info_log("MEMBER_ADDED", "Member joined", {
            user_id = userId,
            user_type = isBot and "bot" or "user",
            total_members = server.member_count
        })
    else
        utils.info_log("MEMBER_UPDATED", "Member data refreshed", {
            user_id = userId,
            user_type = isBot and "bot" or "user"
        })
    end

    -- Push event to subscribers
    push_event({
        event_type = helpers.events.member_joined,
        user_id = userId,
        is_bot = isBot,
        timestamp = os.time()
    })

    send({
        target = subspace_id,
        action = "approve-add-member",
        status = helpers.status.success,
        ["user-id"] = userId,
    })
end

Handlers.add("add-member", function(msg)
    utils.handle_run(add_member, msg)
end)

local function remove_member(msg)
    local senderId = msg.from
    assert(senderId == subspace_id, "403|unauthorized sender")
    local userId = msg["user-id"]

    assert(userId, "400|user-id is required")

    local member = utils.members.get(userId)
    assert(member, "404|member not found")

    local isBot = member.is_bot

    utils.info_log("REMOVE_MEMBER", "Leaving server", {
        user_id = userId,
        user_type = isBot and "bot" or "user"
    })

    -- Remove all roles first
    for roleId, _ in pairs(member.roles) do
        role_utils.unassign(roleId, userId)
    end
    role_utils.unassign("@", userId)

    -- Remove from appropriate table
    if isBot then
        bots[userId] = nil
    else
        members[userId] = nil
    end

    server.member_count = math.max(server.member_count - 1, 0)

    utils.info_log("MEMBER_LEFT", "Member removed", {
        user_id = userId,
        user_type = isBot and "bot" or "user",
        total_members = server.member_count
    })

    -- Push event to subscribers
    push_event({
        event_type = helpers.events.member_left,
        user_id = userId,
        is_bot = isBot,
        timestamp = os.time()
    })

    msg.reply({
        target = subspace_id,
        action = "approve-remove-member",
        ["user-id"] = userId,
        status = helpers.status.success,
    })
end

Handlers.add("remove-member", function(msg)
    utils.handle_run(remove_member, msg)
end)

local function update_member(msg)
    local senderId = msg.from

    -- members can only update their own nickname for now
    -- or mods with manage nicknames or manage server permissions can update other members' nicknames

    local userId = msg["user-id"] or senderId
    local nickname = utils.var_or_nil(msg["nickname"])

    utils.info_log("UPDATE_MEMBER", "Updating member", {
        editor_id = senderId,
        target_id = userId,
        self_edit = userId == senderId
    })

    local member = utils.members.get(userId)
    assert(member, "404|member not found")

    local editingSelf = userId == senderId

    if not editingSelf then
        -- Get sender member to check permissions
        local senderMember = utils.members.get(senderId)
        assert(senderMember, "404|sender not found")

        -- Check permissions using standardized helper
        assert(utils.permissions.member_has_any(senderMember, {
            helpers.permissions.manage_nicknames,
            helpers.permissions.manage_members,
            helpers.permissions.manage_server,
            helpers.permissions.administrator
        }), "403|insufficient permissions to update member")
    end

    -- Allow setting nickname to nil to unset it
    if nickname == "__unset__" then
        member.nickname = "" -- Set to empty string when unsetting
    else
        member.nickname = tostring(nickname)
    end
    utils.members.set(userId, member)

    msg.reply({
        action = "update-member-response",
        status = helpers.status.success,
    })
end

Handlers.add("update-member", function(msg)
    utils.handle_run(update_member, msg)
end)

local function kick_member(msg)
    local senderId = msg.from
    local userId = msg["user-id"]

    assert(userId, "400|user-id is required")
    assert(userId ~= senderId, "400|cannot kick yourself")

    utils.info_log("KICK", "Kicking member", {
        kicked_by = senderId,
        user_id = userId
    })

    -- Get sender member to check permissions
    local senderMember = utils.members.get(senderId)
    assert(senderMember, "404|sender not found")

    -- Check permissions using standardized helper
    assert(utils.permissions.member_has_any(senderMember, {
        helpers.permissions.kick_members,
        helpers.permissions.manage_members,
        helpers.permissions.manage_server,
        helpers.permissions.administrator
    }), "403|insufficient permissions to kick members")

    -- Get the member to kick
    local member = utils.members.get(userId)
    assert(member, "404|member not found")

    local isBot = member.is_bot

    -- Remove all roles first
    for roleId, _ in pairs(member.roles) do
        role_utils.unassign(roleId, userId)
    end
    role_utils.unassign("@", userId)

    -- Remove from appropriate table
    if isBot then
        bots[userId] = nil
    else
        members[userId] = nil
    end

    -- Decrement member count
    server.member_count = math.max(server.member_count - 1, 0)

    -- Push event to subscribers
    push_event({
        event_type = helpers.events.member_kicked,
        user_id = userId,
        kicked_by = senderId,
        is_bot = isBot,
        timestamp = os.time()
    })

    send({
        target = subspace_id,
        action = "approve-remove-member",
        ["user-id"] = userId,
        status = helpers.status.success,
    })

    msg.reply({
        action = "kick-member-response",
        status = helpers.status.success,
    })
end

Handlers.add("kick-member", function(msg)
    utils.handle_run(kick_member, msg)
end)

local function ban_member(msg)
    local senderId = msg.from
    local userId = msg["user-id"]

    assert(userId, "400|user-id is required")
    assert(userId ~= senderId, "400|cannot ban yourself")

    utils.info_log("BAN", "Banning member", {
        banned_by = senderId,
        user_id = userId
    })

    -- Get sender member to check permissions
    local senderMember = utils.members.get(senderId)
    assert(senderMember, "404|sender not found")

    -- Check permissions using standardized helper
    assert(utils.permissions.member_has_any(senderMember, {
        helpers.permissions.ban_members,
        helpers.permissions.manage_members,
        helpers.permissions.manage_server,
        helpers.permissions.administrator
    }), "403|insufficient permissions to ban members")

    -- Get the member to ban
    local member = utils.members.get(userId)
    assert(member, "404|member not found")

    local isBot = member.is_bot

    -- Remove all roles first
    for roleId, _ in pairs(member.roles) do
        role_utils.unassign(roleId, userId)
    end
    role_utils.unassign("@", userId)

    -- Remove from appropriate table
    if isBot then
        bots[userId] = nil
    else
        members[userId] = nil
    end

    -- Add to ban list
    helpers.bans[userId] = true

    -- Decrement member count
    server.member_count = math.max(server.member_count - 1, 0)

    -- Push event to subscribers
    push_event({
        event_type = helpers.events.member_banned,
        user_id = userId,
        banned_by = senderId,
        is_bot = isBot,
        timestamp = os.time()
    })

    send({
        target = subspace_id,
        action = "approve-remove-member",
        ["user-id"] = userId,
        status = helpers.status.success,
    })

    msg.reply({
        action = "ban-member-response",
        status = helpers.status.success,
    })
end

Handlers.add("ban-member", function(msg)
    utils.handle_run(ban_member, msg)
end)

local function unban_member(msg)
    local senderId = msg.from
    local userId = msg["user-id"]

    assert(userId, "400|user-id is required")

    -- Get sender member to check permissions
    local senderMember = utils.members.get(senderId)
    assert(senderMember, "404|sender not found")

    -- Check permissions using standardized helper
    assert(utils.permissions.member_has_any(senderMember, {
        helpers.permissions.ban_members,
        helpers.permissions.manage_members,
        helpers.permissions.manage_server,
        helpers.permissions.administrator
    }), "403|insufficient permissions to unban members")

    -- Check if user is actually banned
    assert(helpers.bans[userId], "400|user is not banned")

    helpers.bans[userId] = nil

    utils.info_log("UNBAN", "Member unbanned", {
        unbanned_by = senderId,
        user_id = userId
    })

    msg.reply({
        action = "unban-member-response",
        status = helpers.status.success,
    })
end

Handlers.add("unban-member", function(msg)
    utils.handle_run(unban_member, msg)
end)

--#endregion

--#region categories

local function create_category(msg)
    local senderId = msg.from
    local categoryName = utils.var_or_nil(msg["category-name"])
    local categoryOrder = msg["category-order"]

    assert(categoryName, "400|category-name is required")
    assert(type(categoryName) == "string", "400|category-name must be a string")

    utils.info_log("CREATE_CATEGORY", "Creating category", {
        creator_id = senderId,
        category_name = categoryName
    })

    -- Get sender member to check permissions
    local senderMember = utils.members.get(senderId)
    assert(senderMember, "404|sender not found")

    -- Check permissions using standardized helper
    assert(utils.permissions.member_has_any(senderMember, {
        helpers.permissions.manage_channels,
        helpers.permissions.manage_server,
        helpers.permissions.administrator
    }), "403|insufficient permissions to create categories")

    local categoryId = utils.get_id()

    -- If no order specified, put it at the end
    if not categoryOrder then
        local maxOrder = 0
        for _, category in pairs(server.categories) do
            if category.order > maxOrder then
                maxOrder = category.order
            end
        end
        categoryOrder = maxOrder + 1
    end

    local category = {
        id = categoryId,
        name = categoryName,
        order = categoryOrder,
    }

    utils.categories.set(categoryId, category)

    msg.reply({
        action = "create-category-response",
        status = helpers.status.success,
        data = json.encode(category)
    })
end

Handlers.add("create-category", function(msg)
    utils.handle_run(create_category, msg)
end)

local function update_category(msg)
    local senderId = msg.from
    local categoryId = utils.var_or_nil(msg["category-id"])
    local categoryName = utils.var_or_nil(msg["category-name"])
    local categoryOrder = msg["category-order"]

    assert(categoryId, "400|category-id is required")

    utils.info_log("UPDATE_CATEGORY", "Updating category", {
        editor_id = senderId,
        category_id = categoryId
    })

    -- Get sender member to check permissions
    local senderMember = utils.members.get(senderId)
    assert(senderMember, "404|sender not found")

    -- Check permissions using standardized helper
    assert(utils.permissions.member_has_any(senderMember, {
        helpers.permissions.manage_channels,
        helpers.permissions.manage_server,
        helpers.permissions.administrator
    }), "403|insufficient permissions to update categories")

    local category = utils.categories.get(categoryId)
    assert(category, "404|category not found")

    if categoryName then
        assert(type(categoryName) == "string", "400|category-name must be a string")
        category.name = categoryName
    end

    if categoryOrder then
        assert(type(categoryOrder) == "number", "400|category-order must be a number")
        category.order = categoryOrder
    end

    utils.categories.set(categoryId, category)

    msg.reply({
        action = "update-category-response",
        status = helpers.status.success,
        data = json.encode(category)
    })
end

Handlers.add("update-category", function(msg)
    utils.handle_run(update_category, msg)
end)

local function delete_category(msg)
    local senderId = msg.from
    local categoryId = utils.var_or_nil(msg["category-id"])

    assert(categoryId, "400|category-id is required")

    utils.info_log("DELETE_CATEGORY", "Deleting category", {
        deleter_id = senderId,
        category_id = categoryId
    })

    -- Get sender member to check permissions
    local senderMember = utils.members.get(senderId)
    assert(senderMember, "404|sender not found")

    -- Check permissions using standardized helper
    assert(utils.permissions.member_has_any(senderMember, {
        helpers.permissions.manage_channels,
        helpers.permissions.manage_server,
        helpers.permissions.administrator
    }), "403|insufficient permissions to delete categories")

    local category = utils.categories.get(categoryId)
    assert(category, "404|category not found")

    -- Move all channels in this category to uncategorized
    for channelId, channel in pairs(server.channels) do
        if channel.category_id == categoryId then
            channel.category_id = nil
            utils.channels.set(channelId, channel)
        end
    end

    -- Delete the category
    server.categories[categoryId] = nil

    msg.reply({
        action = "delete-category-response",
        status = helpers.status.success,
    })
end

Handlers.add("delete-category", function(msg)
    utils.handle_run(delete_category, msg)
end)

--#endregion

--#region channels

local function create_channel(msg)
    local senderId = msg.from
    local channelName = utils.var_or_nil(msg["channel-name"])
    local categoryId = utils.var_or_nil(msg["category-id"])
    local channelOrder = msg["channel-order"]
    local allowMessaging = msg["allow-messaging"]
    local allowAttachments = msg["allow-attachments"]

    assert(channelName, "400|channel-name is required")
    assert(type(channelName) == "string", "400|channel-name must be a string")

    utils.info_log("CREATE_CHANNEL", "Creating channel", {
        creator_id = senderId,
        channel_name = channelName,
        category_id = categoryId
    })

    -- Validate and convert allow_messaging if provided
    if allowMessaging ~= nil then
        if type(allowMessaging) == "string" then
            allowMessaging = tonumber(allowMessaging)
        end
        assert(type(allowMessaging) == "number", "400|allow-messaging must be a number (0 or 1)")
        assert(allowMessaging == 0 or allowMessaging == 1, "400|allow-messaging must be 0 or 1")
    end

    -- Validate and convert allow_attachments if provided
    if allowAttachments ~= nil then
        if type(allowAttachments) == "string" then
            allowAttachments = tonumber(allowAttachments)
        end
        assert(type(allowAttachments) == "number", "400|allow-attachments must be a number (0 or 1)")
        assert(allowAttachments == 0 or allowAttachments == 1, "400|allow-attachments must be 0 or 1")
    end

    -- Get sender member to check permissions
    local senderMember = utils.members.get(senderId)
    assert(senderMember, "404|sender not found")

    -- Check permissions using standardized helper
    assert(utils.permissions.member_has_any(senderMember, {
        helpers.permissions.manage_channels,
        helpers.permissions.manage_server,
        helpers.permissions.administrator
    }), "403|insufficient permissions to create channels")

    -- Validate category if provided
    if categoryId then
        local category = utils.categories.get(categoryId)
        assert(category, "404|category not found")
    end

    local channelId = utils.get_id()

    -- If no order specified, put it at the end within the category
    if not channelOrder then
        local maxOrder = 0
        for _, channel in pairs(server.channels) do
            if channel.category_id == categoryId and channel.order > maxOrder then
                maxOrder = channel.order
            end
        end
        channelOrder = maxOrder + 1
    end

    local channel = {
        id = channelId,
        name = channelName,
        order = channelOrder,
        category_id = categoryId,
        allow_messaging = allowMessaging,
        allow_attachments = allowAttachments,
    }

    utils.channels.set(channelId, channel)

    msg.reply({
        action = "create-channel-response",
        status = helpers.status.success,
        data = json.encode(channel)
    })
end

Handlers.add("create-channel", function(msg)
    utils.handle_run(create_channel, msg)
end)

local function update_channel(msg)
    local senderId = msg.from
    local channelId = utils.var_or_nil(msg["channel-id"])
    local channelName = utils.var_or_nil(msg["channel-name"])
    local categoryId = utils.var_or_nil(msg["category-id"])
    local channelOrder = msg["channel-order"]
    local allowMessaging = msg["allow-messaging"]
    local allowAttachments = msg["allow-attachments"]

    assert(channelId, "400|channel-id is required")

    utils.info_log("UPDATE_CHANNEL", "Updating channel", {
        editor_id = senderId,
        channel_id = channelId
    })

    -- Get sender member to check permissions
    local senderMember = utils.members.get(senderId)
    assert(senderMember, "404|sender not found")

    -- Check permissions using standardized helper
    assert(utils.permissions.member_has_any(senderMember, {
        helpers.permissions.manage_channels,
        helpers.permissions.manage_server,
        helpers.permissions.administrator
    }), "403|insufficient permissions to update channels")

    local channel = utils.channels.get(channelId)
    assert(channel, "404|channel not found")

    -- Validate category if provided
    if categoryId then
        local category = utils.categories.get(categoryId)
        assert(category, "404|category not found")
    end

    if channelName then
        assert(type(channelName) == "string", "400|channel-name must be a string")
        channel.name = channelName
    end

    if categoryId ~= nil then -- Allow setting to nil to uncategorize
        channel.category_id = categoryId
    end

    if channelOrder then
        assert(type(channelOrder) == "number", "400|channel-order must be a number")
        channel.order = channelOrder
    end

    if allowMessaging ~= nil then
        if type(allowMessaging) == "string" then
            allowMessaging = tonumber(allowMessaging)
        end
        assert(type(allowMessaging) == "number", "400|allow-messaging must be a number (0 or 1)")
        assert(allowMessaging == 0 or allowMessaging == 1, "400|allow-messaging must be 0 or 1")
        channel.allow_messaging = allowMessaging -- 0 = restricted, 1 = allowed, nil = default
    end

    if allowAttachments ~= nil then
        if type(allowAttachments) == "string" then
            allowAttachments = tonumber(allowAttachments)
        end
        assert(type(allowAttachments) == "number", "400|allow-attachments must be a number (0 or 1)")
        assert(allowAttachments == 0 or allowAttachments == 1, "400|allow-attachments must be 0 or 1")
        channel.allow_attachments = allowAttachments -- 0 = restricted, 1 = allowed, nil = default
    end

    utils.channels.set(channelId, channel)

    msg.reply({
        action = "update-channel-response",
        status = helpers.status.success,
        data = json.encode(channel)
    })
end

Handlers.add("update-channel", function(msg)
    utils.handle_run(update_channel, msg)
end)

local function delete_channel(msg)
    local senderId = msg.from
    local channelId = utils.var_or_nil(msg["channel-id"])

    assert(channelId, "400|channel-id is required")

    utils.info_log("DELETE_CHANNEL", "Deleting channel", {
        deleter_id = senderId,
        channel_id = channelId
    })

    -- Get sender member to check permissions
    local senderMember = utils.members.get(senderId)
    assert(senderMember, "404|sender not found")

    -- Check permissions using standardized helper
    assert(utils.permissions.member_has_any(senderMember, {
        helpers.permissions.manage_channels,
        helpers.permissions.manage_server,
        helpers.permissions.administrator
    }), "403|insufficient permissions to delete channels")

    local channel = utils.channels.get(channelId)
    assert(channel, "404|channel not found")

    -- Remove from channel to category mapping
    helpers.channel_to_category[channelId] = nil

    -- Delete all messages in the channel
    messages[channelId] = nil

    -- Delete the channel
    server.channels[channelId] = nil

    msg.reply({
        action = "delete-channel-response",
        status = helpers.status.success,
    })
end

Handlers.add("delete-channel", function(msg)
    utils.handle_run(delete_channel, msg)
end)

--#endregion

--#region roles

local function create_role(msg)
    local senderId = msg.from
    local roleName = utils.var_or_nil(msg["role-name"])
    local roleColor = utils.var_or_nil(msg["role-color"])
    local rolePermissions = utils.var_or_nil(msg["role-permissions"]) or 0
    local roleOrder = msg["role-order"]
    local mentionable = msg["mentionable"]
    local hoist = msg["hoist"]

    utils.info_log("CREATE_ROLE", "Creating role", {
        creator_id = senderId,
        role_name = roleName
    })

    -- Convert and validate rolePermissions if provided
    if rolePermissions and rolePermissions ~= 0 then
        local numPermissions = tonumber(rolePermissions)
        if numPermissions == nil then
            error("400|role-permissions must be a number!")
        end
        rolePermissions = numPermissions --[[@as integer]]
    elseif rolePermissions == 0 then
        -- Default value is already 0, ensure it's a number
        rolePermissions = 0
    end

    -- Convert and validate boolean fields
    if mentionable ~= nil then
        if type(mentionable) == "string" then
            if mentionable == "true" then
                mentionable = true
            elseif mentionable == "false" then
                mentionable = false
            else
                error("400|mentionable must be a boolean!")
            end
        elseif type(mentionable) ~= "boolean" then
            error("400|mentionable must be a boolean!")
        end
    end

    if hoist ~= nil then
        if type(hoist) == "string" then
            if hoist == "true" then
                hoist = true
            elseif hoist == "false" then
                hoist = false
            else
                error("400|hoist must be a boolean!")
            end
        elseif type(hoist) ~= "boolean" then
            error("400|hoist must be a boolean!")
        end
    end

    assert(roleName, "400|role-name is required")
    assert(type(roleName) == "string", "400|role-name must be a string")

    -- Get sender member to check permissions
    local senderMember = utils.members.get(senderId)
    assert(senderMember, "404|sender not found")

    -- Check permissions using standardized helper
    assert(utils.permissions.member_has_any(senderMember, {
        helpers.permissions.manage_roles,
        helpers.permissions.manage_server,
        helpers.permissions.administrator
    }), "403|insufficient permissions to create roles")

    -- Validate permissions
    if rolePermissions then
        assert(type(rolePermissions) == "number", "400|role-permissions must be a number!")
        assert(rolePermissions >= 0, "400|role-permissions must be non-negative")
    end

    -- Validate color format (hex color)
    if roleColor then
        assert(type(roleColor) == "string", "400|role-color must be a string")
        assert(roleColor:match("^#[0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f]$"),
            "400|role-color must be a valid hex color (e.g., #FF0000)")
    end

    local roleId = utils.get_id()

    -- If no order specified, put it at the bottom (just above @everyone which is order 1)
    if not roleOrder then
        -- Shift all existing roles (except @everyone) up by 1 to make room at the bottom
        for existingRoleId, existingRole in pairs(server.roles) do
            if existingRole.id ~= "@" then
                -- Ensure order is a number before incrementing
                local currentOrder = tonumber(existingRole.order) or 1
                existingRole.order = currentOrder + 1
                utils.roles.set(existingRoleId, existingRole)
            end
        end
        roleOrder = 2 -- New role gets order 2, making it the lowest (except @everyone at 1)
    else
        -- Ensure roleOrder is a number when explicitly provided
        roleOrder = tonumber(roleOrder) or 2
    end

    local role = {
        id = roleId,
        name = roleName,
        order = roleOrder,
        color = roleColor or "#99AAB5",
        permissions = rolePermissions,
        mentionable = mentionable or false,
        hoist = hoist or false,
    }

    utils.roles.set(roleId, role)

    msg.reply({
        action = "create-role-response",
        status = helpers.status.success,
        data = json.encode(role)
    })
end

Handlers.add("create-role", function(msg)
    utils.handle_run(create_role, msg)
end)

local function update_role(msg)
    local senderId = msg.from
    local roleId = utils.var_or_nil(msg["role-id"])
    local roleName = utils.var_or_nil(msg["role-name"])
    local roleColor = utils.var_or_nil(msg["role-color"])
    local rolePermissions = utils.var_or_nil(msg["role-permissions"])
    local roleOrder = utils.var_or_nil(msg["role-order"])
    local mentionable = utils.var_or_nil(msg["mentionable"])
    local hoist = utils.var_or_nil(msg["hoist"])

    utils.info_log("UPDATE_ROLE", "Updating role", {
        editor_id = senderId,
        role_id = roleId
    })

    -- Convert and validate rolePermissions if provided
    if rolePermissions then
        local numPermissions = tonumber(rolePermissions)
        if numPermissions == nil then
            error("400|role-permissions must be a number!")
        end
        rolePermissions = numPermissions --[[@as integer]]
    end

    -- Convert and validate boolean fields
    if mentionable ~= nil then
        if type(mentionable) == "string" then
            if mentionable == "true" then
                mentionable = true
            elseif mentionable == "false" then
                mentionable = false
            else
                error("400|mentionable must be a boolean!")
            end
        elseif type(mentionable) ~= "boolean" then
            error("400|mentionable must be a boolean!")
        end
    end

    if hoist ~= nil then
        if type(hoist) == "string" then
            if hoist == "true" then
                hoist = true
            elseif hoist == "false" then
                hoist = false
            else
                error("400|hoist must be a boolean!")
            end
        elseif type(hoist) ~= "boolean" then
            error("400|hoist must be a boolean!")
        end
    end

    assert(roleId, "400|role-id is required")
    assert(roleId ~= "@", "400|cannot update everyone role")

    -- Get sender member to check permissions
    local senderMember = utils.members.get(senderId)
    assert(senderMember, "404|sender not found")

    -- Check permissions using standardized helper
    assert(utils.permissions.member_has_any(senderMember, {
        helpers.permissions.manage_roles,
        helpers.permissions.manage_server,
        helpers.permissions.administrator
    }), "403|insufficient permissions to update roles")

    local role = utils.roles.get(roleId)
    assert(role, "404|role not found")

    -- Check role hierarchy: users can only update roles below their highest role
    -- (unless they are the server owner or have administrator permission)
    if senderMember.id ~= owner and not utils.permissions.member_has(senderMember, helpers.permissions.administrator) then
        local senderHighestOrder = utils.permissions.get_highest_role_order(senderMember)
        assert(role.order < senderHighestOrder, "403|cannot update role higher than or equal to your highest role")
    end

    if roleName then
        assert(type(roleName) == "string", "400|role-name must be a string")
        role.name = roleName
    end

    if roleColor then
        assert(type(roleColor) == "string", "400|role-color must be a string")
        assert(roleColor:match("^#[0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f]$"),
            "400|role-color must be a valid hex color (e.g., #FF0000)")
        role.color = roleColor
    end

    if rolePermissions ~= nil then
        assert(type(rolePermissions) == "number", "400|role-permissions must be a number!")
        assert(rolePermissions >= 0, "400|role-permissions must be non-negative")
        role.permissions = rolePermissions
    end

    if roleOrder then
        assert(type(roleOrder) == "number", "400|role-order must be a number")
        role.order = roleOrder
    end

    if mentionable ~= nil then
        role.mentionable = mentionable
    end

    if hoist ~= nil then
        role.hoist = hoist
    end

    utils.roles.set(roleId, role)

    msg.reply({
        action = "update-role-response",
        status = helpers.status.success,
        data = json.encode(role)
    })
end

Handlers.add("update-role", function(msg)
    utils.handle_run(update_role, msg)
end)

local function delete_role(msg)
    local senderId = msg.from
    local roleId = utils.var_or_nil(msg["role-id"])

    assert(roleId, "400|role-id is required")
    assert(roleId ~= "@", "400|cannot delete everyone role")

    utils.info_log("DELETE_ROLE", "Deleting role", {
        deleter_id = senderId,
        role_id = roleId
    })

    -- Get sender member to check permissions
    local senderMember = utils.members.get(senderId)
    assert(senderMember, "404|sender not found")

    -- Check permissions using standardized helper
    assert(utils.permissions.member_has_any(senderMember, {
        helpers.permissions.manage_roles,
        helpers.permissions.manage_server,
        helpers.permissions.administrator
    }), "403|insufficient permissions to delete roles")

    local role = utils.roles.get(roleId)
    assert(role, "404|role not found")

    -- Check role hierarchy: users can only delete roles below their highest role
    -- (unless they are the server owner or have administrator permission)
    if senderMember.id ~= owner and not utils.permissions.member_has(senderMember, helpers.permissions.administrator) then
        local senderHighestOrder = utils.permissions.get_highest_role_order(senderMember)
        assert(role.order < senderHighestOrder, "403|cannot delete role higher than or equal to your highest role")
    end

    -- Remove this role from all members
    for memberId, _ in pairs(helpers.role_to_member[roleId] or {}) do
        local member = utils.members.get(memberId)
        if member then
            member.roles[roleId] = nil
            utils.members.set(memberId, member)
        end
    end

    -- Clear the role to member mapping
    helpers.role_to_member[roleId] = nil

    -- Delete the role
    server.roles[roleId] = nil

    msg.reply({
        action = "delete-role-response",
        status = helpers.status.success,
    })
end

Handlers.add("delete-role", function(msg)
    utils.handle_run(delete_role, msg)
end)

local function assign_role(msg)
    local senderId = msg.from
    local userId = msg["user-id"]
    local roleId = msg["role-id"]

    assert(userId, "400|user-id is required")
    assert(roleId, "400|role-id is required")

    utils.info_log("ASSIGN_ROLE", "Assigning role", {
        assigner_id = senderId,
        user_id = userId,
        role_id = roleId
    })

    -- Get sender member to check permissions
    local senderMember = utils.members.get(senderId)
    assert(senderMember, "404|sender not found")

    -- Check permissions using standardized helper
    assert(utils.permissions.member_has_any(senderMember, {
        helpers.permissions.manage_roles,
        helpers.permissions.manage_server,
        helpers.permissions.administrator
    }), "403|insufficient permissions to assign roles")

    -- Get the member to assign role to
    local member = utils.members.get(userId)
    assert(member, "404|member not found")

    -- Get the role
    local role = utils.roles.get(roleId)
    assert(role, "404|role not found")

    -- Check role hierarchy: users can only assign roles below their highest role
    -- (unless they are the server owner or have administrator permission)
    if senderMember.id ~= owner and not utils.permissions.member_has(senderMember, helpers.permissions.administrator) then
        local senderHighestOrder = utils.permissions.get_highest_role_order(senderMember)
        assert(role.order < senderHighestOrder, "403|cannot assign role higher than or equal to your highest role")
    end

    -- Assign the role
    role_utils.assign(roleId, userId)

    msg.reply({
        action = "assign-role-response",
        status = helpers.status.success,
    })
end

Handlers.add("assign-role", function(msg)
    utils.handle_run(assign_role, msg)
end)

local function unassign_role(msg)
    local senderId = msg.from
    local userId = msg["user-id"]
    local roleId = msg["role-id"]

    assert(userId, "400|user-id is required")
    assert(roleId, "400|role-id is required")
    assert(roleId ~= "@", "400|cannot unassign everyone role")

    utils.info_log("UNASSIGN_ROLE", "Unassigning role", {
        unassigner_id = senderId,
        user_id = userId,
        role_id = roleId
    })

    -- Get sender member to check permissions
    local senderMember = utils.members.get(senderId)
    assert(senderMember, "404|sender not found")

    -- Check permissions using standardized helper
    assert(utils.permissions.member_has_any(senderMember, {
        helpers.permissions.manage_roles,
        helpers.permissions.manage_server,
        helpers.permissions.administrator
    }), "403|insufficient permissions to unassign roles")

    -- Get the member to unassign role from
    local member = utils.members.get(userId)
    assert(member, "404|member not found")

    -- Check if member has the role
    assert(member.roles[roleId], "400|member does not have this role")

    -- Check role hierarchy: users can only unassign roles below their highest role
    -- (unless they are the server owner or have administrator permission)
    if senderMember.id ~= owner and not utils.permissions.member_has(senderMember, helpers.permissions.administrator) then
        local role = utils.roles.get(roleId)
        if role then
            local senderHighestOrder = utils.permissions.get_highest_role_order(senderMember)
            assert(role.order < senderHighestOrder, "403|cannot unassign role higher than or equal to your highest role")
        end
    end

    -- Unassign the role
    role_utils.unassign(roleId, userId)

    msg.reply({
        action = "unassign-role-response",
        status = helpers.status.success,
    })
end

Handlers.add("unassign-role", function(msg)
    utils.handle_run(unassign_role, msg)
end)



--#endregion

--#region messages

local function send_message(msg)
    local senderId = msg.from
    local channelId = utils.var_or_nil(msg["channel-id"])
    local content = utils.var_or_nil(msg["content"])
    local attachments = msg["attachments"] or {}

    assert(channelId, "400|channel-id is required")
    assert(content or #attachments > 0, "400|content or attachments required")

    utils.info_log("SEND_MESSAGE", "Sending message", {
        sender_id = senderId,
        channel_id = channelId,
        has_attachments = #attachments > 0
    })

    -- Get sender member
    local senderMember = utils.members.get(senderId)
    assert(senderMember, "404|sender not found")

    -- Get the channel
    local channel = utils.channels.get(channelId)
    assert(channel, "404|channel not found")

    -- Log permission check details
    utils.log("send_message", "Checking send permissions", {
        sender_id = senderId,
        channel_id = channelId,
        channel_allow_messaging = channel.allow_messaging,
        member_roles = json.encode(senderMember.roles),
        is_owner = senderId == owner
    })

    -- Check if member can send messages in this channel
    local can_send = utils.channels.can_send(channel, senderMember)

    if not can_send then
        utils.log("send_message", "Permission denied", {
            sender_id = senderId,
            channel_id = channelId,
            reason = "insufficient permissions to send messages"
        })
    end

    assert(can_send,
        "403|insufficient permissions to send messages in this channel")

    -- Validate content
    if content then
        assert(type(content) == "string", "400|content must be a string")
        assert(#content > 0, "400|content must not be empty")
    end

    -- Validate attachments if present
    if attachments and #attachments > 0 then
        if type(attachments) ~= "table" then
            local success, decoded = pcall(json.decode, attachments)
            assert(success, "400|invalid attachments format")
            attachments = decoded
        end
        -- Check if member has attachment permissions
        if channel.allow_attachments == 0 then
            utils.log("send_message", "Checking attachment permissions", {
                sender_id = senderId,
                channel_id = channelId,
                channel_allow_attachments = channel.allow_attachments
            })

            local can_attach = utils.permissions.member_has_any(senderMember, {
                helpers.permissions.attachments,
                helpers.permissions.manage_channels,
                helpers.permissions.manage_server,
                helpers.permissions.administrator
            })

            if not can_attach then
                utils.log("send_message", "Attachment permission denied", {
                    sender_id = senderId,
                    channel_id = channelId,
                    reason = "insufficient permissions to send attachments"
                })
            end

            assert(can_attach, "403|insufficient permissions to send attachments in this channel")
        end

        assert(type(attachments) == "table", "400|attachments must be a table")
        assert(#attachments <= 10, "400|maximum 10 attachments allowed")

        for _, attachment in ipairs(attachments) do
            assert(type(attachment) == "string", "400|each attachment must be a string (arweave tx id)")
            assert(#attachment == 43, "400|each attachment must be a valid arweave tx id")
        end
    end

    local messageId = utils.get_id()
    local timestamp = os.time()

    local message = {
        id = messageId,
        channel_id = channelId,
        author_id = senderId,
        content = content or "",
        attachments = attachments,
        timestamp = timestamp,
        edited_timestamp = nil,
    }

    -- TODO
    -- Store message (in a real implementation, you'd want a proper message storage system)
    -- For now, we'll just acknowledge the message was sent

    utils.messages.set(messageId, message)

    -- Push event to subscribers
    push_event({
        event_type = helpers.events.message_sent,
        channel_id = channelId,
        message = message,
        timestamp = timestamp
    })

    utils.log("send_message", "Message sent successfully", {
        sender_id = senderId,
        channel_id = channelId,
        message_id = messageId,
        has_attachments = #attachments > 0,
        attachment_count = #attachments
    })

    msg.reply({
        action = "send-message-response",
        status = helpers.status.success,
        data = json.encode(message)
    })
end

Handlers.add("send-message", function(msg)
    utils.handle_run(send_message, msg)
end)

local function update_message(msg)
    local senderId = msg.from
    local messageId = utils.var_or_nil(msg["message-id"])
    local channelId = utils.var_or_nil(msg["channel-id"])
    local newContent = utils.var_or_nil(msg["content"])

    assert(messageId, "400|message-id is required")
    assert(channelId, "400|channel-id is required")
    assert(newContent, "400|content is required")

    utils.info_log("UPDATE_MESSAGE", "Updating message", {
        editor_id = senderId,
        message_id = messageId,
        channel_id = channelId
    })

    -- Get sender member
    local senderMember = utils.members.get(senderId)
    assert(senderMember, "404|sender not found")

    -- Get the channel
    local channel = utils.channels.get(channelId)
    assert(channel, "404|channel not found")

    -- Validate content
    assert(type(newContent) == "string", "400|content must be a string")
    assert(#newContent > 0, "400|content must not be empty")

    -- In a real implementation, you'd retrieve the original message and check:
    -- 1. Message exists
    -- 2. Sender is the author OR has manage_messages permission
    -- 3. Message is not too old to edit (e.g., within 24 hours)

    -- For now, we'll simulate message editing
    -- Assume the sender is either the author or has permissions (in real implementation, check actual message author)
    local canEdit = true -- This would be: (message.author_id == senderId) or utils.permissions.member_has_any(senderMember, {helpers.permissions.manage_messages, helpers.permissions.manage_server, helpers.permissions.administrator})
    assert(canEdit, "403|insufficient permissions to edit this message")

    local timestamp = os.time()
    local updatedMessage = {
        id = messageId,
        channel_id = channelId,
        author_id = senderId,         -- In real implementation, this would be the original author
        content = newContent,
        timestamp = timestamp - 3600, -- Simulate original timestamp (1 hour ago)
        edited_timestamp = timestamp,
    }

    utils.messages.set(messageId, updatedMessage)

    -- Push event to subscribers
    push_event({
        event_type = helpers.events.message_edited,
        channel_id = channelId,
        message = updatedMessage,
        timestamp = timestamp
    })

    msg.reply({
        action = "update-message-response",
        status = helpers.status.success,
        data = json.encode(updatedMessage)
    })
end

Handlers.add("update-message", function(msg)
    utils.handle_run(update_message, msg)
end)

local function delete_message(msg)
    local senderId = msg.from
    local messageId = utils.var_or_nil(msg["message-id"])
    local channelId = utils.var_or_nil(msg["channel-id"])

    assert(messageId, "400|message-id is required")
    assert(channelId, "400|channel-id is required")

    utils.info_log("DELETE_MESSAGE", "Deleting message", {
        deleter_id = senderId,
        message_id = messageId,
        channel_id = channelId
    })

    -- Get sender member
    local senderMember = utils.members.get(senderId)
    assert(senderMember, "404|sender not found")

    -- Get the channel
    local channel = utils.channels.get(channelId)
    assert(channel, "404|channel not found")

    -- In a real implementation, you'd retrieve the original message and check:
    -- 1. Message exists
    -- 2. Sender is the author OR has manage_messages permission

    -- For now, we'll simulate message deletion permissions
    -- Assume the sender is either the author or has permissions (in real implementation, check actual message author)
    local canDelete = true -- This would be: (message.author_id == senderId) or utils.permissions.member_has_any(senderMember, {helpers.permissions.manage_messages, helpers.permissions.manage_server, helpers.permissions.administrator})
    assert(canDelete, "403|insufficient permissions to delete this message")

    local timestamp = os.time()

    -- Delete the message from the messages table
    if messages[channelId] then
        messages[channelId][messageId] = nil
    end

    -- Push event to subscribers
    push_event({
        event_type = helpers.events.message_deleted,
        channel_id = channelId,
        message_id = messageId,
        deleted_by = senderId,
        timestamp = timestamp
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

local function subscribe(msg)
    local subscriberId = msg.from
    local events = msg["events"] or {}

    -- Get subscriber - must be a bot
    local subscriber = utils.members.get(subscriberId)
    assert(subscriber, "404|subscriber not found")
    assert(subscriber.is_bot, "403|only bots can subscribe to events")

    -- Validate events
    assert(type(events) == "table", "400|events must be a table")

    for _, event in ipairs(events) do
        assert(helpers.events[event] ~= nil, "400|invalid event: " .. tostring(event))
    end

    -- Initialize subscribers table if it doesn't exist
    if not server.subscribers then
        server.subscribers = {}
    end

    -- Store subscription
    server.subscribers[subscriberId] = {
        id = subscriberId,
        events = events,
        subscribed_at = os.time(),
        is_bot = true -- Always true since only bots can subscribe
    }

    utils.info_log("SUBSCRIBE", "Bot subscribed to events", {
        subscriber_id = subscriberId,
        event_count = #events
    })

    msg.reply({
        action = "subscribe-response",
        status = helpers.status.success,
        data = json.encode({
            subscriber_id = subscriberId,
            events = events
        })
    })
end

Handlers.add("subscribe", function(msg)
    utils.handle_run(subscribe, msg)
end)

local function unsubscribe(msg)
    local subscriberId = msg.from

    -- Get subscriber - must be a bot
    local subscriber = utils.members.get(subscriberId)
    assert(subscriber, "404|subscriber not found")
    assert(subscriber.is_bot, "403|only bots can manage event subscriptions")

    -- Initialize subscribers table if it doesn't exist
    if not server.subscribers then
        server.subscribers = {}
    end

    -- Check if subscriber exists
    assert(server.subscribers[subscriberId], "404|subscription not found")

    -- Remove subscription
    server.subscribers[subscriberId] = nil

    utils.info_log("UNSUBSCRIBE", "Bot unsubscribed from events", {
        subscriber_id = subscriberId
    })

    msg.reply({
        action = "unsubscribe-response",
        status = helpers.status.success,
    })
end

Handlers.add("unsubscribe", function(msg)
    utils.handle_run(unsubscribe, msg)
end)

--#endregion
