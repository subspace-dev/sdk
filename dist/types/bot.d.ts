import { AO } from "./utils/ao";
export declare class Bot {
    private ao;
    botProcess: string;
    botName: string;
    botPfp: string;
    botPublic: boolean;
    userId: string;
    totalServers?: number;
    constructor(data: any, ao: AO);
}
