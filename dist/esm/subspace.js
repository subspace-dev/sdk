import { AO } from "./utils/ao";
import { Constants } from "./utils/constants";
import { Server, ServerReadOnly } from "./server";
import { Profile } from "./profile";
import { Bot } from "./bot";
// ---------------- Subspace readonly client ---------------- //
export class SubspaceClientReadOnly {
    CU_URL = "https://cu.arnode.asia";
    GATEWAY_URL = "https://arnode.asia";
    ao;
    constructor(params) {
        this.CU_URL = params.CU_URL || this.CU_URL;
        this.GATEWAY_URL = params.GATEWAY_URL || this.GATEWAY_URL;
        this.ao = new AO({
            CU_URL: this.CU_URL,
            GATEWAY_URL: this.GATEWAY_URL,
        });
    }
    async getProfile(userId) {
        const res = await this.ao.read({
            process: Constants.Subspace,
            action: Constants.Actions.GetProfile,
            tags: { UserId: userId }
        });
        const data = JSON.parse(res.Data);
        return data;
    }
    async getBulkProfiles(userIds) {
        const res = await this.ao.read({
            process: Constants.Subspace,
            action: Constants.Actions.GetBulkProfile,
            tags: { UserIds: JSON.stringify(userIds) },
        });
        const data = JSON.parse(res.Data);
        return data;
    }
    async anchorToServer(anchorId) {
        const res = await this.ao.read({
            process: Constants.Subspace,
            action: Constants.Actions.AnchorToServer,
            tags: { AnchorId: anchorId },
        });
        const serverId = res['ServerId'];
        if (!serverId) {
            throw new Error('ServerId not found');
        }
        const server = await this.getServer(serverId);
        if (!server) {
            throw new Error('Server not found');
        }
        return server;
    }
    async getServer(serverId) {
        const res = await this.ao.read({
            process: serverId,
            action: Constants.Actions.Info,
        });
        const server = {
            serverId: serverId,
            name: res['Name'],
            ownerId: res['Owner'],
            logo: res['Logo'],
            categories: 'Categories' in res ? JSON.parse(res['Categories']) : [],
            channels: 'Channels' in res ? JSON.parse(res['Channels']) : [],
            roles: 'Roles' in res ? JSON.parse(res['Roles']) : [],
        };
        return new ServerReadOnly(server, this.ao);
    }
    async getOriginalId(userId) {
        const res = await this.ao.read({
            process: Constants.Subspace,
            action: Constants.Actions.GetOriginalId,
            tags: { UserId: userId },
        });
        return res['OriginalId'];
    }
    async getBot(botProcess) {
        const res = await this.ao.read({
            process: Constants.Subspace,
            action: Constants.Actions.BotInfo,
            tags: { BotProcess: botProcess },
        });
        const data = JSON.parse(res.Data);
        return data;
    }
    async anchorToBot(botAnchor) {
        const res = await this.ao.read({
            process: Constants.Subspace,
            action: Constants.Actions.AnchorToBot,
            tags: { BotAnchor: botAnchor },
        });
        const data = JSON.parse(res.Data);
        return data;
    }
}
// ---------------- Subspace writable client ---------------- //
export class SubspaceClient extends SubspaceClientReadOnly {
    constructor(params) {
        super(params);
        Object.assign(this, params);
        if (params.signer) {
            this.ao = new AO({
                CU_URL: this.CU_URL,
                GATEWAY_URL: this.GATEWAY_URL,
                signer: params.signer
            });
        }
        else {
            throw new Error('Signer is required');
        }
    }
    async getProfile(userId) {
        const tags = userId ? { UserId: userId } : undefined;
        const res = await this.ao.read({
            process: Constants.Subspace,
            action: Constants.Actions.GetProfile,
            tags: tags,
        });
        const data = JSON.parse(res.Data);
        return new Profile(data, this.ao);
    }
    async getBulkProfiles(userIds) {
        const res = await this.ao.read({
            process: Constants.Subspace,
            action: Constants.Actions.GetBulkProfile,
            tags: { UserIds: JSON.stringify(userIds) },
        });
        const data = JSON.parse(res.Data);
        return data.map(profile => new Profile(profile, this.ao));
    }
    async anchorToServer(anchorId) {
        const res = await this.ao.read({
            process: Constants.Subspace,
            action: Constants.Actions.AnchorToServer,
            tags: { AnchorId: anchorId },
        });
        const serverId = res['ServerId'];
        if (!serverId) {
            throw new Error('ServerId not found');
        }
        const server = await this.getServer(serverId);
        if (!server) {
            throw new Error('Server not found');
        }
        return server;
    }
    async getServer(serverId) {
        const res = await this.ao.read({
            process: serverId,
            action: Constants.Actions.Info,
        });
        const server = {
            serverId: serverId,
            name: res['Name'],
            ownerId: res['Owner'],
            logo: res['Logo'],
            categories: 'Categories' in res ? JSON.parse(res['Categories']) : [],
            channels: 'Channels' in res ? JSON.parse(res['Channels']) : [],
            roles: 'Roles' in res ? JSON.parse(res['Roles']) : [],
        };
        return new Server(server, this.ao);
    }
    async createProfile() {
        const res = await this.ao.write({
            process: Constants.Subspace,
            action: Constants.Actions.CreateProfile,
        });
        if (res.tags?.Status === "200" && res.id) {
            // The profile is created for the sender (message sender's address)
            // Small delay to allow profile creation to complete
            await new Promise(resolve => setTimeout(resolve, 1000));
            // Get the profile using the message sender (which is from the signer)
            const profile = await this.getProfile(); // when you dont pass a userId, it will use the signer's address
            if (profile)
                return profile;
        }
        throw new Error('Failed to create profile');
    }
    async createServer(params) {
        const res = await this.ao.write({
            process: Constants.Subspace,
            action: Constants.Actions.CreateServer,
            tags: {
                Name: params.name,
                Logo: params.logo
            },
        });
        if (res.tags?.Status === "200" && res.tags?.ServerAnchor) {
            const server = await this.anchorToServer(res.tags.ServerAnchor);
            return server;
        }
        throw new Error('Failed to create server');
    }
    async getBot(botProcess) {
        const res = await this.ao.read({
            process: Constants.Subspace,
            action: Constants.Actions.BotInfo,
            tags: { BotProcess: botProcess },
        });
        const data = JSON.parse(res.Data);
        return new Bot(data, this.ao);
    }
    async anchorToBot(botAnchor) {
        const res = await this.ao.read({
            process: Constants.Subspace,
            action: Constants.Actions.AnchorToBot,
            tags: { BotAnchor: botAnchor },
        });
        const data = JSON.parse(res.Data);
        return new Bot(data, this.ao);
    }
    async createBot(params) {
        const res = await this.ao.write({
            process: Constants.Subspace,
            action: Constants.Actions.CreateBot,
            tags: {
                BotName: params.botName,
                BotPfp: params.botPfp,
                BotPublic: params.publicBot ? "true" : "false"
            },
        });
        if (res.tags?.Status === "200" && res.tags?.BotAnchor) {
            const botAnchor = res.tags.BotAnchor;
            if (botAnchor) {
                const bot = await this.anchorToBot(botAnchor);
                if (bot)
                    return bot;
            }
        }
        throw new Error('Failed to create bot');
    }
    async addBot(params) {
        const res = await this.ao.write({
            process: Constants.Subspace,
            action: Constants.Actions.AddBot,
            tags: {
                BotProcess: params.botProcess,
                ServerId: params.serverId
            },
        });
        return res.tags?.Status === "200";
    }
    async removeBot(params) {
        const res = await this.ao.write({
            process: params.serverId,
            action: Constants.Actions.RemoveBot,
            tags: {
                BotProcess: params.botProcess
            },
        });
        return res.tags?.Status === "200";
    }
}
