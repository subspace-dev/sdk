import { ConnectionManager } from "../connection-manager";
import { Constants } from "../utils/constants";
import { loggedAction } from "../utils/logger";
import type { Tag } from "../types/ao";

export interface Bot {
    botId: string;
    name: string;
    description?: string;
    ownerId: string;
    serverId?: string;
    permissions?: any;
    isActive?: boolean;
    createdAt?: number;
}

export interface BotInfo {
    botId: string;
    name: string;
    description?: string;
    version?: string;
    commands?: string[];
    events?: string[];
}

export class BotManager {
    constructor(private connectionManager: ConnectionManager) { }

    async createBot(params: { name: string; description?: string; source?: string }): Promise<string | null> {
        return loggedAction('➕ creating bot', params, async () => {
            const tags: Tag[] = [
                { name: "Action", value: Constants.Actions.CreateBot },
                { name: "Name", value: params.name }
            ];

            if (params.description) tags.push({ name: "Description", value: params.description });

            const botId = await this.connectionManager.spawn({ tags });
            if (!botId) throw new Error("Failed to spawn bot process");

            // Initialize bot with source code if provided
            if (params.source) {
                await this.connectionManager.execLua({
                    processId: botId,
                    code: params.source,
                    tags: [{ name: "Action", value: "Initialize" }]
                });
            }

            return botId;
        });
    }

    async getBot(botId: string): Promise<BotInfo | null> {
        return loggedAction('🔍 getting bot info', { botId }, async () => {
            const res = await this.connectionManager.dryrun({
                processId: botId,
                tags: [
                    { name: "Action", value: Constants.Actions.BotInfo }
                ]
            });

            const data = this.connectionManager.parseOutput(res);
            return data ? data as BotInfo : null;
        });
    }

    async addBotToServer(params: { serverId: string; botId: string; permissions?: any }): Promise<boolean> {
        return loggedAction('➕ adding bot to server', params, async () => {
            const tags: Tag[] = [
                { name: "Action", value: Constants.Actions.AddBot },
                { name: "BotId", value: params.botId }
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
                    { name: "BotId", value: params.botId }
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
                    { name: "BotId", value: params.botId },
                    { name: "ChannelId", value: params.channelId }
                ]
            });

            const data = this.connectionManager.parseOutput(res);
            return data?.success === true;
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

    async anchorToBot(anchorId: string): Promise<Bot | null> {
        return loggedAction('⚓ anchoring to bot', { anchorId }, async () => {
            const res = await this.connectionManager.dryrun({
                processId: Constants.Subspace,
                tags: [
                    { name: "Action", value: Constants.Actions.AnchorToBot },
                    { name: "AnchorId", value: anchorId }
                ]
            });

            const data = this.connectionManager.parseOutput(res);
            return data ? data as Bot : null;
        });
    }
} 