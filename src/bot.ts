
import { AO } from "./utils/ao";


export class Bot {
    private ao: AO
    botProcess: string
    botName: string
    botPfp: string
    botPublic: boolean
    userId: string
    totalServers?: number

    constructor(data: any, ao: AO) {
        this.ao = ao
        this.botProcess = data.botProcess
        this.botName = data.botName
        this.botPfp = data.botPfp
        this.botPublic = data.botPublic
        this.userId = data.userId
        this.totalServers = data.totalServers
    }
}