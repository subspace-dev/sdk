import { ConnectionManager } from "../connection-manager";
import { Constants } from "../utils/constants";
import type { Tag } from "../types/ao";

export interface Server {
    serverId: string;
    ownerId: string;
    name: string;
    logo?: string;
    description?: string;
    memberCount: number;
    members?: Member[];
    channels: Channel[];
    categories: Category[];
    roles: Role[];
    createdAt?: number;
}

export interface Member {
    userId: string;
    serverId: string;
    nickname?: string;
    roles: string[];
    joinedAt?: number;
    permissions?: any;
}

export interface Channel {
    channelId: string;
    name: string;
    serverId: string;
    categoryId?: string;
    orderId?: number;
    allowMessaging?: 0 | 1;
    allowAttachments?: 0 | 1;
    description?: string;
    type?: 'text' | 'voice';
}

export interface Category {
    categoryId: string;
    serverId: string;
    name: string;
    orderId?: number;
    allowMessaging?: 0 | 1;
    allowAttachments?: 0 | 1;
}

export interface Role {
    roleId: string;
    name: string;
    serverId: string;
    color?: string;
    position: number;
    permissions: any;
    mentionable?: boolean;
    hoisted?: boolean;
}

export interface Message {
    messageId: string;
    serverId: string;
    channelId: string;
    senderId: string;
    content: string;
    timestamp: number;
    attachments?: string;
    replyTo?: string;
    edited?: boolean;
    editedAt?: number;
}

export interface MessagesResponse {
    messages: Message[];
    hasMore: boolean;
    cursor?: string;
}

export class ServerManager {
    constructor(private connectionManager: ConnectionManager) {
    }

    async createServer(params: { name: string; logo?: string; description?: string }): Promise<string | null> {
        const start = Date.now();

        try {
            // Spawn a new process with server metadata
            const tags: Tag[] = [
                { name: "Name", value: params.name },
                { name: "Owner", value: this.connectionManager.owner },
                { name: "Action", value: Constants.Actions.CreateServer }
            ];

            if (params.logo) tags.push({ name: "Logo", value: params.logo });
            if (params.description) tags.push({ name: "Description", value: params.description });
            // Generate ticker from server name (first 3-5 characters, uppercase)
            const ticker = params.name.replace(/[^a-zA-Z0-9]/g, '').slice(0, 5).toUpperCase() || 'SRVR';
            tags.push({ name: "Ticker", value: ticker });


            const serverId = await this.connectionManager.spawn({ tags });
            if (!serverId) {
                return null;
            }

            console.log("Server spawned:", serverId)

            // Wait for sources to be available (retry up to 3 times)
            for (let i = 0; i < 3; i++) {
                if (this.connectionManager.sources?.Server?.Lua) break;
                await new Promise(resolve => setTimeout(resolve, 1000 * i));
            }

            if (!this.connectionManager.sources?.Server?.Lua) {
                throw new Error("Failed to get server source code");
            }

            // Replace template placeholders in the server source code
            let serverSourceCode = this.connectionManager.sources.Server.Lua;


            // Replace placeholders
            serverSourceCode = serverSourceCode.replace('{NAME}', params.name);
            serverSourceCode = serverSourceCode.replace('{LOGO}', params.logo || '');
            serverSourceCode = serverSourceCode.replace('{TICKER}', ticker);

            // Load server source code into the spawned process
            const serverRes = await this.connectionManager.execLua({
                processId: serverId,
                code: serverSourceCode,
                tags: []
            });

            console.log("Server hydrated:", serverRes.id);

            // Wait for server to initialize
            await new Promise(resolve => setTimeout(resolve, 2000));

            // Register server with Subspace process
            const res = await this.connectionManager.sendMessage({
                processId: Constants.Subspace,
                tags: [
                    { name: "Action", value: Constants.Actions.CreateServer },
                    { name: "ServerProcess", value: serverId }
                ]
            });

            console.log("Registering server:", res)
            const msg = this.connectionManager.parseOutput(res, {
                hasMatchingTag: "Action",
                hasMatchingTagValue: "Create-Server-Response"
            });
            const success = msg.Tags.Status === "200";
            if (!success) {
                throw new Error(msg.Data);
            }

            const duration = Date.now() - start;
            return msg.Tags.ServerId;
        } catch (error) {
            const duration = Date.now() - start;
            console.error("Failed to create server:", error);
            return null;
        }
    }

    async getServer(serverId: string): Promise<Server | null> {
        try {
            const res = await this.connectionManager.dryrun({
                processId: serverId,
                tags: [
                    { name: "Action", value: Constants.Actions.Info }
                ]
            });

            const data = this.connectionManager.parseOutput(res, {
                hasMatchingTag: "Action",
                hasMatchingTagValue: "Info-Response"
            });

            const server: Server = {
                serverId,
                ownerId: data.Tags.Owner_,
                name: data.Tags.Name,
                logo: data.Tags.Logo,
                description: data.Tags.Description,
                memberCount: data.Tags.MemberCount,
                channels: JSON.parse(data.Tags.Channels),
                categories: JSON.parse(data.Tags.Categories),
                roles: JSON.parse(data.Tags.Roles)
            }

            return server;
        } catch (error) {
            return null;
        }
    }

    async updateServer(serverId: string, params: { name?: string; logo?: string; description?: string }): Promise<boolean> {
        try {
            const tags: Tag[] = [
                { name: "Action", value: Constants.Actions.UpdateServer }
            ];

            if (params.name) tags.push({ name: "Name", value: params.name });
            if (params.logo) tags.push({ name: "Logo", value: params.logo });
            if (params.description) tags.push({ name: "Description", value: params.description });

            const res = await this.connectionManager.sendMessage({
                processId: serverId,
                tags
            });

            const data = this.connectionManager.parseOutput(res);
            return data?.success === true;
        } catch (error) {
            return false;
        }
    }

    async getMember(serverId: string, userId: string): Promise<Member | null> {
        try {
            const res = await this.connectionManager.dryrun({
                processId: serverId,
                tags: [
                    { name: "Action", value: Constants.Actions.GetMember },
                    { name: "UserId", value: userId }
                ]
            });

            const data = this.connectionManager.parseOutput(res);
            return data ? data as Member : null;
        } catch (error) {
            return null;
        }
    }

    async getAllMembers(serverId: string): Promise<Member[]> {
        try {
            const res = await this.connectionManager.dryrun({
                processId: serverId,
                tags: [
                    { name: "Action", value: Constants.Actions.GetAllMembers }
                ]
            });

            const msg = this.connectionManager.parseOutput(res);
            return JSON.parse(msg.Data) || [];
        } catch (error) {
            return [];
        }
    }

    async updateMember(serverId: string, params: { userId: string; nickname?: string; roles?: string[] }): Promise<boolean> {
        try {
            const tags: Tag[] = [
                { name: "Action", value: Constants.Actions.UpdateMember },
                { name: "UserId", value: params.userId }
            ];

            if (params.nickname) tags.push({ name: "Nickname", value: params.nickname });
            if (params.roles) tags.push({ name: "Roles", value: JSON.stringify(params.roles) });

            const res = await this.connectionManager.sendMessage({
                processId: serverId,
                tags
            });

            const data = this.connectionManager.parseOutput(res);
            return data?.success === true;
        } catch (error) {
            return false;
        }
    }

    async kickMember(serverId: string, userId: string): Promise<boolean> {
        try {
            const res = await this.connectionManager.sendMessage({
                processId: serverId,
                tags: [
                    { name: "Action", value: Constants.Actions.KickMember },
                    { name: "UserId", value: userId }
                ]
            });

            const data = this.connectionManager.parseOutput(res);
            return data?.success === true;
        } catch (error) {
            return false;
        }
    }

    async banMember(serverId: string, userId: string): Promise<boolean> {
        try {
            const res = await this.connectionManager.sendMessage({
                processId: serverId,
                tags: [
                    { name: "Action", value: Constants.Actions.BanMember },
                    { name: "UserId", value: userId }
                ]
            });

            const data = this.connectionManager.parseOutput(res);
            return data?.success === true;
        } catch (error) {
            return false;
        }
    }

    async unbanMember(serverId: string, userId: string): Promise<boolean> {
        try {
            const res = await this.connectionManager.sendMessage({
                processId: serverId,
                tags: [
                    { name: "Action", value: Constants.Actions.UnbanMember },
                    { name: "UserId", value: userId }
                ]
            });

            const data = this.connectionManager.parseOutput(res);
            return data?.success === true;
        } catch (error) {
            return false;
        }
    }

    async createCategory(serverId: string, params: { name: string; orderId?: number }): Promise<boolean> {
        try {
            const tags: Tag[] = [
                { name: "Action", value: Constants.Actions.CreateCategory },
                { name: "Name", value: params.name }
            ];

            if (params.orderId !== undefined) {
                tags.push({ name: "OrderId", value: params.orderId.toString() });
            }

            const res = await this.connectionManager.sendMessage({
                processId: serverId,
                tags
            });

            const data = this.connectionManager.parseOutput(res);
            return data?.success === true;
        } catch (error) {
            return false;
        }
    }

    async updateCategory(serverId: string, params: { categoryId: string; name?: string; orderId?: number }): Promise<boolean> {
        try {
            const tags: Tag[] = [
                { name: "Action", value: Constants.Actions.UpdateCategory },
                { name: "CategoryId", value: params.categoryId }
            ];

            if (params.name) tags.push({ name: "Name", value: params.name });
            if (params.orderId !== undefined) {
                tags.push({ name: "OrderId", value: params.orderId.toString() });
            }

            const res = await this.connectionManager.sendMessage({
                processId: serverId,
                tags
            });

            const data = this.connectionManager.parseOutput(res);
            return data?.success === true;
        } catch (error) {
            return false;
        }
    }

    async deleteCategory(serverId: string, categoryId: string): Promise<boolean> {
        try {
            const res = await this.connectionManager.sendMessage({
                processId: serverId,
                tags: [
                    { name: "Action", value: Constants.Actions.DeleteCategory },
                    { name: "CategoryId", value: categoryId }
                ]
            });

            const data = this.connectionManager.parseOutput(res);
            return data?.success === true;
        } catch (error) {
            return false;
        }
    }

    async createChannel(serverId: string, params: { name: string; categoryId?: string; orderId?: number; type?: 'text' | 'voice' }): Promise<boolean> {
        try {
            const tags: Tag[] = [
                { name: "Action", value: Constants.Actions.CreateChannel },
                { name: "Name", value: params.name }
            ];

            if (params.categoryId) tags.push({ name: "CategoryId", value: params.categoryId });
            if (params.orderId !== undefined) tags.push({ name: "OrderId", value: params.orderId.toString() });
            if (params.type) tags.push({ name: "Type", value: params.type });

            const res = await this.connectionManager.sendMessage({
                processId: serverId,
                tags
            });

            const data = this.connectionManager.parseOutput(res);
            return data?.success === true;
        } catch (error) {
            return false;
        }
    }

    async updateChannel(serverId: string, params: { channelId: string; name?: string; categoryId?: string; orderId?: number }): Promise<boolean> {
        try {
            const tags: Tag[] = [
                { name: "Action", value: Constants.Actions.UpdateChannel },
                { name: "ChannelId", value: params.channelId }
            ];

            if (params.name) tags.push({ name: "Name", value: params.name });
            if (params.categoryId) tags.push({ name: "CategoryId", value: params.categoryId });
            if (params.orderId !== undefined) tags.push({ name: "OrderId", value: params.orderId.toString() });

            const res = await this.connectionManager.sendMessage({
                processId: serverId,
                tags
            });

            const data = this.connectionManager.parseOutput(res);
            return data?.success === true;
        } catch (error) {
            return false;
        }
    }

    async deleteChannel(serverId: string, channelId: string): Promise<boolean> {
        try {
            const res = await this.connectionManager.sendMessage({
                processId: serverId,
                tags: [
                    { name: "Action", value: Constants.Actions.DeleteChannel },
                    { name: "ChannelId", value: channelId }
                ]
            });

            const data = this.connectionManager.parseOutput(res);
            return data?.success === true;
        } catch (error) {
            return false;
        }
    }

    async createRole(serverId: string, params: { name: string; color?: string; permissions?: any; position?: number }): Promise<boolean> {
        try {
            const tags: Tag[] = [
                { name: "Action", value: Constants.Actions.CreateRole },
                { name: "Name", value: params.name }
            ];

            if (params.color) tags.push({ name: "Color", value: params.color });
            if (params.permissions) tags.push({ name: "Permissions", value: JSON.stringify(params.permissions) });
            if (params.position !== undefined) tags.push({ name: "Position", value: params.position.toString() });

            const res = await this.connectionManager.sendMessage({
                processId: serverId,
                tags
            });

            const data = this.connectionManager.parseOutput(res);
            return data?.success === true;
        } catch (error) {
            return false;
        }
    }

    async updateRole(serverId: string, params: { roleId: string; name?: string; color?: string; permissions?: any; position?: number }): Promise<boolean> {
        try {
            const tags: Tag[] = [
                { name: "Action", value: Constants.Actions.UpdateRole },
                { name: "RoleId", value: params.roleId }
            ];

            if (params.name) tags.push({ name: "Name", value: params.name });
            if (params.color) tags.push({ name: "Color", value: params.color });
            if (params.permissions) tags.push({ name: "Permissions", value: JSON.stringify(params.permissions) });
            if (params.position !== undefined) tags.push({ name: "Position", value: params.position.toString() });

            const res = await this.connectionManager.sendMessage({
                processId: serverId,
                tags
            });

            const data = this.connectionManager.parseOutput(res);
            return data?.success === true;
        } catch (error) {
            return false;
        }
    }

    async deleteRole(serverId: string, roleId: string): Promise<boolean> {
        try {
            const res = await this.connectionManager.sendMessage({
                processId: serverId,
                tags: [
                    { name: "Action", value: Constants.Actions.DeleteRole },
                    { name: "RoleId", value: roleId }
                ]
            });

            const data = this.connectionManager.parseOutput(res);
            return data?.success === true;
        } catch (error) {
            return false;
        }
    }

    async assignRole(serverId: string, params: { userId: string; roleId: string }): Promise<boolean> {
        try {
            const res = await this.connectionManager.sendMessage({
                processId: serverId,
                tags: [
                    { name: "Action", value: Constants.Actions.AssignRole },
                    { name: "UserId", value: params.userId },
                    { name: "RoleId", value: params.roleId }
                ]
            });

            const data = this.connectionManager.parseOutput(res);
            return data?.success === true;
        } catch (error) {
            return false;
        }
    }

    async unassignRole(serverId: string, params: { userId: string; roleId: string }): Promise<boolean> {
        try {
            const res = await this.connectionManager.sendMessage({
                processId: serverId,
                tags: [
                    { name: "Action", value: Constants.Actions.UnassignRole },
                    { name: "UserId", value: params.userId },
                    { name: "RoleId", value: params.roleId }
                ]
            });

            const data = this.connectionManager.parseOutput(res);
            return data?.success === true;
        } catch (error) {
            return false;
        }
    }

    async sendMessage(serverId: string, params: { channelId: string; content: string; attachments?: string; replyTo?: string }): Promise<boolean> {
        try {
            const tags: Tag[] = [
                { name: "Action", value: Constants.Actions.SendMessage },
                { name: "ChannelId", value: params.channelId },
            ];

            if (params.attachments) tags.push({ name: "Attachments", value: params.attachments });
            if (params.replyTo) tags.push({ name: "ReplyTo", value: params.replyTo });

            const res = await this.connectionManager.sendMessage({
                processId: serverId,
                data: params.content,
                tags
            });

            const data = this.connectionManager.parseOutput(res);
            return data?.success === true;
        } catch (error) {
            return false;
        }
    }

    async editMessage(serverId: string, params: { messageId: string; content: string }): Promise<boolean> {
        try {
            const res = await this.connectionManager.sendMessage({
                processId: serverId,
                tags: [
                    { name: "Action", value: Constants.Actions.EditMessage },
                    { name: "MessageId", value: params.messageId },
                    { name: "Content", value: params.content }
                ]
            });

            const data = this.connectionManager.parseOutput(res);
            return data?.success === true;
        } catch (error) {
            return false;
        }
    }

    async deleteMessage(serverId: string, messageId: string): Promise<boolean> {
        try {
            const res = await this.connectionManager.sendMessage({
                processId: serverId,
                tags: [
                    { name: "Action", value: Constants.Actions.DeleteMessage },
                    { name: "MessageId", value: messageId }
                ]
            });

            const data = this.connectionManager.parseOutput(res);
            return data?.success === true;
        } catch (error) {
            return false;
        }
    }

    async getMessage(serverId: string, messageId: string): Promise<Message | null> {
        try {
            const res = await this.connectionManager.dryrun({
                processId: serverId,
                tags: [
                    { name: "Action", value: Constants.Actions.GetSingleMessage },
                    { name: "MessageId", value: messageId }
                ]
            });

            const data = this.connectionManager.parseOutput(res);
            return data ? data as Message : null;
        } catch (error) {
            return null;
        }
    }

    async getMessages(serverId: string, params: { channelId: string; limit?: number; before?: string; after?: string }): Promise<MessagesResponse | null> {
        try {
            const tags: Tag[] = [
                { name: "Action", value: Constants.Actions.GetMessages },
                { name: "ChannelId", value: params.channelId }
            ];

            if (params.limit) tags.push({ name: "Limit", value: params.limit.toString() });
            if (params.before) tags.push({ name: "Before", value: params.before });
            if (params.after) tags.push({ name: "After", value: params.after });

            const res = await this.connectionManager.dryrun({
                processId: serverId,
                tags
            });

            const data = JSON.parse(this.connectionManager.parseOutput(res).Data);
            console.log("getMessages", data)
            return data ? data as MessagesResponse : null;
        } catch (error) {
            return null;
        }
    }
} 