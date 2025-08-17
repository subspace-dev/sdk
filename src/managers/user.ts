import { ConnectionManager } from "../connection-manager";
import { Constants } from "../utils/constants";
import { loggedAction } from "../utils/logger";
import type { Tag } from "../types/ao";
import { getPrimaryName, getWanderTierInfo, WanderTierInfo } from "../utils/lib";

export interface Profile {
    userId: string;
    pfp?: string;
    primaryName?: string;
    wndrTier?: WanderTierInfo;
    bio?: string;
    banner?: string;
    // Key-value map of serverId -> server info
    serversJoined: Record<string, {
        orderId: number;
        serverApproved?: boolean;
    }>;
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
            let data: Profile | null = null
            try {
                data = await this.connectionManager.hashpathGET<Profile>(`${Constants.Subspace}~process@1.0/now/cache/subspace/profiles/${userId}/~json@1.0/serialize`)
            } catch (e) {
                throw new Error("[subspace-sdk] failed to get profile: " + e)
                return null
            }

            const wanderTierInfo = await getWanderTierInfo(userId)

            let primaryName: string | undefined = undefined
            try {
                primaryName = await getPrimaryName(userId)
            } catch (e) {
            }

            const profile: Profile = {
                userId,
                pfp: data.pfp || "",
                delegations: data.delegations || [],
                // Lua state stores serversJoined as a table keyed by serverId
                // Normalize to an object map in TS
                serversJoined: data.serversJoined || {},
                dmProcess: data.dmProcess || "",
                friends: data.friends || {
                    accepted: [],
                    sent: [],
                    received: []
                },
                primaryName: primaryName || undefined,
                wndrTier: wanderTierInfo || undefined
            }
            return profile;
            // const res = await this.connectionManager.dryrun({
            //     processId: Constants.Subspace,
            //     tags: [
            //         { name: "Action", value: Constants.Actions.GetProfile },
            //         { name: "UserId", value: userId }
            //     ]
            // });

            // const data = JSON.parse(this.connectionManager.parseOutput(res).Data);

            // if (data) {
            //     if (data.error) throw new Error(data.error);
            //     return data as Profile;
            // } else {
            //     // Handle special case for owner creating new profile
            //     if (userId == this.connectionManager.owner) {
            //         console.info("profile not found, creating new")
            //         const profileId = await this.createProfile()
            //         if (profileId) {
            //             return this.getProfile(userId)
            //         } else {
            //             return null
            //         }
            //     }
            //     return null;
            // }
        });
    }

    /**
     * Fetch multiple user profiles in batches with rate limiting
     * @param userIds Array of user IDs to fetch profiles for
     * @param batchSize Number of profiles to fetch concurrently (default: 10)
     * @param batchDelay Delay between batches in milliseconds (default: 500)
     * @returns Record mapping userId to Profile or null if failed
     */
    async getBulkProfiles(userIds: string[], batchSize: number = 10, batchDelay: number = 500): Promise<Record<string, Profile | null>> {
        return loggedAction('📦 getting bulk profiles', { userIds, count: userIds.length, batchSize, batchDelay }, async () => {
            const results: Record<string, Profile | null> = {}

            for (let i = 0; i < userIds.length; i += batchSize) {
                const batch = userIds.slice(i, i + batchSize)
                const batchNumber = Math.floor(i / batchSize) + 1
                const totalBatches = Math.ceil(userIds.length / batchSize)

                console.log(`📦 Fetching batch ${batchNumber}/${totalBatches} (${batch.length} profiles)`)

                // Fetch all profiles in current batch concurrently
                const batchPromises = batch.map(async (userId) => {
                    try {
                        const profile = await this.getProfile(userId)
                        return { userId, profile }
                    } catch (error) {
                        console.error(`❌ Failed to fetch profile for ${userId}:`, error)
                        return { userId, profile: null }
                    }
                })

                const batchResults = await Promise.all(batchPromises)

                // Store results in key-value format
                batchResults.forEach(({ userId, profile }) => {
                    results[userId] = profile
                })

                console.log(`✅ Batch ${batchNumber}/${totalBatches} completed (${batchResults.filter(r => r.profile).length}/${batch.length} successful)`)

                // Add delay between batches (except for the last batch)
                if (i + batchSize < userIds.length) {
                    await new Promise(resolve => setTimeout(resolve, batchDelay))
                }
            }

            return results
        })
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
                    { name: "Dm-Process", value: dmProcess }
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
            if (params.displayName) tags.push({ name: "Display-Name", value: params.displayName });
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
                    { name: "User-Id", value: userId }
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
                    { name: "Friend-Id", value: userId }
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
                    { name: "Friend-Id", value: userId }
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
                    { name: "Friend-Id", value: userId }
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
                    { name: "Friend-Id", value: userId }
                ]
            });

            const data = this.connectionManager.parseOutput(res, { hasMatchingTag: "Action", hasMatchingTagValue: "Remove-Friend-Response" });
            return data?.Tags?.Status === "200";
        });
    }

    async getDMs(dmProcessId: string, params: { friendId?: string; limit?: number; before?: string; after?: string } = {}): Promise<DMResponse | null> {
        return loggedAction('🔍 getting DMs', { dmProcessId, friendId: params.friendId, limit: params.limit }, async () => {
            const tags: Tag[] = [
                { name: "Action", value: Constants.Actions.GetDMs }
            ];

            if (params.friendId) tags.push({ name: "Friend-Id", value: params.friendId });
            if (params.limit) tags.push({ name: "Limit", value: params.limit.toString() });
            if (params.before) tags.push({ name: "Before", value: params.before });
            if (params.after) tags.push({ name: "After", value: params.after });

            const res = await this.connectionManager.dryrun({
                processId: dmProcessId,
                tags
            });

            const rawData = JSON.parse(this.connectionManager.parseOutput(res, { hasMatchingTag: "Action", hasMatchingTagValue: "Get-DMs-Response" }).Data);

            if (!rawData || !rawData.messages) return null;

            // Map the field names from Lua response to DMMessage interface
            const mappedMessages: DMMessage[] = rawData.messages.map((msg: any) => ({
                id: msg.messageId.toString(), // Convert to string and rename
                senderId: msg.authorId, // Rename from authorId to senderId
                content: msg.content,
                timestamp: msg.timestamp,
                attachments: msg.attachments,
                replyTo: msg.replyTo
            }));

            return {
                messages: mappedMessages,
                hasMore: false, // Can be enhanced later with pagination
                cursor: undefined
            } as DMResponse;
        });
    }

    async sendDM(dmProcessId: string, params: { content: string; attachments?: string; replyTo?: number }): Promise<boolean> {
        return loggedAction('📤 sending DM', { dmProcessId, content: params.content.substring(0, 100) + (params.content.length > 100 ? '...' : '') }, async () => {
            const tags: Tag[] = [
                { name: "Action", value: Constants.Actions.SendDM },
                { name: "Content", value: params.content }
            ];

            if (params.attachments) tags.push({ name: "Attachments", value: params.attachments });
            if (params.replyTo) tags.push({ name: "Reply-To", value: params.replyTo.toString() });

            const res = await this.connectionManager.sendMessage({
                processId: dmProcessId,
                tags
            });

            const data = this.connectionManager.parseOutput(res, { hasMatchingTag: "Action", hasMatchingTagValue: "Send-DM-Response" });
            return data?.Tags?.Status === "200";
        });
    }

    async sendDMToFriend(friendId: string, params: { content: string; attachments?: string; replyTo?: number }): Promise<boolean> {
        return loggedAction('📤 sending DM to friend', { friendId, content: params.content.substring(0, 100) + (params.content.length > 100 ? '...' : '') }, async () => {
            const tags: Tag[] = [
                { name: "Action", value: Constants.Actions.SendDM },
                { name: "Friend-Id", value: friendId }
            ];

            if (params.attachments) tags.push({ name: "Attachments", value: params.attachments });
            if (params.replyTo) tags.push({ name: "Reply-To", value: params.replyTo.toString() });

            const res = await this.connectionManager.sendMessage({
                processId: Constants.Subspace,
                tags,
                data: params.content
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
                    { name: "Message-Id", value: params.messageId },
                    { name: "Content", value: params.content }
                ]
            });

            const data = this.connectionManager.parseOutput(res, { hasMatchingTag: "Action", hasMatchingTagValue: "Edit-DM-Response" });
            return data?.Tags?.Status === "200";
        });
    }

    async editDMToFriend(friendId: string, params: { messageId: string; content: string }): Promise<boolean> {
        return loggedAction('✏️ editing DM to friend', { friendId, messageId: params.messageId }, async () => {
            const res = await this.connectionManager.sendMessage({
                processId: Constants.Subspace,
                tags: [
                    { name: "Action", value: Constants.Actions.EditDM },
                    { name: "Friend-Id", value: friendId },
                    { name: "Message-Id", value: params.messageId }
                ],
                data: params.content
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
                    { name: "Message-Id", value: messageId }
                ]
            });

            const data = this.connectionManager.parseOutput(res, { hasMatchingTag: "Action", hasMatchingTagValue: "Delete-DM-Response" });
            return data?.Tags?.Status === "200";
        });
    }

    async deleteDMToFriend(friendId: string, messageId: string): Promise<boolean> {
        return loggedAction('🗑️ deleting DM to friend', { friendId, messageId }, async () => {
            const res = await this.connectionManager.sendMessage({
                processId: Constants.Subspace,
                tags: [
                    { name: "Action", value: Constants.Actions.DeleteDM },
                    { name: "Friend-Id", value: friendId },
                    { name: "Message-Id", value: messageId }
                ]
            });

            const data = this.connectionManager.parseOutput(res, { hasMatchingTag: "Action", hasMatchingTagValue: "Delete-DM-Response" });
            return data?.Tags?.Status === "200";
        });
    }

    async approveJoinServer(serverId: string): Promise<boolean> {
        return loggedAction('✅ approving join server (user)', { serverId }, async () => {
            // Send approve join request to the subspace process (Step 1)
            const res = await this.connectionManager.sendMessage({
                processId: Constants.Subspace,
                tags: [
                    { name: "Action", value: Constants.Actions.ApproveJoinServer },
                    { name: "Server-Id", value: serverId }
                ]
            });

            const data = this.connectionManager.parseOutput(res, { hasMatchingTag: "Action", hasMatchingTagValue: "Approve-Join-Server-Response" });
            return data?.Tags?.Status === "200";
        });
    }

    async joinServer(serverId: string): Promise<boolean> {
        return loggedAction('➡️ joining server (user)', { serverId }, async () => {
            // Send join request directly to the server process (Step 2)
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

    async joinServerWithApproval(serverId: string): Promise<boolean> {
        return loggedAction('🔄 joining server with approval (user)', { serverId }, async () => {
            // Step 1: Approve join request in Subspace
            const approvalSuccess = await this.approveJoinServer(serverId);
            if (!approvalSuccess) {
                throw new Error('Failed to approve join server request');
            }

            // Step 2: Send join request to the server
            const joinSuccess = await this.joinServer(serverId);
            if (!joinSuccess) {
                throw new Error('Failed to join server after approval');
            }

            return true;
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

    /**
     * Fetch multiple user profiles for primary names in batches with rate limiting
     * @param userIds Array of user IDs to fetch profiles for
     * @param batchSize Number of profiles to fetch concurrently (default: 10)
     * @param batchDelay Delay between batches in milliseconds (default: 220)
     * @returns Record mapping userId to Profile or null if failed
     */
    async getBulkPrimaryNames(userIds: string[], batchSize: number = 10, batchDelay: number = 220): Promise<Record<string, Profile | null>> {
        return loggedAction('🏷️ getting bulk primary names', { userIds, count: userIds.length, batchSize, batchDelay }, async () => {
            const results: Record<string, Profile | null> = {}

            for (let i = 0; i < userIds.length; i += batchSize) {
                const batch = userIds.slice(i, i + batchSize)
                const batchNumber = Math.floor(i / batchSize) + 1
                const totalBatches = Math.ceil(userIds.length / batchSize)

                console.log(`🏷️ Fetching primary names batch ${batchNumber}/${totalBatches} (${batch.length} profiles)`)

                // Fetch all profiles in current batch concurrently
                const batchPromises = batch.map(async (userId) => {
                    try {
                        const profile = await this.getProfile(userId)
                        return { userId, profile }
                    } catch (error) {
                        console.error(`❌ Failed to fetch primary name for ${userId}:`, error)
                        return { userId, profile: null }
                    }
                })

                const batchResults = await Promise.all(batchPromises)

                // Store results in key-value format
                batchResults.forEach(({ userId, profile }) => {
                    results[userId] = profile
                })

                console.log(`✅ Primary names batch ${batchNumber}/${totalBatches} completed (${batchResults.filter(r => r.profile).length}/${batch.length} successful)`)

                // Add delay between batches (except for the last batch)
                if (i + batchSize < userIds.length) {
                    await new Promise(resolve => setTimeout(resolve, batchDelay))
                }
            }

            return results
        })
    }
} 