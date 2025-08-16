// Re-export types from the new modular structure
export type { Bot } from "../managers/bot"
export type { Profile, Notification, Friend, DMMessage, DMResponse } from "../managers/user"
export type { Server, Member, Channel, Category, Role, Message, MessagesResponse } from "../managers/server"
export type { Tag, MessageResult, AoSigner } from "./ao"
export type { ConnectionConfig } from "../connection-manager"

// ---------------- Permissions ---------------- //

export enum EPermissions {
    SEND_MESSAGES = 1 << 0,  // 1
    MANAGE_NICKNAMES = 1 << 1,  // 2
    MANAGE_MESSAGES = 1 << 2,  // 4
    KICK_MEMBERS = 1 << 3,  // 8
    BAN_MEMBERS = 1 << 4,  // 16
    MANAGE_CHANNELS = 1 << 5,  // 32
    MANAGE_SERVER = 1 << 6,  // 64
    MANAGE_ROLES = 1 << 7,  // 128
    MANAGE_MEMBERS = 1 << 8,  // 256
    MENTION_EVERYONE = 1 << 9,  // 512
    ADMINISTRATOR = 1 << 10, // 1024
    ATTACHMENTS = 1 << 11, // 2048
    MANAGE_BOTS = 1 << 12, // 4096
}