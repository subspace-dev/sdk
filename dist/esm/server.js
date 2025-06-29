import { Constants } from "./utils/constants";
// ---------------- Server implementation ---------------- //
export class ServerReadOnly {
    ao;
    serverId;
    ownerId;
    name;
    logo;
    channels;
    categories;
    roles;
    constructor(data, ao) {
        this.ao = ao;
        this.serverId = data.serverId;
        this.ownerId = data.ownerId;
        this.name = data.name;
        this.logo = data.logo;
        this.channels = data.channels;
        this.categories = data.categories;
        this.roles = data.roles;
    }
    async getMember(userId) {
        const res = await this.ao.read({
            process: this.serverId,
            action: Constants.Actions.GetMember,
            tags: { UserId: userId },
        });
        return JSON.parse(res.Data);
    }
    async getAllMembers() {
        const res = await this.ao.read({
            process: this.serverId,
            action: Constants.Actions.GetAllMembers,
        });
        return JSON.parse(res.Data);
    }
}
export class Server extends ServerReadOnly {
    constructor(data, ao) {
        super(data, ao);
        Object.assign(this, data);
    }
    async getMember(userId) {
        const res = await this.ao.read({
            process: this.serverId,
            action: Constants.Actions.GetMember,
            tags: { UserId: userId },
        });
        return JSON.parse(res.Data);
    }
    async getAllMembers() {
        const res = await this.ao.read({
            process: this.serverId,
            action: Constants.Actions.GetAllMembers,
        });
        return JSON.parse(res.Data);
    }
    async updateMember(params) {
        const tags = {};
        if (params.targetUserId)
            tags.TargetUserId = params.targetUserId;
        if (params.nickname)
            tags.Nickname = params.nickname;
        const res = await this.ao.write({
            process: this.serverId,
            action: Constants.Actions.UpdateMember,
            tags,
        });
        if (res.tags?.Status === "200") {
            const targetUserId = params.targetUserId;
            if (!targetUserId)
                throw new Error('TargetUserId is required');
            return this.getMember(targetUserId);
        }
        throw new Error('Failed to update member');
    }
    async kickMember(userId) {
        const res = await this.ao.write({
            process: this.serverId,
            action: Constants.Actions.KickMember,
            tags: { TargetUserId: userId },
        });
        return res.tags?.Status === "200";
    }
    async banMember(userId) {
        const res = await this.ao.write({
            process: this.serverId,
            action: Constants.Actions.BanMember,
            tags: { TargetUserId: userId },
        });
        return res.tags?.Status === "200";
    }
    async unbanMember(userId) {
        const res = await this.ao.write({
            process: this.serverId,
            action: Constants.Actions.UnbanMember,
            tags: { TargetUserId: userId },
        });
        return res.tags?.Status === "200";
    }
    async createCategory(params) {
        if (!params.name) {
            throw new Error('Category name is required');
        }
        const tags = {
            Name: params.name,
            AllowMessaging: (params.allowMessaging ?? true) ? "1" : "0",
            AllowAttachments: (params.allowAttachments ?? true) ? "1" : "0"
        };
        if (params.orderId !== undefined)
            tags.OrderId = params.orderId.toString();
        const res = await this.ao.write({
            process: this.serverId,
            action: Constants.Actions.CreateCategory,
            tags,
        });
        return res.tags?.Status === "200";
    }
    async updateCategory(params) {
        const tags = {};
        if (params.categoryId)
            tags.CategoryId = params.categoryId;
        if (params.name)
            tags.Name = params.name;
        if (params.allowMessaging !== undefined)
            tags.AllowMessaging = params.allowMessaging ? "1" : "0";
        if (params.allowAttachments !== undefined)
            tags.AllowAttachments = params.allowAttachments ? "1" : "0";
        if (params.orderId !== undefined)
            tags.OrderId = params.orderId.toString();
        const res = await this.ao.write({
            process: this.serverId,
            action: Constants.Actions.UpdateCategory,
            tags,
        });
        return res.tags?.Status === "200";
    }
    async deleteCategory(categoryId) {
        const res = await this.ao.write({
            process: this.serverId,
            action: Constants.Actions.DeleteCategory,
            tags: { CategoryId: categoryId },
        });
        return res.tags?.Status === "200";
    }
    async createChannel(params) {
        if (!params.name) {
            throw new Error('Channel name is required');
        }
        const tags = {
            Name: params.name,
            AllowMessaging: (params.allowMessaging ?? true) ? "1" : "0",
            AllowAttachments: (params.allowAttachments ?? true) ? "1" : "0"
        };
        if (params.categoryId)
            tags.CategoryId = params.categoryId;
        if (params.orderId !== undefined)
            tags.OrderId = params.orderId.toString();
        const res = await this.ao.write({
            process: this.serverId,
            action: Constants.Actions.CreateChannel,
            tags,
        });
        return res.tags?.Status === "200";
    }
    async updateChannel(params) {
        const res = await this.ao.write({
            process: this.serverId,
            action: Constants.Actions.UpdateChannel,
            tags: {
                ChannelId: params.channelId,
                Name: params.name || "",
                AllowMessaging: params.allowMessaging ? "1" : "0",
                AllowAttachments: params.allowAttachments ? "1" : "0",
                CategoryId: params.categoryId || "",
                OrderId: params.orderId?.toString() || ""
            },
        });
        return res.tags?.Status === "200";
    }
    async deleteChannel(channelId) {
        const res = await this.ao.write({
            process: this.serverId,
            action: Constants.Actions.DeleteChannel,
            tags: { ChannelId: channelId },
        });
        return res.tags?.Status === "200";
    }
    async createRole(params) {
        const res = await this.ao.write({
            process: this.serverId,
            action: Constants.Actions.CreateRole,
            tags: {
                Name: params.name,
                Color: params.color || "",
                Permissions: params.permissions?.toString() || "",
                OrderId: params.orderId?.toString() || ""
            },
        });
        return res.tags?.Status === "200";
    }
    async updateRole(params) {
        const res = await this.ao.write({
            process: this.serverId,
            action: Constants.Actions.UpdateRole,
            tags: {
                RoleId: params.roleId,
                Name: params.name || "",
                Color: params.color || "",
                Permissions: params.permissions?.toString() || "",
                OrderId: params.orderId?.toString() || ""
            },
        });
        return res.tags?.Status === "200";
    }
    async deleteRole(roleId) {
        const res = await this.ao.write({
            process: this.serverId,
            action: Constants.Actions.DeleteRole,
            tags: { RoleId: roleId },
        });
        return res.tags?.Status === "200";
    }
    async assignRole(params) {
        const res = await this.ao.write({
            process: this.serverId,
            action: Constants.Actions.AssignRole,
            tags: {
                TargetUserId: params.targetUserId,
                RoleId: params.roleId
            },
        });
        return res.tags?.Status === "200";
    }
    async unassignRole(params) {
        const res = await this.ao.write({
            process: this.serverId,
            action: Constants.Actions.UnassignRole,
            tags: {
                TargetUserId: params.targetUserId,
                RoleId: params.roleId
            },
        });
        return res.tags?.Status === "200";
    }
    async sendMessage(params) {
        const res = await this.ao.write({
            process: this.serverId,
            action: Constants.Actions.SendMessage,
            data: params.content,
            tags: {
                ChannelId: params.channelId,
                ReplyTo: params.replyTo || "",
                Attachments: JSON.stringify(params.attachments || [])
            },
        });
        return res.tags?.Status === "200";
    }
    async editMessage(params) {
        const res = await this.ao.write({
            process: this.serverId,
            action: Constants.Actions.EditMessage,
            data: params.content,
            tags: {
                MessageId: params.messageId
            },
        });
        return res.tags?.Status === "200";
    }
    async deleteMessage(messageId) {
        const res = await this.ao.write({
            process: this.serverId,
            action: Constants.Actions.DeleteMessage,
            tags: { MessageId: messageId },
        });
        return res.tags?.Status === "200";
    }
    async getSingleMessage(messageId) {
        const res = await this.ao.read({
            process: this.serverId,
            action: Constants.Actions.GetSingleMessage,
            tags: { MessageId: messageId },
        });
        return JSON.parse(res.Data);
    }
    async getMessages(params) {
        const res = await this.ao.read({
            process: this.serverId,
            action: Constants.Actions.GetMessages,
            tags: {
                ChannelId: params.channelId,
                Limit: params.limit?.toString() || "",
                After: params.after || "",
                Before: params.before || ""
            },
        });
        const data = JSON.parse(res.Data);
        return {
            messages: data.messages,
            channelScope: data.channelScope
        };
    }
}
// ---------------- Member implementation ---------------- //
class Member {
    userId;
    serverId;
    nickname;
    roles;
    constructor(data) {
        this.userId = data.userId;
        this.serverId = data.serverId;
        this.nickname = data.nickname;
        this.roles = data.roles;
    }
}
// ---------------- Channel implementation ---------------- //
class Channel {
    channelId;
    name;
    serverId;
    categoryId;
    orderId;
    allowMessaging;
    allowAttachments;
    constructor(data) {
        this.channelId = data.channelId;
        this.name = data.name;
        this.serverId = data.serverId;
        this.categoryId = data.categoryId;
        this.orderId = data.orderId;
        this.allowMessaging = data.allowMessaging;
        this.allowAttachments = data.allowAttachments;
    }
}
// ---------------- Category implementation ---------------- //
class Category {
    serverId;
    categoryId;
    name;
    orderId;
    allowMessaging;
    allowAttachments;
    constructor(data) {
        this.serverId = data.serverId;
        this.categoryId = data.categoryId;
        this.name = data.name;
        this.orderId = data.orderId;
        this.allowMessaging = data.allowMessaging;
        this.allowAttachments = data.allowAttachments;
    }
}
// ---------------- Role implementation ---------------- //
class Role {
    id;
    name;
    serverId;
    color;
    position;
    permissions;
    constructor(data) {
        this.id = data.id;
        this.name = data.name;
        this.serverId = data.serverId;
        this.color = data.color;
        this.position = data.position;
        this.permissions = data.permissions;
    }
}
