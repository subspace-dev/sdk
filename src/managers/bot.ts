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

export interface ServerBot {
    userId: string;
    nickname?: string;
    roles: string[];
    joinedAt: string;
    approved: boolean;
    process: string;
    isBot: true;
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
            // let botprocessBotData: any | null = null;
            // try {
            //     botprocessBotData = await this.connectionManager.hashpathGET<any>(`${botId}~process@1.0/now/cache/bot/~json@1.0/serialize`)
            // } catch (_) {
            //     botprocessBotData = null;
            // }

            // Get bot metadata from Subspace process
            let subspaceBotData: any | null = null;
            try {
                subspaceBotData = await this.connectionManager.hashpathGET<any>(`${Constants.Subspace}~process@1.0/now/cache/subspace/bots/${botId}/~json@1.0/serialize`)
            } catch (_) {
                subspaceBotData = null;
            }

            console.log('subspaceBotData', subspaceBotData);

            // @ts-ignore
            const botInfo: Bot = {};

            // if (botprocessBotData) {
            //     botInfo.public = botprocessBotData.publicBot || false;
            //     botInfo.joinedServers = botprocessBotData.joinedServers || {};
            //     botInfo.subscribedServers = botprocessBotData.subscribedServers || {};
            //     botInfo.name = botprocessBotData?.name || 'Unknown Bot';
            //     botInfo.pfp = botprocessBotData?.pfp;
            //     botInfo.description = botprocessBotData?.description;
            //     botInfo.version = botprocessBotData?.version || 'unknown';
            //     botInfo.owner = botprocessBotData?.owner || '';
            //     botInfo.process = botId;
            // }
            if (subspaceBotData) {
                // Subspace data can override some fields if available
                botInfo.name = subspaceBotData.name || botInfo.name;
                botInfo.owner = subspaceBotData.owner || botInfo.owner;
                botInfo.pfp = subspaceBotData.pfp || botInfo.pfp;
                botInfo.description = subspaceBotData.description || botInfo.description;
                botInfo.process = botId;
                botInfo.public = subspaceBotData.public || false;
                botInfo.joinedServers = subspaceBotData.servers || {};
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
                            public: botState.publicBot || false,
                            subscribedServers: botState.subscribedServers || {},
                            joinedServers: botState.joinedServers || {},
                            name: botState.name || metadata.name || 'Unknown Bot',
                            pfp: botState.pfp || metadata.pfp,
                            description: botState.description || metadata.description,
                            process: botId,
                            owner: botState.owner || metadata.owner || '',
                            version: botState.version || 'unknown',
                        };
                    }
                }
            }

            return result;
        });
    }

    async getServerBot(serverId: string, botId: string): Promise<ServerBot | null> {
        return loggedAction('🔍 getting server bot', { serverId, botId }, async () => {
            const res = await this.connectionManager.hashpathGET<ServerBot>(`${serverId}~process@1.0/now/cache/server/serverinfo/bots/${botId}/~json@1.0/serialize`);
            return res;
        });
    }

    async getAllServerBots(serverId: string): Promise<Record<string, ServerBot>> {
        return loggedAction('🔍 getting all server bots', { serverId }, async () => {
            const res = await this.connectionManager.hashpathGET<Record<string, ServerBot>>(`${serverId}~process@1.0/now/cache/server/serverinfo/bots/~json@1.0/serialize`);
            return res;
        });
    }

    async getBotsByOwner(ownerId: string): Promise<Bot[]> {
        return loggedAction('🔍 getting bots by owner', { ownerId }, async () => {
            const allBots = await this.getAllBots();
            return Object.values(allBots).filter(bot => bot.owner === ownerId);
        });
    }

    async addBotToServer(params: { serverId: string; botId: string }): Promise<boolean> {
        return loggedAction('➕ adding bot to server', params, async () => {
            const tags: Tag[] = [
                { name: "Action", value: Constants.Actions.AddBot },
                { name: "Bot-Process", value: params.botId },
                { name: "Server-Id", value: params.serverId }
            ];

            const res = await this.connectionManager.sendMessage({
                processId: Constants.Subspace,
                tags
            });

            const msg = this.connectionManager.parseOutput(res, {
                hasMatchingTag: "Action",
                hasMatchingTagValue: "Add-Bot-Response"
            });

            // Check if the initial request was accepted (Status: 200)
            // The actual bot addition is an async multi-step process
            return msg?.Tags?.Status === "200";
        });
    }

    async removeBotFromServer(params: { serverId: string; botId: string }): Promise<boolean> {
        return loggedAction('🗑️ removing bot from server', params, async () => {
            const res = await this.connectionManager.sendMessage({
                processId: params.serverId,
                tags: [
                    { name: "Action", value: Constants.Actions.RemoveBot },
                    { name: "Bot-Process", value: params.botId }
                ]
            });

            const msg = this.connectionManager.parseOutput(res, {
                hasMatchingTag: "Action",
                hasMatchingTagValue: "Remove-Bot-Response"
            });

            return msg?.Tags?.Status === "200";
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

    // Polling status functions for bot addition process
    async getBotStatus(botId: string): Promise<{ joinedServers?: Record<string, boolean> } | null> {
        try {
            return await this.connectionManager.hashpathGET<any>(`${botId}/now/cache/bot/~json@1.0/serialize`);
        } catch (error) {
            console.warn(`Failed to get bot status for ${botId}:`, error);
            return null;
        }
    }

    async getServerBotStatus(serverId: string): Promise<Record<string, { approved: boolean; process: string }> | null> {
        try {
            return await this.connectionManager.hashpathGET<any>(`${serverId}~process@1.0/now/cache/server/serverinfo/bots/~json@1.0/serialize`);
        } catch (error) {
            console.warn(`Failed to get server bot status for ${serverId}:`, error);
            return null;
        }
    }

    async getSubspaceBotStatus(botId: string): Promise<{ servers?: Record<string, boolean> } | null> {
        try {
            return await this.connectionManager.hashpathGET<any>(`${Constants.Subspace}~process@1.0/now/cache/subspace/bots/${botId}/~json@1.0/serialize`);
        } catch (error) {
            console.warn(`Failed to get subspace bot status for ${botId}:`, error);
            return null;
        }
    }

    async pollBotAdditionStatus(
        params: { serverId: string; botId: string },
        onStatusUpdate?: (status: string, progress?: number) => void,
        maxRetries: number = 20,
        maxTotalTime: number = 60000 // 60 seconds max total time
    ): Promise<boolean> {
        return loggedAction('🔄 polling bot addition status', params, async () => {
            let retries = 0;
            const startTime = Date.now();

            // Define polling intervals (in milliseconds)
            // Start fast, then gradually increase interval to reduce cache load
            const getPollingInterval = (attempt: number): number => {
                if (attempt <= 3) return 1000;      // First 3 attempts: 1 second
                if (attempt <= 6) return 2000;      // Next 3 attempts: 2 seconds  
                if (attempt <= 10) return 3000;     // Next 4 attempts: 3 seconds  
                return 5000;                        // After that: 5 seconds
            };

            while (retries < maxRetries) {
                const elapsedTime = Date.now() - startTime;

                // Check if we've exceeded max total time
                if (elapsedTime > maxTotalTime) {
                    onStatusUpdate?.("Bot addition timed out, but may still be processing...", 90);
                    return false;
                }

                try {
                    retries++;
                    const progress = Math.min(25 + (retries / maxRetries) * 65, 90); // Progress from 25% to 90%
                    const nextInterval = getPollingInterval(retries);

                    onStatusUpdate?.(`Checking bot addition status... (attempt ${retries}/${maxRetries})`, progress);

                    // Poll all three endpoints using connection manager
                    const [botData, serverData, subspaceData] = await Promise.allSettled([
                        this.getBotStatus(params.botId),
                        this.getServerBotStatus(params.serverId),
                        this.getSubspaceBotStatus(params.botId)
                    ]);

                    // Extract results from settled promises
                    const botResult = botData.status === 'fulfilled' ? botData.value : null;
                    const serverResult = serverData.status === 'fulfilled' ? serverData.value : null;
                    const subspaceResult = subspaceData.status === 'fulfilled' ? subspaceData.value : null;

                    // Check completion conditions
                    const botJoined = botResult?.joinedServers?.[params.serverId] === true;
                    const serverApproved = serverResult?.[params.botId]?.approved === true;
                    const subspaceUpdated = subspaceResult?.servers?.[params.serverId] === true;

                    console.log('Bot addition polling status:', {
                        attempt: retries,
                        nextInterval: `${nextInterval}ms`,
                        elapsedTime: `${elapsedTime}ms`,
                        botJoined,
                        serverApproved,
                        subspaceUpdated,
                        botJoinedServers: botResult?.joinedServers,
                        serverBots: serverResult,
                        subspaceServers: subspaceResult?.servers
                    });

                    // All three conditions must be met for successful addition
                    if (botJoined && serverApproved && subspaceUpdated) {
                        onStatusUpdate?.("Bot successfully added to server!", 100);
                        return true;
                    }

                    // Provide more specific status updates based on what's completed
                    if (botJoined && serverApproved) {
                        onStatusUpdate?.("Almost done, finalizing in subspace registry...", progress);
                    } else if (botJoined) {
                        onStatusUpdate?.("Bot joined, waiting for server approval...", progress);
                    } else {
                        onStatusUpdate?.("Processing bot addition...", progress);
                    }

                    // Wait with increasing interval before next poll
                    await new Promise(resolve => setTimeout(resolve, nextInterval));

                } catch (error) {
                    console.error('Error polling bot addition status:', error);
                    // Use a shorter interval on errors to retry quickly
                    const errorInterval = Math.min(getPollingInterval(retries), 2000);
                    await new Promise(resolve => setTimeout(resolve, errorInterval));
                }
            }

            // If we've exhausted retries, return false
            onStatusUpdate?.("Bot addition timed out, but may still be processing...", 90);
            return false;
        });
    }
} 