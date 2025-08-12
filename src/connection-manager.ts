import { connect, createDataItemSigner } from "@permaweb/aoconnect"
import { Constants } from "./utils/constants";
import { loggedAction } from "./utils/logger";
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
    static hyperbeamUrl: string = "https://forward.computer"

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

        this.refreshSources()
    }

    static async hashpathGET<T>(path: string): Promise<T> {
        const maxRetries = 3
        let retries = 0
        while (retries < maxRetries) {
            try {
                const res = await fetch(`${ConnectionManager.hyperbeamUrl}/${path}`)
                return ConnectionManager.sanitizeHyperbeamResult(await res.json()) as T
            } catch (e) {
                retries++
                await new Promise(resolve => setTimeout(resolve, 1000 * (retries + 1)))
            }
        }
    }

    static sanitizeHyperbeamResult(input: Record<string, any>): any {
        const blockedKeys = new Set<string>([
            'accept',
            'accept-bundle',
            'accept-encoding',
            'accept-language',
            'connection',
            'device',
            'host',
            'method',
            'priority',
            'sec-ch-ua',
            'sec-ch-ua-mobile',
            'sec-ch-ua-platform',
            'sec-fetch-dest',
            'sec-fetch-mode',
            'sec-fetch-site',
            'sec-fetch-user',
            'sec-gpc',
            'upgrade-insecure-requests',
            'user-agent',
            'x-forwarded-for',
            'x-forwarded-proto',
            'x-real-ip',
            'origin',
            'referer'
        ])

        return Object.fromEntries(
            Object.entries(input).filter(([key]) => !blockedKeys.has(key))
        );
    }

    private static safeStringify(obj: any, maxLen: number = 2000): string {
        try {
            const str = JSON.stringify(obj, null, 2);
            if (typeof str === 'string' && str.length > maxLen) {
                return str.slice(0, maxLen) + '…';
            }
            return str;
        } catch (_) {
            try {
                return String(obj);
            } catch {
                return '[Unserializable]';
            }
        }
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

    public async refreshSources() {
        // fetch sources from Subspace process
        loggedAction('🔍 fetching sources', {}, async () => {
            const hashpath = `https://forward.computer/${Constants.Subspace}~process@1.0/now/cache/subspace/sources/~json@1.0/serialize`
            const res = await fetch(hashpath)
            const resJson = await res.json() as Sources

            // const sources = this.parseOutput(res, { hasMatchingTag: "Action", hasMatchingTagValue: "Sources-Response" })
            if (resJson) {
                this.sources = {
                    Server: resJson.Server,
                    Dm: resJson.Dm,
                    Bot: resJson.Bot,
                }
                // fetch source src from arweave.net/Id
                const fetchPromises = Object.values(this.sources).map(async (source) => {
                    if (source.Id) {
                        const src = await fetch(`${this.gatewayUrl}/${source.Id}`).then(res => res.text())
                        source.Lua = src
                    }
                })
                await Promise.all(fetchPromises)
            }
            return this.sources
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
        return loggedAction('🚀 spawning process', { tags: tags.map(t => `${t.name}=${t.value}`).join(', ') }, async () => {
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
            return res;
        });
    }

    async execLua({ processId, code, tags }: { processId: string, code: string, tags: Tag[] }): Promise<MessageResult & { id: string }> {
        return loggedAction('⚙️ executing lua', { processId, codeLength: code.length }, async () => {
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

            res.id = messageId
            return res;
        });
    }

    async sendMessage({ processId, data, tags }: { processId: string, data?: string, tags: Tag[] }): Promise<MessageResult & { id: string }> {

        const args = {
            process: processId,
            data: data || "",
            signer: this.getAoSigner(),
            tags,
        }

        console.log("🔧 SDK DEBUG: Sending message", {
            processId,
            data,
            tags
        })
        const messageId: string = await this.ao.message(args)

        const res: MessageResult & { id: string } = await this.ao.result({
            process: processId,
            message: messageId,
        })

        res.id = messageId;
        return res;

    }

    async dryrun({ processId, data, tags }: { processId: string, data?: string, tags: Tag[] }): Promise<MessageResult> {
        // For dryrun requests, we need a valid owner/wallet address
        const owner = this.owner;
        if (!owner || owner.trim() === "") {
            throw new Error("Owner address is required for dryrun operations");
        }
        const res: MessageResult = await this.ao.dryrun({
            process: processId,
            data: data || "",
            tags,
            Owner: owner,
        })

        return res;
    }

    parseOutput(res: MessageResult, { hasMatchingTag, hasMatchingTagValue }: { hasMatchingTag?: string, hasMatchingTagValue?: string } = {}) {

        if (res.Error) {
            // Provide a much more informative error message than "[object Object]"
            const base = typeof (res as any).Error === 'string'
                ? (res as any).Error
                : ConnectionManager.safeStringify((res as any).Error);

            const extra: Record<string, any> = {};
            if ((res as any).Output?.data) extra.output = (res as any).Output?.data;
            if ((res as any).Messages && Array.isArray((res as any).Messages)) {
                // Include only the first message's tags to avoid massive logs
                const first = (res as any).Messages[0];
                if (first?.Tags) extra.firstMessageTags = first.Tags;
            }

            const extraStr = Object.keys(extra).length
                ? ` | Details: ${ConnectionManager.safeStringify(extra)}`
                : '';

            const err = new Error(`AO Error: ${base}${extraStr}`);
            // Attach the full AO result for richer console inspection
            (err as any).ao = res;
            throw err;
        }

        if (res.Output && res.Output.data && !hasMatchingTag && !hasMatchingTagValue) {

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
                    if (message.Tags) {
                        const msg = message.Tags.find((tag: Tag) => {
                            if (hasMatchingTag && hasMatchingTagValue) {
                                return tag.name === hasMatchingTag && tag.value === hasMatchingTagValue;
                            } else {
                                return tag.name === hasMatchingTag || tag.value === hasMatchingTagValue;
                            }
                        })
                        if (msg) {
                            returnMessage = message;
                            found = true;
                            break;
                        }
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

        // translate from array of {name, value} to {name: value} object
        if (returnMessage && returnMessage.Tags) {
            const tagsObj: { [key: string]: string } = {};
            for (const tag of returnMessage.Tags) {
                tagsObj[tag.name] = tag.value;
            }
            returnMessage.Tags = tagsObj;
        }

        return returnMessage;
    }
} 