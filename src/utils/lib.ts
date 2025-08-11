import { dryrun } from "@permaweb/aoconnect"
import { ARIO } from "@ar.io/sdk"

export type WanderTierInfo = {
    balance: string;
    progress: number;
    rank: number;
    snapshotTimestamp: number;
    tier: number;
    totalHolders: number;
}

export async function getPrimaryName(address: string): Promise<string> {
    const ario = ARIO.mainnet()
    const res = await ario.getPrimaryName({ address })
    return res.name
}

export async function getWanderTierInfo(walletAddress: string): Promise<WanderTierInfo | null> {
    try {
        const dryrunRes = await dryrun({
            Owner: walletAddress,
            process: "rkAezEIgacJZ_dVuZHOKJR8WKpSDqLGfgPJrs_Es7CA",
            tags: [{ name: "Action", value: "Get-Wallet-Info" }]
        });

        const message = dryrunRes.Messages?.[0];

        if (!message?.Data) {
            console.warn(`No message data returned for wallet: ${walletAddress}`);
            return null;
        }

        let data;
        try {
            data = JSON.parse(message.Data);
        } catch (parseError) {
            console.warn(`Failed to parse tier data for wallet: ${walletAddress}`, parseError);
            return null;
        }

        if (data?.tier === undefined || data?.tier === null) {
            console.warn(`No tier data found for wallet: ${walletAddress}`);
            return null;
        }

        const tierInfo: WanderTierInfo = { ...data };
        return tierInfo;
    } catch (error) {
        console.warn(`Failed to fetch tier info for wallet: ${walletAddress}`, error);
        return null;
    }
}