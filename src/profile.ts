import { deleteDMParams, editDMParams, getDMsParams, sendDMParams, updateProfileParams } from "./types/inputs"
import { INotificationReadOnly, IProfile } from "./types/subspace"
import { AO } from "./utils/ao"
import { Constants } from "./utils/constants"
import { DMResponse } from "./types/responses"

// ---------------- Profile implementation ---------------- //

export class Profile implements IProfile {
    private ao: AO
    userId: string
    pfp?: string
    dmProcess?: string
    delegations?: string[]
    serversJoined?: Array<{ orderId: number, serverId: string }>
    friends?: {
        accepted: string[]
        sent: string[]
        received: string[]
    }

    constructor(data: IProfile, ao: AO) {
        Object.assign(this, data)
        this.ao = ao
    }

    async getNotifications(): Promise<Array<INotificationReadOnly>> {
        const res = await this.ao.read({
            process: Constants.Subspace,
            action: Constants.Actions.GetNotifications,
            tags: { UserId: this.userId },
        })

        const data = JSON.parse(res.Data) as INotificationReadOnly[]
        return data;
    }

    async updateProfile(params: updateProfileParams): Promise<Profile> {
        const tags: Record<string, string> = {}
        if (params.Pfp) tags.Pfp = params.Pfp

        const res = await this.ao.write({
            process: Constants.Subspace,
            action: Constants.Actions.UpdateProfile,
            tags,
        })

        if (res.tags?.Status === "200" && res.data) {
            const updatedProfile = res.data as Profile
            Object.assign(this, updatedProfile)
        }

        return this
    }

    async addDelegation(): Promise<boolean> {
        const res = await this.ao.write({
            process: Constants.Subspace,
            action: Constants.Actions.AddDelegation,
        })

        return res.tags?.Status === "200"
    }

    async removeDelegation(): Promise<boolean> {
        const res = await this.ao.write({
            process: Constants.Subspace,
            action: Constants.Actions.RemoveDelegation,
        })

        return res.tags?.Status === "200"
    }

    async removeAllDelegations(): Promise<boolean> {
        const res = await this.ao.write({
            process: Constants.Subspace,
            action: Constants.Actions.RemoveAllDelegations,
        })

        return res.tags?.Status === "200"
    }

    async getDMs(params: getDMsParams): Promise<DMResponse> {
        if (!this.dmProcess) {
            throw new Error('User does not have a DM process')
        }

        const res = await this.ao.read({
            process: this.dmProcess,
            action: Constants.Actions.GetDMs,
            tags: {
                FriendId: params.friendId,
                Limit: params.limit?.toString() || "",
                After: params.after?.toString() || "",
                Before: params.before?.toString() || "",
                EventId: params.eventId?.toString() || ""
            },
        })

        return JSON.parse(res.Data) as DMResponse
    }

    async sendDM(params: sendDMParams): Promise<boolean> {
        const tags: Record<string, string> = {
            FriendId: params.friendId,
            Attachments: JSON.stringify(params.attachments || [])
        }

        if (params.replyTo) {
            tags.ReplyTo = params.replyTo
        }

        const res = await this.ao.write({
            process: Constants.Subspace,
            action: Constants.Actions.SendDM,
            data: params.content,
            tags,
        })

        return res.tags?.Status === "200"
    }

    async deleteDM(params: deleteDMParams): Promise<boolean> {
        const res = await this.ao.write({
            process: Constants.Subspace,
            action: Constants.Actions.DeleteDM,
            tags: {
                FriendId: params.friendId,
                MessageId: params.messageId
            },
        })

        return res.tags?.Status === "200"
    }

    async editDM(params: editDMParams): Promise<boolean> {
        const res = await this.ao.write({
            process: Constants.Subspace,
            action: Constants.Actions.EditDM,
            data: params.content,
            tags: {
                FriendId: params.friendId,
                MessageId: params.messageId
            },
        })

        return res.tags?.Status === "200"
    }

    async sendFriendRequest(userId: string): Promise<boolean> {
        const res = await this.ao.write({
            process: Constants.Subspace,
            action: Constants.Actions.SendFriendRequest,
            tags: { FriendId: userId },
        })

        return res.tags?.Status === "200"
    }

    async acceptFriendRequest(userId: string): Promise<boolean> {
        const res = await this.ao.write({
            process: Constants.Subspace,
            action: Constants.Actions.AcceptFriendRequest,
            tags: { FriendId: userId },
        })

        return res.tags?.Status === "200"
    }

    async rejectFriendRequest(userId: string): Promise<boolean> {
        const res = await this.ao.write({
            process: Constants.Subspace,
            action: Constants.Actions.RejectFriendRequest,
            tags: { FriendId: userId },
        })

        return res.tags?.Status === "200"
    }

    async removeFriend(userId: string): Promise<boolean> {
        const res = await this.ao.write({
            process: Constants.Subspace,
            action: Constants.Actions.RemoveFriend,
            tags: { FriendId: userId },
        })

        return res.tags?.Status === "200"
    }
}