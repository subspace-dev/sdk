import { ConnectionManager } from "../connection-manager";
import { Constants } from "../utils/constants";
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
        const start = Date.now();

        try {
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
                return null;
            }
        } catch (error) {
            console.error(error)
            console.info(userId, this.connectionManager.owner)
            if (userId == this.connectionManager.owner) {
                console.info("profile not found, creating new")
                const profileId = await this.createProfile()
                if (profileId) {
                    return this.getProfile(userId)
                } else {
                    return null
                }
            }
            const duration = Date.now() - start;
            return null;
        }
    }

    async getBulkProfiles(userIds: string[]): Promise<Profile[]> {
        try {
            const res = await this.connectionManager.dryrun({
                processId: Constants.Subspace,
                tags: [
                    { name: "Action", value: Constants.Actions.GetBulkProfile },
                    { name: "UserIds", value: JSON.stringify(userIds) }
                ]
            });

            const data = this.connectionManager.parseOutput(res);
            return data || [];
        } catch (error) {
            return [];
        }
    }

    async createProfile(): Promise<string | null> {
        const start = Date.now();

        try {

            // spawn dm process
            const dmProcess = await this.connectionManager.spawn({
                tags: [
                    { name: "Action", value: Constants.Actions.CreateProfile },
                    { name: "Owner", value: this.connectionManager.owner }
                ]
            })

            console.log("DmProcess:", dmProcess)


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
            console.log("Hydrate DM:", dmRes.id)

            // wait 1.5 seconds for dm process to finish
            await new Promise(resolve => setTimeout(resolve, 1500))

            const res = await this.connectionManager.sendMessage({
                processId: Constants.Subspace,
                tags: [
                    { name: "Action", value: Constants.Actions.CreateProfile },
                    { name: "DmProcess", value: dmProcess }
                ]
            });

            console.log("res", res)
            const data = this.connectionManager.parseOutput(res);
            console.log("data", data)
            const duration = Date.now() - start;

            return data?.profileId || null;
        } catch (error) {
            const duration = Date.now() - start;
            return null;
        }
    }

    async updateProfile(params: { pfp?: string; displayName?: string; bio?: string; banner?: string }): Promise<boolean> {
        try {
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

            const data = this.connectionManager.parseOutput(res);
            return data?.success === true;
        } catch (error) {
            return false;
        }
    }

    async getNotifications(userId: string): Promise<Notification[]> {
        try {
            const res = await this.connectionManager.dryrun({
                processId: Constants.Subspace,
                tags: [
                    { name: "Action", value: Constants.Actions.GetNotifications },
                    { name: "UserId", value: userId }
                ]
            });

            const data = this.connectionManager.parseOutput(res);
            return data || [];
        } catch (error) {
            return [];
        }
    }

    async sendFriendRequest(userId: string): Promise<boolean> {
        try {
            const res = await this.connectionManager.sendMessage({
                processId: Constants.Subspace,
                tags: [
                    { name: "Action", value: Constants.Actions.SendFriendRequest },
                    { name: "UserId", value: userId }
                ]
            });

            const data = this.connectionManager.parseOutput(res);
            return data?.success === true;
        } catch (error) {
            return false;
        }
    }

    async acceptFriendRequest(userId: string): Promise<boolean> {
        try {
            const res = await this.connectionManager.sendMessage({
                processId: Constants.Subspace,
                tags: [
                    { name: "Action", value: Constants.Actions.AcceptFriendRequest },
                    { name: "UserId", value: userId }
                ]
            });

            const data = this.connectionManager.parseOutput(res);
            return data?.success === true;
        } catch (error) {
            return false;
        }
    }

    async rejectFriendRequest(userId: string): Promise<boolean> {
        try {
            const res = await this.connectionManager.sendMessage({
                processId: Constants.Subspace,
                tags: [
                    { name: "Action", value: Constants.Actions.RejectFriendRequest },
                    { name: "UserId", value: userId }
                ]
            });

            const data = this.connectionManager.parseOutput(res);
            return data?.success === true;
        } catch (error) {
            return false;
        }
    }

    async removeFriend(userId: string): Promise<boolean> {
        try {
            const res = await this.connectionManager.sendMessage({
                processId: Constants.Subspace,
                tags: [
                    { name: "Action", value: Constants.Actions.RemoveFriend },
                    { name: "UserId", value: userId }
                ]
            });

            const data = this.connectionManager.parseOutput(res);
            return data?.success === true;
        } catch (error) {
            return false;
        }
    }

    async getDMs(dmProcessId: string, params: { limit?: number; before?: string; after?: string } = {}): Promise<DMResponse | null> {
        try {
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
        } catch (error) {
            return null;
        }
    }

    async sendDM(dmProcessId: string, params: { content: string; attachments?: string; replyTo?: number }): Promise<boolean> {
        try {
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

            const data = this.connectionManager.parseOutput(res);
            return data?.success === true;
        } catch (error) {
            return false;
        }
    }

    async editDM(dmProcessId: string, params: { messageId: string; content: string }): Promise<boolean> {
        try {
            const res = await this.connectionManager.sendMessage({
                processId: dmProcessId,
                tags: [
                    { name: "Action", value: Constants.Actions.EditDM },
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

    async deleteDM(dmProcessId: string, messageId: string): Promise<boolean> {
        try {
            const res = await this.connectionManager.sendMessage({
                processId: dmProcessId,
                tags: [
                    { name: "Action", value: Constants.Actions.DeleteDM },
                    { name: "MessageId", value: messageId }
                ]
            });

            const data = this.connectionManager.parseOutput(res);
            return data?.success === true;
        } catch (error) {
            return false;
        }
    }

    async joinServer(serverId: string): Promise<boolean> {
        try {
            const res = await this.connectionManager.sendMessage({
                processId: Constants.Subspace,
                tags: [
                    { name: "Action", value: Constants.Actions.JoinServer },
                    { name: "ServerId", value: serverId }
                ]
            });

            const data = this.connectionManager.parseOutput(res);
            return data?.success === true;
        } catch (error) {
            return false;
        }
    }

    async leaveServer(serverId: string): Promise<boolean> {
        try {
            const res = await this.connectionManager.sendMessage({
                processId: Constants.Subspace,
                tags: [
                    { name: "Action", value: Constants.Actions.LeaveServer },
                    { name: "ServerId", value: serverId }
                ]
            });

            const data = this.connectionManager.parseOutput(res);
            return data?.success === true;
        } catch (error) {
            return false;
        }
    }

    async addDelegation(): Promise<boolean> {
        try {
            const res = await this.connectionManager.sendMessage({
                processId: Constants.Subspace,
                tags: [
                    { name: "Action", value: Constants.Actions.AddDelegation }
                ]
            });

            const data = this.connectionManager.parseOutput(res);
            return data?.success === true;
        } catch (error) {
            return false;
        }
    }

    async removeDelegation(): Promise<boolean> {
        try {
            const res = await this.connectionManager.sendMessage({
                processId: Constants.Subspace,
                tags: [
                    { name: "Action", value: Constants.Actions.RemoveDelegation }
                ]
            });

            const data = this.connectionManager.parseOutput(res);
            return data?.success === true;
        } catch (error) {
            return false;
        }
    }

    async removeAllDelegations(): Promise<boolean> {
        try {
            const res = await this.connectionManager.sendMessage({
                processId: Constants.Subspace,
                tags: [
                    { name: "Action", value: Constants.Actions.RemoveAllDelegations }
                ]
            });

            const data = this.connectionManager.parseOutput(res);
            return data?.success === true;
        } catch (error) {
            return false;
        }
    }
} 