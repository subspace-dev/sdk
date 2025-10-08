// Profile Input Interfaces
export interface ICreateProfile {
    pfp?: string
    banner?: string
    bio?: string
}

// Server Input Interfaces
export interface ICreateServer {
    serverName: string
    serverDescription?: string
    serverPfp?: string
    serverBanner?: string
}

export interface IUpdateServer extends ICreateServer {
    serverId: string
}

// Category Input Interfaces
export interface ICreateCategory {
    serverId: string
    categoryName: string
    categoryOrder?: number
}

export interface IUpdateCategory {
    serverId: string
    categoryId: string
    categoryName?: string
    categoryOrder?: number
}

export interface IDeleteCategory {
    serverId: string
    categoryId: string
}

// Channel Input Interfaces
export interface ICreateChannel {
    serverId: string
    channelName: string
    categoryId?: string
    channelOrder?: number
    allowMessaging?: number
    allowAttachments?: number
}

export interface IUpdateChannel {
    serverId: string
    channelId: string
    channelName?: string
    categoryId?: string
    channelOrder?: number
    allowMessaging?: number
    allowAttachments?: number
}

export interface IDeleteChannel {
    serverId: string
    channelId: string
}

// Role Input Interfaces
export interface ICreateRole {
    serverId: string
    roleName: string
    roleColor?: string
    rolePermissions?: number
    roleOrder?: number
    mentionable?: boolean
    hoist?: boolean
}

export interface IUpdateRole {
    serverId: string
    roleId: string
    roleName?: string
    roleColor?: string
    rolePermissions?: number
    roleOrder?: number
    mentionable?: boolean
    hoist?: boolean
}

export interface IDeleteRole {
    serverId: string
    roleId: string
}

export interface IAssignRole {
    serverId: string
    userId: string
    roleId: string
}

export interface IUnassignRole {
    serverId: string
    userId: string
    roleId: string
}

// Message Input Interfaces
export interface ISendMessage {
    serverId: string
    channelId: string
    content: string
    attachments?: string[]
}

export interface IUpdateMessage {
    serverId: string
    channelId: string
    messageId: string
    content: string
}

export interface IDeleteMessage {
    serverId: string
    channelId: string
    messageId: string
}

// DM Input Interfaces
export interface ISendDM {
    userId: string
    content: string
}

export interface IEditDM {
    userId: string
    messageId: string
    content: string
}

export interface IDeleteDM {
    userId: string
    messageId: string
}

export interface IUpdateMember {
    serverId: string
    userId: string
    nickname?: string | null
}

export interface IKickMember {
    serverId: string
    userId: string
}

export interface IBanMember extends IKickMember { }
export interface IUnbanMember extends IBanMember { }

export interface IGetMember {
    serverId: string
    userId: string
}