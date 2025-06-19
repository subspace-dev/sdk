export class Bot {
    ao;
    signer;
    botProcess;
    botName;
    botPfp;
    botPublic;
    userId;
    totalServers;
    constructor(data, ao, signer) {
        this.ao = ao;
        this.signer = signer;
        this.botProcess = data.botProcess;
        this.botName = data.botName;
        this.botPfp = data.botPfp;
        this.botPublic = data.botPublic;
        this.userId = data.userId;
        this.totalServers = data.totalServers;
    }
}
