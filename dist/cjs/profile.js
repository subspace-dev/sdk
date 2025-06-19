"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.Profile = void 0;
const ao_1 = require("./utilts/ao");
const constants_1 = require("./utilts/constants");
// ---------------- Profile implementation ---------------- //
class Profile {
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
        const res = await ao_1.AO.read({
            process: constants_1.Constants.Profiles,
            action: constants_1.Constants.Actions.GetNotifications,
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
        const res = await ao_1.AO.write({
            process: constants_1.Constants.Profiles,
            action: constants_1.Constants.Actions.UpdateProfile,
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
        const res = await ao_1.AO.write({
            process: constants_1.Constants.Profiles,
            action: constants_1.Constants.Actions.AddDelegation,
            ao: this.ao,
            signer: this.signer
        });
        return res.tags?.Status === "200";
    }
    async removeDelegation() {
        const res = await ao_1.AO.write({
            process: constants_1.Constants.Profiles,
            action: constants_1.Constants.Actions.RemoveDelegation,
            ao: this.ao,
            signer: this.signer
        });
        return res.tags?.Status === "200";
    }
    async removeAllDelegations() {
        const res = await ao_1.AO.write({
            process: constants_1.Constants.Profiles,
            action: constants_1.Constants.Actions.RemoveAllDelegations,
            ao: this.ao,
            signer: this.signer
        });
        return res.tags?.Status === "200";
    }
    async getDMs(params) {
        if (!this.dmProcess) {
            throw new Error('User does not have a DM process');
        }
        const res = await ao_1.AO.read({
            process: this.dmProcess,
            action: constants_1.Constants.Actions.GetDMs,
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
        const res = await ao_1.AO.write({
            process: constants_1.Constants.Profiles,
            action: constants_1.Constants.Actions.SendDM,
            data: params.content,
            tags,
            ao: this.ao,
            signer: this.signer
        });
        return res.tags?.Status === "200";
    }
    async deleteDM(params) {
        const res = await ao_1.AO.write({
            process: constants_1.Constants.Profiles,
            action: constants_1.Constants.Actions.DeleteDM,
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
        const res = await ao_1.AO.write({
            process: constants_1.Constants.Profiles,
            action: constants_1.Constants.Actions.EditDM,
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
        const res = await ao_1.AO.write({
            process: constants_1.Constants.Profiles,
            action: constants_1.Constants.Actions.SendFriendRequest,
            tags: { FriendId: userId },
            ao: this.ao,
            signer: this.signer
        });
        return res.tags?.Status === "200";
    }
    async acceptFriendRequest(userId) {
        const res = await ao_1.AO.write({
            process: constants_1.Constants.Profiles,
            action: constants_1.Constants.Actions.AcceptFriendRequest,
            tags: { FriendId: userId },
            ao: this.ao,
            signer: this.signer
        });
        return res.tags?.Status === "200";
    }
    async rejectFriendRequest(userId) {
        const res = await ao_1.AO.write({
            process: constants_1.Constants.Profiles,
            action: constants_1.Constants.Actions.RejectFriendRequest,
            tags: { FriendId: userId },
            ao: this.ao,
            signer: this.signer
        });
        return res.tags?.Status === "200";
    }
    async removeFriend(userId) {
        const res = await ao_1.AO.write({
            process: constants_1.Constants.Profiles,
            action: constants_1.Constants.Actions.RemoveFriend,
            tags: { FriendId: userId },
            ao: this.ao,
            signer: this.signer
        });
        return res.tags?.Status === "200";
    }
}
exports.Profile = Profile;
