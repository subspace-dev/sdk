import { AoClient, ReadOptions, TagsKV, WriteOptions, WriteResult } from "../types/ao";
export declare class AO {
    static ao: AoClient;
    constructor();
    static read(params: ReadOptions): Promise<TagsKV>;
    static write(params: WriteOptions): Promise<WriteResult>;
}
