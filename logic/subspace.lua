-- in-memory storage only
json = require("json")

----------------------------------------------------------------------------
--- VARIABLES

Authority = "fcoN_xJeisVsPXA-trzVAuIiqO3ydLQxM-L4XbrQKzY"

Sources = {
    Bot = {
        Id = "HkB1WOco7nYXp73qYyGgyF6QkeJtFG5qIi4MaXsd1iY",
        Version = "1.0.0"
    },
    Dm = {
        Id = "RRFdbQy-ApzRIKdyI2GDIMi7Tmkgqsz7Ee4eNiYWY9k",
        Version = "1.0.0"
    },
    Server = {
        Id = "qj2Q_6R7U3QXbD9G30m97BN3xM6ZiSb7M-PKJxU8fkQ",
        Version = "1.0.0"
    },
}

Handlers.add("Sources", function(msg)
    msg.reply({
        Action = "Sources-Response",
        Status = "200",
        Data = json.encode(Sources)
    })
end)


----------------------------------------------------------------------------

-- legacy sqlite helpers removed

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
-- Migrate sqlite to simple lua tables

profiles = profiles or {}               -- includes serversJoined, friends and delegations
usedDmProcesses = usedDmProcesses or {} -- mapping for dmProcess to userId
delegations = delegations or {}         -- mapping for delegated id to original id (only one delegation per user)
servers = servers or {}
bots = bots or {}                       -- includes botServers

-- function CurrentStateToTables()
--     local dbProfiles = SQLRead("SELECT * FROM profiles")
--     for _, profile in ipairs(dbProfiles) do
--         profiles[profile.userId] = {
--             pfp = profile.pfp,
--             dmProcess = profile.dmProcess,
--             serversJoined = {},
--             friends = {
--                 accepted = {},
--                 sent = {},
--                 received = {}
--             },
--             delegations = {}
--         }
--     end

--     local serversJoined = SQLRead("SELECT * FROM serversJoined")
--     for _, serverJoined in ipairs(serversJoined) do
--         profiles[serverJoined.userId].serversJoined[serverJoined.serverId] = { orderId = serverJoined.orderId }
--     end

--     local servers = SQLRead("SELECT * FROM servers")
--     for _, server in ipairs(servers) do
--         servers[server.serverId] = {
--             publicServer = server.publicServer,
--             ownerId = server.userId
--         }
--     end
-- end

----------------------------------------------------------------------------

-- db:exec([[
--     CREATE TABLE IF NOT EXISTS profiles (
--         userId TEXT PRIMARY KEY,
--         pfp TEXT DEFAULT "",
--         dmProcess TEXT DEFAULT ""
--     );

--     CREATE TABLE IF NOT EXISTS serversJoined (
--         userId TEXT NOT NULL,
--         serverId TEXT NOT NULL,
--         orderId INTEGER DEFAULT 0,
--         PRIMARY KEY (userId, serverId)
--     );

--     CREATE TABLE IF NOT EXISTS friends (
--         senderId TEXT NOT NULL,
--         receiverId TEXT NOT NULL,
--         accepted INTEGER DEFAULT 0,
--         PRIMARY KEY (senderId, receiverId)
--     );

--     CREATE TABLE IF NOT EXISTS servers (
--         serverId TEXT PRIMARY KEY,
--         publicServer INTEGER DEFAULT 1,
--         userId TEXT NOT NULL
--     );

--     CREATE TABLE IF NOT EXISTS notifications (
--         notificationId INTEGER PRIMARY KEY AUTOINCREMENT,
--         serverOrDmId TEXT NOT NULL,
--         fromUserId TEXT NOT NULL,
--         forUserId TEXT NOT NULL,
--         timestamp INTEGER DEFAULT 0,
--         source TEXT NOT NULL CHECK (source IN ('SERVER', 'DM')),
--         channelId INTEGER,
--         serverName TEXT,
--         channelName TEXT,
--         authorName TEXT,
--         messageTxId TEXT,

--         FOREIGN KEY (fromUserId) REFERENCES profiles(userId),
--         FOREIGN KEY (forUserId) REFERENCES profiles(userId),
--         CHECK (
--             (source = 'SERVER' AND channelId IS NOT NULL) OR
--             (source = 'DM' AND channelId IS NULL)
--         )
--     );

--     CREATE TABLE IF NOT EXISTS delegations (
--         userId TEXT NOT NULL,
--         delegatedUserId TEXT NOT NULL,
--         PRIMARY KEY (userId, delegatedUserId)
--     );

--     CREATE TABLE IF NOT EXISTS bots (
--         userId TEXT NOT NULL,
--         botProcess TEXT PRIMARY KEY,
--         botName TEXT NOT NULL,
--         botPfp TEXT NOT NULL,
--         botPublic INTEGER DEFAULT 0,

--         FOREIGN KEY (userId) REFERENCES profiles(userId)
--     );

--     CREATE TABLE IF NOT EXISTS botServers (
--         botProcess TEXT NOT NULL,
--         serverId TEXT NOT NULL,
--         PRIMARY KEY (botProcess, serverId)

--         FOREIGN KEY (botProcess) REFERENCES bots(botProcess)
--         FOREIGN KEY (serverId) REFERENCES servers(serverId)
--     );
-- ]])

-- table helper functions

function GetProfile(userId)
    local profile = profiles[userId]
    if not profile then
        return nil
    end
    return profile
end

-- Resolve the original user id for a possibly delegated id; validates delegation
function GetOriginalId(delegationOrOriginalId)
    -- userId can either be the originalId or the delegatedId
    -- always return the originalId
    -- a user can have multiple delegations
    local originalId = delegations[delegationOrOriginalId]
    if originalId then
        local profile = GetProfile(originalId)
        -- verify that the delegation is valid
        if profile and profile.delegations[delegationOrOriginalId] then
            return originalId
        else
            return nil
        end
    else
        return delegationOrOriginalId
    end
end

function GetServer(serverId)
    local server = servers[serverId]
    if not server then
        return nil
    end
    return server
end

function ServerExists(serverId)
    return GetServer(serverId) ~= nil
end

function ServerIsPublic(serverId)
    local server = GetServer(serverId)
    return server and server.publicServer
end

function UserInServer(userId, serverId)
    local profile = GetProfile(userId)
    return profile and profile.serversJoined[tostring(serverId)] ~= nil
end

-- Helper function to resequence servers for a specific user
-- Normalize server orderIds for a profile (1..n without gaps)
function ResequenceUserServers(userId)
    local profile = GetProfile(userId)
    if not profile then
        return 0
    end

    -- Keep serversJoined keyed by serverId; just normalize orderId values to 1..n
    local entries = {}
    for serverId, info in pairs(profile.serversJoined) do
        table.insert(entries, { id = tostring(serverId), orderId = tonumber(info.orderId) or 0 })
    end
    table.sort(entries, function(a, b)
        return a.orderId < b.orderId
    end)
    local count = 0
    for index, entry in ipairs(entries) do
        local sv = profile.serversJoined[entry.id]
        if sv then
            sv.orderId = index
            profile.serversJoined[entry.id] = sv
            count = count + 1
        end
    end
    return count
end

-- Helper to compute next order id for serversJoined for a given profile
-- Compute the next order id where a new server should appear for a profile
local function GetNextServerOrderId(profile)
    if not profile or not profile.serversJoined then return 1 end
    local maxOrder = 0
    for _, info in pairs(profile.serversJoined) do
        local ord = tonumber(info.orderId) or 0
        if ord > maxOrder then maxOrder = ord end
    end
    return maxOrder + 1
end

----------------------------------------------------------------------------

-- Push Subspace-wide state (profiles, servers, bots, notifications) to patch cache
function SyncProcessState()
    -- This function is used to take all the possible data and couple it into
    -- a single table which will be stored in Hyperbeams state for quick access.
    -- Everything must be in a JSON like structure
    -- This function should be called everytime after a change is made to the server

    local state = {
        sources = Sources,
        profiles = profiles,
        servers = servers,
        delegations = delegations,
        bots = bots,
        notifications = notifications,
    }

    -- Special message to the patch device which will update the cache in hyperbeam nodes
    Send({
        Target = ao.id,
        device = "patch@1.0",
        cache = { subspace = state }
    })
end

----------------------------------------------------------------------------
--- PROFILES

-- Create a profile with a unique DM process id
Handlers.add("Create-Profile", function(msg)
    local userId = msg.From
    local dmProcess = VarOrNil(msg.Tags["Dm-Process"])

    -- check if profile already exists
    local profile = GetProfile(userId)
    if profile and profile.dmProcess then
        msg.reply({
            Action = "Create-Profile-Response",
            Status = "400",
            Data = json.encode({
                error = "Profile already exists"
            })
        })
        return
    end

    if ValidateCondition(not dmProcess or #dmProcess ~= 43, msg, {
            Status = "400",
            Data = json.encode({
                error = "Dm process is required and must be a valid process id"
            })
        })
    then
        return
    end

    -- make sure that this dmProcess is not already in the database
    if ValidateCondition(usedDmProcesses[dmProcess], msg, {
            Status = "400",
            Data = json.encode({
                error = "Dm process already exists"
            })
        })
    then
        return
    end

    -- create profile
    profiles[userId] = {
        pfp = "",
        dmProcess = dmProcess,
        serversJoined = {},
        friends = {
            accepted = {},
            sent = {},
            received = {}
        },
        delegations = {},
        notifications = {},
        nextNotificationId = 1
    }
    usedDmProcesses[dmProcess] = userId

    SyncProcessState()

    msg.reply({
        Action = "Create-Profile-Response",
        Status = "200",
        Data = json.encode({
            success = "Profile created"
        })
    })
end)

-- all get requests will now be handled by hyperbeam URL calls by reading the patch cache
-- Handlers.add("Get-Profile", function(msg)
--     local userId = VarOrNil(msg.Tags.UserId) or msg.From
--     userId = GetOriginalId(userId)

--     local profile = GetProfile(userId)
--     if ValidateCondition(not profile, msg, {
--             Status = "404",
--             Data = json.encode({
--                 error = "Profile not found"
--             })
--         })
--     then
--         return
--     end

--     msg.reply({
--         Action = "Get-Profile-Response",
--         Status = "200",
--         Data = json.encode(profile)
--     })
-- end)

-- Handlers.add("Get-Bulk-Profile", function(msg)
--     local userIds = VarOrNil(msg.Tags.UserIds)
--     if ValidateCondition(not userIds, msg, {
--             Status = "400",
--             Data = json.encode({
--                 error = "userIds is required"
--             })
--         })
--     then
--         return
--     end

--     userIds = json.decode(userIds)

--     local profiles = {}
--     for _, userId in ipairs(userIds) do
--         local profile = GetProfile(userId)
--         if profile then
--             table.insert(profiles, profile)
--         end
--     end

--     msg.reply({
--         Action = "Get-Bulk-Profile-Response",
--         Status = "200",
--         Data = json.encode(profiles)
--     })
-- end)

-- Update profile fields; currently supports pfp
Handlers.add("Update-Profile", function(msg)
    local userId = msg.From
    userId = GetOriginalId(userId)
    local pfp = VarOrNil(msg.Tags.Pfp)

    local profile = GetProfile(userId)
    if ValidateCondition(not profile, msg, {
            Status = "404",
            Data = json.encode({
                error = "Profile not found"
            })
        })
    then
        return
    end

    if pfp then
        profile.pfp = pfp
    end

    profiles[userId] = profile

    SyncProcessState()
    msg.reply({
        Action = "Update-Profile-Response",
        Status = "200",
        Data = json.encode(profile)
    })
end)

----------------------------------------------------------------------------
--- DELEGATIONS

-- Handlers.add("Get-Original-Id", function(msg)
--     local userId = VarOrNil(msg.Tags.UserId)
--     if ValidateCondition(not userId, msg, {
--             Status = "400",
--             Data = json.encode({
--                 error = "userId is required"
--             })
--         })
--     then
--         return
--     end

--     local originalId = GetOriginalId(userId)
--     msg.reply({
--         Action = "Get-Original-Id-Response",
--         Status = "200",
--         OriginalId = originalId
--     })
-- end)

Handlers.add("Add-Delegation", function(msg)

end)

Handlers.add("Remove-Delegation", function(msg)

end)

Handlers.add("Remove-All-Delegations", function(msg)

end)


----------------------------------------------------------------------------
--- SERVER

-- Create a server record owned by the caller, and stage it in their joined list
Handlers.add("Create-Server", function(msg)
    local userId = msg.From
    userId = GetOriginalId(userId)
    local serverProcess = VarOrNil(msg.Tags["Server-Process"])

    local profile = GetProfile(userId)
    if ValidateCondition(not profile, msg, {
            Status = "404",
            Data = json.encode({
                error = "Profile not found"
            })
        })
    then
        return
    end

    if ValidateCondition(not serverProcess or #serverProcess ~= 43, msg, {
            Status = "400",
            Data = json.encode({
                error = "Server process is required and must be a valid process id"
            })
        })
    then
        return
    end

    -- make sure that this serverId is not already in the database
    if ValidateCondition(ServerExists(serverProcess), msg, {
            Status = "400",
            Data = json.encode({
                error = "Server already exists"
            })
        })
    then
        return
    end

    servers[serverProcess] = {
        ownerId = userId,
        publicServer = true
    }

    profiles[userId].serversJoined[serverProcess] = {
        orderId = GetNextServerOrderId(profiles[userId]),
        serverApproved = false
    }

    SyncProcessState()
    msg.reply({
        Action = "Create-Server-Response",
        Status = "200",
        ["Server-Id"] = serverProcess
    })
end)

-- Update server visibility from the server process itself
Handlers.add("Update-Server", function(msg)
    local serverId = msg.From
    local publicServer = (VarOrNil(msg.Tags["Public-Server"]) == "true") -- bool

    if ValidateCondition(not ServerExists(serverId), msg, {
            Status = "404",
            Data = json.encode({
                error = "Server not found"
            })
        })
    then
        return
    end

    local server = GetServer(serverId)
    if ValidateCondition(not server, msg, {
            Status = "404",
            Data = json.encode({
                error = "Server not found"
            })
        })
    then
        return
    end
    server.publicServer = publicServer
    servers[serverId] = server

    SyncProcessState()
    msg.reply({
        Action = "Update-Server-Response",
        Status = "200",
        Data = json.encode(server)
    })
end)

-- users need to call this frist, before actually joining server
-- To prevent any server from listing themself on the users profile
-- User pre-approves a server join so servers cannot list themselves without consent
Handlers.add("Approve-Join-Server", function(msg)
    local userId = msg.From
    userId = GetOriginalId(userId)
    local serverId = VarOrNil(msg.Tags["Server-Id"])

    local profile = GetProfile(userId)
    if ValidateCondition(not profile, msg, {
            Status = "404",
            Data = json.encode({
                error = "Profile not found"
            })
        })
    then
        return
    end

    if ValidateCondition(not serverId, msg, {
            Status = "400",
            Data = json.encode({
                error = "ServerId is required"
            })
        })
    then
        return
    end

    if ValidateCondition(not ServerExists(serverId), msg, {
            Status = "404",
            Data = json.encode({
                error = "Server not found"
            })
        })
    then
        return
    end

    profile.serversJoined[tostring(serverId)] = {
        orderId = GetNextServerOrderId(profile),
        serverApproved = false -- Show the user this server only when serverApproves the join request
    }

    profiles[userId] = profile

    SyncProcessState()
    msg.reply({
        Action = "Approve-Join-Server-Response",
        Status = "200",
        Data = json.encode(profile)
    })
end)

-- Handler for when a server notifies us that a user has joined
-- Server confirms a user joined; flips serverApproved flag in profile
Handlers.add("User-Joined-Server", function(msg)
    local serverId = msg.From
    local userId = VarOrNil(msg.Tags["User-Id"])
    local serverApproved = (VarOrNil(msg.Tags["Server-Approved"]) == "true") -- bool

    -- Validate that the message comes from a known server
    if ValidateCondition(not ServerExists(serverId), msg, {
            Status = "404",
            Data = json.encode({
                error = "Server not found"
            })
        })
    then
        return
    end

    if ValidateCondition(not userId, msg, {
            Status = "400",
            Data = json.encode({
                error = "UserId is required"
            })
        })
    then
        return
    end

    userId = GetOriginalId(userId)
    local profile = GetProfile(userId)

    -- Check if user has approved the join request
    if not profile.serversJoined[tostring(serverId)] then
        msg.reply({
            Action = "User-Joined-Server-Response",
            Status = "400",
            Data = json.encode({
                error = "User has not approved the join request"
            })
        })
        return
    end
    if ValidateCondition(not serverApproved, msg, {
            Status = "400",
            Data = json.encode({
                error = "Server has not approved the join request"
            })
        })
    then
        profile.serversJoined[tostring(serverId)] = nil
        profiles[userId] = profile
        return
    end

    profile.serversJoined[tostring(serverId)].serverApproved = serverApproved
    profiles[userId] = profile

    -- Resequence to ensure clean ordering
    ResequenceUserServers(userId)

    SyncProcessState()
    msg.reply({
        Action = "User-Joined-Server-Response",
        Status = "200",
        Data = json.encode({
            message = "User added to server"
        })
    })
end)

-- Handler for when a server notifies us that a user has left
-- Server confirms a user left; removes from profile and resequences order
Handlers.add("User-Left-Server", function(msg)
    local serverId = msg.From
    local userId = VarOrNil(msg.Tags["User-Id"])
    local reason = VarOrNil(msg.Tags.Reason) -- "left", "kicked", "banned"

    -- Validate that the message comes from a known server
    if ValidateCondition(not ServerExists(serverId), msg, {
            Status = "404",
            Data = json.encode({
                error = "Server not found"
            })
        })
    then
        return
    end

    if ValidateCondition(not userId, msg, {
            Status = "400",
            Data = json.encode({
                error = "UserId is required"
            })
        })
    then
        return
    end

    userId = GetOriginalId(userId)

    -- Check if user is actually in the server
    if not UserInServer(userId, serverId) then
        msg.reply({
            Action = "User-Left-Server-Response",
            Status = "200",
            Data = json.encode({
                message = "User was not in server"
            })
        })
        return
    end

    -- SQLWrite("DELETE FROM serversJoined WHERE userId = ? AND serverId = ?", userId, serverId)
    profiles[userId].serversJoined[tostring(serverId)] = nil

    -- Resequence to ensure clean ordering after removal
    ResequenceUserServers(userId)

    SyncProcessState()
    msg.reply({
        Action = "User-Left-Server-Response",
        Status = "200",
        Data = json.encode({
            message = "User removed from server",
            reason = reason or "left"
        })
    })
end)

-- Reorder a server in the user’s sidebar; maintains a contiguous sequence
Handlers.add("Update-Server-Order", function(msg)
    local userId = msg.From
    userId = GetOriginalId(userId)
    local serverId = VarOrNil(msg.Tags["Server-Id"])
    local orderId = VarOrNil(msg.Tags["Order-Id"])

    if orderId then orderId = tonumber(orderId) end

    local profile = GetProfile(userId)
    if ValidateCondition(not profile, msg, {
            Status = "404",
            Data = json.encode({
                error = "Profile not found"
            })
        })
    then
        return
    end

    if ValidateCondition(not serverId, msg, {
            Status = "400",
            Data = json.encode({
                error = "ServerId is required"
            })
        })
    then
        return
    end

    if ValidateCondition(not orderId, msg, {
            Status = "400",
            Data = json.encode({
                error = "OrderId is required"
            })
        })
    then
        return
    end

    if ValidateCondition(not ServerExists(serverId), msg, {
            Status = "404",
            Data = json.encode({
                error = "Server not found"
            })
        })
    then
        return
    end

    if ValidateCondition(not UserInServer(userId, serverId), msg, {
            Status = "400",
            Data = json.encode({
                error = "User not in server"
            })
        })
    then
        return
    end

    -- Get current server order info
    -- local currentServerInfo = SQLRead("SELECT orderId FROM serversJoined WHERE userId = ? AND serverId = ?", userId,
    --     serverId)[1]
    local currentServerInfo = profiles[userId].serversJoined[tostring(serverId)]

    if ValidateCondition(not currentServerInfo, msg, {
            Status = "500",
            Data = json.encode({
                error = "Failed to get current server order"
            })
        })
    then
        return
    end

    local currentOrder = currentServerInfo.orderId

    -- If no change in order, just return success
    if orderId == currentOrder then
        msg.reply({
            Action = "Update-Server-Order-Response",
            Status = "200",
            Data = json.encode({
                message = "Server order unchanged"
            })
        })
        return
    end

    -- Begin transaction for atomic updates
    -- db:exec("BEGIN TRANSACTION")
    -- local success = true

    -- -- Handle ordering changes
    -- if orderId < currentOrder then
    --     -- Moving up: shift other servers down
    --     SQLWrite([[
    --         UPDATE serversJoined
    --         SET orderId = orderId + 1
    --         WHERE userId = ? AND orderId >= ? AND orderId < ? AND serverId != ?
    --     ]], userId, orderId, currentOrder, serverId)
    -- else
    --     -- Moving down: shift other servers up
    --     SQLWrite([[
    --         UPDATE serversJoined
    --         SET orderId = orderId - 1
    --         WHERE userId = ? AND orderId > ? AND orderId <= ? AND serverId != ?
    --     ]], userId, currentOrder, orderId, serverId)
    -- end

    -- -- Update the server's order
    -- local rows = SQLWrite([[
    --     UPDATE serversJoined
    --     SET orderId = ?
    --     WHERE userId = ? AND serverId = ?
    -- ]], orderId, userId, serverId)

    -- if rows ~= 1 then
    --     success = false
    -- end

    for serverId_, server in pairs(profiles[userId].serversJoined) do
        if serverId_ == tostring(serverId) then
            server.orderId = orderId
            profiles[userId].serversJoined[serverId_] = server
        end
        if server.orderId >= orderId and server.orderId < currentOrder then
            server.orderId = server.orderId + 1
            profiles[userId].serversJoined[serverId_] = server
        elseif server.orderId > orderId and server.orderId <= currentOrder then
            server.orderId = server.orderId - 1
            profiles[userId].serversJoined[serverId_] = server
        end
    end

    -- Resequence to ensure clean ordering
    ResequenceUserServers(userId)

    -- Get updated profile
    local updatedProfile = GetProfile(userId)
    SyncProcessState()
    msg.reply({
        Action = "Update-Server-Order-Response",
        Status = "200",
        Data = json.encode(updatedProfile)
    })
end)



----------------------------------------------------------------------------
--- FRIENDS

-- Helper function to check if two users are friends
function IsFriend(userId1, userId2)
    -- local result = SQLRead(
    --     "SELECT * FROM friends WHERE ((senderId = ? AND receiverId = ?) OR (senderId = ? AND receiverId = ?)) AND accepted = 1",
    --     userId1, userId2, userId2, userId1)
    local p1 = GetProfile(userId1)
    local p2 = GetProfile(userId2)
    return p1 and p2 and (p1.friends.accepted[userId2] and p2.friends.accepted[userId1])
end

-- Helper function to check if a friend request exists
function FriendRequestExists(senderId, receiverId)
    -- local result = SQLRead(
    --     "SELECT * FROM friends WHERE senderId = ? AND receiverId = ?",
    --     senderId, receiverId)
    -- return #result > 0
    local p1 = GetProfile(senderId)
    local p2 = GetProfile(receiverId)
    return p1 and p2 and
        ((p1.friends.sent[receiverId] and p2.friends.received[senderId]) or (p1.friends.received[receiverId] and p2.friends.sent[senderId]))
end

-- Helper function to check if there's a pending friend request
function HasPendingFriendRequest(senderId, receiverId)
    -- local result = SQLRead(
    --     "SELECT * FROM friends WHERE senderId = ? AND receiverId = ? AND accepted = 0",
    --     senderId, receiverId)
    -- return #result > 0
    local p1 = GetProfile(senderId)
    local p2 = GetProfile(receiverId)
    -- Pending exists if sender has sent to receiver AND receiver has not accepted yet (they should have it in received)
    return p1 and p2 and (p1.friends.sent[receiverId] and p2.friends.received[senderId])
end

-- Helper function to send a friend request
function SendFriendRequest(senderId, receiverId)
    -- SQLWrite("INSERT OR IGNORE INTO friends (senderId, receiverId, accepted) VALUES (?, ?, 0)",
    --     senderId, receiverId)
    local p1 = GetProfile(senderId)
    local p2 = GetProfile(receiverId)
    if p1 and p2 then
        p1.friends.sent[receiverId] = true
        p2.friends.received[senderId] = true
    end
end

-- Helper function to accept a friend request
function AcceptFriendRequest(senderId, receiverId)
    -- SQLWrite("UPDATE friends SET accepted = 1 WHERE senderId = ? AND receiverId = ?", senderId, receiverId)
    local p1 = GetProfile(senderId)
    local p2 = GetProfile(receiverId)

    if p1 and p2 then
        -- check if a friend request was made before accepting
        if not p1.friends.sent[receiverId] or not p2.friends.received[senderId] then
            return
        end
        p1.friends.accepted[receiverId] = true
        p1.friends.sent[receiverId] = nil
        p2.friends.accepted[senderId] = true
        p2.friends.received[senderId] = nil
    end
end

-- Helper function to reject/remove a friend request
function RejectFriendRequest(senderId, receiverId)
    -- SQLWrite("DELETE FROM friends WHERE senderId = ? AND receiverId = ?", senderId, receiverId)
    local p1 = GetProfile(senderId)
    local p2 = GetProfile(receiverId)
    if p1 and p2 then
        p1.friends.sent[receiverId] = nil
        p2.friends.received[senderId] = nil
    end
end

-- Helper function to remove a friendship (both directions)
function RemoveFriend(userId1, userId2)
    -- SQLWrite("DELETE FROM friends WHERE (senderId = ? AND receiverId = ?) OR (senderId = ? AND receiverId = ?)",
    --     userId1, userId2, userId2, userId1)
    local p1 = GetProfile(userId1)
    local p2 = GetProfile(userId2)
    if p1 and p2 then
        p1.friends.accepted[userId2] = nil
        p2.friends.accepted[userId1] = nil
    end
end

-- Helper function to get all friends of a user
function GetUserFriends(userId)
    -- local result = SQLRead([[
    --     SELECT CASE
    --         WHEN senderId = ? THEN receiverId
    --         ELSE senderId
    --     END AS friendId
    --     FROM friends
    --     WHERE (senderId = ? OR receiverId = ?) AND accepted = 1
    -- ]], userId, userId, userId)
    -- return result
    local profile = GetProfile(userId)
    if profile then
        return profile.friends.accepted
    end
    return {}
end

-- Helper function to get pending friend requests received by a user
function GetFriendRequestsReceived(userId)
    -- local result = SQLRead("SELECT * FROM friends WHERE receiverId = ? AND accepted = 0", userId)
    -- return result
    local profile = GetProfile(userId)
    if profile then
        return profile.friends.received
    end
    return {}
end

-- Helper function to get pending friend requests sent by a user
function GetFriendRequestsSent(userId)
    -- local result = SQLRead("SELECT * FROM friends WHERE senderId = ? AND accepted = 0", userId)
    -- return result
    local profile = GetProfile(userId)
    if profile then
        return profile.friends.sent
    end
    return {}
end

-- Send a friend request; auto-accept if a reverse pending exists
Handlers.add("Add-Friend", function(msg)
    local senderId = msg.From
    senderId = GetOriginalId(senderId)
    local receiverId = VarOrNil(msg.Tags["Friend-Id"])

    if ValidateCondition(not receiverId, msg, {
            Status = "400",
            Data = json.encode({
                error = "FriendId is required"
            })
        }) then
        return
    end

    receiverId = GetOriginalId(receiverId)

    -- Check if sender profile exists
    local senderProfile = GetProfile(senderId)
    if ValidateCondition(not senderProfile, msg, {
            Status = "404",
            Data = json.encode({
                error = "Sender profile not found"
            })
        }) then
        return
    end

    -- Check if receiver profile exists
    local receiverProfile = GetProfile(receiverId)
    if ValidateCondition(not receiverProfile, msg, {
            Status = "404",
            Data = json.encode({
                error = "Friend profile not found"
            })
        }) then
        return
    end

    -- Check if trying to friend themselves
    if ValidateCondition(senderId == receiverId, msg, {
            Status = "400",
            Data = json.encode({
                error = "Cannot send friend request to yourself"
            })
        }) then
        return
    end

    -- Check if already friends
    if ValidateCondition(IsFriend(senderId, receiverId), msg, {
            Status = "400",
            Data = json.encode({
                error = "Already friends"
            })
        }) then
        return
    end

    -- Check if friend request already exists
    if ValidateCondition(FriendRequestExists(senderId, receiverId), msg, {
            Status = "400",
            Data = json.encode({
                error = "Friend request already sent"
            })
        }) then
        return
    end

    -- Check if there's a reverse friend request (they sent us a request)
    if HasPendingFriendRequest(receiverId, senderId) then
        -- Auto-accept the reverse request to become friends immediately
        AcceptFriendRequest(receiverId, senderId)
        msg.reply({
            Action = "Add-Friend-Response",
            Status = "200",
            Data = json.encode({
                message = "Friend request accepted automatically - you are now friends"
            })
        })
    else
        -- Send new friend request
        SendFriendRequest(senderId, receiverId)
        msg.reply({
            Action = "Add-Friend-Response",
            Status = "200",
            Data = json.encode({
                message = "Friend request sent"
            })
        })
    end
    SyncProcessState()
end)

-- Remove an existing friendship
Handlers.add("Remove-Friend", function(msg)
    local userId = msg.From
    userId = GetOriginalId(userId)
    local friendId = VarOrNil(msg.Tags["Friend-Id"])

    if ValidateCondition(not friendId, msg, {
            Status = "400",
            Data = json.encode({
                error = "FriendId is required"
            })
        }) then
        return
    end

    friendId = GetOriginalId(friendId)

    -- Check if user profile exists
    local userProfile = GetProfile(userId)
    if ValidateCondition(not userProfile, msg, {
            Status = "404",
            Data = json.encode({
                error = "User profile not found"
            })
        }) then
        return
    end

    -- Check if friend profile exists
    local friendProfile = GetProfile(friendId)
    if ValidateCondition(not friendProfile, msg, {
            Status = "404",
            Data = json.encode({
                error = "Friend profile not found"
            })
        }) then
        return
    end

    -- Check if they are actually friends
    if ValidateCondition(not IsFriend(userId, friendId), msg, {
            Status = "400",
            Data = json.encode({
                error = "Not friends with this user"
            })
        }) then
        return
    end

    -- Remove the friendship
    RemoveFriend(userId, friendId)

    msg.reply({
        Action = "Remove-Friend-Response",
        Status = "200",
        Data = json.encode({
            message = "Friend removed successfully"
        })
    })
    SyncProcessState()
end)

-- Accept a pending friend request
Handlers.add("Accept-Friend", function(msg)
    local receiverId = msg.From
    receiverId = GetOriginalId(receiverId)
    local senderId = VarOrNil(msg.Tags["Friend-Id"])

    if ValidateCondition(not senderId, msg, {
            Status = "400",
            Data = json.encode({
                error = "FriendId is required"
            })
        }) then
        return
    end

    senderId = GetOriginalId(senderId)

    -- Check if receiver profile exists
    local receiverProfile = GetProfile(receiverId)
    if ValidateCondition(not receiverProfile, msg, {
            Status = "404",
            Data = json.encode({
                error = "User profile not found"
            })
        }) then
        return
    end

    -- Check if sender profile exists
    local senderProfile = GetProfile(senderId)
    if ValidateCondition(not senderProfile, msg, {
            Status = "404",
            Data = json.encode({
                error = "Friend profile not found"
            })
        }) then
        return
    end

    -- Check if there's a pending friend request to accept
    if ValidateCondition(not HasPendingFriendRequest(senderId, receiverId), msg, {
            Status = "400",
            Data = json.encode({
                error = "No pending friend request found from this user"
            })
        }) then
        return
    end

    -- Accept the friend request
    AcceptFriendRequest(senderId, receiverId)

    msg.reply({
        Action = "Accept-Friend-Response",
        Status = "200",
        Data = json.encode({
            message = "Friend request accepted - you are now friends"
        })
    })
    SyncProcessState()
end)

-- Reject a pending friend request
Handlers.add("Reject-Friend", function(msg)
    local receiverId = msg.From
    receiverId = GetOriginalId(receiverId)
    local senderId = VarOrNil(msg.Tags["Friend-Id"])

    if ValidateCondition(not senderId, msg, {
            Status = "400",
            Data = json.encode({
                error = "FriendId is required"
            })
        }) then
        return
    end

    senderId = GetOriginalId(senderId)

    -- Check if receiver profile exists
    local receiverProfile = GetProfile(receiverId)
    if ValidateCondition(not receiverProfile, msg, {
            Status = "404",
            Data = json.encode({
                error = "User profile not found"
            })
        }) then
        return
    end

    -- Check if sender profile exists
    local senderProfile = GetProfile(senderId)
    if ValidateCondition(not senderProfile, msg, {
            Status = "404",
            Data = json.encode({
                error = "Friend profile not found"
            })
        }) then
        return
    end

    -- Check if there's a pending friend request to reject
    if ValidateCondition(not HasPendingFriendRequest(senderId, receiverId), msg, {
            Status = "400",
            Data = json.encode({
                error = "No pending friend request found from this user"
            })
        }) then
        return
    end

    -- Reject the friend request
    RejectFriendRequest(senderId, receiverId)

    SyncProcessState()
    msg.reply({
        Action = "Reject-Friend-Response",
        Status = "200",
        Data = json.encode({
            message = "Friend request rejected"
        })
    })
end)

----------------------------------------------------------------------------
--- DMs

-- example dm scenario:
-- A,B are friends
-- A -> Profile (Send-DM "Hi" to B)
-- Profile -> A (X-Origin = A)
-- Profile -> B (X-Origin = A)

-- Sending DMs only possible if they are friends
-- Forward a DM to both sender and recipient DM processes after validations
Handlers.add("Send-DM", function(msg)
    local senderId = msg.From
    senderId = GetOriginalId(senderId)
    local friendId = VarOrNil(msg.Tags["Friend-Id"])
    local content = VarOrNil(msg.Data) or ""
    local attachments = VarOrNil(msg.Tags.Attachments) or "[]"
    local replyTo = VarOrNil(msg.Tags["Reply-To"])

    if ValidateCondition(not friendId, msg, {
            Status = "400",
            Data = json.encode({
                error = "FriendId is required"
            })
        }) then
        return
    end

    friendId = GetOriginalId(friendId)

    local senderProfile = GetProfile(senderId)
    if ValidateCondition(not senderProfile, msg, {
            Status = "404",
            Data = json.encode({
                error = "Sender profile not found"
            })
        }) then
        return
    end

    local friendProfile = GetProfile(friendId)
    if ValidateCondition(not friendProfile, msg, {
            Status = "404",
            Data = json.encode({
                error = "Friend profile not found"
            })
        }) then
        return
    end

    -- Check if they are friends
    if ValidateCondition(not IsFriend(senderId, friendId), msg, {
            Status = "400",
            Data = json.encode({
                error = "Not friends with this user"
            })
        }) then
        return
    end

    -- Both users must have a dm process
    if ValidateCondition(not friendProfile.dmProcess, msg, {
            Status = "400",
            Data = json.encode({
                error = "Friend does not have a dm process"
            })
        }) then
        return
    end

    if ValidateCondition(not senderProfile.dmProcess, msg, {
            Status = "400",
            Data = json.encode({
                error = "You do not have a dm process"
            })
        }) then
        return
    end

    -- validate inputs
    if #content == 0 then
        -- should be atleast 1 attachment if content is empty
        local _attachments = json.decode(attachments)
        if ValidateCondition(#_attachments == 0, msg, {
                Status = "400",
                Data = json.encode({
                    error = "Atleast 1 attachment is required if content is empty"
                })
            }) then
            return
        end
    end

    -- Send the DM
    msg.forward(friendProfile.dmProcess, { ["X-Origin"] = senderId, ["X-Origin-Id"] = msg.Id })
    msg.forward(senderProfile.dmProcess, { ["X-Origin"] = senderId, ["X-Origin-Id"] = msg.Id })

    SyncProcessState()
    msg.reply({
        Action = "Send-DM-Response",
        Status = "200",
        Data = msg.Id
    })
end)

-- Forward a delete request to both DM processes
Handlers.add("Delete-DM", function(msg)
    local senderId = msg.From
    senderId = GetOriginalId(senderId)
    local messageId = VarOrNil(msg.Tags["Message-Id"])
    local friendId = VarOrNil(msg.Tags["Friend-Id"])

    if ValidateCondition(not messageId, msg, {
            Status = "400",
            Data = json.encode({
                error = "MessageId is required"
            })
        }) then
        return
    end

    if ValidateCondition(not friendId, msg, {
            Status = "400",
            Data = json.encode({
                error = "FriendId is required"
            })
        }) then
        return
    end

    friendId = GetOriginalId(friendId)

    local senderProfile = GetProfile(senderId)
    if ValidateCondition(not senderProfile, msg, {
            Status = "404",
            Data = json.encode({
                error = "Sender profile not found"
            })
        }) then
        return
    end

    local friendProfile = GetProfile(friendId)
    if ValidateCondition(not friendProfile, msg, {
            Status = "404",
            Data = json.encode({
                error = "Friend profile not found"
            })
        }) then
        return
    end

    msg.forward(senderProfile.dmProcess, { ["X-Origin"] = senderId, ["X-Origin-Id"] = msg.Id })
    msg.forward(friendProfile.dmProcess, { ["X-Origin"] = senderId, ["X-Origin-Id"] = msg.Id })


    SyncProcessState()
    msg.reply({
        Action = "Delete-DM-Response",
        Status = "200",
        Data = msg.Id
    })
end)

-- Forward an edit request to both DM processes
Handlers.add("Edit-DM", function(msg)
    local senderId = msg.From
    senderId = GetOriginalId(senderId)
    local messageId = VarOrNil(msg.Tags["Message-Id"])
    local friendId = VarOrNil(msg.Tags["Friend-Id"])
    local content = VarOrNil(msg.Data)

    if ValidateCondition(not messageId, msg, {
            Status = "400",
            Data = json.encode({
                error = "MessageId is required"
            })
        }) then
        return
    end

    if ValidateCondition(not friendId, msg, {
            Status = "400",
            Data = json.encode({
                error = "FriendId is required"
            })
        }) then
        return
    end

    friendId = GetOriginalId(friendId)

    local senderProfile = GetProfile(senderId)
    if ValidateCondition(not senderProfile, msg, {
            Status = "404",
            Data = json.encode({
                error = "Sender profile not found"
            })
        }) then
        return
    end

    local friendProfile = GetProfile(friendId)
    if ValidateCondition(not friendProfile, msg, {
            Status = "404",
            Data = json.encode({
                error = "Friend profile not found"
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

    msg.forward(senderProfile.dmProcess, { ["X-Origin"] = senderId, ["X-Origin-Id"] = msg.Id })
    msg.forward(friendProfile.dmProcess, { ["X-Origin"] = senderId, ["X-Origin-Id"] = msg.Id })

    SyncProcessState()
    msg.reply({
        Action = "Edit-DM-Response",
        Status = "200",
        Data = msg.Id
    })
end)

----------------------------------------------------------------------------
--- NOTIFICATIONS

-- Handlers.add("Get-Notifications", function(msg)
--     local userId = VarOrNil(msg.Tags.UserId) or msg.From
--     userId = GetOriginalId(userId)

--     local profile = GetProfile(userId)
--     if ValidateCondition(not profile, msg, {
--             Status = "404",
--             Data = json.encode({
--                 error = "Profile not found"
--             })
--         }) then
--         return
--     end

--     -- local notifications = SQLRead("SELECT * FROM notifications WHERE forUserId = ? ORDER BY notificationId DESC", userId)
--     local notifications = profiles[userId].notifications
--     msg.reply({
--         Action = "Get-Notifications-Response",
--         Status = "200",
--         Data = json.encode(notifications)
--     })
-- end)

-- Helper to get next incremental notification id for a user, regardless of sparse deletions
-- Generate a per-user incremental notification id
local function GetNextNotificationId(forUserId)
    local profile = GetProfile(forUserId)
    if not profile then return 1 end
    profile.nextNotificationId = tonumber(profile.nextNotificationId) or 1
    local id = profile.nextNotificationId
    profile.nextNotificationId = id + 1
    return id
end

-- Create a notification for a user (SERVER or DM source) after validations
Handlers.add("Add-Notification", function(msg)
    local serverOrDmId = VarOrNil(msg.From)
    local fromUserId = VarOrNil(msg.Tags["From-User-Id"])
    local forUserId = VarOrNil(msg.Tags["For-User-Id"])
    local timestamp = VarOrNil(msg.Timestamp)
    local source = VarOrNil(msg.Tags.Source) -- Server / DM
    local messageTxId = VarOrNil(msg.Tags["Message-Tx-Id"])
    -- if source = Server
    local channelId = VarOrNil(msg.Tags["Channel-Id"])
    local serverName = VarOrNil(msg.Tags["Server-Name"])
    local channelName = VarOrNil(msg.Tags["Channel-Name"])
    -- optionals
    local authorName = VarOrNil(msg.Tags["Author-Name"])

    if source == "SERVER" then
        -- validate server exists
        if ValidateCondition(not ServerExists(serverOrDmId), msg, {
                Status = "404",
                Data = json.encode({
                    error = "Server not found"
                })
            }) then
            return
        end

        -- validate sender is in server
        if ValidateCondition(not UserInServer(fromUserId, serverOrDmId), msg, {
                Status = "400",
                Data = json.encode({
                    error = "Sender not in server"
                })
            }) then
            return
        end

        -- validate user is in server
        if ValidateCondition(not UserInServer(forUserId, serverOrDmId), msg, {
                Status = "400",
                Data = json.encode({
                    error = "User not in server"
                })
            }) then
            return
        end
    end

    if source == "DM" then
        -- validate dm process exists
        local recipient = GetProfile(forUserId)
        if ValidateCondition(not recipient or not recipient.dmProcess, msg, {
                Status = "404",
                Data = json.encode({
                    error = "Recipient does not have a dm process"
                })
            }) then
            return
        end

        -- validate dm process belongs to correct user
        if ValidateCondition(recipient.dmProcess ~= serverOrDmId, msg, {
                Status = "400",
                Data = json.encode({
                    error = "Recipient's dm process does not belong to the correct user"
                })
            }) then
            return
        end

        -- validate that the sender is a friend of the recipient
        if ValidateCondition(not IsFriend(fromUserId, forUserId), msg, {
                Status = "400",
                Data = json.encode({
                    error = "Sender is not a friend of the recipient"
                })
            }) then
            return
        end
    end

    -- local rows = SQLWrite(
    --     "INSERT INTO notifications (serverOrDmId, fromUserId, forUserId, timestamp, source, channelId, serverName, channelName, authorName, messageTxId) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
    --     serverOrDmId, fromUserId, forUserId, timestamp, source, channelId, serverName, channelName, authorName,
    --     messageTxId
    -- )
    profiles[forUserId].notifications = profiles[forUserId].notifications or {}
    local notificationId = GetNextNotificationId(forUserId)
    profiles[forUserId].notifications[notificationId] = {
        serverOrDmId = serverOrDmId,
        fromUserId = fromUserId,
        forUserId = forUserId,
        timestamp = timestamp,
        source = source,
        channelId = channelId,
        serverName = serverName,
        channelName = channelName,
        authorName = authorName,
        messageTxId = messageTxId,
        notificationId = notificationId
    }
    msg.reply({
        Action = "Add-Notification-Response",
        Status = "200",
        Data = json.encode({
            message = "Notification added"
        })
    })
    SyncProcessState()
end)

-- Delete a single notification
Handlers.add("Mark-Read", function(msg)
    local userId = msg.From
    userId = GetOriginalId(userId)
    local notificationId = VarOrNil(msg.Tags.NotificationId)

    local profile = GetProfile(userId)
    if ValidateCondition(not profile, msg, {
            Status = "404",
            Data = json.encode({
                error = "Profile not found"
            })
        }) then
        return
    end

    if ValidateCondition(not notificationId, msg, {
            Status = "400",
            Data = json.encode({
                error = "NotificationId is required"
            })
        }) then
        return
    end

    -- local notification = SQLRead("SELECT * FROM notifications WHERE notificationId = ? AND forUserId = ?", notificationId,
    --     userId)[1]
    profiles[userId].notifications = profiles[userId].notifications or {}
    local notification = profiles[userId].notifications[notificationId]
    if ValidateCondition(not notification, msg, {
            Status = "404",
            Data = json.encode({
                error = "Notification not found"
            })
        }) then
        return
    end

    -- delete notification from notifications table
    -- SQLWrite("DELETE FROM notifications WHERE notificationId = ? AND forUserId = ?", notificationId, userId)
    profiles[userId].notifications[notificationId] = nil

    msg.reply({
        Action = "Mark-Read-Response",
        Status = "200",
        Data = json.encode(profile)
    })
    SyncProcessState()
end)

-- Delete all notifications for a user
Handlers.add("Mark-All-Read", function(msg)
    local userId = msg.From
    userId = GetOriginalId(userId)

    local profile = GetProfile(userId)
    if ValidateCondition(not profile, msg, {
            Status = "404",
            Data = json.encode({
                error = "Profile not found"
            })
        }) then
        return
    end

    -- SQLWrite("DELETE FROM notifications WHERE forUserId = ?", userId)
    profiles[userId].notifications = {}

    msg.reply({
        Action = "Mark-All-Read-Response",
        Status = "200",
        Data = json.encode(profile)
    })
    SyncProcessState()
end)

----------------------------------------------------------------------------
-- BOTS

Handlers.add("Create-Bot", function(msg)
    local userId = msg.From
    userId = GetOriginalId(userId)
    local botProcess = VarOrNil(msg.Tags.BotProcess)
    local publicBot = VarOrNil(msg.Tags.PublicBot)
    publicBot = (publicBot == "true")
    local botName = VarOrNil(msg.Tags.Name)
    local botPfp = VarOrNil(msg.Tags.Pfp)

    if ValidateCondition(not botProcess or #botProcess ~= 43, msg, {
            Status = "400",
            Data = json.encode({
                error = "BotProcess is required and must be a valid process id"
            })
        })
    then
        return
    end

    local profile = GetProfile(userId)
    if ValidateCondition(not profile, msg, {
            Status = "404",
            Data = json.encode({
                error = "Profile not found"
            })
        })
    then
        return
    end

    -- if publicBot then
    --     publicBot = (publicBot == "true")
    -- else
    --     publicBot = true
    -- end


    -- SQLWrite("INSERT INTO bots (userId, botProcess, botName, botPfp, botPublic) VALUES (?, ?, ?, ?, ?)", userId,
    --     botProcess, botName, botPfp, publicBot)
    bots[botProcess] = {
        userId = userId,
        botProcess = botProcess,
        botName = botName,
        botPfp = botPfp,
        botPublic = publicBot,
        servers = {}
    }

    msg.reply({
        Action = "Create-Bot-Response",
        Status = "200",
        BotProcess = botProcess
    })
    SyncProcessState()
end)

Handlers.add("Update-Bot", function(msg)
    local userId = msg.From
    userId = GetOriginalId(userId)
    local botId = VarOrNil(msg.Tags.BotProcess)
    local publicBot = VarOrNil(msg.Tags.PublicBot)

    if ValidateCondition(not botId, msg, {
            Status = "400",
            Data = json.encode({
                error = "BotProcess is required"
            })
        })
    then
        return
    end

    -- Check if user profile exists
    local profile = GetProfile(userId)
    if ValidateCondition(not profile, msg, {
            Status = "404",
            Data = json.encode({
                error = "Profile not found"
            })
        })
    then
        return
    end

    -- Check if bot exists and user is the owner
    -- local bot = SQLRead("SELECT * FROM bots WHERE botProcess = ?", botId)[1]
    local bot = bots[botId]
    if ValidateCondition(not bot, msg, {
            Status = "404",
            Data = json.encode({
                error = "Bot not found"
            })
        })
    then
        return
    end

    if ValidateCondition(bot.userId ~= userId, msg, {
            Status = "403",
            Data = json.encode({
                error = "You are not the owner of this bot"
            })
        })
    then
        return
    end

    if publicBot then
        publicBot = (publicBot == "true")
    end

    local name = VarOrNil(msg.Tags.Name)
    local pfp = VarOrNil(msg.Tags.Pfp)

    ao.send({
        Target = botId,
        Action = "Update-Bot",
        Tags = {
            PublicBot = tostring(publicBot),
            Name = name,
            Pfp = pfp
        }
    })

    local updateResponse = Receive({ Action = "Update-Bot-Response", From = botId })
    if ValidateCondition(updateResponse.Status ~= "200", msg, {
            Status = "500",
            Data = json.encode(updateResponse.Data)
        }) then
        return
    end

    -- update bot in bots table
    -- SQLWrite("UPDATE bots SET botPublic = ?, botName = ?, botPfp = ? WHERE botProcess = ?", publicBot, name, pfp, botId)
    bots[botId].botPublic = publicBot or bots[botId].botPublic
    bots[botId].botName = name or bots[botId].botName
    bots[botId].botPfp = pfp or bots[botId].botPfp

    msg.reply({
        Action = "Update-Bot-Response",
        Status = "200",
    })
    SyncProcessState()
end)

-- Handlers.add("Bot-Info", function(msg)
--     local botProcess = VarOrNil(msg.Tags.BotProcess)

--     if ValidateCondition(not botProcess, msg, {
--             Status = "400",
--             Data = json.encode({
--                 error = "BotProcess is required"
--             })
--         })
--     then
--         return
--     end

--     -- local bot = SQLRead("SELECT * FROM bots WHERE botProcess = ?", botProcess)[1]
--     local bot = bots[botProcess]
--     if ValidateCondition(not bot, msg, {
--             Status = "404",
--             Data = json.encode({
--                 error = "Bot not found"
--             })
--         })
--     then
--         return
--     end

--     -- fetch number of servers the bot is in
--     -- local totalServers = SQLRead("SELECT COUNT(*) FROM serversJoined WHERE botProcess = ?", botProcess)[1]
--     local totalServers = #bot.servers
--     bot.totalServers = totalServers

--     msg.reply({
--         Action = "Bot-Info-Response",
--         Status = "200",
--         Data = json.encode(bot)
--     })
-- end)

Handlers.add("Add-Bot", function(msg)
    local userId = msg.From
    userId = GetOriginalId(userId)
    local botProcess = VarOrNil(msg.Tags.BotProcess)
    local serverId = VarOrNil(msg.Tags["Server-Id"])

    if ValidateCondition(not botProcess, msg, {
            Status = "400",
            Data = json.encode({
                error = "BotProcess is required"
            })
        })
    then
        return
    end

    if ValidateCondition(not serverId, msg, {
            Status = "400",
            Data = json.encode({
                error = "ServerId is required"
            })
        })
    then
        return
    end

    if ValidateCondition(not ServerExists(serverId), msg, {
            Status = "404",
            Data = json.encode({
                error = "Server not found"
            })
        })
    then
        return
    end

    local profile = GetProfile(userId)
    if ValidateCondition(not profile, msg, {
            Status = "404",
            Data = json.encode({
                error = "Profile not found"
            })
        })
    then
        return
    end

    -- local bot = SQLRead("SELECT * FROM bots WHERE botProcess = ?", botProcess)[1]
    local bot = bots[botProcess]
    if ValidateCondition(not bot, msg, {
            Status = "404",
            Data = json.encode({
                error = "Bot not found"
            })
        })
    then
        return
    end

    msg.forward(serverId)
    msg.reply({
        Action = "Add-Bot-Response",
        Status = "200",
        Data = json.encode({
            message = "Bot add request sent to server"
        })
    })

    local addResponse = Receive({ Action = "Add-Bot-Response", From = serverId })
    if ValidateCondition(addResponse.Status ~= "200", msg, {
            Status = "500",
            Data = json.encode(addResponse.Data)
        }) then
        return
    end

    -- send message to bot to join server
    ao.send({
        Target = botProcess,
        Action = "Join-Server",
        Tags = { ServerId = serverId }
    })
    local joinResponse = Receive({ Action = "Join-Server-Response", From = botProcess })
    if ValidateCondition(joinResponse.Status ~= "200", msg, {
            Status = "500",
            Data = json.encode(joinResponse.Data)
        }) then
        return
    end

    -- add bot to serversJoined table
    -- SQLWrite("INSERT INTO botServers (botProcess, serverId) VALUES (?, ?)", botProcess, serverId)
    bot.servers[serverId] = true
    ao.send({
        Target = serverId,
        Action = "Approve-Add-Bot",
        Tags = {
            BotProcess = botProcess
        }
    })
    local approveResponse = Receive({ Action = "Approve-Add-Bot-Response", From = serverId })
    if ValidateCondition(approveResponse.Status ~= "200", msg, {
            Status = "500",
            Data = json.encode(approveResponse.Data)
        }) then
        return
    end

    SyncProcessState()
    ao.send({
        Target = botProcess,
        Status = "200",
        Action = "Join-Server-Success",
    })
end)

Handlers.add("Remove-Bot", function(msg)
    local serverId = msg.From
    local botProcess = VarOrNil(msg.Tags.BotProcess)

    if ValidateCondition(not botProcess, msg, {
            Status = "400",
            Data = json.encode({
                error = "BotProcess is required"
            })
        })
    then
        return
    end

    -- remove bot from serversJoined table
    -- SQLWrite("DELETE FROM botServers WHERE botProcess = ? AND serverId = ?", botProcess, serverId)
    bots[botProcess].servers[serverId] = nil

    SyncProcessState()

    msg.reply({
        Action = "Remove-Bot-Response",
        Status = "200",
    })
end)
