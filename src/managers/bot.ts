import { ConnectionManager } from "../connection-manager";
import { Constants } from "../utils/constants";
import { loggedAction } from "../utils/logger";
import type { Tag } from "../types/ao";

export interface Bot {
    public: boolean;
    subscribedServers?: Record<string, boolean>;
    joinedServers?: Record<string, boolean>;
    name: string;
    pfp?: string;
    description?: string;
    process: string;
    owner: string;
    version: string; // bot process code version
}

export class BotManager {
    constructor(private connectionManager: ConnectionManager) { }

    async createBot(params: { name: string; description?: string; source?: string; pfp?: string; publicBot?: boolean }): Promise<string | null> {
        return loggedAction('➕ creating bot', params, async () => {
            const start = Date.now();

            // Spawn a new process with bot metadata
            const tags: Tag[] = [
                { name: "Name", value: params.name },
                { name: "Owner", value: this.connectionManager.owner },
                { name: "Action", value: Constants.Actions.CreateBot },
                { name: "Public-Bot", value: (params.publicBot ?? true).toString() }
            ];

            if (params.description) tags.push({ name: "Description", value: params.description });
            if (params.pfp) tags.push({ name: "Pfp", value: params.pfp });

            const botId = await this.connectionManager.spawn({ tags });
            if (!botId) {
                throw new Error("Failed to spawn bot process");
            }

            // Wait for sources to be available (retry up to 3 times)
            for (let i = 0; i < 3; i++) {
                if (this.connectionManager.sources?.Bot?.Lua) break;
                await new Promise(resolve => setTimeout(resolve, 1000 * i));
            }

            if (!this.connectionManager.sources?.Bot?.Lua) {
                // If bot source is not available, still try to register the bot
                // The bot process will use default behavior
                console.warn("Bot source code not available, using default bot behavior");
            } else {
                // Replace template placeholders in the bot source code
                let botSourceCode = this.connectionManager.sources.Bot.Lua;

                // Replace placeholders
                botSourceCode = botSourceCode.replace('{NAME}', params.name);
                botSourceCode = botSourceCode.replace('{DESCRIPTION}', params.description || '');
                botSourceCode = botSourceCode.replace('{PFP}', params.pfp || '');
                botSourceCode = botSourceCode.replace('{PUBLIC}', (params.publicBot ?? true).toString());

                // Load bot source code into the spawned process
                const botRes = await this.connectionManager.execLua({
                    processId: botId,
                    code: botSourceCode,
                    tags: []
                });

                // Wait for bot to initialize
                await new Promise(resolve => setTimeout(resolve, 2000));
            }

            // Register bot with Subspace process
            const res = await this.connectionManager.sendMessage({
                processId: Constants.Subspace,
                tags: [
                    { name: "Action", value: Constants.Actions.CreateBot },
                    { name: "Bot-Process", value: botId },
                    { name: "Name", value: params.name },
                    { name: "Public-Bot", value: (params.publicBot ?? true).toString() },
                    { name: "Pfp", value: params.pfp || "" }
                ]
            });

            const msg = this.connectionManager.parseOutput(res, {
                hasMatchingTag: "Action",
                hasMatchingTagValue: "Create-Bot-Response"
            });
            if (!msg || msg.Tags.Status !== "200") {
                throw new Error(msg?.Data || "Failed to create bot");
            }

            // Return the bot process ID from the response
            return msg.Tags.BotProcess || botId;
        });
    }

    async getBot(botId: string): Promise<Bot | null> {
        return loggedAction('🔍 getting bot info', { botId }, async () => {
            // Get bot's own state from its process
            let botprocessBotData: any | null = null;
            try {
                botprocessBotData = await this.connectionManager.hashpathGET<any>(`${botId}~process@1.0/now/cache/bot/~json@1.0/serialize`)
            } catch (_) {
                botprocessBotData = null;
            }

            // Get bot metadata from Subspace process
            let subspaceBotData: any | null = null;
            try {
                subspaceBotData = await this.connectionManager.hashpathGET<any>(`${Constants.Subspace}~process@1.0/now/cache/subspace/bots/${botId}/~json@1.0/serialize`)
            } catch (_) {
                subspaceBotData = null;
            }

            // @ts-ignore
            const botInfo: Bot = {};

            if (botprocessBotData) {
                botInfo.public = subspaceBotData.public || false;
                botInfo.joinedServers = subspaceBotData.joinedServers || {};
                botInfo.name = subspaceBotData?.name || 'Unknown Bot';
                botInfo.pfp = subspaceBotData?.pfp;
                botInfo.description = subspaceBotData?.description;
                botInfo.process = botId;
            }
            if (subspaceBotData) {
                botInfo.subscribedServers = botprocessBotData.subscribedServers || {};
                botInfo.version = botprocessBotData.version;
                botInfo.owner = botprocessBotData.owner;
            }
            return botInfo;
        });
    }


    async getAllBots(): Promise<Record<string, Bot>> {
        return loggedAction('🔍 getting all bots', {}, async () => {
            // Get all bots metadata from Subspace process
            let botsMetadata: Record<string, any> | null = null;
            try {
                botsMetadata = await this.connectionManager.hashpathGET<Record<string, any>>(`${Constants.Subspace}~process@1.0/now/cache/subspace/bots/~json@1.0/serialize`)
            } catch (_) {
                botsMetadata = null;
            }

            const result: Record<string, Bot> = {};
            if (botsMetadata) {
                // For each bot in metadata, fetch its own state
                for (const [botId, metadata] of Object.entries(botsMetadata)) {
                    if (!metadata) continue;

                    // Get bot's own state
                    let botState: any | null = null;
                    try {
                        botState = await this.connectionManager.hashpathGET<any>(`${botId}~process@1.0/now/cache/bot/~json@1.0/serialize`)
                    } catch (_) {
                        botState = null;
                    }

                    if (botState) {
                        result[botId] = {
                            public: botState.public || false,
                            subscribedServers: botState.subscribedServers || {},
                            joinedServers: botState.joinedServers || {},
                            name: metadata.name || 'Unknown Bot',
                            pfp: metadata.pfp,
                            description: metadata.description,
                            process: botId,
                            owner: metadata.owner || botState.owner || '',
                            version: botState.version || 'unknown',
                        };
                    }
                }
            }

            return result;
        });
    }

    async getBotsByOwner(ownerId: string): Promise<Bot[]> {
        return loggedAction('🔍 getting bots by owner', { ownerId }, async () => {
            const allBots = await this.getAllBots();
            return Object.values(allBots).filter(bot => bot.owner === ownerId);
        });
    }

    async addBotToServer(params: { serverId: string; botId: string; permissions?: any }): Promise<boolean> {
        return loggedAction('➕ adding bot to server', params, async () => {
            const tags: Tag[] = [
                { name: "Action", value: Constants.Actions.AddBot },
                { name: "BotProcess", value: params.botId }
            ];

            if (params.permissions) {
                tags.push({ name: "Permissions", value: JSON.stringify(params.permissions) });
            }

            const res = await this.connectionManager.sendMessage({
                processId: params.serverId,
                tags
            });

            const data = this.connectionManager.parseOutput(res);
            return data?.success === true;
        });
    }

    async removeBotFromServer(params: { serverId: string; botId: string }): Promise<boolean> {
        return loggedAction('🗑️ removing bot from server', params, async () => {
            const res = await this.connectionManager.sendMessage({
                processId: params.serverId,
                tags: [
                    { name: "Action", value: Constants.Actions.RemoveBot },
                    { name: "BotProcess", value: params.botId }
                ]
            });

            const data = this.connectionManager.parseOutput(res);
            return data?.success === true;
        });
    }

    async subscribeBotToChannel(params: { botId: string; serverId: string; channelId: string }): Promise<boolean> {
        return loggedAction('🔔 subscribing bot to channel', params, async () => {
            const res = await this.connectionManager.sendMessage({
                processId: params.serverId,
                tags: [
                    { name: "Action", value: Constants.Actions.Subscribe },
                    { name: "BotProcess", value: params.botId },
                    { name: "Channel-Id", value: params.channelId }
                ]
            });

            const data = this.connectionManager.parseOutput(res);
            return data?.success === true;
        });
    }

    async updateBot(botId: string, params: { name?: string; description?: string; pfp?: string; publicBot?: boolean }): Promise<boolean> {
        return loggedAction('✏️ updating bot', { botId, ...params }, async () => {
            const res = await this.connectionManager.sendMessage({
                processId: Constants.Subspace,
                tags: [
                    { name: "Action", value: "Update-Bot" },
                    { name: "Bot-Process", value: botId },
                    { name: "Name", value: params.name || "" },
                    { name: "Description", value: params.description || "" },
                    { name: "Pfp", value: params.pfp || "" },
                    { name: "Public-Bot", value: params.publicBot?.toString() || "" }
                ]
            });

            const data = this.connectionManager.parseOutput(res, { hasMatchingTag: "Action", hasMatchingTagValue: "Update-Bot-Response" });

            return data?.Tags?.Status === "200";
        });
    }

    async updateBotSource(botId: string, source: string): Promise<boolean> {
        return loggedAction('✏️ updating bot source', { botId, sourceLength: source.length }, async () => {
            const res = await this.connectionManager.execLua({
                processId: botId,
                code: source,
                tags: [{ name: "Action", value: "UpdateSource" }]
            });

            const data = this.connectionManager.parseOutput(res);
            return data?.success !== false; // Consider success if no explicit failure
        });
    }

    async deleteBot(botId: string): Promise<boolean> {
        return loggedAction('🗑️ deleting bot', { botId }, async () => {
            // First remove bot from all servers
            const bot = await this.getBot(botId);
            if (bot) {
                for (const serverId of Object.keys(bot.joinedServers)) {
                    try {
                        await this.removeBotFromServer({ serverId, botId });
                    } catch (error) {
                        console.warn(`Failed to remove bot from server ${serverId}:`, error);
                    }
                }
            }

            // Send delete message to Subspace process
            const res = await this.connectionManager.sendMessage({
                processId: Constants.Subspace,
                tags: [
                    { name: "Action", value: "Delete-Bot" },
                    { name: "BotProcess", value: botId }
                ]
            });

            const data = this.connectionManager.parseOutput(res);
            return data?.success === true;
        });
    }

    async anchorToBot(anchorId: string): Promise<Bot | null> {
        return loggedAction('⚓ anchoring to bot', { anchorId }, async () => {
            const res = await this.connectionManager.dryrun({
                processId: Constants.Subspace,
                tags: [
                    { name: "Action", value: Constants.Actions.AnchorToBot },
                    { name: "Anchor-Id", value: anchorId }
                ]
            });

            const data = this.connectionManager.parseOutput(res);
            return data ? data as Bot : null;
        });
    }
} 