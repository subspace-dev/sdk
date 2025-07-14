import { ConnectionManager } from './connection-manager';
import { UserManager } from './managers/user';
import { ServerManager } from './managers/server';
import { BotManager } from './managers/bot';
export class Subspace {
    connectionManager;
    user;
    server;
    bot;
    constructor(config = {}) {
        this.connectionManager = new ConnectionManager(config);
        this.user = new UserManager(this.connectionManager);
        this.server = new ServerManager(this.connectionManager);
        this.bot = new BotManager(this.connectionManager);
    }
    // Method to update connection configuration
    updateConfig(config) {
        this.connectionManager.updateConfig(config);
    }
    // Method to switch compute unit if needed
    switchCu() {
        this.connectionManager.switchCu();
    }
    // Convenience method for getting current connection info
    getConnectionInfo() {
        return {
            cuUrl: this.connectionManager.getCuUrl(),
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
