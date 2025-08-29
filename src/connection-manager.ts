import { connect, createDataItemSigner } from "@permaweb/aoconnect"
import { Constants } from "./utils/constants";
import { loggedAction } from "./utils/logger";
import { ArweaveSigner, createData, DataItem } from "@dha-team/arbundles"
import type { JWKInterface } from "arweave/web/lib/wallet";
import type { Tag, MessageResult, AoSigner } from "./types/ao";

export interface ConnectionConfig {
    GATEWAY_URL?: string;
    HYPERBEAM_URL?: string;
    signer?: AoSigner;
    jwk?: JWKInterface;
    owner?: string;
}

export interface Sources {
    server: {
        id: string;
        version: string;
        lua?: string;
    }
    dm: {
        id: string;
        version: string;
        lua?: string;
    }
    bot: {
        id: string;
        version: string;
        lua?: string;
    }
}

export class ConnectionManager {
    ao: any
    jwk: JWKInterface | null = null
    signer: AoSigner | null = null
    owner: string
    hyperbeamUrl: string
    gatewayUrl: string
    sources: Sources

    constructor(config: ConnectionConfig = {}) {
        this.hyperbeamUrl = config.HYPERBEAM_URL || "https://hb.arnode.asia"
        this.gatewayUrl = config.GATEWAY_URL || 'https://arnode.asia'
        this.owner = config.owner || ""
        this.jwk = config.jwk || null
        this.signer = config.signer || null

        this.ao = connect({
            MODE: "mainnet",
            URL: this.hyperbeamUrl,
            GATEWAY_URL: this.gatewayUrl,
            signer: this.signer,
            device: "process@1.0",
        })

        this.refreshSources()
    }

    async hashpathGET<T>(path: string): Promise<T> {
        const maxRetries = 3
        let retries = 0
        while (retries < maxRetries) {
            try {
                const res = await fetch(`${this.hyperbeamUrl}/${path}`)
                return ConnectionManager.sanitizeHyperbeamResult(await res.json()) as T
            } catch (e) {
                retries++
                await new Promise(resolve => setTimeout(resolve, 1000 * (retries + 1)))
            }
        }
        throw new Error(`Failed to fetch after ${maxRetries} retries`)
    }

    async operator(): Promise<string> {
        const scheduler = (await (await fetch(this.hyperbeamUrl + '/~meta@1.0/info/address')).text()).trim()
        return scheduler
    }

    async readState<T>({ processId, path }: { processId: string, path?: string }): Promise<T> {
        let hashpath = `${this.hyperbeamUrl}/${processId}~process@1.0`
        if (path) {
            hashpath += `/${path.startsWith("/") ? path.slice(1) : path}`
        } else {
            hashpath += "/now/cache"
        }
        hashpath += "/~json@1.0/serialize"

        const res = await fetch(hashpath)
        return (await res.json()) as T
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
            'referer',
            'cdn-loop',
            'cf-connecting-ip',
            'cf-ipcountry',
            'cf-ray',
            'cf-visitor',
            'remote-host',
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
        if (config.GATEWAY_URL) this.gatewayUrl = config.GATEWAY_URL
        if (config.HYPERBEAM_URL) this.hyperbeamUrl = config.HYPERBEAM_URL
        if (config.owner) this.owner = config.owner
        if (config.jwk) this.jwk = config.jwk
        if (config.signer) this.signer = config.signer

        this.ao = connect({
            MODE: "mainnet",
            URL: this.hyperbeamUrl,
            GATEWAY_URL: this.gatewayUrl,
            signer: this.signer,
            device: "process@1.0",
        })
    }

    public async refreshSources() {
        // fetch sources from Subspace process
        loggedAction('🔍 fetching sources', {}, async () => {
            const hashpath = `${this.hyperbeamUrl}/${Constants.Subspace}/now/sources/~json@1.0/serialize`
            const res = await fetch(hashpath)
            const resJson = await res.json() as Sources

            // const sources = this.parseOutput(res, { hasMatchingTag: "Action", hasMatchingTagValue: "Sources-Response" })
            if (resJson) {
                this.sources = {
                    server: resJson.server,
                    dm: resJson.dm,
                    bot: resJson.bot,
                }
                // fetch source src from arweave.net/Id
                const fetchPromises = Object.values(this.sources).map(async (source) => {
                    if (source.id) {
                        const src = await fetch(`${this.gatewayUrl}/${source.id}`).then(res => res.text())
                        source.lua = src
                    }
                })
                await Promise.all(fetchPromises)
            }
            return this.sources
        })
    }

    getAo() { return this.ao }
    getHyperbeamUrl() { return this.hyperbeamUrl }
    getGatewayUrl() { return this.gatewayUrl }
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

    async spawn({ tags, data, module_ }: { tags: Tag[], data?: any, module_?: string }): Promise<string> {
        return loggedAction('🚀 spawning process', { tags: tags.map(t => `${t.name}=${t.value}`).join(', ') }, async () => {
            const params: any = {
                path: '/push',
                method: 'POST',
                type: 'Process',
                device: 'process@1.0',
                'scheduler-device': 'scheduler@1.0',
                'push-device': 'push@1.0',
                'execution-device': 'lua@5.3a',
                'data-protocol': 'ao',
                variant: 'ao.N.1',
                Random: Math.random().toString(),
                Authority: await this.operator() + ',' + Constants.Authority,
                'signing-format': 'ANS-104',
                Module: module_ || Constants.Module,
                scheduler: await this.operator(),
            }

            // Add custom tags as properties
            if (tags) {
                tags.forEach(tag => {
                    params[tag.name] = tag.value
                })
            }

            // Add data if provided
            if (data) {
                params.data = data
            }

            const res = await this.ao.request(params)
            const spawnResJson = await res
            const process = spawnResJson.process

            // delay 1s to ensure process is ready
            await new Promise(resolve => setTimeout(resolve, 1000))

            // Start live monitoring and wait for first result
            await this.startLiveMonitoringAndActivate(process)

            return process
        });
    }

    async execLua({ processId, code, tags }: { processId: string, code: string, tags: Tag[] }): Promise<MessageResult & { id: string }> {
        return loggedAction('⚙️ executing lua', { processId, codeLength: code.length }, async () => {
            return this.sendMessage({
                processId,
                data: code,
                tags: [
                    ...tags,
                    { name: "Action", value: "Eval" }
                ]
            })
        });
    }

    async sendMessage({ processId, data, tags, noResult = false }: { processId: string, data?: string, tags: Tag[], noResult?: boolean }): Promise<MessageResult & { id: string }> {
        const params: any = {
            path: `/${processId}~process@1.0/push/serialize~json@1.0`,
            method: 'POST',
            type: 'Message',
            'data-protocol': 'ao',
            variant: 'ao.N.1',
            target: processId,
            'signing-format': 'ANS-104',
        }

        // Add tags as properties
        if (tags) {
            tags.forEach(tag => {
                params[tag.name] = tag.value
            })
        }

        // Add data if provided
        if (data) {
            params.data = data
        }

        const res = await this.ao.request(params)
        const result = await JSON.parse(res.body)
        return { id: result.id || result.messageId, ...result }
    }

    async dryrun({ processId, data, tags }: { processId: string, data?: string, tags: Tag[] }): Promise<MessageResult> {
        // In hyperbeam mode, use read operation for dryrun-like functionality
        // This is a simplified approach - in practice you might want to use a different endpoint
        throw new Error("Dryrun not supported in hyperbeam mode. Use readState instead for state queries.");
    }

    async runLua({ processId, code }: { processId: string, code: string }): Promise<any> {
        return loggedAction('⚙️ running lua code', { processId, codeLength: code.length }, async () => {
            return this.sendMessage({
                processId,
                tags: [
                    { name: "Action", value: "Eval" }
                ],
                data: code
            })
        });
    }

    private async startLiveMonitoringAndActivate(processId: string): Promise<void> {
        return new Promise((resolve, reject) => {
            let isResolved = false
            const timeout = setTimeout(() => {
                if (!isResolved) {
                    isResolved = true
                    reject(new Error('Process activation timeout'))
                }
            }, 30000) // 30 second timeout

            const stopMonitoring = this.startLiveMonitoring(processId, {
                intervalMs: 1000,
                onResult: async (result) => {
                    if (!isResolved) {
                        isResolved = true
                        clearTimeout(timeout)
                        stopMonitoring()

                        // Send initial activation message
                        try {
                            await this.sendMessage({
                                processId,
                                tags: [{ name: 'Action', value: 'Eval' }],
                                data: "require('.process')._version",
                                noResult: true
                            })
                        } catch (e) {
                            console.warn('Process activation message failed:', e)
                        }

                        resolve()
                    }
                }
            })
        })
    }

    private startLiveMonitoring(
        processId: string,
        options: {
            intervalMs?: number
            onResult?: (result: { slot: number; output?: string; error?: string; hasNewData: boolean; hasPrint: boolean }) => void
            lastKnownSlot?: number
        } = {}
    ): () => void {
        const {
            intervalMs = 2000,
            onResult,
        } = options

        let lastSlot: number | undefined = options.lastKnownSlot
        let isRunning = true

        const checkForUpdates = async () => {
            if (!isRunning) return

            try {
                // Get the current slot
                const currentSlotPath = `${processId}~process@1.0/slot/current/body`
                const currentSlot = await this.readState<{ body: number }>({
                    processId,
                    path: 'slot/current/body'
                })
                const currentSlotNumber = currentSlot.body

                // Determine which slot to check
                const slotToCheck = lastSlot ? lastSlot + 1 : currentSlotNumber

                // If we're already at the latest slot, no new data
                if (slotToCheck > currentSlotNumber) {
                    // Schedule next check
                    if (isRunning) {
                        setTimeout(checkForUpdates, intervalMs)
                    }
                    return
                }

                // Fetch computation results for the slot
                const results = await this.readState<any>({
                    processId,
                    path: `compute&slot=${slotToCheck}/results`
                })

                // Check if results have print output
                const hasPrint = !!(results?.output?.print)

                let output: string | undefined
                let error: string | undefined
                let hasNewData = false

                if (results && hasPrint) {
                    if (this.isExecutionError(results)) {
                        error = this.parseMonitoringOutput(results)
                        output = results.output.data
                    } else {
                        output = this.parseMonitoringOutput(results)
                    }
                    hasNewData = !!(output || error)
                }

                const result = {
                    slot: slotToCheck,
                    output,
                    error,
                    hasNewData,
                    hasPrint
                }

                // Update last slot regardless of whether there's new data
                lastSlot = slotToCheck

                // Only call handler if there's new data with print output
                if (hasNewData && hasPrint && onResult) {
                    onResult(result)
                }

            } catch (error) {
                console.error('Error in live monitoring:', error)
            }

            // Schedule next check
            if (isRunning) {
                setTimeout(checkForUpdates, intervalMs)
            }
        }

        // Start monitoring
        checkForUpdates()

        // Return stop function
        return () => {
            isRunning = false
        }
    }

    private isExecutionError(results: any): boolean {
        return results?.output?.data?.includes('error') ||
            results?.output?.data?.includes('Error') ||
            results?.error
    }

    private parseMonitoringOutput(results: any): string {
        if (results?.output?.print) {
            return results.output.print
        }
        if (results?.output?.data) {
            return results.output.data
        }
        return ''
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