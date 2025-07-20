import { ConnectionManager } from "../connection-manager";
import { Constants } from "../utils/constants";
import { loggedAction } from "../utils/logger";
import type { Tag } from "../types/ao";

export interface Profile {
    userId: string;
    pfp?: string;
    displayName?: string;
    bio?: string;
    banner?: string;
    serversJoined?: string[];
    friends?: {
        accepted: string[]
        sent: string[]
        received: string[]
    };
    dmProcess?: string;
    delegations?: string[];
}

export interface Notification {
    id: string;
    type: string;
    data: any;
    timestamp: number;
    read: boolean;
}

export interface Friend {
    userId: string;
    status: 'accepted' | 'sent' | 'received';
}

export interface DMMessage {
    id: string;
    senderId: string;
    content: string;
    timestamp: number;
    attachments?: string;
    replyTo?: number;
}

export interface DMResponse {
    messages: DMMessage[];
    hasMore: boolean;
    cursor?: string;
}

export class UserManager {
    constructor(private connectionManager: ConnectionManager) { }

    async getProfile(userId: string): Promise<Profile | null> {
        return loggedAction('🔍 getting profile', { userId }, async () => {
            const res = await this.connectionManager.dryrun({
                processId: Constants.Subspace,
                tags: [
                    { name: "Action", value: Constants.Actions.GetProfile },
                    { name: "UserId", value: userId }
                ]
            });

            const data = JSON.parse(this.connectionManager.parseOutput(res).Data);

            if (data) {
                if (data.error) throw new Error(data.error);
                return data as Profile;
            } else {
                // Handle special case for owner creating new profile
                if (userId == this.connectionManager.owner) {
                    console.info("profile not found, creating new")
                    const profileId = await this.createProfile()
                    if (profileId) {
                        return this.getProfile(userId)
                    } else {
                        return null
                    }
                }
                return null;
            }
        });
    }

    async getBulkProfiles(userIds: string[]): Promise<Profile[]> {
        return loggedAction('🔍 getting bulk profiles', { userCount: userIds.length }, async () => {
            const res = await this.connectionManager.dryrun({
                processId: Constants.Subspace,
                tags: [
                    { name: "Action", value: Constants.Actions.GetBulkProfile },
                    { name: "UserIds", value: JSON.stringify(userIds) }
                ]
            });

            const data = this.connectionManager.parseOutput(res);
            return data || [];
        });
    }

    async createProfile(): Promise<string | null> {
        return loggedAction('➕ creating profile', {}, async () => {
            // spawn dm process
            const dmProcess = await this.connectionManager.spawn({
                tags: [
                    { name: "Action", value: Constants.Actions.CreateProfile },
                    { name: "Owner", value: this.connectionManager.owner }
                ]
            })

            // retry 3 times to wait for this.connectionManager.sources.Dm.Lua to populate
            for (let i = 0; i < 3; i++) {
                if (this.connectionManager.sources.Dm.Lua) break
                await new Promise(resolve => setTimeout(resolve, 1000 * i))
            }

            if (!this.connectionManager.sources.Dm.Lua) {
                throw new Error("Failed to get dm source")
            }

            const dmRes = await this.connectionManager.execLua({
                processId: dmProcess,
                code: this.connectionManager.sources.Dm.Lua,
                tags: []
            })
            // wait 1.5 seconds for dm process to finish
            await new Promise(resolve => setTimeout(resolve, 1500))

            const res = await this.connectionManager.sendMessage({
                processId: Constants.Subspace,
                tags: [
                    { name: "Action", value: Constants.Actions.CreateProfile },
                    { name: "DmProcess", value: dmProcess }
                ]
            });

            const data = this.connectionManager.parseOutput(res, {
                hasMatchingTag: "Action",
                hasMatchingTagValue: "Create-Profile-Response"
            });

            if (data.Tags.Status != "200") {
                console.error("Failed to create profile", data)
                throw new Error("Failed to create profile: " + data.Data)
            }

            const profileId = data.Tags.ProfileId
            return profileId || null;
        });
    }

    async updateProfile(params: { pfp?: string; displayName?: string; bio?: string; banner?: string }): Promise<boolean> {
        return loggedAction('✏️ updating profile', params, async () => {
            const tags: Tag[] = [
                { name: "Action", value: Constants.Actions.UpdateProfile }
            ];

            if (params.pfp) tags.push({ name: "Pfp", value: params.pfp });
            if (params.displayName) tags.push({ name: "DisplayName", value: params.displayName });
            if (params.bio) tags.push({ name: "Bio", value: params.bio });
            if (params.banner) tags.push({ name: "Banner", value: params.banner });

            const res = await this.connectionManager.sendMessage({
                processId: Constants.Subspace,
                tags
            });

            const data = this.connectionManager.parseOutput(res, { hasMatchingTag: "Action", hasMatchingTagValue: "Update-Profile-Response" });
            return data?.Tags?.Status === "200";
        });
    }

    async getNotifications(userId: string): Promise<Notification[]> {
        return loggedAction('🔍 getting notifications', { userId }, async () => {
            const res = await this.connectionManager.dryrun({
                processId: Constants.Subspace,
                tags: [
                    { name: "Action", value: Constants.Actions.GetNotifications },
                    { name: "UserId", value: userId }
                ]
            });

            const data = this.connectionManager.parseOutput(res);
            return data || [];
        });
    }

    async sendFriendRequest(userId: string): Promise<boolean> {
        return loggedAction('📤 sending friend request', { userId }, async () => {
            const res = await this.connectionManager.sendMessage({
                processId: Constants.Subspace,
                tags: [
                    { name: "Action", value: Constants.Actions.SendFriendRequest },
                    { name: "UserId", value: userId }
                ]
            });

            const data = this.connectionManager.parseOutput(res, { hasMatchingTag: "Action", hasMatchingTagValue: "Add-Friend-Response" });
            return data?.Tags?.Status === "200";
        });
    }

    async acceptFriendRequest(userId: string): Promise<boolean> {
        return loggedAction('✅ accepting friend request', { userId }, async () => {
            const res = await this.connectionManager.sendMessage({
                processId: Constants.Subspace,
                tags: [
                    { name: "Action", value: Constants.Actions.AcceptFriendRequest },
                    { name: "UserId", value: userId }
                ]
            });

            const data = this.connectionManager.parseOutput(res, { hasMatchingTag: "Action", hasMatchingTagValue: "Accept-Friend-Response" });
            return data?.Tags?.Status === "200";
        });
    }

    async rejectFriendRequest(userId: string): Promise<boolean> {
        return loggedAction('❌ rejecting friend request', { userId }, async () => {
            const res = await this.connectionManager.sendMessage({
                processId: Constants.Subspace,
                tags: [
                    { name: "Action", value: Constants.Actions.RejectFriendRequest },
                    { name: "UserId", value: userId }
                ]
            });

            const data = this.connectionManager.parseOutput(res, { hasMatchingTag: "Action", hasMatchingTagValue: "Reject-Friend-Response" });
            return data?.Tags?.Status === "200";
        });
    }

    async removeFriend(userId: string): Promise<boolean> {
        return loggedAction('🗑️ removing friend', { userId }, async () => {
            const res = await this.connectionManager.sendMessage({
                processId: Constants.Subspace,
                tags: [
                    { name: "Action", value: Constants.Actions.RemoveFriend },
                    { name: "UserId", value: userId }
                ]
            });

            const data = this.connectionManager.parseOutput(res, { hasMatchingTag: "Action", hasMatchingTagValue: "Remove-Friend-Response" });
            return data?.Tags?.Status === "200";
        });
    }

    async getDMs(dmProcessId: string, params: { limit?: number; before?: string; after?: string } = {}): Promise<DMResponse | null> {
        return loggedAction('🔍 getting DMs', { dmProcessId, limit: params.limit }, async () => {
            const tags: Tag[] = [
                { name: "Action", value: Constants.Actions.GetDMs }
            ];

            if (params.limit) tags.push({ name: "Limit", value: params.limit.toString() });
            if (params.before) tags.push({ name: "Before", value: params.before });
            if (params.after) tags.push({ name: "After", value: params.after });

            const res = await this.connectionManager.dryrun({
                processId: dmProcessId,
                tags
            });

            const data = this.connectionManager.parseOutput(res);
            return data ? data as DMResponse : null;
        });
    }

    async sendDM(dmProcessId: string, params: { content: string; attachments?: string; replyTo?: number }): Promise<boolean> {
        return loggedAction('📤 sending DM', { dmProcessId, content: params.content.substring(0, 100) + (params.content.length > 100 ? '...' : '') }, async () => {
            const tags: Tag[] = [
                { name: "Action", value: Constants.Actions.SendDM },
                { name: "Content", value: params.content }
            ];

            if (params.attachments) tags.push({ name: "Attachments", value: params.attachments });
            if (params.replyTo) tags.push({ name: "ReplyTo", value: params.replyTo.toString() });

            const res = await this.connectionManager.sendMessage({
                processId: dmProcessId,
                tags
            });

            const data = this.connectionManager.parseOutput(res, { hasMatchingTag: "Action", hasMatchingTagValue: "Send-DM-Response" });
            return data?.Tags?.Status === "200";
        });
    }

    async editDM(dmProcessId: string, params: { messageId: string; content: string }): Promise<boolean> {
        return loggedAction('✏️ editing DM', { dmProcessId, messageId: params.messageId }, async () => {
            const res = await this.connectionManager.sendMessage({
                processId: dmProcessId,
                tags: [
                    { name: "Action", value: Constants.Actions.EditDM },
                    { name: "MessageId", value: params.messageId },
                    { name: "Content", value: params.content }
                ]
            });

            const data = this.connectionManager.parseOutput(res, { hasMatchingTag: "Action", hasMatchingTagValue: "Edit-DM-Response" });
            return data?.Tags?.Status === "200";
        });
    }

    async deleteDM(dmProcessId: string, messageId: string): Promise<boolean> {
        return loggedAction('🗑️ deleting DM', { dmProcessId, messageId }, async () => {
            const res = await this.connectionManager.sendMessage({
                processId: dmProcessId,
                tags: [
                    { name: "Action", value: Constants.Actions.DeleteDM },
                    { name: "MessageId", value: messageId }
                ]
            });

            const data = this.connectionManager.parseOutput(res, { hasMatchingTag: "Action", hasMatchingTagValue: "Delete-DM-Response" });
            return data?.Tags?.Status === "200";
        });
    }

    async joinServer(serverId: string): Promise<boolean> {
        return loggedAction('➡️ joining server (user)', { serverId }, async () => {
            // Send join request directly to the server process
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
        return loggedAction('⬅️ leaving server (user)', { serverId }, async () => {
            // Send leave request directly to the server process
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

    async addDelegation(): Promise<boolean> {
        return loggedAction('➕ adding delegation', {}, async () => {
            const res = await this.connectionManager.sendMessage({
                processId: Constants.Subspace,
                tags: [
                    { name: "Action", value: Constants.Actions.AddDelegation }
                ]
            });

            const data = this.connectionManager.parseOutput(res, { hasMatchingTag: "Action", hasMatchingTagValue: "Add-Delegation-Response" });
            return data?.Tags?.Status === "200";
        });
    }

    async removeDelegation(): Promise<boolean> {
        return loggedAction('🗑️ removing delegation', {}, async () => {
            const res = await this.connectionManager.sendMessage({
                processId: Constants.Subspace,
                tags: [
                    { name: "Action", value: Constants.Actions.RemoveDelegation }
                ]
            });

            const data = this.connectionManager.parseOutput(res, { hasMatchingTag: "Action", hasMatchingTagValue: "Remove-Delegation-Response" });
            return data?.Tags?.Status === "200";
        });
    }

    async removeAllDelegations(): Promise<boolean> {
        return loggedAction('🗑️ removing all delegations', {}, async () => {
            const res = await this.connectionManager.sendMessage({
                processId: Constants.Subspace,
                tags: [
                    { name: "Action", value: Constants.Actions.RemoveAllDelegations }
                ]
            });

            const data = this.connectionManager.parseOutput(res, { hasMatchingTag: "Action", hasMatchingTagValue: "Remove-All-Delegations-Response" });
            return data?.Tags?.Status === "200";
        });
    }
} 