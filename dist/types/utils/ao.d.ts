import { AoSigner, ReadOptions, TagsKV, WriteOptions, WriteResult } from "../types/ao";
export declare class AO {
    readonly CU_URL: string;
    readonly GATEWAY_URL: string;
    readonly ao: any;
    private signer;
    readonly writable: boolean;
    readonly owner: string;
    constructor(params?: Partial<{
        CU_URL: string;
        GATEWAY_URL: string;
        signer: AoSigner;
        Owner: string;
    }>);
    read(params: ReadOptions): Promise<TagsKV>;
    write(params: WriteOptions): Promise<WriteResult>;
}
