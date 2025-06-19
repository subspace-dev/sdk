import { AoClient, AoSigner } from "./types/ao";
import { IBotReadOnly } from "./types/subspace";


export class Bot implements IBotReadOnly {
    private ao: AoClient
    private signer?: AoSigner
    botProcess: string
    botName: string
    botPfp: string
    botPublic: boolean
    userId: string
    totalServers?: number

    constructor(data: IBotReadOnly, ao: AoClient, signer?: AoSigner) {
        Object.assign(this, data)
        this.ao = ao
        this.signer = signer
    }
}