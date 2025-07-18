import { connect } from "@permaweb/aoconnect";
import { AoSigner, MessageResult, ReadOptions, Tag, TagsKV, WriteOptions, WriteResult } from "../types/ao";
import { logger } from "./logger";

export class AO {
    readonly CU_URL: string
    readonly GATEWAY_URL: string
    readonly ao: any
    private signer: AoSigner
    readonly writable: boolean
    readonly owner: string

    constructor(params: Partial<{ CU_URL: string, GATEWAY_URL: string, signer: AoSigner, Owner: string }> = {}) {
        const cuUrl = params?.CU_URL
        const gatewayUrl = params?.GATEWAY_URL

        this.ao = connect({ MODE: "legacy", CU_URL: cuUrl, GATEWAY_URL: gatewayUrl })
        this.signer = params.signer
        if (this.signer) {
            this.writable = true
        } else {
            this.writable = false
        }
        this.owner = params.Owner || "NA"
    }

    async read(params: ReadOptions): Promise<TagsKV> {
        const operationId = Math.random().toString(36).substring(2, 15);
        const startTime = Date.now();

        logger.operationStart("AO", `READ_${operationId}`, {
            process: params.process,
            action: params.action,
            owner: params.owner || this.owner,
            hasData: !!params.data,
            tagCount: params.tags ? Object.keys(params.tags).length : 0
        });

        const dryrunInput: any = {
            process: params.process
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

        dryrunInput['Owner'] = params.owner || this.owner

        if (!params.retries) params.retries = 3

        let attempts = 0;
        let response: TagsKV | undefined = undefined
        let result: MessageResult | undefined = undefined

        while (attempts < params.retries) {
            try {
                logger.requestSent("AO", `READ_${operationId}`, dryrunInput.process, {
                    attempt: attempts + 1,
                    maxRetries: params.retries,
                    action: params.action,
                    owner: dryrunInput.Owner
                });

                result = await this.ao.dryrun(dryrunInput)

                logger.responseReceived("AO", `READ_${operationId}`, dryrunInput.process, !result?.Error, {
                    attempt: attempts + 1,
                    hasError: !!result?.Error,
                    messageCount: result?.Messages?.length || 0
                });

                break
            } catch (e) {
                logger.error("AO", `READ_${operationId} attempt ${attempts + 1} failed`, e);
                attempts++
                if (attempts < params.retries) {
                    const delay = 2 ** attempts * 1000;
                    await new Promise(resolve => setTimeout(resolve, delay));
                    logger.warn('AO', `READ_${operationId} retrying in ${delay}ms (${attempts + 1}/${params.retries})`);
                }
            }
        }

        const duration = Date.now() - startTime;

        if (!result) {
            logger.operationError("AO", `READ_${operationId}`, new Error("Read Failed - No result after retries"), duration);
            throw new Error(`Read Failed\nInputs: ${JSON.stringify(params, null, 2)}`)
        }

        if (result.Error) {
            logger.operationError("AO", `READ_${operationId}`, new Error(`Read Error: ${result.Error}`), duration);
            throw new Error(`Read Error\n${JSON.stringify(result, null, 2)}\nInputs:${JSON.stringify(params, null, 2)}`)
        }

        if (!result.Messages || result.Messages.length == 0) {
            logger.operationError("AO", `READ_${operationId}`, new Error("Read Failed - No messages returned"), duration);
            throw new Error(`Read Failed, No messages returned\nInputs: ${JSON.stringify(params, null, 2)}`)
        }

        if (result.Messages.length > 1) {
            logger.operationError("AO", `READ_${operationId}`, new Error("Read Failed - Multiple messages returned"), duration);
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

        if (tags['Status'] != "200") {
            logger.operationError("AO", `READ_${operationId}`, new Error(`Status ${tags['Status']}`), duration);
            throw new Error(`Status ${tags['Status']}\n${JSON.stringify(response, null, 2)}\nInputs: ${JSON.stringify(params, null, 2)}`)
        }

        logger.operationSuccess("AO", `READ_${operationId}`, {
            status: tags['Status'],
            hasData: !!tags['Data'],
            responseTagCount: Object.keys(tags).length,
            attempts: attempts + 1
        }, duration);

        return response
    }

    async write(params: WriteOptions): Promise<WriteResult> {
        const operationId = Math.random().toString(36).substring(2, 15);
        const startTime = Date.now();

        logger.operationStart("AO", `WRITE_${operationId}`, {
            process: params.process,
            action: params.action,
            hasData: !!params.data,
            tagCount: params.tags ? Object.keys(params.tags).length : 0,
            hasSigner: !!(params.signer || this.signer)
        });

        const signer = params.signer || this.signer

        if (!signer) {
            const duration = Date.now() - startTime;
            logger.operationError("AO", `WRITE_${operationId}`, new Error("No signer provided"), duration);
            throw new Error("No signer provided. A signer is required for write operations.")
        }

        const writeInput: any = {
            process: params.process,
            signer: signer
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

        if (!params.retries) params.retries = 3

        let attempts = 0
        let messageId: string | undefined = undefined

        // Phase 1: Send message
        while (attempts < params.retries) {
            try {
                logger.requestSent("AO", `WRITE_${operationId}_MESSAGE`, writeInput.process, {
                    phase: "MESSAGE",
                    attempt: attempts + 1,
                    maxRetries: params.retries,
                    action: params.action
                });

                messageId = await this.ao.message(writeInput)

                logger.responseReceived("AO", `WRITE_${operationId}_MESSAGE`, writeInput.process, !!messageId, {
                    phase: "MESSAGE",
                    attempt: attempts + 1,
                    messageId,
                    success: !!messageId
                });

                break
            } catch (e) {
                logger.error("AO", `WRITE_${operationId} message attempt ${attempts + 1} failed`, e);
                attempts++
                if (attempts < params.retries) {
                    const delay = 2 ** attempts * 1000;
                    await new Promise(resolve => setTimeout(resolve, delay));
                    logger.warn('AO', `WRITE_${operationId} message retrying in ${delay}ms (${attempts + 1}/${params.retries})`);
                }
            }
        }

        if (!messageId) {
            const duration = Date.now() - startTime;
            logger.operationError("AO", `WRITE_${operationId}`, new Error("Write Failed - No message ID after retries"), duration);
            throw new Error(`Write Failed\nInputs: ${JSON.stringify(params, null, 2)}`)
        }

        // Phase 2: Get result
        attempts = 0
        let response: TagsKV | undefined = undefined
        let result: MessageResult | undefined = undefined

        while (attempts < params.retries) {
            try {
                logger.requestSent("AO", `WRITE_${operationId}_RESULT`, params.process, {
                    phase: "RESULT",
                    attempt: attempts + 1,
                    maxRetries: params.retries,
                    messageId
                });

                result = await this.ao.result({ process: params.process, message: messageId })

                logger.responseReceived("AO", `WRITE_${operationId}_RESULT`, params.process, !result?.Error, {
                    phase: "RESULT",
                    attempt: attempts + 1,
                    hasError: !!result?.Error,
                    messageCount: result?.Messages?.length || 0
                });

                break
            } catch (e) {
                logger.error("AO", `WRITE_${operationId} result attempt ${attempts + 1} failed`, e);
                attempts++
                if (attempts < params.retries) {
                    const delay = 2 ** attempts * 1000;
                    await new Promise(resolve => setTimeout(resolve, delay));
                    logger.warn('AO', `WRITE_${operationId} result retrying in ${delay}ms (${attempts + 1}/${params.retries})`);
                }
            }
        }

        const duration = Date.now() - startTime;

        if (!result) {
            logger.error("AO", `WRITE_${operationId} failed to read result for message ${messageId}`);
            logger.operationSuccess("AO", `WRITE_${operationId}`, {
                messageId,
                resultStatus: "PARTIAL",
                note: "Message sent but result could not be retrieved"
            }, duration);
            return { id: messageId }
        }

        if (result.Error) {
            logger.operationError("AO", `WRITE_${operationId}`, new Error(`Write Error: ${result.Error}`), duration);
            throw new Error(`Write Error\n${JSON.stringify(result, null, 2)}\nInputs:${JSON.stringify(params, null, 2)}`)
        }

        if (!result.Messages || result.Messages.length == 0) {
            logger.operationError("AO", `WRITE_${operationId}`, new Error("Write Failed - No messages returned"), duration);
            throw new Error(`Write Failed, No messages returned\nInputs: ${JSON.stringify(params, null, 2)}`)
        }

        let msg = result.Messages[0]

        if (result.Messages.length > 1) {
            logger.debug("AO", `WRITE_${operationId} multiple messages returned, finding Action-Response`, {
                messageCount: result.Messages.length
            });

            // find the message with `Action-Response` like tag
            for (const msg_ of result.Messages) {
                const tags = (msg_.Tags as Tag[]).reduce((acc, tag) => {
                    acc[tag.name] = tag.value
                    return acc
                }, {} as Record<string, string>)
                const action = tags['Action']
                if (action.endsWith("Response")) {
                    msg = msg_
                    logger.debug("AO", `WRITE_${operationId} found Action-Response message`, {
                        action
                    });
                }
            }
        }

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
            logger.error("AO", `WRITE_${operationId} failed to parse response data`, e);
            response['Data'] = msg.Data
        }

        if (tags['Status'] != "200") {
            logger.operationError("AO", `WRITE_${operationId}`, new Error(`Status ${tags['Status']}`), duration);
            throw new Error(`Status ${tags['Status']}\n${JSON.stringify(response, null, 2)}\nInputs: ${JSON.stringify(params, null, 2)}`)
        }

        logger.operationSuccess("AO", `WRITE_${operationId}`, {
            messageId,
            status: tags['Status'],
            hasData: !!response['Data'],
            responseTagCount: Object.keys(tags).length,
            resultStatus: "COMPLETE"
        }, duration);

        return {
            id: messageId,
            tags: response,
            data: response['Data']
        }
    }
}