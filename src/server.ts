
import { assignRoleParams, createCategoryParams, createChannelParams, createRoleParams, editMessageParams, getMessagesParams, sendMessageParams, unassignRoleParams, updateCategoryParams, updateChannelParams, updateMemberParams, updateRoleParams } from "./types/inputs"
import { ICategory, ICategoryReadOnly, IChannel, IChannelReadOnly, IMember, IMemberReadOnly, IMessageReadOnly, IRole, IRoleReadOnly, IServer, IServerReadOnly } from "./types/subspace"
import { GetMessagesResponse } from "./types/responses"
import { AO } from "./utils/ao"
import { Constants } from "./utils/constants"

// ---------------- Server implementation ---------------- //

export class ServerReadOnly implements IServerReadOnly {
    ao: AO
    serverId: string
    ownerId: string
    name: string
    logo: string
    channels: IChannelReadOnly[]
    categories: ICategoryReadOnly[]
    roles: IRoleReadOnly[]

    constructor(data: IServerReadOnly, ao: AO) {
        this.ao = ao
        this.serverId = data.serverId
        this.ownerId = data.ownerId
        this.name = data.name
        this.logo = data.logo
        this.channels = data.channels
        this.categories = data.categories
        this.roles = data.roles
    }

    async getMember(userId: string): Promise<IMemberReadOnly> {
        const res = await this.ao.read({
            process: this.serverId,
            action: Constants.Actions.GetMember,
            tags: { UserId: userId },
        })

        return JSON.parse(res.Data) as IMemberReadOnly
    }

    async getAllMembers(): Promise<IMemberReadOnly[]> {
        const res = await this.ao.read({
            process: this.serverId,
            action: Constants.Actions.GetAllMembers,
        })

        return JSON.parse(res.Data) as IMemberReadOnly[]
    }
}

export class Server extends ServerReadOnly implements IServer {

    constructor(data: IServerReadOnly, ao: AO) {
        super(data, ao)
        Object.assign(this, data)
    }

    async getMember(userId: string): Promise<IMember> {
        const res = await this.ao.read({
            process: this.serverId,
            action: Constants.Actions.GetMember,
            tags: { UserId: userId },
        })

        return JSON.parse(res.Data) as IMember
    }

    async getAllMembers(): Promise<IMember[]> {
        const res = await this.ao.read({
            process: this.serverId,
            action: Constants.Actions.GetAllMembers,
        })

        return JSON.parse(res.Data) as IMember[]
    }

    async updateMember(params: updateMemberParams): Promise<IMember> {
        const tags: Record<string, string> = {}

        if (params.targetUserId) tags.TargetUserId = params.targetUserId
        if (params.nickname) tags.Nickname = params.nickname

        const res = await this.ao.write({
            process: this.serverId,
            action: Constants.Actions.UpdateMember,
            tags,
        })

        if (res.tags?.Status === "200") {
            const targetUserId = params.targetUserId
            if (!targetUserId) throw new Error('TargetUserId is required')
            return this.getMember(targetUserId)
        }
        throw new Error('Failed to update member')
    }

    async kickMember(userId: string): Promise<boolean> {
        const res = await this.ao.write({
            process: this.serverId,
            action: Constants.Actions.KickMember,
            tags: { TargetUserId: userId },
        })

        return res.tags?.Status === "200"
    }

    async banMember(userId: string): Promise<boolean> {
        const res = await this.ao.write({
            process: this.serverId,
            action: Constants.Actions.BanMember,
            tags: { TargetUserId: userId },
        })

        return res.tags?.Status === "200"
    }

    async unbanMember(userId: string): Promise<boolean> {
        const res = await this.ao.write({
            process: this.serverId,
            action: Constants.Actions.UnbanMember,
            tags: { TargetUserId: userId },
        })

        return res.tags?.Status === "200"
    }

    async createCategory(params: createCategoryParams): Promise<boolean> {
        if (!params.name) {
            throw new Error('Category name is required')
        }

        const tags: Record<string, string> = {
            Name: params.name,
            AllowMessaging: (params.allowMessaging ?? true) ? "1" : "0",
            AllowAttachments: (params.allowAttachments ?? true) ? "1" : "0"
        }

        if (params.orderId !== undefined) tags.OrderId = params.orderId.toString()

        const res = await this.ao.write({
            process: this.serverId,
            action: Constants.Actions.CreateCategory,
            tags,
        })

        return res.tags?.Status === "200"
    }

    async updateCategory(params: updateCategoryParams): Promise<boolean> {
        const tags: Record<string, string> = {}

        if (params.categoryId) tags.CategoryId = params.categoryId
        if (params.name) tags.Name = params.name
        if (params.allowMessaging !== undefined) tags.AllowMessaging = params.allowMessaging ? "1" : "0"
        if (params.allowAttachments !== undefined) tags.AllowAttachments = params.allowAttachments ? "1" : "0"
        if (params.orderId !== undefined) tags.OrderId = params.orderId.toString()

        const res = await this.ao.write({
            process: this.serverId,
            action: Constants.Actions.UpdateCategory,
            tags,
        })

        return res.tags?.Status === "200"
    }

    async deleteCategory(categoryId: string): Promise<boolean> {
        const res = await this.ao.write({
            process: this.serverId,
            action: Constants.Actions.DeleteCategory,
            tags: { CategoryId: categoryId },
        })

        return res.tags?.Status === "200"
    }

    async createChannel(params: createChannelParams): Promise<boolean> {
        if (!params.name) {
            throw new Error('Channel name is required')
        }

        const tags: Record<string, string> = {
            Name: params.name,
            AllowMessaging: (params.allowMessaging ?? true) ? "1" : "0",
            AllowAttachments: (params.allowAttachments ?? true) ? "1" : "0"
        }

        if (params.categoryId) tags.CategoryId = params.categoryId
        if (params.orderId !== undefined) tags.OrderId = params.orderId.toString()

        const res = await this.ao.write({
            process: this.serverId,
            action: Constants.Actions.CreateChannel,
            tags,
        })

        return res.tags?.Status === "200"
    }

    async updateChannel(params: updateChannelParams): Promise<boolean> {
        const res = await this.ao.write({
            process: this.serverId,
            action: Constants.Actions.UpdateChannel,
            tags: {
                ChannelId: params.channelId!,
                Name: params.name || "",
                AllowMessaging: params.allowMessaging ? "1" : "0",
                AllowAttachments: params.allowAttachments ? "1" : "0",
                CategoryId: params.categoryId || "",
                OrderId: params.orderId?.toString() || ""
            },
        })

        return res.tags?.Status === "200"
    }

    async deleteChannel(channelId: string): Promise<boolean> {
        const res = await this.ao.write({
            process: this.serverId,
            action: Constants.Actions.DeleteChannel,
            tags: { ChannelId: channelId },
        })

        return res.tags?.Status === "200"
    }

    async createRole(params: createRoleParams): Promise<boolean> {
        const res = await this.ao.write({
            process: this.serverId,
            action: Constants.Actions.CreateRole,
            tags: {
                Name: params.name!,
                Color: params.color || "",
                Permissions: params.permissions?.toString() || "",
                OrderId: params.orderId?.toString() || ""
            },
        })

        return res.tags?.Status === "200"
    }

    async updateRole(params: updateRoleParams): Promise<boolean> {
        const res = await this.ao.write({
            process: this.serverId,
            action: Constants.Actions.UpdateRole,
            tags: {
                RoleId: params.roleId!,
                Name: params.name || "",
                Color: params.color || "",
                Permissions: params.permissions?.toString() || "",
                OrderId: params.orderId?.toString() || ""
            },
        })

        return res.tags?.Status === "200"
    }

    async deleteRole(roleId: string): Promise<boolean> {
        const res = await this.ao.write({
            process: this.serverId,
            action: Constants.Actions.DeleteRole,
            tags: { RoleId: roleId },
        })

        return res.tags?.Status === "200"
    }

    async assignRole(params: assignRoleParams): Promise<boolean> {
        const res = await this.ao.write({
            process: this.serverId,
            action: Constants.Actions.AssignRole,
            tags: {
                TargetUserId: params.targetUserId!,
                RoleId: params.roleId!
            },
        })

        return res.tags?.Status === "200"
    }

    async unassignRole(params: unassignRoleParams): Promise<boolean> {
        const res = await this.ao.write({
            process: this.serverId,
            action: Constants.Actions.UnassignRole,
            tags: {
                TargetUserId: params.targetUserId!,
                RoleId: params.roleId
            },
        })

        return res.tags?.Status === "200"
    }

    async sendMessage(params: sendMessageParams): Promise<boolean> {
        const res = await this.ao.write({
            process: this.serverId,
            action: Constants.Actions.SendMessage,
            data: params.content,
            tags: {
                ChannelId: params.channelId,
                ReplyTo: params.replyTo || "",
                Attachments: JSON.stringify(params.attachments || [])
            },
        })

        return res.tags?.Status === "200"
    }

    async editMessage(params: editMessageParams): Promise<boolean> {
        const res = await this.ao.write({
            process: this.serverId,
            action: Constants.Actions.EditMessage,
            data: params.content,
            tags: {
                MessageId: params.messageId
            },
        })

        return res.tags?.Status === "200"
    }

    async deleteMessage(messageId: string): Promise<boolean> {
        const res = await this.ao.write({
            process: this.serverId,
            action: Constants.Actions.DeleteMessage,
            tags: { MessageId: messageId },
        })

        return res.tags?.Status === "200"
    }

    async getSingleMessage(messageId: string): Promise<IMessageReadOnly> {
        const res = await this.ao.read({
            process: this.serverId,
            action: Constants.Actions.GetSingleMessage,
            tags: { MessageId: messageId },
        })

        return JSON.parse(res.Data) as IMessageReadOnly
    }

    async getMessages(params: getMessagesParams): Promise<GetMessagesResponse> {
        const res = await this.ao.read({
            process: this.serverId,
            action: Constants.Actions.GetMessages,
            tags: {
                ChannelId: params.channelId,
                Limit: params.limit?.toString() || "",
                After: params.after || "",
                Before: params.before || ""
            },
        })

        const data = JSON.parse(res.Data)
        return {
            messages: data.messages as IMessageReadOnly[],
            channelScope: data.channelScope as "single" | "all"
        }
    }
}

// ---------------- Member implementation ---------------- //

class Member implements IMember {
    userId: string
    serverId: string
    nickname?: string
    roles: string[]

    constructor(data: IMemberReadOnly) {
        this.userId = data.userId
        this.serverId = data.serverId
        this.nickname = data.nickname
        this.roles = data.roles
    }
}

// ---------------- Channel implementation ---------------- //

class Channel implements IChannel {
    channelId: string
    name: string
    serverId: string
    categoryId?: string
    orderId?: number
    allowMessaging?: 1 | 0
    allowAttachments?: 1 | 0

    constructor(data: IChannelReadOnly) {
        this.channelId = data.channelId
        this.name = data.name
        this.serverId = data.serverId
        this.categoryId = data.categoryId
        this.orderId = data.orderId
        this.allowMessaging = data.allowMessaging
        this.allowAttachments = data.allowAttachments
    }
}

// ---------------- Category implementation ---------------- //

class Category implements ICategory {
    serverId: string
    categoryId: string
    name: string
    orderId?: number
    allowMessaging?: 1 | 0
    allowAttachments?: 1 | 0

    constructor(data: ICategoryReadOnly) {
        this.serverId = data.serverId
        this.categoryId = data.categoryId
        this.name = data.name
        this.orderId = data.orderId
        this.allowMessaging = data.allowMessaging
        this.allowAttachments = data.allowAttachments
    }
}

// ---------------- Role implementation ---------------- //

class Role implements IRole {
    id: string
    name: string
    serverId: string
    color?: string
    position: number
    permissions: any

    constructor(data: IRoleReadOnly) {
        this.id = data.id
        this.name = data.name
        this.serverId = data.serverId
        this.color = data.color
        this.position = data.position
        this.permissions = data.permissions
    }
}