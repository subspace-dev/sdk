import { Bot } from "../bot"
import { Profile } from "../profile"
import { addBotParams, assignRoleParams, createBotParams, createCategoryParams, createChannelParams, createRoleParams, createServerParams, deleteDMParams, editDMParams, editMessageParams, getDMsParams, getMessagesParams, removeBotParams, sendDMParams, sendMessageParams, unassignRoleParams, updateCategoryParams, updateChannelParams, updateMemberParams, updateProfileParams, updateRoleParams } from "./inputs"
import { DMResponse, GetMessagesResponse } from "./responses"

// ---------------- Subspace client interfaces ---------------- //

export interface ISubspaceReadOnly {
    getProfile(userId: string): Promise<IProfileReadOnly | null>
    getBulkProfile(userIds: string[]): Promise<Array<IProfileReadOnly>>
    anchorToServer(anchorId: string): Promise<IServerReadOnly>
    getServer(serverId: string): Promise<IServerReadOnly | null>

    getOriginalId(userId: string): Promise<string>
    getBot(botProcess: string): Promise<IBotReadOnly | null>
}

// Subspace Writable
export interface ISubspace extends ISubspaceReadOnly {
    getProfile(userId: string): Promise<IProfile | null>
    getBulkProfile(userIds: string[]): Promise<Array<IProfile>>
    anchorToServer(anchorId: string): Promise<IServer>
    getServer(serverId: string): Promise<IServer | null>

    createProfile(): Promise<IProfile>
    createServer(params: createServerParams): Promise<IServer>

    createBot(params: createBotParams): Promise<Bot>
    addBot(params: addBotParams): Promise<boolean>
    removeBot(params: removeBotParams): Promise<boolean>
}

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

// ---------------- Readable interfaces ---------------- //

export interface IProfileReadOnly {
    userId: string
    pfp?: string
    dmProcess?: string
    delegations?: string[]
    serversJoined?: Array<{ orderId: number, serverId: string }>
    friends?: {
        accepted: string[]
        sent: string[]
        received: string[]
    }

    getDMs(params: getDMsParams): Promise<DMResponse>
}

export interface IServerReadOnly {
    serverId: string
    ownerId: string
    name: string
    logo: string
    channels: IChannelReadOnly[]
    categories: ICategoryReadOnly[]
    roles: IRoleReadOnly[]
}

export interface IChannelReadOnly {
    channelId: string
    name: string
    serverId: string
    categoryId?: string
    orderId?: number
    allowMessaging?: 1 | 0
    allowAttachments?: 1 | 0
}

export interface ICategoryReadOnly {
    serverId: string
    categoryId: string
    name: string
    orderId?: number
    allowMessaging?: 1 | 0
    allowAttachments?: 1 | 0
}

export interface IMemberReadOnly {
    userId: string
    serverId: string
    nickname?: string
    roles: string[]
}

export interface IRoleReadOnly {
    id: string
    name: string
    serverId: string
    color?: string
    position: number
    permissions: EPermissions
}

export interface INotificationReadOnly {
    notificationId: string
    serverOrDmId: string
    fromUserId: string
    forUserId: string
    timestamp: number
    source: 'SERVER' | 'DM'
    channelId?: string
    serverName?: string
    channelName?: string
    authorName?: string
    messageTxId?: string
}

export interface IMessageReadOnly {
    messageId: string
    content: string
    serverId?: string
    channelId?: string
    authorId?: string
    replyTo?: string
    attachments?: string[]
    timestamp: number
    edited: number
}

export interface IDirectMessageReadOnly {
    messageId: string
    content: string
    dmUserId: string
    authorId: string
    replyTo?: string
    attachments?: string[]
    timestamp: number
    edited: number
    messageTxId: string
}

export interface IEventReadOnly {
    eventId: string
    eventType: 'DELETE_MESSAGE' | 'EDIT_MESSAGE'
    messageId: string
}

// ---------------- Writable interfaces ---------------- //

export interface IProfile extends IProfileReadOnly {
    updateProfile(params: updateProfileParams): Promise<Profile>

    addDelegation(): Promise<boolean>
    removeDelegation(): Promise<boolean>
    removeAllDelegations(): Promise<boolean>

    sendFriendRequest(userId: string): Promise<boolean>
    acceptFriendRequest(userId: string): Promise<boolean>
    rejectFriendRequest(userId: string): Promise<boolean>
    removeFriend(userId: string): Promise<boolean>

    sendDM(params: sendDMParams): Promise<boolean>
    deleteDM(params: deleteDMParams): Promise<boolean>
    editDM(params: editDMParams): Promise<boolean>
}

export interface IServer extends IServerReadOnly {
    getMember(userId: string): Promise<IMember>
    getAllMembers(): Promise<IMember[]>
    updateMember(params: updateMemberParams): Promise<IMember>
    kickMember(userId: string): Promise<boolean>
    banMember(userId: string): Promise<boolean>
    unbanMember(userId: string): Promise<boolean>

    createCategory(params: createCategoryParams): Promise<boolean>
    updateCategory(params: updateCategoryParams): Promise<boolean>
    deleteCategory(categoryId: string): Promise<boolean>

    createChannel(params: createChannelParams): Promise<boolean>
    updateChannel(params: updateChannelParams): Promise<boolean>
    deleteChannel(channelId: string): Promise<boolean>

    createRole(params: createRoleParams): Promise<boolean>
    updateRole(params: updateRoleParams): Promise<boolean>
    deleteRole(roleId: string): Promise<boolean>

    assignRole(params: assignRoleParams): Promise<boolean>
    unassignRole(params: unassignRoleParams): Promise<boolean>

    sendMessage(params: sendMessageParams): Promise<boolean>
    editMessage(params: editMessageParams): Promise<boolean>
    deleteMessage(messageId: string): Promise<boolean>

    getSingleMessage(messageId: string): Promise<IMessageReadOnly>
    getMessages(params: getMessagesParams): Promise<GetMessagesResponse>
}

export interface IChannel extends IChannelReadOnly {

}

export interface ICategory extends ICategoryReadOnly {

}

export interface IMember extends IMemberReadOnly {

}

export interface IRole extends IRoleReadOnly {

}


export interface IBotReadOnly {
    botProcess: string
    botName: string
    botPfp: string
    botPublic: boolean
    userId: string
    totalServers?: number
}