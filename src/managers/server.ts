
import { Subspace, SubspaceProfiles } from "..";
import type { IProfile, IMember, IServer, Tag, ICategory, IChannel, IRole, IMessage } from "../types/subspace";
import type {
    ICreateServer,
    IUpdateServer,
} from "../types/inputs";
import { Constants } from "../utils/constants";
import { log } from "../utils/logger";
import { SubspaceValidation, ValidationError } from "../utils/validation";

export class SubspaceServers {
    //#region core

    static formatRole(role: IRole): IRole {
        if (role) {
            if (role.mentionable && typeof role.mentionable == "string") {
                role.mentionable = JSON.parse(role.mentionable)
            }
            if (role.hoist && typeof role.hoist == "string") {
                role.hoist = JSON.parse(role.hoist)
            }
        }
        return role
    }

    static formatServer(server: IServer): IServer {
        if (server && server.roles) {
            Object.keys(server.roles).forEach(roleId => {
                server.roles[roleId] = this.formatRole(server.roles[roleId])
            })
        }
        return server
    }

    static formatMember(member: IMember): IMember {
        if (member) {
            if (member.is_bot && typeof member.is_bot == "string") {
                member.is_bot = JSON.parse(member.is_bot)
            }
        }
        return member
    }

    public static async createServer(input: ICreateServer): Promise<IServer> {
        // Validate inputs before making any backend calls
        SubspaceValidation.validateServerCreation({
            serverName: input.serverName,
            serverDescription: input.serverDescription,
            serverPfp: input.serverPfp,
            serverBanner: input.serverBanner
        });

        const tags: Tag[] = [{ name: "Action", value: "create-server" }]

        tags.push({ name: "server-name", value: input.serverName })

        if (input.serverDescription) {
            tags.push({ name: "server-description", value: input.serverDescription })
        }
        if (input.serverPfp) {
            tags.push({ name: "server-pfp", value: input.serverPfp })
        }
        if (input.serverBanner) {
            tags.push({ name: "server-banner", value: input.serverBanner })
        }

        //fetch the server source
        let serverSource = Subspace.sources.server.lua
        if (!serverSource) await Subspace.getSources()
        serverSource = Subspace.sources.server.lua
        if (!serverSource) throw new Error("server source not found")
        serverSource = serverSource.replace("<<SUBSPACE>>", Constants.subspaceProcess)

        // spawn a server process
        const spawnTags: Tag[] = []
        const serverProcess = await Subspace.ao().spawn({ tags: spawnTags })
        // add server code to the process
        await Subspace.ao().runLua({ processId: serverProcess, code: serverSource })

        tags.push({ name: "server-process", value: serverProcess })
        const res = await Subspace.ao().write({ processId: Constants.subspaceProcess, tags: tags })
        if (!res) return null

        const server = await this.getServer(serverProcess)
        return server
    }

    public static async getServer(serverId: string): Promise<IServer> {
        // Validate server ID
        SubspaceValidation.validateServerId(serverId);

        const server = await Subspace.ao().read<IServer>({ path: `/${serverId}/now/server` })
        return this.formatServer(server)
    }

    public static async getServerMembers(serverId: string): Promise<Record<string, IMember>> {
        // Validate server ID
        SubspaceValidation.validateServerId(serverId);

        const members = await Subspace.ao().read<Record<string, IMember>>({ path: `/${serverId}/now/members` })
        Object.keys(members).forEach(memberId => {
            members[memberId] = this.formatMember(members[memberId])
        })
        return members
    }

    public static async updateServer({ serverId, serverName, serverDescription, serverPfp, serverBanner }: IUpdateServer): Promise<IServer> {
        // Validate inputs
        SubspaceValidation.validateServerId(serverId);
        SubspaceValidation.validateServerUpdate({
            serverName,
            serverDescription,
            serverPfp,
            serverBanner
        });

        const tags: Tag[] = [{ name: "Action", value: "update-server" }]

        if (serverName) tags.push({ name: "server-name", value: serverName })
        if (serverDescription) tags.push({ name: "server-description", value: serverDescription })
        if (serverPfp) tags.push({ name: "server-pfp", value: serverPfp })
        if (serverBanner) tags.push({ name: "server-banner", value: serverBanner })

        const res = await Subspace.ao().write({ processId: serverId, tags: tags })
        return Subspace.ao().matchAction<IServer>("update-server-response", res)
    }

    public static async joinServer(serverId: string): Promise<boolean> {
        // Validate server ID
        SubspaceValidation.validateServerId(serverId);

        const tags: Tag[] = [{ name: "Action", value: "join-server" }]
        tags.push({ name: "server-id", value: serverId })
        log({ type: "debug", label: "Joining Server [1/2]", data: serverId })
        const res = await Subspace.ao().write({ processId: Constants.subspaceProcess, tags: tags })
        log({ type: "output", label: "Joining Server [1/2]", data: res })
        let retries = 0
        const maxRetries = 5
        while (retries < maxRetries) {
            const p = await SubspaceProfiles.getProfile(Subspace.address)
            const approved = p.servers[serverId].approved
            if (approved) {
                log({ type: "output", label: "Joined Server [2/2]", data: { approved } })
                return true
            }
            log({ type: "debug", label: "Retry Joining Server [2/2]", data: { approved, retries } })
            await new Promise(resolve => setTimeout(resolve, 1000 * (retries + 1)))
            retries++
        }
        return false
    }

    //#endregion

    //#region categories

    public static async createCategory({ serverId, categoryName, categoryOrder }: { serverId: string, categoryName: string, categoryOrder?: number }): Promise<ICategory> {
        // Validate inputs
        SubspaceValidation.validateServerId(serverId);
        SubspaceValidation.validateCategoryParams({ categoryName, categoryOrder });

        const tags: Tag[] = [{ name: "Action", value: "create-category" }]

        tags.push({ name: "server-id", value: serverId })
        tags.push({ name: "category-name", value: categoryName })
        if (categoryOrder) tags.push({ name: "category-order", value: categoryOrder.toString() })

        const res = await Subspace.ao().write({ processId: serverId, tags: tags })
        const category = Subspace.ao().matchAction<ICategory>("create-category-response", res)
        return category
    }

    public static async updateCategory({ serverId, categoryId, categoryName, categoryOrder }: { serverId: string, categoryId: string, categoryName?: string, categoryOrder?: number }): Promise<ICategory> {
        // Validate inputs
        SubspaceValidation.validateServerId(serverId);
        SubspaceValidation.validateCategoryId(categoryId);

        // Ensure at least one field is being updated
        if (!categoryName && !categoryOrder) {
            throw new ValidationError(400, "categoryName or categoryOrder is required");
        }

        SubspaceValidation.validateCategoryParams({ categoryName, categoryOrder });

        const tags: Tag[] = [{ name: "Action", value: "update-category" }]

        tags.push({ name: "server-id", value: serverId })
        tags.push({ name: "category-id", value: categoryId })
        if (categoryName) tags.push({ name: "category-name", value: categoryName })
        if (categoryOrder) tags.push({ name: "category-order", value: categoryOrder.toString() })

        const res = await Subspace.ao().write({ processId: serverId, tags: tags })
        const category = Subspace.ao().matchAction<ICategory>("update-category-response", res)
        return category
    }

    public static async deleteCategory({ serverId, categoryId }: { serverId: string, categoryId: string }): Promise<boolean> {
        // Validate inputs
        SubspaceValidation.validateServerId(serverId);
        SubspaceValidation.validateCategoryId(categoryId);

        const tags: Tag[] = [{ name: "Action", value: "delete-category" }]

        tags.push({ name: "server-id", value: serverId })
        tags.push({ name: "category-id", value: categoryId })

        const res = await Subspace.ao().write({ processId: serverId, tags: tags })
        return (res.status == 200)
    }

    //#endregion

    //#region channels

    public static async createChannel({ serverId, channelName, categoryId, channelOrder, allowMessaging, allowAttachments }: { serverId: string, channelName: string, categoryId?: string, channelOrder?: number, allowMessaging?: number, allowAttachments?: number }): Promise<IChannel> {
        // Validate inputs
        SubspaceValidation.validateServerId(serverId);
        SubspaceValidation.validateChannelParams({
            channelName,
            categoryId,
            channelOrder,
            allowMessaging,
            allowAttachments
        });

        const tags: Tag[] = [{ name: "Action", value: "create-channel" }]

        tags.push({ name: "server-id", value: serverId })
        tags.push({ name: "channel-name", value: channelName })
        if (categoryId) tags.push({ name: "category-id", value: categoryId })
        if (channelOrder) tags.push({ name: "channel-order", value: channelOrder.toString() })
        if (allowMessaging !== undefined) tags.push({ name: "allow-messaging", value: allowMessaging.toString() })
        if (allowAttachments !== undefined) tags.push({ name: "allow-attachments", value: allowAttachments.toString() })

        const res = await Subspace.ao().write({ processId: serverId, tags: tags })
        const channel = Subspace.ao().matchAction<IChannel>("create-channel-response", res)
        return channel
    }

    public static async updateChannel({ serverId, channelId, channelName, categoryId, channelOrder, allowMessaging, allowAttachments }: { serverId: string, channelId: string, channelName?: string, categoryId?: string, channelOrder?: number, allowMessaging?: number, allowAttachments?: number }): Promise<IChannel> {
        // Validate inputs
        SubspaceValidation.validateServerId(serverId);
        SubspaceValidation.validateChannelId(channelId);

        // Ensure at least one field is being updated
        if (!channelName && categoryId === undefined && !channelOrder && allowMessaging === undefined && allowAttachments === undefined) {
            throw new ValidationError(400, "channelName, categoryId, channelOrder, allowMessaging, or allowAttachments is required");
        }

        SubspaceValidation.validateChannelParams({
            channelName,
            categoryId,
            channelOrder,
            allowMessaging,
            allowAttachments
        });

        const tags: Tag[] = [{ name: "Action", value: "update-channel" }]

        tags.push({ name: "server-id", value: serverId })
        tags.push({ name: "channel-id", value: channelId })
        if (channelName) tags.push({ name: "channel-name", value: channelName })
        if (categoryId !== undefined) tags.push({ name: "category-id", value: categoryId || "" }) // Allow setting to empty for uncategorized
        if (channelOrder) tags.push({ name: "channel-order", value: channelOrder.toString() })
        if (allowMessaging !== undefined) tags.push({ name: "allow-messaging", value: allowMessaging.toString() })
        if (allowAttachments !== undefined) tags.push({ name: "allow-attachments", value: allowAttachments.toString() })

        const res = await Subspace.ao().write({ processId: serverId, tags: tags })
        const channel = Subspace.ao().matchAction<IChannel>("update-channel-response", res)
        return channel
    }

    public static async deleteChannel({ serverId, channelId }: { serverId: string, channelId: string }): Promise<boolean> {
        // Validate inputs
        SubspaceValidation.validateServerId(serverId);
        SubspaceValidation.validateChannelId(channelId);

        const tags: Tag[] = [{ name: "Action", value: "delete-channel" }]

        tags.push({ name: "server-id", value: serverId })
        tags.push({ name: "channel-id", value: channelId })

        const res = await Subspace.ao().write({ processId: serverId, tags: tags })
        return (res.status == 200)
    }

    //#endregion

    //#region roles

    public static async createRole({ serverId, roleName, roleColor, rolePermissions, roleOrder, mentionable, hoist }: { serverId: string, roleName: string, roleColor?: string, rolePermissions?: number, roleOrder?: number, mentionable?: boolean, hoist?: boolean }): Promise<IRole> {
        // Validate inputs
        SubspaceValidation.validateServerId(serverId);
        SubspaceValidation.validateRoleParams({
            roleName,
            roleColor,
            rolePermissions,
            roleOrder,
            mentionable,
            hoist
        });

        const tags: Tag[] = [{ name: "Action", value: "create-role" }]

        tags.push({ name: "server-id", value: serverId })
        tags.push({ name: "role-name", value: roleName })
        if (roleColor) tags.push({ name: "role-color", value: roleColor })
        if (rolePermissions !== undefined) tags.push({ name: "role-permissions", value: rolePermissions.toString() })
        if (roleOrder) tags.push({ name: "role-order", value: roleOrder.toString() })
        if (mentionable !== undefined) tags.push({ name: "mentionable", value: mentionable.toString() })
        if (hoist !== undefined) tags.push({ name: "hoist", value: hoist.toString() })

        const res = await Subspace.ao().write({ processId: serverId, tags: tags })
        const role = Subspace.ao().matchAction<IRole>("create-role-response", res)
        return role
    }

    public static async updateRole({ serverId, roleId, roleName, roleColor, rolePermissions, roleOrder, mentionable, hoist }: { serverId: string, roleId: string, roleName?: string, roleColor?: string, rolePermissions?: number, roleOrder?: number, mentionable?: boolean, hoist?: boolean }): Promise<IRole> {
        // Validate inputs
        SubspaceValidation.validateServerId(serverId);
        SubspaceValidation.validateRoleId(roleId);

        // Ensure at least one field is being updated
        if (!roleName && !roleColor && rolePermissions === undefined && !roleOrder && mentionable === undefined && hoist === undefined) {
            throw new ValidationError(400, "roleName, roleColor, rolePermissions, roleOrder, mentionable, or hoist is required");
        }

        SubspaceValidation.validateRoleParams({
            roleName,
            roleColor,
            rolePermissions,
            roleOrder,
            mentionable,
            hoist
        });

        const tags: Tag[] = [{ name: "Action", value: "update-role" }]

        tags.push({ name: "server-id", value: serverId })
        tags.push({ name: "role-id", value: roleId })
        if (roleName) tags.push({ name: "role-name", value: roleName })
        if (roleColor) tags.push({ name: "role-color", value: roleColor })
        if (rolePermissions !== undefined) tags.push({ name: "role-permissions", value: rolePermissions.toString() })
        if (roleOrder) tags.push({ name: "role-order", value: roleOrder.toString() })
        if (mentionable !== undefined) tags.push({ name: "mentionable", value: mentionable.toString() })
        if (hoist !== undefined) tags.push({ name: "hoist", value: hoist.toString() })

        const res = await Subspace.ao().write({ processId: serverId, tags: tags })
        const role = Subspace.ao().matchAction<IRole>("update-role-response", res)
        return role
    }

    public static async deleteRole({ serverId, roleId }: { serverId: string, roleId: string }): Promise<boolean> {
        // Validate inputs
        SubspaceValidation.validateServerId(serverId);
        SubspaceValidation.validateRoleId(roleId);

        const tags: Tag[] = [{ name: "Action", value: "delete-role" }]

        tags.push({ name: "server-id", value: serverId })
        tags.push({ name: "role-id", value: roleId })

        const res = await Subspace.ao().write({ processId: serverId, tags: tags })
        return (res.status == 200)
    }

    public static async assignRole({ serverId, userId, roleId }: { serverId: string, userId: string, roleId: string }): Promise<boolean> {
        // Validate inputs
        SubspaceValidation.validateServerId(serverId);
        SubspaceValidation.validateUserId(userId);
        SubspaceValidation.validateString(roleId, "role id");

        const tags: Tag[] = [{ name: "Action", value: "assign-role" }]

        tags.push({ name: "user-id", value: userId })
        tags.push({ name: "role-id", value: roleId })

        const res = await Subspace.ao().write({ processId: serverId, tags: tags })
        return (res.status == 200)
    }

    public static async unassignRole({ serverId, userId, roleId }: { serverId: string, userId: string, roleId: string }): Promise<boolean> {
        // Validate inputs
        SubspaceValidation.validateServerId(serverId);
        SubspaceValidation.validateUserId(userId);
        SubspaceValidation.validateString(roleId, "role id");

        // Cannot unassign everyone role
        if (roleId === "@") {
            throw new ValidationError(400, "cannot unassign everyone role");
        }

        const tags: Tag[] = [{ name: "Action", value: "unassign-role" }]

        tags.push({ name: "user-id", value: userId })
        tags.push({ name: "role-id", value: roleId })

        const res = await Subspace.ao().write({ processId: serverId, tags: tags })
        return (res.status == 200)
    }

    //#endregion

    //#region messages

    public static async sendMessage({ serverId, channelId, content, attachments }: { serverId: string, channelId: string, content: string, attachments?: string[] }): Promise<IMessage> {
        // Validate inputs
        SubspaceValidation.validateServerId(serverId);
        SubspaceValidation.validateChannelId(channelId);
        SubspaceValidation.validateMessageParams({ content, attachments });

        const tags: Tag[] = [{ name: "Action", value: "send-message" }]

        tags.push({ name: "server-id", value: serverId })
        tags.push({ name: "channel-id", value: channelId })
        if (content) tags.push({ name: "content", value: content })
        if (attachments) tags.push({ name: "attachments", value: JSON.stringify(attachments) })

        const res = await Subspace.ao().write({ processId: serverId, tags: tags })
        const message = Subspace.ao().matchAction<IMessage>("send-message-response", res)
        return message
    }

    public static async updateMessage({ serverId, channelId, messageId, content }: { serverId: string, channelId: string, messageId: string, content: string }): Promise<IMessage> {
        // Validate inputs
        SubspaceValidation.validateServerId(serverId);
        SubspaceValidation.validateChannelId(channelId);
        SubspaceValidation.validateMessageId(messageId);
        SubspaceValidation.validateMessageContent(content);

        const tags: Tag[] = [{ name: "Action", value: "update-message" }]

        tags.push({ name: "channel-id", value: channelId })
        tags.push({ name: "message-id", value: messageId })
        tags.push({ name: "content", value: content })

        const res = await Subspace.ao().write({ processId: serverId, tags: tags })
        const message = Subspace.ao().matchAction<IMessage>("update-message-response", res)
        return message
    }

    public static async deleteMessage({ serverId, channelId, messageId }: { serverId: string, channelId: string, messageId: string }): Promise<boolean> {
        // Validate inputs
        SubspaceValidation.validateServerId(serverId);
        SubspaceValidation.validateChannelId(channelId);
        SubspaceValidation.validateMessageId(messageId);

        const tags: Tag[] = [{ name: "Action", value: "delete-message" }]

        tags.push({ name: "channel-id", value: channelId })
        tags.push({ name: "message-id", value: messageId })

        const res = await Subspace.ao().write({ processId: serverId, tags: tags })
        return (res.status == 200)
    }
}