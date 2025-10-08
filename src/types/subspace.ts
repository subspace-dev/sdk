export type Tag = { name: string, value: string };

export interface IProfile {
    id: string;
    pfp: string;
    banner: string;
    bio: string;
    dm_process: string;
    servers: Record<string, { order_id: number; approved: boolean }>;
    friends: { sent: Record<string, boolean>; received: Record<string, boolean>; accepted: Record<string, boolean> };
    notifications: Record<string, INotification>;
}

export interface IBot {
    id: string;
    owner_id: string;
    name: string;
    description: string;
    pfp: string;
    banner: string;
    servers: Record<string, { approved: boolean }>;
    required_events: Record<number, string>;
    version: string;
}

export interface IServer {
    categories: Record<string, ICategory>;
    channels: Record<string, IChannel>;
    roles: Record<string, IRole>;
    member_count: number;
    profile: {
        banner: string;
        description: string;
        id: string;
        name: string;
        owner: string;
        pfp: string;
    };
    version: string;
}

export interface IMember {
    id: string;
    nickname: string;
    roles: Record<string, string>; // {role-id: role-id}
    joined_at: number;
    is_bot: boolean;
}

export interface IRole {
    id: string;
    name: string;
    order: number;
    color: string;
    mentionable: boolean;
    hoist: boolean;
    permissions: number;
}

export interface ICategory {
    id: string;
    name: string;
    order: number;
}

export interface IChannel {
    id: string;
    name: string;
    order: number;
    category_id: string | null;
    allow_messaging: number | null;
    allow_attachments: number | null;
}

export interface IMessage {
    id: string;
    content: string;
    author_id: string;
    channel_id: string;
    timestamp: number;
    edited: boolean;
    attachments: Record<string, IAttachment>;
}

export interface IAttachment {
    id: string;
    url: string;
    filename: string;
    content_type: string;
}

export type ServerEvent = 10 | 20 | 30 | 40 | 50 | 60 | 70 | 80 | 90 | 100 | 110 | 120 | 130 | 140 | 150 | 160 | 170;

export const EPermissions = {
    SEND_MESSAGES: 1 << 0,    // 1
    MANAGE_NICKNAMES: 1 << 1, // 2
    MANAGE_MESSAGES: 1 << 2,  // 4
    KICK_MEMBERS: 1 << 3,     // 8
    BAN_MEMBERS: 1 << 4,      // 16
    MANAGE_CHANNELS: 1 << 5,  // 32
    MANAGE_SERVER: 1 << 6,    // 64
    MANAGE_ROLES: 1 << 7,     // 128
    MANAGE_MEMBERS: 1 << 8,   // 256
    MENTION_EVERYONE: 1 << 9, // 512
    ADMINISTRATOR: 1 << 10,   // 1024
    ATTACHMENTS: 1 << 11,     // 2048
    MANAGE_BOTS: 1 << 12,     // 4096
}

export interface INotification {
    id: string;
    is_dm: boolean;
    server_id: string;
    channel_id: string;
    author_id: string;
    author_nickname: string;
    message_id: string;
    timestamp: string;
    preview_content: string;
}