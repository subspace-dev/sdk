json = require("json")

----------------------------------------------------------------------------
--- VARIABLES

Subspace = "RmrKN2lAw5nu9eIQzXXi9DYT-95PqaLURnG9PRsoVuo"
Name = Name or "{NAME}"
Logo = Logo or "{LOGO}"
Description = Description or "{DESCRIPTION}"
Balances = Balances or { [Owner] = 1 }
TotalSupply = TotalSupply or 1
Denomination = Denomination or 10
Ticker = Ticker or "{TICKER}"
Version_ = Version_ or "1.0.0" -- Version is already a built in function

-- Server visibility policy:
-- - Public by default: anyone can join
-- - If private, join requests must be approved by server-side logic (not implemented here)
-- - Reads can still be permitted by external cache depending on consumer policy
PublicServer = PublicServer or true

-- in-memory storage only

----------------------------------------------------------------------------

-- legacy sqlite helpers removed

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
-- Bootstrap defaults so a fresh server starts usable
local categories_default = {
    ["1"] = {
        name = "Welcome",
        orderId = 1,
        allowMessaging = 1,
        allowAttachments = 1
    }
}
local channels_default = {
    ["1"] = {
        name = "General",
        orderId = 1,
        categoryId = "1",
    }
}
local roles_default = {
    ["1"] = {
        roleId = "1",
        name = "everyone",
        orderId = 1,
        color = "#99AAB5",
        permissions = 1 -- SEND_MESSAGES
    }
}

categories = categories or categories_default
channels = channels or channels_default
members = members or {}
roles = roles or roles_default
messages = messages or {}
events = events or {}
events_bak = events_bak or {}
bots = bots or {}
MemberCount = MemberCount or 0

-- Fast lookup: roleId => set(userId)
role_member_mapping = role_member_mapping or {} -- {roleId = {memberId=true, memberId=true, ...}}

-- Keep role_member_mapping in sync
local function AddUserToRoleMapping(roleId, userId)
    roleId = tostring(roleId)
    if not role_member_mapping[roleId] then
        role_member_mapping[roleId] = {}
    end
    role_member_mapping[roleId][userId] = true
end

local function RemoveUserFromRoleMapping(roleId, userId)
    roleId = tostring(roleId)
    local map = role_member_mapping[roleId]
    if map then
        map[userId] = nil
        if next(map) == nil then
            role_member_mapping[roleId] = nil
        end
    end
end

local function RemoveUserFromAllRoleMappings(userId, rolesList)
    if rolesList and type(rolesList) == "table" then
        for _, rid in ipairs(rolesList) do
            RemoveUserFromRoleMapping(rid, userId)
        end
        return
    end
    -- Fallback if roles list is unavailable
    for rid, map in pairs(role_member_mapping) do
        if map then
            map[userId] = nil
            if next(map) == nil then
                role_member_mapping[rid] = nil
            end
        end
    end
end

-- legacy sqlite schema removed

-- legacy default DB bootstrap comments removed
SubscribedBots = SubscribedBots or {}
-- example structure = {[bot-id]={[event-type]=true, [event-type]=true, ...}}

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

Events = { -- Readonly
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
}

-- if SQLRead("SELECT COUNT(*) as roleCount FROM roles")[1].roleCount == 0 then
--     SQLWrite("INSERT INTO roles (name, orderId, color, permissions) VALUES (?, ?, ?, ?)",
--         "everyone", 1, "#696969", Permissions.SEND_MESSAGES)
-- end

----------------------------------------------------------------------------
--- HELPERS

-- FOR FUTURE USE - DONOT REMOVE
-- function GetOriginalId(userId)
--     local originalId = nil
--     ao.send({
--         Action = "Get-Original-Id",
--         Tags = {
--             userId = userId
--         }
--     })
--     local res = Receive({ Action = "Get-Original-Id-Response", From = Profiles })
--     if res.Status == "200" then
--         originalId = res.Data.originalId
--     end
--     return originalId
-- end

function IsMemberBot(userId)
    return bots[userId] ~= nil
end

-- Return a copy of member with roles resolved to role objects (non-mutating)
function GetMember(userId)
    -- Return a copy with roles resolved to role objects; do not mutate stored state
    local stored = IsMemberBot(userId) and bots[userId] or members[userId]
    if not stored then return nil end
    local copy = {
        userId = stored.userId or userId,
        process = stored.process,
        nickname = stored.nickname,
        joinedAt = stored.joinedAt,
        roles = {},
        isBot = IsMemberBot(userId)
    }
    for _, roleId in ipairs(stored.roles or {}) do
        local role = GetRole(roleId)
        if role then table.insert(copy.roles, role) end
    end
    table.sort(copy.roles, function(a, b)
        return (a.orderId or 0) < (b.orderId or 0)
    end)
    return copy
end

function GetMemberPermissions(member)
    local permissions = 0
    for _, role in ipairs(member.roles) do
        permissions = permissions | role.permissions
    end
    return permissions
end

-- Sanitize member data before storage - keep only raw data
function SanitizeMemberData(memberData)
    if not memberData then return nil end

    local sanitized = {
        userId = memberData.userId,
        nickname = memberData.nickname,
        joinedAt = memberData.joinedAt,
        roles = {}
    }

    -- Ensure roles is an array of role IDs only (not role objects)
    if memberData.roles then
        for _, roleData in ipairs(memberData.roles) do
            if type(roleData) == "string" then
                -- Already a role ID string
                table.insert(sanitized.roles, roleData)
            elseif type(roleData) == "table" and roleData.roleId then
                -- Role object, extract the roleId
                table.insert(sanitized.roles, tostring(roleData.roleId))
            end
        end
    end

    -- For bots, also preserve additional bot-specific fields
    if memberData.process then
        sanitized.process = memberData.process
        sanitized.approved = memberData.approved
    end

    return sanitized
end

-- Helper function to get the appropriate table and update role mapping
function UpdateMemberTable(userId, memberData)
    -- Sanitize the member data before storing to ensure clean storage
    local sanitizedData = SanitizeMemberData(memberData)

    if IsMemberBot(userId) then
        bots[userId] = sanitizedData
    else
        members[userId] = sanitizedData
    end
end

-- Helper function to remove from appropriate table and role mapping
function RemoveMemberFromTables(userId)
    local memberData = IsMemberBot(userId) and bots[userId] or members[userId]
    local rolesList = memberData and memberData.roles

    -- Remove from role mapping
    RemoveUserFromAllRoleMappings(userId, rolesList)

    -- Remove from appropriate table
    if IsMemberBot(userId) then
        bots[userId] = nil
        SubscribedBots[userId] = nil -- Also remove from subscriptions if it's a bot
    else
        members[userId] = nil
    end
end

function RoleHasPermission(role, permission)
    if not role or not PermissionIsValid(role.permissions) or not PermissionIsValid(permission) then
        return false
    end

    return role.permissions & permission == permission
end

-- Resolve member's effective permissions across all roles.
-- ADMINISTRATOR or server Owner short-circuit to true.
function MemberHasPermission(member, permission)
    -- return true if the member has the permission, false otherwise
    -- analyze member.roles to find out what permissions the member has
    -- Administrator permission overrides all other permissions

    if not member or not PermissionIsValid(permission) then
        return false
    end

    -- if member is the server owner, return true
    if member.userId == Owner then
        return true
    end

    if not member.roles or #member.roles == 0 then
        return false
    end

    local totalPermissions = 0
    for _, role in ipairs(member.roles) do
        if role and PermissionIsValid(role.permissions) then
            -- Accumulate permissions from all roles
            totalPermissions = totalPermissions | role.permissions
            -- Administrator permission overrides all other permissions
            if RoleHasPermission(role, Permissions.ADMINISTRATOR) then
                return true
            end
        end
    end

    -- Check if the accumulated permissions include the requested permission
    return HasSpecificPermission(totalPermissions, permission)
end

-- Validate that a permissions bitfield contains only known bits
function PermissionIsValid(permission)
    -- validate: permission should be either one or many from Permissions table

    permission = tonumber(permission)

    -- Check if permission is a number and is positive
    if not permission or permission <= 0 then
        return false
    end

    -- Calculate the maximum valid permission value (all permissions combined)
    local maxValidPermission = 0
    for _, permValue in pairs(Permissions) do
        maxValidPermission = maxValidPermission | permValue
    end

    -- Check if the permission only contains valid permission bits
    -- If (permission & maxValidPermission) == permission, then all bits in permission
    -- are valid permission bits
    if (permission & maxValidPermission) ~= permission then
        return false
    end

    return true
end

-- Get all individual permissions from a combined permission value
-- Expand a bitfield into individual permission names
function GetPermissionNames(permissions)
    local permissionNames = {}

    if not PermissionIsValid(permissions) then
        return permissionNames
    end

    for permName, permValue in pairs(Permissions) do
        if permissions & permValue == permValue then
            table.insert(permissionNames, permName)
        end
    end

    return permissionNames
end

-- Combine multiple permission values safely
-- Combine multiple permission values safely
function CombinePermissions(...)
    local combined = 0
    local permissions = { ... }

    for _, perm in ipairs(permissions) do
        if PermissionIsValid(perm) then
            combined = combined | perm
        end
    end

    return combined
end

-- Check if a permission value has a specific permission
-- Check if a bitfield contains a specific permission
function HasSpecificPermission(permissions, specificPermission)
    if not PermissionIsValid(permissions) or not PermissionIsValid(specificPermission) then
        return false
    end

    return permissions & specificPermission == specificPermission
end

-- Get the default role for the server (roleId 1 is always the default role)
-- Retrieve the default role (roleId 1)
function GetDefaultRole()
    -- Prefer role with key "1"
    if roles["1"] then return roles["1"] end
    -- Fallback if stored under numeric key 1
    if roles[1] then return roles[1] end
    -- Fallback: scan for role where role.roleId == "1" or 1
    for _, r in pairs(roles) do
        if r and (tostring(r.roleId) == "1" or r.roleId == 1) then
            return r
        end
    end
    return nil
end

-- Ensure all members have the default role (roleId 1)
-- This function can be called to fix any inconsistencies
-- Ensure every member has the default role (repair tool)
function EnsureAllMembersHaveDefaultRole()
    local defaultRole = GetDefaultRole()
    if not defaultRole then
        print("==> No default role exists")
        return 0 -- No default role exists
    end

    local membersUpdated = 0

    -- Update regular members
    for memberId, member in pairs(members) do
        local hasDefault = false
        local existing = member.roles or {}
        for _, rid in ipairs(existing) do
            if tostring(rid) == "1" then
                hasDefault = true
                break
            end
        end
        if not hasDefault then
            local newRoles = { "1" }
            for _, rid in ipairs(existing) do table.insert(newRoles, rid) end
            member.roles = newRoles
            -- Update the sanitized version in storage
            UpdateMemberTable(memberId, member)
            -- reflect in mapping
            AddUserToRoleMapping("1", memberId)
            membersUpdated = membersUpdated + 1
        end
    end

    -- Update bots
    for botId, bot in pairs(bots) do
        if bot.approved then -- Only update approved bots
            local hasDefault = false
            local existing = bot.roles or {}
            for _, rid in ipairs(existing) do
                if tostring(rid) == "1" then
                    hasDefault = true
                    break
                end
            end
            if not hasDefault then
                local newRoles = { "1" }
                for _, rid in ipairs(existing) do table.insert(newRoles, rid) end
                bot.roles = newRoles
                -- Update the sanitized version in storage
                UpdateMemberTable(botId, bot)
                -- reflect in mapping
                AddUserToRoleMapping("1", botId)
                membersUpdated = membersUpdated + 1
            end
        end
    end

    return membersUpdated
end

-- Rebuild role_member_mapping based on current members' roles
-- Rebuild role_member_mapping from scratch
local function RebuildRoleMemberMapping()
    role_member_mapping = {}

    -- Add regular members
    for memberId, member in pairs(members) do
        local list = member and member.roles or {}
        if list then
            for _, rid in ipairs(list) do
                AddUserToRoleMapping(rid, memberId)
            end
        end
    end

    -- Add bots
    for botId, bot in pairs(bots) do
        if bot.approved then -- Only include approved bots
            local list = bot and bot.roles or {}
            if list then
                for _, rid in ipairs(list) do
                    AddUserToRoleMapping(rid, botId)
                end
            end
        end
    end
end

-- Check if a member can send messages in a specific channel
-- Policy for who can post in a given channel considering channel overrides
function CanMemberSendMessagesInChannel(member, channel)
    if not member or not channel then
        return false
    end

    -- Rule 1: If channel.allowMessaging is nil, fallback to permission check
    if channel.allowMessaging == nil then
        return MemberHasPermission(member, Permissions.SEND_MESSAGES)
    end

    -- Rule 2: If channel.allowMessaging is 1, allow everyone to message
    if channel.allowMessaging == 1 then
        return true
    end

    -- Rule 3: If channel.allowMessaging is 0, only allow members with manage channel permissions and above
    if channel.allowMessaging == 0 then
        return MemberHasPermission(member, Permissions.MANAGE_CHANNELS) or
            MemberHasPermission(member, Permissions.ADMINISTRATOR) or
            member.userId == Owner
    end

    -- Default fallback (shouldn't reach here normally)
    return false
end

-- Helper function to resequence channels within a specific category or uncategorized channels
-- Recompute orderId sequence for channels in a bucket (categoryId or uncategorized)
function ResequenceChannels(categoryId)
    -- Build a working list for the target bucket
    local list = {}
    for _, ch in pairs(channels) do
        if categoryId ~= nil then
            if ch and ch.categoryId == categoryId then table.insert(list, ch) end
        else
            if ch and ch.categoryId == nil then table.insert(list, ch) end
        end
    end

    table.sort(list, function(a, b)
        local ao = tonumber(a.orderId) or 0
        local bo = tonumber(b.orderId) or 0
        if ao == bo then
            local ai = tonumber(a.channelId) or 0
            local bi = tonumber(b.channelId) or 0
            return ai < bi
        end
        return ao < bo
    end)

    for i, ch in ipairs(list) do
        ch.orderId = i
        channels[tostring(ch.channelId)] = ch
    end

    return #list
end

-- Helper function to resequence all categories
-- Recompute orderId sequence for all categories
function ResequenceCategories()
    local list = {}
    for _, cat in pairs(categories) do
        if cat then table.insert(list, cat) end
    end
    table.sort(list, function(a, b)
        local ao = tonumber(a.orderId) or 0
        local bo = tonumber(b.orderId) or 0
        if ao == bo then
            local ai = tonumber(a.categoryId) or 0
            local bi = tonumber(b.categoryId) or 0
            return ai < bi
        end
        return ao < bo
    end)

    for i, cat in ipairs(list) do
        cat.orderId = i
        categories[tostring(cat.categoryId)] = cat
    end

    return #list
end

-- Helper function to resequence all roles
-- Normalize role ordering; keeps roleId stable
function ResequenceRoles()
    -- local roles = SQLRead("SELECT roleId FROM roles ORDER BY orderId ASC")

    -- Resequence starting from 1
    for k, role in pairs(roles) do
        if role then
            local derivedIndex = tonumber(role.orderId) or tonumber(k) or 0
            role.orderId = derivedIndex > 0 and derivedIndex or 1
            role.roleId = tostring(role.roleId or k)
        end
    end

    return #roles
end

-- Normalize ordering after category/channel mutations
function ResequenceCategoriesAndChannels()
    -- This should be called when a category or channel is created or deleted
    -- It will resequence the orderId of the categories and channels

    -- First resequence all categories
    ResequenceCategories()

    -- Then resequence channels within each category
    for _, category in pairs(categories) do
        if category then
            ResequenceChannels(category.categoryId)
        end
    end

    -- Finally resequence uncategorized channels
    ResequenceChannels(nil)
end

-- Ensure default ids for categories/channels at startup
-- Ensure categoryId/channelId/orderId are populated for defaults
local function EnsureEntityIds()
    local ci = 0
    for _, category in pairs(categories) do
        ci = ci + 1
        if category.categoryId == nil then category.categoryId = tostring(ci) end
        if category.orderId == nil then category.orderId = ci end
    end
    local chi = 0
    for _, channel in pairs(channels) do
        chi = chi + 1
        if channel.channelId == nil then channel.channelId = tostring(chi) end
        if channel.orderId == nil then channel.orderId = chi end
    end
end

-- Robust channel resolver that works with both string and numeric keys
-- Robust channel fetch by id (string key)
function GetChannel(channelId)
    if not channelId then return nil end
    local idStr = tostring(channelId)

    local channel = channels[idStr]
    return channel
end

-- Robust category resolver similar to GetChannel
-- Robust category fetch by id (string key)
function GetCategory(categoryId)
    if not categoryId then return nil end
    local idStr = tostring(categoryId)
    local category = categories[idStr]
    return category
end

-- Robust role fetch by id (string key)
function GetRole(roleId)
    if not roleId then return nil end
    local idStr = tostring(roleId)
    local role = roles[idStr]
    return role
end

-- Generate the next categoryId by scanning existing categories (works for map-style tables)
-- Compute next category id by scanning existing keys
local function GetNextCategoryId()
    local maxId = 0
    for key, cat in pairs(categories) do
        local candidate = nil
        if type(key) == "string" or type(key) == "number" then
            candidate = tonumber(key)
        end
        if not candidate and cat and cat.categoryId then
            candidate = tonumber(cat.categoryId)
        end
        if candidate and candidate > maxId then
            maxId = candidate
        end
    end
    return tostring(maxId + 1)
end

-- Generate the next channelId by scanning existing channels (works for map-style tables)
-- Compute next channel id by scanning existing keys
local function GetNextChannelId()
    local maxId = 0
    for key, ch in pairs(channels) do
        local candidate = nil
        if type(key) == "string" or type(key) == "number" then
            candidate = tonumber(key)
        end
        if not candidate and ch and ch.channelId then
            candidate = tonumber(ch.channelId)
        end
        if candidate and candidate > maxId then
            maxId = candidate
        end
    end
    return tostring(maxId + 1)
end

function GetFirstItem(table)
    local x, y
    for a, b in pairs(table) do
        x = a
        y = b
        break
    end
    return x, y
end

-- Push a snapshot of server state to Hyperbeam's patch cache for fast reads
function SyncProcessState()
    -- This function is used to take all the possible data and couple it into
    -- a single table which will be stored in Hyperbeams state for quick access.
    -- Everything must be in a JSON like structure
    -- This function should be called everytime after a change is made to the server



    -- loop over the events table and patch individual deleted items
    -- for _, event in ipairs(events) do
    --     if event.eventType == "DELETE" then
    --         if event.targetTable == "categories" then
    --             -- do this so that the entry doesnot become an array {}->[]
    --             -- local x, y = GetFirstItem(categories)

    --             local categoryId = event.targetKey
    --             Send({
    --                 Target = ao.id,
    --                 device = "patch@1.0",
    --                 cache = { server = { serverinfo = { categories = categories } } }
    --             })
    --         elseif event.targetTable == "channels" then
    --             -- do this so that the entry doesnot become an array {}->[]
    --             -- local x, y = GetFirstItem(channels)
    --             -- local z, w = GetFirstItem(messages)

    --             local channelId = event.targetKey
    --             Send({
    --                 Target = ao.id,
    --                 device = "patch@1.0",
    --                 cache = {
    --                     server = {
    --                         serverinfo = {
    --                             channels = channels
    --                         },
    --                         messages = { [channelId] = messages[channelId] }
    --                     }
    --                 }
    --             })
    --         elseif event.targetTable == "roles" then
    --             -- do this so that the entry doesnot become an array {}->[]
    --             -- local x, y = GetFirstItem(roles)

    --             local roleId = event.targetKey
    --             Send({
    --                 Target = ao.id,
    --                 device = "patch@1.0",
    --                 -- cache = { server = { serverinfo = { roles = { [roleId] = nil, [x] = y } } } }
    --                 cache = { server = { serverinfo = { roles = { [roleId] = roles[roleId] } } } }
    --             })
    --         elseif event.targetTable == "messages" then
    --             local channelId = event.baseKey
    --             local messageId = event.targetKey

    --             Send({
    --                 Target = ao.id,
    --                 device = "patch@1.0",
    --                 -- cache = { server = { messages = { [channelId] = { [messageId] = nil, [x] = y } } } }
    --                 cache = { server = { messages = { [channelId] = messages[channelId] } } }
    --             })
    --         end
    --     end
    -- end


    if #events > 0 then
        -- clear state before setting it again if there are events (usually delete events)
        Send({
            Target = ao.id,
            device = "patch@1.0",
            cache = { server = nil }
        })
    end

    Send({
        Target = ao.id,
        Action = "Sync"
    })
end

Handlers.add("Sync", function(msg)
    if msg.From ~= ao.id then return end

    EnsureEntityIds()

    Send({
        Target = ao.id,
        device = "patch@1.0",
        cache = {
            server = {
                serverinfo = {
                    name = Name,
                    logo = Logo,
                    description = Description,
                    owner = Owner,
                    publicServer = PublicServer,
                    version = Version_,
                    ticker = Ticker,
                    categories = categories,
                    channels = channels,
                    roles = roles,
                    memberCount = MemberCount,
                    bots = bots,
                    subscribedBots = SubscribedBots,
                },
                members = members,
                roleMemberMapping = role_member_mapping,
                messages = messages,
                events = events,
            }
        }
    })
    events_bak = events
    events     = {}
end)

-- make sure state is synced on startup
-- Ensure initial cache is populated on first boot
InitialSync = InitialSync or 'INCOMPLETE'
if InitialSync == 'INCOMPLETE' then
    SyncProcessState()
    InitialSync = 'COMPLETE'
end

----------------------------------------------------------------------------

-- Add a new member to the server (public servers only)
Handlers.add("Join-Server", function(msg)
    local userId = msg.From
    local joinedAt = msg.Timestamp or os.time()

    -- Check if server is public (if private, only allow if invited/approved)
    if ValidateCondition(not PublicServer, msg, {
            Status = "400",
            Data = json.encode({
                error = "Server is not public, ask the server admins to update the server settings"
            })
        }) then
        return
    end

    local member = GetMember(userId)
    if ValidateCondition(member, msg, {
            Status = "400",
            Data = json.encode({
                error = "User is already in the server"
            })
        }) then
        return
    end

    member = {
        userId = userId,
        nickname = nil,
        joinedAt = joinedAt,
        roles = { "1" } -- default role
    }
    UpdateMemberTable(userId, member)
    -- update role mapping for default role
    AddUserToRoleMapping("1", userId)
    -- Increment member counter
    MemberCount = MemberCount + 1

    msg.reply({
        Action = "Join-Server-Response",
        Status = "200",
    })
    SyncProcessState()

    -- Notify Subspace that user successfully joined (after state sync)
    ao.send({
        Target = Subspace,
        Action = "User-Joined-Server",
        Tags = {
            ["User-Id"] = userId,
            ["Server-Approved"] = "true"
        }
    })
end)

-- Remove a member from the server (cannot remove the owner)
Handlers.add("Leave-Server", function(msg)
    local userId = msg.From

    local member = GetMember(userId)
    if ValidateCondition(not member, msg, {
            Status = "400",
            Data = json.encode({
                error = "User is not in the server"
            })
        }) then
        return
    end

    -- Cannot leave if user is the server owner
    if ValidateCondition(userId == Owner, msg, {
            Status = "400",
            Data = json.encode({
                error = "Server owner cannot leave the server"
            })
        }) then
        return
    end

    -- Remove from appropriate table and role mapping
    RemoveMemberFromTables(userId)

    -- Decrement member counter
    if MemberCount > 0 then MemberCount = MemberCount - 1 end

    -- Add DELETE event for state patching
    table.insert(events, {
        eventType = "DELETE",
        targetTable = "members",
        targetKey = userId,
    })

    msg.reply({
        Action = "Leave-Server-Response",
        Status = "200",
    })
    SyncProcessState()
end)

-- Update server metadata and publicity. MANAGE_SERVER required.
Handlers.add("Update-Server", function(msg)
    local userId = msg.From
    local name = VarOrNil(msg.Tags.Name)
    local logo = VarOrNil(msg.Tags.Logo)
    local description = VarOrNil(msg.Tags.Description)
    local publicServer = VarOrNil(msg.Tags["Public-Server"])

    local member = GetMember(userId)
    if ValidateCondition(not member, msg, {
            Status = "400",
            Data = json.encode({
                error = "User not found"
            })
        }) then
        return
    end
    local hasPermission = MemberHasPermission(member, Permissions.MANAGE_SERVER)
    if ValidateCondition(not hasPermission, msg, {
            Status = "400",
            Data = json.encode({
                error = "User does not have permission to update the server"
            })
        }) then
        return
    end

    if name then
        Name = name
    end
    if logo then
        Logo = logo
    end
    if description then
        Description = description
    end

    if publicServer then
        PublicServer = publicServer == "true"
        ao.send({
            Action = "Update-Server",
            Tags = {
                ["Public-Server"] = tostring(PublicServer)
            }
        })
    end

    msg.reply({
        Action = "Update-Server-Response",
        Status = "200",
    })
    SyncProcessState()
end)

----------------------------------------------------------------------------
--- CATEGORIES

Handlers.add("Create-Category", function(msg)
    local userId = msg.From
    local name = VarOrNil(msg.Tags.Name)
    local allowMessaging = VarOrNil(msg.Tags["Allow-Messaging"]) or 1
    local allowAttachments = VarOrNil(msg.Tags["Allow-Attachments"]) or 1
    local orderId = VarOrNil(msg.Tags["Order-Id"])

    allowMessaging = tonumber(allowMessaging)
    allowAttachments = tonumber(allowAttachments)
    if orderId then orderId = tonumber(orderId) end

    local member = GetMember(userId)
    if ValidateCondition(not member, msg, {
            Status = "400",
            Data = json.encode({
                error = "User not found"
            })
        }) then
        return
    end
    local hasPermission = MemberHasPermission(member, Permissions.MANAGE_CHANNELS)
    if ValidateCondition(not hasPermission, msg, {
            Status = "400",
            Data = json.encode({
                error = "User does not have permission to create a category"
            })
        }) then
        return
    end

    -- Determine next categoryId using helper (categories is a map)
    local categoryId = GetNextCategoryId()
    local newCategory = {
        categoryId = categoryId,
        name = name,
        orderId = tonumber(orderId) or tonumber(categoryId),
        allowMessaging = allowMessaging,
        allowAttachments = allowAttachments
    }
    categories[categoryId] = newCategory

    msg.reply({
        Action = "Create-Category-Response",
        Status = "200"
    })
    SyncProcessState()
end)

Handlers.add("Update-Category", function(msg)
    local userId = msg.From
    local categoryId = VarOrNil(msg.Tags["Category-Id"])
    local name = VarOrNil(msg.Tags.Name)
    local allowMessaging = VarOrNil(msg.Tags["Allow-Messaging"])
    local allowAttachments = VarOrNil(msg.Tags["Allow-Attachments"])
    local orderId = VarOrNil(msg.Tags["Order-Id"])

    local member = GetMember(userId)
    if ValidateCondition(not member, msg, {
            Status = "400",
            Data = json.encode({
                error = "User not found"
            })
        }) then
        return
    end

    if allowMessaging then allowMessaging = tonumber(allowMessaging) end
    if allowAttachments then allowAttachments = tonumber(allowAttachments) end
    if orderId then orderId = tonumber(orderId) end

    local hasPermission = MemberHasPermission(member, Permissions.MANAGE_CHANNELS)
    if ValidateCondition(not hasPermission, msg, {
            Status = "400",
            Data = json.encode({
                error = "User does not have permission to update the category"
            })
        }) then
        return
    end

    local category, categoryStorageKey = GetCategory(categoryId)
    if ValidateCondition(not category, msg, {
            Status = "400",
            Data = json.encode({
                error = "Category not found"
            })
        }) then
        return
    end

    -- Get current values
    local current_order = category.orderId
    local new_name = name or category.name
    local new_allowMessaging = allowMessaging or category.allowMessaging
    local new_allowAttachments = allowAttachments or category.allowAttachments
    local new_orderId = orderId or current_order

    -- Handle ordering changes
    if orderId and orderId ~= current_order then
        if orderId < current_order then
            -- Moving up: shift other categories down
            for i, category in ipairs(categories) do
                if category.orderId >= orderId and category.orderId < current_order and category.categoryId ~= categoryId then
                    category.orderId = category.orderId + 1
                end
            end
        else
            -- Moving down: shift other categories up
            for i, category in ipairs(categories) do
                if category.orderId > current_order and category.orderId <= orderId and category.categoryId ~= categoryId then
                    category.orderId = category.orderId - 1
                end
            end
        end
    end

    -- Update the category
    category.name = new_name
    category.allowMessaging = new_allowMessaging
    category.allowAttachments = new_allowAttachments
    category.orderId = new_orderId

    if categoryStorageKey ~= nil then
        categories[categoryStorageKey] = category
    end

    -- Resequence to ensure clean ordering
    ResequenceCategories()

    msg.reply({
        Action = "Update-Category-Response",
        Status = "200",
    })
    SyncProcessState()
end)

Handlers.add("Delete-Category", function(msg)
    local userId = msg.From
    local categoryId = VarOrNil(msg.Tags["Category-Id"])

    local member = GetMember(userId)
    if ValidateCondition(not member, msg, {
            Status = "400",
            Data = json.encode({
                error = "User not found"
            })
        }) then
        return
    end

    local hasPermission = MemberHasPermission(member, Permissions.MANAGE_CHANNELS)
    if ValidateCondition(not hasPermission, msg, {
            Status = "400",
            Data = json.encode({
                error = "User does not have permission to delete the category"
            })
        }) then
        return
    end

    local category, categoryStorageKey = GetCategory(categoryId)
    if ValidateCondition(not category, msg, {
            Status = "400",
            Data = json.encode({
                error = "Category not found"
            })
        }) then
        return
    end

    -- Move all channels from this category to uncategorized
    for _, channel in ipairs(channels) do
        if channel.categoryId == categoryId then
            channel.categoryId = nil
        end
    end

    -- Delete the category
    if categoryStorageKey ~= nil then
        categories[categoryStorageKey] = nil
    end

    -- Resequence categories and affected channels
    ResequenceCategories()
    ResequenceChannels(nil) -- Resequence uncategorized channels

    table.insert(events, {
        eventType = "DELETE",
        targetTable = "categories",
        targetKey = categoryId,
    })

    msg.reply({
        Action = "Delete-Category-Response",
        Status = "200"
    })
    SyncProcessState()
end)

----------------------------------------------------------------------------
--- CHANNELS

Handlers.add("Create-Channel", function(msg)
    local userId = msg.From
    local name = VarOrNil(msg.Tags.Name)
    local allowMessaging = VarOrNil(msg.Tags["Allow-Messaging"]) or 1
    local allowAttachments = VarOrNil(msg.Tags["Allow-Attachments"]) or 1
    local categoryId = VarOrNil(msg.Tags["Category-Id"])
    local orderId = VarOrNil(msg.Tags["Order-Id"])

    allowMessaging = tonumber(allowMessaging)
    allowAttachments = tonumber(allowAttachments)
    -- categoryId must be string storage key
    if categoryId then categoryId = tostring(categoryId) end

    local member = GetMember(userId)
    if ValidateCondition(not member, msg, {
            Status = "400",
            Data = json.encode({
                error = "User not found"
            })
        }) then
        return
    end

    local hasPermission = MemberHasPermission(member, Permissions.MANAGE_CHANNELS)
    if ValidateCondition(not hasPermission, msg, {
            Status = "400",
            Data = json.encode({
                error = "User does not have permission to create a channel"
            })
        }) then
        return
    end

    local category = nil
    if categoryId then
        category = GetCategory(categoryId)
        if ValidateCondition(not category, msg, {
                Status = "400",
                Data = json.encode({
                    error = "Category not found"
                })
            }) then
            return
        end
    end

    -- Determine next channelId using helper (channels is a map)
    local channelId = GetNextChannelId()
    local newChannel = {
        channelId = channelId,
        name = name,
        orderId = tonumber(orderId) or tonumber(channelId),
        categoryId = categoryId,
        allowMessaging = allowMessaging or 1,
        allowAttachments = allowAttachments or 1
    }
    channels[channelId] = newChannel

    ResequenceCategoriesAndChannels()

    msg.reply({
        Action = "Create-Channel-Response",
        Status = "200",
    })
    SyncProcessState()
end)

Handlers.add("Update-Channel", function(msg)
    local userId = msg.From
    local channelId = VarOrNil(msg.Tags["Channel-Id"])
    local name = VarOrNil(msg.Tags.Name)
    local allowMessaging = VarOrNil(msg.Tags["Allow-Messaging"])
    local allowAttachments = VarOrNil(msg.Tags["Allow-Attachments"])
    local categoryIdRaw = msg.Tags["Category-Id"] -- Get raw value first
    local categoryId = VarOrNil(msg.Tags["Category-Id"])
    local orderId = VarOrNil(msg.Tags["Order-Id"])

    if allowMessaging then allowMessaging = tonumber(allowMessaging) end
    if allowAttachments then allowAttachments = tonumber(allowAttachments) end
    if orderId then orderId = tonumber(orderId) end

    local member = GetMember(userId)
    if ValidateCondition(not member, msg, {
            Status = "400",
            Data = json.encode({
                error = "User not found"
            })
        }) then
        return
    end

    local hasPermission = MemberHasPermission(member, Permissions.MANAGE_CHANNELS)
    if ValidateCondition(not hasPermission, msg, {
            Status = "400",
            Data = json.encode({
                error = "User does not have permission to update the channel"
            })
        }) then
        return
    end

    -- Channel id must be treated as string
    if channelId then channelId = tostring(channelId) end
    local channel, storageKey = GetChannel(channelId)
    if ValidateCondition(not channel, msg, {
            Status = "400",
            Data = json.encode({
                error = "Channel not found"
            })
        }) then
        return
    end

    -- Get current values
    local current_categoryId = channel.categoryId
    local current_order = channel.orderId
    local new_name = name or channel.name
    local new_allowMessaging = allowMessaging or channel.allowMessaging
    local new_allowAttachments = allowAttachments or channel.allowAttachments

    -- Determine target category
    local target_categoryId = current_categoryId
    if categoryId then
        target_categoryId = categoryId
    end

    -- Check if we're changing category
    local changing_category = (target_categoryId ~= current_categoryId)

    -- Determine new order
    local new_orderId = current_order
    if orderId then
        new_orderId = orderId
    elseif changing_category then
        -- When changing category without specifying order, place at end
        if target_categoryId then
            local max_order = 0
            for _, channel in ipairs(channels) do
                if channel.categoryId == target_categoryId then
                    max_order = math.max(max_order, channel.orderId)
                end
            end
            new_orderId = 1
            if max_order then
                new_orderId = max_order + 1
            end
        else
            local max_order = 0
            for _, channel in ipairs(channels) do
                if channel.categoryId == nil then
                    max_order = math.max(max_order, channel.orderId)
                end
            end
            new_orderId = 1
            if max_order then
                new_orderId = max_order + 1
            end
        end
    end

    -- Handle category change: remove from old category's ordering
    if changing_category then
        if current_categoryId then
            for _, channel in ipairs(channels) do
                if channel.categoryId == current_categoryId and channel.orderId > current_order then
                    channel.orderId = channel.orderId - 1
                end
            end
        else
            -- SQLWrite([[
            --     UPDATE channels
            --     SET orderId = orderId - 1
            --     WHERE categoryId IS NULL AND orderId > ?
            -- ]], current_order)
            for _, channel in ipairs(channels) do
                if channel.categoryId == nil and channel.orderId > current_order then
                    channel.orderId = channel.orderId - 1
                end
            end
        end

        -- Make room in target category
        if target_categoryId then
            for _, channel in ipairs(channels) do
                if channel.categoryId == target_categoryId and channel.orderId >= new_orderId then
                    channel.orderId = channel.orderId + 1
                end
            end
        else
            for _, channel in ipairs(channels) do
                if channel.categoryId == nil and channel.orderId >= new_orderId then
                    channel.orderId = channel.orderId + 1
                end
            end
        end
    elseif orderId and orderId ~= current_order then
        -- Handle ordering within same category
        if orderId < current_order then
            -- Moving up: shift others down
            if current_categoryId then
                for _, channel in ipairs(channels) do
                    if channel.categoryId == current_categoryId and channel.orderId >= orderId and channel.orderId < current_order and channel.channelId ~= channelId then
                        channel.orderId = channel.orderId + 1
                    end
                end
            else
                for _, channel in ipairs(channels) do
                    if channel.categoryId == nil and channel.orderId >= orderId and channel.orderId < current_order and channel.channelId ~= channelId then
                        channel.orderId = channel.orderId + 1
                    end
                end
            end
        else
            -- Moving down: shift others up
            if current_categoryId then
                for _, channel in ipairs(channels) do
                    if channel.categoryId == current_categoryId and channel.orderId > current_order and channel.orderId <= orderId and channel.channelId ~= channelId then
                        channel.orderId = channel.orderId - 1
                    end
                end
            else
                for _, channel in ipairs(channels) do
                    if channel.categoryId == nil and channel.orderId > current_order and channel.orderId <= orderId and channel.channelId ~= channelId then
                        channel.orderId = channel.orderId - 1
                    end
                end
            end
        end
    end

    channel.name = new_name
    channel.allowMessaging = new_allowMessaging
    channel.allowAttachments = new_allowAttachments
    channel.categoryId = target_categoryId
    channel.orderId = new_orderId

    channels[channelId] = channel


    ResequenceCategoriesAndChannels()

    msg.reply({
        Action = "Update-Channel-Response",
        Status = "200",
    })
    SyncProcessState()
end)

Handlers.add("Delete-Channel", function(msg)
    local userId = msg.From
    local channelId = VarOrNil(msg.Tags["Channel-Id"])

    local member = GetMember(userId)
    if ValidateCondition(not member, msg, {
            Status = "400",
            Data = json.encode({
                error = "User not found"
            })
        }) then
        return
    end

    local hasPermission = MemberHasPermission(member, Permissions.MANAGE_CHANNELS)
    if ValidateCondition(not hasPermission, msg, {
            Status = "400",
            Data = json.encode({
                error = "User does not have permission to delete the channel"
            })
        }) then
        return
    end

    if channelId then channelId = tonumber(channelId) end
    local channel = GetChannel(channelId)
    if ValidateCondition(not channel, msg, {
            Status = "400",
            Data = json.encode({
                error = "Channel not found"
            })
        }) then
        return
    end

    local channel_categoryId = channel.categoryId and tostring(channel.categoryId) or nil

    -- Delete all messages in the channel
    messages[tostring(channelId)] = nil

    -- Delete the channel
    channels[tostring(channelId)] = nil

    -- Resequence channels in the affected category
    ResequenceChannels(channel_categoryId)

    table.insert(events, {
        eventType = "DELETE",
        targetTable = "channels",
        targetKey = channelId,
    })

    msg.reply({
        Action = "Delete-Channel-Response",
        Status = "200",
    })
    SyncProcessState()
end)

----------------------------------------------------------------------------
--- ROLES

-- Generate the next roleId by scanning existing roles table keys and role objects
local function GetNextRoleId()
    local maxId = 0
    for key, role in pairs(roles) do
        local candidate = nil
        if type(key) == "string" or type(key) == "number" then
            candidate = tonumber(key)
        end
        if not candidate and role and role.roleId then
            candidate = tonumber(role.roleId)
        end
        if candidate and candidate > maxId then
            maxId = candidate
        end
    end
    return tostring(maxId + 1)
end

Handlers.add("Create-Role", function(msg)
    local userId = msg.From
    local name = VarOrNil(msg.Tags.Name) or "New Role"
    local color = VarOrNil(msg.Tags.Color) or "#696969"
    local permissions = VarOrNil(msg.Tags.Permissions) or 1
    local orderId = VarOrNil(msg.Tags["Order-Id"])

    if permissions then permissions = tonumber(permissions) end
    if orderId then orderId = tonumber(orderId) end

    -- Validate permissions
    if ValidateCondition(not PermissionIsValid(permissions), msg, {
            Status = "400",
            Data = json.encode({
                error = "Invalid permissions value"
            })
        }) then
        return
    end

    local member = GetMember(userId)
    if ValidateCondition(not member, msg, {
            Status = "400",
            Data = json.encode({
                error = "User not found"
            })
        }) then
        return
    end

    local hasPermission = MemberHasPermission(member, Permissions.MANAGE_ROLES)
    if ValidateCondition(not hasPermission, msg, {
            Status = "400",
            Data = json.encode({
                error = "User does not have permission to create roles"
            })
        }) then
        return
    end

    -- Determine order position
    local new_orderId
    if orderId then
        new_orderId = orderId
        -- Make room for new role
        for _, role in pairs(roles) do
            if role and role.orderId and role.orderId >= orderId then
                role.orderId = role.orderId + 1
            end
        end
    else
        -- Place at end
        local maxOrderId = 0
        for _, role in pairs(roles) do
            if role and role.orderId then
                maxOrderId = math.max(maxOrderId, role.orderId)
            end
        end
        new_orderId = 1
        if maxOrderId then
            new_orderId = maxOrderId + 1
        end
    end

    -- Insert new role with robust roleId generation (roles is a map/table)
    local roleId = GetNextRoleId()
    roles[roleId] = {
        roleId = roleId,
        name = name,
        color = color,
        permissions = permissions,
        orderId = new_orderId
    }

    -- initialize empty mapping bucket for the new role for consistency
    role_member_mapping[roleId] = role_member_mapping[roleId] or {}

    -- Resequence to ensure clean ordering
    ResequenceRoles()

    msg.reply({
        Action = "Create-Role-Response",
        Status = "200",
    })
    SyncProcessState()
end)

Handlers.add("Update-Role", function(msg)
    local userId = msg.From
    local roleId = VarOrNil(msg.Tags["Role-Id"])
    local name = VarOrNil(msg.Tags.Name)
    local color = VarOrNil(msg.Tags.Color)
    local permissions = VarOrNil(msg.Tags.Permissions)
    local orderId = VarOrNil(msg.Tags["Order-Id"])

    if permissions then permissions = tonumber(permissions) end
    if orderId then orderId = tonumber(orderId) end
    if roleId then roleId = tostring(roleId) end

    if ValidateCondition(not roleId, msg, {
            Status = "400",
            Data = json.encode({
                error = "Role ID is required"
            })
        }) then
        return
    end

    -- Validate permissions if provided
    if permissions and ValidateCondition(not PermissionIsValid(permissions), msg, {
            Status = "400",
            Data = json.encode({
                error = "Invalid permissions value"
            })
        }) then
        return
    end

    local member = GetMember(userId)
    if ValidateCondition(not member, msg, {
            Status = "400",
            Data = json.encode({
                error = "User not found"
            })
        }) then
        return
    end

    local hasPermission = MemberHasPermission(member, Permissions.MANAGE_ROLES)
    if ValidateCondition(not hasPermission, msg, {
            Status = "400",
            Data = json.encode({
                error = "User does not have permission to update roles"
            })
        }) then
        return
    end

    local role = GetRole(roleId)
    if ValidateCondition(not role, msg, {
            Status = "400",
            Data = json.encode({
                error = "Role not found"
            })
        }) then
        return
    end


    -- Get current values
    local current_order = role.orderId
    local new_name = name or role.name
    local new_color = color or role.color
    local new_permissions = permissions or role.permissions
    local new_orderId = orderId or current_order

    -- Handle ordering changes
    if orderId and orderId ~= current_order then
        if orderId < current_order then
            -- Moving up: shift other roles down
            for _, role in pairs(roles) do
                if role and role.orderId and role.orderId >= orderId and role.orderId < current_order and tostring(role.roleId) ~= tostring(roleId) then
                    role.orderId = role.orderId + 1
                end
            end
        else
            -- Moving down: shift other roles up
            for _, role in pairs(roles) do
                if role and role.orderId and role.orderId > current_order and role.orderId <= orderId and tostring(role.roleId) ~= tostring(roleId) then
                    role.orderId = role.orderId - 1
                end
            end
        end
    end

    -- Update the role
    role.name = new_name
    role.color = new_color
    role.permissions = new_permissions
    role.orderId = new_orderId

    -- Resequence to ensure clean ordering
    ResequenceRoles()

    msg.reply({
        Action = "Update-Role-Response",
        Status = "200",
    })
    SyncProcessState()
end)

Handlers.add("Delete-Role", function(msg)
    local userId = msg.From
    local roleId = VarOrNil(msg.Tags["Role-Id"])

    if roleId then roleId = tostring(roleId) end
    if ValidateCondition(not roleId, msg, {
            Status = "400",
            Data = json.encode({
                error = "Role ID is required"
            })
        }) then
        return
    end

    local member = GetMember(userId)
    if ValidateCondition(not member, msg, {
            Status = "400",
            Data = json.encode({
                error = "User not found"
            })
        }) then
        return
    end

    local hasPermission = MemberHasPermission(member, Permissions.MANAGE_ROLES)
    if ValidateCondition(not hasPermission, msg, {
            Status = "400",
            Data = json.encode({
                error = "User does not have permission to delete roles"
            })
        }) then
        return
    end

    local role = GetRole(roleId)
    if ValidateCondition(not role, msg, {
            Status = "400",
            Data = json.encode({
                error = "Role not found"
            })
        }) then
        return
    end

    -- Prevent deletion of default role (roleId 1)
    if ValidateCondition(tostring(roleId) == "1", msg, {
            Status = "400",
            Data = json.encode({
                error = "Cannot delete the default role"
            })
        }) then
        return
    end

    -- Remove this role from all members who have it (by value)
    local membersWithRole = role_member_mapping[roleId] or {}
    for memberId, _ in pairs(membersWithRole) do
        local member = members[memberId]
        if member then
            local newRoles = {}
            for _, rid in ipairs(member.roles) do
                if rid ~= roleId then table.insert(newRoles, rid) end
            end
            member.roles = newRoles
            -- Update the sanitized version in storage
            UpdateMemberTable(memberId, member)
        end
    end
    -- clear mapping for this role
    role_member_mapping[roleId] = nil

    -- for _, member in pairs(members) do
    --     if member.roles then
    --         local newRoles = {}
    --         for _, rid in ipairs(member.roles) do
    --             if rid ~= roleId then table.insert(newRoles, rid) end
    --         end
    --         member.roles = newRoles
    --     end
    -- end

    -- Delete the role
    roles[roleId] = nil

    -- Resequence roles to fill the gap
    ResequenceRoles()

    table.insert(events, {
        eventType = "DELETE",
        targetTable = "roles",
        targetKey = roleId,
    })

    msg.reply({
        Action = "Delete-Role-Response",
        Status = "200",
    })
    SyncProcessState()
end)

----------------------------------------------------------------------------
--- MEMBERS

-- Handlers.add("Get-Member", function(msg)
--     local userId = VarOrNil(msg.Tags.UserId) or msg.From

--     local member = GetMember(userId)
--     if ValidateCondition(not member, msg, {
--             Status = "400",
--             Data = json.encode({
--                 error = "User is not a member of this server"
--             })
--         }) then
--         return
--     end

--     msg.reply({
--         Action = "Get-Member-Response",
--         Member = json.encode(member)
--     })
-- end)

-- Handlers.add("Get-All-Members", function(msg)
--     local membersArranged = GetAllMembers()

--     msg.reply({
--         Action = "Get-Members-Response",
--         Status = "200",
--         Data = json.encode(membersArranged)
--     })
-- end)

Handlers.add("Update-Member", function(msg)
    local userId = msg.From
    local targetUserId = VarOrNil(msg.Tags["Target-User-Id"])
    local nickname = msg.Tags.Nickname -- Don't use VarOrNil here to allow empty strings

    -- Check if updating own profile or others
    local isUpdatingSelf = (targetUserId == userId or targetUserId == nil)
    local actualTargetId = targetUserId or userId

    local member = GetMember(userId)
    if ValidateCondition(not member, msg, {
            Status = "400",
            Data = json.encode({
                error = "You are not a member of this server"
            })
        }) then
        return
    end

    -- Check permissions for updating others
    if not isUpdatingSelf then
        local hasPermission = MemberHasPermission(member, Permissions.MANAGE_NICKNAMES)
        if ValidateCondition(not hasPermission, msg, {
                Status = "400",
                Data = json.encode({
                    error = "User does not have permission to manage nicknames"
                })
            }) then
            return
        end
    end

    local targetMember = GetMember(actualTargetId)
    if ValidateCondition(not targetMember, msg, {
            Status = "400",
            Data = json.encode({
                error = "Target user is not a member of this server"
            })
        }) then
        return
    end

    -- Update nickname if Nickname tag is present (supports clearing nicknames)
    if msg.Tags.Nickname then
        nickname = msg.Tags.Nickname

        -- Handle special sentinel value for clearing nicknames
        local nicknameValue
        if nickname == "__CLEAR_NICKNAME__" then
            nicknameValue = nil -- NULL in database clears the nickname
        else
            nicknameValue = nickname
        end

        targetMember.nickname = nicknameValue
    end

    -- Update the appropriate table (members or bots)
    UpdateMemberTable(actualTargetId, targetMember)

    msg.reply({
        Action = "Update-Member-Response",
        Status = "200",
    })
    SyncProcessState()
end)

Handlers.add("Kick-Member", function(msg)
    local userId = msg.From
    local targetUserId = VarOrNil(msg.Tags["Target-User-Id"])
    local reason = VarOrNil(msg.Tags.Reason)

    local member = GetMember(userId)
    if ValidateCondition(not member, msg, {
            Status = "400",
            Data = json.encode({
                error = "User not found"
            })
        }) then
        return
    end

    local hasPermission = MemberHasPermission(member, Permissions.KICK_MEMBERS)
    if ValidateCondition(not hasPermission, msg, {
            Status = "400",
            Data = json.encode({
                error = "User does not have permission to kick members"
            })
        }) then
        return
    end

    local targetMember = GetMember(targetUserId)
    if ValidateCondition(not targetMember, msg, {
            Status = "400",
            Data = json.encode({
                error = "Target user is not a member of this server"
            })
        }) then
        return
    end

    -- Cannot kick server owner
    if ValidateCondition(targetUserId == Owner, msg, {
            Status = "400",
            Data = json.encode({
                error = "Cannot kick the server owner"
            })
        }) then
        return
    end

    -- Remove from appropriate table and role mapping
    RemoveMemberFromTables(targetUserId)

    -- Decrement member counter for removed member
    if MemberCount > 0 then MemberCount = MemberCount - 1 end

    -- Notify subspace that user was kicked
    ao.send({
        Target = Subspace,
        Action = "User-Left-Server",
        Tags = {
            ["User-Id"] = targetUserId,
            ["Server-Id"] = ao.id,
            Reason = reason or "Kicked"
        }
    })

    -- If it's a bot, also notify the bot process
    if IsMemberBot(targetUserId) then
        ao.send({
            Target = targetUserId,
            Action = "Remove-Bot",
        })
    end

    -- Add DELETE event for state patching
    table.insert(events, {
        eventType = "DELETE",
        targetTable = IsMemberBot(targetUserId) and "bots" or "members",
        targetKey = targetUserId,
    })

    msg.reply({
        Action = "Kick-Member-Response",
        Status = "200",
    })

    SyncProcessState()
end)

Handlers.add("Ban-Member", function(msg)
    local userId = msg.From
    local targetUserId = VarOrNil(msg.Tags["Target-User-Id"])
    local reason = VarOrNil(msg.Tags.Reason)

    local member = GetMember(userId)
    if ValidateCondition(not member, msg, {
            Status = "400",
            Data = json.encode({
                error = "User not found"
            })
        }) then
        return
    end

    local hasPermission = MemberHasPermission(member, Permissions.BAN_MEMBERS)
    if ValidateCondition(not hasPermission, msg, {
            Status = "400",
            Data = json.encode({
                error = "User does not have permission to ban members"
            })
        }) then
        return
    end

    -- Cannot ban server owner
    if ValidateCondition(targetUserId == Owner, msg, {
            Status = "400",
            Data = json.encode({
                error = "Cannot ban the server owner"
            })
        }) then
        return
    end

    -- Check if user is already banned (if we had a bans table)
    -- For now, just kick them since we don't have a bans table in the schema

    local targetMember = GetMember(targetUserId)
    if ValidateCondition(not targetMember, msg, {
            Status = "400",
            Data = json.encode({
                error = "Target user is not a member of this server"
            })
        }) then
        return
    end

    -- Remove from appropriate table and role mapping
    RemoveMemberFromTables(targetUserId)

    -- Decrement member counter for removed member
    if MemberCount > 0 then MemberCount = MemberCount - 1 end

    -- Add DELETE event for state patching
    table.insert(events, {
        eventType = "DELETE",
        targetTable = IsMemberBot(targetUserId) and "bots" or "members",
        targetKey = targetUserId,
    })

    ao.send({
        Target = Subspace,
        Action = "User-Left-Server",
        Tags = {
            ["User-Id"] = targetUserId,
            ["Server-Id"] = ao.id,
            Reason = reason or "Banned"
        }
    })

    -- If it's a bot, also notify the bot process
    if IsMemberBot(targetUserId) then
        ao.send({
            Target = targetUserId,
            Action = "Remove-Bot",
        })
    end

    msg.reply({
        Action = "Ban-Member-Response",
        Status = "200",
    })
    SyncProcessState()
end)

Handlers.add("Unban-Member", function(msg)
    local userId = msg.From
    local targetUserId = VarOrNil(msg.Tags["Target-User-Id"])

    local member = GetMember(userId)
    if ValidateCondition(not member, msg, {
            Status = "400",
            Data = json.encode({
                error = "User not found"
            })
        }) then
        return
    end

    local hasPermission = MemberHasPermission(member, Permissions.BAN_MEMBERS)
    if ValidateCondition(not hasPermission, msg, {
            Status = "400",
            Data = json.encode({
                error = "User does not have permission to unban members"
            })
        }) then
        return
    end

    SyncProcessState()

    -- Since we don't have a proper bans table, this is a placeholder
    -- In a full implementation, this would remove the user from a bans table
    msg.reply({
        Action = "Unban-Member-Response",
        Status = "200",
        Data = json.encode({
            message = "User can now rejoin the server (ban system not fully implemented)"
        })
    })
end)

Handlers.add("Assign-Role", function(msg)
    local userId = msg.From
    local targetUserId = VarOrNil(msg.Tags["Target-User-Id"])
    local roleId = VarOrNil(msg.Tags["Role-Id"])

    if roleId then roleId = tostring(roleId) end
    if ValidateCondition(not roleId, msg, {
            Status = "400",
            Data = json.encode({
                error = "Role ID is required"
            })
        }) then
        return
    end

    local member = GetMember(userId)
    if ValidateCondition(not member, msg, {
            Status = "400",
            Data = json.encode({
                error = "User not found"
            })
        }) then
        return
    end

    local hasPermission = MemberHasPermission(member, Permissions.MANAGE_ROLES)
    if ValidateCondition(not hasPermission, msg, {
            Status = "400",
            Data = json.encode({
                error = "User does not have permission to assign roles"
            })
        }) then
        return
    end

    local targetMember = GetMember(targetUserId)
    if ValidateCondition(not targetMember, msg, {
            Status = "400",
            Data = json.encode({
                error = "Target user is not a member of this server"
            })
        }) then
        return
    end

    local role = GetRole(roleId)
    if ValidateCondition(not role, msg, {
            Status = "400",
            Data = json.encode({
                error = "Role not found"
            })
        }) then
        return
    end

    -- Check role hierarchy - different logic for self vs others
    local canManageRole = false
    local errorMessage = ""

    if userId == targetUserId then
        -- Self-management: use own role hierarchy logic
        canManageRole = CanUserManageOwnRole(userId, roleId)
        errorMessage =
        "You cannot assign this role to yourself. You can only assign roles lower in hierarchy than your highest role with MANAGE_ROLES permission, and you cannot assign roles that would conflict with your authority."
    else
        -- Managing others: use standard role management logic
        canManageRole = CanUserManageRole(userId, roleId)
        errorMessage =
        "You cannot assign this role. You can only assign roles lower in hierarchy than your highest role, or you need ADMINISTRATOR permission."
    end

    if ValidateCondition(not canManageRole, msg, {
            Status = "403",
            Data = json.encode({
                error = errorMessage
            })
        }) then
        return
    end

    -- Check if user can manage the target user's roles
    if ValidateCondition(not CanUserManageUserRoles(userId, targetUserId), msg, {
            Status = "403",
            Data = json.encode({
                error = "You cannot manage this user's roles. You can only manage users with lower role hierarchy than yours, or you need ADMINISTRATOR permission."
            })
        }) then
        return
    end

    -- Check if user already has this role (by value)
    local hasRole = false
    for _, rid in ipairs(targetMember.roles or {}) do
        if rid == roleId then
            hasRole = true
            break
        end
    end
    if ValidateCondition(hasRole, msg, {
            Status = "400",
            Data = json.encode({
                error = "User already has this role"
            })
        }) then
        return
    end

    -- Assign the role to the appropriate table
    local targetData = IsMemberBot(targetUserId) and bots[targetUserId] or members[targetUserId]
    targetData.roles = targetData.roles or {}
    table.insert(targetData.roles, roleId)

    -- Update the appropriate table
    UpdateMemberTable(targetUserId, targetData)

    -- Update mapping
    AddUserToRoleMapping(roleId, targetUserId)

    msg.reply({
        Action = "Assign-Role-Response",
        Status = "200",
    })
    SyncProcessState()
end)

Handlers.add("Unassign-Role", function(msg)
    local userId = msg.From
    local targetUserId = VarOrNil(msg.Tags["Target-User-Id"])
    local roleId = VarOrNil(msg.Tags["Role-Id"])

    if roleId then roleId = tostring(roleId) end

    local member = GetMember(userId)
    if ValidateCondition(not member, msg, {
            Status = "400",
            Data = json.encode({
                error = "User not found"
            })
        }) then
        return
    end

    local hasPermission = MemberHasPermission(member, Permissions.MANAGE_ROLES)
    if ValidateCondition(not hasPermission, msg, {
            Status = "400",
            Data = json.encode({
                error = "User does not have permission to unassign roles"
            })
        }) then
        return
    end

    local targetMember = GetMember(targetUserId)
    if ValidateCondition(not targetMember, msg, {
            Status = "400",
            Data = json.encode({
                error = "Target user is not a member of this server"
            })
        }) then
        return
    end

    local role = GetRole(roleId)
    if ValidateCondition(not role, msg, {
            Status = "400",
            Data = json.encode({
                error = "Role not found"
            })
        }) then
        return
    end

    -- Prevent removal of default role (roleId 1) from any member
    if ValidateCondition(tostring(roleId) == "1", msg, {
            Status = "400",
            Data = json.encode({
                error = "Cannot remove the default role from members. All members must have the default role."
            })
        }) then
        return
    end

    -- Check role hierarchy - different logic for self vs others
    local canManageRole = false
    local errorMessage = ""

    if userId == targetUserId then
        -- Self-management: use own role hierarchy logic
        canManageRole = CanUserManageOwnRole(userId, roleId)
        errorMessage =
        "You cannot remove this role from yourself. You can only remove roles lower in hierarchy than your highest role with MANAGE_ROLES permission, and you cannot remove your highest MANAGE_ROLES role."
    else
        -- Managing others: use standard role management logic
        canManageRole = CanUserManageRole(userId, roleId)
        errorMessage =
        "You cannot remove this role. You can only remove roles lower in hierarchy than your highest role, or you need ADMINISTRATOR permission."
    end

    if ValidateCondition(not canManageRole, msg, {
            Status = "403",
            Data = json.encode({
                error = errorMessage
            })
        }) then
        return
    end

    -- Check if user can manage the target user's roles
    if ValidateCondition(not CanUserManageUserRoles(userId, targetUserId), msg, {
            Status = "403",
            Data = json.encode({
                error = "You cannot manage this user's roles. You can only manage users with lower role hierarchy than yours, or you need ADMINISTRATOR permission."
            })
        }) then
        return
    end

    -- Check if user has this role (by value)
    local hasRole = false
    for _, rid in ipairs(targetMember.roles or {}) do
        if rid == roleId then
            hasRole = true
            break
        end
    end
    if ValidateCondition(not hasRole, msg, {
            Status = "200",
            Data = json.encode({
                error = "User does not have this role"
            })
        }) then
        -- return
    end

    -- Remove the role (by value) from the appropriate table
    local targetData = IsMemberBot(targetUserId) and bots[targetUserId] or members[targetUserId]
    local newRoles = {}
    for _, rid in ipairs(targetData.roles or {}) do
        if rid ~= roleId then table.insert(newRoles, rid) end
    end
    targetData.roles = newRoles

    -- Update the appropriate table
    UpdateMemberTable(targetUserId, targetData)

    -- Update mapping
    RemoveUserFromRoleMapping(roleId, targetUserId)

    -- table.insert(events, {
    --     eventType = "UNASSIGN",
    --     targetTable = "members",
    --     baseKey = targetUserId,
    --     targetKey = roleId,
    -- })

    msg.reply({
        Action = "Unassign-Role-Response",
        Status = "200",
    })
    SyncProcessState()
end)

----------------------------------------------------------------------------
--- MESSAGES


function ExtractMentions(content)
    local mentions = {}
    local seen = {}                                -- Prevent duplicates
    for userId in content:gmatch("<([^@]+)@user>") do
        if not seen[userId] and #userId == 43 then -- Validate ID length
            table.insert(mentions, userId)
            seen[userId] = true
        end
    end
    return mentions
end

Handlers.add("Send-Message", function(msg)
    local userId = msg.From
    local content = VarOrNil(msg.Data)
    local channelId = VarOrNil(msg.Tags["Channel-Id"] or msg["Channel-Id"])
    local attachments = VarOrNil(msg.Tags.Attachments) or "[]"
    local replyTo = VarOrNil(msg.Tags["Reply-To"])
    local timestamp = tonumber(msg.Timestamp or os.time())
    local messageTxId = msg.Id
    if channelId then channelId = tostring(channelId) end
    if ValidateCondition(not channelId, msg, {
            Status = "400",
            Data = json.encode({
                error = "Channel ID is required"
            })
        }) then
        return
    end
    if replyTo then replyTo = tostring(replyTo) end

    local member = GetMember(userId)
    if ValidateCondition(not member, msg, {
            Status = "400",
            Data = json.encode({
                error = "You are not a member of this server"
            })
        }) then
        return
    end

    local channel = GetChannel(channelId)
    if ValidateCondition(not channel, msg, {
            Status = "400",
            Data = json.encode({
                error = "Channel not found"
            })
        }) then
        return
    end

    local canSendMessages = CanMemberSendMessagesInChannel(member, channel)
    if ValidateCondition(not canSendMessages, msg, {
            Status = "400",
            Data = json.encode({
                error = "User does not have permission to send messages in this channel"
            })
        }) then
        return
    end

    -- Check if reply message exists (if replying)
    local channelKey = tostring(channelId)
    if replyTo then
        local replyBucket = messages[channelKey] or {}
        local replyMessage = replyBucket[replyTo]
        if ValidateCondition(not replyMessage, msg, {
                Status = "400",
                Data = json.encode({
                    error = "Reply target message not found"
                })
            }) then
            return
        end
    end

    -- Ensure channel message bucket exists
    messages[channelKey] = messages[channelKey] or {}
    -- Insert message
    messages[channelKey][messageTxId] = {
        content = content,
        authorId = userId,
        timestamp = timestamp,
        messageId = messageTxId,
        attachments = attachments,
        replyTo = replyTo
    }

    msg.reply({
        Action = "Send-Message-Response",
        Status = "200",
    })
    SyncProcessState()

    msg.forward(ao.id, {
        Action = "Push-To-Bots",
        Tags = {
            ["X-Id"] = tostring(msg.Id),
            ["X-Timestamp"] = tostring(timestamp),
            ["X-Channel-Id"] = tostring(channelId),
            ["X-Author-Id"] = tostring(userId),
            ["X-Attachments"] = tostring(attachments or ""),
            ["X-Reply-To"] = tostring(replyTo or ""),
            ["X-Event-Type"] = "on_message_send"
        }
    })
end)

Handlers.add("Edit-Message", function(msg)
    local userId = msg.From
    local messageId = VarOrNil(msg.Tags["Message-Id"])
    local channelId = VarOrNil(msg.Tags["Channel-Id"])
    local content = VarOrNil(msg.Data)

    local member = GetMember(userId)
    if ValidateCondition(not member, msg, {
            Status = "400",
            Data = json.encode({
                error = "You are not a member of this server"
            })
        }) then
        return
    end

    if ValidateCondition(not channelId, msg, {
            Status = "400",
            Data = json.encode({
                error = "Channel ID is required"
            })
        }) then
        return
    end

    if channelId then channelId = tostring(channelId) end

    -- Validate that the channel exists
    local channel = GetChannel(channelId)
    if ValidateCondition(not channel, msg, {
            Status = "400",
            Data = json.encode({
                error = "Channel not found"
            })
        }) then
        return
    end

    local messageBucket = messages[channelId] or {}
    local message = messageBucket[messageId]
    if ValidateCondition(not message, msg, {
            Status = "400",
            Data = json.encode({
                error = "Message not found"
            })
        }) then
        return
    end

    -- Check if user is the author or has manage messages permission
    local isAuthor = (message.authorId == userId)
    local hasManagePermission = MemberHasPermission(member, Permissions.MANAGE_MESSAGES)

    if ValidateCondition(not isAuthor and not hasManagePermission, msg, {
            Status = "400",
            Data = json.encode({
                error = "You can only edit your own messages"
            })
        }) then
        return
    end

    if ValidateCondition(not content, msg, {
            Status = "400",
            Data = json.encode({
                error = "Content cannot be empty when editing a message"
            })
        }) then
        return
    end

    -- Update message
    message.content = content
    message.edited = 1

    -- Forward message edit to all subscribed bots
    msg.forward(ao.id, {
        Action = "Push-To-Bots",
        Data = content,
        Tags = {
            ["X-Id"] = tostring(messageId),
            ["X-Timestamp"] = tostring(message.timestamp),
            ["X-Channel-Id"] = tostring(channelId),
            ["X-Author-Id"] = tostring(message.authorId),
            ["X-Attachments"] = tostring(message.attachments or ""),
            ["X-Reply-To"] = tostring(message.replyTo or ""),
            ["X-Event-Type"] = "on_message_edit",
            ["X-Editor-Id"] = tostring(userId)
        }
    })

    msg.reply({
        Action = "Edit-Message-Response",
        Status = "200",
    })
    SyncProcessState()
end)

Handlers.add("Delete-Message", function(msg)
    local userId = msg.From
    local messageId = VarOrNil(msg.Tags["Message-Id"])
    local channelId = VarOrNil(msg.Tags["Channel-Id"])

    local member = GetMember(userId)
    if ValidateCondition(not member, msg, {
            Status = "400",
            Data = json.encode({
                error = "You are not a member of this server"
            })
        }) then
        return
    end

    if ValidateCondition(not channelId, msg, {
            Status = "400",
            Data = json.encode({
                error = "Channel ID is required"
            })
        }) then
        return
    end

    if channelId then channelId = tostring(channelId) end

    -- Validate that the channel exists
    local channel = GetChannel(channelId)
    if ValidateCondition(not channel, msg, {
            Status = "400",
            Data = json.encode({
                error = "Channel not found"
            })
        }) then
        return
    end

    local messageBucket = messages[channelId] or {}
    local message = messageBucket[messageId]
    if ValidateCondition(not message, msg, {
            Status = "400",
            Data = json.encode({
                error = "Message not found"
            })
        }) then
        return
    end

    -- Check if user is the author, server owner, or has manage messages permission
    local isAuthor = (message.authorId == userId)
    local isOwner = (userId == Owner)
    local hasManagePermission = MemberHasPermission(member, Permissions.MANAGE_MESSAGES)

    if ValidateCondition(not isAuthor and not isOwner and not hasManagePermission, msg, {
            Status = "403",
            Data = json.encode({
                error = "You do not have permission to delete this message. You can only delete your own messages or need MANAGE_MESSAGES permission."
            })
        }) then
        return
    end

    -- Forward message deletion to all subscribed bots before deleting
    msg.forward(ao.id, {
        Action = "Push-To-Bots",
        Data = message.content or "",
        Tags = {
            ["X-Id"] = tostring(messageId),
            ["X-Timestamp"] = tostring(message.timestamp),
            ["X-Channel-Id"] = tostring(channelId),
            ["X-Author-Id"] = tostring(message.authorId),
            ["X-Attachments"] = tostring(message.attachments or ""),
            ["X-Reply-To"] = tostring(message.replyTo or ""),
            ["X-Event-Type"] = "on_message_delete",
            ["X-Deleter-Id"] = tostring(userId)
        }
    })

    -- Delete message
    if channelId then channelId = tostring(channelId) end
    if messages[channelId] then
        messages[channelId][messageId] = nil
    end

    table.insert(events, {
        eventType = "DELETE",
        targetTable = "messages",
        baseKey = channelId,
        targetKey = messageId,
    })

    msg.reply({
        Action = "Delete-Message-Response",
        Status = "200",
    })
    SyncProcessState()
end)

----------------------------------------------------------------------------

-- Validate and fix any invalid permissions in existing roles
function ValidateExistingRolePermissions()
    local fixedCount = 0

    for _, role in pairs(roles) do
        if not PermissionIsValid(role.permissions) then
            -- Fix invalid permissions by setting to basic SEND_MESSAGES permission
            local newPermissions = Permissions.SEND_MESSAGES
            role.permissions = newPermissions
            fixedCount = fixedCount + 1
            print("Fixed invalid permissions for role: " .. role.name .. " (ID: " .. role.roleId .. ")")
        end
    end

    if fixedCount > 0 then
        print("Fixed " .. fixedCount .. " roles with invalid permissions")
    end
end

-- Initialize database and validate permissions
ValidateExistingRolePermissions()

-- Clean up any contaminated member data (resolve role objects back to IDs)
function CleanupContaminatedMemberData()
    local cleanedCount = 0

    -- Clean members table
    for memberId, member in pairs(members) do
        local needsCleaning = false

        -- Check if roles contains objects instead of strings
        if member.roles then
            for _, roleData in ipairs(member.roles) do
                if type(roleData) == "table" then
                    needsCleaning = true
                    break
                end
            end
        end

        -- Check if isBot property exists (should not be in storage)
        if member.isBot ~= nil then
            needsCleaning = true
        end

        if needsCleaning then
            UpdateMemberTable(memberId, member)
            cleanedCount = cleanedCount + 1
        end
    end

    -- Clean bots table
    for botId, bot in pairs(bots) do
        local needsCleaning = false

        -- Check if roles contains objects instead of strings
        if bot.roles then
            for _, roleData in ipairs(bot.roles) do
                if type(roleData) == "table" then
                    needsCleaning = true
                    break
                end
            end
        end

        -- Check if isBot property exists (should not be in storage)
        if bot.isBot ~= nil then
            needsCleaning = true
        end

        if needsCleaning then
            UpdateMemberTable(botId, bot)
            cleanedCount = cleanedCount + 1
        end
    end

    if cleanedCount > 0 then
        print("Cleaned up " .. cleanedCount .. " contaminated member/bot records")
    end

    return cleanedCount
end

-- Clean up any existing contaminated data
CleanupContaminatedMemberData()

-- Ensure all existing members have the default role
EnsureAllMembersHaveDefaultRole()
-- Ensure mapping is consistent at startup
RebuildRoleMemberMapping()

-- Initialize MemberCount once at startup based on current state
local function InitializeMemberCount()
    local count = 0
    -- Count regular members
    for _ in pairs(members) do count = count + 1 end
    -- Count approved bots
    for _, bot in pairs(bots) do
        if bot.approved then
            count = count + 1
        end
    end
    MemberCount = count
end
InitializeMemberCount()

----------------------------------------------------------------------------

-- Get the user's highest role (lowest orderId = highest hierarchy)
function GetUserHighestRole(userId)
    local member = GetMember(userId)
    if not member or not member.roles or #member.roles == 0 then
        return nil
    end

    local highestRole = nil
    local lowestOrderId = nil

    for _, role in ipairs(member.roles) do
        if role then
            if lowestOrderId == nil or (role.orderId or math.huge) < lowestOrderId then
                lowestOrderId = role.orderId or math.huge
                highestRole = role
            end
        end
    end

    return highestRole
end

-- Check if a user can manage a specific role based on hierarchy
function CanUserManageRole(userId, targetRoleId)
    local member = GetMember(userId)
    if not member then
        return false
    end

    -- check if role exists
    local targetRole = roles[targetRoleId]
    if not targetRole then
        return false
    end

    -- Check if user has ADMINISTRATOR permission (can manage any role)
    if MemberHasPermission(member, Permissions.ADMINISTRATOR) then
        return true
    end

    -- Check if user has MANAGE_ROLES permission
    if not MemberHasPermission(member, Permissions.MANAGE_ROLES) then
        return false
    end

    -- Get user's highest role
    local userHighestRole = GetUserHighestRole(userId)
    if not userHighestRole then
        return false -- User has no roles, cannot manage any roles
    end

    -- User can only manage roles with higher orderId (lower hierarchy) than their highest role
    return targetRole.orderId > userHighestRole.orderId
end

-- Get the user's highest role that has MANAGE_ROLES permission
function GetUserHighestManageRolesRole(userId)
    local member = GetMember(userId)
    if not member or not member.roles or #member.roles == 0 then
        return nil
    end

    local highestManageRole = nil
    local lowestOrderId = nil

    for _, role in ipairs(member.roles) do
        if role and HasSpecificPermission(role.permissions, Permissions.MANAGE_ROLES) then
            if lowestOrderId == nil or (role.orderId or math.huge) < lowestOrderId then
                lowestOrderId = role.orderId or math.huge
                highestManageRole = role
            end
        end
    end

    return highestManageRole
end

-- Check if a user can manage their own specific role
function CanUserManageOwnRole(userId, roleId)
    local member = GetMember(userId)
    if not member then
        return false
    end

    -- Check if user has ADMINISTRATOR permission (can manage any of their own roles)
    if MemberHasPermission(member, Permissions.ADMINISTRATOR) then
        return true
    end

    -- Get the target role
    local targetRole = roles[roleId]
    if not targetRole then
        return false
    end

    -- Get user's highest role with MANAGE_ROLES permission
    local userHighestManageRole = GetUserHighestManageRolesRole(userId)
    if not userHighestManageRole then
        return false -- User has no MANAGE_ROLES permission
    end

    -- User cannot remove their highest MANAGE_ROLES role (would lose permission)
    if targetRole.roleId == userHighestManageRole.roleId then
        return false
    end

    -- User can only manage roles with higher orderId (lower hierarchy) than their highest MANAGE_ROLES role
    return targetRole.orderId > userHighestManageRole.orderId
end

-- Check if a user can manage another user's roles
function CanUserManageUserRoles(managerId, targetUserId)
    local managerMember = GetMember(managerId)
    if not managerMember then
        return false
    end

    -- Check if manager has ADMINISTRATOR permission (can manage anyone)
    if MemberHasPermission(managerMember, Permissions.ADMINISTRATOR) then
        return true
    end

    -- Check if manager has MANAGE_ROLES permission
    if not MemberHasPermission(managerMember, Permissions.MANAGE_ROLES) then
        return false
    end

    -- If managing own roles, use different logic
    if managerId == targetUserId then
        return true -- Self-management allowed, but specific role checks apply in CanUserManageOwnRole
    end

    -- Get both users' highest roles
    local managerHighestRole = GetUserHighestRole(managerId)
    local targetHighestRole = GetUserHighestRole(targetUserId)

    if not managerHighestRole then
        return false -- Manager has no roles, cannot manage anyone
    end

    -- If target has no roles, manager can manage them
    if not targetHighestRole then
        return true
    end

    -- Manager can only manage users whose highest role is lower in hierarchy
    return managerHighestRole.orderId < targetHighestRole.orderId
end

----------------------------------------------------------------------------
-- BOTS

Handlers.add("Add-Bot", function(msg)
    assert(msg.From == Subspace, "You are not allowed to add bots")

    local userId = msg["X-Origin"]

    local botProcess = VarOrNil(msg.Tags["Bot-Process"])
    local serverId = VarOrNil(msg.Tags["Server-Id"])

    if ValidateCondition(not botProcess, msg, {
            Status = "400",
            Data = json.encode({
                error = "Bot-Process is required"
            })
        }) then
        return
    end

    if ValidateCondition(not serverId, msg, {
            Status = "400",
            Data = json.encode({
                error = "Server-Id is required"
            })
        }) then
        return
    end

    -- verify serverId is the if of this server
    if ValidateCondition(serverId ~= ao.id, msg, {
            Status = "400",
            Data = json.encode({
                error = "Server-Id is not the id of this server"
            })
        }) then
        return
    end

    -- member exists and has permissions to add bots
    local member = GetMember(userId)
    if ValidateCondition(not member, msg, {
            Status = "400",
            Data = json.encode({
                error = "User is not a member of this server"
            })
        }) then
        return
    end

    local hasPermission = MemberHasPermission(member, Permissions.MANAGE_BOTS)
    if ValidateCondition(not hasPermission, msg, {
            Status = "400",
            Data = json.encode({
                error = "User does not have permission to add bots"
            })
        }) then
        return
    end

    -- check if bot already exists
    local bot = bots[botProcess]
    if ValidateCondition(bot and bot.approved, msg, {
            Status = "400",
            Data = json.encode({
                error = "Bot already exists in server"
            })
        }) then
        return
    end

    -- add bot to server
    bots[botProcess] = {
        approved = false,
        process = botProcess
    }

    -- msg.reply({
    --     Action = "Add-Bot-Response",
    --     Status = "200",
    --     Tags = {
    --         ["Bot-Process"] = botProcess,
    --         ["Status"] = "200"
    --     }
    -- })
    Send({
        Target = Subspace,
        Action = "Add-Bot-Response",
        Status = "200",
        Tags = {
            ["Bot-Process"] = botProcess,
            ["Server-Id"] = serverId
        }
    })
    SyncProcessState()
end)

Handlers.add("Approve-Add-Bot", function(msg)
    assert(msg.From == Subspace, "You are not allowed to approve bots")

    local botProcess = VarOrNil(msg.Tags["Bot-Process"])

    local bot = bots[botProcess]
    if ValidateCondition(not bot, msg, {
            Status = "400",
            Data = json.encode({
                error = "Bot not found"
            })
        }) then
        return
    end

    -- A bot is like a regular member, but with a special process id, and stored in a different table
    -- This is because bots are not real users, and we don't want to store them in the members table
    bot.approved = true
    bot.nickname = ""       -- blank nickname, show default bot name
    bot.roles = { "1" }     -- default role id
    bot.joinedAt = msg.Timestamp
    bot.userId = botProcess -- Set userId for consistency with member structure
    UpdateMemberTable(botProcess, bot)

    -- Update role mapping for default role
    AddUserToRoleMapping("1", botProcess)

    -- Increment member counter
    MemberCount = MemberCount + 1

    msg.reply({
        Action = "Approve-Add-Bot-Response",
        Status = "200",
        Tags = {
            ["Bot-Process"] = botProcess
        }
    })
    SyncProcessState()
end)

Handlers.add("Subscribe", function(msg)
    local botProcess = msg.From
    local events = VarOrNil(msg.Tags.Events)

    -- verify if bot is approved
    local bot = bots[botProcess]
    if ValidateCondition(not bot or not bot.approved, msg, {
            Status = "400",
            Data = json.encode({
                error = "Bot is either not approved or doesnot exist in the server"
            })
        }) then
        return
    end

    -- Parse events if provided
    local subscribedEvents = {}
    if events then
        local success, parsedEvents = pcall(json.decode, events)
        if success and type(parsedEvents) == "table" then
            -- Validate that all event keys are valid
            for eventKey, value in pairs(parsedEvents) do
                if not Events[eventKey] then
                    msg.reply({
                        Action = "Subscribe-Response",
                        Status = "400",
                        Data = json.encode({
                            error = "Invalid event key: " .. eventKey
                        })
                    })
                    return
                end
                -- Validate that the value is a boolean
                if type(value) ~= "boolean" then
                    msg.reply({
                        Action = "Subscribe-Response",
                        Status = "400",
                        Data = json.encode({
                            error = "Invalid event value for " .. eventKey .. ": expected boolean, got " .. type(value)
                        })
                    })
                    return
                end
            end
            subscribedEvents = parsedEvents
        else
            -- If JSON parsing failed, return an error
            msg.reply({
                Action = "Subscribe-Response",
                Status = "400",
                Data = json.encode({
                    error = "Invalid JSON format for events"
                })
            })
            return
        end
    end

    -- add bot to subsriptions list with their subscribed events
    SubscribedBots[botProcess] = subscribedEvents

    msg.reply({
        Action = "Subscribe-Response",
        Status = "200",
        Tags = {
            Events = json.encode(subscribedEvents)
        }
    })
    SyncProcessState()
end)

Handlers.add("Remove-Bot", function(msg)
    local userId = msg.From
    local botProcess = VarOrNil(msg.Tags["Bot-Process"])

    -- verify if user has permission to remove bots
    local member = GetMember(userId)
    if ValidateCondition(not member, msg, {
            Status = "400",
            Data = json.encode({
                error = "User is not a member of this server"
            })
        }) then
        return
    end

    local hasPermission = MemberHasPermission(member, Permissions.MANAGE_BOTS)
    if ValidateCondition(not hasPermission, msg, {
            Status = "400",
            Data = json.encode({
                error = "User does not have permission to remove bots"
            })
        }) then
        return
    end

    local bot = bots[botProcess]
    if ValidateCondition(not bot, msg, {
            Status = "400",
            Data = json.encode({
                error = "Bot not found"
            })
        }) then
        return
    end

    -- Remove bot from server using helper function
    RemoveMemberFromTables(botProcess)

    -- Decrement member counter
    if MemberCount > 0 then MemberCount = MemberCount - 1 end

    -- Add DELETE event for state patching
    table.insert(events, {
        eventType = "DELETE",
        targetTable = "bots",
        targetKey = botProcess,
    })

    -- tell subspace and bot process that bot has been removed
    ao.send({
        Target = botProcess,
        Action = "Remove-Bot",
    })
    ao.send({
        Target = Subspace,
        Action = "Remove-Bot",
        Tags = {
            ["Bot-Process"] = botProcess
        }
    })

    msg.reply({
        Action = "Remove-Bot-Response",
        Status = "200",
    })
    SyncProcessState()
end)


-- self message to trigger a seperate flow to send data to bots instead of the main message handler
Handlers.add("Push-To-Bots", function(msg)
    if not msg.From == ao.id then return end

    print("Pushing msg " .. msg.Tags["X-Id"] .. " to bots")

    -- Forward message to all subscribed bots
    for botProcess, subscribedEvents in pairs(SubscribedBots) do
        if subscribedEvents and type(subscribedEvents) == "table" then
            local channelId = msg.Tags["X-Channel-Id"]
            local userId = msg.Tags["X-Author-Id"]
            local attachments = msg.Tags["X-Attachments"]
            local replyTo = msg.Tags["X-Reply-To"]
            local eventType = msg.Tags["X-Event-Type"]
            local timestamp = msg.Tags["X-Timestamp"]
            local messageId = msg.Tags["X-Id"]
            local editorId = msg.Tags["X-Editor-Id"]
            local deleterId = msg.Tags["X-Deleter-Id"]
            local serverId = ao.id

            -- Check if bot is subscribed to this event type
            if not subscribedEvents[eventType] then
                return
            end

            local member = GetMember(userId)
            local channel = GetChannel(channelId)
            if not channel then goto continue end
            if not member then goto continue end

            local channelName = channel.name or ""
            local serverName = Name or ""
            local authorNickname = member.nickname or ""
            local fromBot = IsMemberBot(userId) and "true" or "false"
            local permissions = GetMemberPermissions(member)
            local content = msg.Data

            -- Build Discord-like structured event data
            local eventData = {
                eventType = eventType,
                server = {
                    id = serverId,
                    name = serverName,
                    logo = Logo,
                    owner = Owner,
                    description = Description
                },
                channel = {
                    id = channelId,
                    name = channelName,
                },
                author = {
                    id = userId,
                    nickname = authorNickname or "",
                    isBot = fromBot == "true",
                    roles = member.roles,
                    joinedAt = member.joinedAt,
                    permissions = permissions,
                },
                message = {
                    id = messageId,
                    content = content or "",
                    timestamp = timestamp,
                    attachments = attachments and json.decode(attachments) or {},
                    replyTo = replyTo,
                    mentions = {}
                }
            }

            msg.forward(botProcess, {
                Action = "Event",
                Data = json.encode(eventData),
                Tags = {
                    ["Event-Type"] = tostring(eventType)
                }
            })

            ::continue::
        end
    end
end)
