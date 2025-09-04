import { AO } from "./utils/ao";
import { Constants } from "./utils/constants";

interface SubspaceOptions {
    GATEWAY_URL?: string;
    HB_URL?: string;
    signer?: any;
    address?: string;
}

interface Sources {
    bot: {
        id: string;
        version: string;
        lua?: string;
    };
    dm: {
        id: string;
        version: string;
        lua?: string;
    };
    server: {
        id: string;
        version: string;
        lua?: string;
    };
}

export class Subspace {
    private static ao_: AO;
    public static address: string;
    public static initialized = false;
    private static fetchingSources = false;
    public static sources: Sources;


    static async init(options: SubspaceOptions = {}) {
        this.ao_ = new AO({
            GATEWAY_URL: options.GATEWAY_URL,
            HB_URL: options.HB_URL,
            signer: options.signer,
            address: options.address
        });
        this.address = options.address
        this.initialized = true;
        try {
            await this.getSources()
        } catch (error) {
            console.error("Failed to fetch sources:", error)
        }
    }

    public static ao() {
        if (!this.initialized) {
            throw new Error("Subspace not yet initialized")
        }
        return this.ao_;
    }

    public static async getSources() {
        try {
            if (this.fetchingSources) return;
            this.fetchingSources = true;
            const s = await this.ao().read<Sources>({ path: `/${Constants.subspaceProcess}/now/sources` })

            const promises = [
                fetch(`${this.ao().gatewayUrl}/${s.bot.id}`),
                fetch(`${this.ao().gatewayUrl}/${s.dm.id}`),
                fetch(`${this.ao().gatewayUrl}/${s.server.id}`),
            ]
            const [bot, dm, server] = await Promise.all(promises)

            s.bot.lua = await bot.text()
            s.dm.lua = await dm.text()
            s.server.lua = await server.text()

            this.sources = s
            this.fetchingSources = false;
            return s
        } catch (error) {
            console.error("Failed to fetch sources:", error)
            this.fetchingSources = false;
            return null
        }
    }
}


export { SubspaceProfiles } from "./managers/profiles"
export { SubspaceServers } from "./managers/server"

import { log, withDuration } from "./utils/logger"
const Utils = { log, withDuration }
export { Utils }