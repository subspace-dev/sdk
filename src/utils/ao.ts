import { connect } from "@permaweb/aoconnect";
import { AoClient, AoSigner, MessageResult, ReadOptions, Tag, TagsKV, WriteOptions, WriteResult } from "../types/ao";

export class AO {
    readonly CU_URL: string
    readonly GATEWAY_URL: string
    readonly ao: AoClient
    private signer: AoSigner
    readonly writable: boolean

    constructor(params: Partial<{ CU_URL: string, GATEWAY_URL: string, signer: AoSigner }> = {}) {
        const cuUrl = params?.CU_URL || this.CU_URL
        const gatewayUrl = params?.GATEWAY_URL || this.GATEWAY_URL

        this.ao = connect({ MODE: "legacy", CU_URL: cuUrl, GATEWAY_URL: gatewayUrl })
        this.signer = params.signer
        if (this.signer) {
            this.writable = true
        } else {
            this.writable = false
        }
    }

    async read(params: ReadOptions): Promise<TagsKV> {
        const dryrunInput = {
            process: params.process,
        }

        if (params.data) {
            dryrunInput['data'] = params.data
        }

        if (params.tags) {
            if (params.action) {
                params.tags['Action'] = params.action
            }
            dryrunInput['tags'] = Object.entries(params.tags).map(([key, value]) => ({ name: key, value: value.toString() }))
        } else {
            if (params.action) {
                dryrunInput['tags'] = [{ name: 'Action', value: params.action }]
            }
        }

        if (params.owner) {
            dryrunInput['Owner'] = params.owner
        }

        if (!params.retries) params.retries = 3

        let attempts = 0;
        let response: TagsKV | undefined = undefined
        let result: MessageResult | undefined = undefined

        while (attempts < params.retries) {
            try {
                result = await this.ao.dryrun(dryrunInput)
                break
            } catch (e) {
                console.error(e)
                attempts++
                await new Promise(resolve => setTimeout(resolve, 2 ** attempts * 1000))
                console.warn(`Retrying ${attempts + 1} of ${params.retries}`)
            }
        }

        if (!result) {
            throw new Error(`Read Failed\nInputs: ${JSON.stringify(params, null, 2)}`)
        }

        if (result.Error) {
            throw new Error(`Read Error\n${JSON.stringify(result, null, 2)}\nInputs:${JSON.stringify(params, null, 2)}`)
        }

        if (!result.Messages || result.Messages.length == 0) {
            console.dir(result, { depth: null })
            throw new Error(`Read Failed, No messages returned\nInputs: ${JSON.stringify(params, null, 2)}`)
        }

        if (result.Messages.length > 1) {
            throw new Error(`Read Failed, Multiple messages returned\n${JSON.stringify(result.Messages, null, 2)}\nInputs: ${JSON.stringify(params, null, 2)}`)
        }

        const msg = result.Messages[0]

        // Array to KeyValue
        const tags = (msg.Tags as Tag[]).reduce((acc, tag) => {
            acc[tag.name] = tag.value
            return acc
        }, {} as Record<string, string>)

        response = tags

        // Data will always be a json string
        if (msg.Data) {
            tags['Data'] = msg.Data
        }
        // try {
        //     const data = JSON.parse(msg.Data as string)
        //     response['Data'] = data
        // } catch (e) {
        //     console.error(e)
        //     response['Data'] = msg.Data
        // }

        if (tags['Status'] != "200") {
            throw new Error(`Status ${tags['Status']}\n${JSON.stringify(response, null, 2)}\nInputs: ${JSON.stringify(params, null, 2)}`)
        }

        return response
    }

    async write(params: WriteOptions): Promise<WriteResult> {
        const writeInput = {
            process: params.process,
            signer: params.signer
        }

        if (params.data) {
            writeInput['data'] = params.data
        }

        if (params.tags) {
            if (params.action) {
                params.tags['Action'] = params.action
            }
            writeInput['tags'] = Object.entries(params.tags).map(([key, value]) => ({ name: key, value: value.toString() }))
        } else {
            if (params.action) {
                writeInput['tags'] = [{ name: 'Action', value: params.action }]
            }
        }

        if (params.signer) {
            writeInput['signer'] = params.signer
        }

        if (!params.retries) params.retries = 3

        let attempts = 0

        let messageId: string | undefined = undefined

        while (attempts < params.retries) {
            try {
                messageId = await this.ao.message(writeInput)
                break
            } catch (e) {
                console.error(e)
                attempts++
                await new Promise(resolve => setTimeout(resolve, 2 ** attempts * 1000))
                console.warn(`Retrying ${attempts + 1} of ${params.retries}`)
            }
        }

        if (!messageId) {
            throw new Error(`Write Failed\nInputs: ${JSON.stringify(params, null, 2)}`)
        }



        attempts = 0
        let response: TagsKV | undefined = undefined
        let result: MessageResult | undefined = undefined

        while (attempts < params.retries) {
            try {
                result = await this.ao.result({ process: params.process, message: messageId })
                break
            } catch (e) {
                console.error(e)
                attempts++
                await new Promise(resolve => setTimeout(resolve, 2 ** attempts * 1000))
                console.warn(`Retrying ${attempts + 1} of ${params.retries}`)
            }
        }

        if (!result) {
            console.error(`Failed to read result for message ${messageId}`)
            return { id: messageId }
            // throw new Error(`Write Failed\nInputs: ${JSON.stringify(params, null, 2)}`)
        }

        if (result.Error) {
            throw new Error(`Write Error\n${JSON.stringify(result, null, 2)}\nInputs:${JSON.stringify(params, null, 2)}`)
        }

        if (!result.Messages || result.Messages.length == 0) {
            throw new Error(`Write Failed, No messages returned\nInputs: ${JSON.stringify(params, null, 2)}`)
        }

        if (result.Messages.length > 1) {
            throw new Error(`Write Failed, Multiple messages returned\n${JSON.stringify(result.Messages, null, 2)}\nInputs: ${JSON.stringify(params, null, 2)}`)
        }

        const msg = result.Messages[0]

        const tags = (msg.Tags as Tag[]).reduce((acc, tag) => {
            acc[tag.name] = tag.value
            return acc
        }, {} as Record<string, string>)

        response = tags

        // Data will always be a json string
        try {
            const data = JSON.parse(msg.Data as string)
            response['Data'] = data
        } catch (e) {
            console.error(e)
            response['Data'] = msg.Data
        }

        if (tags['Status'] != "200") {
            throw new Error(`Status ${tags['Status']}\n${JSON.stringify(response, null, 2)}\nInputs: ${JSON.stringify(params, null, 2)}`)
        }

        return {
            id: messageId,
            tags: response,
            data: response['Data']
        }
    }
}