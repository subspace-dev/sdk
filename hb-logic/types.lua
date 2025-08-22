--- @class Profile
--- @field id string
--- @field pfp string
--- @field banner string
--- @field dm_process string
--- @field servers table<string, {order_id: number, approved: boolean}>
--- @field friends { sent: table<string, boolean>, received: table<string, boolean>, accepted: table<string, boolean> }
--- @field notifications table<string, Notification>

--- @class Bot
--- @field id string
--- @field owner_id string
--- @field name string
--- @field description string
--- @field pfp string
--- @field banner string
--- @field servers table<string, {approved: boolean}>
--- @field required_events table<number, string>  -- Array of event names

--- @class Server
--- @field id string
--- @field owner string
--- @field name string
--- @field description string
--- @field pfp string
--- @field banner string
--- @field public_server boolean

--- @class Member -- server member/bot member
--- @field id string
--- @field nickname string
--- @field roles table<string, Role|string> -- {role-id: Role|role-id}
--- @field joined_at integer
--- @field is_bot boolean

--- @class Role
--- @field id string
--- @field name string
--- @field order number             -- top to bottom -> lower order is higher
--- @field color string             -- hex color
--- @field mentionable boolean      -- can be mentioned
--- @field hoist boolean            -- shows up seperately in the member list
--- @field permissions number       -- bitwise permissions

--- @class Category
--- @field id string
--- @field name string
--- @field order number

--- @class Channel
--- @field id string
--- @field name string
--- @field order number
--- @field category_id string | nil
--- @field allow_messaging number | nil
--- @field allow_attachments number | nil

--- @class Message
--- @field id string
--- @field content string
--- @field author_id string
--- @field channel_id string
--- @field timestamp string
--- @field edited boolean
--- @field attachments table<string, Attachment>
--- @field mentions table<string, boolean> -- {user-id: boolean}

--- @class Attachment
--- @field id string
--- @field url string
--- @field filename string
--- @field content_type string

--- Event values from helpers.events
--- @alias Event 10|20|30|40|50|60|70|80|90|100|110|120|130|140|150|160|170

--- @class Notification
--- @field id string
--- @field is_dm boolean
--- @field server_id string
--- @field channel_id string
--- @field author_id string
--- @field author_nickname string
--- @field message_id string
--- @field timestamp string
--- @field preview_content string
