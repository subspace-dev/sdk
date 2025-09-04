import { IBot } from "../types/subspace";

export class BotManager {
    static async getBot(id: string): Promise<IBot> {
        throw new Error("Not implemented");
    }
}