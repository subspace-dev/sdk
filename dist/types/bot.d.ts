import { AoClient, AoSigner } from "./types/ao";
import { IBotReadOnly } from "./types/subspace";
export declare class Bot implements IBotReadOnly {
    private ao;
    private signer?;
    botProcess: string;
    botName: string;
    botPfp: string;
    botPublic: boolean;
    userId: string;
    totalServers?: number;
    constructor(data: IBotReadOnly, ao: AoClient, signer?: AoSigner);
}
