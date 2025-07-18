import { connect, createDataItemSigner } from "@permaweb/aoconnect"
import { Constants } from "./utils/constants";
import { ArweaveSigner, createData, DataItem } from "@dha-team/arbundles"
import type { JWKInterface } from "arweave/web/lib/wallet";
import type { Tag, MessageResult, AoSigner } from "./types/ao";

export interface ConnectionConfig {
    CU_URL?: string;
    GATEWAY_URL?: string;
    signer?: AoSigner;
    jwk?: JWKInterface;
    owner?: string;
}

export interface Sources {
    Server: {
        Id: string;
        Version: string;
        Lua?: string;
    }
    Dm: {
        Id: string;
        Version: string;
        Lua?: string;
    }
    Bot: {
        Id: string;
        Version: string;
        Lua?: string;
    }
}

export class ConnectionManager {
    ao: any
    jwk: JWKInterface | null = null
    signer: AoSigner | null = null
    owner: string
    cuUrl: string
    gatewayUrl: string
    sources: Sources

    constructor(config: ConnectionConfig = {}) {
        this.cuUrl = config.CU_URL || Constants.CuEndpoints[0] || 'https://cu.arnode.asia'
        this.gatewayUrl = config.GATEWAY_URL || 'https://arweave.net'
        this.owner = config.owner || ""
        this.jwk = config.jwk || null
        this.signer = config.signer || null

        this.ao = connect({
            MODE: "legacy",
            CU_URL: this.cuUrl,
            GATEWAY_URL: this.gatewayUrl,
        })

        // fetch sources from Subspace process
        this.dryrun({
            processId: Constants.Subspace,
            tags: [
                { name: "Action", value: "Sources" }
            ]
        }).then(async (res) => {
            const sources = this.parseOutput(res, { hasMatchingTag: "Action", hasMatchingTagValue: "Sources-Response" })
            if (sources && sources.Data) {
                const sourcesData = JSON.parse(sources.Data)
                this.sources = sourcesData as Sources
                // fetch source src from arweave.net/Id
                const fetchPromises = Object.values(this.sources).map(async (source) => {
                    if (source.Id) {
                        const src = await fetch(`${this.gatewayUrl}/${source.Id}`).then(res => res.text())
                        source.Lua = src
                    }
                })
                await Promise.all(fetchPromises)
            }
        })
    }

    updateConfig(config: Partial<ConnectionConfig>) {

        if (config.CU_URL) this.cuUrl = config.CU_URL
        if (config.GATEWAY_URL) this.gatewayUrl = config.GATEWAY_URL
        if (config.owner) this.owner = config.owner
        if (config.jwk) this.jwk = config.jwk
        if (config.signer) this.signer = config.signer

        this.ao = connect({
            MODE: "legacy",
            CU_URL: this.cuUrl,
            GATEWAY_URL: this.gatewayUrl,
        })
    }

    getAo() { return this.ao }
    getCuUrl() { return this.cuUrl }
    setJwk(jwk: JWKInterface) { this.jwk = jwk }

    getAoSigner() {
        if (this.signer) {
            return this.signer;
        }

        if (this.jwk) {
            const newSigner = async (create: any, createDataItem = (buf: any) => new DataItem(buf)) => {
                const dataItem = createDataItem(create)
                const signer = new ArweaveSigner(this.jwk!)
                await dataItem.sign(signer)
                return dataItem.getRaw()
            };
            return newSigner;
        }

        if (typeof window !== 'undefined' && window.arweaveWallet) {
            return createDataItemSigner(window.arweaveWallet);
        }

        throw new Error('No signer available. Provide either a signer, JWK, or ensure ArConnect is available.');
    }

    async spawn({ tags }: { tags: Tag[] }): Promise<string> {
        const start = Date.now();

        try {
            const args = {
                scheduler: Constants.Scheduler,
                module: Constants.Module,
                signer: this.getAoSigner(),
                tags: [
                    ...tags,
                    { name: "Authority", value: Constants.Authority }
                ]
            }
            const res: string = await this.ao.spawn(args)
            const duration = Date.now() - start;

            return res;
        } catch (error) {
            const duration = Date.now() - start;
            throw error;
        }
    }

    async execLua({ processId, code, tags }: { processId: string, code: string, tags: Tag[] }): Promise<MessageResult & { id: string }> {
        const start = Date.now();

        try {
            const args = {
                process: processId,
                data: code,
                signer: this.getAoSigner(),
                tags: [
                    ...tags,
                    { name: "Action", value: "Eval" }
                ],
            }
            const messageId: string = await this.ao.message(args)

            const res: MessageResult & { id: string } = await this.ao.result({
                process: processId,
                message: messageId,
            })

            const duration = Date.now() - start;
            const success = !res.Error;

            if (success) {
            } else {
            }

            res.id = messageId

            return res;
        } catch (error) {
            const duration = Date.now() - start;
            throw error;
        }
    }

    async sendMessage({ processId, data, tags }: { processId: string, data?: string, tags: Tag[] }): Promise<MessageResult> {
        const start = Date.now();

        try {
            const args = {
                process: processId,
                data: data || "",
                signer: this.getAoSigner(),
                tags,
            }
            const messageId: string = await this.ao.message(args)

            const res: MessageResult = await this.ao.result({
                process: processId,
                message: messageId,
            })

            const duration = Date.now() - start;
            const success = !res.Error;

            if (success) {
            } else {
            }

            return res;
        } catch (error) {
            const duration = Date.now() - start;
            throw error;
        }
    }

    async dryrun({ processId, data, tags }: { processId: string, data?: string, tags: Tag[] }): Promise<MessageResult> {
        const start = Date.now();

        try {
            // For dryrun requests, we need a valid owner/wallet address
            let owner = this.owner;

            // If no owner is set or empty, use a placeholder address for read-only operations
            if (!owner || owner.trim() === "") {
                owner = "placeholder-read-only-address";
            }
            const res: MessageResult = await this.ao.dryrun({
                process: processId,
                data: data || "",
                tags,
                Owner: owner,
            })

            const duration = Date.now() - start;
            const success = !res.Error;

            if (success) {
            } else {
            }

            return res;
        } catch (error) {
            const duration = Date.now() - start;
            throw error;
        }
    }

    parseOutput(res: MessageResult, { hasMatchingTag, hasMatchingTagValue }: { hasMatchingTag?: string, hasMatchingTagValue?: string } = {}) {

        if (res.Error) {
            throw new Error(`AO Error: ${res.Error}`)
        }

        if (res.Output && res.Output.data) {

            try {
                const parsed = JSON.parse(res.Output.data)
                return parsed
            } catch {
                return res.Output.data
            }
        }

        let returnMessage = null;
        if (res.Messages && res.Messages.length > 0) {

            if (hasMatchingTag || hasMatchingTagValue) {
                let found = false;
                for (const message of res.Messages) {
                    if (message.Tags && message.Tags.find((tag: Tag) => (tag.name == hasMatchingTag || tag.value == hasMatchingTagValue))) {
                        returnMessage = message;
                        found = true;
                        break;
                    }
                }
                if (!found) {
                    throw new Error(`No message found with the given tag or tag value: "${hasMatchingTag}" | "${hasMatchingTagValue}"`)
                }
            } else {
                if (res.Messages.length == 1) {
                    returnMessage = res.Messages[0];
                } else {
                    returnMessage = res.Messages;
                }
            }
        } else {
            throw new Error("No messages found")
        }

        return returnMessage;
    }
} 