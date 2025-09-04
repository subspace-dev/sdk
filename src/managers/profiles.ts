import { Subspace } from "..";
import type { IProfile, Tag } from "../types/subspace";
import type {
    ICreateProfile,
} from "../types/inputs";
import { Constants } from "../utils/constants";
import { SubspaceValidation } from "../utils/validation";

export class SubspaceProfiles {

    static formatProfile(profile: IProfile): IProfile {
        if (profile && profile.servers) {
            Object.keys(profile.servers).forEach(serverId => {
                profile.servers[serverId].approved = JSON.parse(profile.servers[serverId].approved.toString())
            })
        }
        console.log(profile)
        return profile
    }

    public static async createProfile({ pfp, banner, bio }: ICreateProfile): Promise<IProfile> {
        // Validate inputs before making any backend calls
        SubspaceValidation.validateProfileFields({ pfp, banner, bio });

        const tags: Tag[] = [{ name: "Action", value: "create-profile" }]

        // get source code for dm process
        let dmSource = Subspace.sources.dm.lua
        if (!dmSource) await Subspace.getSources()
        dmSource = Subspace.sources.dm.lua
        if (!dmSource) throw new Error("dm source not found")
        dmSource = dmSource.replace("<<SUBSPACE>>", Constants.subspaceProcess)

        // spawn dm process
        const dmProcess = await Subspace.ao().spawn({})
        // add functionality to the dm process
        await Subspace.ao().runLua({ processId: dmProcess, code: dmSource })

        tags.push({ name: "dm-process", value: dmProcess })
        if (pfp) tags.push({ name: "pfp", value: pfp })
        if (banner) tags.push({ name: "banner", value: banner })
        if (bio) tags.push({ name: "bio", value: bio })

        const res = await Subspace.ao().write({ processId: Constants.subspaceProcess, tags: tags })
        const createProfileRes = Subspace.ao().matchAction<IProfile>("create-profile-response", res)
        return this.formatProfile(createProfileRes)
    }

    public static async getProfile(id: string): Promise<IProfile> {
        // Validate user ID
        SubspaceValidation.validateUserId(id);

        const res = await Subspace.ao().read<IProfile>({ path: `${Constants.subspaceProcess}/now/subspace/profiles/${id}` })
        return this.formatProfile(res)
    }

    public static async updateProfile({ pfp, banner, bio }: ICreateProfile): Promise<IProfile> {
        // Validate inputs before making any backend calls
        SubspaceValidation.validateProfileFields({ pfp, banner, bio });

        const tags: Tag[] = [{ name: "Action", value: "update-profile" }]

        if (pfp) tags.push({ name: "pfp", value: pfp })
        if (banner) tags.push({ name: "banner", value: banner })
        if (bio) tags.push({ name: "bio", value: bio })

        const res = await Subspace.ao().write({ processId: Constants.subspaceProcess, tags: tags })
        const updateProfileRes = Subspace.ao().matchAction<IProfile>("update-profile-response", res)
        return this.formatProfile(updateProfileRes)
    }

    public static async addFriend(userId: string): Promise<boolean> {
        // Validate friend ID
        SubspaceValidation.validateFriendId(userId);

        const tags: Tag[] = [{ name: "Action", value: "add-friend" }]
        tags.push({ name: "friend-id", value: userId })

        const res = await Subspace.ao().write({ processId: Constants.subspaceProcess, tags: tags })
        return (res.status == 200)
    }

    public static async acceptFriend(userId: string): Promise<boolean> {
        // Validate friend ID
        SubspaceValidation.validateFriendId(userId);

        const tags: Tag[] = [{ name: "Action", value: "accept-friend" }]
        tags.push({ name: "friend-id", value: userId })

        const res = await Subspace.ao().write({ processId: Constants.subspaceProcess, tags: tags })
        return (res.status == 200)
    }

    public static async rejectFriend(userId: string): Promise<boolean> {
        // Validate friend ID
        SubspaceValidation.validateFriendId(userId);

        const tags: Tag[] = [{ name: "Action", value: "reject-friend" }]
        tags.push({ name: "friend-id", value: userId })

        const res = await Subspace.ao().write({ processId: Constants.subspaceProcess, tags: tags })
        return (res.status == 200)
    }

    public static async removeFriend(userId: string): Promise<boolean> {
        // Validate friend ID
        SubspaceValidation.validateFriendId(userId);

        const tags: Tag[] = [{ name: "Action", value: "remove-friend" }]
        tags.push({ name: "friend-id", value: userId })

        const res = await Subspace.ao().write({ processId: Constants.subspaceProcess, tags: tags })
        return (res.status == 200)
    }

    public static async sendDM({ userId, content }: { userId: string, content: string }): Promise<boolean> {
        // Validate DM parameters
        SubspaceValidation.validateDMParams({ userId, content });

        const tags: Tag[] = [{ name: "Action", value: "send-dm" }]
        tags.push({ name: "receiver-id", value: userId })
        tags.push({ name: "content", value: content })

        const res = await Subspace.ao().write({ processId: Constants.subspaceProcess, tags: tags })
        return (res.status == 200)
    }

    public static async editDM({ userId, messageId, content }: { userId: string, messageId: string, content: string }): Promise<boolean> {
        // Validate DM parameters
        SubspaceValidation.validateDMParams({ userId, content, messageId });

        const tags: Tag[] = [{ name: "Action", value: "edit-dm" }]
        tags.push({ name: "receiver-id", value: userId })
        tags.push({ name: "message-id", value: messageId })
        tags.push({ name: "content", value: content })

        const res = await Subspace.ao().write({ processId: Constants.subspaceProcess, tags: tags })
        return (res.status == 200)
    }

    public static async deleteDM({ userId, messageId }: { userId: string, messageId: string }): Promise<boolean> {
        // Validate DM parameters
        SubspaceValidation.validateDMParams({ userId, messageId });

        const tags: Tag[] = [{ name: "Action", value: "delete-dm" }]
        tags.push({ name: "receiver-id", value: userId })
        tags.push({ name: "message-id", value: messageId })

        const res = await Subspace.ao().write({ processId: Constants.subspaceProcess, tags: tags })
        return (res.status == 200)
    }
}