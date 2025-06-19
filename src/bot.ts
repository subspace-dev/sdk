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
        this.ao = ao
        this.signer = signer
        this.botProcess = data.botProcess
        this.botName = data.botName
        this.botPfp = data.botPfp
        this.botPublic = data.botPublic
        this.userId = data.userId
        this.totalServers = data.totalServers
    }
}