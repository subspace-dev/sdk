import { addBotParams, createBotParams, createServerParams, removeBotParams, SubspaceConfig, SubspaceConfigReadOnly } from "./types/inputs";
import { IBotReadOnly, IProfile, IProfileReadOnly, IServerReadOnly, ISubspace, ISubspaceReadOnly } from "./types/subspace";
import { AoClient } from "./types/ao";
import { Server, ServerReadOnly } from "./server";
import { Bot } from "./bot";
export declare class SubspaceClientReadOnly implements ISubspaceReadOnly {
    readonly CU_URL: string;
    readonly GATEWAY_URL: string;
    ao: AoClient;
    constructor(params: SubspaceConfigReadOnly);
    getProfile(userId: string): Promise<IProfileReadOnly | null>;
    getBulkProfiles(userIds: string[]): Promise<Array<IProfileReadOnly>>;
    anchorToServer(anchorId: string): Promise<IServerReadOnly>;
    getServer(serverId: string): Promise<ServerReadOnly | null>;
    getOriginalId(userId: string): Promise<string>;
    getBot(botProcess: string): Promise<IBotReadOnly | null>;
    anchorToBot(botAnchor: string): Promise<IBotReadOnly | null>;
}
export declare class SubspaceClient extends SubspaceClientReadOnly implements ISubspace {
    private readonly signer;
    constructor(params: SubspaceConfig);
    getProfile(userId?: string): Promise<IProfile | null>;
    getBulkProfiles(userIds: string[]): Promise<Array<IProfile>>;
    anchorToServer(anchorId: string): Promise<Server>;
    getServer(serverId: string): Promise<Server | null>;
    createProfile(): Promise<IProfile>;
    createServer(params: createServerParams): Promise<Server>;
    getBot(botProcess: string): Promise<Bot | null>;
    anchorToBot(botAnchor: string): Promise<Bot | null>;
    createBot(params: createBotParams): Promise<Bot>;
    addBot(params: addBotParams): Promise<boolean>;
    removeBot(params: removeBotParams): Promise<boolean>;
}
