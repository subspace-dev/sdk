import { ConnectionManager, ConnectionConfig } from './connection-manager';
import { UserManager } from './managers/user';
import { ServerManager } from './managers/server';
import { BotManager } from './managers/bot';

// Re-export types for convenience
export type { Profile, Notification, Friend, DMMessage, DMResponse } from './managers/user';
export type { Server, Member, Channel, Category, Role, Message, MessagesResponse } from './managers/server';
export type { Bot, BotInfo } from './managers/bot';
export type { Tag, MessageResult, AoSigner } from './types/ao';
export type { ConnectionConfig } from './connection-manager';

export class Subspace {
    connectionManager: ConnectionManager;
    user: UserManager;
    server: ServerManager;
    bot: BotManager;

    constructor(config: ConnectionConfig = {}) {
        this.connectionManager = new ConnectionManager(config);
        this.user = new UserManager(this.connectionManager);
        this.server = new ServerManager(this.connectionManager);
        this.bot = new BotManager(this.connectionManager);
    }

    // Method to update connection configuration
    updateConfig(config: Partial<ConnectionConfig>) {
        this.connectionManager.updateConfig(config);
    }

    // Convenience method for getting current connection info
    getConnectionInfo() {
        return {
            cuUrl: this.connectionManager.getCuUrl(),
            hyperbeamUrl: this.connectionManager.hyperbeamUrl,
            owner: this.connectionManager.owner,
            hasJwk: !!this.connectionManager.jwk,
            hasSigner: !!this.connectionManager.signer
        };
    }
}

// Export the managers directly for those who want to use them independently
export { ConnectionManager } from './connection-manager';
export { UserManager } from './managers/user';
export { ServerManager } from './managers/server';
export { BotManager } from './managers/bot';