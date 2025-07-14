import { ConnectionManager, ConnectionConfig } from './connection-manager';
import { UserManager } from './managers/user';
import { ServerManager } from './managers/server';
import { BotManager } from './managers/bot';
export type { Profile, Notification, Friend, DMMessage, DMResponse } from './managers/user';
export type { Server, Member, Channel, Category, Role, Message, MessagesResponse } from './managers/server';
export type { Bot, BotInfo } from './managers/bot';
export type { Tag, MessageResult, AoSigner } from './types/ao';
export type { ConnectionConfig } from './connection-manager';
export declare class Subspace {
    connectionManager: ConnectionManager;
    user: UserManager;
    server: ServerManager;
    bot: BotManager;
    constructor(config?: ConnectionConfig);
    updateConfig(config: Partial<ConnectionConfig>): void;
    switchCu(): void;
    getConnectionInfo(): {
        cuUrl: string;
        owner: string;
        hasJwk: boolean;
        hasSigner: boolean;
    };
}
export { ConnectionManager } from './connection-manager';
export { UserManager } from './managers/user';
export { ServerManager } from './managers/server';
export { BotManager } from './managers/bot';
