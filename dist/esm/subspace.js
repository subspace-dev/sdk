import { connect } from "@permaweb/aoconnect";
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
        Object.assign(this, params);
        this.ao = connect({
            MODE: "legacy",
            CU_URL: this.CU_URL,
            GATEWAY_URL: this.GATEWAY_URL
        });
    }
    async getProfile(userId) {
        const res = await AO.read({
            process: Constants.Profiles,
            action: Constants.Actions.GetProfile,
            tags: { UserId: userId },
            ao: this.ao
        });
        const data = JSON.parse(res.Data);
        return data;
    }
    async getBulkProfiles(userIds) {
        const res = await AO.read({
            process: Constants.Profiles,
            action: Constants.Actions.GetBulkProfile,
            tags: { UserIds: JSON.stringify(userIds) },
            ao: this.ao
        });
        const data = JSON.parse(res.Data);
        return data;
    }
    async anchorToServer(anchorId) {
        const res = await AO.read({
            process: Constants.Profiles,
            action: Constants.Actions.AnchorToServer,
            tags: { AnchorId: anchorId },
            ao: this.ao
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
        const res = await AO.read({
            process: serverId,
            action: Constants.Actions.Info,
            ao: this.ao
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
        const res = await AO.read({
            process: Constants.Profiles,
            action: Constants.Actions.GetOriginalId,
            tags: { UserId: userId },
            ao: this.ao
        });
        return res['OriginalId'];
    }
    async getBot(botProcess) {
        const res = await AO.read({
            process: Constants.Profiles,
            action: Constants.Actions.BotInfo,
            tags: { BotProcess: botProcess },
            ao: this.ao
        });
        const data = JSON.parse(res.Data);
        return data;
    }
    async anchorToBot(botAnchor) {
        const res = await AO.read({
            process: Constants.Profiles,
            action: Constants.Actions.AnchorToBot,
            tags: { BotAnchor: botAnchor },
            ao: this.ao
        });
        const data = JSON.parse(res.Data);
        return data;
    }
}
// ---------------- Subspace writable client ---------------- //
export class SubspaceClient extends SubspaceClientReadOnly {
    signer;
    constructor(params) {
        super(params);
        this.signer = params.signer;
        Object.assign(this, params);
    }
    async getProfile(userId) {
        const tags = userId ? { UserId: userId } : undefined;
        const res = await AO.read({
            process: Constants.Profiles,
            action: Constants.Actions.GetProfile,
            tags: tags,
            ao: this.ao
        });
        const data = JSON.parse(res.Data);
        return new Profile(data, this.ao, this.signer);
    }
    async getBulkProfiles(userIds) {
        const res = await AO.read({
            process: Constants.Profiles,
            action: Constants.Actions.GetBulkProfile,
            tags: { UserIds: JSON.stringify(userIds) },
            ao: this.ao
        });
        const data = JSON.parse(res.Data);
        return data.map(profile => new Profile(profile, this.ao, this.signer));
    }
    async anchorToServer(anchorId) {
        const res = await AO.read({
            process: Constants.Profiles,
            action: Constants.Actions.AnchorToServer,
            tags: { AnchorId: anchorId },
            ao: this.ao
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
        const res = await AO.read({
            process: serverId,
            action: Constants.Actions.Info,
            ao: this.ao
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
        return new Server(server, this.ao, this.signer);
    }
    async createProfile() {
        const res = await AO.write({
            process: Constants.Profiles,
            action: Constants.Actions.CreateProfile,
            ao: this.ao,
            signer: this.signer
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
        const res = await AO.write({
            process: Constants.Profiles,
            action: Constants.Actions.CreateServer,
            tags: {
                Name: params.name,
                Logo: params.logo
            },
            ao: this.ao,
            signer: this.signer
        });
        if (res.tags?.Status === "200" && res.tags?.ServerAnchor) {
            const server = await this.anchorToServer(res.tags.ServerAnchor);
            return server;
        }
        throw new Error('Failed to create server');
    }
    async getBot(botProcess) {
        const res = await AO.read({
            process: Constants.Profiles,
            action: Constants.Actions.BotInfo,
            tags: { BotProcess: botProcess },
            ao: this.ao
        });
        const data = JSON.parse(res.Data);
        return new Bot(data, this.ao, this.signer);
    }
    async anchorToBot(botAnchor) {
        const res = await AO.read({
            process: Constants.Profiles,
            action: Constants.Actions.AnchorToBot,
            tags: { BotAnchor: botAnchor },
            ao: this.ao
        });
        const data = JSON.parse(res.Data);
        return new Bot(data, this.ao, this.signer);
    }
    async createBot(params) {
        const res = await AO.write({
            process: Constants.Profiles,
            action: Constants.Actions.CreateBot,
            tags: {
                BotName: params.botName,
                BotPfp: params.botPfp,
                BotPublic: params.publicBot ? "true" : "false"
            },
            ao: this.ao,
            signer: this.signer
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
        const res = await AO.write({
            process: Constants.Profiles,
            action: Constants.Actions.AddBot,
            tags: {
                BotProcess: params.botProcess,
                ServerId: params.serverId
            },
            ao: this.ao,
            signer: this.signer
        });
        return res.tags?.Status === "200";
    }
    async removeBot(params) {
        const res = await AO.write({
            process: params.serverId,
            action: Constants.Actions.RemoveBot,
            tags: {
                BotProcess: params.botProcess
            },
            ao: this.ao,
            signer: this.signer
        });
        return res.tags?.Status === "200";
    }
}
