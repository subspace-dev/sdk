import { result, results, message, spawn, monitor, unmonitor, dryrun } from "@permaweb/aoconnect"

export type Tag = { name: string, value: string }
export type TagsKV = Record<string, string>

export type MessageResult = {
    Output: any;
    Messages: any[];
    Spawns: any[];
    Error?: any;
};

export type AoSigner = (args: {
    data: string | Buffer;
    tags?: Tag[];
    target?: string;
    anchor?: string;
}) => Promise<{ id: string; raw: ArrayBuffer } | null>;

// ------------- AO input types -------------

export type ReadOptions = {
    ao?: any;
    process: string;
    action?: string;
    tags?: TagsKV;
    data?: string;
    owner?: string;
    retries?: number;
}

export type WriteOptions = {
    ao?: any;
    process: string;
    action?: string;
    tags?: TagsKV;
    data?: string;
    signer?: AoSigner;
    retries?: number;
}

export type WriteResult = {
    id: string,
    tags?: TagsKV,
    data?: any
}