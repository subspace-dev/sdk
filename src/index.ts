import { AO } from "./utils/ao";
import { Constants } from "./utils/constants";

interface SubspaceOptions {
    GATEWAY_URL?: string;
    HB_URL?: string;
    signer?: any;
    address?: string;
    PROCESS?: string;
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
    public static subspaceProcess: string;


    static async init(options: SubspaceOptions = {}) {
        // Force clear any existing connection
        this.ao_ = null;
        this.initialized = false;
        this.subspaceProcess = options.PROCESS || Constants.subspaceProcess;

        this.ao_ = new AO({
            GATEWAY_URL: options.GATEWAY_URL,
            HB_URL: options.HB_URL,
            signer: options.signer,
            address: options.address,
        });
        this.address = options.address
        this.initialized = false;
        try {
            await this.getSources()
            this.initialized = true;
            Utils.log({ type: "success", label: "Subspace initialized", data: options })
        } catch (error) {
            Utils.log({ type: "error", label: "Subspace initialization failed", data: error })
            this.initialized = false;
        }
    }

    public static ao({ noCheck = false }: { noCheck?: boolean } = { noCheck: false }) {
        if (!this.initialized && !noCheck) {
            throw new Error("Subspace not yet initialized")
        }
        return this.ao_;
    }

    public static clear() {
        this.ao_ = null;
        this.initialized = false;
        this.address = null;
        Utils.log({ type: "debug", label: "Subspace cleared", data: "Connection and state cleared" })
    }

    public static async getSources() {
        try {
            if (this.fetchingSources) return;
            this.fetchingSources = true;
            const s = await this.ao({ noCheck: true }).read<Sources>({ path: `/${this.subspaceProcess}/now/sources` })

            const promises = [
                fetch(`${this.ao({ noCheck: true }).gatewayUrl}/${s.bot.id}`),
                fetch(`${this.ao({ noCheck: true }).gatewayUrl}/${s.dm.id}`),
                fetch(`${this.ao({ noCheck: true }).gatewayUrl}/${s.server.id}`),
            ]
            const [bot, dm, server] = await Promise.all(promises)

            s.bot.lua = await bot.text()
            s.dm.lua = await dm.text()
            s.server.lua = await server.text()

            this.sources = s
            this.fetchingSources = false;
            return s
        } catch (error) {
            Utils.log({ type: "error", label: "Failed to fetch sources", data: error })
            this.fetchingSources = false;
            this.initialized = false;
            throw error
        }
    }
}


export { SubspaceProfiles } from "./managers/profiles"
export { SubspaceServers } from "./managers/server"
export { SubspaceValidation, ValidationError } from "./utils/validation"

// Export Inputs namespace
// export { Inputs } from "./types"

import { log, withDuration } from "./utils/logger"
const Utils = { log, withDuration }
export { Utils }

export { EPermissions } from "./types/subspace"