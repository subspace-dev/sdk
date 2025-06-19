import { AO } from "./utils/ao";
import { Constants } from "./utils/constants";
// ---------------- Profile implementation ---------------- //
export class Profile {
    ao;
    signer;
    userId;
    pfp;
    dmProcess;
    delegations;
    serversJoined;
    friends;
    constructor(data, ao, signer) {
        Object.assign(this, data);
        this.ao = ao;
        this.signer = signer;
    }
    async getNotifications() {
        const res = await AO.read({
            process: Constants.Profiles,
            action: Constants.Actions.GetNotifications,
            tags: { UserId: this.userId },
            ao: this.ao
        });
        const data = JSON.parse(res.Data);
        return data;
    }
    async updateProfile(params) {
        const tags = {};
        if (params.Pfp)
            tags.Pfp = params.Pfp;
        const res = await AO.write({
            process: Constants.Profiles,
            action: Constants.Actions.UpdateProfile,
            tags,
            ao: this.ao,
            signer: this.signer
        });
        if (res.tags?.Status === "200" && res.data) {
            const updatedProfile = res.data;
            Object.assign(this, updatedProfile);
        }
        return this;
    }
    async addDelegation() {
        const res = await AO.write({
            process: Constants.Profiles,
            action: Constants.Actions.AddDelegation,
            ao: this.ao,
            signer: this.signer
        });
        return res.tags?.Status === "200";
    }
    async removeDelegation() {
        const res = await AO.write({
            process: Constants.Profiles,
            action: Constants.Actions.RemoveDelegation,
            ao: this.ao,
            signer: this.signer
        });
        return res.tags?.Status === "200";
    }
    async removeAllDelegations() {
        const res = await AO.write({
            process: Constants.Profiles,
            action: Constants.Actions.RemoveAllDelegations,
            ao: this.ao,
            signer: this.signer
        });
        return res.tags?.Status === "200";
    }
    async getDMs(params) {
        if (!this.dmProcess) {
            throw new Error('User does not have a DM process');
        }
        const res = await AO.read({
            process: this.dmProcess,
            action: Constants.Actions.GetDMs,
            tags: {
                FriendId: params.friendId,
                Limit: params.limit?.toString() || "",
                After: params.after?.toString() || "",
                Before: params.before?.toString() || "",
                EventId: params.eventId?.toString() || ""
            },
            ao: this.ao
        });
        return JSON.parse(res.Data);
    }
    async sendDM(params) {
        const tags = {
            FriendId: params.friendId,
            Attachments: JSON.stringify(params.attachments || [])
        };
        if (params.replyTo) {
            tags.ReplyTo = params.replyTo;
        }
        const res = await AO.write({
            process: Constants.Profiles,
            action: Constants.Actions.SendDM,
            data: params.content,
            tags,
            ao: this.ao,
            signer: this.signer
        });
        return res.tags?.Status === "200";
    }
    async deleteDM(params) {
        const res = await AO.write({
            process: Constants.Profiles,
            action: Constants.Actions.DeleteDM,
            tags: {
                FriendId: params.friendId,
                MessageId: params.messageId
            },
            ao: this.ao,
            signer: this.signer
        });
        return res.tags?.Status === "200";
    }
    async editDM(params) {
        const res = await AO.write({
            process: Constants.Profiles,
            action: Constants.Actions.EditDM,
            data: params.content,
            tags: {
                FriendId: params.friendId,
                MessageId: params.messageId
            },
            ao: this.ao,
            signer: this.signer
        });
        return res.tags?.Status === "200";
    }
    async sendFriendRequest(userId) {
        const res = await AO.write({
            process: Constants.Profiles,
            action: Constants.Actions.SendFriendRequest,
            tags: { FriendId: userId },
            ao: this.ao,
            signer: this.signer
        });
        return res.tags?.Status === "200";
    }
    async acceptFriendRequest(userId) {
        const res = await AO.write({
            process: Constants.Profiles,
            action: Constants.Actions.AcceptFriendRequest,
            tags: { FriendId: userId },
            ao: this.ao,
            signer: this.signer
        });
        return res.tags?.Status === "200";
    }
    async rejectFriendRequest(userId) {
        const res = await AO.write({
            process: Constants.Profiles,
            action: Constants.Actions.RejectFriendRequest,
            tags: { FriendId: userId },
            ao: this.ao,
            signer: this.signer
        });
        return res.tags?.Status === "200";
    }
    async removeFriend(userId) {
        const res = await AO.write({
            process: Constants.Profiles,
            action: Constants.Actions.RemoveFriend,
            tags: { FriendId: userId },
            ao: this.ao,
            signer: this.signer
        });
        return res.tags?.Status === "200";
    }
}
