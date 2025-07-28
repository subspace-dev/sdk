sqlite3 = require("lsqlite3")
json = require("json")

----------------------------------------------------------------------------
--- VARIABLES

Subspace = "VDkbyJj9o67AtTaYregitjDgcrLWmrxMvKICbWR-kBA"
Version = Version or "1.0.0"

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

-- dmUserId is always the friendId with whom Owner is dming with
-- authorId can either be the Owber or the friendId
db:exec([[
    CREATE TABLE IF NOT EXISTS messages (
        messageId INTEGER PRIMARY KEY AUTOINCREMENT,
        dmUserId TEXT NOT NULL,
        authorId TEXT NOT NULL,
        content TEXT NOT NULL,
        attachments TEXT DEFAULT "[]",
        replyTo INTEGER,
        timestamp INTEGER NOT NULL,
        edited INTEGER NOT NULL DEFAULT 0,
        messageTxId TEXT UNIQUE,
        FOREIGN KEY (replyTo) REFERENCES messages(messageId) ON DELETE SET NULL
    );

    CREATE TABLE IF NOT EXISTS events (
        eventId INTEGER PRIMARY KEY AUTOINCREMENT,
        eventType TEXT, CHECK (eventType IN ("DELETE_MESSAGE", "EDIT_MESSAGE")),
        messageId INTEGER,
        FOREIGN KEY (messageId) REFERENCES messages(messageId)
    );
]])

----------------------------------------------------------------------------

Handlers.add("Info", function(msg)
    msg.reply({
        Action = "Info-Response",
        Status = "200",
        Version = tostring(Version),
        Owner_ = Owner
    })
end)

Handlers.add("Get-DMs", function(msg)
    assert(Owner == msg.From, "❌[auth error] Dm module not initialized")

    local dmUserId = VarOrNil(msg.Tags.FriendId)
    local limit = VarOrNil(msg.Tags.Limit)
    local after = VarOrNil(msg.Tags.After)
    local before = VarOrNil(msg.Tags.Before)
    local eventId = VarOrNil(msg.Tags.EventId) -- eventId is the id of the last event fetched (optional)

    -- debug print data
    -- print("DM UserId: " .. (dmUserId or "nil"))
    -- print("Limit: " .. (limit or "nil"))
    -- print("After: " .. (after or "nil"))
    -- print("Before: " .. (before or "nil"))
    -- print("EventId: " .. (eventId or "nil"))
    -- print("From: " .. msg.From)
    -- print("Owner: " .. Owner)

    local query = "SELECT * FROM messages"
    local queryParams = {}

    -- Build WHERE clause
    local whereConditions = {}
    if dmUserId then
        table.insert(whereConditions, "dmUserId = ?")
        table.insert(queryParams, dmUserId)
    end

    if after then
        table.insert(whereConditions, "messageId > ?")
        table.insert(queryParams, after)
    end

    if before then
        table.insert(whereConditions, "messageId < ?")
        table.insert(queryParams, before)
    end

    if #whereConditions > 0 then
        query = query .. " WHERE " .. table.concat(whereConditions, " AND ")
    end

    query = query .. " ORDER BY messageId DESC"

    if limit then
        query = query .. " LIMIT ?"
        table.insert(queryParams, limit)
    end

    local messages = SQLRead(query, table.unpack(queryParams))

    local events = {}
    if eventId then
        events = SQLRead("SELECT * FROM events WHERE eventId > ?", eventId)
        -- if event has an edited message, fetch the message from messages table and update in response.messages
        for _, event in ipairs(events) do
            if event.eventType == "EDIT_MESSAGE" then
                if event.messageId < after then
                    local message = SQLRead("SELECT * FROM messages WHERE messageId = ?", event.messageId)[1]
                    table.insert(messages, message)
                end
            end
        end
    else
        events = SQLRead("SELECT * FROM events ORDER BY eventId DESC")
    end

    local response = {
        messages = messages,
        events = events
    }

    msg.reply({
        Action = "Get-DMs-Response",
        Status = "200",
        Data = json.encode(response)
    })
end)

-- msg forwarded by Profiles
Handlers.add("Send-DM", function(msg)
    assert(msg.From == Subspace, "❌[auth error] sender not authorized to add a dm")

    local authorId = msg["X-Origin"]
    local dmUserId = msg.Tags.FriendId
    local content = VarOrNil(msg.Data) or ""
    local attachments = VarOrNil(msg.Tags.Attachments) or "[]"
    local replyTo = VarOrNil(msg.Tags.ReplyTo)
    local timestamp = tonumber(msg.Timestamp)
    local messageTxId = msg["X-Origin-Id"]

    -- Either authorId or dmUserId must be the Owner
    if ValidateCondition(authorId ~= Owner and dmUserId ~= Owner, msg, {
            Status = "400",
            Data = json.encode({
                error = "Either authorId or dmUserId must be the Owner"
            })
        }) then
        return
    end

    if ValidateCondition(not authorId, msg, {
            Status = "400",
            Data = json.encode({
                error = "AuthorId is required"
            })
        }) then
        return
    end

    if ValidateCondition(not dmUserId, msg, {
            Status = "400",
            Data = json.encode({
                error = "FriendId is required"
            })
        }) then
        return
    end

    -- if dmUserId is the Owner, then authorId is the friendId
    if dmUserId == Owner then
        dmUserId = authorId
    end

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

    -- if replyTo is provided, it should be a number and a valid messageId in messages table
    if replyTo then
        replyTo = tonumber(replyTo)
        local message = SQLRead("SELECT * FROM messages WHERE messageId = ? AND dmUserId = ?", replyTo, authorId)[1]
        if ValidateCondition(not message, msg, {
                Status = "400",
                Data = json.encode({
                    error = "Invalid replyTo messageId"
                })
            }) then
            return
        end
    end

    -- insert message into messages table
    SQLWrite(
        "INSERT INTO messages (dmUserId, authorId, content, attachments, replyTo, timestamp, messageTxId) VALUES (?, ?, ?, ?, ?, ?, ?)",
        dmUserId, authorId, content, attachments, replyTo, timestamp, messageTxId)

    -- send notification
    if authorId ~= Owner then
        ao.send({
            Target = Subspace,
            Action = "Add-Notification",
            Tags = {
                ServerOrDmId = ao.id,
                FromUserId = authorId,
                ForUserId = Owner,
                Source = "DM",
                MessageTxId = messageTxId
            }
        })
    end

    msg.reply({
        Action = "Send-DM-Response",
        Status = "200",
        Data = json.encode({
            messageId = db:last_insert_rowid()
        })
    })
end)

Handlers.add("Delete-DM", function(msg)
    assert(msg.From == Subspace, "❌[auth error] sender not authorized to delete a dm")

    local messageId = VarOrNil(msg.Tags.MessageId)
    local dmUserId = VarOrNil(msg.Tags.FriendId)
    local authorId = msg["X-Origin"]

    if ValidateCondition(not messageId, msg, {
            Status = "400",
            Data = json.encode({
                error = "MessageId is required"
            })
        }) then
        return
    end

    if ValidateCondition(not dmUserId, msg, {
            Status = "400",
            Data = json.encode({
                error = "DmUserId is required"
            })
        }) then
        return
    end

    if ValidateCondition(not authorId, msg, {
            Status = "400",
            Data = json.encode({
                error = "AuthorId is required"
            })
        }) then
        return
    end

    if ValidateCondition(authorId ~= Owner and dmUserId ~= Owner, msg, {
            Status = "400",
            Data = json.encode({
                error = "Either authorId or dmUserId must be the Owner"
            })
        }) then
        return
    end

    if dmUserId == Owner then
        dmUserId = authorId
    end

    -- fetch message from messages table if it exists
    local message = SQLRead("SELECT * FROM messages WHERE messageId = ? AND authorId = ? AND dmUserId = ?", messageId,
        authorId, dmUserId)[1]
    if ValidateCondition(not message, msg, {
            Status = "400",
            Data = json.encode({
                error = "Message not found"
            })
        }) then
        return
    end

    -- delete message from messages table
    SQLWrite("DELETE FROM messages WHERE messageId = ?", messageId)

    -- add delete event to events table
    SQLWrite("INSERT INTO events (eventType, messageId) VALUES ('DELETE_MESSAGE', ?)", messageId)

    msg.reply({
        Action = "Delete-DM-Response",
        Status = "200",
        Data = msg.Id
    })
end)


Handlers.add("Edit-DM", function(msg)
    assert(msg.From == Subspace, "❌[auth error] sender not authorized to edit a dm")

    local messageId = VarOrNil(msg.Tags.MessageId)
    local dmUserId = VarOrNil(msg.Tags.FriendId)
    local authorId = msg["X-Origin"]
    local content = VarOrNil(msg.Data)

    if ValidateCondition(not messageId, msg, {
            Status = "400",
            Data = json.encode({
                error = "MessageId is required"
            })
        }) then
        return
    end

    if ValidateCondition(not dmUserId, msg, {
            Status = "400",
            Data = json.encode({
                error = "DmUserId is required"
            })
        }) then
        return
    end

    if ValidateCondition(not authorId, msg, {
            Status = "400",
            Data = json.encode({
                error = "AuthorId is required"
            })
        }) then
        return
    end

    if ValidateCondition(authorId ~= Owner and dmUserId ~= Owner, msg, {
            Status = "400",
            Data = json.encode({
                error = "Either authorId or dmUserId must be the Owner"
            })
        }) then
        return
    end

    if dmUserId == Owner then
        dmUserId = authorId
    end

    if ValidateCondition(not content, msg, {
            Status = "400",
            Data = json.encode({
                error = "Content cannot be empty when editing a message"
            })
        }) then
        return
    end

    -- fetch message from messages table if it exists
    local message = SQLRead("SELECT * FROM messages WHERE messageId = ? AND authorId = ? AND dmUserId = ?", messageId,
        authorId, dmUserId)[1]
    if ValidateCondition(not message, msg, {
            Status = "400",
            Data = json.encode({
                error = "Message not found"
            })
        }) then
        return
    end

    -- update message in messages table
    SQLWrite("UPDATE messages SET content = ?, edited = 1 WHERE messageId = ?", content, messageId)

    -- add edit event to events table
    SQLWrite("INSERT INTO events (eventType, messageId) VALUES ('EDIT_MESSAGE', ?)", messageId)

    msg.reply({
        Action = "Edit-DM-Response",
        Status = "200",
        Data = msg.Id
    })
end)
