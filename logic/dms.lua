json = require("json")

----------------------------------------------------------------------------
-- Direct Messages (DM) Process Logic
--
-- Purpose:
-- - Store DM threads per counterpart user id
-- - Provide CRUD for DM messages with simple event tracking
-- - Expose a compact patch state for external consumers
--
-- Storage Model:
-- - dm_messages[dmUserId][messageId] = message
-- - messageId is a local, per-dmUserId incrementing integer
-- - dm_events is a simple append-only list of edit/delete events
----------------------------------------------------------------------------

----------------------------------------------------------------------------
--- VARIABLES

Subspace = "RmrKN2lAw5nu9eIQzXXi9DYT-95PqaLURnG9PRsoVuo"
Version = Version or "1.0.0"

-- Storage policy: in-memory tables only

----------------------------------------------------------------------------

-- (no legacy persistence layer)

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

-- In-memory state
dm_messages = dm_messages or {}           -- { [dmUserId] = { [messageId:string] = messageObj } }
dm_nextMessageId = dm_nextMessageId or {} -- { [dmUserId] = nextId:number }
dm_events = dm_events or {}               -- array of { eventId, eventType, messageId }
dm_nextEventId = dm_nextEventId or 1

-- Allocate a new per-peer message id
local function getNextMessageId(dmUserId)
    local nextId = tonumber(dm_nextMessageId[dmUserId]) or 1
    dm_nextMessageId[dmUserId] = nextId + 1
    return nextId
end

-- Record a mutation event for consumers that want incremental syncing
local function appendEvent(eventType, messageId)
    local eid = dm_nextEventId
    dm_nextEventId = eid + 1
    dm_events[#dm_events + 1] = { eventId = eid, eventType = eventType, messageId = messageId }
    return eid
end

----------------------------------------------------------------------------

-- Push current DM state to Hyperbeam’s patch cache for fast external reads
function SyncProcessState()
    local state = {
        version = tostring(Version),
        owner = Owner,
        messages = dm_messages,
        events = dm_events,
    }

    Send({
        Target = ao.id,
        device = "patch@1.0",
        cache = { dms = state }
    })
end

----------------------------------------------------------------------------


-- Create a new DM message (forwarded via Profiles). Only Subspace can issue this.
Handlers.add("Send-DM", function(msg)
    assert(msg.From == Subspace, "❌[auth error] sender not authorized to add a dm")

    local authorId = msg["X-Origin"]
    local dmUserId = msg.Tags["Friend-Id"]
    local content = VarOrNil(msg.Data) or ""
    local attachments = VarOrNil(msg.Tags.Attachments) or "[]"
    local replyTo = VarOrNil(msg.Tags["Reply-To"])
    local timestamp = tonumber(msg.Timestamp)
    local messageTxId = msg["X-Origin-Id"]

    -- Trust policy: Either authorId or dmUserId must be the Owner of this dm process
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

    -- If the friendId points to this process owner, normalize to the other party
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

    -- If replying: ensure the referenced message exists in the same peer bucket
    if replyTo then
        replyTo = tonumber(replyTo)
        local bucket = dm_messages[dmUserId] or {}
        local message = bucket[tostring(replyTo)]
        if ValidateCondition(not message, msg, {
                Status = "400",
                Data = json.encode({
                    error = "Invalid replyTo messageId"
                })
            }) then
            return
        end
    end

    -- Insert message into the per-peer bucket
    dm_messages[dmUserId] = dm_messages[dmUserId] or {}
    local messageId = getNextMessageId(dmUserId)
    dm_messages[dmUserId][tostring(messageId)] = {
        messageId = messageId,
        dmUserId = dmUserId,
        authorId = authorId,
        content = content,
        attachments = attachments,
        replyTo = replyTo,
        timestamp = timestamp,
        edited = 0,
        messageTxId = messageTxId,
    }

    -- Notify Subspace so the recipient can receive a notification out-of-band
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

    SyncProcessState()
    msg.reply({
        Action = "Send-DM-Response",
        Status = "200",
        Data = json.encode({
            messageId = messageId
        })
    })
end)

-- Delete a DM message authored by the caller
Handlers.add("Delete-DM", function(msg)
    assert(msg.From == Subspace, "❌[auth error] sender not authorized to delete a dm")

    local messageId = VarOrNil(msg.Tags["Message-Id"])
    local dmUserId = VarOrNil(msg.Tags["Friend-Id"])
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

    -- Fetch and author-validate message from the per-peer bucket
    messageId = tonumber(messageId)
    local bucket = dm_messages[dmUserId] or {}
    local message = bucket[tostring(messageId)]
    if message and message.authorId ~= authorId then message = nil end
    if ValidateCondition(not message, msg, {
            Status = "400",
            Data = json.encode({
                error = "Message not found"
            })
        }) then
        return
    end

    -- Delete message and record a DELETE event for incremental consumers
    dm_messages[dmUserId][tostring(messageId)] = nil
    appendEvent("DELETE_MESSAGE", messageId)

    SyncProcessState()
    msg.reply({
        Action = "Delete-DM-Response",
        Status = "200",
        Data = msg.Id
    })
end)


-- Edit a DM message authored by the caller
Handlers.add("Edit-DM", function(msg)
    assert(msg.From == Subspace, "❌[auth error] sender not authorized to edit a dm")

    local messageId = VarOrNil(msg.Tags["Message-Id"])
    local dmUserId = VarOrNil(msg.Tags["Friend-Id"])
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

    -- Fetch and author-validate message from the per-peer bucket
    messageId = tonumber(messageId)
    local bucket = dm_messages[dmUserId] or {}
    local message = bucket[tostring(messageId)]
    if message and message.authorId ~= authorId then message = nil end
    if ValidateCondition(not message, msg, {
            Status = "400",
            Data = json.encode({
                error = "Message not found"
            })
        }) then
        return
    end

    -- Update message in place and record an EDIT event
    message.content = content
    message.edited = 1
    appendEvent("EDIT_MESSAGE", messageId)

    SyncProcessState()

    msg.reply({
        Action = "Edit-DM-Response",
        Status = "200",
        Data = msg.Id
    })
end)
