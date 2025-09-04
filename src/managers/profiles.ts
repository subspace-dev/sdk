import { Subspace } from "..";
import type { IProfile, Tag } from "../types/subspace";
import type {
    ICreateProfile,
} from "../types/inputs";
import { Constants } from "../utils/constants";

export class SubspaceProfiles {

    static formatProfile(profile: IProfile): IProfile {
        if (profile && profile.servers) {
            Object.keys(profile.servers).forEach(serverId => {
                profile.servers[serverId].approved = JSON.parse(profile.servers[serverId].approved.toString())
            })
        }
        return profile
    }

    public static async createProfile({ pfp, banner, bio }: ICreateProfile): Promise<IProfile> {
        const tags: Tag[] = [{ name: "Action", value: "create-profile" }]

        // get source code for dm process
        let dmSource = Subspace.sources.dm.lua
        if (!dmSource) await Subspace.getSources()
        dmSource = Subspace.sources.dm.lua
        if (!dmSource) throw new Error("dm source not found")
        dmSource = dmSource.replace("<<SUBSPACE>>", Constants.subspaceProcess)


        const dmProcess = await Subspace.ao().spawn({})

        tags.push({ name: "dm-process", value: dmProcess })
        if (pfp) tags.push({ name: "pfp", value: pfp })
        if (banner) tags.push({ name: "banner", value: banner })
        if (bio) tags.push({ name: "bio", value: bio })

        const res = await Subspace.ao().write({ processId: Constants.subspaceProcess, tags: tags })
        const createProfileRes = Subspace.ao().matchAction<IProfile>("create-profile-response", res)
        return this.formatProfile(createProfileRes)
    }

    public static async getProfile(id: string): Promise<IProfile> {
        const res = await Subspace.ao().read<IProfile>({ path: `${Constants.subspaceProcess}/now/subspace/profiles/${id}` })
        return this.formatProfile(res)
    }

    public static async updateProfile({ pfp, banner, bio }: ICreateProfile): Promise<IProfile> {
        const tags: Tag[] = [{ name: "Action", value: "update-profile" }]

        if (pfp) tags.push({ name: "pfp", value: pfp })
        if (banner) tags.push({ name: "banner", value: banner })
        if (bio) tags.push({ name: "bio", value: bio })

        const res = await Subspace.ao().write({ processId: Constants.subspaceProcess, tags: tags })
        const updateProfileRes = Subspace.ao().matchAction<IProfile>("update-profile-response", res)
        return this.formatProfile(updateProfileRes)
    }


}