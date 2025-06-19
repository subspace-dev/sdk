sqlite3 = require("lsqlite3")
json = require("json")

----------------------------------------------------------------------------
--- VARIABLES

Subspace = Subspace or Owner
BotOwner = BotOwner or ""
Name = Name or ""
Pfp = Pfp or ""
PublicBot = PublicBot or true

JoinedServers = {}
SubscribedServers = {}

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

Handlers.once("Init-Bot", function(msg)
    assert(msg.From == Subspace, "You are not allowed to init bots")
    assert(BotOwner == "", "Bot already initialized")

    local botOwner = VarOrNil(msg.Tags.UserId)
    local botName = VarOrNil(msg.Tags.BotName)
    local botPfp = VarOrNil(msg.Tags.BotPfp)
    local botPublic = VarOrNil(msg.Tags.BotPublic)

    if botPublic then
        botPublic = (botPublic == "true")
    else
        botPublic = true
    end

    if ValidateCondition(not botOwner, msg, {
            Status = "400",
            Data = json.encode({
                error = "UserId is required"
            })
        }) then
        return
    end

    if ValidateCondition(not botName, msg, {
            Status = "400",
            Data = json.encode({
                error = "Name is required"
            })
        }) then
        return
    end

    if ValidateCondition(not botPfp, msg, {
            Status = "400",
            Data = json.encode({
                error = "Pfp is required"
            })
        }) then
        return
    end

    BotOwner = botOwner
    Name = botName
    Pfp = botPfp
    PublicBot = botPublic

    msg.reply({
        Action = "Init-Bot-Response",
        Status = "200",
    })
end)

Handlers.add("Join-Server", function(msg)
    assert(msg.From == Subspace, "You are not allowed to join servers")

    local serverId = VarOrNil(msg.Tags.ServerId)

    if ValidateCondition(not serverId, msg, {
            Status = "400",
            Data = json.encode({
                error = "ServerId is required"
            })
        }) then
        return
    end

    -- can add checks here for blacklisted servers
    msg.reply({
        Action = "Join-Server-Response",
        Status = "200",
    })
    local joinResponse = Receive({ Action = "Join-Server-Success", From = serverId })
    if ValidateCondition(joinResponse.Status ~= "200", msg, {
            Status = "500",
            Data = json.encode(joinResponse.Data)
        }) then
        return
    end

    JoinedServers[serverId] = true

    -- send subscription messages
    ao.send({
        Target = serverId,
        Action = "Subscribe",
    })
    local subscribeResponse = Receive({ Action = "Subscribe-Response", From = serverId })
    if ValidateCondition(subscribeResponse.Status ~= "200", msg, {
            Status = "500",
            Data = json.encode(subscribeResponse.Data)
        }) then
        return
    end

    SubscribedServers[serverId] = true
end)

Handlers.add("Remove-Bot", function(msg)
    local serverId = msg.From

    JoinedServers[serverId] = nil
    SubscribedServers[serverId] = nil

    -- send unsubscription messages
    ao.send({
        Target = serverId,
        Action = "Unsubscribe",
    })
end)


----------------------------------------------------------------------------

-- Events sent from servers

Handlers.add("Event-Message", function(msg)

end)
