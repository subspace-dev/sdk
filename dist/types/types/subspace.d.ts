export type { Bot } from "../managers/bot";
export type { Profile, Notification, Friend, DMMessage, DMResponse } from "../managers/user";
export type { Server, Member, Channel, Category, Role, Message, MessagesResponse } from "../managers/server";
export type { Tag, MessageResult, AoSigner } from "./ao";
export type { ConnectionConfig } from "../connection-manager";
export declare enum EPermissions {
    SEND_MESSAGES = 1,// 1
    MANAGE_NICKNAMES = 2,// 2
    MANAGE_MESSAGES = 4,// 4
    KICK_MEMBERS = 8,// 8
    BAN_MEMBERS = 16,// 16
    MANAGE_CHANNELS = 32,// 32
    MANAGE_SERVER = 64,// 64
    MANAGE_ROLES = 128,// 128
    MANAGE_MEMBERS = 256,// 256
    MENTION_EVERYONE = 512,// 512
    ADMINISTRATOR = 1024,// 1024
    ATTACHMENTS = 2048,// 2048
    MANAGE_BOTS = 4096
}
