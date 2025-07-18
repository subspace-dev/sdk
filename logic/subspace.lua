sqlite3 = require("lsqlite3")
json = require("json")

----------------------------------------------------------------------------
--- VARIABLES

Authority = "fcoN_xJeisVsPXA-trzVAuIiqO3ydLQxM-L4XbrQKzY"

Sources = {
    Bot = {
        Id = "RWv6wuTXNbY3mNlE1sWXC7ZRo7eHSAl_Pq0ogaClEa4",
        Version = "1.0.0"
    },
    Dm = {
        Id = "emOxhkORaBoT2ZKbhYMQHYyuJahugx7ohR-wNhjjR8Q",
        Version = "1.0.0"
    },
    Server = {
        Id = "rCTZTPzzAcqPf9VVOg3Khum-TIQ57PZpW5RJ8rRRbig",
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

db = db or sqlite3.open_memory()

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
    CREATE TABLE IF NOT EXISTS profiles (
        userId TEXT PRIMARY KEY,
        pfp TEXT DEFAULT "",
        dmProcess TEXT DEFAULT ""
    );

    CREATE TABLE IF NOT EXISTS serversJoined (
        userId TEXT NOT NULL,
        serverId TEXT NOT NULL,
        orderId INTEGER DEFAULT 0,
        PRIMARY KEY (userId, serverId)
    );

    CREATE TABLE IF NOT EXISTS friends (
        senderId TEXT NOT NULL,
        receiverId TEXT NOT NULL,
        accepted INTEGER DEFAULT 0,
        PRIMARY KEY (senderId, receiverId)
    );

    CREATE TABLE IF NOT EXISTS servers (
        serverId TEXT PRIMARY KEY,
        publicServer INTEGER DEFAULT 1,
        userId TEXT NOT NULL
    );

    CREATE TABLE IF NOT EXISTS notifications (
        notificationId INTEGER PRIMARY KEY AUTOINCREMENT,
        serverOrDmId TEXT NOT NULL,
        fromUserId TEXT NOT NULL,
        forUserId TEXT NOT NULL,
        timestamp INTEGER DEFAULT 0,
        source TEXT NOT NULL CHECK (source IN ('SERVER', 'DM')),
        channelId INTEGER,
        serverName TEXT,
        channelName TEXT,
        authorName TEXT,
        messageTxId TEXT,

        FOREIGN KEY (fromUserId) REFERENCES profiles(userId),
        FOREIGN KEY (forUserId) REFERENCES profiles(userId),
        CHECK (
            (source = 'SERVER' AND channelId IS NOT NULL) OR
            (source = 'DM' AND channelId IS NULL)
        )
    );

    CREATE TABLE IF NOT EXISTS delegations (
        userId TEXT NOT NULL,
        delegatedUserId TEXT NOT NULL,
        PRIMARY KEY (userId, delegatedUserId)
    );

    CREATE TABLE IF NOT EXISTS bots (
        userId TEXT NOT NULL,
        botProcess TEXT PRIMARY KEY,
        botName TEXT NOT NULL,
        botPfp TEXT NOT NULL,
        botPublic INTEGER DEFAULT 0,

        FOREIGN KEY (userId) REFERENCES profiles(userId)
    );

    CREATE TABLE IF NOT EXISTS botServers (
        botProcess TEXT NOT NULL,
        serverId TEXT NOT NULL,
        PRIMARY KEY (botProcess, serverId)

        FOREIGN KEY (botProcess) REFERENCES bots(botProcess)
        FOREIGN KEY (serverId) REFERENCES servers(serverId)
    );
]])

-- table helper functions

function GetProfile(userId)
    local profile = SQLRead("SELECT * FROM profiles WHERE userId = ?", userId)
    if profile and #profile > 0 then
        profile = profile[1]
        local servers = SQLRead("SELECT serverId,orderId FROM serversJoined WHERE userId = ? ORDER BY orderId ASC",
            userId)
        local delegations = SQLRead("SELECT * FROM delegations WHERE userId = ?", userId)

        local friendData = {
            accepted = {},
            sent = {},
            received = {}
        }
        -- Use the new friend helper functions to get organized friend data
        local acceptedFriends = GetUserFriends(userId)
        local friendRequestsReceived = GetFriendRequestsReceived(userId)
        local friendRequestsSent = GetFriendRequestsSent(userId)

        -- Extract just the friend IDs for the accepted friends
        local acceptedFriendIds = {}
        for _, friend in ipairs(acceptedFriends) do
            table.insert(acceptedFriendIds, friend.friendId)
        end
        friendData.accepted = acceptedFriendIds

        -- Extract sender IDs for received requests
        local receivedRequestIds = {}
        for _, request in ipairs(friendRequestsReceived) do
            table.insert(receivedRequestIds, request.senderId)
        end
        friendData.received = receivedRequestIds

        -- Extract receiver IDs for sent requests
        local sentRequestIds = {}
        for _, request in ipairs(friendRequestsSent) do
            table.insert(sentRequestIds, request.receiverId)
        end
        friendData.sent = sentRequestIds

        local delegationsData = {}
        for _, delegation in ipairs(delegations) do
            table.insert(delegationsData, delegation.delegatedUserId)
        end

        profile.serversJoined = servers
        profile.friends = friendData
        profile.delegations = delegationsData
        return profile
    else
        return nil
    end
end

function GetOriginalId(userId)
    -- userId can either be the originalId or the delegatedId
    -- always return the originalId
    -- a user can have multiple delegations
    local delegations = SQLRead("SELECT * FROM delegations WHERE delegatedUserId = ?", userId)
    if delegations and #delegations > 0 then
        return delegations[1].userId
    else
        return userId
    end
end

function ServerExists(serverId)
    local servers = SQLRead("SELECT * FROM servers WHERE serverId = ?", serverId)
    return servers and #servers > 0
end

function ServerIsPublic(serverId)
    local servers = SQLRead("SELECT * FROM servers WHERE serverId = ?", serverId)
    return servers and #servers > 0 and servers[1].publicServer == 1
end

function UserInServer(userId, serverId)
    if not userId or not serverId then
        return false
    end

    local servers = SQLRead("SELECT * FROM serversJoined WHERE userId = ? AND serverId = ?", userId, serverId)
    return servers and #servers > 0
end

-- Helper function to resequence servers for a specific user
function ResequenceUserServers(userId)
    local servers = SQLRead("SELECT serverId FROM serversJoined WHERE userId = ? ORDER BY orderId ASC", userId)

    -- Resequence starting from 1
    for i, server in ipairs(servers) do
        SQLWrite("UPDATE serversJoined SET orderId = ? WHERE userId = ? AND serverId = ?", i, userId, server.serverId)
    end

    return #servers
end

----------------------------------------------------------------------------

function GetFullState()
    local profiles = SQLRead("SELECT * FROM profiles")
    local servers = SQLRead("SELECT * FROM servers")
    local serversJoined = SQLRead("SELECT * FROM serversJoined")
    local friends = SQLRead("SELECT * FROM friends")
    local delegations = SQLRead("SELECT * FROM delegations")

    return {
        profiles = profiles,
        servers = servers,
        serversJoined = serversJoined,
        friends = friends,
        delegations = delegations
    }
end

----------------------------------------------------------------------------
--- PROFILES

Handlers.add("Create-Profile", function(msg)
    local userId = msg.From
    local dmProcess = VarOrNil(msg.Tags.DmProcess)

    -- check if profile already exists
    local profile = GetProfile(userId)
    if profile then
        msg.reply({
            Action = "Create-Profile-Response",
            Status = "400",
            Data = json.encode({
                error = "Profile already exists"
            })
        })
        return
    end

    -- verify if dm process is for the correct owner
    if dmProcess then
        if #dmProcess ~= 43 then
            msg.reply({
                Action = "Create-Profile-Response",
                Status = "400",
                Data = json.encode({
                    error = "Invalid dm process"
                })
            })
            return
        end

        Send({
            Target = dmProcess,
            Action = "Info",
        })
        local infoRes = Receive({ Action = "Info-Response", From = dmProcess })
        if infoRes.Status == "200" then
            if infoRes.Tags.Owner_ == userId then
                -- create profile
                SQLWrite("INSERT INTO profiles (userId, dmProcess) VALUES (?, ?)", userId, dmProcess)
            else
                msg.reply({
                    Action = "Create-Profile-Response",
                    Status = "400",
                    Data = json.encode({
                        error = "Invalid dm process or owner mismatch"
                    })
                })
                return
            end
        else
            msg.reply({
                Action = "Create-Profile-Response",
                Status = "400",
                Data = json.encode({
                    error = "Invalid dm process or owner mismatch"
                })
            })
            return
        end
    else
        msg.reply({
            Action = "Create-Profile-Response",
            Status = "400",
            Data = json.encode({
                error = "Invalid dm process or owner mismatch"
            })
        })
        return
    end
end)

Handlers.add("Get-Profile", function(msg)
    local userId = VarOrNil(msg.Tags.UserId) or msg.From
    userId = GetOriginalId(userId)

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

    msg.reply({
        Action = "Get-Profile-Response",
        Status = "200",
        Data = json.encode(profile)
    })
end)

Handlers.add("Get-Bulk-Profile", function(msg)
    local userIds = VarOrNil(msg.Tags.UserIds)
    if ValidateCondition(not userIds, msg, {
            Status = "400",
            Data = json.encode({
                error = "userIds is required"
            })
        })
    then
        return
    end

    userIds = json.decode(userIds)

    local profiles = {}
    for _, userId in ipairs(userIds) do
        local profile = GetProfile(userId)
        if profile then
            table.insert(profiles, profile)
        end
    end

    msg.reply({
        Action = "Get-Bulk-Profile-Response",
        Status = "200",
        Data = json.encode(profiles)
    })
end)

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
        SQLWrite("UPDATE profiles SET pfp = ? WHERE userId = ?", pfp, userId)
    end

    msg.reply({
        Action = "Update-Profile-Response",
        Status = "200",
        Data = json.encode(profile)
    })
end)

----------------------------------------------------------------------------
--- DELEGATIONS

Handlers.add("Get-Original-Id", function(msg)
    local userId = VarOrNil(msg.Tags.UserId)
    if ValidateCondition(not userId, msg, {
            Status = "400",
            Data = json.encode({
                error = "userId is required"
            })
        })
    then
        return
    end

    local originalId = GetOriginalId(userId)
    msg.reply({
        Action = "Get-Original-Id-Response",
        Status = "200",
        OriginalId = originalId
    })
end)

Handlers.add("Add-Delegation", function(msg)

end)

Handlers.add("Remove-Delegation", function(msg)

end)

Handlers.add("Remove-All-Delegations", function(msg)

end)


----------------------------------------------------------------------------
--- SERVER

Handlers.add("Create-Server", function(msg)
    local userId = msg.From
    userId = GetOriginalId(userId)
    local serverProcess = VarOrNil(msg.Tags.ServerProcess)

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

    -- verify if server process is for the correct owner
    if serverProcess then
        ao.send({
            Target = serverProcess,
            Action = "Info",
        })

        local infoRes = Receive({ Action = "Info-Response", From = serverProcess })
        if ValidateCondition(infoRes.Tags.Status ~= "200" or infoRes.Tags.Owner_ ~= userId, msg, {
                Status = "400",
                Data = json.encode({
                    error = "Invalid server process or owner mismatch"
                })
            })
        then
            return
        end
    end

    SQLWrite("INSERT INTO servers (serverId, userId) VALUES (?, ?)", serverProcess, userId)

    msg.reply({
        Action = "Create-Server-Response",
        Status = "200",
        ServerId = serverProcess
    })
end)

Handlers.add("Update-Server", function(msg)
    local serverId = msg.From
    local publicServer = VarOrNil(msg.Tags.PublicServer)

    if ValidateCondition(not ServerExists(serverId), msg, {
            Status = "404",
            Data = json.encode({
                error = "Server not found"
            })
        })
    then
        return
    end

    if publicServer then publicServer = (publicServer == "true") end
    if publicServer then
        publicServer = 1
    else
        publicServer = 0
    end

    SQLWrite("UPDATE servers SET publicServer = ? WHERE serverId = ?", publicServer, serverId)

    msg.reply({
        Action = "Update-Server-Response",
        Status = "200",
    })
end)

Handlers.add("Join-Server", function(msg)
    local userId = msg.From
    userId = GetOriginalId(userId)
    local serverId = msg.Tags.ServerId

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

    if ValidateCondition(not ServerExists(serverId), msg, {
            Status = "404",
            Data = json.encode({
                error = "Server not found"
            })
        })
    then
        return
    end

    if ValidateCondition(UserInServer(userId, serverId), msg, {
            Status = "400",
            Data = json.encode({
                error = "User already in server"
            })
        })
    then
        return
    end

    if ValidateCondition(not ServerIsPublic(serverId), msg, {
            Status = "400",
            Data = json.encode({
                error = "Server is not public, ask the server admins to update the server settings"
            })
        })
    then
        return
    end

    -- Get the current max order for the user's servers and place new server at the end
    local maxOrderResult = SQLRead("SELECT MAX(orderId) as maxOrder FROM serversJoined WHERE userId = ?", userId)[1]
    local newOrderId = 1
    if maxOrderResult and maxOrderResult.maxOrder then
        newOrderId = maxOrderResult.maxOrder + 1
    end

    SQLWrite("INSERT OR REPLACE INTO serversJoined (userId, serverId, orderId) VALUES (?, ?, ?)", userId, serverId,
        newOrderId)

    -- Resequence to ensure clean ordering
    ResequenceUserServers(userId)

    profile.serversJoined = SQLRead("SELECT * FROM serversJoined WHERE userId = ? ORDER BY orderId ASC", userId)

    -- Send message to server to add the user to the server
    ao.send({
        Target = serverId,
        Action = "Join-Server",
        Tags = {
            UserId = userId
        }
    })

    msg.reply({
        Action = "Join-Server-Response",
        Status = "200",
        Data = json.encode(profile)
    })
end)

Handlers.add("Leave-Server", function(msg)
    local userId = msg.From
    userId = GetOriginalId(userId)
    local serverId = msg.Tags.ServerId

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

    SQLWrite("DELETE FROM serversJoined WHERE userId = ? AND serverId = ?", userId, serverId)

    -- Resequence to ensure clean ordering after removal
    ResequenceUserServers(userId)

    profile.serversJoined = SQLRead("SELECT * FROM serversJoined WHERE userId = ? ORDER BY orderId ASC", userId)

    ao.send({
        Action = "Leave-Server",
        Target = serverId,
        Tags = {
            UserId = userId
        }
    })

    msg.reply({
        Action = "Leave-Server-Response",
        Status = "200",
        Data = json.encode(profile)
    })
end)

Handlers.add("Update-Server-Order", function(msg)
    local userId = msg.From
    userId = GetOriginalId(userId)
    local serverId = VarOrNil(msg.Tags.ServerId)
    local orderId = VarOrNil(msg.Tags.OrderId)

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
    local currentServerInfo = SQLRead("SELECT orderId FROM serversJoined WHERE userId = ? AND serverId = ?", userId,
        serverId)[1]
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
    db:exec("BEGIN TRANSACTION")
    local success = true

    -- Handle ordering changes
    if orderId < currentOrder then
        -- Moving up: shift other servers down
        SQLWrite([[
            UPDATE serversJoined
            SET orderId = orderId + 1
            WHERE userId = ? AND orderId >= ? AND orderId < ? AND serverId != ?
        ]], userId, orderId, currentOrder, serverId)
    else
        -- Moving down: shift other servers up
        SQLWrite([[
            UPDATE serversJoined
            SET orderId = orderId - 1
            WHERE userId = ? AND orderId > ? AND orderId <= ? AND serverId != ?
        ]], userId, currentOrder, orderId, serverId)
    end

    -- Update the server's order
    local rows = SQLWrite([[
        UPDATE serversJoined
        SET orderId = ?
        WHERE userId = ? AND serverId = ?
    ]], orderId, userId, serverId)

    if rows ~= 1 then
        success = false
    end

    -- Resequence to ensure clean ordering
    if success then
        ResequenceUserServers(userId)
    end

    if success then
        db:exec("COMMIT")
        -- Get updated profile
        local updatedProfile = GetProfile(userId)
        msg.reply({
            Action = "Update-Server-Order-Response",
            Status = "200",
            Data = json.encode(updatedProfile)
        })
    else
        db:exec("ROLLBACK")
        msg.reply({
            Action = "Update-Server-Order-Response",
            Status = "500",
            Data = json.encode({
                error = "Failed to update server order"
            })
        })
    end
end)

-- Message from server for when a user is Kicked
Handlers.add("Kick-Member", function(msg)
    local serverId = msg.From
    local initiatorUserId = msg["X-Origin"]
    local targetUserId = msg.Tags.TargetUserId

    SQLWrite("DELETE FROM serversJoined WHERE userId = ? AND serverId = ?", targetUserId, serverId)
    profile.serversJoined = SQLRead("SELECT * FROM serversJoined WHERE userId = ? ORDER BY orderId ASC", targetUserId)

    msg.reply({
        Action = "Kick-Member-Response",
        Status = "200",
        Data = json.encode(profile)
    })
end)

-- Message from server for when a user is Banned
Handlers.add("Ban-Member", function(msg)
    local serverId = msg.From
    local initiatorUserId = msg["X-Origin"]
    local targetUserId = msg.Tags.TargetUserId

    SQLWrite("DELETE FROM serversJoined WHERE userId = ? AND serverId = ?", targetUserId, serverId)
    profile.serversJoined = SQLRead("SELECT * FROM serversJoined WHERE userId = ? ORDER BY orderId ASC", targetUserId)

    msg.reply({
        Action = "Ban-Member-Response",
        Status = "200",
        Data = json.encode(profile)
    })
end)

----------------------------------------------------------------------------
--- FRIENDS

-- Helper function to check if two users are friends
function IsFriend(userId1, userId2)
    local result = SQLRead(
        "SELECT * FROM friends WHERE ((senderId = ? AND receiverId = ?) OR (senderId = ? AND receiverId = ?)) AND accepted = 1",
        userId1, userId2, userId2, userId1)
    return #result > 0
end

-- Helper function to check if a friend request exists
function FriendRequestExists(senderId, receiverId)
    local result = SQLRead(
        "SELECT * FROM friends WHERE senderId = ? AND receiverId = ?",
        senderId, receiverId)
    return #result > 0
end

-- Helper function to check if there's a pending friend request
function HasPendingFriendRequest(senderId, receiverId)
    local result = SQLRead(
        "SELECT * FROM friends WHERE senderId = ? AND receiverId = ? AND accepted = 0",
        senderId, receiverId)
    return #result > 0
end

-- Helper function to send a friend request
function SendFriendRequest(senderId, receiverId)
    SQLWrite("INSERT OR IGNORE INTO friends (senderId, receiverId, accepted) VALUES (?, ?, 0)",
        senderId, receiverId)
end

-- Helper function to accept a friend request
function AcceptFriendRequest(senderId, receiverId)
    SQLWrite("UPDATE friends SET accepted = 1 WHERE senderId = ? AND receiverId = ?", senderId, receiverId)
end

-- Helper function to reject/remove a friend request
function RejectFriendRequest(senderId, receiverId)
    SQLWrite("DELETE FROM friends WHERE senderId = ? AND receiverId = ?", senderId, receiverId)
end

-- Helper function to remove a friendship (both directions)
function RemoveFriend(userId1, userId2)
    SQLWrite("DELETE FROM friends WHERE (senderId = ? AND receiverId = ?) OR (senderId = ? AND receiverId = ?)",
        userId1, userId2, userId2, userId1)
end

-- Helper function to get all friends of a user
function GetUserFriends(userId)
    local result = SQLRead([[
        SELECT CASE
            WHEN senderId = ? THEN receiverId
            ELSE senderId
        END AS friendId
        FROM friends
        WHERE (senderId = ? OR receiverId = ?) AND accepted = 1
    ]], userId, userId, userId)
    return result
end

-- Helper function to get pending friend requests received by a user
function GetFriendRequestsReceived(userId)
    local result = SQLRead("SELECT * FROM friends WHERE receiverId = ? AND accepted = 0", userId)
    return result
end

-- Helper function to get pending friend requests sent by a user
function GetFriendRequestsSent(userId)
    local result = SQLRead("SELECT * FROM friends WHERE senderId = ? AND accepted = 0", userId)
    return result
end

Handlers.add("Add-Friend", function(msg)
    local senderId = msg.From
    senderId = GetOriginalId(senderId)
    local receiverId = VarOrNil(msg.Tags.FriendId)

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
end)

Handlers.add("Remove-Friend", function(msg)
    local userId = msg.From
    userId = GetOriginalId(userId)
    local friendId = VarOrNil(msg.Tags.FriendId)

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
end)

Handlers.add("Accept-Friend", function(msg)
    local receiverId = msg.From
    receiverId = GetOriginalId(receiverId)
    local senderId = VarOrNil(msg.Tags.FriendId)

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
end)

Handlers.add("Reject-Friend", function(msg)
    local receiverId = msg.From
    receiverId = GetOriginalId(receiverId)
    local senderId = VarOrNil(msg.Tags.FriendId)

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
Handlers.add("Send-DM", function(msg)
    local senderId = msg.From
    senderId = GetOriginalId(senderId)
    local friendId = VarOrNil(msg.Tags.FriendId)
    local content = VarOrNil(msg.Data) or ""
    local attachments = VarOrNil(msg.Tags.Attachments) or "[]"
    local replyTo = VarOrNil(msg.Tags.ReplyTo)

    if ValidateCondition(not friendId, msg, {
            Status = "400",
            Data = json.encode({
                error = "FriendId is required"
            })
        }) then
        return
    end

    friendId = GetOriginalId(friendId)

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
    msg.forward(friendProfile.dmProcess, { ["X-Origin-Id"] = msg.Id })
    msg.forward(senderProfile.dmProcess, { ["X-Origin-Id"] = msg.Id })

    msg.reply({
        Action = "Send-DM-Response",
        Status = "200",
        Data = msg.Id
    })
end)

Handlers.add("Delete-DM", function(msg)
    local senderId = msg.From
    senderId = GetOriginalId(senderId)
    local messageId = VarOrNil(msg.Tags.MessageId)
    local friendId = VarOrNil(msg.Tags.FriendId)

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

    msg.forward(senderProfile.dmProcess, { ["X-Origin-Id"] = msg.Id })
    msg.forward(friendProfile.dmProcess, { ["X-Origin-Id"] = msg.Id })


    msg.reply({
        Action = "Delete-DM-Response",
        Status = "200",
        Data = msg.Id
    })
end)

Handlers.add("Edit-DM", function(msg)
    local senderId = msg.From
    senderId = GetOriginalId(senderId)
    local messageId = VarOrNil(msg.Tags.MessageId)
    local friendId = VarOrNil(msg.Tags.FriendId)
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

    msg.forward(senderProfile.dmProcess, { ["X-Origin-Id"] = msg.Id })
    msg.forward(friendProfile.dmProcess, { ["X-Origin-Id"] = msg.Id })

    msg.reply({
        Action = "Edit-DM-Response",
        Status = "200",
        Data = msg.Id
    })
end)

----------------------------------------------------------------------------
--- NOTIFICATIONS

Handlers.add("Get-Notifications", function(msg)
    local userId = VarOrNil(msg.Tags.UserId) or msg.From
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

    local notifications = SQLRead("SELECT * FROM notifications WHERE forUserId = ? ORDER BY notificationId DESC", userId)
    msg.reply({
        Action = "Get-Notifications-Response",
        Status = "200",
        Data = json.encode(notifications)
    })
end)

Handlers.add("Add-Notification", function(msg)
    local serverOrDmId = VarOrNil(msg.From)
    local fromUserId = VarOrNil(msg.Tags.FromUserId)
    local forUserId = VarOrNil(msg.Tags.ForUserId)
    local timestamp = VarOrNil(msg.Timestamp)
    local source = VarOrNil(msg.Tags.Source) -- Server / DM
    local messageTxId = VarOrNil(msg.Tags.MessageTxId)
    -- if source = Server
    local channelId = VarOrNil(msg.Tags.ChannelId)
    local serverName = VarOrNil(msg.Tags.ServerName)
    local channelName = VarOrNil(msg.Tags.ChannelName)
    -- optionals
    local authorName = VarOrNil(msg.Tags.AuthorName)

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
        if ValidateCondition(not recipient.dmProcess, msg, {
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
                    error = "Recipient's dm process does not belong to the correct server"
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

    local rows = SQLWrite(
        "INSERT INTO notifications (serverOrDmId, fromUserId, forUserId, timestamp, source, channelId, serverName, channelName, authorName, messageTxId) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
        serverOrDmId, fromUserId, forUserId, timestamp, source, channelId, serverName, channelName, authorName,
        messageTxId
    )
    if rows > 0 then
        msg.reply({
            Action = "Add-Notification-Response",
            Status = "200",
            Data = json.encode({
                message = "Notification added"
            })
        })
    end
end)

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

    local notification = SQLRead("SELECT * FROM notifications WHERE notificationId = ? AND forUserId = ?", notificationId,
        userId)[1]
    if ValidateCondition(not notification, msg, {
            Status = "404",
            Data = json.encode({
                error = "Notification not found"
            })
        }) then
        return
    end

    -- delete notification from notifications table
    SQLWrite("DELETE FROM notifications WHERE notificationId = ? AND forUserId = ?", notificationId, userId)

    msg.reply({
        Action = "Mark-Read-Response",
        Status = "200",
        Data = json.encode(profile)
    })
end)

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

    SQLWrite("DELETE FROM notifications WHERE forUserId = ?", userId)

    msg.reply({
        Action = "Mark-All-Read-Response",
        Status = "200",
        Data = json.encode(profile)
    })
end)

----------------------------------------------------------------------------
-- BOTS

Handlers.add("Create-Bot", function(msg)
    local userId = msg.From
    userId = GetOriginalId(userId)
    local botProcess = VarOrNil(msg.Tags.BotProcess)

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

    -- verify if bot process is for the correct owner
    ao.send({
        Target = botProcess,
        Action = "Info",
    })

    local infoRes = Receive({ Action = "Info-Response", From = botProcess })
    if ValidateCondition(infoRes.Status ~= "200" or infoRes.Tags.Owner_ ~= userId, msg, {
            Status = "400",
            Data = json.encode({
                error = "Invalid bot process or owner mismatch"
            })
        })
    then
        return
    end

    local publicBot = infoRes.Tags.PublicBot
    PublicBot = (publicBot == "true")
    local botName = infoRes.Tags.Name
    local botPfp = infoRes.Tags.Pfp

    SQLWrite("INSERT INTO bots (userId, botProcess, botName, botPfp, botPublic) VALUES (?, ?, ?, ?, ?)", userId,
        botProcess, botName, botPfp, publicBot)

    msg.reply({
        Action = "Create-Bot-Response",
        Status = "200",
        BotProcess = botProcess
    })
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
    local bot = SQLRead("SELECT * FROM bots WHERE botProcess = ?", botId)[1]
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
    SQLWrite("UPDATE bots SET botPublic = ?, botName = ?, botPfp = ? WHERE botProcess = ?", publicBot, name, pfp, botId)

    msg.reply({
        Action = "Update-Bot-Response",
        Status = "200",
    })
end)

Handlers.add("Bot-Info", function(msg)
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

    local bot = SQLRead("SELECT * FROM bots WHERE botProcess = ?", botProcess)[1]
    if ValidateCondition(not bot, msg, {
            Status = "404",
            Data = json.encode({
                error = "Bot not found"
            })
        })
    then
        return
    end

    -- fetch number of servers the bot is in
    local totalServers = SQLRead("SELECT COUNT(*) FROM serversJoined WHERE botProcess = ?", botProcess)[1]
    bot.totalServers = totalServers

    msg.reply({
        Action = "Bot-Info-Response",
        Status = "200",
        Data = json.encode(bot)
    })
end)

Handlers.add("Add-Bot", function(msg)
    local userId = msg.From
    userId = GetOriginalId(userId)
    local botProcess = VarOrNil(msg.Tags.BotProcess)
    local serverId = VarOrNil(msg.Tags.ServerId)

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

    local bot = SQLRead("SELECT * FROM bots WHERE botProcess = ?", botProcess)[1]
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
    SQLWrite("INSERT INTO botServers (botProcess, serverId) VALUES (?, ?)", botProcess, serverId)
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
    SQLWrite("DELETE FROM botServers WHERE botProcess = ? AND serverId = ?", botProcess, serverId)

    msg.reply({
        Action = "Remove-Bot-Response",
        Status = "200",
    })
end)
