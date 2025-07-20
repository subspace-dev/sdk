sqlite3 = require("lsqlite3")
json = require("json")

----------------------------------------------------------------------------
--- VARIABLES

Subspace = "VDkbyJj9o67AtTaYregitjDgcrLWmrxMvKICbWR-kBA"
Name = Name or "{NAME}"
Logo = Logo or "{LOGO}"
Balances = Balances or { [Owner] = 1 }
TotalSupply = TotalSupply or 1
Denomination = Denomination or 10
Ticker = Ticker or "{TICKER}"
Version = Version or "1.0.0"

-- By default servers are public and anyone can join
-- If private, new users cannot join
-- Get requests can still be done and non members can still see and fetch messages
PublicServer = PublicServer or true

db = db or sqlite3.open_memory()

----------------------------------------------------------------------------

-- easily read from the database
function SQLRead(query, ...)
    local m = {}
    local _ = 1
    local stmt = db:prepare(query)
    if stmt then
        local bind_res = stmt:bind_values(...)
        assert(bind_res, "❌[bind error] " .. db:errmsg())
        for row in stmt:nrows() do
            -- table.insert(m, row)
            m[_] = row
            _ = _ + 1
        end
        stmt:finalize()
    end
    return m
end

-- easily write to the database
function SQLWrite(query, ...)
    local stmt = db:prepare(query)
    if stmt then
        local bind_res = stmt:bind_values(...)
        assert(bind_res, "❌[bind error] " .. db:errmsg())
        local step = stmt:step()
        assert(step == sqlite3.DONE, "❌[write error] " .. db:errmsg())
        stmt:finalize()
    end
    return db:changes()
end

function VarOrNil(var)
    return var ~= "" and var or nil
end

-- Validate that a condition is false, send error response if true
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

db:exec([[
    CREATE TABLE IF NOT EXISTS categories (
        categoryId INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        orderId INTEGER NOT NULL DEFAULT 1,
        allowMessaging INTEGER NOT NULL DEFAULT 1,
        allowAttachments INTEGER NOT NULL DEFAULT 1
    );

    CREATE TABLE IF NOT EXISTS channels (
        channelId INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        orderId INTEGER NOT NULL DEFAULT 1,
        categoryId INTEGER,
        allowMessaging INTEGER DEFAULT NULL,
        allowAttachments INTEGER DEFAULT NULL,
        FOREIGN KEY (categoryId) REFERENCES categories(categoryId) ON DELETE SET NULL
    );

    CREATE TABLE IF NOT EXISTS members (
        userId TEXT PRIMARY KEY,
        nickname TEXT
    );

    CREATE TABLE IF NOT EXISTS memberRoles (
        userId TEXT,
        roleId INTEGER,
        FOREIGN KEY (userId) REFERENCES members(userId) ON DELETE CASCADE,
        FOREIGN KEY (roleId) REFERENCES roles(roleId) ON DELETE CASCADE
    );

    CREATE TABLE IF NOT EXISTS messages (
        messageId INTEGER PRIMARY KEY AUTOINCREMENT,
        content TEXT NOT NULL,
        channelId INTEGER,
        authorId TEXT,
        messageTxId TEXT UNIQUE,
        timestamp INTEGER NOT NULL DEFAULT (strftime('%s', 'now')),
        edited INTEGER NOT NULL DEFAULT 0,
        attachments TEXT DEFAULT "[]",
        replyTo INTEGER,
        FOREIGN KEY (channelId) REFERENCES channels(channelId) ON DELETE CASCADE,
        FOREIGN KEY (authorId) REFERENCES members(userId) ON DELETE SET NULL,
        FOREIGN KEY (replyTo) REFERENCES messages(messageId) ON DELETE SET NULL
    );

    CREATE TABLE IF NOT EXISTS roles (
        roleId INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        orderId INTEGER NOT NULL DEFAULT 1,
        color TEXT NOT NULL,
        permissions INTEGER NOT NULL DEFAULT 0
    );

    CREATE TABLE IF NOT EXISTS events (
        eventId INTEGER PRIMARY KEY AUTOINCREMENT,
        eventType TEXT, CHECK (eventType IN ("DELETE_MESSAGE", "EDIT_MESSAGE")),
        messageId INTEGER,
        FOREIGN KEY (messageId) REFERENCES messages(messageId)
    );

    CREATE TABLE IF NOT EXISTS bots (
        botProcess TEXT PRIMARY KEY,
        botApproved INTEGER NOT NULL DEFAULT 0
    );
]])

-- create default category and channel if the tables are empty
-- Welcome
-- - General with Welcome as parent category
if SQLRead("SELECT COUNT(*) as catCount FROM categories")[1].catCount == 0 then
    SQLWrite("INSERT INTO categories (name, orderId) VALUES (?, ?)", "Welcome", 1)
end

if SQLRead("SELECT COUNT(*) as chanCount FROM channels")[1].chanCount == 0 then
    SQLWrite("INSERT INTO channels (name, orderId, categoryId) VALUES (?, ?, ?)",
        "General", 1, 1)
end

-- create default role if no roles exist
-- The first role created will have roleId 1 and be the default role
-- DEFAULT ROLE POLICY:
-- - roleId 1 is always the default role that ALL members must have
-- - It cannot be deleted from the server
-- - It cannot be removed from any member
-- - It starts with SEND_MESSAGES permission by default, but can be updated by role managers
-- - All new members automatically get this role when joining
SubscribedBots = {}

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

if SQLRead("SELECT COUNT(*) as roleCount FROM roles")[1].roleCount == 0 then
    SQLWrite("INSERT INTO roles (name, orderId, color, permissions) VALUES (?, ?, ?, ?)",
        "everyone", 1, "#696969", Permissions.SEND_MESSAGES)
end

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

function GetMember(userId)
    local member = SQLRead("SELECT * FROM members WHERE userId = ?", userId)[1]
    if member then
        member.roles = {}
        local roles = SQLRead(
            "SELECT mr.roleId FROM memberRoles mr JOIN roles r ON mr.roleId = r.roleId WHERE mr.userId = ? ORDER BY r.orderId ASC",
            userId)
        for _, role in ipairs(roles) do
            table.insert(member.roles, role.roleId)
        end
    end
    return member
end

function RoleHasPermission(role, permission)
    if not role or not PermissionIsValid(role.permissions) or not PermissionIsValid(permission) then
        return false
    end

    return role.permissions & permission == permission
end

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
    for _, roleId in ipairs(member.roles) do
        local role = SQLRead("SELECT * FROM roles WHERE roleId = ?", roleId)[1]
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
function HasSpecificPermission(permissions, specificPermission)
    if not PermissionIsValid(permissions) or not PermissionIsValid(specificPermission) then
        return false
    end

    return permissions & specificPermission == specificPermission
end

-- Get the default role for the server (roleId 1 is always the default role)
function GetDefaultRole()
    return SQLRead("SELECT * FROM roles WHERE roleId = 1")[1]
end

-- Ensure all members have the default role (roleId 1)
-- This function can be called to fix any inconsistencies
function EnsureAllMembersHaveDefaultRole()
    local defaultRole = GetDefaultRole()
    if not defaultRole then
        return 0 -- No default role exists
    end

    local members = SQLRead("SELECT userId FROM members")
    local membersUpdated = 0

    for _, member in ipairs(members) do
        -- Check if member already has default role
        local hasDefaultRole = SQLRead("SELECT * FROM memberRoles WHERE userId = ? AND roleId = 1", member.userId)
        if #hasDefaultRole == 0 then
            -- Assign default role to member
            local rows = SQLWrite("INSERT INTO memberRoles (userId, roleId) VALUES (?, 1)", member.userId)
            if rows == 1 then
                membersUpdated = membersUpdated + 1
            end
        end
    end

    return membersUpdated
end

-- Check if a member can send messages in a specific channel
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
function ResequenceChannels(categoryId)
    local channels

    if categoryId ~= nil then
        channels = SQLRead([[
            SELECT channelId FROM channels
            WHERE categoryId = ?
            ORDER BY orderId ASC
        ]], categoryId)
    else
        channels = SQLRead([[
            SELECT channelId FROM channels
            WHERE categoryId IS NULL
            ORDER BY orderId ASC
        ]])
    end

    -- Resequence starting from 1
    for i, channel in ipairs(channels) do
        if categoryId ~= nil then
            SQLWrite([[
                UPDATE channels SET orderId = ?
                WHERE channelId = ? AND categoryId = ?
            ]], i, channel.channelId, categoryId)
        else
            SQLWrite([[
                UPDATE channels SET orderId = ?
                WHERE channelId = ? AND categoryId IS NULL
            ]], i, channel.channelId)
        end
    end

    return #channels
end

-- Helper function to resequence all categories
function ResequenceCategories()
    local categories = SQLRead("SELECT categoryId FROM categories ORDER BY orderId ASC")

    -- Resequence starting from 1
    for i, category in ipairs(categories) do
        SQLWrite("UPDATE categories SET orderId = ? WHERE categoryId = ?", i, category.categoryId)
    end

    return #categories
end

-- Helper function to resequence all roles
function ResequenceRoles()
    local roles = SQLRead("SELECT roleId FROM roles ORDER BY orderId ASC")

    -- Resequence starting from 1
    for i, role in ipairs(roles) do
        SQLWrite("UPDATE roles SET orderId = ? WHERE roleId = ?", i, role.roleId)
    end

    return #roles
end

function ResequenceCategoriesAndChannels()
    -- This should be called when a category or channel is created or deleted
    -- It will resequence the orderId of the categories and channels

    -- First resequence all categories
    ResequenceCategories()

    -- Then resequence channels within each category
    local categories = SQLRead("SELECT categoryId FROM categories")
    for _, category in ipairs(categories) do
        ResequenceChannels(category.categoryId)
    end

    -- Finally resequence uncategorized channels
    ResequenceChannels(nil)
end

----------------------------------------------------------------------------

Handlers.add("Info", function(msg)
    local categories = SQLRead("SELECT * FROM categories ORDER BY orderId ASC")
    local channels = SQLRead("SELECT * FROM channels ORDER BY orderId ASC")
    local roles = SQLRead("SELECT * FROM roles ORDER BY orderId ASC")

    local memberCount = SQLRead("SELECT COUNT(*) as memberCount FROM members")[1].memberCount

    msg.reply({
        Action = "Info-Response",
        Name = Name,
        Logo = Logo,
        Owner_ = Owner,
        Categories = json.encode(categories),
        Channels = json.encode(channels),
        Roles = json.encode(roles),
        PublicServer = tostring(PublicServer),
        MemberCount = tostring(memberCount),
        Version = tostring(Version),
        -- IGNORE REST
        Denomination = tostring(Denomination),
        Ticker = Ticker,
        Status = "200"
    })
end)

-- handlers to make this token compatible
Handlers.add("Balance", function(msg)
    local bal = 0

    if msg.Tags.Recipient then
        bal = Balances[msg.Tags.Recipient] or 0
    else
        bal = Balances[msg.From] or 0
    end

    msg.reply({
        Balance = bal,
        Ticker = Ticker,
        Account = msg.Tags.Recipient or msg.From,
        Data = bal
    })
end)

Handlers.add("Balances", function(msg)
    msg.reply({ Data = json.encode(Balances) })
end)

Handlers.add("Total-Supply", function(msg)
    msg.reply({
        Action = 'Total-Supply',
        Data = tostring(TotalSupply),
        Ticker = Ticker
    })
end)

---------------------

Handlers.add("Join-Server", function(msg)
    local userId = msg.From

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

    -- Begin transaction
    db:exec("BEGIN TRANSACTION")
    local success = true

    -- Add user to server members
    local rows = SQLWrite("INSERT INTO members (userId) VALUES (?)", userId)
    if rows ~= 1 then
        success = false
    end

    -- Assign default role to new member
    local defaultRole = GetDefaultRole()
    if success and defaultRole then
        local roleRows = SQLWrite("INSERT INTO memberRoles (userId, roleId) VALUES (?, ?)", userId, defaultRole.roleId)
        if roleRows ~= 1 then
            success = false
        end
    end

    if success then
        db:exec("COMMIT")

        -- Notify subspace that user has joined
        ao.send({
            Target = Subspace,
            Action = "User-Joined-Server",
            Tags = {
                UserId = userId,
                ServerId = ao.id
            }
        })

        msg.reply({
            Action = "Join-Server-Response",
            Status = "200",
        })
    else
        db:exec("ROLLBACK")
        msg.reply({
            Action = "Join-Server-Response",
            Status = "500",
            Data = json.encode({
                error = "Failed to join server"
            })
        })
    end
end)

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

    -- Begin transaction
    db:exec("BEGIN TRANSACTION")
    local success = true

    -- Remove member roles
    local rolesDeleted = SQLWrite("DELETE FROM memberRoles WHERE userId = ?", userId)

    -- Remove member
    local rows = SQLWrite("DELETE FROM members WHERE userId = ?", userId)
    if rows ~= 1 then
        success = false
    end

    if success then
        db:exec("COMMIT")

        -- Notify subspace that user has left
        ao.send({
            Target = Subspace,
            Action = "User-Left-Server",
            Tags = {
                UserId = userId,
                ServerId = ao.id
            }
        })

        msg.reply({
            Action = "Leave-Server-Response",
            Status = "200",
        })
    else
        db:exec("ROLLBACK")
        msg.reply({
            Action = "Leave-Server-Response",
            Status = "500",
            Data = json.encode({
                error = "Failed to leave server"
            })
        })
    end
end)

Handlers.add("Update-Server", function(msg)
    local userId = msg.From
    local name = VarOrNil(msg.Tags.Name)
    local logo = VarOrNil(msg.Tags.Logo)
    local publicServer = VarOrNil(msg.Tags.PublicServer)

    local hasPermission = MemberHasPermission(GetMember(userId), Permissions.MANAGE_SERVER)
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

    if publicServer then
        PublicServer = publicServer == "true"
        ao.send({
            Action = "Update-Server",
            Tags = {
                PublicServer = tostring(PublicServer)
            }
        })
    end

    msg.reply({
        Action = "Update-Server-Response",
        Status = "200",
    })
end)

----------------------------------------------------------------------------
--- CATEGORIES

Handlers.add("Create-Category", function(msg)
    local userId = msg.From
    local name = VarOrNil(msg.Tags.Name)
    local allowMessaging = VarOrNil(msg.Tags.AllowMessaging) or 1
    local allowAttachments = VarOrNil(msg.Tags.AllowAttachments) or 1
    local orderId = VarOrNil(msg.Tags.OrderId)

    allowMessaging = tonumber(allowMessaging)
    allowAttachments = tonumber(allowAttachments)
    if orderId then orderId = tonumber(orderId) end

    local hasPermission = MemberHasPermission(GetMember(userId), Permissions.MANAGE_CHANNELS)
    if ValidateCondition(not hasPermission, msg, {
            Status = "400",
            Data = json.encode({
                error = "User does not have permission to create a category"
            })
        }) then
        return
    end

    -- Begin transaction
    db:exec("BEGIN TRANSACTION")
    local success = true

    -- Determine order position
    local new_orderId
    if orderId then
        new_orderId = orderId
        -- Make room for new category
        SQLWrite([[
            UPDATE categories SET orderId = orderId + 1
            WHERE orderId >= ?
        ]], orderId)
    else
        -- Place at end
        local maxOrderId = SQLRead("SELECT MAX(orderId) as maxOrder FROM categories")[1]
        new_orderId = 1
        if maxOrderId and maxOrderId.maxOrder then
            new_orderId = maxOrderId.maxOrder + 1
        end
    end

    -- Insert new category
    local rows = SQLWrite([[
        INSERT INTO categories (name, orderId, allowMessaging, allowAttachments)
        VALUES (?, ?, ?, ?)
    ]], name, new_orderId, allowMessaging, allowAttachments)

    if rows ~= 1 then
        success = false
    end

    -- Resequence to ensure clean ordering
    if success then
        ResequenceCategories()
    end

    if success then
        db:exec("COMMIT")
        msg.reply({
            Action = "Create-Category-Response",
            Status = "200",
        })
    else
        db:exec("ROLLBACK")
        msg.reply({
            Action = "Create-Category-Response",
            Status = "500",
            Data = json.encode({
                error = "Failed to create category"
            })
        })
    end
end)

Handlers.add("Update-Category", function(msg)
    local userId = msg.From
    local categoryId = VarOrNil(msg.Tags.CategoryId)
    local name = VarOrNil(msg.Tags.Name)
    local allowMessaging = VarOrNil(msg.Tags.AllowMessaging)
    local allowAttachments = VarOrNil(msg.Tags.AllowAttachments)
    local orderId = VarOrNil(msg.Tags.OrderId)

    if allowMessaging then allowMessaging = tonumber(allowMessaging) end
    if allowAttachments then allowAttachments = tonumber(allowAttachments) end
    if orderId then orderId = tonumber(orderId) end

    local hasPermission = MemberHasPermission(GetMember(userId), Permissions.MANAGE_CHANNELS)
    if ValidateCondition(not hasPermission, msg, {
            Status = "400",
            Data = json.encode({
                error = "User does not have permission to update the category"
            })
        }) then
        return
    end

    local category = SQLRead("SELECT * FROM categories WHERE categoryId = ?", categoryId)[1]
    if ValidateCondition(not category, msg, {
            Status = "400",
            Data = json.encode({
                error = "Category not found"
            })
        }) then
        return
    end

    -- Begin transaction for atomic updates
    db:exec("BEGIN TRANSACTION")
    local success = true

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
            SQLWrite([[
                UPDATE categories
                SET orderId = orderId + 1
                WHERE orderId >= ? AND orderId < ? AND categoryId != ?
            ]], orderId, current_order, categoryId)
        else
            -- Moving down: shift other categories up
            SQLWrite([[
                UPDATE categories
                SET orderId = orderId - 1
                WHERE orderId > ? AND orderId <= ? AND categoryId != ?
            ]], current_order, orderId, categoryId)
        end
    end

    -- Update the category
    local rows = SQLWrite([[
        UPDATE categories
        SET name = ?, allowMessaging = ?, allowAttachments = ?, orderId = ?
        WHERE categoryId = ?
    ]], new_name, new_allowMessaging, new_allowAttachments, new_orderId, categoryId)

    if rows ~= 1 then
        success = false
    end

    -- Resequence to ensure clean ordering
    if success then
        ResequenceCategories()
    end

    if success then
        db:exec("COMMIT")
        msg.reply({
            Action = "Update-Category-Response",
            Status = "200",
        })
    else
        db:exec("ROLLBACK")
        msg.reply({
            Action = "Update-Category-Response",
            Status = "500",
            Data = json.encode({
                error = "Failed to update category"
            })
        })
    end
end)

Handlers.add("Delete-Category", function(msg)
    local userId = msg.From
    local categoryId = VarOrNil(msg.Tags.CategoryId)

    local hasPermission = MemberHasPermission(GetMember(userId), Permissions.MANAGE_CHANNELS)
    if ValidateCondition(not hasPermission, msg, {
            Status = "400",
            Data = json.encode({
                error = "User does not have permission to delete the category"
            })
        }) then
        return
    end

    local category = SQLRead("SELECT * FROM categories WHERE categoryId = ?", categoryId)[1]
    if ValidateCondition(not category, msg, {
            Status = "400",
            Data = json.encode({
                error = "Category not found"
            })
        }) then
        return
    end

    -- Begin transaction
    db:exec("BEGIN TRANSACTION")
    local success = true

    -- Move all channels from this category to uncategorized
    local channels_updated = SQLWrite("UPDATE channels SET categoryId = NULL WHERE categoryId = ?", categoryId)

    -- Delete the category
    local rows = SQLWrite("DELETE FROM categories WHERE categoryId = ?", categoryId)

    if rows ~= 1 then
        success = false
    end

    -- Resequence categories and affected channels
    if success then
        ResequenceCategories()
        ResequenceChannels(nil) -- Resequence uncategorized channels
    end

    if success then
        db:exec("COMMIT")
        msg.reply({
            Action = "Delete-Category-Response",
            Status = "200",
            Data = json.encode({
                channelsMovedToUncategorized = channels_updated
            })
        })
    else
        db:exec("ROLLBACK")
        msg.reply({
            Action = "Delete-Category-Response",
            Status = "500",
            Data = json.encode({
                error = "Failed to delete category"
            })
        })
    end
end)

----------------------------------------------------------------------------
--- CHANNELS

Handlers.add("Create-Channel", function(msg)
    local userId = msg.From
    local name = VarOrNil(msg.Tags.Name)
    local allowMessaging = VarOrNil(msg.Tags.AllowMessaging) or 1
    local allowAttachments = VarOrNil(msg.Tags.AllowAttachments) or 1
    local categoryId = VarOrNil(msg.Tags.CategoryId)
    local orderId = VarOrNil(msg.Tags.OrderId)

    allowMessaging = tonumber(allowMessaging)
    allowAttachments = tonumber(allowAttachments)
    if categoryId then categoryId = tonumber(categoryId) end
    if orderId then orderId = tonumber(orderId) end

    local hasPermission = MemberHasPermission(GetMember(userId), Permissions.MANAGE_CHANNELS)
    if ValidateCondition(not hasPermission, msg, {
            Status = "400",
            Data = json.encode({
                error = "User does not have permission to create a channel"
            })
        }) then
        return
    end

    -- Begin transaction
    db:exec("BEGIN TRANSACTION")
    local success = true

    -- Determine order position
    local new_orderId
    if orderId then
        new_orderId = orderId
        -- Make room for new channel in the specified category
        if categoryId then
            SQLWrite([[
                UPDATE channels SET orderId = orderId + 1
                WHERE categoryId = ? AND orderId >= ?
            ]], categoryId, orderId)
        else
            SQLWrite([[
                UPDATE channels SET orderId = orderId + 1
                WHERE categoryId IS NULL AND orderId >= ?
            ]], orderId)
        end
    else
        -- Place at end of category/uncategorized
        if categoryId then
            local maxOrderId = SQLRead([[
                SELECT MAX(orderId) as maxOrder FROM channels
                WHERE categoryId = ?
            ]], categoryId)[1]
            new_orderId = 1
            if maxOrderId and maxOrderId.maxOrder then
                new_orderId = maxOrderId.maxOrder + 1
            end
        else
            local maxOrderId = SQLRead([[
                SELECT MAX(orderId) as maxOrder FROM channels
                WHERE categoryId IS NULL
            ]])[1]
            new_orderId = 1
            if maxOrderId and maxOrderId.maxOrder then
                new_orderId = maxOrderId.maxOrder + 1
            end
        end
    end

    -- Insert new channel
    local rows = SQLWrite([[
        INSERT INTO channels (name, orderId, categoryId, allowMessaging, allowAttachments)
        VALUES (?, ?, ?, ?, ?)
    ]], name, new_orderId, categoryId, allowMessaging, allowAttachments)

    if rows ~= 1 then
        success = false
    end

    -- Resequence to ensure clean ordering
    if success then
        ResequenceChannels(categoryId)
    end

    if success then
        db:exec("COMMIT")
        msg.reply({
            Action = "Create-Channel-Response",
            Status = "200",
        })
    else
        db:exec("ROLLBACK")
        msg.reply({
            Action = "Create-Channel-Response",
            Status = "500",
            Data = json.encode({
                error = "Failed to create channel"
            })
        })
    end
end)

Handlers.add("Update-Channel", function(msg)
    local userId = msg.From
    local channelId = VarOrNil(msg.Tags.ChannelId)
    local name = VarOrNil(msg.Tags.Name)
    local allowMessaging = VarOrNil(msg.Tags.AllowMessaging)
    local allowAttachments = VarOrNil(msg.Tags.AllowAttachments)
    local categoryId = VarOrNil(msg.Tags.CategoryId)
    local orderId = VarOrNil(msg.Tags.OrderId)

    if allowMessaging then allowMessaging = tonumber(allowMessaging) end
    if allowAttachments then allowAttachments = tonumber(allowAttachments) end
    if orderId then orderId = tonumber(orderId) end

    local hasPermission = MemberHasPermission(GetMember(userId), Permissions.MANAGE_CHANNELS)
    if ValidateCondition(not hasPermission, msg, {
            Status = "400",
            Data = json.encode({
                error = "User does not have permission to update the channel"
            })
        }) then
        return
    end

    local channel = SQLRead("SELECT * FROM channels WHERE channelId = ?", channelId)[1]
    if ValidateCondition(not channel, msg, {
            Status = "400",
            Data = json.encode({
                error = "Channel not found"
            })
        }) then
        return
    end

    -- Begin transaction for atomic updates
    db:exec("BEGIN TRANSACTION")
    local success = true

    -- Get current values
    local current_categoryId = channel.categoryId
    local current_order = channel.orderId
    local new_name = name or channel.name
    local new_allowMessaging = allowMessaging or channel.allowMessaging
    local new_allowAttachments = allowAttachments or channel.allowAttachments

    -- Determine target category
    local target_categoryId = current_categoryId
    if categoryId ~= nil then
        if categoryId == "" then
            target_categoryId = nil -- Moving to uncategorized
        else
            target_categoryId = tonumber(categoryId)
        end
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
            local max_order = SQLRead([[
                SELECT MAX(orderId) as maxOrder FROM channels
                WHERE categoryId = ?
            ]], target_categoryId)
            new_orderId = 1
            if max_order and #max_order > 0 and max_order[1].maxOrder then
                new_orderId = max_order[1].maxOrder + 1
            end
        else
            local max_order = SQLRead([[
                SELECT MAX(orderId) as maxOrder FROM channels
                WHERE categoryId IS NULL
            ]])
            new_orderId = 1
            if max_order and #max_order > 0 and max_order[1].maxOrder then
                new_orderId = max_order[1].maxOrder + 1
            end
        end
    end

    -- Handle category change: remove from old category's ordering
    if changing_category then
        if current_categoryId then
            SQLWrite([[
                UPDATE channels
                SET orderId = orderId - 1
                WHERE categoryId = ? AND orderId > ?
            ]], current_categoryId, current_order)
        else
            SQLWrite([[
                UPDATE channels
                SET orderId = orderId - 1
                WHERE categoryId IS NULL AND orderId > ?
            ]], current_order)
        end

        -- Make room in target category
        if target_categoryId then
            SQLWrite([[
                UPDATE channels
                SET orderId = orderId + 1
                WHERE categoryId = ? AND orderId >= ?
            ]], target_categoryId, new_orderId)
        else
            SQLWrite([[
                UPDATE channels
                SET orderId = orderId + 1
                WHERE categoryId IS NULL AND orderId >= ?
            ]], new_orderId)
        end
    elseif orderId and orderId ~= current_order then
        -- Handle ordering within same category
        if orderId < current_order then
            -- Moving up: shift others down
            if current_categoryId then
                SQLWrite([[
                    UPDATE channels
                    SET orderId = orderId + 1
                    WHERE categoryId = ? AND orderId >= ? AND orderId < ? AND channelId != ?
                ]], current_categoryId, orderId, current_order, channelId)
            else
                SQLWrite([[
                    UPDATE channels
                    SET orderId = orderId + 1
                    WHERE categoryId IS NULL AND orderId >= ? AND orderId < ? AND channelId != ?
                ]], orderId, current_order, channelId)
            end
        else
            -- Moving down: shift others up
            if current_categoryId then
                SQLWrite([[
                    UPDATE channels
                    SET orderId = orderId - 1
                    WHERE categoryId = ? AND orderId > ? AND orderId <= ? AND channelId != ?
                ]], current_categoryId, current_order, orderId, channelId)
            else
                SQLWrite([[
                    UPDATE channels
                    SET orderId = orderId - 1
                    WHERE categoryId IS NULL AND orderId > ? AND orderId <= ? AND channelId != ?
                ]], current_order, orderId, channelId)
            end
        end
    end

    -- Update the channel
    local rows = SQLWrite([[
        UPDATE channels
        SET name = ?, allowMessaging = ?, allowAttachments = ?, categoryId = ?, orderId = ?
        WHERE channelId = ?
    ]], new_name, new_allowMessaging, new_allowAttachments, target_categoryId, new_orderId, channelId)

    if rows ~= 1 then
        success = false
    end

    -- Resequence affected categories
    if success then
        if changing_category then
            ResequenceChannels(current_categoryId)
            ResequenceChannels(target_categoryId)
        else
            ResequenceChannels(current_categoryId)
        end
    end

    if success then
        db:exec("COMMIT")
        msg.reply({
            Action = "Update-Channel-Response",
            Status = "200",
        })
    else
        db:exec("ROLLBACK")
        msg.reply({
            Action = "Update-Channel-Response",
            Status = "500",
            Data = json.encode({
                error = "Failed to update channel"
            })
        })
    end
end)

Handlers.add("Delete-Channel", function(msg)
    local userId = msg.From
    local channelId = VarOrNil(msg.Tags.ChannelId)

    local hasPermission = MemberHasPermission(GetMember(userId), Permissions.MANAGE_CHANNELS)
    if ValidateCondition(not hasPermission, msg, {
            Status = "400",
            Data = json.encode({
                error = "User does not have permission to delete the channel"
            })
        }) then
        return
    end

    local channel = SQLRead("SELECT * FROM channels WHERE channelId = ?", channelId)[1]
    if ValidateCondition(not channel, msg, {
            Status = "400",
            Data = json.encode({
                error = "Channel not found"
            })
        }) then
        return
    end

    -- Begin transaction
    db:exec("BEGIN TRANSACTION")
    local success = true

    local channel_categoryId = channel.categoryId

    -- Delete all messages in the channel
    local messages_deleted = SQLWrite("DELETE FROM messages WHERE channelId = ?", channelId)

    -- Delete the channel
    local rows = SQLWrite("DELETE FROM channels WHERE channelId = ?", channelId)

    if rows ~= 1 then
        success = false
    end

    -- Resequence channels in the affected category
    if success then
        ResequenceChannels(channel_categoryId)
    end

    if success then
        db:exec("COMMIT")
        msg.reply({
            Action = "Delete-Channel-Response",
            Status = "200",
            Data = json.encode({
                messagesDeleted = messages_deleted
            })
        })
    else
        db:exec("ROLLBACK")
        msg.reply({
            Action = "Delete-Channel-Response",
            Status = "500",
            Data = json.encode({
                error = "Failed to delete channel"
            })
        })
    end
end)

----------------------------------------------------------------------------
--- ROLES

Handlers.add("Create-Role", function(msg)
    local userId = msg.From
    local name = VarOrNil(msg.Tags.Name) or "New Role"
    local color = VarOrNil(msg.Tags.Color) or "#696969"
    local permissions = VarOrNil(msg.Tags.Permissions) or 1
    local orderId = VarOrNil(msg.Tags.OrderId)

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

    local hasPermission = MemberHasPermission(GetMember(userId), Permissions.MANAGE_ROLES)
    if ValidateCondition(not hasPermission, msg, {
            Status = "400",
            Data = json.encode({
                error = "User does not have permission to create roles"
            })
        }) then
        return
    end

    -- Begin transaction
    db:exec("BEGIN TRANSACTION")
    local success = true

    -- Determine order position
    local new_orderId
    if orderId then
        new_orderId = orderId
        -- Make room for new role
        SQLWrite([[
            UPDATE roles SET orderId = orderId + 1
            WHERE orderId >= ?
        ]], orderId)
    else
        -- Place at end
        local maxOrderId = SQLRead("SELECT MAX(orderId) as maxOrder FROM roles")[1]
        new_orderId = 1
        if maxOrderId and maxOrderId.maxOrder then
            new_orderId = maxOrderId.maxOrder + 1
        end
    end

    -- Insert new role
    local rows = SQLWrite([[
        INSERT INTO roles (name, color, permissions, orderId)
        VALUES (?, ?, ?, ?)
    ]], name, color, permissions, new_orderId)

    if rows ~= 1 then
        success = false
    end

    -- Resequence to ensure clean ordering
    if success then
        ResequenceRoles()
    end

    if success then
        db:exec("COMMIT")
        msg.reply({
            Action = "Create-Role-Response",
            Status = "200",
        })
    else
        db:exec("ROLLBACK")
        msg.reply({
            Action = "Create-Role-Response",
            Status = "500",
            Data = json.encode({
                error = "Failed to create role"
            })
        })
    end
end)

Handlers.add("Update-Role", function(msg)
    local userId = msg.From
    local roleId = VarOrNil(msg.Tags.RoleId)
    local name = VarOrNil(msg.Tags.Name)
    local color = VarOrNil(msg.Tags.Color)
    local permissions = VarOrNil(msg.Tags.Permissions)
    local orderId = VarOrNil(msg.Tags.OrderId)

    if permissions then permissions = tonumber(permissions) end
    if orderId then orderId = tonumber(orderId) end
    if roleId then roleId = tonumber(roleId) end

    -- Validate permissions if provided
    if permissions and ValidateCondition(not PermissionIsValid(permissions), msg, {
            Status = "400",
            Data = json.encode({
                error = "Invalid permissions value"
            })
        }) then
        return
    end

    local hasPermission = MemberHasPermission(GetMember(userId), Permissions.MANAGE_ROLES)
    if ValidateCondition(not hasPermission, msg, {
            Status = "400",
            Data = json.encode({
                error = "User does not have permission to update roles"
            })
        }) then
        return
    end

    local role = SQLRead("SELECT * FROM roles WHERE roleId = ?", roleId)[1]
    if ValidateCondition(not role, msg, {
            Status = "400",
            Data = json.encode({
                error = "Role not found"
            })
        }) then
        return
    end



    -- Begin transaction for atomic updates
    db:exec("BEGIN TRANSACTION")
    local success = true

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
            SQLWrite([[
                UPDATE roles
                SET orderId = orderId + 1
                WHERE orderId >= ? AND orderId < ? AND roleId != ?
            ]], orderId, current_order, roleId)
        else
            -- Moving down: shift other roles up
            SQLWrite([[
                UPDATE roles
                SET orderId = orderId - 1
                WHERE orderId > ? AND orderId <= ? AND roleId != ?
            ]], current_order, orderId, roleId)
        end
    end

    -- Update the role
    local rows = SQLWrite([[
        UPDATE roles
        SET name = ?, color = ?, permissions = ?, orderId = ?
        WHERE roleId = ?
    ]], new_name, new_color, new_permissions, new_orderId, roleId)

    if rows ~= 1 then
        success = false
    end

    -- Resequence to ensure clean ordering
    if success then
        ResequenceRoles()
    end

    if success then
        db:exec("COMMIT")
        msg.reply({
            Action = "Update-Role-Response",
            Status = "200",
        })
    else
        db:exec("ROLLBACK")
        msg.reply({
            Action = "Update-Role-Response",
            Status = "500",
            Data = json.encode({
                error = "Failed to update role"
            })
        })
    end
end)

Handlers.add("Delete-Role", function(msg)
    local userId = msg.From
    local roleId = VarOrNil(msg.Tags.RoleId)

    if roleId then roleId = tonumber(roleId) end

    local hasPermission = MemberHasPermission(GetMember(userId), Permissions.MANAGE_ROLES)
    if ValidateCondition(not hasPermission, msg, {
            Status = "400",
            Data = json.encode({
                error = "User does not have permission to delete roles"
            })
        }) then
        return
    end

    local role = SQLRead("SELECT * FROM roles WHERE roleId = ?", roleId)[1]
    if ValidateCondition(not role, msg, {
            Status = "400",
            Data = json.encode({
                error = "Role not found"
            })
        }) then
        return
    end

    -- Prevent deletion of default role (roleId 1)
    if ValidateCondition(roleId == 1, msg, {
            Status = "400",
            Data = json.encode({
                error = "Cannot delete the default role"
            })
        }) then
        return
    end

    -- Begin transaction
    db:exec("BEGIN TRANSACTION")
    local success = true

    -- Remove this role from all members who have it
    local members = SQLRead("SELECT * FROM members")
    local membersUpdated = 0

    for _, member in ipairs(members) do
        local memberRoles = SQLRead("SELECT * FROM memberRoles WHERE userId = ? AND roleId = ?", member.userId, roleId)
        if #memberRoles > 0 then
            local removed = SQLWrite("DELETE FROM memberRoles WHERE userId = ? AND roleId = ?", member.userId, roleId)
            membersUpdated = membersUpdated + removed
        end
    end

    -- Delete the role
    local rows = SQLWrite("DELETE FROM roles WHERE roleId = ?", roleId)

    if rows ~= 1 then
        success = false
    end

    -- Resequence roles to fill the gap
    if success then
        ResequenceRoles()
    end

    if success then
        db:exec("COMMIT")
        msg.reply({
            Action = "Delete-Role-Response",
            Status = "200",
            Data = json.encode({
                membersUpdated = membersUpdated
            })
        })
    else
        db:exec("ROLLBACK")
        msg.reply({
            Action = "Delete-Role-Response",
            Status = "500",
            Data = json.encode({
                error = "Failed to delete role"
            })
        })
    end
end)

----------------------------------------------------------------------------
--- MEMBERS

Handlers.add("Get-Member", function(msg)
    local userId = VarOrNil(msg.Tags.UserId) or msg.From

    local member = GetMember(userId)
    if ValidateCondition(not member, msg, {
            Status = "400",
            Data = json.encode({
                error = "User is not a member of this server"
            })
        }) then
        return
    end

    msg.reply({
        Action = "Get-Member-Response",
        Member = json.encode(member)
    })
end)

Handlers.add("Get-All-Members", function(msg)
    local membersWithRoles = SQLRead([[
        SELECT m.userId, m.nickname, mr.roleId
        FROM members m
        LEFT JOIN memberRoles mr ON m.userId = mr.userId
    ]])

    local membersArranged = {}
    for _, row in ipairs(membersWithRoles) do
        if not membersArranged[row.userId] then
            membersArranged[row.userId] = {
                nickname = row.nickname,
                roles = {}
            }
        end
        if row.roleId then
            table.insert(membersArranged[row.userId].roles, row.roleId)
        end
    end

    msg.reply({
        Action = "Get-Members-Response",
        Status = "200",
        Data = json.encode(membersArranged)
    })
end)

Handlers.add("Update-Member", function(msg)
    local userId = msg.From
    local targetUserId = VarOrNil(msg.Tags.TargetUserId)
    local nickname = VarOrNil(msg.Tags.Nickname)

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

    -- Update nickname if provided
    if nickname then
        local rows = SQLWrite("UPDATE members SET nickname = ? WHERE userId = ?", nickname, actualTargetId)
        if ValidateCondition(rows ~= 1, msg, {
                Status = "500",
                Data = json.encode({
                    error = "Failed to update member"
                })
            }) then
            return
        end
    end

    msg.reply({
        Action = "Update-Member-Response",
        Status = "200",
    })
end)

Handlers.add("Kick-Member", function(msg)
    local userId = msg.From
    local targetUserId = VarOrNil(msg.Tags.TargetUserId)

    local hasPermission = MemberHasPermission(GetMember(userId), Permissions.KICK_MEMBERS)
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

    -- Begin transaction
    db:exec("BEGIN TRANSACTION")
    local success = true

    -- Remove member roles
    local rolesDeleted = SQLWrite("DELETE FROM memberRoles WHERE userId = ?", targetUserId)

    -- Remove member
    local rows = SQLWrite("DELETE FROM members WHERE userId = ?", targetUserId)

    if rows ~= 1 then
        success = false
    end

    if success then
        db:exec("COMMIT")

        -- Notify subspace that user was kicked
        ao.send({
            Target = Subspace,
            Action = "User-Left-Server",
            Tags = {
                UserId = targetUserId,
                ServerId = ao.id,
                Reason = "kicked"
            }
        })

        msg.reply({
            Action = "Kick-Member-Response",
            Status = "200",
            Data = json.encode({
                rolesRemoved = rolesDeleted
            })
        })
    else
        db:exec("ROLLBACK")
        msg.reply({
            Action = "Kick-Member-Response",
            Status = "500",
            Data = json.encode({
                error = "Failed to kick member"
            })
        })
    end
end)

Handlers.add("Ban-Member", function(msg)
    local userId = msg.From
    local targetUserId = VarOrNil(msg.Tags.TargetUserId)
    local reason = VarOrNil(msg.Tags.Reason) or "No reason provided"

    local hasPermission = MemberHasPermission(GetMember(userId), Permissions.BAN_MEMBERS)
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
    if targetMember then
        -- Begin transaction
        db:exec("BEGIN TRANSACTION")
        local success = true

        -- Remove member roles
        local rolesDeleted = SQLWrite("DELETE FROM memberRoles WHERE userId = ?", targetUserId)

        -- Remove member
        local rows = SQLWrite("DELETE FROM members WHERE userId = ?", targetUserId)

        if rows ~= 1 then
            success = false
        end

        if success then
            db:exec("COMMIT")

            -- Notify subspace that user was banned
            ao.send({
                Target = Subspace,
                Action = "User-Left-Server",
                Tags = {
                    UserId = targetUserId,
                    ServerId = ao.id,
                    Reason = "banned"
                }
            })

            msg.reply({
                Action = "Ban-Member-Response",
                Status = "200",
                Data = json.encode({
                    message = "Member banned and removed from server",
                    rolesRemoved = rolesDeleted
                })
            })
        else
            db:exec("ROLLBACK")
            msg.reply({
                Action = "Ban-Member-Response",
                Status = "500",
                Data = json.encode({
                    error = "Failed to ban member"
                })
            })
        end
    else
        msg.reply({
            Action = "Ban-Member-Response",
            Status = "200",
            Data = json.encode({
                message = "User was not a member of the server"
            })
        })
    end
end)

Handlers.add("Unban-Member", function(msg)
    local userId = msg.From
    local targetUserId = VarOrNil(msg.Tags.TargetUserId)

    local hasPermission = MemberHasPermission(GetMember(userId), Permissions.BAN_MEMBERS)
    if ValidateCondition(not hasPermission, msg, {
            Status = "400",
            Data = json.encode({
                error = "User does not have permission to unban members"
            })
        }) then
        return
    end

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
    local targetUserId = VarOrNil(msg.Tags.TargetUserId)
    local roleId = VarOrNil(msg.Tags.RoleId)

    if roleId then roleId = tonumber(roleId) end

    local hasPermission = MemberHasPermission(GetMember(userId), Permissions.MANAGE_ROLES)
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

    local role = SQLRead("SELECT * FROM roles WHERE roleId = ?", roleId)[1]
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

    -- Check if user already has this role
    local existingRole = SQLRead("SELECT * FROM memberRoles WHERE userId = ? AND roleId = ?", targetUserId, roleId)
    if ValidateCondition(#existingRole > 0, msg, {
            Status = "400",
            Data = json.encode({
                error = "User already has this role"
            })
        }) then
        return
    end

    -- Assign the role
    local rows = SQLWrite("INSERT INTO memberRoles (userId, roleId) VALUES (?, ?)", targetUserId, roleId)
    if ValidateCondition(rows ~= 1, msg, {
            Status = "500",
            Data = json.encode({
                error = "Failed to assign role"
            })
        }) then
        return
    end

    msg.reply({
        Action = "Assign-Role-Response",
        Status = "200",
    })
end)

Handlers.add("Unassign-Role", function(msg)
    local userId = msg.From
    local targetUserId = VarOrNil(msg.Tags.TargetUserId)
    local roleId = VarOrNil(msg.Tags.RoleId)

    if roleId then roleId = tonumber(roleId) end

    local hasPermission = MemberHasPermission(GetMember(userId), Permissions.MANAGE_ROLES)
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

    local role = SQLRead("SELECT * FROM roles WHERE roleId = ?", roleId)[1]
    if ValidateCondition(not role, msg, {
            Status = "400",
            Data = json.encode({
                error = "Role not found"
            })
        }) then
        return
    end

    -- Prevent removal of default role (roleId 1) from any member
    if ValidateCondition(roleId == 1, msg, {
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

    -- Check if user has this role
    local existingRole = SQLRead("SELECT * FROM memberRoles WHERE userId = ? AND roleId = ?", targetUserId, roleId)
    if ValidateCondition(#existingRole == 0, msg, {
            Status = "400",
            Data = json.encode({
                error = "User does not have this role"
            })
        }) then
        return
    end

    -- Remove the role
    local rows = SQLWrite("DELETE FROM memberRoles WHERE userId = ? AND roleId = ?", targetUserId, roleId)
    if ValidateCondition(rows ~= 1, msg, {
            Status = "500",
            Data = json.encode({
                error = "Failed to unassign role"
            })
        }) then
        return
    end

    msg.reply({
        Action = "Unassign-Role-Response",
        Status = "200",
    })
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
    local channelId = VarOrNil(msg.Tags.ChannelId)
    local attachments = VarOrNil(msg.Tags.Attachments) or "[]"
    local replyTo = VarOrNil(msg.Tags.ReplyTo)
    local timestamp = tonumber(msg.Timestamp or os.time())
    local messageTxId = msg.Id

    if channelId then channelId = tonumber(channelId) end
    if replyTo then replyTo = tonumber(replyTo) end

    local member = GetMember(userId)
    if ValidateCondition(not member, msg, {
            Status = "400",
            Data = json.encode({
                error = "You are not a member of this server"
            })
        }) then
        return
    end

    local channel = SQLRead("SELECT * FROM channels WHERE channelId = ?", channelId)[1]
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
    if replyTo then
        local replyMessage = SQLRead("SELECT * FROM messages WHERE messageId = ?", replyTo)[1]
        if ValidateCondition(not replyMessage, msg, {
                Status = "400",
                Data = json.encode({
                    error = "Reply target message not found"
                })
            }) then
            return
        end
    end

    -- Insert message
    local rows = SQLWrite([[
        INSERT INTO messages (content, channelId, authorId, timestamp, messageTxId, attachments, replyTo)
        VALUES (?, ?, ?, ?, ?, ?, ?)
    ]], content, channelId, userId, timestamp, messageTxId, attachments, replyTo)

    if ValidateCondition(rows ~= 1, msg, {
            Status = "500",
            Data = json.encode({
                error = "Failed to send message"
            })
        }) then
        return
    end

    -- Extract mentions from content and send notification messages
    local mentions = ExtractMentions(content)
    for _, mentionedUserId in ipairs(mentions) do
        -- Check if the mentioned user is a member of this server
        local mentionedMember = GetMember(mentionedUserId)
        if mentionedMember then
            ao.send({
                Target = Subspace,
                Action = "Add-Notification",
                Tags = {
                    ServerOrDmId = ao.id,
                    FromUserId = userId,
                    ForUserId = mentionedUserId,
                    Source = "SERVER",
                    ChannelId = tostring(channelId),
                    ServerName = Name,
                    ServerLogo = Logo,
                    ChannelName = channel.name,
                    AuthorName = member.nickname,
                    MessageTxId = messageTxId,
                    Timestamp = tostring(timestamp),
                }
            })
        end
    end

    msg.reply({
        Action = "Send-Message-Response",
        Status = "200",
    })
end)

Handlers.add("Edit-Message", function(msg)
    local userId = msg.From
    local messageId = VarOrNil(msg.Tags.MessageId)
    local content = VarOrNil(msg.Data)

    if messageId then messageId = tonumber(messageId) end

    local member = GetMember(userId)
    if ValidateCondition(not member, msg, {
            Status = "400",
            Data = json.encode({
                error = "You are not a member of this server"
            })
        }) then
        return
    end

    local message = SQLRead("SELECT * FROM messages WHERE messageId = ?", messageId)[1]
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
    local rows = SQLWrite([[
        UPDATE messages
        SET content = ?, edited = 1
        WHERE messageId = ?
    ]], content, messageId)

    if ValidateCondition(rows ~= 1, msg, {
            Status = "500",
            Data = json.encode({
                error = "Failed to edit message"
            })
        }) then
        return
    end

    msg.reply({
        Action = "Edit-Message-Response",
        Status = "200",
    })
end)

Handlers.add("Delete-Message", function(msg)
    local userId = msg.From
    local messageId = VarOrNil(msg.Tags.MessageId)

    if messageId then messageId = tonumber(messageId) end

    local member = GetMember(userId)
    if ValidateCondition(not member, msg, {
            Status = "400",
            Data = json.encode({
                error = "You are not a member of this server"
            })
        }) then
        return
    end

    local message = SQLRead("SELECT * FROM messages WHERE messageId = ?", messageId)[1]
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

    -- Delete message
    local rows = SQLWrite("DELETE FROM messages WHERE messageId = ?", messageId)

    if ValidateCondition(rows ~= 1, msg, {
            Status = "500",
            Data = json.encode({
                error = "Failed to delete message"
            })
        }) then
        return
    end

    msg.reply({
        Action = "Delete-Message-Response",
        Status = "200",
    })
end)

Handlers.add("Get-Messages", function(msg)
    local userId = msg.From
    local channelId = VarOrNil(msg.Tags.ChannelId)
    local limit = VarOrNil(msg.Tags.Limit) or 50
    local before = VarOrNil(msg.Tags.Before)
    local after = VarOrNil(msg.Tags.After)

    if channelId then channelId = tonumber(channelId) end
    if limit then limit = tonumber(limit) end
    if before then before = tonumber(before) end
    if after then after = tonumber(after) end

    local member = GetMember(userId)
    if ValidateCondition(not member, msg, {
            Status = "400",
            Data = json.encode({
                error = "You are not a member of this server"
            })
        }) then
        return
    end

    local messages

    if channelId then
        -- Get messages from specific channel
        -- Check if channel exists
        local channel = SQLRead("SELECT * FROM channels WHERE channelId = ?", channelId)[1]
        if ValidateCondition(not channel, msg, {
                Status = "400",
                Data = json.encode({
                    error = "Channel not found"
                })
            }) then
            return
        end

        -- Build query with optional pagination for specific channel
        local query = "SELECT * FROM messages WHERE channelId = ?"
        local params = { channelId }

        if before then
            query = query .. " AND messageId < ?"
            table.insert(params, before)
        end

        if after then
            query = query .. " AND messageId > ?"
            table.insert(params, after)
        end

        query = query .. " ORDER BY messageId DESC LIMIT ?"
        table.insert(params, limit)

        messages = SQLRead(query, table.unpack(params))
    else
        -- Get messages from all channels in the server
        local query = "SELECT * FROM messages"
        local params = {}

        if before then
            query = query .. " WHERE messageId < ?"
            table.insert(params, before)
        end

        if after then
            if before then
                query = query .. " AND messageId > ?"
            else
                query = query .. " WHERE messageId > ?"
            end
            table.insert(params, after)
        end

        query = query .. " ORDER BY messageId DESC LIMIT ?"
        table.insert(params, limit)

        messages = SQLRead(query, table.unpack(params))
    end

    msg.reply({
        Action = "Get-Messages-Response",
        Status = "200",
        Data = json.encode({
            messages = messages,
            channelScope = channelId and "single" or "all"
        })
    })
end)

Handlers.add("Get-Single-Message", function(msg)
    local messageId = VarOrNil(msg.Tags.MessageId)
    local messageTxId = VarOrNil(msg.Tags.MessageTxId)

    if messageId then messageId = tonumber(messageId) end

    local message
    if messageId then
        message = SQLRead("SELECT * FROM messages WHERE messageId = ?", messageId)[1]
    elseif messageTxId then
        message = SQLRead("SELECT * FROM messages WHERE messageTxId = ?", messageTxId)[1]
    else
        msg.reply({
            Action = "Get-Single-Message-Response",
            Status = "400",
            Data = json.encode({
                error = "Either messageId or messageTxId is required"
            })
        })
        return
    end

    if ValidateCondition(not message, msg, {
            Status = "400",
            Data = json.encode({
                error = "Message not found"
            })
        }) then
        return
    end

    msg.reply({
        Action = "Get-Single-Message-Response",
        Status = "200",
        Data = json.encode({
            message = message
        })
    })
end)

----------------------------------------------------------------------------

-- Validate and fix any invalid permissions in existing roles
function ValidateExistingRolePermissions()
    local roles = SQLRead("SELECT * FROM roles")
    local fixedCount = 0

    for _, role in ipairs(roles) do
        if not PermissionIsValid(role.permissions) then
            -- Fix invalid permissions by setting to basic SEND_MESSAGES permission
            local newPermissions = Permissions.SEND_MESSAGES
            SQLWrite("UPDATE roles SET permissions = ? WHERE roleId = ?", newPermissions, role.roleId)
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

-- Ensure all existing members have the default role
EnsureAllMembersHaveDefaultRole()

----------------------------------------------------------------------------

-- Get the user's highest role (lowest orderId = highest hierarchy)
function GetUserHighestRole(userId)
    local member = GetMember(userId)
    if not member or not member.roles or #member.roles == 0 then
        return nil
    end

    local highestRole = nil
    local lowestOrderId = nil

    for _, roleId in ipairs(member.roles) do
        local role = SQLRead("SELECT * FROM roles WHERE roleId = ?", roleId)[1]
        if role then
            if lowestOrderId == nil or role.orderId < lowestOrderId then
                lowestOrderId = role.orderId
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
    local targetRole = SQLRead("SELECT * FROM roles WHERE roleId = ?", targetRoleId)[1]
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

    for _, roleId in ipairs(member.roles) do
        local role = SQLRead("SELECT * FROM roles WHERE roleId = ?", roleId)[1]
        if role and HasSpecificPermission(role.permissions, Permissions.MANAGE_ROLES) then
            if lowestOrderId == nil or role.orderId < lowestOrderId then
                lowestOrderId = role.orderId
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
    local targetRole = SQLRead("SELECT * FROM roles WHERE roleId = ?", roleId)[1]
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

    local botProcess = VarOrNil(msg.Tags.BotProcess)
    local serverId = VarOrNil(msg.Tags.ServerId)

    if ValidateCondition(not botProcess, msg, {
            Status = "400",
            Data = json.encode({
                error = "BotProcess is required"
            })
        }) then
        return
    end

    if ValidateCondition(not serverId, msg, {
            Status = "400",
            Data = json.encode({
                error = "ServerId is required"
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
    local bot = SQLRead("SELECT * FROM bots WHERE botProcess = ? AND botApproved = 0", botProcess)[1]
    if ValidateCondition(bot, msg, {
            Status = "400",
            Data = json.encode({
                error = "Bot already exists in server"
            })
        }) then
        return
    end

    -- add bot to server
    local rows = SQLWrite("INSERT INTO bots (botProcess) VALUES (?)", botProcess)
    if ValidateCondition(rows ~= 1, msg, {
            Status = "500",
            Data = json.encode({
                error = "Failed to add bot"
            })
        }) then
        return
    end

    msg.reply({
        Action = "Add-Bot-Response",
        Status = "200",
    })
end)

Handlers.add("Approve-Add-Bot", function(msg)
    assert(msg.From == Subspace, "You are not allowed to approve bots")

    local botProcess = VarOrNil(msg.Tags.BotProcess)

    local bot = SQLRead("SELECT * FROM bots WHERE botProcess = ?", botProcess)[1]
    if ValidateCondition(not bot, msg, {
            Status = "400",
            Data = json.encode({
                error = "Bot not found"
            })
        }) then
        return
    end

    SQLWrite("UPDATE bots SET botApproved = 1 WHERE botProcess = ?", botProcess)

    msg.reply({
        Action = "Approve-Add-Bot-Response",
        Status = "200",
    })
end)

Handlers.add("Subscribe", function(msg)
    local botProcess = msg.From

    -- verify if bot is approved
    local bot = SQLRead("SELECT * FROM bots WHERE botProcess = ? AND botApproved = 1", botProcess)[1]
    if ValidateCondition(not bot, msg, {
            Status = "400",
            Data = json.encode({
                error = "Bot is either not approved or doesnot exist in the server"
            })
        }) then
        return
    end

    -- add bot to subsriptions list
    SubscribedBots[botProcess] = true

    msg.reply({
        Action = "Subscribe-Response",
        Status = "200",
    })
end)

Handlers.add("Remove-Bot", function(msg)
    local userId = msg.From
    local botProcess = VarOrNil(msg.Tags.BotProcess)

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

    local bot = SQLRead("SELECT * FROM bots WHERE botProcess = ?", botProcess)[1]
    if ValidateCondition(not bot, msg, {
            Status = "400",
            Data = json.encode({
                error = "Bot not found"
            })
        }) then
        return
    end

    -- remove bot from server
    local rows = SQLWrite("DELETE FROM bots WHERE botProcess = ?", botProcess)
    if ValidateCondition(rows ~= 1, msg, {
            Status = "500",
            Data = json.encode({
                error = "Failed to remove bot"
            })
        }) then
        return
    end

    -- tell subspace and bot process that bot has been removed
    ao.send({
        Target = botProcess,
        Action = "Remove-Bot",
    })
    ao.send({
        Target = Subspace,
        Action = "Remove-Bot",
        Tags = {
            BotProcess = botProcess
        }
    })

    msg.reply({
        Action = "Remove-Bot-Response",
        Status = "200",
    })
end)
