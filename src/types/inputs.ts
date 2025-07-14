import { AoSigner } from "./ao"

export type SubspaceConfig = {
    CU_URL?: string
    GATEWAY_URL?: string
    Owner?: string
    signer?: AoSigner
}

export type updateProfileParams = {
    Pfp?: string
}

export type createServerParams = {
    name: string
    logo: string
}

export type updateMemberParams = {
    nickname?: string
    targetUserId?: string
}

export type createRoleParams = {
    name: string
    color?: string
    permissions?: number
    orderId?: number
}

export type updateRoleParams = {
    roleId: string
    name?: string
    color?: string
    permissions?: number
    orderId?: number
}

export type assignRoleParams = {
    targetUserId?: string
    roleId: string
}

export type unassignRoleParams = {
    targetUserId?: string
    roleId: string
}

export type sendMessageParams = {
    channelId: string
    content: string
    replyTo?: string
    attachments?: string[]
}

export type editMessageParams = {
    messageId: string
    content: string
}

export type getMessagesParams = {
    channelId: string
    limit?: number
    after?: string
    before?: string
}

export type createCategoryParams = {
    name: string
    allowMessaging?: boolean
    allowAttachments?: boolean
    orderId?: number
}

export type updateCategoryParams = {
    categoryId: string
    name?: string
    allowMessaging?: boolean
    allowAttachments?: boolean
    orderId?: number
}

export type createChannelParams = {
    name: string
    allowMessaging?: boolean
    allowAttachments?: boolean
    categoryId?: string
    orderId?: number
}

export type updateChannelParams = {
    channelId: string
    name?: string
    allowMessaging?: boolean
    allowAttachments?: boolean
    categoryId?: string
    orderId?: number
}

export type sendDMParams = {
    friendId: string
    content: string
    replyTo?: string
    attachments?: string[]
}

export type deleteDMParams = {
    friendId: string
    messageId: string
}

export type editDMParams = {
    friendId: string
    messageId: string
    content: string
}

export type getDMsParams = {
    friendId: string
    limit?: number
    after?: number
    before?: number
    eventId?: number
}

export type createBotParams = {
    botName: string
    botPfp: string
    publicBot?: boolean
}

export type addBotParams = {
    botProcess: string
    serverId: string
}

export type removeBotParams = {
    botProcess: string
    serverId: string
}

export type joinServerParams = {
    serverId: string
}

export type leaveServerParams = {
    serverId: string
}