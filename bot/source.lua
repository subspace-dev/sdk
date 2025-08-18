function Setup()
    -- update subscriptions to receive only specific events
    -- or any other styup that needs to run once
end

---@class BotEvent
---@field eventType string Event type: "MESSAGE_SENT" | "MESSAGE_EDITED" | "MESSAGE_DELETED"
---@field serverId string Server process ID
---@field channelId string Channel ID where the event occurred
---@field messageId string Message ID
---@field timestamp string Message timestamp
---@field content string Message content
---@field attachments string JSON string of attachments
---@field replyTo string|nil Message ID being replied to
---@field authorId string Author's user ID
---@field authorNickname string|nil Author's nickname (if available)
---@field fromBot boolean Whether the author is a bot
---@field serverName string Server name
---@field channelName string Channel name
---@field editorId string|nil User ID who edited the message (MESSAGE_EDITED only)
---@field deleterId string|nil User ID who deleted the message (MESSAGE_DELETED only)
---@field rawMessage table Raw message object from AO
---@field reply function Reply to the message
---@field raw table Raw message object from AO

---Main bot logic handler
---@param event BotEvent
function Main(event)
    local displayName = event.authorNickname ~= "" and event.authorNickname or event.authorId

    -- debug logs for testing
    print(displayName .. ": " .. event.content)

    -- if message is !ping, reply with pong, message can start with !ping and have more text after it
    if event.content:match("^!ping") and event.fromBot == false then
        event.reply("Pong!")
        print("replied to " .. displayName .. " with pong")
    end
end
