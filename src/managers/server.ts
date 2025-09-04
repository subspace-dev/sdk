
import { Subspace, SubspaceProfiles } from "..";
import type { IProfile, IMember, IServer, Tag } from "../types/subspace";
import type {
    ICreateServer,
    IUpdateServer,
} from "../types/inputs";
import { Constants } from "../utils/constants";
import { log } from "../utils/logger";

export class SubspaceServers {
    public static async createServer(input: ICreateServer): Promise<IServer> {
        const tags: Tag[] = [{ name: "Action", value: "create-server" }]

        if (!input.serverName) throw new Error("serverName is required")

        tags.push({ name: "server-name", value: input.serverName })

        if (input.serverDescription) {
            tags.push({ name: "description", value: input.serverDescription })
        }
        if (input.serverPfp) {
            tags.push({ name: "pfp", value: input.serverPfp })
        }
        if (input.serverBanner) {
            tags.push({ name: "banner", value: input.serverBanner })
        }
        tags.push({ name: "server-public", value: "true" })

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

        return Subspace.ao().matchAction<IServer>("create-server-response", res)
    }

    public static async getServer(serverId: string): Promise<IServer> {
        return await Subspace.ao().read<IServer>({ path: `/${serverId}/now/server` })
    }

    public static async getServerMembers(serverId: string): Promise<Record<string, IMember>> {
        const members = await Subspace.ao().read<Record<string, IMember>>({ path: `/${serverId}/now/members` })
        return members
    }

    public static async updateServer({ serverId, serverName, serverDescription, serverPfp, serverBanner }: IUpdateServer): Promise<IServer> {
        const tags: Tag[] = [{ name: "Action", value: "update-server" }]

        if (serverName) tags.push({ name: "server-name", value: serverName })
        if (serverDescription) tags.push({ name: "description", value: serverDescription })
        if (serverPfp) tags.push({ name: "pfp", value: serverPfp })
        if (serverBanner) tags.push({ name: "banner", value: serverBanner })

        const res = await Subspace.ao().write({ processId: serverId, tags: tags })
        return Subspace.ao().matchAction<IServer>("update-server-response", res)
    }

    public static async joinServer(serverId: string): Promise<boolean> {
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

}