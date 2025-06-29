import { addBotParams, createBotParams, createServerParams, removeBotParams, SubspaceConfig, SubspaceConfigReadOnly } from "./types/inputs";
import { IBotReadOnly, IProfile, IProfileReadOnly, IServerReadOnly, ISubspace, ISubspaceReadOnly } from "./types/subspace";
import { AoClient, AoSigner } from "./types/ao";
import { connect } from "@permaweb/aoconnect";
import { AO } from "./utils/ao";
import { Constants } from "./utils/constants";
import { Server, ServerReadOnly } from "./server";
import { Profile } from "./profile";
import { Bot } from "./bot";

// ---------------- Subspace readonly client ---------------- //

export class SubspaceClientReadOnly implements ISubspaceReadOnly {
    readonly CU_URL: string = "https://cu.arnode.asia"
    readonly GATEWAY_URL: string = "https://arnode.asia"
    ao: AO

    constructor(params: SubspaceConfigReadOnly) {
        this.CU_URL = params.CU_URL || this.CU_URL
        this.GATEWAY_URL = params.GATEWAY_URL || this.GATEWAY_URL
        this.ao = new AO({
            CU_URL: this.CU_URL,
            GATEWAY_URL: this.GATEWAY_URL,
        })
    }

    async getProfile(userId: string): Promise<IProfileReadOnly | null> {
        const res = await this.ao.read({
            process: Constants.Subspace,
            action: Constants.Actions.GetProfile,
            tags: { UserId: userId }
        })

        const data = JSON.parse(res.Data) as IProfileReadOnly
        return data
    }

    async getBulkProfiles(userIds: string[]): Promise<Array<IProfileReadOnly>> {
        const res = await this.ao.read({
            process: Constants.Subspace,
            action: Constants.Actions.GetBulkProfile,
            tags: { UserIds: JSON.stringify(userIds) },
        })

        const data = JSON.parse(res.Data) as IProfileReadOnly[]
        return data
    }

    async anchorToServer(anchorId: string): Promise<IServerReadOnly> {
        const res = await this.ao.read({
            process: Constants.Subspace,
            action: Constants.Actions.AnchorToServer,
            tags: { AnchorId: anchorId },
        })

        const serverId = res['ServerId']
        if (!serverId) {
            throw new Error('ServerId not found')
        }

        const server = await this.getServer(serverId)
        if (!server) {
            throw new Error('Server not found')
        }

        return server
    }

    async getServer(serverId: string): Promise<ServerReadOnly | null> {
        const res = await this.ao.read({
            process: serverId,
            action: Constants.Actions.Info,
        })

        const server: IServerReadOnly = {
            serverId: serverId,
            name: res['Name'],
            ownerId: res['Owner'],
            logo: res['Logo'],
            categories: 'Categories' in res ? JSON.parse(res['Categories']) : [],
            channels: 'Channels' in res ? JSON.parse(res['Channels']) : [],
            roles: 'Roles' in res ? JSON.parse(res['Roles']) : [],
        }

        return new ServerReadOnly(server, this.ao)
    }

    async getOriginalId(userId: string): Promise<string> {
        const res = await this.ao.read({
            process: Constants.Subspace,
            action: Constants.Actions.GetOriginalId,
            tags: { UserId: userId },
        })

        return res['OriginalId']
    }

    async getBot(botProcess: string): Promise<IBotReadOnly | null> {
        const res = await this.ao.read({
            process: Constants.Subspace,
            action: Constants.Actions.BotInfo,
            tags: { BotProcess: botProcess },
        })

        const data = JSON.parse(res.Data) as IBotReadOnly
        return data
    }

    async anchorToBot(botAnchor: string): Promise<IBotReadOnly | null> {
        const res = await this.ao.read({
            process: Constants.Subspace,
            action: Constants.Actions.AnchorToBot,
            tags: { BotAnchor: botAnchor },
        })

        const data = JSON.parse(res.Data) as IBotReadOnly
        return data
    }
}

// ---------------- Subspace writable client ---------------- //

export class SubspaceClient extends SubspaceClientReadOnly implements ISubspace {

    constructor(params: SubspaceConfig) {
        super(params)
        Object.assign(this, params)
        if (params.signer) {
            this.ao = new AO({
                CU_URL: this.CU_URL,
                GATEWAY_URL: this.GATEWAY_URL,
                signer: params.signer
            })
        } else {
            throw new Error('Signer is required')
        }
    }

    async getProfile(userId?: string): Promise<IProfile | null> {
        const tags = userId ? { UserId: userId } : undefined
        const res = await this.ao.read({
            process: Constants.Subspace,
            action: Constants.Actions.GetProfile,
            tags: tags,
        })

        const data = JSON.parse(res.Data) as IProfile
        return new Profile(data, this.ao)
    }

    async getBulkProfiles(userIds: string[]): Promise<Array<IProfile>> {
        const res = await this.ao.read({
            process: Constants.Subspace,
            action: Constants.Actions.GetBulkProfile,
            tags: { UserIds: JSON.stringify(userIds) },
        })

        const data = JSON.parse(res.Data) as IProfile[]
        return data.map(profile => new Profile(profile, this.ao))
    }

    async anchorToServer(anchorId: string): Promise<Server> {
        const res = await this.ao.read({
            process: Constants.Subspace,
            action: Constants.Actions.AnchorToServer,
            tags: { AnchorId: anchorId },
        })

        const serverId = res['ServerId']
        if (!serverId) {
            throw new Error('ServerId not found')
        }

        const server = await this.getServer(serverId)
        if (!server) {
            throw new Error('Server not found')
        }

        return server
    }

    async getServer(serverId: string): Promise<Server | null> {
        const res = await this.ao.read({
            process: serverId,
            action: Constants.Actions.Info,
        })

        const server: IServerReadOnly = {
            serverId: serverId,
            name: res['Name'],
            ownerId: res['Owner'],
            logo: res['Logo'],
            categories: 'Categories' in res ? JSON.parse(res['Categories']) : [],
            channels: 'Channels' in res ? JSON.parse(res['Channels']) : [],
            roles: 'Roles' in res ? JSON.parse(res['Roles']) : [],
        }

        return new Server(server, this.ao)
    }

    async createProfile(): Promise<IProfile> {
        const res = await this.ao.write({
            process: Constants.Subspace,
            action: Constants.Actions.CreateProfile,
        })

        if (res.tags?.Status === "200" && res.id) {
            // The profile is created for the sender (message sender's address)
            // Small delay to allow profile creation to complete
            await new Promise(resolve => setTimeout(resolve, 1000))
            // Get the profile using the message sender (which is from the signer)
            const profile = await this.getProfile() // when you dont pass a userId, it will use the signer's address
            if (profile) return profile
        }
        throw new Error('Failed to create profile')
    }

    async createServer(params: createServerParams): Promise<Server> {
        const res = await this.ao.write({
            process: Constants.Subspace,
            action: Constants.Actions.CreateServer,
            tags: {
                Name: params.name,
                Logo: params.logo
            },
        })

        if (res.tags?.Status === "200" && res.tags?.ServerAnchor) {
            const server = await this.anchorToServer(res.tags.ServerAnchor)
            return server
        }
        throw new Error('Failed to create server')
    }

    async getBot(botProcess: string): Promise<Bot | null> {
        const res = await this.ao.read({
            process: Constants.Subspace,
            action: Constants.Actions.BotInfo,
            tags: { BotProcess: botProcess },
        })

        const data = JSON.parse(res.Data) as IBotReadOnly
        return new Bot(data, this.ao)
    }

    async anchorToBot(botAnchor: string): Promise<Bot | null> {
        const res = await this.ao.read({
            process: Constants.Subspace,
            action: Constants.Actions.AnchorToBot,
            tags: { BotAnchor: botAnchor },
        })

        const data = JSON.parse(res.Data) as IBotReadOnly
        return new Bot(data, this.ao)
    }

    async createBot(params: createBotParams): Promise<Bot> {
        const res = await this.ao.write({
            process: Constants.Subspace,
            action: Constants.Actions.CreateBot,
            tags: {
                BotName: params.botName,
                BotPfp: params.botPfp,
                BotPublic: params.publicBot ? "true" : "false"
            },
        })

        if (res.tags?.Status === "200" && res.tags?.BotAnchor) {
            const botAnchor = res.tags.BotAnchor as string

            if (botAnchor) {
                const bot = await this.anchorToBot(botAnchor)
                if (bot) return bot
            }

        }
        throw new Error('Failed to create bot')
    }

    async addBot(params: addBotParams): Promise<boolean> {
        const res = await this.ao.write({
            process: Constants.Subspace,
            action: Constants.Actions.AddBot,
            tags: {
                BotProcess: params.botProcess,
                ServerId: params.serverId
            },
        })

        return res.tags?.Status === "200"
    }

    async removeBot(params: removeBotParams): Promise<boolean> {
        const res = await this.ao.write({
            process: params.serverId,
            action: Constants.Actions.RemoveBot,
            tags: {
                BotProcess: params.botProcess
            },
        })

        return res.tags?.Status === "200"
    }
}