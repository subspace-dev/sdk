import { ConnectionManager } from "../connection-manager";
import { Constants } from "../utils/constants";
import { loggedAction } from "../utils/logger";
import type { Tag } from "../types/ao";

export interface Server {
    serverId: string;
    ownerId: string;
    name: string;
    logo?: string;
    description?: string;
    version?: string;
    memberCount: number;
    members?: Member[];
    channels: Channel[];
    categories: Category[];
    // roles: Role[];
    roles: Record<string, Role>; // roleId -> role
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
    orderId?: number;  // Server uses orderId for role hierarchy
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
        return loggedAction('➕ creating server', params, async () => {
            const start = Date.now();

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
                throw new Error("Failed to spawn server process");
            }

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
            serverSourceCode = serverSourceCode.replace('{DESCRIPTION}', params.description || '');
            serverSourceCode = serverSourceCode.replace('{TICKER}', ticker);

            // Load server source code into the spawned process
            const serverRes = await this.connectionManager.execLua({
                processId: serverId,
                code: serverSourceCode,
                tags: []
            });

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

            const msg = this.connectionManager.parseOutput(res, {
                hasMatchingTag: "Action",
                hasMatchingTagValue: "Create-Server-Response"
            });
            const success = msg.Tags.Status === "200";
            if (!success) {
                throw new Error(msg.Data);
            }

            return msg.Tags.ServerId;
        });
    }

    async getServer(serverId: string): Promise<Server | null> {
        return loggedAction('🔍 getting server', { serverId }, async () => {
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
                version: data.Tags.Version,
                memberCount: parseInt(data.Tags.MemberCount) || 0,
                channels: JSON.parse(data.Tags.Channels),
                categories: JSON.parse(data.Tags.Categories),
                roles: JSON.parse(data.Tags.Roles).reduce((acc: Record<string, Role>, role: Role) => {
                    acc[role.roleId.toString()] = role;
                    return acc;
                }, {})
            }

            return server;
        });
    }

    async updateServer(serverId: string, params: { name?: string; logo?: string; description?: string }): Promise<boolean> {
        return loggedAction('✏️ updating server', { serverId, ...params }, async () => {
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

            const data = this.connectionManager.parseOutput(res, { hasMatchingTag: "Action", hasMatchingTagValue: "Update-Server-Response" });
            return data?.Tags?.Status === "200";
        });
    }

    async updateServerCode(serverId: string): Promise<boolean> {
        return loggedAction('🔄 updating server code', { serverId }, async () => {
            await this.connectionManager.refreshSources()

            // Wait for sources to be available (retry up to 3 times)
            for (let i = 0; i < 3; i++) {
                if (this.connectionManager.sources?.Server?.Lua) break;
                await new Promise(resolve => setTimeout(resolve, 1000 * i));
            }

            if (!this.connectionManager.sources?.Server?.Lua) {
                throw new Error("Failed to get latest server source code");
            }

            // Get the current server to extract its metadata
            const currentServer = await this.getServer(serverId);
            if (!currentServer) {
                throw new Error("Server not found");
            }

            // Get the latest server source code
            let serverSourceCode = this.connectionManager.sources.Server.Lua;

            // Replace template placeholders with current server data
            serverSourceCode = serverSourceCode.replace('{NAME}', currentServer.name);
            serverSourceCode = serverSourceCode.replace('{LOGO}', currentServer.logo || '');
            serverSourceCode = serverSourceCode.replace('{DESCRIPTION}', currentServer.description || '');

            // Generate ticker from current server name
            const ticker = currentServer.name.replace(/[^a-zA-Z0-9]/g, '').slice(0, 5).toUpperCase() || 'SRVR';
            serverSourceCode = serverSourceCode.replace('{TICKER}', ticker);

            // Execute the updated server source code
            const res = await this.connectionManager.execLua({
                processId: serverId,
                code: serverSourceCode,
                tags: [{ name: "Action", value: Constants.Actions.UpdateServerCode }]
            });

            const data = this.connectionManager.parseOutput(res);
            return data?.success !== false; // Consider success if no explicit failure
        });
    }

    async getMember(serverId: string, userId: string): Promise<Member | null> {
        return loggedAction('🔍 getting member', { serverId, userId }, async () => {
            const res = await this.connectionManager.dryrun({
                processId: serverId,
                tags: [
                    { name: "Action", value: Constants.Actions.GetMember },
                    { name: "UserId", value: userId }
                ]
            });

            const data = JSON.parse(this.connectionManager.parseOutput(res).Tags.Member);
            return data ? data as Member : null;
        });
    }

    async getAllMembers(serverId: string): Promise<Record<string, Member>> {
        return loggedAction('🔍 getting all members', { serverId }, async () => {
            const res = await this.connectionManager.dryrun({
                processId: serverId,
                tags: [
                    { name: "Action", value: Constants.Actions.GetAllMembers }
                ]
            });

            const msg = this.connectionManager.parseOutput(res);
            return JSON.parse(msg.Data);
        });
    }

    async updateMember(serverId: string, params: { userId: string; nickname?: string; roles?: string[] }): Promise<boolean> {
        return loggedAction('✏️ updating member', { serverId, userId: params.userId }, async () => {
            const tags: Tag[] = [
                { name: "Action", value: Constants.Actions.UpdateMember },
                { name: "TargetUserId", value: params.userId }
            ];

            if (params.nickname !== undefined) {
                // Use a special sentinel value for clearing nicknames to avoid empty string issues
                const nicknameValue = params.nickname === "" ? "__CLEAR_NICKNAME__" : params.nickname;
                tags.push({ name: "Nickname", value: nicknameValue });
            }
            if (params.roles) tags.push({ name: "Roles", value: JSON.stringify(params.roles) });

            const res = await this.connectionManager.sendMessage({
                processId: serverId,
                tags
            });

            const data = this.connectionManager.parseOutput(res, { hasMatchingTag: "Action", hasMatchingTagValue: "Update-Member-Response" });
            return data?.Tags.Status === "200";
        });
    }

    async joinServer(serverId: string): Promise<boolean> {
        return loggedAction('➡️ joining server', { serverId }, async () => {
            const res = await this.connectionManager.sendMessage({
                processId: serverId,
                tags: [
                    { name: "Action", value: Constants.Actions.JoinServer }
                ]
            });

            const data = this.connectionManager.parseOutput(res, { hasMatchingTag: "Action", hasMatchingTagValue: "Join-Server-Response" });
            return data?.Tags.Status === "200";
        });
    }

    async leaveServer(serverId: string): Promise<boolean> {
        return loggedAction('⬅️ leaving server', { serverId }, async () => {
            const res = await this.connectionManager.sendMessage({
                processId: serverId,
                tags: [
                    { name: "Action", value: Constants.Actions.LeaveServer }
                ]
            });

            const data = this.connectionManager.parseOutput(res, { hasMatchingTag: "Action", hasMatchingTagValue: "Leave-Server-Response" });
            return data?.Tags.Status === "200";
        });
    }

    async kickMember(serverId: string, userId: string): Promise<boolean> {
        return loggedAction('👢 kicking member', { serverId, userId }, async () => {
            const res = await this.connectionManager.sendMessage({
                processId: serverId,
                tags: [
                    { name: "Action", value: Constants.Actions.KickMember },
                    { name: "TargetUserId", value: userId }
                ]
            });

            const data = this.connectionManager.parseOutput(res, { hasMatchingTag: "Action", hasMatchingTagValue: "Kick-Member-Response" });
            return data?.Tags.Status === "200";
        });
    }

    async banMember(serverId: string, userId: string): Promise<boolean> {
        return loggedAction('🚫 banning member', { serverId, userId }, async () => {
            const res = await this.connectionManager.sendMessage({
                processId: serverId,
                tags: [
                    { name: "Action", value: Constants.Actions.BanMember },
                    { name: "TargetUserId", value: userId }
                ]
            });

            const data = this.connectionManager.parseOutput(res, { hasMatchingTag: "Action", hasMatchingTagValue: "Ban-Member-Response" });
            return data?.Tags.Status === "200";
        });
    }

    async unbanMember(serverId: string, userId: string): Promise<boolean> {
        return loggedAction('✅ unbanning member', { serverId, userId }, async () => {
            const res = await this.connectionManager.sendMessage({
                processId: serverId,
                tags: [
                    { name: "Action", value: Constants.Actions.UnbanMember },
                    { name: "TargetUserId", value: userId }
                ]
            });

            const data = this.connectionManager.parseOutput(res, { hasMatchingTag: "Action", hasMatchingTagValue: "Unban-Member-Response" });
            return data?.Tags.Status === "200";
        });
    }

    async createCategory(serverId: string, params: { name: string; orderId?: number }): Promise<boolean> {
        return loggedAction('➕ creating category', { serverId, ...params }, async () => {
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

            const data = this.connectionManager.parseOutput(res, { hasMatchingTag: "Action", hasMatchingTagValue: "Create-Category-Response" });
            return data?.Tags?.Status === "200";
        });
    }

    async updateCategory(serverId: string, params: { categoryId: string; name?: string; orderId?: number }): Promise<boolean> {
        return loggedAction('✏️ updating category', { serverId, categoryId: params.categoryId }, async () => {
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

            const data = this.connectionManager.parseOutput(res, { hasMatchingTag: "Action", hasMatchingTagValue: "Update-Category-Response" });
            return data?.Tags?.Status === "200";
        });
    }

    async deleteCategory(serverId: string, categoryId: string): Promise<boolean> {
        return loggedAction('🗑️ deleting category', { serverId, categoryId }, async () => {
            const res = await this.connectionManager.sendMessage({
                processId: serverId,
                tags: [
                    { name: "Action", value: Constants.Actions.DeleteCategory },
                    { name: "CategoryId", value: categoryId }
                ]
            });

            const data = this.connectionManager.parseOutput(res, { hasMatchingTag: "Action", hasMatchingTagValue: "Delete-Category-Response" });
            return data?.Tags?.Status === "200";
        });
    }

    async createChannel(serverId: string, params: { name: string; categoryId?: string; orderId?: number; type?: 'text' | 'voice' }): Promise<boolean> {
        return loggedAction('➕ creating channel', { serverId, ...params }, async () => {
            const tags: Tag[] = [
                { name: "Action", value: Constants.Actions.CreateChannel },
                { name: "Name", value: params.name }
            ];

            if (params.categoryId) tags.push({ name: "CategoryId", value: params.categoryId });
            if (params.orderId !== undefined) tags.push({ name: "OrderId", value: params.orderId.toString() });
            // if (params.type) tags.push({ name: "Type", value: params.type }); // Commented out - server doesn't handle this yet

            const res = await this.connectionManager.sendMessage({
                processId: serverId,
                tags
            });

            const data = this.connectionManager.parseOutput(res, { hasMatchingTag: "Action", hasMatchingTagValue: "Create-Channel-Response" });
            return data?.Tags?.Status === "200";
        });
    }

    async updateChannel(serverId: string, params: { channelId: string; name?: string; categoryId?: string | null; orderId?: number; allowMessaging?: 0 | 1; allowAttachments?: 0 | 1 }): Promise<boolean> {
        return loggedAction('✏️ updating channel', { serverId, channelId: params.channelId }, async () => {
            const tags: Tag[] = [
                { name: "Action", value: Constants.Actions.UpdateChannel },
                { name: "ChannelId", value: params.channelId }
            ];

            // console.log('🔧 SDK DEBUG: Processing params', {
            //     name: params.name,
            //     categoryId: params.categoryId,
            //     categoryIdUndefined: params.categoryId === undefined,
            //     categoryIdNotUndefined: params.categoryId !== undefined,
            //     orderId: params.orderId,
            //     allowMessaging: params.allowMessaging,
            //     allowAttachments: params.allowAttachments
            // });

            if (params.name) tags.push({ name: "Name", value: params.name });
            if (params.categoryId !== undefined) {
                const categoryValue = params.categoryId || "";
                // console.log('🔧 SDK DEBUG: Adding CategoryId tag', {
                //     originalCategoryId: params.categoryId,
                //     categoryValue,
                //     categoryValueType: typeof categoryValue
                // });
                tags.push({ name: "CategoryId", value: categoryValue });
            } else {
                // console.log('🔧 SDK DEBUG: CategoryId is undefined, skipping tag');
            }
            if (params.orderId !== undefined) tags.push({ name: "OrderId", value: params.orderId.toString() });
            if (params.allowMessaging !== undefined) tags.push({ name: "AllowMessaging", value: params.allowMessaging.toString() });
            if (params.allowAttachments !== undefined) tags.push({ name: "AllowAttachments", value: params.allowAttachments.toString() });

            // console.log('📤 SDK: Sending tags to server:', tags);

            const res = await this.connectionManager.sendMessage({
                processId: serverId,
                tags
            });

            const data = this.connectionManager.parseOutput(res, { hasMatchingTag: "Action", hasMatchingTagValue: "Update-Channel-Response" });
            // console.log('📥 SDK: Server response:', data);
            return data?.Tags?.Status === "200";
        });
    }

    async deleteChannel(serverId: string, channelId: string): Promise<boolean> {
        return loggedAction('🗑️ deleting channel', { serverId, channelId }, async () => {
            const res = await this.connectionManager.sendMessage({
                processId: serverId,
                tags: [
                    { name: "Action", value: Constants.Actions.DeleteChannel },
                    { name: "ChannelId", value: channelId }
                ]
            });

            const data = this.connectionManager.parseOutput(res, { hasMatchingTag: "Action", hasMatchingTagValue: "Delete-Channel-Response" });
            return data?.Tags?.Status === "200";
        });
    }

    async createRole(serverId: string, params: { name: string; color?: string; permissions?: number | string; position?: number }): Promise<boolean> {
        return loggedAction('➕ creating role', { serverId, ...params }, async () => {
            const tags: Tag[] = [
                { name: "Action", value: Constants.Actions.CreateRole },
                { name: "Name", value: params.name }
            ];

            if (params.color) tags.push({ name: "Color", value: params.color });
            if (params.permissions) tags.push({ name: "Permissions", value: params.permissions.toString() });
            if (params.position !== undefined) tags.push({ name: "Position", value: params.position.toString() });

            const res = await this.connectionManager.sendMessage({
                processId: serverId,
                tags
            });

            const data = this.connectionManager.parseOutput(res, { hasMatchingTag: "Action", hasMatchingTagValue: "Create-Role-Response" });
            return data?.Tags?.Status === "200";
        });
    }

    async updateRole(serverId: string, params: { roleId: string; name?: string; color?: string; permissions?: number | string; position?: number; orderId?: number }): Promise<boolean> {
        return loggedAction('✏️ updating role', { serverId, roleId: params.roleId }, async () => {
            const tags: Tag[] = [
                { name: "Action", value: Constants.Actions.UpdateRole },
                { name: "RoleId", value: params.roleId.toString() }
            ];

            if (params.name) tags.push({ name: "Name", value: params.name });
            if (params.color) tags.push({ name: "Color", value: params.color });
            if (params.permissions) tags.push({ name: "Permissions", value: params.permissions.toString() });

            // Fix: Use orderId (what server expects) instead of position
            // Support both for backward compatibility
            if (params.orderId !== undefined) {
                tags.push({ name: "OrderId", value: params.orderId.toString() });
            } else if (params.position !== undefined) {
                tags.push({ name: "OrderId", value: params.position.toString() });
            }

            const res = await this.connectionManager.sendMessage({
                processId: serverId,
                tags
            });

            const data = this.connectionManager.parseOutput(res, { hasMatchingTag: "Action", hasMatchingTagValue: "Update-Role-Response" });
            return data?.Tags?.Status === "200";
        });
    }

    /**
     * Reorder a role to a specific position in the hierarchy
     * @param serverId The server ID
     * @param roleId The role ID to reorder
     * @param newOrderId The new order position (1-based, higher = more privileged)
     */
    async reorderRole(serverId: string, roleId: string, newOrderId: number): Promise<boolean> {
        return loggedAction('🔄 reordering role', { serverId, roleId, newOrderId }, async () => {
            const tags: Tag[] = [
                { name: "Action", value: Constants.Actions.UpdateRole },
                { name: "RoleId", value: roleId.toString() },
                { name: "OrderId", value: newOrderId.toString() }
            ];

            const res = await this.connectionManager.sendMessage({
                processId: serverId,
                tags
            });

            const data = this.connectionManager.parseOutput(res, { hasMatchingTag: "Action", hasMatchingTagValue: "Update-Role-Response" });

            return data?.Tags?.Status === "200";
        });
    }

    /**
     * Move a role above another role in the hierarchy
     * @param serverId The server ID
     * @param roleId The role ID to move
     * @param targetRoleId The role ID to move above
     */
    async moveRoleAbove(serverId: string, roleId: string, targetRoleId: string): Promise<boolean> {
        return loggedAction('⬆️ moving role above', { serverId, roleId, targetRoleId }, async () => {
            // Get server data to find current role positions
            const server = await this.getServer(serverId);
            if (!server || !server.roles) {
                throw new Error('Server or roles not found');
            }

            const targetRole = server.roles[targetRoleId];
            if (!targetRole) {
                throw new Error('Target role not found');
            }

            // Move to target role's position + 1 (higher in hierarchy)
            const newOrderId = (targetRole.orderId || 0) + 1;
            return this.reorderRole(serverId, roleId, newOrderId);
        });
    }

    /**
     * Move a role below another role in the hierarchy
     * @param serverId The server ID
     * @param roleId The role ID to move
     * @param targetRoleId The role ID to move below
     */
    async moveRoleBelow(serverId: string, roleId: string, targetRoleId: string): Promise<boolean> {
        return loggedAction('⬇️ moving role below', { serverId, roleId, targetRoleId }, async () => {
            // Get server data to find current role positions
            const server = await this.getServer(serverId);
            if (!server || !server.roles) {
                throw new Error('Server or roles not found');
            }

            const targetRole = server.roles[targetRoleId];
            if (!targetRole) {
                throw new Error('Target role not found');
            }

            // Move to target role's position - 1 (lower in hierarchy)
            const newOrderId = Math.max(1, (targetRole.orderId || 0) - 1);
            return this.reorderRole(serverId, roleId, newOrderId);
        });
    }

    async deleteRole(serverId: string, roleId: string): Promise<boolean> {
        return loggedAction('🗑️ deleting role', { serverId, roleId }, async () => {
            const res = await this.connectionManager.sendMessage({
                processId: serverId,
                tags: [
                    { name: "Action", value: Constants.Actions.DeleteRole },
                    { name: "RoleId", value: roleId.toString() }
                ]
            });

            const data = this.connectionManager.parseOutput(res, { hasMatchingTag: "Action", hasMatchingTagValue: "Delete-Role-Response" });
            return data?.Tags?.Status === "200";
        });
    }

    async assignRole(serverId: string, params: { userId: string; roleId: string }): Promise<boolean> {
        return loggedAction('➕ assigning role', { serverId, ...params }, async () => {
            const res = await this.connectionManager.sendMessage({
                processId: serverId,
                tags: [
                    { name: "Action", value: Constants.Actions.AssignRole },
                    { name: "TargetUserId", value: params.userId },
                    { name: "RoleId", value: params.roleId.toString() }
                ]
            });

            const data = this.connectionManager.parseOutput(res, { hasMatchingTag: "Action", hasMatchingTagValue: "Assign-Role-Response" });
            return data?.Tags.Status === "200";
        });
    }

    async unassignRole(serverId: string, params: { userId: string; roleId: string }): Promise<boolean> {
        return loggedAction('🗑️ unassigning role', { serverId, ...params }, async () => {
            const res = await this.connectionManager.sendMessage({
                processId: serverId,
                tags: [
                    { name: "Action", value: Constants.Actions.UnassignRole },
                    { name: "TargetUserId", value: params.userId },
                    { name: "RoleId", value: params.roleId.toString() }
                ]
            });

            const data = this.connectionManager.parseOutput(res, { hasMatchingTag: "Action", hasMatchingTagValue: "Unassign-Role-Response" });
            return data?.Tags.Status === "200";
        });
    }

    async sendMessage(serverId: string, params: { channelId: string; content: string; attachments?: string; replyTo?: string }): Promise<boolean> {
        return loggedAction('📤 sending message', { serverId, channelId: params.channelId, content: params.content.substring(0, 100) + (params.content.length > 100 ? '...' : '') }, async () => {
            const tags: Tag[] = [
                { name: "Action", value: Constants.Actions.SendMessage },
                { name: "ChannelId", value: params.channelId },
            ];

            if (params.attachments) tags.push({ name: "Attachments", value: params.attachments });
            if (params.replyTo) tags.push({ name: "ReplyTo", value: `${params.replyTo}` });

            const res = await this.connectionManager.sendMessage({
                processId: serverId,
                data: params.content,
                tags
            });

            const data = this.connectionManager.parseOutput(res, { hasMatchingTag: "Action", hasMatchingTagValue: "Send-Message-Response" });
            return data?.Tags?.Status === "200";
        });
    }

    async editMessage(serverId: string, params: { messageId: string; content: string }): Promise<boolean> {
        return loggedAction('✏️ editing message', { serverId, messageId: params.messageId }, async () => {
            const res = await this.connectionManager.sendMessage({
                processId: serverId,
                tags: [
                    { name: "Action", value: Constants.Actions.EditMessage },
                    { name: "MessageId", value: params.messageId },
                    // { name: "Content", value: params.content }
                ],
                data: params.content
            });

            const data = this.connectionManager.parseOutput(res, { hasMatchingTag: "Action", hasMatchingTagValue: "Edit-Message-Response" });
            return data?.Tags?.Status === "200";
        });
    }

    async deleteMessage(serverId: string, messageId: string): Promise<boolean> {
        return loggedAction('🗑️ deleting message', { serverId, messageId }, async () => {
            const res = await this.connectionManager.sendMessage({
                processId: serverId,
                tags: [
                    { name: "Action", value: Constants.Actions.DeleteMessage },
                    { name: "MessageId", value: messageId }
                ]
            });

            const data = this.connectionManager.parseOutput(res, { hasMatchingTag: "Action", hasMatchingTagValue: "Delete-Message-Response" });
            return data?.Tags?.Status === "200";
        });
    }

    async getMessage(serverId: string, messageId: string): Promise<Message | null> {
        return loggedAction('🔍 getting message', { serverId, messageId }, async () => {
            const res = await this.connectionManager.dryrun({
                processId: serverId,
                tags: [
                    { name: "Action", value: Constants.Actions.GetSingleMessage },
                    { name: "MessageId", value: messageId }
                ]
            });

            const data = this.connectionManager.parseOutput(res);
            return data ? data as Message : null;
        });
    }

    async getMessages(serverId: string, params: { channelId: string; limit?: number; before?: string; after?: string }): Promise<MessagesResponse | null> {
        return loggedAction('🔍 getting messages', { serverId, channelId: params.channelId, limit: params.limit }, async () => {
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
            return data ? data as MessagesResponse : null;
        });
    }
} 