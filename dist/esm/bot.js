export class Bot {
    ao;
    botProcess;
    botName;
    botPfp;
    botPublic;
    userId;
    totalServers;
    constructor(data, ao) {
        this.ao = ao;
        this.botProcess = data.botProcess;
        this.botName = data.botName;
        this.botPfp = data.botPfp;
        this.botPublic = data.botPublic;
        this.userId = data.userId;
        this.totalServers = data.totalServers;
    }
}
